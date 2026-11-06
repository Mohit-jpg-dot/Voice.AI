using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace VoiceAI.Windows.Services
{
    /// <summary>
    /// Manages encrypted credentials on Windows using DPAPI (Data Protection API)
    /// scoped to CurrentUser.
    /// </summary>
    public class WindowsCredentialManagerService
    {
        private readonly string _credentialsDir;

        public WindowsCredentialManagerService()
        {
            var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            _credentialsDir = Path.Combine(appData, "VoiceAI", "Credentials");
            Directory.CreateDirectory(_credentialsDir);
        }

        public void SaveCredential(string accountId, string keyName, string secretValue)
        {
            var filePath = Path.Combine(_credentialsDir, $"{accountId}_{keyName}.dat");
            var plainBytes = Encoding.UTF8.GetBytes(secretValue);
            var cipherBytes = ProtectedData.Protect(plainBytes, null, DataProtectionScope.CurrentUser);
            File.WriteAllBytes(filePath, cipherBytes);
        }

        public string? GetCredential(string accountId, string keyName)
        {
            var filePath = Path.Combine(_credentialsDir, $"{accountId}_{keyName}.dat");
            if (!File.Exists(filePath)) return null;

            try
            {
                var cipherBytes = File.ReadAllBytes(filePath);
                var plainBytes = ProtectedData.Unprotect(cipherBytes, null, DataProtectionScope.CurrentUser);
                return Encoding.UTF8.GetString(plainBytes);
            }
            catch
            {
                return null;
            }
        }

        public void DeleteCredential(string accountId, string keyName)
        {
            var filePath = Path.Combine(_credentialsDir, $"{accountId}_{keyName}.dat");
            if (File.Exists(filePath))
            {
                File.Delete(filePath);
            }
        }
    }
}
