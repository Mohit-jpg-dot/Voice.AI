using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

namespace VoiceAI.Core.Brain
{
    public enum AIMode
    {
        Cloud,
        Local,
        GoogleSearch,
        Hybrid
    }

    public record LLMChatMessage(string Role, string Content);

    public record ChatResponse(string Text, bool IsSuccess, string ErrorMessage = "");

    public interface IChatModel
    {
        string ProviderName { get; }
        string ModelIdentifier { get; }
        Task<ChatResponse> SendMessageAsync(IReadOnlyList<LLMChatMessage> messages);
        IAsyncEnumerable<string> StreamMessageAsync(IReadOnlyList<LLMChatMessage> messages);
    }

    /// <summary>
    /// Central AI router for Windows.
    /// Routes between Cloud LLMs, Local Ollama on Windows, and zero-key Google Search mode.
    /// </summary>
    public sealed class ModelRouter
    {
        public static ModelRouter Shared { get; } = new ModelRouter();

        public AIMode CurrentMode { get; set; } = AIMode.GoogleSearch;

        public string CloudApiKey { get; set; } = string.Empty;
        public string CloudProvider { get; set; } = "openai"; // openai, claude, gemini
        public string OllamaBaseUrl { get; set; } = "http://127.0.0.1:11434";
        public string OllamaModelName { get; set; } = "qwen2.5:7b";

        private readonly HttpClient _http = new HttpClient { Timeout = TimeSpan.FromSeconds(60) };

        private ModelRouter() { }

        public IChatModel ResolveChatModel()
        {
            switch (CurrentMode)
            {
                case AIMode.Local:
                    return new OllamaChatModel(_http, OllamaBaseUrl, OllamaModelName);
                case AIMode.GoogleSearch:
                    return new GoogleOnlyChatModel();
                case AIMode.Cloud:
                case AIMode.Hybrid:
                default:
                    return new CloudChatModel(_http, CloudProvider, CloudApiKey);
            }
        }
    }

    public sealed class GoogleOnlyChatModel : IChatModel
    {
        public string ProviderName => "Google Search (No LLM)";
        public string ModelIdentifier => "google-search-direct-v1";

        public async Task<ChatResponse> SendMessageAsync(IReadOnlyList<LLMChatMessage> messages)
        {
            string prompt = messages.Count > 0 ? messages[^1].Content : "";
            var card = await GoogleSearchFreeEngine.Shared.AnswerQuestionAsync(prompt);

            string formatted = $"\"{card.AnswerText}\"\n\n— {card.SourceTitle} ({card.MethodLabel})\n🔗 {card.SourceUrl}\n⚡ Retrieved in {card.RetrievalTimeMs}ms";
            return new ChatResponse(formatted, true);
        }

        public async IAsyncEnumerable<string> StreamMessageAsync(IReadOnlyList<LLMChatMessage> messages)
        {
            var res = await SendMessageAsync(messages);
            var words = res.Text.Split(' ');
            foreach (var w in words)
            {
                yield return w + " ";
                await Task.Delay(15);
            }
        }
    }

    public sealed class OllamaChatModel : IChatModel
    {
        public string ProviderName => "Ollama (Windows Local)";
        public string ModelIdentifier { get; }

        private readonly HttpClient _http;
        private readonly string _baseUrl;

        public OllamaChatModel(HttpClient http, string baseUrl, string modelName)
        {
            _http = http;
            _baseUrl = baseUrl.TrimEnd('/');
            ModelIdentifier = modelName;
        }

        public async Task<ChatResponse> SendMessageAsync(IReadOnlyList<LLMChatMessage> messages)
        {
            try
            {
                var payload = new
                {
                    model = ModelIdentifier,
                    messages = messages,
                    stream = false
                };

                var content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");
                var res = await _http.PostAsync($"{_baseUrl}/api/chat", content);
                if (!res.IsSuccessStatusCode)
                {
                    return new ChatResponse("", false, $"Ollama returned HTTP {(int)res.StatusCode}: {res.ReasonPhrase}");
                }

                var jsonStr = await res.Content.ReadAsStringAsync();
                using var doc = JsonDocument.Parse(jsonStr);
                string reply = doc.RootElement.GetProperty("message").GetProperty("content").GetString() ?? "";
                return new ChatResponse(reply, true);
            }
            catch (Exception ex)
            {
                return new ChatResponse("", false, $"Failed to reach local Ollama: {ex.Message}");
            }
        }

        public async IAsyncEnumerable<string> StreamMessageAsync(IReadOnlyList<LLMChatMessage> messages)
        {
            var res = await SendMessageAsync(messages);
            if (res.IsSuccess)
            {
                foreach (var w in res.Text.Split(' '))
                {
                    yield return w + " ";
                    await Task.Delay(15);
                }
            }
            else
            {
                yield return res.ErrorMessage;
            }
        }
    }

    public sealed class CloudChatModel : IChatModel
    {
        public string ProviderName { get; }
        public string ModelIdentifier { get; }

        private readonly HttpClient _http;
        private readonly string _apiKey;

        public CloudChatModel(HttpClient http, string provider, string apiKey)
        {
            _http = http;
            ProviderName = provider.ToUpperInvariant();
            ModelIdentifier = provider.ToLowerInvariant() switch
            {
                "claude" => "claude-3-5-sonnet-20241022",
                "gemini" => "gemini-1.5-pro",
                _ => "gpt-4o"
            };
            _apiKey = apiKey;
        }

        public async Task<ChatResponse> SendMessageAsync(IReadOnlyList<LLMChatMessage> messages)
        {
            if (string.IsNullOrEmpty(_apiKey))
            {
                return new ChatResponse("", false, "No API key configured for Cloud AI Mode.");
            }

            try
            {
                // Default OpenAI compatible endpoint
                var payload = new
                {
                    model = ModelIdentifier,
                    messages = messages,
                    temperature = 0.7
                };

                using var req = new HttpRequestMessage(HttpMethod.Post, "https://api.openai.com/v1/chat/completions");
                req.Headers.Add("Authorization", $"Bearer {_apiKey}");
                req.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");

                var res = await _http.SendAsync(req);
                if (!res.IsSuccessStatusCode)
                {
                    return new ChatResponse("", false, $"Cloud provider returned HTTP {(int)res.StatusCode}");
                }

                var jsonStr = await res.Content.ReadAsStringAsync();
                using var doc = JsonDocument.Parse(jsonStr);
                string reply = doc.RootElement.GetProperty("choices")[0].GetProperty("message").GetProperty("content").GetString() ?? "";
                return new ChatResponse(reply, true);
            }
            catch (Exception ex)
            {
                return new ChatResponse("", false, $"Cloud request failed: {ex.Message}");
            }
        }

        public async IAsyncEnumerable<string> StreamMessageAsync(IReadOnlyList<LLMChatMessage> messages)
        {
            var res = await SendMessageAsync(messages);
            if (res.IsSuccess)
            {
                foreach (var w in res.Text.Split(' '))
                {
                    yield return w + " ";
                    await Task.Delay(15);
                }
            }
            else
            {
                yield return res.ErrorMessage;
            }
        }
    }
}

