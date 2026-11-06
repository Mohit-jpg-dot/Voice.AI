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
- [Why Voice.AI? (Features Other Apps Don't Have)](#-why-voiceai-features-other-apps-dont-have)
- [Feature Matrix & Status](#-feature-matrix--status)
- [Three Flexible AI Modes](#-three-flexible-ai-modes)
- [Deep Dive: Standout Capabilities](#-deep-dive-standout-capabilities)
  - [1. Dynamic Adaptive Notch (Zero Text Truncation)](#1-dynamic-adaptive-notch-zero-text-truncation)
  - [2. Live Coding Agents Monitor Inside the Notch](#2-live-coding-agents-monitor-inside-the-notch)
  - [3. Now Playing Wings with Bi-Directional YouTube & Spotify Controls](#3-now-playing-wings-with-bi-directional-youtube--spotify-controls)
  - [4. Sub-10ms Colloquial Hinglish & Hindi Fast-Path Engine](#4-sub-10ms-colloquial-hinglish--hindi-fast-path-engine)
  - [5. Zero-Token Instant Deterministic Math Engine](#5-zero-token-instant-deterministic-math-engine)
  - [6. "Circle to Ask" Visual Beacon Screen Tutor](#6-circle-to-ask-visual-beacon-screen-tutor)
  - [7. Consequential Action Safety Guardrail (Visual Approvals)](#7-consequential-action-safety-guardrail-visual-approvals)
  - [8. Strict Per-Account Encrypted Isolation with Key Scrubbing](#8-strict-per-account-encrypted-isolation-with-key-scrubbing)
- [Installation & Quickstart](#-installation--quickstart)
  - [macOS Installation (.dmg)](#macos-installation)
  - [Windows Installation](#windows-installation)
  - [Building from Source](#building-from-source-macos)
- [Voice Commands Cheat Sheet](#-voice-commands-cheat-sheet)
- [Security, Privacy & Permissions](#-security-privacy--permissions)
- [Documentation & Decision Records](#-documentation--decision-records)

---

## 🚀 Why Voice.AI? (Features Other Apps Don't Have)

Most voice apps and desktop assistants are either glorified transcription tools (Whisper wrappers) or static chatbot overlays that cut off responses and require constant cloud subscriptions. **Voice.AI was engineered from scratch with unique capabilities not found in Siri, Windows Copilot, Boring Notch, or Superwhisper:**

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          VOICE.AI EXCLUSIVE ADVANTAGES                          │
├──────────────────────────────┬─────────────────────────────┬────────────────────┤
│ Capability                   │ Other Apps (Siri / Copilot) │ Voice.AI           │
├──────────────────────────────┼─────────────────────────────┼────────────────────┤
│ Notch UI Response Display    │ Fixed height; truncates ... │ Auto-adapts to 480pt│
│ Coding Agents Live Monitor   │ ❌ Not available            │ ✅ Built into Notch│
│ YouTube & Browser Media Voice│ ❌ App-only or broken       │ ✅ Real DOM/Media  │
│ Natural Hinglish Fast-Path   │ ❌ Fails on mixed grammar   │ ✅ Sub-10ms native │
│ Instant Math (Zero Tokens)   │ ❌ 2-3s Cloud LLM call      │ ✅ Instant offline │
│ "Circle to Ask" Screen Tutor │ ❌ Raw text dump            │ ✅ Guided visual beacon│
│ High-Impact Action Safety    │ ❌ Blind execution          │ ✅ Visual approval card│
│ Zero-Key Google Search Mode  │ ❌ Monthly subscription req.│ ✅ 100% Free       │
│ Per-Account Encrypted Silos  │ ❌ Shared plaintext files   │ ✅ AES PBKDF2 scrub│
└──────────────────────────────┴─────────────────────────────┴────────────────────┘
```

---

## 📊 Feature Matrix & Status

Every feature in Voice.AI is truthfully categorized by its verified implementation status:
- **Stable**: Tested and manually verified with automated test suites passing.
- **Beta**: Functional and verified, ongoing real-world polish.
- **Experimental**: Functional under specific conditions; pending owner/legal review.
- **Planned**: Architected, in development.

| Feature Area | What Makes It Unique | macOS | Windows | Status |
|:---|:---|:---:|:---:|:---:|
| **Adaptive Notch Sizing** | Dynamically expands from `118pt` to `480pt` height so long answers are never truncated | ✅ Native SwiftUI | 🔄 Top-Center Overlay | **Stable** (macOS) / **Beta** (Windows) |
| **Coding Agents Monitor** | Embedded task dashboard showing subagent checklists, execution clocks & question replies | ✅ | 🔄 | **Stable** |
| **Now Playing Dynamic Wings** | Flanking wings with jumping audio EQ + voice control for YouTube & Spotify | ✅ | 🔄 SMTC API | **Stable** (macOS) / **Beta** (Windows) |
| **Hinglish Fast-Path (125+)** | 125 colloquial Hindi & Hinglish command patterns recognized in sub-10ms | ✅ | ✅ .NET Core | **Stable** |
| **Zero-Token Math Engine** | Deterministic arithmetic, percentages, powers, roots, and Hindi math phrasing offline | ✅ | ✅ .NET Core | **Stable** |
| **"Circle to Ask" Screen Tutor**| Local OCR with animated pulsing visual cursor beacons guiding you step-by-step | ✅ Vision.framework | 🔄 Windows OCR | **Stable** (macOS) / **Beta** (Windows) |
| **Visual Action Safety Cards** | Consequential actions (WhatsApp, deletes) paused for visual human confirmation | ✅ | ✅ | **Stable** |
| **Free Google Search Mode** | Zero-key search combining Wikipedia action extracts, Open-Meteo, and Google CSE | ✅ | ✅ | **Stable** |
| **100% Offline Ollama Brain** | Fully private local LLM (Qwen/Llama) + local Whisper STT + local Neural TTS | ✅ | 🔄 | **Stable** |
| **Universal Dictation** | Hold key (250ms), speak, release; cleans fillers and injects directly into active app | ✅ AXUIElement | 🔄 SendInput / UIPI | **Stable** |
| **Encrypted Account Silos** | AES-GCM encrypted history with automatic `[REDACTED_API_KEY]` scrubbing | ✅ Keychain | ✅ DPAPI | **Stable** |

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

## 🌟 Deep Dive: Standout Capabilities

### 1. Dynamic Adaptive Notch (Zero Text Truncation)
- **The Problem in Other Apps**: Conventional notch clones and notification windows use fixed-size cards. When an answer is longer than three lines, text is either abruptly cut off with ellipses (`...`) or trapped inside a microscopic scrollable box.
- **The Voice.AI Solution**: The Notch Drawer dynamically calculates the rendered typography bounding box and smoothly expands along both axes (`540pt` to `680pt` width, `118pt` to `480pt` height) using Apple spring physics. Answers are 100% visible, beautifully formatted, and shrink back automatically for the next query.
- **Clickable Web Source Pills**: Includes interactive liquid glass pills (`[ Open on Wikipedia ↗ ]`, `[ Open on Google Web Search ↗ ]`) allowing one-click verification of source materials.

### 2. Live Coding Agents Monitor Inside the Notch
- **The Problem in Other Apps**: When autonomous coding agents (Claude Code, Antigravity, background subagents) run long tasks, developers must juggle terminal windows to check if the agent finished, errored, or is waiting for approval.
- **The Voice.AI Solution**: Voice.AI features an **Agents** tab directly inside the notch HUD:
  - **Live Progress Checklists**: Displays completed task steps with green checkmarks and active step spinners.
  - **Execution Clocks**: Displays exact elapsed runtimes for every active agent.
  - **Human-in-the-Loop Replies**: If a coding agent requires clarification or permission, answer by voice or tap directly within the notch drawer without context switching.

### 3. Now Playing Wings with Bi-Directional YouTube & Spotify Controls
- **The Problem in Other Apps**: "Dynamic islands" on desktop usually just show album art. If a user asks to play, pause, or change songs while watching a YouTube video in a background browser tab, other assistants fail.
- **The Voice.AI Solution**:
  - **Flanking Dynamic Wings**: When Spotify or YouTube is active, the resting notch smoothly expands flanking glass wings displaying the app glyph, track title, and jumping audio equalizer waveforms.
  - **Real Conversational Media Commands**: Speak naturally in English or Hinglish:
    - *"play the current video"* / *"video chalao"*
    - *"pause it"* / *"pause karo"*
    - *"change it to next"* / *"agla gana chalao"*
    - *"previous video"* / *"pichhla gana"*
  - Interacts directly with macOS NowPlaying / browser DOM and Windows System Media Transport Controls (SMTC).

### 4. Sub-10ms Colloquial Hinglish & Hindi Fast-Path Engine
- **The Problem in Other Apps**: Standard assistants require rigid, formal English or force users to switch their entire system language. Saying *"Spotify band karo"* or *"aawaz badhao"* causes Siri or Copilot to fail or perform an irrelevant web search.
- **The Voice.AI Solution**: Features a built-in deterministic grammar engine covering over 125 colloquial English, Hindi (Devanagari), and Romanized Hinglish patterns:
  - *"WhatsApp kholo"* &rarr; Launches WhatsApp.
  - *"Spotify band karo"* &rarr; Cleanly terminates Spotify.
  - *"Screen light thodi badhao"* &rarr; Increases display brightness.
  - *"Volume kam karo"* &rarr; Lowers master audio volume.
  - Operates locally with **sub-10ms execution latency** without waiting for cloud LLM roundtrips.

### 5. Zero-Token Instant Deterministic Math Engine
- **The Problem in Other Apps**: Asking an AI assistant *"what is 25 * 4?"* or *"15% of 80"* sends a request to an expensive cloud LLM, consuming API tokens and taking 2 to 3 seconds to generate an answer.
- **The Voice.AI Solution**: Intercepts mathematical queries and executes them locally via a deterministic offline engine:
  - Arithmetic: `25 * 4` &rarr; `100` (handles trailing question marks and Hindi phrasing like *"into ... kitna hota hai"*).
  - Percentages: `15% of 80` &rarr; `12`.
  - Powers & Roots: `2^8` &rarr; `256`, `square root of 144` &rarr; `12`.
  - Instantaneous response, zero token cost, zero cloud reliance.

### 6. "Circle to Ask" Visual Beacon Screen Tutor
- **The Problem in Other Apps**: Screen-aware assistants take a screenshot and reply with a wall of text ("click the button at the top right"), leaving the user confused.
- **The Voice.AI Solution**: 
  - Draw a quick circle, rectangle, or lasso around any button, error message, or diagram on your screen.
  - Voice.AI runs on-device OCR using Apple Vision / Windows OCR.
  - An animated **pulsing visual beacon** appears directly on your screen over the target button, guiding your cursor visually step-by-step.

### 7. Consequential Action Safety Guardrail (Visual Approvals)
- **The Problem in Other Apps**: Autonomous computer agents can be dangerously unpredictable, sending half-typed emails or deleting directories without confirmation.
- **The Voice.AI Solution**: Automatically classifies actions by risk level. Consequential actions (such as sending a message on WhatsApp or deleting files) are paused before execution:
  - Generates a high-contrast **Approval Card** inside the notch.
  - Displays the exact recipient and preview payload.
  - Requires an explicit voice confirmation (*"approve"* / *"yes"*) or button click before any keystrokes are sent.

### 8. Strict Per-Account Encrypted Isolation with Key Scrubbing
- **The Problem in Other Apps**: Multi-user or profile-based apps store chat histories and credentials in shared, unencrypted SQLite or JSON files where sensitive keys can leak.
- **The Voice.AI Solution**:
  - Every account's history is isolated in separate AES-PBKDF2 encrypted files.
  - Built-in credential sanitizers automatically scrub API keys matching regex patterns (`sk-...`, `Bearer ...`) replacing them with `[REDACTED_API_KEY]` before any text is written to persistent logs.

---

## 📦 Installation & Quickstart

### macOS Installation
1. Download the release disk image: [Voice.AI-1.0.0.dmg](website/downloads/Voice.AI-1.0.0.dmg) (Universal Apple Silicon Native).
2. Open the `.dmg` and drag `Voice.AI.app` to your `Applications` folder.
3. Launch Voice.AI. On first launch, follow the onboarding flow to select your preferred AI mode and grant **Accessibility** and **Microphone** permissions.

### Windows Installation
- Source code is available under [`windows/VoiceAI.Windows`](windows/VoiceAI.Windows) (WinUI 3 / C#). See [Windows Build Guide](docs/windows-dev-setup.md) for compiling with Visual Studio 2022 and `.NET 8`.
- Build the preview package:
  ```powershell
  cd windows\VoiceAI.Windows
  dotnet build -c Release
  ```

### Building from Source (macOS)
```bash
# 1. Clone the repository
git clone https://github.com/Mohit-jpg-dot/Voice.AI.git
cd Voice.AI

# 2. Compile VoiceOSCore library and Voice.AI.app bundle
./scripts/build-app.sh

# 3. Package the release DMG installer
./scripts/make-dmg.sh

# 4. Run the automated verification test suites
./scripts/run-tests.sh core    # 184 / 184 PASSED
./scripts/run-tests.sh google  # 83 / 83 PASSED
./scripts/run-tests.sh auth    # 41 / 41 PASSED
./scripts/run-tests.sh hindi   # 125 / 125 PASSED

# 5. Run the cross-platform .NET verification suite
dotnet run --project windows/tests/VoiceAI.Core.Tests/VoiceAI.Core.Tests.csproj # 40 / 40 PASSED
```

---

## 🗣️ Voice Commands Cheat Sheet

### Media & Playback Controls
- *"Play the current video"* / *"Video chalao"* &rarr; Resumes playback in active YouTube tab.
- *"Pause karo"* / *"Pause the music"* &rarr; Pauses Spotify or YouTube.
- *"Change it to next"* / *"Agla gana chalao"* &rarr; Skips to the next track.
- *"Previous track"* / *"Pichhla video"* &rarr; Rewinds or jumps to previous song.

### Computer Control & System Fast-Path
- *"WhatsApp kholo"* / *"Open Safari"* &rarr; Launches and focuses application.
- *"Close the app"* / *"Spotify band karo"* &rarr; Cleanly terminates application.
- *"Turn down the volume"* / *"Aawaz kam karo"* &rarr; Adjusts master audio volume.
- *"Adjust brightness to 70%"* / *"Screen light badhao"* &rarr; Adjusts display brightness.
- *"Take a screenshot"* / *"Screenshot lo"* &rarr; Captures display to clipboard.

### Instant Offline Math & Real-Time Knowledge
- *"What is 25 * 4?"* / *"25 into 4 kitna hota hai"* &rarr; Evaluates to `100` in < 5ms.
- *"What is 15 percent of 80?"* &rarr; Evaluates to `12`.
- *"Square root of 144"* &rarr; Evaluates to `12`.
- *"What is photosynthesis?"* &rarr; Summarizes scientific definition with encyclopedic source pill.
- *"What is the weather in Delhi?"* &rarr; Returns live temperature from Open-Meteo.

---

## 🛡️ Security, Privacy & Permissions

1. **Accessibility API (`AXUIElement` / `IUIAutomation`)**:
   - Used exclusively to identify focused text inputs, inspect UI hierarchies, and inject polished text.
2. **Microphone Access**:
   - Audio is processed on-device (Apple Speech or local Whisper). Raw audio recordings are never uploaded to remote servers.
3. **Screen Recording**:
   - Used on-demand by `ScreenVisionService` using Apple Vision framework for offline text recognition. Pixels never leave your device.
4. **Credential Safety**:
   - All API keys (OpenAI, Claude, Gemini, Google CSE) are stored strictly in macOS Keychain (`ai.voice.app.auth`) or Windows Credential Manager / DPAPI.
   - Built-in regex filters automatically block queries containing passwords, credit card numbers, or private API keys from being sent to external endpoints.

---

## 📚 Documentation & Decision Records

- [Cross-Platform Architecture Specification](docs/architecture-cross-platform.md)
- [Free & Offline Setup Guide (Windows)](docs/setup-free-offline-windows.md)
- [Windows Platform Parity & Test Report](docs/test-report-windows.md)
- [Windows Developer Toolchain Setup](docs/windows-dev-setup.md)
- [Documentation Sitemap](docs/index.md)
- [Hindi Quickstart Guide (हिन्दी में पढ़ें)](README.hi.md)
- [Third-Party Software & Model Notices](THIRD_PARTY_NOTICES.md)
- [Contributing Guidelines](CONTRIBUTING.md)
- [Release Changelog](CHANGELOG.md)

---

## 📄 License
Voice.AI is released under the [MIT License](LICENSE).  
Copyright © 2026 Voice.AI Team.
