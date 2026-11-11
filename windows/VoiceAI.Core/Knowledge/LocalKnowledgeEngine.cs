using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using VoiceAI.Core.Security;

namespace VoiceAI.Core.Knowledge
{
    public sealed record KnowledgeChunk(
        string Id,
        string FolderPath,
        string FilePath,
        string FileName,
        string Snippet,
        float[] Embedding);

    public sealed record KnowledgeHit(KnowledgeChunk Chunk, double Score);

    public interface ILocalKnowledgeEngine
    {
        void AddFolder(string folderPath);
        int IndexFolder(string folderPath);
        IReadOnlyList<KnowledgeHit> Search(string query, int limit = 5);
    }

    /// <summary>
    /// On-device local file & knowledge search (RAG) for user-chosen folders on Windows.
    /// Computes deterministic local normalized token vectors and scrubs secrets before indexing.
    /// </summary>
    public sealed class LocalKnowledgeEngine : ILocalKnowledgeEngine
    {
        public static LocalKnowledgeEngine Shared { get; } = new LocalKnowledgeEngine();

        private static readonly HashSet<string> SupportedExt = new(StringComparer.OrdinalIgnoreCase)
        {
            ".md", ".txt", ".cs", ".swift", ".py", ".js", ".ts", ".json", ".csv", ".yaml", ".yml", ".log"
        };

        private readonly object _lock = new();
        private readonly List<string> _folders = new();
        private readonly List<KnowledgeChunk> _chunks = new();

        public void AddFolder(string folderPath)
        {
            string full = Path.GetFullPath(folderPath);
            lock (_lock)
            {
                if (!_folders.Contains(full, StringComparer.OrdinalIgnoreCase))
                    _folders.Add(full);
            }
        }

        public int IndexFolder(string folderPath)
        {
            string full = Path.GetFullPath(folderPath);
            AddFolder(full);
            if (!Directory.Exists(full)) return 0;

            var newChunks = new List<KnowledgeChunk>();
            foreach (var file in Directory.EnumerateFiles(full, "*.*", SearchOption.AllDirectories).Take(300))
            {
                if (!SupportedExt.Contains(Path.GetExtension(file))) continue;
                var info = new FileInfo(file);
                if (info.Length > 512_000) continue;

                string raw = File.ReadAllText(file);
                string safe = SecretRedactor.Redact(raw);
                foreach (var snippet in ChunkText(safe, 500))
                {
                    newChunks.Add(new KnowledgeChunk(
                        Guid.NewGuid().ToString(),
                        full,
                        file,
                        Path.GetFileName(file),
                        snippet,
                        Embed($"{Path.GetFileName(file)} {snippet}")));
                }
            }

            lock (_lock)
            {
                _chunks.RemoveAll(c => string.Equals(c.FolderPath, full, StringComparison.OrdinalIgnoreCase));
                _chunks.AddRange(newChunks);
            }
            return newChunks.Count;
        }

        public IReadOnlyList<KnowledgeHit> Search(string query, int limit = 5)
        {
            if (string.IsNullOrWhiteSpace(query) || limit <= 0) return Array.Empty<KnowledgeHit>();
            var qVec = Embed(query);
            string qLower = query.Trim().ToLowerInvariant();
            var tokens = qLower.Split(new[] { ' ', ',', '.', ':', ';', '/', '\\', '-' }, StringSplitOptions.RemoveEmptyEntries)
                .Where(t => t.Length >= 2)
                .ToArray();

            List<KnowledgeChunk> snap;
            lock (_lock) snap = _chunks.ToList();

            var hits = new List<KnowledgeHit>();
            foreach (var c in snap)
            {
                double cosine = Cosine(qVec, c.Embedding);
                string hay = $"{c.FileName.ToLowerInvariant()} {c.Snippet.ToLowerInvariant()}";
                double boost = hay.Contains(qLower)
                    ? 0.45
                    : (tokens.Length == 0 ? 0.0 : 0.30 * ((double)tokens.Count(hay.Contains) / tokens.Length));
                double score = cosine + boost;
                if (score > 0.14) hits.Add(new KnowledgeHit(c, score));
            }
            return hits.OrderByDescending(h => h.Score).Take(limit).ToList();
        }

        public static IEnumerable<string> ChunkText(string text, int maxChars = 500)
        {
            if (string.IsNullOrWhiteSpace(text)) yield break;
            for (int i = 0; i < text.Length; i += System.Math.Max(1, maxChars - 60))
            {
                int len = System.Math.Min(maxChars, text.Length - i);
                string piece = text.Substring(i, len).Trim();
                if (!string.IsNullOrEmpty(piece)) yield return piece;
                if (i + len >= text.Length) break;
            }
        }

        private static float[] Embed(string text)
        {
            const int dim = 128;
            var v = new float[dim];
            var words = text.ToLowerInvariant().Split(new[] { ' ', '\n', '\r', '\t', '.', ',', ':', ';' }, StringSplitOptions.RemoveEmptyEntries);
            foreach (var w in words)
            {
                uint h = 2166136261;
                foreach (char ch in w)
                {
                    h ^= ch;
                    h *= 16777619;
                }
                v[h % dim] += 1.0f;
            }
            double mag = System.Math.Sqrt(v.Sum(x => x * x));
            if (mag > 0) for (int i = 0; i < dim; i++) v[i] = (float)(v[i] / mag);
            return v;
        }

        private static double Cosine(float[] a, float[] b)
        {
            double dot = 0;
            for (int i = 0; i < System.Math.Min(a.Length, b.Length); i++) dot += a[i] * b[i];
            return dot;
        }
    }
}

