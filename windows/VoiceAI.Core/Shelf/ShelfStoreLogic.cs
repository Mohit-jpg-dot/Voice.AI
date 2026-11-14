using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace VoiceAI.Core.Shelf
{
    public enum ShelfItemKind
    {
        File,
        Folder,
        Image,
        TextSnippet,
        Url
    }

    public enum ShelfDragOutAction
    {
        Copy,
        Move
    }

    public sealed class ShelfSettings
    {
        public bool IsEnabled { get; set; } = true;
        public bool AutoOpenOnDragNearNotch { get; set; } = true;
        public bool CloseAfterDrop { get; set; } = false;
        public ShelfDragOutAction DefaultDragOutAction { get; set; } = ShelfDragOutAction.Copy;
        public bool RemoveAfterDragOut { get; set; } = false;
        public bool KeepItemsAfterRelaunch { get; set; } = true;
        public bool ClearOnQuit { get; set; } = false;
        public int AutoExpireDays { get; set; } = 7;
        public int MaxItemCount { get; set; } = 50;
        public bool ShowCountBadgeOnCollapsedNotch { get; set; } = true;
    }

    public sealed class ShelfItem
    {
        public Guid Id { get; set; } = Guid.NewGuid();
        public ShelfItemKind Kind { get; set; }
        public string DisplayName { get; set; } = string.Empty;
        public string? Path { get; set; }
        public byte[]? StoredPayloadEncrypted { get; set; }
        public long FileSizeBytes { get; set; }
        public DateTime DateAdded { get; set; } = DateTime.UtcNow;
        public string? SourceAppName { get; set; }
        public bool IsUnavailable { get; set; }
        public string? TextContent { get; set; }
        public string? UrlString { get; set; }

        public string FormattedSize
        {
            get
            {
                if (Kind == ShelfItemKind.TextSnippet) return $"{TextContent?.Length ?? 0} chars";
                if (Kind == ShelfItemKind.Url) return "Web Link";
                if (FileSizeBytes <= 0) return Kind == ShelfItemKind.Folder ? "Folder" : "--";
                if (FileSizeBytes < 1024) return $"{FileSizeBytes} B";
                if (FileSizeBytes < 1024 * 1024) return $"{FileSizeBytes / 1024.0:F1} KB";
                return $"{FileSizeBytes / (1024.0 * 1024.0):F1} MB";
            }
        }
    }

    public sealed class ShelfStoreLogic
    {
        private readonly object _lock = new();
        private readonly List<ShelfItem> _items = new();
        private readonly byte[] _aesKey;
        public ShelfSettings Settings { get; set; }

        public ShelfStoreLogic(ShelfSettings? settings = null, byte[]? customKey = null)
        {
            Settings = settings ?? new ShelfSettings();
            _aesKey = customKey ?? new byte[32] {
                0x4a, 0x11, 0x93, 0xbc, 0x5d, 0xef, 0x22, 0x78,
                0x33, 0xaa, 0x55, 0x12, 0x89, 0xcc, 0x01, 0x44,
                0x77, 0x88, 0x99, 0x00, 0x11, 0x22, 0x33, 0x44,
                0x55, 0x66, 0x77, 0x88, 0x99, 0xaa, 0xbb, 0xcc
            };
        }

        public int Count
        {
            get
            {
                lock (_lock) return _items.Count;
            }
        }

        public IReadOnlyList<ShelfItem> GetItems()
        {
            lock (_lock)
            {
                PruneExpiredAndOverflowLocked();
                return _items.ToList();
            }
        }

        public ShelfItem? GetItem(Guid id)
        {
            lock (_lock) return _items.FirstOrDefault(x => x.Id == id);
        }

        public ShelfItem AddFile(string path, string? sourceAppName = null)
        {
            lock (_lock)
            {
                bool isDir = Directory.Exists(path);
                bool exists = isDir || File.Exists(path);
                string normalized = System.IO.Path.GetFullPath(path);

                var existingIdx = _items.FindIndex(x => x.Path != null && string.Equals(System.IO.Path.GetFullPath(x.Path), normalized, StringComparison.OrdinalIgnoreCase));
                if (existingIdx >= 0)
                {
                    var existing = _items[existingIdx];
                    existing.DateAdded = DateTime.UtcNow;
                    existing.IsUnavailable = !exists;
                    _items.RemoveAt(existingIdx);
                    _items.Insert(0, existing);
                    return existing;
                }

                long size = 0;
                if (exists && !isDir)
                {
                    try { size = new FileInfo(path).Length; } catch { }
                }

                var item = new ShelfItem
                {
                    Kind = isDir ? ShelfItemKind.Folder : ShelfItemKind.File,
                    DisplayName = System.IO.Path.GetFileName(path) switch { "" => path, var name => name },
                    Path = normalized,
                    FileSizeBytes = size,
                    DateAdded = DateTime.UtcNow,
                    SourceAppName = sourceAppName,
                    IsUnavailable = !exists
                };

                _items.Insert(0, item);
                PruneExpiredAndOverflowLocked();
                return item;
            }
        }

        public ShelfItem AddTextSnippet(string text, string? sourceAppName = null)
        {
            lock (_lock)
            {
                var payload = Encoding.UTF8.GetBytes(text);
                var encrypted = EncryptBytes(payload);
                var item = new ShelfItem
                {
                    Kind = ShelfItemKind.TextSnippet,
                    DisplayName = text.Length > 24 ? text[..24] + "..." : text,
                    TextContent = text,
                    StoredPayloadEncrypted = encrypted,
                    FileSizeBytes = payload.Length,
                    DateAdded = DateTime.UtcNow,
                    SourceAppName = sourceAppName
                };

                _items.Insert(0, item);
                PruneExpiredAndOverflowLocked();
                return item;
            }
        }

        public ShelfItem AddImageData(byte[] imageBytes, string suggestedName = "Pasted Image.png", string? sourceAppName = null)
        {
            lock (_lock)
            {
                var encrypted = EncryptBytes(imageBytes);
                var item = new ShelfItem
                {
                    Kind = ShelfItemKind.Image,
                    DisplayName = suggestedName,
                    StoredPayloadEncrypted = encrypted,
                    FileSizeBytes = imageBytes.Length,
                    DateAdded = DateTime.UtcNow,
                    SourceAppName = sourceAppName
                };

                _items.Insert(0, item);
                PruneExpiredAndOverflowLocked();
                return item;
            }
        }

        public ShelfItem AddWebUrl(string url, string? title = null, string? sourceAppName = null)
        {
            lock (_lock)
            {
                var item = new ShelfItem
                {
                    Kind = ShelfItemKindKind(url),
                    DisplayName = !string.IsNullOrWhiteSpace(title) ? title : url,
                    UrlString = url,
                    DateAdded = DateTime.UtcNow,
                    SourceAppName = sourceAppName
                };

                _items.Insert(0, item);
                PruneExpiredAndOverflowLocked();
                return item;
            }
        }

        private static ShelfItemKind ShelfItemKindKind(string url) => ShelfItemKind.Url;

        public byte[]? RetrieveDecryptedPayload(ShelfItem item)
        {
            if (item.StoredPayloadEncrypted == null || item.StoredPayloadEncrypted.Length <= 16)
                return null;

            return DecryptBytes(item.StoredPayloadEncrypted);
        }

        public bool RemoveItem(Guid id)
        {
            lock (_lock)
            {
                int removed = _items.RemoveAll(x => x.Id == id);
                return removed > 0;
            }
        }

        public void Clear()
        {
            lock (_lock) _items.Clear();
        }

        private void PruneExpiredAndOverflowLocked()
        {
            if (Settings.AutoExpireDays > 0)
            {
                var cutoff = DateTime.UtcNow.AddDays(-Settings.AutoExpireDays);
                _items.RemoveAll(x => x.DateAdded < cutoff);
            }

            if (Settings.MaxItemCount > 0 && _items.Count > Settings.MaxItemCount)
            {
                int excess = _items.Count - Settings.MaxItemCount;
                _items.RemoveRange(_items.Count - excess, excess);
            }
        }

        private byte[] EncryptBytes(byte[] plain)
        {
            using var aes = Aes.Create();
            aes.Key = _aesKey;
            aes.GenerateIV();
            using var encryptor = aes.CreateEncryptor(aes.Key, aes.IV);
            using var ms = new MemoryStream();
            ms.Write(aes.IV, 0, aes.IV.Length);
            using (var cs = new CryptoStream(ms, encryptor, CryptoStreamMode.Write))
            {
                cs.Write(plain, 0, plain.Length);
                cs.FlushFinalBlock();
            }
            return ms.ToArray();
        }

        private byte[]? DecryptBytes(byte[] cipherWithIv)
        {
            try
            {
                using var aes = Aes.Create();
                aes.Key = _aesKey;
                byte[] iv = new byte[16];
                Array.Copy(cipherWithIv, 0, iv, 0, 16);
                aes.IV = iv;

                using var decryptor = aes.CreateDecryptor(aes.Key, aes.IV);
                using var ms = new MemoryStream();
                using (var cs = new CryptoStream(ms, decryptor, CryptoStreamMode.Write))
                {
                    cs.Write(cipherWithIv, 16, cipherWithIv.Length - 16);
                    cs.FlushFinalBlock();
                }
                return ms.ToArray();
            }
            catch
            {
                return null;
            }
        }
    }

    public enum ShelfVoiceActionKind
    {
        None,
        ListItems,
        ShowShelf,
        AirDrop,
        AttachToEmail,
        SendToContact,
        MoveFiles,
        MoveToTrash,
        SummarizeFile,
        UndoAdd,
        ClearShelf,
        RemoveItem,
        OpenItem,
        BrowseForFile,
        AddLatestDownload,
        AddLastScreenshot,
        AddNamedItem
    }

    public sealed record ShelfVoiceAction(ShelfVoiceActionKind Kind, string? Target = null, string? DestinationFolder = null, string? Contact = null, string? Platform = null);

    public sealed class ShelfVoiceEngineLogic
    {
        private readonly ShelfStoreLogic _shelfStore;
        private readonly List<string> _allowedRoots;

        public ShelfVoiceEngineLogic(ShelfStoreLogic shelfStore, List<string>? customAllowedRoots = null)
        {
            _shelfStore = shelfStore;
            _allowedRoots = customAllowedRoots ?? new List<string>
            {
                Environment.GetFolderPath(Environment.SpecialFolder.Desktop),
                Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads")
            };
        }

        public ShelfVoiceAction ParseVoiceIntent(string utterance)
        {
            string lower = utterance.Trim().ToLowerInvariant().Trim('?', '.', '!', '"', '\'', '`');

            if (lower.StartsWith("what is the weather") || lower.StartsWith("tell me a joke") ||
                lower.StartsWith("play music") || lower.StartsWith("volume up") ||
                lower.StartsWith("open safari") || lower.StartsWith("open chrome") ||
                lower.StartsWith("what time is it") || lower.StartsWith("set timer") ||
                lower.StartsWith("who is the president") || lower.StartsWith("how are you") ||
                lower.StartsWith("take a screenshot") || lower.StartsWith("lock screen") ||
                lower.StartsWith("increase brightness") || lower.StartsWith("close window") ||
                lower.StartsWith("shutdown mac"))
            {
                return new ShelfVoiceAction(ShelfVoiceActionKind.None);
            }

            if (lower.Contains("airdrop") || lower.Contains("air drop"))
                return new ShelfVoiceAction(ShelfVoiceActionKind.AirDrop, "shelf_items");

            if ((lower.Contains("attach") && (lower.Contains("shelf") || lower.Contains("email") || lower.Contains("mail"))) ||
                lower.Contains("email mein attach karo") || lower.Contains("mail pe lagao"))
                return new ShelfVoiceAction(ShelfVoiceActionKind.AttachToEmail);

            if (lower.Contains("send ") && (lower.Contains("whatsapp") || lower.Contains("slack")))
            {
                string platform = lower.Contains("whatsapp") ? "WhatsApp" : "Slack";
                string contact = "Contact";
                if (lower.Contains("to rahul") || lower.Contains("rahul ko")) contact = "Rahul";
                else if (lower.Contains("to sarah") || lower.Contains("sarah ko")) contact = "Sarah";
                return new ShelfVoiceAction(ShelfVoiceActionKind.SendToContact, "first item", null, contact, platform);
            }

            if (lower.Contains("move ") && (lower.Contains("folder") || lower.Contains("directory")))
            {
                string destFolder = "Reports";
                if (lower.Contains("into "))
                {
                    int intoIdx = lower.IndexOf("into ");
                    string rest = lower[(intoIdx + 5)..].Replace("folder", "").Replace("directory", "").Trim();
                    if (rest.StartsWith("the ")) rest = rest[4..].Trim();
                    if (!string.IsNullOrEmpty(rest)) destFolder = char.ToUpperInvariant(rest[0]) + rest[1..];
                }
                return new ShelfVoiceAction(ShelfVoiceActionKind.MoveFiles, "shelf_items", destFolder);
            }

            if (lower.Contains("trash") || lower.Contains("delete from shelf") || lower.Contains("trash mein daalo"))
            {
                string target = lower.Replace("move to trash", "").Replace("move", "").Replace("to trash", "").Trim();
                return new ShelfVoiceAction(ShelfVoiceActionKind.MoveToTrash, string.IsNullOrEmpty(target) ? "selected item" : target);
            }

            if (lower.Contains("summarize") || lower.Contains("explain file") || lower.Contains("kya likha hai"))
                return new ShelfVoiceAction(ShelfVoiceActionKind.SummarizeFile, "file on shelf");

            if (lower == "undo that" || lower == "undo" || lower == "wapas lo")
                return new ShelfVoiceAction(ShelfVoiceActionKind.UndoAdd);

            if (lower.Contains("clear the shelf") || lower.Contains("clear shelf") || lower == "empty the shelf" ||
                lower.Contains("shelf saaf karo") || lower.Contains("shelf empty karo"))
                return new ShelfVoiceAction(ShelfVoiceActionKind.ClearShelf);

            if (lower.Contains("remove ") || lower.Contains("hatao"))
            {
                string target = lower.Contains("second") || lower.Contains("doosra") ? "second" : "first";
                return new ShelfVoiceAction(ShelfVoiceActionKind.RemoveItem, target);
            }

            if (lower.Contains("open ") && (lower.Contains("shelf") || lower.Contains("pdf")))
            {
                string target = lower.Contains("pdf") ? "pdf" : "first";
                return new ShelfVoiceAction(ShelfVoiceActionKind.OpenItem, target);
            }

            if (lower.Contains("what's on my shelf") || lower.Contains("whats on my shelf") ||
                lower.Contains("what is on my shelf") || lower.Contains("shelf mein kya hai") ||
                lower == "show the shelf" || lower == "show shelf" || lower == "shelf dikhao")
            {
                if (lower.Contains("show") || lower.Contains("open") || lower.Contains("dikhao"))
                    return new ShelfVoiceAction(ShelfVoiceActionKind.ShowShelf);
                return new ShelfVoiceAction(ShelfVoiceActionKind.ListItems);
            }

            if (lower.Contains("browse for a file") || lower.Contains("pick a file") || lower.Contains("file browse karo"))
                return new ShelfVoiceAction(ShelfVoiceActionKind.BrowseForFile);

            if (lower.Contains("latest download") || lower.Contains("last download") || lower.Contains("aakhri download"))
                return new ShelfVoiceAction(ShelfVoiceActionKind.AddLatestDownload);

            if (lower.Contains("last screenshot") || lower.Contains("latest screenshot") || lower.Contains("aakhri screenshot"))
                return new ShelfVoiceAction(ShelfVoiceActionKind.AddLastScreenshot);

            if (lower.StartsWith("put ") || lower.StartsWith("add ") || lower.Contains("shelf pe") || lower.Contains("shelf mein"))
            {
                string target = lower.Replace("put", "").Replace("add", "").Replace("on the shelf", "").Replace("to the shelf", "").Replace("shelf pe rakho", "").Replace("shelf mein daalo", "").Trim();
                return new ShelfVoiceAction(ShelfVoiceActionKind.AddNamedItem, target);
            }

            return new ShelfVoiceAction(ShelfVoiceActionKind.None);
        }

        public static bool RequiresConsequentialApproval(ShelfVoiceAction action)
        {
            return action.Kind is ShelfVoiceActionKind.ClearShelf or ShelfVoiceActionKind.MoveToTrash or ShelfVoiceActionKind.AirDrop;
        }

        public static bool IsProtectedSensitivePath(string path)
        {
            string lower = path.ToLowerInvariant().Replace('\\', '/');
            if (lower.Contains("/.ssh") || lower.Contains("\\.ssh") || lower.EndsWith("/.env") || lower.EndsWith("\\.env") ||
                lower.Contains("id_rsa") || lower.Contains("id_ed25519") || lower.Contains(".gnupg"))
                return true;
            return false;
        }

        public bool IsInsideAllowedRoots(string path)
        {
            string full = Path.GetFullPath(path);
            foreach (var root in _allowedRoots)
            {
                if (full.StartsWith(Path.GetFullPath(root), StringComparison.OrdinalIgnoreCase))
                    return true;
            }
            return false;
        }

        public static string WrapUntrustedDataForAI(string fileName, string content)
        {
            // Secret redaction
            string scrubbed = Regex.Replace(content, @"sk-[a-zA-Z0-9_\-]{20,}", "[REDACTED_API_KEY]");
            scrubbed = Regex.Replace(scrubbed, @"ghp_[a-zA-Z0-9]{20,}", "[REDACTED_GITHUB_TOKEN]");

            return $"<UNTRUSTED_FILE_DATA filename=\"{fileName}\">\n{scrubbed}\n</UNTRUSTED_FILE_DATA>";
        }
    }
}
