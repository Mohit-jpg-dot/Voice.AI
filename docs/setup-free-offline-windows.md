# Free & Offline Voice.AI Setup Guide (Windows 10 & 11)

Voice.AI on Windows can run **100% offline** without any third-party cloud subscriptions, credit cards, or proprietary API keys. When configured in Free Offline Mode, voice transcription, reasoning, and speech synthesis execute locally on your hardware.

---

## Architecture Overview

```
                      ┌──────────────────────────────────────┐
                      │    Voice.AI Top-Center Island (WinUI 3)│
                      └──────────────────┬───────────────────┘
                                         │
                   ┌─────────────────────┼─────────────────────┐
                   ▼                     ▼                     ▼
        ┌─────────────────────┐┌──────────────────┐┌──────────────────────┐
        │  Local Whisper STT  ││  Ollama Engine   ││  Windows Neural TTS  │
        │  (whisper.cpp Win)  ││  (Llama 3 / Qwen)││  (Swara / Jenny)     │
        └─────────────────────┘└──────────────────┘└──────────────────────┘
                   ▲                     ▲                     ▲
                   └─────────────────────┴─────────────────────┘
                                  100% Offline
```

---

## 1. Prerequisites & System Requirements

- **Operating System:** Windows 10 (version 22H2 or newer) or Windows 11 (21H2, 22H2, 23H2+).
- **RAM:** Minimum 8 GB (16 GB recommended for 7B/8B models).
- **Storage:** ~4 GB free disk space for models.
- **GPU (Optional but recommended):** NVIDIA RTX (CUDA) or modern Intel/AMD integrated graphics (DirectML / AVX2).

---

## 2. In-App Setup (Recommended)

1. Launch **Voice.AI** on Windows.
2. In the **First-Run Setup Wizard**:
   - Select **Free Offline Mode**.
   - Click **Download Recommended Offline Models**. Voice.AI will fetch:
     - `qwen2.5:3b-instruct` or `llama3.2:3b` (~2.0 GB) for fast local reasoning.
     - `whisper.cpp-small` (~460 MB) for multi-language Hindi/Hinglish/English transcription.
3. Grant Microphone permissions when prompted (or open `ms-settings:privacy-microphone` if blocked).
4. Completed! Hold **Right Ctrl** for 250ms to talk completely offline.

---

## 3. Manual CLI Setup (Power Users)

If you prefer managing local daemons manually via PowerShell or Windows Terminal:

### Step 3.1: Install and Run Ollama for Windows

1. Download Ollama Windows installer from official repository:
   ```powershell
   winget install Ollama.Ollama
   ```
2. Pull the optimized reasoning model:
   ```powershell
   ollama pull qwen2.5:3b
   # Or for larger VRAM systems:
   ollama pull llama3:8b
   ```
3. Verify Ollama is listening locally:
   ```powershell
   curl http://127.0.0.1:11434/api/tags
   ```

### Step 3.2: Set Up Local Whisper STT

Voice.AI communicates with `whisper.cpp` server on port 8080:
```powershell
# Run whisper.cpp server with ggml-small model
.\whisper-server.exe -m models\ggml-small.bin --port 8080
```

### Step 3.3: Verify Windows Neural Voices (Hindi & English)

Windows 10/11 includes built-in Natural voices:
- **Hindi (India):** `Microsoft Swara Online (Natural)` / `Microsoft Madhur Online (Natural)`
- **English (India):** `Microsoft Neerja Online (Natural)` / `Microsoft Prabhat Online (Natural)`
- **English (US):** `Microsoft Jenny Online (Natural)` / `Microsoft Guy Online (Natural)`

To install additional voices in Windows:
1. Open **Windows Settings** (`Win + I`).
2. Navigate to **Time & Language** > **Speech**.
3. Under **Manage voices**, click **Add voices** and select **Hindi** and **English (India)**.

---

## 4. Testing Offline Operation

To verify that Voice.AI is strictly running offline without external calls:
1. Disconnect Wi-Fi and unplug Ethernet.
2. Hold **Right Ctrl** and speak:
   > *"25 into 4 kitna hota hai"*
3. Voice.AI will immediately respond via the offline MathEngine and local TTS:
   > *"25 × 4 = 100"*
4. Check history log file at `%APPDATA%\VoiceAI\EncryptedHistory\default_history.json`. All records are stored locally with zero cloud telemetry.
