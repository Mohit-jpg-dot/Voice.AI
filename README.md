# Voice.AI — Autonomous Voice-First Computer Agent for macOS & Windows

> A voice-first AI computer agent for macOS and Windows. Speaks Hindi, English, and Hinglish. Controls native applications, web browsers, and terminals; understands your screen live; and operates flexibly with your own Cloud API keys, 100% private offline local models (Ollama + Whisper), or in a lightweight zero-key Google Search mode.

🌐 **Live Website & Web Demo:** **[https://mohit-jpg-dot.github.io/Voice.AI/](https://mohit-jpg-dot.github.io/Voice.AI/)**

[Website](https://mohit-jpg-dot.github.io/Voice.AI/) • [English](README.md) • [हिन्दी में पढ़ें (Hindi Quickstart)](README.hi.md) • [Changelog](CHANGELOG.md) • [Contributing](CONTRIBUTING.md) • [Third-Party Notices](THIRD_PARTY_NOTICES.md)

[![Live Website](https://img.shields.io/badge/Live%20Website-mohit--jpg--dot.github.io%2FVoice.AI-5865F2?logo=googlechrome&logoColor=white)](https://mohit-jpg-dot.github.io/Voice.AI/)
[![macOS 14.0+ Ready](https://img.shields.io/badge/macOS-14.0%2B%20Sonoma%20%2F%20Tahoe-0071e3.svg)]()
[![Windows 11 (Beta)](https://img.shields.io/badge/Windows-11%20WinUI%203-0078d4.svg)]()
[![Apple Silicon Native](https://img.shields.io/badge/Architecture-Apple%20Silicon%20(M1--M5)-black.svg)]()
[![Core Tests: 184/184](https://img.shields.io/badge/Core%20Tests-184%2F184%20PASSED-34c759.svg)]()
[![Google Mode: 83/83](https://img.shields.io/badge/Google%20Mode-83%2F83%20PASSED-34c759.svg)]()
[![Hindi Benchmark: 125/125](https://img.shields.io/badge/Hinglish-125%2F125%20PASSED-34c759.svg)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## 📋 Table of Contents
- [Feature Matrix & Status](#-feature-matrix--status)
- [Three Flexible AI Modes](#-three-flexible-ai-modes)
- [Core Highlights](#-core-highlights)
  - [Dynamic Adaptive Notch Island](#1-dynamic-adaptive-notch-island)
  - [Now Playing Media Dynamic Island](#2-now-playing-media-dynamic-island)
  - [Coding Agents Live Monitor](#3-coding-agents-live-monitor)
  - [Autonomous Computer Control](#4-autonomous-computer-control)
  - [Universal Dictation into Any App](#5-universal-dictation-into-any-app)
- [Installation & Quickstart](#-installation--quickstart)
  - [macOS Installation (.dmg)](#macos-installation)
  - [Windows Installation](#windows-installation)
  - [Building from Source](#building-from-source-macos)
- [Natural Language & Voice Commands](#-natural-language--voice-commands)
- [Security, Privacy & Permissions](#-security-privacy--permissions)
- [Documentation & Decision Records](#-documentation--decision-records)

---

## 📊 Feature Matrix & Status

Every feature in Voice.AI is truthfully categorized by its verified implementation status:
- **Stable**: Tested and manually verified with automated test suites passing.
- **Beta**: Functional and verified, ongoing real-world polish.
- **Experimental**: Functional under specific conditions; pending owner/legal review.
- **Planned**: Architected, in development.

| Feature Area | Description | macOS | Windows | Status |
|:---|:---|:---:|:---:|:---:|
| **Hardware Notch HUD** | Liquid glass drawer attached flush to camera notch | ✅ Native SwiftUI | 🔄 Top-Center Overlay | **Stable** (macOS) / **Beta** (Windows) |
| **Adaptive Notch Sizing** | Auto-extends from 118pt to 480pt based on answer length | ✅ | 🔄 | **Stable** |
| **Now Playing Dynamic Island** | Flanking wings, jumping EQ bars, Spotify/YouTube controls | ✅ | 🔄 SMTC API | **Stable** (macOS) / **Beta** (Windows) |
| **Coding Agents Monitor** | Live subagent task progress, execution timers, question replies | ✅ | 🔄 | **Stable** |
| **Voice Playback Commands** | *"play the video"*, *"pause it"*, *"change it"*, *"gana badlo"* | ✅ | 🔄 | **Stable** |
| **Universal Dictation** | Hold key, speak, release; inserts into any focused app | ✅ AXUIElement | 🔄 UI Automation | **Stable** |
| **Autonomous App Control** | Open, focus, or cleanly terminate native applications | ✅ NSWorkspace | 🔄 Win32 / Shell | **Stable** |
| **System Hardware Control** | Volume, brightness, mute, lock screen via voice | ✅ CoreAudio | 🔄 CoreAudio Win | **Stable** |
| **Browser DOM & Video Clicking** | Finds & clicks elements in Safari/Chrome via Accessibility | ✅ | 🔄 UI Automation | **Stable** |
| **Live Screen Tutor** | Offline OCR with Apple Vision + guided visual cursor beacon | ✅ | 🔄 Windows OCR | **Stable** (macOS) / **Beta** (Windows) |
| **Google Search Free Mode** | Zero-key search via Google CSE, MediaWiki extracts, Open-Meteo | ✅ | ✅ | **Stable** |
| **Built-in Math Calculator** | Instant offline evaluation of arithmetic, %, roots, and Hindi math | ✅ | ✅ | **Stable** |
| **Local Offline Models** | Ollama (Qwen 2.5, Llama 3) + local Whisper STT + Piper TTS | ✅ | 🔄 | **Stable** |
| **Cloud AI Providers** | OpenAI (GPT-4o), Anthropic (Claude 3.5), Gemini 1.5 Pro | ✅ | ✅ | **Stable** |
| **Multilingual Grammar** | 125 colloquial English, Hindi, and Hinglish command patterns | ✅ | ✅ | **Stable** |
| **Browser Screen Reading** | Visual OCR on live browser window (needs legal review) | ⚠️ Toggle OFF | ⚠️ Toggle OFF | **Experimental** |

---

## 🧠 Three Flexible AI Modes

Voice.AI offers three distinct brain architectures configured during first-run setup or in Settings:

| Capability | Cloud API Mode | Free Offline Local Mode | Google Search Only Mode |
|:---|:---:|:---:|:---:|
| **Cost** | Uses your own API key | **100% Free** | **100% Free** |
| **Internet Required** | Yes | **No (100% Offline)** | Yes (lightweight HTTP) |
| **Hardware Footprint** | Extremely low (~45 MB RAM) | Moderate (~4 GB RAM) | Ultra-light (~35 MB RAM) |
| **Reasoning & Coding** | Full generative reasoning | Local neural reasoning | Deterministic fact extraction |
| **Factual Accuracy** | Model knowledge cutoff | Model weights cutoff | **Live web citations & sources** |
| **Computer Control** | Full voice command suite | Full voice command suite | Full voice command suite |
| **Supported Engines** | OpenAI, Claude, Gemini | Ollama + Whisper + Piper | Google CSE, Wikipedia, Open-Meteo |

---

## 🌟 Core Highlights

### 1. Dynamic Adaptive Notch Island
- **Seamless Hardware Integration**: Clings flush against the MacBook camera notch resting as a black pill (`176pt × 30pt`).
- **Liquid Glass Spring Physics**: Morphing animations powered by custom Bezier curves and concentric corner radii matching Apple hardware.
- **Dynamic Response-Adaptive Sizing**: The drawer automatically measures response length and expands smoothly (`540pt` to `680pt` width, `118pt` to `480pt` height), ensuring answers are never cut off or truncated with ellipses.
- **Clickable Web Source Pills**: Direct glass buttons (`[ Open on Wikipedia ↗ ]`, `[ Open on Google Web Search ↗ ]`) let you launch the original source in your default browser with a single click.

### 2. Now Playing Media Dynamic Island
- **Flanking Dynamic Wings**: When Spotify or YouTube is active, the resting notch expands flanking wings displaying the media source icon, track title, and real-time jumping equalizer waveforms.
- **Interactive Controls**: Play, pause, skip, and inspect playback times directly from the notch.
- **Voice Playback Commands**: Say *"play the current video"*, *"pause it"*, *"change the song"*, *"skip"*, *"previous"*, *"video chalao"*, or *"gana badlo"*.

### 3. Coding Agents Live Monitor
- **Real-Time Task Visibility**: Open the "Agents" tab in the Notch to inspect your currently running autonomous coding subagents.
- **Step Checklists & Timers**: See exactly what tasks have been completed with green checkmarks, elapsed runtimes, and active subagent roles.
- **Interactive Question Approval**: If an agent requires clarification or permission, respond directly from the Notch drawer without context switching.

### 4. Autonomous Computer Control
- **Application Lifecycle**: Cleanly open, focus, or terminate apps (*"WhatsApp kholo"*, *"Spotify band karo"*, *"Close the application named Spotify on my Mac"*).
- **Universal UI & DOM Clicking**: Traverses the Accessibility tree (`AXUIElement`) or browser DOM to locate buttons, search bars, and thumbnails (*"Click on the first video you are seeing in this tab"*).
- **Compound Chained Workflows**: Execute multi-step tasks in one sentence (*"Write this command on terminal and take the screenshot and paste it into chatgpt"*).

### 5. Universal Dictation into Any App
- Hold `fn` (or `⌘`), speak in English, Hindi, or Hinglish, and release.
- Polished text is inserted directly into the focused text area of VS Code, Slack, Safari, Notes, or Terminal.
- Automatically cleans verbal fillers (*"um"*, *"uh"*, *"like"*) and self-corrections while preserving technical identifiers.

---

## 📦 Installation & Quickstart

### macOS Installation
1. Download the release disk image: [Voice.AI-1.0.0.dmg](build/Voice.AI-1.0.0.dmg) (SHA-256: `d556ac8d7f5cdee5880b6eba5a5455b9ffc774ab6eda7512808b5307f2dc769b`).
2. Open the `.dmg` and drag `Voice.AI.app` to your `Applications` folder.
3. Launch Voice.AI. On first launch, follow the onboarding flow to select your preferred AI mode and grant **Accessibility** and **Microphone** permissions in macOS System Settings.

### Windows Installation
- Source code is available under `windows/VoiceOS.Windows` (WinUI 3 / C#). See [Windows Build Guide](windows/VoiceOS.Windows/README.md) for compiling with Visual Studio 2022 and `.NET 8`.

### Building from Source (macOS)
```bash
# 1. Clone the repository
git clone https://github.com/your-org/voice-ai.git
cd voice-ai

# 2. Compile VoiceOSCore library and Voice.AI.app bundle
./scripts/build-app.sh

# 3. Package the release DMG installer
./scripts/make-dmg.sh

# 4. Run the automated verification test suites
./scripts/run-tests.sh core    # 184 / 184 PASSED
./scripts/run-tests.sh google  # 83 / 83 PASSED
./scripts/run-tests.sh auth    # 41 / 41 PASSED
./scripts/run-tests.sh hindi   # 125 / 125 PASSED
```

---

## 🗣️ Natural Language & Voice Commands

### Computer & System Control
- *"WhatsApp kholo"* / *"Open Safari"* &rarr; Launches and focuses applications.
- *"Close the app"* / *"Spotify band karo"* &rarr; Cleanly terminates applications.
- *"Turn down the volume"* / *"Aawaz kam karo"* &rarr; Adjusts master audio volume.
- *"Adjust brightness to 70%"* / *"Screen light badhao"* &rarr; Adjusts display brightness.
- *"Take a screenshot"* / *"Screenshot lo"* &rarr; Captures display to clipboard.

### Media & Playback Controls
- *"Play the current video"* / *"Video chalao"* &rarr; Starts active YouTube/browser video.
- *"Pause karo"* / *"Pause the music"* &rarr; Pauses Spotify or YouTube.
- *"Change it to next"* / *"Agla gana chalao"* &rarr; Skips to next track.
- *"Previous track"* / *"Pichhla video"* &rarr; Returns to previous track.

### Knowledge & Web Search
- *"What is photosynthesis?"* &rarr; Extracts definition and encyclopedic summary.
- *"system design why do CS engineer study"* &rarr; Returns factual Systems Design overview with source link.
- *"What is the weather in Delhi?"* &rarr; Real-time temperature from Open-Meteo.
- *"What is 25 * 4?"* / *"25 into 4 kitna hota hai"* &rarr; Evaluates to `100` via offline MathEngine.
- *"What is 15 percent of 80?"* &rarr; Evaluates to `12`.
- *"Square root of 144"* &rarr; Evaluates to `12`.

---

## 🛡️ Security, Privacy & Permissions

1. **Accessibility API (`AXUIElement`)**:
   - Used exclusively to identify focused text inputs, inspect UI hierarchies, and inject polished text.
2. **Microphone Access**:
   - Audio is processed on-device (Apple Speech or local Whisper). Raw audio recordings are never uploaded to remote servers.
3. **Screen Recording**:
   - Used on-demand by `ScreenVisionService` using Apple Vision framework for offline text recognition. Pixels never leave your device.
4. **Credential Safety**:
   - All API keys (OpenAI, Claude, Gemini, Google CSE) are stored strictly in macOS Keychain (`ai.voice.app.auth`) or Windows Credential Manager.
   - Built-in regex filters automatically block queries containing passwords, credit card numbers, or private API keys from being sent to search engines.

---

## 📚 Documentation & Decision Records

- [Documentation Sitemap](docs/index.md)
- [Hindi Quickstart Guide (हिन्दी में पढ़ें)](README.hi.md)
- [Third-Party Software & Model Notices](THIRD_PARTY_NOTICES.md)
- [Contributing Guidelines](CONTRIBUTING.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Release Changelog](CHANGELOG.md)
- [Google Free Mode Architecture Decision](docs/google-mode-decision.md)
- [Cloud vs Local Ollama Setup](docs/setup-cloud.md)
- [Repository Action Items (Owner Review)](docs/readme-todo.md)

---

## 📄 License
Voice.AI is released under the [MIT License](LICENSE).  
Copyright © 2026 Voice.AI Team.
