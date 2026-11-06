# Contributing to Voice.AI

Thank you for your interest in contributing to Voice.AI! We welcome issues, pull requests, and discussions from the open-source community.

---

## 1. Code of Conduct

All contributors and maintainers are expected to adhere to our [Code of Conduct](CODE_OF_CONDUCT.md). Please treat everyone with respect and empathy.

---

## 2. Development Setup

### macOS Prerequisites
- macOS 14.0+ (Sonoma, Sequoia, Tahoe) on Apple Silicon (M1–M5).
- Xcode 15.0+ or CommandLineTools (`xcode-select --install`).
- Swift 5.9+ / Swift 6 toolchain.
- `bash`, `node` (for packaging scripts), and `python3`.

### Getting Started
```bash
# Clone the repository
git clone https://github.com/your-org/voice-ai.git
cd voice-ai

# Build the macOS application bundle
./scripts/build-app.sh

# Run the automated verification test suites
./scripts/run-tests.sh all
```

---

## 3. Repository Structure

```
├── Sources/
│   ├── VoiceOSCore/       # Core headless framework: Brain, Audio, Platform, Connectors
│   └── VoiceOSApp/        # Native SwiftUI + AppKit frontend: Notch, Settings, Setup
├── Tests/                 # Automated verification test suites
│   ├── core/              # 184 core architecture & motion tests
│   ├── google_mode/       # 83 Google Free Mode tests
│   ├── auth/              # 41 Credential, Keychain & Setup tests
│   └── hindi/             # 125 Hindi & Hinglish phonetic tests
├── scripts/               # Build, packaging, test runners, and DMG generation
├── windows/               # Windows C# / WinUI 3 implementation (Beta)
└── docs/                  # Architecture specifications and technical decision records
```

---

## 4. Coding & Testing Guidelines

1. **Test-Driven Rigor**: Any new tool, grammar parser, or audio pipeline change must include automated unit tests under `Tests/`.
2. **Deterministic Offline Fallbacks**: Voice commands for hardware (volume, brightness, music, opening apps) must work 100% offline without requiring any cloud model or network connection.
3. **Clean-Room & Honesty**: Never overclaim capabilities. Mark features honestly as **Stable**, **Beta**, **Experimental**, or **Planned**.
4. **Zero Secrets in Code**: Never commit credentials, private tokens, or test keys. Placeholders must strictly use `YOUR_KEY_HERE`.

---

## 5. Submitting Pull Requests

1. Fork the repository and create a feature branch (`git checkout -b feature/my-new-feature`).
2. Verify all test suites pass:
   ```bash
   ./scripts/run-tests.sh core
   ./scripts/run-tests.sh google
   ./scripts/run-tests.sh auth
   ./scripts/run-tests.sh hindi
   ```
3. Commit with clear, descriptive messages following [Conventional Commits](https://www.conventionalcommits.org/):
   - `feat(notch): add adaptive response height calculation`
   - `fix(audio): prevent speech recognizer timeout during pause`
   - `test(math): add test cases for hindi conversational arithmetic`
4. Push to your branch and open a Pull Request using the provided PR template.

