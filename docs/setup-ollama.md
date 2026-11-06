# Setting Up Local AI with Ollama in Voice.AI

Voice.AI includes 100% on-device local execution powered by **Ollama**, local **Whisper** neural transcription, and native macOS text-to-speech. In Local Mode, no audio, text, or screenshots ever leave your Mac.

---

## 1. Quick Install Guide

### Option A: Install via Homebrew (Recommended)
Open Terminal and run:
```bash
brew install ollama
brew services start ollama
```

### Option B: Download Direct Binary
1. Download from [ollama.com/download](https://ollama.com/download).
2. Move `Ollama.app` into `/Applications` and launch it.
3. Ollama will run in the menu bar at `http://localhost:11434`.

---

## 2. Pull Recommended Models

To enable natural chat, coding, and screen vision, pull the recommended open-weights models:

### 1. Primary Chat & Reasoning Model (Qwen 2.5)
```bash
# Recommended for Apple Silicon (8GB - 16GB Unified Memory)
ollama pull qwen2.5:7b

# For 16GB+ Unified Memory (faster and smarter)
ollama pull qwen2.5:latest
```

### 2. Multimodal Vision Model (For UI Grounding & Screen Understanding)
```bash
ollama pull llama3.2-vision:latest
```

### 3. Verify Local Installation
Check that Ollama is responding locally:
```bash
curl http://localhost:11434/api/tags
```
You should see your pulled models in the JSON output.

---

## 3. Configuring Voice.AI for Local Mode

1. Open **Voice.AI** Settings (`⌘,` or hover over the Notch).
2. Locate the **AI Brain & Intelligence** card.
3. Change **Execution Mode** to:
   - **Local Mode (Ollama On-Device)**: 100% on-device privacy. Zero network egress.
   - **Hybrid Mode (Local Fast, Cloud Deep)**: Runs fast-path commands and small conversation on Ollama, prompting you before using Cloud vision if local model lacks multimodal vision.
4. Check the **Ollama Local Daemon** status dot:
   - 🟢 **Green (Online)**: Connected to `http://localhost:11434`.
   - 🟠 **Orange (Offline)**: Ollama is not running. Start with `brew services start ollama` or launch the Ollama app.
5. Tap **Test Everything** to run a real streaming and tool-calling probe.

---

## 4. Hardware Recommendations

| Unified Memory | Recommended Chat Model | Recommended Vision Model |
| :--- | :--- | :--- |
| **8 GB RAM** | `qwen2.5:3b` or `qwen2.5:7b` | `llama3.2-vision:latest` |
| **16 GB RAM** | `qwen2.5:7b` or `qwen2.5:14b` | `llama3.2-vision:latest` |
| **32 GB+ RAM** | `qwen2.5:32b` or `llama3.3:70b` | `llama3.2-vision:latest` |

