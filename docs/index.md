# Voice.AI Documentation Sitemap

Welcome to the internal engineering documentation and architectural records for **Voice.AI**.

---

## 1. Getting Started & Setup Guides
- [App Integrations Setup Guide (All Apps)](../set-up-guide.md) — Unified in-app setup guide for Gmail, Apple Mail, Slack, Discord, WhatsApp, Spotify, and more.
- [Setup with Cloud API Key](setup-api-key.md) — Walkthrough for configuring OpenAI, Anthropic Claude, or Google Gemini.
- [Setup 100% Free & Offline (Ollama + Whisper)](setup-free-offline.md) — Automated in-app download and hardware verification for offline neural models.
- [Setup Google Search Free Mode](setup-google-search-key.md) — Zero-cost, lightweight factual query mode without local neural weights.
- [How to Grant macOS Permissions](how-to-grant-permissions.md) — Accessibility, Microphone, and Automation permission guides.

---

## 2. Technical Architecture & Decisions
- [Google Search Free Mode Decision Record](google-mode-decision.md) — Analysis of ToS-compliant search methods, rule-based classification, and fallback priority.
- [AI Brain Cloud vs Ollama Architecture](setup-cloud.md) — Unified `ChatModel` protocol, streaming chunk delivery, and memory persistence.
- [Notch Geometry & Animation Analysis](notch-study/README.md) — Mathematical reference on concentric corner radii, liquid glass materials, and non-blocking click-through testing.
- [Hindi & Hinglish Grammar Rules](hindi-control-report.md) — 125 colloquial sentence patterns, phonetic transliteration, and intent dispatching.

---

## 3. Verification & Test Reports
- [Core Architecture Test Report](test-report.md) — 184 automated tests across tokens, hotkey timing, connectors, and computer control.
- [Google Search Only Test Report](test-report-google-mode.md) — 83 tests verifying verbatim extraction, no hallucinations, and quota tracking.
- [Auth & Onboarding Test Report](test-report-setup.md) — 41 tests verifying Keychain isolation, setup flow routing, and credential management.
- [Diagnostic Audit](diagnosis.md) — Root-cause fixes and system stability analysis.

