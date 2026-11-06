# Voice.AI Setup Guide: Free and Offline (On-Device Intelligence)

Voice.AI provides a completely private, offline, and free operating path designed to run state-of-the-art open models directly on your Mac Apple Silicon chip. In Free mode, **zero voice audio, screen captures, or prompt history are ever uploaded to cloud servers.**

---

## 1. Hardware Detection & Tier Selection

When you select **"Completely free, offline"** in the First-Run Setup Assistant, Voice.AI inspects your Mac's hardware specifications in real time:
- **Processor:** Chip model (e.g., Apple M1, M2, M3, M4, M5).
- **Unified RAM:** Available system memory (e.g., 8 GB, 16 GB, 32 GB, 64 GB+).
- **Disk Storage:** Free disk space available on the primary APFS APFS container.

### Hardware Recommendation Matrix

| Hardware Tier | Minimum Specs | Recommended LLM | STT Engine | TTS Engine | Total Download |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Lite** | 8 GB RAM / 10 GB Disk | `qwen2.5:3b` | Whisper Base Multilingual | macOS Enhanced Neural Voice | ~2.5 GB |
| **Balanced** *(Default)* | 16 GB RAM / 20 GB Disk | `qwen2.5:7b` | Whisper Small Multilingual | macOS Enhanced Neural Voice | ~5.2 GB |
| **Best** | 32 GB+ RAM / 40 GB Disk | `qwen2.5:14b` | Whisper Large-v3 Multilingual | macOS Enhanced Neural Voice | ~9.8 GB |

---

## 2. Model Catalog & Transparency Parity

Voice.AI believes in 100% technical transparency. Every component installed by the automated downloader has an exact, copyable command shown in the UI:

### Signed Components Catalog (`release/catalog.json`)

1. **Ollama Local Engine (v0.5.4)**
   - **Command:** `brew install ollama && ollama serve`
   - **License:** MIT
   - **Size:** 65 MB
   - **Purpose:** Local inference runtime serving open weights via HTTP on `localhost:11434`.

2. **Qwen 2.5 (7B Instruct - High Intelligence)**
   - **Command:** `ollama pull qwen2.5:7b`
   - **License:** Apache 2.0
   - **Size:** 4.7 GB
   - **Purpose:** On-device conversational intelligence, tool calling, and computer control intent parsing.

3. **Whisper Multilingual Core (STT)**
   - **Command:** `voiceai models install whisper-small-multilingual`
   - **License:** MIT
   - **Size:** 480 MB
   - **Purpose:** Streaming on-device speech-to-text with automatic language and code-switching detection (English, Hindi, Hinglish).

4. **Neural Spoken Voice (macOS Enhanced)**
   - **Command:** `voiceai models install voice-piper-en-hi`
   - **License:** MIT
   - **Size:** 85 MB
   - **Purpose:** Local low-latency text-to-speech output.

---

## 3. In-App Automated Download & Configuration

You do **not** need to open Terminal or run commands manually. The in-app download manager handles:
- Multi-item sequential and parallel queue execution.
- Real-time download progress with elapsed time and speed metrics.
- Pause, Resume, and Cancel actions for each item.
- Automatic SHA-256 integrity verification against `release/catalog.json`.
- Live smoke-test probing to ensure `localhost:11434` is healthy and ready before transitioning to active listening.

---

## 4. Verifying Complete Offline Operation

To verify that Voice.AI functions with zero network connection:
1. Turn off your Wi-Fi or unplug your Ethernet cable.
2. Trigger Voice.AI (`Option + Space` or Notch tap).
3. Speak: *"Open Safari and play a song on Spotify"*.
4. Notice immediate local transcription, zero network requests, and autonomous execution.
5. In **Settings > Storage & Offline Models**, click **"Run Offline Check"** to execute a diagnostic probe confirming 100% on-device operation.

