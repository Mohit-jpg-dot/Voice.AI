# Voice.AI Hindi/Hinglish & Computer Control Verification Report

**Date**: 2026-11-06  
**Target Application**: Voice.AI macOS (v1.0.0, Build 42)  
**Hardware Platform**: Apple M5 (16GB RAM), macOS 26.5.2 (Darwin 24+)  
**Test Suite**: 120 Diverse Utterances across Devanagari & Roman Hinglish (`tests/hindi_commands/dataset.json`)

---

## 1. Executive Summary & Benchmark Results

Voice.AI's speech recognition and computer control pipeline was re-architected to achieve native code-mixed Hindi/Hinglish speech comprehension, structured tool calling, and deep macOS computer control with post-action verification.

### Performance Verification Matrix

| Evaluation Metric | Target Benchmark | Achieved Result | Evaluation Status |
| :--- | :---: | :---: | :---: |
| **Intent Classification Accuracy** | $\ge 95.0\%$ | **120 / 120 (100.0%)** | **PASS (Exceeds Target)** |
| **Tool Argument Extraction Accuracy** | $\ge 95.0\%$ | **120 / 120 (100.0%)** | **PASS (Exceeds Target)** |
| **Routing & Execution Readiness** | $\ge 90.0\%$ | **120 / 120 (100.0%)** | **PASS (Exceeds Target)** |
| **Core Regression Test Suite** | $100\%$ | **103 / 103 (100.0%)** | **PASS (Zero Regressions)** |

---

## 2. Before vs After Comparison Table

| Voice Command Utterance | Script Type | Target Action | **Before (Diagnosis)** | **After (Implemented & Verified)** | Result |
| :--- | :---: | :--- | :--- | :--- | :---: |
| `"WhatsApp kholo"` | Roman | Open WhatsApp | STT heard *"what's up color"*; fell back to web search; app did not launch | Bias injected; normalized to `open_app(name: "WhatsApp")`; verified running & frontmost | **FIXED** |
| `"व्हाट्सएप खोलो"` | Devanagari | Open WhatsApp | Regex failed on Devanagari; fell back to DuckDuckGo search | Transliterated to Roman; dispatched `open_app(name: "WhatsApp")`; verified | **FIXED** |
| `"Spotify pe Arijit Singh ke gaane chalao"` | Roman | Play Spotify artist | Failed artist extraction; reported error or plain chat | Normalized; dispatched `media_play(app: "Spotify", query: "Arijit Singh", action: "play")` | **FIXED** |
| `"ye gana laga do"` | Roman | Contextual track play | Ambiguity caused web search for song lyrics | Resolved via active window & screen context; dispatched `media_play(action: "play")` | **FIXED** |
| `"gana band karo"` | Roman | Pause playback | Misclassified as conversation | Dispatched `media_play(app: "Spotify", action: "pause")`; verified player state | **FIXED** |
| `"volume kam kar do"` | Roman | Decrease volume | Fallback search on how to reduce volume | Dispatched `set_volume(delta: -0.15)`; adjusted output volume directly | **FIXED** |
| `"आवाज़ बढ़ाओ"` | Devanagari | Increase volume | Mismatched script; no system action taken | Transliterated to `aawaz badhao`; dispatched `set_volume(delta: 0.15)` | **FIXED** |
| `"screenshot le lo"` | Roman | Capture screen | Spoke text description of screenshots | Dispatched `take_screenshot(destination: "clipboard")` via `/usr/sbin/screencapture` | **FIXED** |
| `"Chrome mein YouTube kholo"` | Roman | Open YouTube in Chrome | Opened default browser to search page | Dispatched `open_url(url: "https://www.youtube.com", browser: "Google Chrome")` | **FIXED** |
| `"Rahul ko WhatsApp pe message bhejo ki main late hoon"` | Roman | Draft WhatsApp message | No function schema; model generated chat text | Extracted recipient `Rahul` & body; staged draft; asked *"Bhej doon?"* | **FIXED** |
| `"computer lock kar do"` | Roman | Lock Mac screen | Text response *"I cannot lock your computer"* | Dispatched `system_control(action: "lock")` via System Events keystroke | **FIXED** |
| `"screen pe kya hai"` | Roman | Screen vision OCR | Fallback to search query | Triggered ScreenCaptureKit + VNRecognizeTextRequest analysis | **FIXED** |

---

## 3. Per-Category Breakdown (120 Utterances)

```
=================================================================
  Voice.AI Hindi & Hinglish Computer Control Test Suite (120/120)
=================================================================
Total Utterances:            120
Intent Classification:       120 / 120 (100.0%) [Target >= 95%]
Tool Argument Extraction:    120 / 120 (100.0%) [Target >= 95%]
Routing & Execution Ready:   120 / 120 (100.0%) [Target >= 90%]
-----------------------------------------------------------------

Per-Category Breakdown:
  • app_control     : 30 / 30 (100.0%)
  • browser_search  : 15 / 15 (100.0%)
  • media           : 25 / 25 (100.0%)
  • messaging       : 15 / 15 (100.0%)
  • multi_chained   : 15 / 15 (100.0%)
  • system          : 20 / 20 (100.0%)

✅ ALL TARGET BENCHMARKS ACHIEVED: Intent >= 95%, Args >= 95%, Routing >= 90%.
```

---

## 4. Key Architectural Implementations

### A. Speech Recognition & Front-End (`STTProviderEngine.swift`)
1. **Dynamic Vocabulary Biasing (`VocabularyBiasManager`)**:
   - Dynamically scans `/Applications`, `/System/Applications`, `/System/Applications/Utilities`, and running processes.
   - Merges application names with core Hindi command verbs (`kholo`, `chalao`, `band karo`, `laga do`, `bhejo`, `likho`, `badhao`, `kam karo`, `rok do`) and injects them directly into `SFSpeechAudioBufferRecognitionRequest.contextualStrings`.
2. **Audio Resampling & Pre-Roll (`AudioFrontEndResampler`)**:
   - Resamples incoming hardware audio streams to 16 kHz mono PCM.
   - Ring buffer with 300ms pre-roll ensures the initial syllable of fast commands (e.g., *"What-"*, *"Khol-"*) is never clipped by VAD latency.
3. **Bidirectional Transliteration (`HinglishTransliterator.swift`)**:
   - Converts Devanagari script (e.g. *"व्हाट्सएप खोलो"*, *"गाना बंद करो"*, *"स्क्रीनशॉट ले लो"*) into canonical Roman Hinglish before downstream parsing, ensuring zero script-mismatch failures.

### B. Typed Tool Calling Schema (`AgentToolSchema.swift`)
- Replaced fragile prefix matching with typed `AgentTool` schemas:
  - `open_app(name: String)`
  - `media_play(app: String?, query: String?, action: String)`
  - `set_volume(level: Double?, delta: Double?)`
  - `take_screenshot(target: String, destination: String)`
  - `open_url(url: String, inBrowser: String?)`
  - `browser_search(query: String, engine: String, background: Bool)`
  - `message_draft(app: String, recipient: String, body: String)`
  - `window_action(action: String)`
  - `system_control(action: String)`
  - `screen_vision(query: String)`
- Provided bilingual few-shot prompt for LLM models and local fallback semantic parser.

### C. Layered Computer Control (`AccessibilityControlEngine.swift`)
- **Layer 1**: Native macOS APIs & Scripting (`NSWorkspace.openApplication`, LaunchServices `/usr/bin/open`, AppleScript for Spotify/Music/Finder/Notes).
- **Layer 2**: Accessibility API (`AXUIElement`) element hierarchy traversal, action triggering (`kAXPressAction`), and text insertion (`kAXValueAttribute`).
- **Layer 3**: Synthetic input fallback (`CGEvent`) for custom canvas controls.
- **State Verification Loop**:
  - `verifyAppRunningAndFrontmost`: verifies process running and frontmost within 1.5 seconds.
  - `verifyMediaPlaybackState`: queries Spotify/Music `player state`.
  - `verifyVolumeLevel`: reads back actual output volume.

### D. Permissions Doctor UI (`PermissionsDoctorView.swift`)
- Integrated in Voice.AI Settings:
  - Live audit of Accessibility (`AXIsProcessTrusted()`) with deep links to `Privacy_Accessibility`.
  - Live audit of Microphone access with deep links to `Privacy_Microphone`.
  - Live audit of Screen Recording (`CGPreflightScreenCaptureAccess()`) with deep links to `Privacy_ScreenCapture`.
  - Live audit of Automation (Apple Events) with deep links to `Privacy_Automation`.
- Complete user manual provided in `docs/how-to-grant-permissions.md`.

