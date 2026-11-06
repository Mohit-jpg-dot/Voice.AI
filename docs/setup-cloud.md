# Setting Up Cloud AI in Voice.AI (OpenAI, Anthropic Claude, Gemini & Search)

Voice.AI features a unified provider architecture that allows you to plug in your own API keys for frontier intelligence, computer vision, tool calling, and web search.

---

## 1. Supported Providers & Models

| Provider | Supported Capabilities | Recommended Model IDs | Context Window |
| :--- | :--- | :--- | :--- |
| **OpenAI** | Streaming Chat, Multimodal Vision, Tool Calling, Whisper STT, TTS | `gpt-4o`, `gpt-4o-mini` | 128,000 tokens |
| **Anthropic Claude** | Streaming Chat, Multimodal Vision, Tool Calling | `claude-3-5-sonnet-20241022`, `claude-3-5-haiku-20241022` | 200,000 tokens |
| **Brave Search** | Web Search Grounding with Sources & Dates | REST API (`v1/web/search`) | Real-time index |
| **Tavily Search** | AI-agent Search Grounding | REST API (`v1/search`) | Real-time index |

---

## 2. Obtaining Your API Keys

### OpenAI
1. Visit [platform.openai.com/api-keys](https://platform.openai.com/api-keys) and sign in.
2. Click **Create new secret key**, give it a name (e.g. `Voice.AI Mac`), and copy the key starting with `sk-proj-...` or `sk-...`.

### Anthropic Claude
1. Visit [console.anthropic.com/settings/keys](https://console.anthropic.com/settings/keys) and sign in.
2. Click **Create Key**, name it `Voice.AI Mac`, and copy the key starting with `sk-ant-...`.

### Search Provider (Brave or Tavily)
- **Brave Search API**: Go to [brave.com/search/api](https://brave.com/search/api) and generate a free API key (2,000 free queries/month).
- **Tavily AI Search**: Go to [tavily.com](https://tavily.com) and copy your secret key (1,000 free searches/month).

---

## 3. Adding Your Keys in Voice.AI

1. Open **Voice.AI** and hover over the top Notch or press `⌘,` to open **Settings**.
2. Under **AI Brain & Intelligence**:
   - Set **Execution Mode** to **Cloud Mode (API Key)** or **Hybrid Mode**.
   - Paste your **OpenAI API Key** and click **Save**.
   - Paste your **Claude API Key** and click **Save**.
   - Paste your **Search API Key** and click **Save**.
3. Click the **Test Everything** button. Voice.AI will execute a live, lightweight probe call to verify streaming, tool calling, and response latency.

---

## 4. Keychain Security Guarantee

Voice.AI strictly obeys Apple macOS security best practices:
- **Zero Disk Persistence**: Keys are never written to plain-text `.json`, `.plist`, or configuration files.
- **Apple Keychain Access**: Keys are stored inside macOS Keychain under service identifier `ai.voice.app`.
- **Zero Logging**: API keys, credentials, and Authorization headers are masked in all diagnostic and crash logs.
- **Private Data Boundary**: In **Local Mode**, network egress is blocked. In **Hybrid Mode**, an explicit prompt asks for your confirmation before any screenshot or audio is sent to Cloud APIs.

