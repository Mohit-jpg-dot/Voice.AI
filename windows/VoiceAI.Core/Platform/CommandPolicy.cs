using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;

namespace VoiceAI.Core.Platform
{
    public enum CommandClassification
    {
        ReadOnly = 0,
        NeedsApproval = 1,
        Blocked = 2
    }

    public sealed record CommandSegment(
        string Program,
        IReadOnlyList<string> Args,
        CommandClassification Classification,
        string? Reason);

    public sealed record CommandPolicyDecision(
        CommandClassification Classification,
        IReadOnlyList<CommandSegment> Segments,
        string ResolvedWorkingDirectory,
        string CommandHash,
        string Reason,
        IReadOnlyList<string> TouchedPaths)
    {
        public bool IsAllowedToPromptOrRun => Classification != CommandClassification.Blocked;
    }

    public static class ShellTokenizer
    {
        public static bool TryTokenize(string raw, out List<string> tokens, out string? error)
        {
            tokens = new List<string>();
            error = null;
            if (string.IsNullOrWhiteSpace(raw))
            {
                error = "Empty command.";
                return false;
            }

            int i = 0;
            while (i < raw.Length)
            {
                while (i < raw.Length && char.IsWhiteSpace(raw[i])) i++;
                if (i >= raw.Length) break;

                char c = raw[i];
                if (c == '`')
                {
                    error = "Backtick command substitution is not allowed.";
                    return false;
                }
                if (c == '(' || c == ')')
                {
                    error = "Subshell grouping is not allowed.";
                    return false;
                }
                if (c == '|' && i + 1 < raw.Length && raw[i + 1] == '|')
                {
                    tokens.Add("||");
                    i += 2;
                    continue;
                }
                if (c == '|')
                {
                    tokens.Add("|");
                    i += 1;
                    continue;
                }
                if (c == '&' && i + 1 < raw.Length && raw[i + 1] == '&')
                {
                    tokens.Add("&&");
                    i += 2;
                    continue;
                }
                if (c == '&' && i + 1 < raw.Length && raw[i + 1] == '>')
                {
                    tokens.Add("&>");
                    i += 2;
                    continue;
                }
                if (c == '&')
                {
                    error = "Background '&' execution is not allowed.";
                    return false;
                }
                if (c == ';')
                {
                    tokens.Add(";");
                    i += 1;
                    continue;
                }
                if (c == '>' && i + 1 < raw.Length && raw[i + 1] == '>')
                {
                    tokens.Add(">>");
                    i += 2;
                    continue;
                }
                if (c == '>')
                {
                    tokens.Add(">");
                    i += 1;
                    continue;
                }
                if (c == '<' && i + 1 < raw.Length && raw[i + 1] == '<')
                {
                    error = "Here-doc '<<' is not allowed.";
                    return false;
                }
                if (c == '<')
                {
                    tokens.Add("<");
                    i += 1;
                    continue;
                }

                var sb = new StringBuilder();
                bool inSingle = false;
                bool inDouble = false;

                while (i < raw.Length)
                {
                    char ch = raw[i];
                    if (inSingle)
                    {
                        if (ch == '\'') { inSingle = false; i++; }
                        else { sb.Append(ch); i++; }
                        continue;
                    }
                    if (inDouble)
                    {
                        if (ch == '"') { inDouble = false; i++; }
                        else if (ch == '\\' && i + 1 < raw.Length) { sb.Append(raw[i + 1]); i += 2; }
                        else if (ch == '`' || ch == '$')
                        {
                            error = "Variable or command substitution inside quotes is not allowed.";
                            return false;
                        }
                        else { sb.Append(ch); i++; }
                        continue;
                    }

                    if (char.IsWhiteSpace(ch) || ch == '|' || ch == '&' || ch == ';' || ch == '<' || ch == '>' || ch == '(' || ch == ')')
                        break;
                    if (ch == '`' || ch == '$')
                    {
                        error = "Variable or command substitution is not allowed.";
                        return false;
                    }
                    if (ch == '\'') { inSingle = true; i++; continue; }
                    if (ch == '"') { inDouble = true; i++; continue; }
                    if (ch == '\\')
                    {
                        if (i + 1 >= raw.Length) { error = "Trailing escape."; return false; }
                        sb.Append(raw[i + 1]);
                        i += 2;
                        continue;
                    }
                    sb.Append(ch);
                    i++;
                }

                if (inSingle || inDouble)
                {
                    error = "Unterminated quote.";
                    return false;
                }
                tokens.Add(sb.ToString());
            }

            if (tokens.Count == 0)
            {
                error = "Empty command.";
                return false;
            }
            return true;
        }
    }

    public sealed class CommandPolicy
    {
        private static readonly HashSet<string> ReadOnlyPrograms = new(StringComparer.OrdinalIgnoreCase)
        {
            "dir", "ls", "Get-ChildItem", "cat", "type", "Get-Content", "head", "tail", "wc",
            "find", "findstr", "Select-String", "grep", "stat", "du", "df", "pwd", "Get-Location",
            "where", "which", "date", "Get-Date", "sort", "diff", "fc"
        };

        private static readonly HashSet<string> MutatingAllowedPrograms = new(StringComparer.OrdinalIgnoreCase)
        {
            "copy", "cp", "Copy-Item", "move", "mv", "Move-Item", "mkdir", "md", "New-Item",
            "ren", "rename", "Rename-Item", "touch", "tar", "Compress-Archive", "Expand-Archive", "start"
        };

        private static readonly HashSet<string> AlwaysBlockedPrograms = new(StringComparer.OrdinalIgnoreCase)
        {
            "sudo", "runas", "rm", "del", "erase", "rmdir", "rd", "Remove-Item", "format", "diskpart",
            "bcdedit", "reg", "regedit", "shutdown", "restart-computer", "stop-computer",
            "sc", "schtasks", "net", "netsh", "powershell", "pwsh", "cmd", "wscript", "cscript",
            "python", "python3", "node", "ruby", "perl", "bash", "sh", "zsh",
            "curl", "wget", "Invoke-WebRequest", "iwr", "Invoke-Expression", "iex",
            "ssh", "scp", "sftp", "nc", "ncat", "telnet", "taskkill", "Stop-Process",
            "icacls", "takeown", "attrib", "cipher", "mklink", "winget", "choco", "npm", "pip"
        };

        private readonly IReadOnlyList<string> _allowedRoots;
        private readonly string _homeDirectory;

        public CommandPolicy(IEnumerable<string>? allowedRoots = null, string? homeDirectory = null)
        {
            _homeDirectory = string.IsNullOrWhiteSpace(homeDirectory)
                ? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
                : Path.GetFullPath(homeDirectory);
            _allowedRoots = (allowedRoots ?? new[]
            {
                Path.Combine(_homeDirectory, "Desktop"),
                Path.Combine(_homeDirectory, "Documents"),
                Path.Combine(_homeDirectory, "Downloads"),
                Path.Combine(_homeDirectory, "VoiceAI-Workspace")
            }).Select(Path.GetFullPath).ToList();
        }

        public static string BindingHash(string command, string workingDirectory)
        {
            byte[] bytes = SHA256.HashData(Encoding.UTF8.GetBytes($"{workingDirectory}\n{command}"));
            return Convert.ToHexString(bytes).ToLowerInvariant();
        }

        public bool IsInsideAllowedRoots(string fullPath)
        {
            string normalized = Path.GetFullPath(fullPath);
            foreach (var root in _allowedRoots)
            {
                string r = Path.GetFullPath(root);
                if (string.Equals(normalized, r, StringComparison.OrdinalIgnoreCase)) return true;
                string prefix = r.EndsWith(Path.DirectorySeparatorChar) ? r : r + Path.DirectorySeparatorChar;
                if (normalized.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) return true;
            }
            return false;
        }

        public static bool IsProtectedPath(string fullPath)
        {
            string lower = fullPath.ToLowerInvariant().Replace('\\', '/');
            string name = Path.GetFileName(lower);
            if (name.StartsWith(".") && name != "." && name != "..") return true;
            if (lower.Contains("/.ssh") || lower.Contains("/.aws") || lower.Contains("/.gnupg") ||
                lower.Contains("/windows/system32") || lower.Contains("/program files") ||
                lower.Contains("/appdata/local/google/chrome") || name.EndsWith(".pem") || name.EndsWith(".key"))
            {
                return true;
            }
            return false;
        }

        public CommandPolicyDecision Evaluate(string rawCommand, string? workingDirectory = null)
        {
            string trimmed = (rawCommand ?? string.Empty).Trim();
            string defaultRoot = _allowedRoots.FirstOrDefault() ?? _homeDirectory;
            string resolvedWD = string.IsNullOrWhiteSpace(workingDirectory) ? defaultRoot : Path.GetFullPath(workingDirectory);
            string hash = BindingHash(trimmed, resolvedWD);

            if (!IsInsideAllowedRoots(resolvedWD) || IsProtectedPath(resolvedWD))
            {
                return new CommandPolicyDecision(CommandClassification.Blocked, Array.Empty<CommandSegment>(), resolvedWD, hash,
                    $"Working directory '{resolvedWD}' is outside allowed roots.", new[] { resolvedWD });
            }

            if (!ShellTokenizer.TryTokenize(trimmed, out var tokens, out var parseErr))
            {
                return new CommandPolicyDecision(CommandClassification.Blocked, Array.Empty<CommandSegment>(), resolvedWD, hash,
                    parseErr ?? "Command could not be parsed.", Array.Empty<string>());
            }

            var segments = new List<CommandSegment>();
            var highest = CommandClassification.ReadOnly;
            var touched = new List<string>();
            string? firstReason = null;

            var cur = new List<string>();
            bool segHasWriteRedir = false;
            for (int i = 0; i < tokens.Count; i++)
            {
                string tok = tokens[i];
                if (tok is "|" or "&&" or "||" or ";")
                {
                    if (cur.Count == 0)
                        return new CommandPolicyDecision(CommandClassification.Blocked, segments, resolvedWD, hash, "Empty command segment.", touched);
                    if (!EvaluateSegment(cur, segHasWriteRedir, resolvedWD, touched, out var seg))
                        return new CommandPolicyDecision(CommandClassification.Blocked, segments, resolvedWD, hash, seg.Reason ?? "Blocked.", touched);
                    segments.Add(seg);
                    if (seg.Classification > highest) { highest = seg.Classification; firstReason = seg.Reason; }
                    cur.Clear();
                    segHasWriteRedir = false;
                }
                else if (tok is ">" or ">>" or "&>" or "<")
                {
                    if (tok != "<") segHasWriteRedir = true;
                    if (i + 1 >= tokens.Count)
                        return new CommandPolicyDecision(CommandClassification.Blocked, segments, resolvedWD, hash, "Missing redirection target.", touched);
                    string target = tokens[++i];
                    string fullTarget = Path.GetFullPath(Path.IsPathRooted(target) ? target : Path.Combine(resolvedWD, target));
                    if (IsProtectedPath(fullTarget) || !IsInsideAllowedRoots(fullTarget))
                        return new CommandPolicyDecision(CommandClassification.Blocked, segments, resolvedWD, hash, $"Redirection target '{target}' is blocked.", touched);
                    touched.Add(fullTarget);
                }
                else
                {
                    cur.Add(tok);
                }
            }

            if (cur.Count == 0)
                return new CommandPolicyDecision(CommandClassification.Blocked, segments, resolvedWD, hash, "Trailing operator with no command.", touched);
            if (!EvaluateSegment(cur, segHasWriteRedir, resolvedWD, touched, out var lastSeg))
                return new CommandPolicyDecision(CommandClassification.Blocked, segments, resolvedWD, hash, lastSeg.Reason ?? "Blocked.", touched);
            segments.Add(lastSeg);
            if (lastSeg.Classification > highest) { highest = lastSeg.Classification; firstReason = lastSeg.Reason; }

            return new CommandPolicyDecision(highest, segments, resolvedWD, hash, firstReason ?? "Validated.", touched.Distinct().ToList());
        }

        private bool EvaluateSegment(List<string> words, bool hasWriteRedir, string resolvedWD, List<string> touched, out CommandSegment segment)
        {
            string prog = Path.GetFileName(words[0]);
            var args = words.Skip(1).ToList();

            if (AlwaysBlockedPrograms.Contains(prog))
            {
                segment = new CommandSegment(words[0], args, CommandClassification.Blocked, $"Program '{prog}' is permanently blocked.");
                return false;
            }
            bool isRO = ReadOnlyPrograms.Contains(prog);
            bool isMut = MutatingAllowedPrograms.Contains(prog);
            if (!isRO && !isMut)
            {
                segment = new CommandSegment(words[0], args, CommandClassification.Blocked, $"Program '{prog}' is not in the allowed list.");
                return false;
            }

            if (string.Equals(prog, "find", StringComparison.OrdinalIgnoreCase) &&
                args.Any(a => a.Equals("-delete", StringComparison.OrdinalIgnoreCase) || a.Equals("-exec", StringComparison.OrdinalIgnoreCase)))
            {
                segment = new CommandSegment(words[0], args, CommandClassification.Blocked, "find -delete/-exec is blocked.");
                return false;
            }

            foreach (var arg in args)
            {
                if (arg.StartsWith("-")) continue;
                if (arg.StartsWith("~") || arg.Contains("..") || Path.IsPathRooted(arg) || arg.Contains('/') || arg.Contains('\\'))
                {
                    if (arg.StartsWith("~") && !arg.StartsWith("~/") && arg != "~")
                    {
                        segment = new CommandSegment(words[0], args, CommandClassification.Blocked, "Cross-user home expansion is blocked.");
                        return false;
                    }
                    string expanded = arg.StartsWith("~/") ? Path.Combine(_homeDirectory, arg[2..]) : arg;
                    string full = Path.GetFullPath(Path.IsPathRooted(expanded) ? expanded : Path.Combine(resolvedWD, expanded));
                    if (IsProtectedPath(full) || !IsInsideAllowedRoots(full))
                    {
                        segment = new CommandSegment(words[0], args, CommandClassification.Blocked, $"Path '{arg}' is outside allowed roots or protected.");
                        return false;
                    }
                    touched.Add(full);
                }
            }

            var cls = (isMut || hasWriteRedir) ? CommandClassification.NeedsApproval : CommandClassification.ReadOnly;
            segment = new CommandSegment(words[0], args, cls, cls == CommandClassification.ReadOnly ? "Read-only command." : "Mutating command requires approval.");
            return true;
        }
    }
}

