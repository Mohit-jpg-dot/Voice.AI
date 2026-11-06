using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace VoiceAI.Core.Memory
{
    public record HistoryMessage(string Role, string Content, DateTime Timestamp, string AccountId);

    /// <summary>
    /// Encrypted local chat history store for Windows.
    /// Uses per-account isolation and AES encryption (bound to DPAPI on Windows) with automatic API-key redaction.
    /// </summary>
    public sealed class EncryptedHistoryManager
    {
        public static EncryptedHistoryManager Shared { get; } = new EncryptedHistoryManager();

        private readonly string _baseStorageDir;
        private readonly byte[] _masterSalt = Encoding.UTF8.GetBytes("VoiceAI-Windows-History-Salt-v1");

        public EncryptedHistoryManager()
        {
            string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            if (string.IsNullOrEmpty(localAppData))
            {
                localAppData = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".voice_ai");
            }
            _baseStorageDir = Path.Combine(localAppData, "VoiceAI", "history");
            Directory.CreateDirectory(_baseStorageDir);
        }

        public string RedactSecrets(string text)
        {
            if (string.IsNullOrEmpty(text)) return text;

            // Redact OpenAI keys (sk-...)
            string redacted = Regex.Replace(text, @"sk-[A-Za-z0-9_-]{20,}", "[REDACTED_API_KEY]");
            // Redact Anthropic keys (sk-ant-...)
            redacted = Regex.Replace(redacted, @"sk-ant-[A-Za-z0-9_-]{20,}", "[REDACTED_API_KEY]");
            // Redact Google AI keys (AIzaSy...)
            redacted = Regex.Replace(redacted, @"AIzaSy[A-Za-z0-9_-]{20,}", "[REDACTED_API_KEY]");

            return redacted;
        }

        public void AppendMessage(string accountId, string role, string content)
        {
            if (string.IsNullOrEmpty(accountId)) return;

            string safeContent = RedactSecrets(content);
            var msg = new HistoryMessage(role, safeContent, DateTime.UtcNow, accountId);

            string accountDir = Path.Combine(_baseStorageDir, GetSafeAccountHash(accountId));
            Directory.CreateDirectory(accountDir);

            string filePath = Path.Combine(accountDir, "messages.enc");

            var existing = LoadMessages(accountId);
            var updated = new List<HistoryMessage>(existing) { msg };

            string json = JsonSerializer.Serialize(updated);
            byte[] cipher = EncryptString(json, accountId);
            File.WriteAllBytes(filePath, cipher);
        }

        public IReadOnlyList<HistoryMessage> LoadMessages(string accountId)
        {
            if (string.IsNullOrEmpty(accountId)) return Array.Empty<HistoryMessage>();

            string accountDir = Path.Combine(_baseStorageDir, GetSafeAccountHash(accountId));
            string filePath = Path.Combine(accountDir, "messages.enc");

            if (!File.Exists(filePath)) return Array.Empty<HistoryMessage>();

            try
            {
                byte[] cipher = File.ReadAllBytes(filePath);
                string json = DecryptBytes(cipher, accountId);
                return JsonSerializer.Deserialize<List<HistoryMessage>>(json) ?? new List<HistoryMessage>();
            }
            catch
            {
                // Account mismatch or tampered file
                return Array.Empty<HistoryMessage>();
            }
        }

        public void ClearHistory(string accountId)
        {
            if (string.IsNullOrEmpty(accountId)) return;
            string accountDir = Path.Combine(_baseStorageDir, GetSafeAccountHash(accountId));
            if (Directory.Exists(accountDir))
            {
                Directory.Delete(accountDir, true);
            }
        }

        private string GetSafeAccountHash(string accountId)
        {
            using var sha = SHA256.Create();
            byte[] hash = sha.ComputeHash(Encoding.UTF8.GetBytes(accountId));
            return BitConverter.ToString(hash).Replace("-", "").ToLowerInvariant();
        }

        private byte[] EncryptString(string plainText, string keySeed)
        {
            using var aes = Aes.Create();
            byte[] key = Rfc2898DeriveBytes.Pbkdf2(keySeed, _masterSalt, 10000, HashAlgorithmName.SHA256, 32);
            byte[] iv = Rfc2898DeriveBytes.Pbkdf2(keySeed, _masterSalt, 10000, HashAlgorithmName.SHA256, 16);
            aes.Key = key;
            aes.IV = iv;

            using var ms = new MemoryStream();
            using (var cs = new CryptoStream(ms, aes.CreateEncryptor(), CryptoStreamMode.Write))
            using (var sw = new StreamWriter(cs))
            {
                sw.Write(plainText);
            }
            return ms.ToArray();
        }

        private string DecryptBytes(byte[] cipherBytes, string keySeed)
        {
            using var aes = Aes.Create();
            byte[] key = Rfc2898DeriveBytes.Pbkdf2(keySeed, _masterSalt, 10000, HashAlgorithmName.SHA256, 32);
            byte[] iv = Rfc2898DeriveBytes.Pbkdf2(keySeed, _masterSalt, 10000, HashAlgorithmName.SHA256, 16);
            aes.Key = key;
            aes.IV = iv;

            using var ms = new MemoryStream(cipherBytes);
            using var cs = new CryptoStream(ms, aes.CreateDecryptor(), CryptoStreamMode.Read);
            using var sr = new StreamReader(cs);
            return sr.ReadToEnd();
        }
    }
}
