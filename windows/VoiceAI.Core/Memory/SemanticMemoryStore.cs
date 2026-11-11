using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using VoiceAI.Core.Events;
using VoiceAI.Core.Security;

namespace VoiceAI.Core.Memory
{
    public enum MemoryScope
    {
        ShortTerm,
        LongTerm,
        UserProfile
    }

    public enum MemoryFactKind
    {
        Turn,
        Fact,
        Preference,
        Project,
        Person,
        Profile
    }

    public sealed record StructuredMemoryItem(
        string Id,
        string AccountId,
        MemoryScope Scope,
        MemoryFactKind Kind,
        string Content,
        IReadOnlyList<string> Tags,
        float[] Embedding,
        DateTime CreatedAtUtc);

    public sealed record UserMemoryProfile(
        string AccountId,
        string DisplayName,
        string PreferredLanguage,
        string Persona,
        Dictionary<string, string> CustomTraits);

    public interface ILocalEmbeddingProvider
    {
        float[] Embed(string text);
        double CosineSimilarity(float[] a, float[] b);
    }

    public sealed class LocalHashEmbeddingProvider : ILocalEmbeddingProvider
    {
        public static LocalHashEmbeddingProvider Shared { get; } = new LocalHashEmbeddingProvider();
        private const int Dimensions = 128;

        public float[] Embed(string text)
        {
            var vec = new float[Dimensions];
            if (string.IsNullOrWhiteSpace(text)) return vec;

            var tokens = text.ToLowerInvariant()
                .Split(new[] { ' ', '\t', '\r', '\n', ',', '.', '!', '?', ':', ';', '-', '_', '/', '(', ')' },
                    StringSplitOptions.RemoveEmptyEntries);

            foreach (var token in tokens)
            {
                ulong h = StableFnv1a(token);
                int idx = (int)(h % Dimensions);
                float sign = ((h >> 8) & 1) == 0 ? 1f : -1f;
                vec[idx] += sign * 2f;

                if (token.Length >= 3)
                {
                    for (int i = 0; i <= token.Length - 3; i++)
                    {
                        ulong th = StableFnv1a("tri:" + token.Substring(i, 3));
                        int tIdx = (int)(th % Dimensions);
                        float tSign = ((th >> 8) & 1) == 0 ? 1f : -1f;
                        vec[tIdx] += tSign * 0.75f;
                    }
                }
            }

            float normSq = 0f;
            for (int i = 0; i < Dimensions; i++) normSq += vec[i] * vec[i];
            float norm = (float)System.Math.Sqrt(normSq);
            if (norm > 0f)
            {
                for (int i = 0; i < Dimensions; i++) vec[i] /= norm;
            }
            return vec;
        }

        public double CosineSimilarity(float[] a, float[] b)
        {
            int len = System.Math.Min(a.Length, b.Length);
            if (len == 0) return 0;
            double dot = 0, na = 0, nb = 0;
            for (int i = 0; i < len; i++)
            {
                dot += a[i] * b[i];
                na += a[i] * a[i];
                nb += b[i] * b[i];
            }
            double denom = System.Math.Sqrt(na) * System.Math.Sqrt(nb);
            return denom > 0 ? dot / denom : 0;
        }

        private static ulong StableFnv1a(string text)
        {
            ulong hash = 14695981039346656037UL;
            foreach (byte b in Encoding.UTF8.GetBytes(text))
            {
                hash ^= b;
                hash *= 1099511628211UL;
            }
            return hash;
        }
    }

    public interface IMemoryStore
    {
        void LoadAccount(string accountId);
        StructuredMemoryItem Remember(string content, MemoryScope scope = MemoryScope.LongTerm, MemoryFactKind kind = MemoryFactKind.Fact, IReadOnlyList<string>? tags = null);
        bool Forget(string id);
        int ForgetMatching(string query);
        IReadOnlyList<(StructuredMemoryItem Item, double Score)> SearchSemantic(string query, MemoryScope? scope = null, int limit = 5);
        UserMemoryProfile GetProfile();
        void UpdateProfile(string? displayName = null, string? preferredLanguage = null, string? persona = null);
    }

    /// <summary>
    /// Per-account encrypted semantic MemoryStore for Windows VoiceAI.Core.
    /// </summary>
    public sealed class SemanticMemoryStore : IMemoryStore
    {
        public static SemanticMemoryStore Shared { get; } = new SemanticMemoryStore();

        private sealed record EncryptedPayload(List<StructuredMemoryItem> Items, UserMemoryProfile Profile);

        private readonly object _lock = new();
        private readonly string _baseDir;
        private readonly ILocalEmbeddingProvider _embedder;
        private readonly byte[] _salt = Encoding.UTF8.GetBytes("VoiceAI-Windows-Memory-Salt-v1");

        private string _activeAccount = "local_default";
        private List<StructuredMemoryItem> _items = new();
        private UserMemoryProfile _profile = new("local_default", "User", "en", "Friday", new());

        public SemanticMemoryStore(ILocalEmbeddingProvider? embedder = null)
        {
            _embedder = embedder ?? LocalHashEmbeddingProvider.Shared;
            string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            if (string.IsNullOrEmpty(localAppData))
            {
                localAppData = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".voice_ai");
            }
            _baseDir = Path.Combine(localAppData, "VoiceAI", "memory");
            Directory.CreateDirectory(_baseDir);
            LoadAccount(_activeAccount);
        }

        public void LoadAccount(string accountId)
        {
            lock (_lock)
            {
                _activeAccount = string.IsNullOrWhiteSpace(accountId) ? "local_default" : accountId;
                _items = new();
                _profile = new(_activeAccount, "User", "en", "Friday", new());

                string file = StorageFileFor(_activeAccount);
                if (!File.Exists(file)) return;

                try
                {
                    byte[] cipher = File.ReadAllBytes(file);
                    string json = Decrypt(cipher, _activeAccount);
                    var payload = JsonSerializer.Deserialize<EncryptedPayload>(json);
                    if (payload != null)
                    {
                        _items = payload.Items ?? new();
                        _profile = payload.Profile ?? _profile;
                    }
                }
                catch
                {
                    // Tampered or account key mismatch
                    _items = new();
                }
            }
        }

        public StructuredMemoryItem Remember(
            string content,
            MemoryScope scope = MemoryScope.LongTerm,
            MemoryFactKind kind = MemoryFactKind.Fact,
            IReadOnlyList<string>? tags = null)
        {
            string safe = SecretRedactor.Redact(content).Trim();
            float[] vec = _embedder.Embed(safe);

            StructuredMemoryItem entry;
            lock (_lock)
            {
                entry = new StructuredMemoryItem(
                    Guid.NewGuid().ToString(),
                    _activeAccount,
                    scope,
                    kind,
                    safe,
                    tags ?? Array.Empty<string>(),
                    vec,
                    DateTime.UtcNow);
                _items.Insert(0, entry);
                PersistLocked();
            }

            EventBus.Shared.Publish(VoiceEvent.Create(
                SystemEventKind.MemoryUpdated,
                "SemanticMemoryStore",
                new Dictionary<string, string> { ["action"] = "remember", ["scope"] = scope.ToString() }));
            return entry;
        }

        public bool Forget(string id)
        {
            bool removed;
            lock (_lock)
            {
                int before = _items.Count;
                _items.RemoveAll(i => i.Id == id);
                removed = _items.Count < before;
                if (removed) PersistLocked();
            }
            return removed;
        }

        public int ForgetMatching(string query)
        {
            string q = query.Trim().ToLowerInvariant();
            if (string.IsNullOrEmpty(q)) return 0;
            int removed;
            lock (_lock)
            {
                int before = _items.Count;
                _items.RemoveAll(i => i.Content.ToLowerInvariant().Contains(q));
                removed = before - _items.Count;
                if (removed > 0) PersistLocked();
            }
            return removed;
        }

        public IReadOnlyList<(StructuredMemoryItem Item, double Score)> SearchSemantic(
            string query,
            MemoryScope? scope = null,
            int limit = 5)
        {
            if (string.IsNullOrWhiteSpace(query) || limit <= 0) return Array.Empty<(StructuredMemoryItem, double)>();
            float[] qVec = _embedder.Embed(query);
            string qLower = query.Trim().ToLowerInvariant();

            List<StructuredMemoryItem> snapshot;
            lock (_lock)
            {
                snapshot = _items.Where(i => scope == null || i.Scope == scope).ToList();
            }

            return snapshot
                .Select(item =>
                {
                    double sim = _embedder.CosineSimilarity(qVec, item.Embedding);
                    double lexical = item.Content.ToLowerInvariant().Contains(qLower) ? 0.35 : 0.0;
                    return (Item: item, Score: sim + lexical);
                })
                .Where(pair => pair.Score > 0.12)
                .OrderByDescending(pair => pair.Score)
                .Take(limit)
                .ToList();
        }

        public UserMemoryProfile GetProfile()
        {
            lock (_lock) return _profile;
        }

        public void UpdateProfile(string? displayName = null, string? preferredLanguage = null, string? persona = null)
        {
            lock (_lock)
            {
                _profile = _profile with
                {
                    DisplayName = displayName ?? _profile.DisplayName,
                    PreferredLanguage = preferredLanguage ?? _profile.PreferredLanguage,
                    Persona = persona ?? _profile.Persona
                };
                PersistLocked();
            }
        }

        public void ClearAccount(string accountId)
        {
            lock (_lock)
            {
                string file = StorageFileFor(accountId);
                if (File.Exists(file)) File.Delete(file);
                if (accountId == _activeAccount) _items.Clear();
            }
        }

        private string StorageFileFor(string accountId)
        {
            byte[] hash = SHA256.HashData(Encoding.UTF8.GetBytes(accountId));
            string hex = Convert.ToHexString(hash).ToLowerInvariant();
            return Path.Combine(_baseDir, $"memory_{hex}.enc");
        }

        private void PersistLocked()
        {
            string json = JsonSerializer.Serialize(new EncryptedPayload(_items, _profile));
            byte[] cipher = Encrypt(json, _activeAccount);
            File.WriteAllBytes(StorageFileFor(_activeAccount), cipher);
        }

        private byte[] Encrypt(string plainText, string accountId)
        {
            using var aes = Aes.Create();
            aes.KeySize = 256;
            aes.Key = Rfc2898DeriveBytes.Pbkdf2(accountId, _salt, 10000, HashAlgorithmName.SHA256, 32);
            aes.GenerateIV();
            using var ms = new MemoryStream();
            ms.Write(aes.IV, 0, aes.IV.Length);
            using (var cs = new CryptoStream(ms, aes.CreateEncryptor(), CryptoStreamMode.Write))
            using (var sw = new StreamWriter(cs))
            {
                sw.Write(plainText);
            }
            return ms.ToArray();
        }

        private string Decrypt(byte[] cipherText, string accountId)
        {
            using var aes = Aes.Create();
            aes.KeySize = 256;
            aes.Key = Rfc2898DeriveBytes.Pbkdf2(accountId, _salt, 10000, HashAlgorithmName.SHA256, 32);
            byte[] iv = new byte[16];
            Array.Copy(cipherText, 0, iv, 0, 16);
            aes.IV = iv;
            using var ms = new MemoryStream(cipherText, 16, cipherText.Length - 16);
            using var cs = new CryptoStream(ms, aes.CreateDecryptor(), CryptoStreamMode.Read);
            using var sr = new StreamReader(cs);
            return sr.ReadToEnd();
        }
    }
}

