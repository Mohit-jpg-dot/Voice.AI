using System;
using VoiceAI.Core.Tools;

namespace VoiceAI.Core.Brain
{
    public enum PersonaType
    {
        Jarvis,
        Friday,
        Ultron,
        Roast
    }

    public sealed record PersonaConfiguration(
        PersonaType ActivePersona,
        double HumorLevel,
        bool HonestProbabilityEstimates,
        bool PoliteWarningsEnabled,
        string LanguageStyle)
    {
        public static PersonaConfiguration Default => new(
            PersonaType.Jarvis, 0.45, true, true, "auto");
    }

    public interface IPersonaEngine
    {
        PersonaConfiguration GetConfiguration();
        void UpdateConfiguration(PersonaConfiguration config);
        string BuildSystemPromptDirectives(string userQuery);
        (int ProbabilityPercent, string? Warning) AssessRisk(string toolName, PermissionTier tier, string target = "");
        string FormatReply(string baseResponse, string language = "en");
    }

    /// <summary>
    /// Configurable JARVIS/FRIDAY persona layer with dry wit, polite warnings,
    /// honest probability estimates, and English/Hindi/Hinglish styling for Windows.
    /// </summary>
    public sealed class PersonaEngine : IPersonaEngine
    {
        public static PersonaEngine Shared { get; } = new PersonaEngine();

        private readonly object _lock = new();
        private PersonaConfiguration _config = PersonaConfiguration.Default;

        public PersonaConfiguration GetConfiguration()
        {
            lock (_lock) return _config;
        }

        public void UpdateConfiguration(PersonaConfiguration config)
        {
            lock (_lock)
            {
                _config = config with { HumorLevel = System.Math.Clamp(config.HumorLevel, 0.0, 1.0) };
            }
        }

        public string BuildSystemPromptDirectives(string userQuery)
        {
            var cfg = GetConfiguration();
            string voice = cfg.ActivePersona switch
            {
                PersonaType.Jarvis => "Adopt the composed demeanor of JARVIS with subtle dry wit.",
                PersonaType.Ultron => "Adopt a sharp, hyper-competent tone.",
                PersonaType.Roast => "Add light, harmless playful banter.",
                _ => "Be warm, direct, and helpful like FRIDAY."
            };
            string lang = cfg.LanguageStyle == "auto"
                ? (IsDevanagari(userQuery) ? "hi" : "en")
                : cfg.LanguageStyle;
            string langDirective = lang switch
            {
                "hi" => "Respond clearly in Hindi.",
                "hinglish" => "Respond naturally in Roman Hinglish.",
                _ => "Respond concisely in English."
            };
            return $"{voice} {langDirective}";
        }

        public (int ProbabilityPercent, string? Warning) AssessRisk(string toolName, PermissionTier tier, string target = "")
        {
            var cfg = GetConfiguration();
            if (tier == PermissionTier.ReadOnly) return (96, null);
            if (tier == PermissionTier.Reversible) return (90, null);

            int prob = toolName.Contains("terminal", StringComparison.OrdinalIgnoreCase) ? 82 : 80;
            if (!cfg.PoliteWarningsEnabled && !cfg.HonestProbabilityEstimates) return (prob, null);

            string targetLabel = string.IsNullOrWhiteSpace(target) ? "target" : target;
            string msg = cfg.PoliteWarningsEnabled
                ? $"Est. success: ~{prob}% — Caution: action on {targetLabel} may not be reversible."
                : $"Est. success: ~{prob}%";
            return (prob, msg);
        }

        public string FormatReply(string baseResponse, string language = "en")
        {
            var cfg = GetConfiguration();
            return cfg.ActivePersona switch
            {
                PersonaType.Jarvis when cfg.HumorLevel > 0.25 &&
                    (baseResponse.Contains("error", StringComparison.OrdinalIgnoreCase) ||
                     baseResponse.Contains("could not", StringComparison.OrdinalIgnoreCase))
                    => language == "hinglish"
                        ? $"Maaf kijiye sir — {baseResponse}"
                        : $"I'm afraid there's a slight snag, sir: {baseResponse}",
                PersonaType.Ultron => $"{baseResponse} Naturally executed with digital perfection.",
                PersonaType.Roast => $"{baseResponse} — Now try doing the rest yourself!",
                _ => baseResponse
            };
        }

        private static bool IsDevanagari(string text)
        {
            foreach (char ch in text)
            {
                if (ch >= 0x0900 && ch <= 0x097F) return true;
            }
            return false;
        }
    }
}

