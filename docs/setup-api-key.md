# Voice.AI Setup Guide: Paid API Key (Cloud Intelligence)

Voice.AI supports direct integration with leading frontier cloud intelligence providers. Using cloud mode provides highest-accuracy screen vision grounding, complex multi-step reasoning, and web-scale deep research.

---

## 1. Supported Providers & Model Configurations

| Provider | Supported Models | Vision Support | Tool Calling | STT / TTS |
| :--- | :--- | :--- | :--- | :--- |
| **OpenAI** | `gpt-4o`, `gpt-4o-mini`, `o1`, `o3-mini` | Yes (high-res grounding) | Yes (structured JSON) | Whisper-1 / TTS-1-HD |
| **Anthropic Claude** | `claude-3-7-sonnet`, `claude-3-5-sonnet`, `claude-3-5-haiku` | Yes (multi-image) | Yes (XML tools) | System / Cloud |
| **Google Gemini** | `gemini-2.0-flash`, `gemini-1.5-pro` | Yes (video & image) | Yes | Cloud |
| **Custom OpenAI-Compatible** | LM Studio, vLLM, OpenRouter, DeepSeek | Provider dependent | Provider dependent | Local / Custom |

---

## 2. Security & Keychain Isolation

Voice.AI takes credential security seriously:
- **Keychain Storage:** All API keys are stored exclusively in the macOS system Keychain under service `ai.voice.app`.
- **Zero Disk Persistence:** Keys are never serialized to disk, caches, preferences, or logs.
- **Redaction Filter:** All inputs and transcripts are passed through an active secret-scrubbing filter before encryption, ensuring no API keys (`sk-...`, `Bearer ...`) ever enter session history.
- **Masking:** After entering an API key in setup or settings, the key is permanently masked (`••••••••••••`).

---

## 3. Real Test Call Validation

Before accepting an API key, Voice.AI performs a non-destructive, cheap test call to the provider's `/v1/models` or completion endpoint:
1. Validates authentication token validity.
2. Checks available quota and rate-limit status.
3. Automatically fetches the list of available models for one-click selection.
4. Returns clear, human-readable errors with action steps if invalid.

---

## 4. Privacy & Explicit Transmission Notice

In Cloud or Hybrid mode:
- Screen screenshots and audio packets sent to cloud endpoints display a clear transmission indicator in the Boring Notch HUD.
- In Hybrid mode, an explicit confirmation dialog prompts the user before sending screen captures off-device.

