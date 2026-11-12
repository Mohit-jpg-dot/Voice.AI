<div align="center">

# Voice.AI

**A voice-first AI agent that controls your computer.**
Speak in English, Hindi, or Hinglish. Voice.AI opens apps, operates your browser and terminal, understands what is on your screen, and works with cloud models, fully offline local models, or a zero-key search mode.

[![macOS 14+](https://img.shields.io/badge/macOS-14.0%2B-0071e3.svg)](#installation)
[![Windows 11](https://img.shields.io/badge/Windows%2011-preview-0078d4.svg)](#windows-preview)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-native-black.svg)](#installation)
[![macOS tests](https://img.shields.io/badge/macOS%20tests-342%2F342-34c759.svg)](#testing)
[![Windows core tests](https://img.shields.io/badge/Windows%20core-114%2F114-34c759.svg)](#testing)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

[Website](https://mohit-jpg-dot.github.io/Voice.AI/) ·
[Docs Hub](website/docs.html) ·
[हिन्दी](README.hi.md) ·
[Changelog](CHANGELOG.md) ·
[Contributing](CONTRIBUTING.md)

</div>

---

## Table of contents

- [Overview](#overview)
- [Project status](#project-status)
- [Features](#features)
- [AI modes](#ai-modes)
- [Voice command reference](#voice-command-reference)
- [Installation](#installation)
- [Building from source](#building-from-source)
- [Testing](#testing)
- [Security and privacy](#security-and-privacy)
- [Roadmap](#roadmap)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

Voice.AI lets you do real work on your computer by speaking. It combines three layers:

1. **Fast local intent routing.** Common commands in English, Hindi, and Hinglish are matched on-device in under 10 ms, with no model call.
2. **A conversational brain.** Anything open-ended goes to the model you choose: a cloud provider with your own API key, a local Ollama model, or a free search-based mode.
3. **A computer-use operator.** For open-ended goals, the agent looks at the screen, decides on the next action, and performs it, repeating until the task is done.

Consequential actions, such as sending a message or deleting files, always stop for your explicit approval first.

---

## Project status

Voice.AI states plainly what is verified and what is still in progress.

| Area | Status |
|:--|:--|
| macOS native app | Working |
| Windows shared core (`VoiceAI.Core`, .NET) | Working, 114/114 tests passing |
| Windows 10/11 WinUI 3 shell | In development |
| In-app one-click offline model downloader | In development |
| Deep in-browser DOM video scraping | In development |
| Live interactive QA of computer-use mode on real apps | Pending manual QA |

Computer-use mode passes its automated headless checks (see [Testing](#testing)). Interactive end-to-end checks on live macOS apps, with Accessibility and Screen Recording permissions granted, are tracked in [real-test.md](real-test.md).

---

## Features

### Voice control

- **Hindi and Hinglish fast path.** More than 125 colloquial patterns handled locally in under 10 ms, for example *"WhatsApp kholo"*, *"Spotify band karo"*, and *"Aawaz kam karo"*. Verified on 125 test utterances.
- **Media control.** Play, pause, next, and previous for Spotify and active YouTube tabs.
- **Offline math engine.** Arithmetic, percentages, powers, and roots evaluated in under 5 ms with no tokens and no internet.
- **Wake word and speech.** Configurable on-device wake word, streaming text-to-speech, and mid-sentence barge-in.

### Dictation

- **Universal dictation.** Hold `fn` (or `⌘`) for 250 ms or more, speak, and release. Filler words are removed and the text is inserted into whichever app has focus. Short taps pass through untouched.
- **Clipboard dictation.** Press `fn + D` (or `⌘⇧C`), speak, and the cleaned text is copied to the clipboard with a short confirmation in the notch. Paste it anywhere with `⌘V`.

### Model switching by voice

Change the model behind every reply in the middle of a conversation:

- *"Switch to smaller local model"* selects the lightweight local Ollama model.
- *"Switch to larger local model"* selects the larger local Ollama model.
- *"Switch to Claude"*, *"go to ChatGPT"*, or *"use paid models"* routes to your configured cloud model.

### Computer-use operator (`⌃` Control key)

An iterative see, decide, act loop that works on any open-ended screen goal, such as *"click the blue submit button"*. It is implemented natively in Swift (`ComputerUseOperator`) and .NET (`ComputerUseLoopEngine`).

- Retina and DPI-normalized coordinates, plus Accessibility UI actions
- Hard limits of 15 steps and 90 seconds per task
- On-screen text wrapped in `<UNTRUSTED_SCREEN_DATA>` so it is treated as data, never as instructions
- Corner failsafe, and an immediate halt on `Esc` or the spoken words "stop" or "ruko"
- Redacted `audit.json` and per-step screenshots saved to `~/.voiceos/computer_use_logs/`
- Destructive, payment, and send steps blocked behind approval cards

### Safety approvals

High-impact actions are intercepted before any keystroke is sent. An approval card in the notch shows the exact payload, with **Cancel** and **Approve** buttons.

### Notch interface (macOS)

- **Adaptive HUD** that grows and shrinks to fit each answer, so responses are never truncated.
- **Now Playing wings** with a live equalizer, app glyph, and track title for Spotify and YouTube.
- **Clickable source pills** that open Wikipedia and Google citations in your browser.
- **Coding agents monitor.** See running subagents (Claude Code, Antigravity, local agents) with checklists and elapsed time, and answer their questions by voice.

### Platform capabilities

| Capability | Description |
|:--|:--|
| MCP tool registry | MCP-compatible registry with permission tiers |
| Event bus | Typed publish/subscribe foundation |
| Memory | Encrypted semantic memory with recall and a viewer UI |
| Routines | Multi-step routines and protocols |
| Proactive alerts | Rules engine driven by the event bus |
| Workflows | Calendar, email, and messages (macOS) |
| Local search | On-device file search and retrieval (RAG) |
| Screen understanding | Vision-language model, Apple Vision OCR, and "Circle to Ask" (macOS) |
| Smart home | Home Assistant, HomeKit, and MQTT |
| Health | Opt-in Apple Health import and warnings |
| Subagents | Parallel subagents ("Iron Legion") |
| Engineering | CAD, physics, and 3D hologram viewer |
| Cyber defense | Defense scan and lockdown gate |
| Camera | Opt-in local camera and gesture vision (macOS) |
| Phone companion | Remote approval bridge |
| Plugins | Runtime plugin and MCP manifest loader |
| Persona | JARVIS/FRIDAY persona with risk warnings |

---

## AI modes

| | Cloud API | Offline local | Google Search only |
|:--|:--:|:--:|:--:|
| **Cost** | Your own API key | Free | Free |
| **Internet** | Required | Not required | Required (light HTTP) |
| **Memory footprint** | About 45 MB | About 4 GB | About 35 MB |
| **Reasoning** | Full generative | Local model | Deterministic fact extraction |
| **Knowledge** | Model cutoff | Model cutoff | Live web with citations |
| **Computer control** | Full | Full | Full |
| **Status** | Working | Manual daemon setup | Working |

Cloud mode supports OpenAI, Anthropic, and Gemini with your own keys. Offline mode uses Ollama and Whisper. The zero-key mode combines MediaWiki extracts, Open-Meteo weather, and Google CSE with source citations.

---

## Voice command reference

### Media

| Say | Result |
|:--|:--|
| "Play the current video" / "Video chalao" | Starts the active video |
| "Pause karo" / "Pause the music" | Pauses Spotify or YouTube |
| "Change it to next" / "Agla gana chalao" | Next track |
| "Previous track" / "Pichhla video" | Previous track |

### System and apps

| Say | Result |
|:--|:--|
| "Open Safari" / "WhatsApp kholo" | Launches and focuses the app |
| "Close the app" / "Spotify band karo" | Quits the app |
| "Turn down the volume" / "Aawaz kam karo" | Adjusts volume |
| "Adjust brightness to 70%" / "Screen light badhao" | Adjusts brightness |
| "Take a screenshot" / "Screenshot lo" | Captures the screen to the clipboard |

### Dictation, models, and computer use

| Input | Result |
|:--|:--|
| `fn + D` or `⌘⇧C` | Dictate to the clipboard |
| "Switch to smaller local model" / "Chote model pe jao" | Smaller local model |
| "Switch to larger local model" / "8b model chalao" | Larger local model |
| "Go to Claude" / "Use paid models" | Cloud model |
| `⌃` Control, then a goal | Runs the computer-use loop |
| `Esc`, or "stop" / "ruko" | Halts the loop immediately |

### Knowledge and math

| Say | Result |
|:--|:--|
| "What is 25 * 4?" / "25 into 4 kitna hota hai" | `100` |
| "What is 15 percent of 80?" | `12` |
| "Square root of 144" | `12` |
| "What is photosynthesis?" | Summary with a source pill |
| "What is the weather in Delhi?" | Live temperature from Open-Meteo |

---

## Installation

### macOS

Requires macOS 14.0 (Sonoma) or later on Apple Silicon.

1. Download [Voice.AI-1.0.0.dmg](website/downloads/Voice.AI-1.0.0.dmg). A [SHA-256 checksum](website/downloads/Voice.AI-1.0.0.dmg.sha256) is published next to it so you can verify the download.
2. Open the disk image and drag **Voice.AI.app** into **Applications**.
3. Launch the app and follow onboarding to pick an AI mode and grant **Accessibility** and **Microphone** permissions. Computer-use mode also needs **Screen Recording**. See [how to grant permissions](docs/how-to-grant-permissions.md) if a prompt does not appear.

### Windows (preview)

The shared core and service adapters live in [`windows/VoiceAI.Windows`](windows/VoiceAI.Windows) (WinUI 3 and C#). The native GUI shell is still in development. See the [Windows developer setup](docs/windows-dev-setup.md) to build with Visual Studio 2022 and .NET 8, and the [offline setup guide](docs/setup-free-offline-windows.md) for local models.

---

## Building from source

```bash
git clone https://github.com/Mohit-jpg-dot/Voice.AI.git
cd Voice.AI

./scripts/build-app.sh     # build VoiceOSCore and Voice.AI.app
./scripts/make-dmg.sh      # package the release DMG
```

---

## Testing

```bash
./scripts/run-tests.sh core      # 342/342 (suites 1-39)
./scripts/run-tests.sh brain     # 28/28
./scripts/run-tests.sh google    # 83/83
./scripts/run-tests.sh hindi     # 125/125
./scripts/run-tests.sh auth      # 37/41 in an offline sandbox
```

The `auth` suite scores 37/41 offline because suites 3 and 5 need host disk access and a live network.

Windows core suite (.NET):

```powershell
dotnet run --project windows/tests/VoiceAI.Core.Tests/VoiceAI.Core.Tests.csproj --no-restore   # 114/114
```

Interactive computer-use test cases are in [real-test.md](real-test.md).

---

## Security and privacy

- **Accessibility API.** Used only to find focused text fields, inspect UI structure, and insert text.
- **Microphone.** Audio is processed on-device with Apple Speech or local Whisper. Raw recordings are never uploaded.
- **Screen Recording.** Used on demand for offline text recognition with Apple Vision. Pixels stay on your device.
- **Credentials.** API keys are stored in the macOS Keychain (`ai.voice.app.auth`) or Windows Credential Manager (DPAPI). Keys found in conversation logs are replaced with `[REDACTED_API_KEY]` before saving.
- **Storage.** Each account's history and preferences are kept in a separate PBKDF2 and AES-GCM encrypted store.
- **Approvals.** Sending, deleting, and payment actions always need explicit approval.
- **Prompt injection.** Text read from the screen is treated as untrusted data and never as a command.

---

## Roadmap

- [ ] Windows 10/11 WinUI 3 native shell (floating island UI, low-level keyboard hook, WASAPI microphone streaming, UIPI elevation handling)
- [ ] One-click offline model downloader that fetches, verifies, and launches Ollama and Whisper
- [ ] Multi-monitor animated "Circle to Ask" beacon overlay
- [ ] Deep in-browser DOM video scraping without browser accessibility warnings
- [ ] Live interactive QA of computer-use mode on real macOS apps

---

## Documentation

- [Docs hub (all guides)](website/docs.html)
- [Cross-platform architecture](docs/architecture-cross-platform.md)
- Architecture phases: [Phase 0 foundations](docs/phase-0-foundations.md) · [Phase 1 JARVIS feel](docs/phase-1-jarvis-feel.md) · [Phase 2 proactive assistant](docs/phase-2-proactive-assistant.md) · [Phase 3 advanced](docs/phase-3-advanced.md)
- Setup guides: [Cloud API](docs/setup-cloud.md) · [API keys](docs/setup-api-key.md) · [Ollama (local models)](docs/setup-ollama.md) · [Free offline mode](docs/setup-free-offline.md) · [Google Search key](docs/setup-google-search-key.md)
- [How to grant permissions](docs/how-to-grant-permissions.md)
- [Computer-use QA matrix](real-test.md)
- [Windows parity and test report](docs/test-report-windows.md)
- [Documentation sitemap](docs/index.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)

---

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request, run the relevant test suite for the area you change, and follow the [Code of Conduct](CODE_OF_CONDUCT.md). To report a vulnerability, see [SECURITY.md](SECURITY.md) instead of opening a public issue.

---

## License

Released under the [MIT License](LICENSE). Copyright © 2026 Voice.AI Team.