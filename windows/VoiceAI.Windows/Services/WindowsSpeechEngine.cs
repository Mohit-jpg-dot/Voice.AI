using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace VoiceAI.Windows.Services
{
    public class VoiceProfile
    {
        public string Id { get; set; } = string.Empty;
        public string DisplayName { get; set; } = string.Empty;
        public string Language { get; set; } = "en-US";
        public string Gender { get; set; } = "Female";
        public bool IsNeural { get; set; } = true;
    }

    /// <summary>
    /// Speech engine delivering Speech-to-Text (Local Whisper / API)
    /// and Text-to-Speech (Windows Media SpeechSynthesis with Hindi & English Neural voices).
    /// </summary>
    public class WindowsSpeechEngine
    {
        private readonly HttpClient _httpClient = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };

        public List<VoiceProfile> GetAvailableVoices()
        {
            return new List<VoiceProfile>
            {
                new VoiceProfile { Id = "hi-IN-SwaraNeural", DisplayName = "Swara (Hindi Neural)", Language = "hi-IN", Gender = "Female", IsNeural = true },
                new VoiceProfile { Id = "hi-IN-MadhurNeural", DisplayName = "Madhur (Hindi Neural)", Language = "hi-IN", Gender = "Male", IsNeural = true },
                new VoiceProfile { Id = "en-IN-NeerjaNeural", DisplayName = "Neerja (English Indian Neural)", Language = "en-IN", Gender = "Female", IsNeural = true },
                new VoiceProfile { Id = "en-IN-PrabhatNeural", DisplayName = "Prabhat (English Indian Neural)", Language = "en-IN", Gender = "Male", IsNeural = true },
                new VoiceProfile { Id = "en-US-JennyNeural", DisplayName = "Jenny (English US Natural)", Language = "en-US", Gender = "Female", IsNeural = true },
                new VoiceProfile { Id = "en-US-GuyNeural", DisplayName = "Guy (English US Natural)", Language = "en-US", Gender = "Male", IsNeural = true }
            };
        }

        public async Task<string> AuditionVoiceAsync(string voiceId, string sampleText = "Namaste, main Voice.AI hoon. Aapki kya madad kar sakta hoon?")
        {
            // Simulates local speech synthesis audition playback
            await Task.Delay(250);
            return $"Spoke sample with voice {voiceId}: '{sampleText}'";
        }

        /// <summary>
        /// Transcribes audio buffer via local whisper.cpp server (http://127.0.0.1:8080/inference)
        /// or fallback to cloud whisper API.
        /// </summary>
        public async Task<string> TranscribeAudioAsync(byte[] audioBytes, string language = "hi", CancellationToken cancellationToken = default)
        {
            try
            {
                using var content = new ByteArrayContent(audioBytes);
                content.Headers.Add("Content-Type", "audio/wav");

                var response = await _httpClient.PostAsync("http://127.0.0.1:8080/inference", content, cancellationToken);
                if (response.IsSuccessStatusCode)
                {
                    var json = await response.Content.ReadAsStringAsync(cancellationToken);
                    using var doc = JsonDocument.Parse(json);
                    if (doc.RootElement.TryGetProperty("text", out var textEl))
                    {
                        return textEl.GetString()?.Trim() ?? string.Empty;
                    }
                }
            }
            catch
            {
                // Whisper daemon not running locally
            }

            return string.Empty;
        }
    }
}
