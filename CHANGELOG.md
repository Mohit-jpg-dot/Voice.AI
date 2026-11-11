# Changelog

All notable changes to **Voice.AI** are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Phase 2 — Proactive Assistant] - 2026-11-11

### Added
- **Proactive Alert Rules Engine** (`ProactiveRulesEngine.swift`, `ProactiveRuleManaging`, Windows `ProactiveRulesEngine.cs`): EventBus-driven, cooldown rate-limited rules raising dismissable alerts in the Notch HUD & Settings for low battery, high CPU/memory load, failed builds, calendar conflicts, and important emails.
- **Unified Calendar, Email & Messages Workflows** (`CalendarMessagesService.swift`, `CommunicationAndCalendarManaging`, `ToolRegistry.swift`): Added `calendar_summarize` (with conflict detection onto `EventBus`), `calendar_create_event`, `mail_summarize`, `messages_read`, `messages_draft`, and `messages_send` (`CONSEQUENTIAL` Notch Approval Card gated).
- **On-Device Local File & Knowledge Search (RAG)** (`LocalKnowledgeStore.swift`, `LocalKnowledgeSearching`, Windows `LocalKnowledgeEngine.cs`): Indexes user-chosen local folders with overlapping 520-char chunking, `SecretRedactor` secret scrubbing, and `LocalEmbeddingProvider` semantic search (`rag_search_files`, `rag_index_folder`).
- **Vision-Language Screen Understanding & Finished Circle-to-Ask Beacon** (`ScreenVisionService.swift`, `AutonomousAgentExecutor.swift`, `NotchGlassIslandView.swift`): Added `understandScreenQuestion` combining local/opt-in-cloud VLM with Apple Vision OCR diagnostics (`"What does this error mean?"`, `"Which button should I click?"`), visible On-Device/Cloud Opt-In privacy badge, and beacon chips.
- **Smart Home Integration (Home Assistant / HomeKit / MQTT)** (`SmartHomeManager.swift`, Windows `SmartHomeCoordinator.cs`, `KeychainService.swift`, `SecretRedactor.swift`): Keychain-backed credentials, JWT scrubbing, `REVERSIBLE` comfort device controls (`smarthome_control_comfort`), and strict `CONSEQUENTIAL` Notch Approval gating for locks/security alarms (`smarthome_control_security`).
- **Opt-In Apple Health & Wearables Import** (`HealthInsightsManager.swift`, Windows `HealthInsightsEngine.cs`, `SettingsView.swift`): Privacy-first opt-in `export.xml` & JSON importer, daily digest, wellness reminders, and automated trend warnings (elevated resting HR, sleep deficit, activity drop).
- **Automated Phase 2 Tests**: Added `Suite 35` in `Tests/core/test_core.swift` and `Suite 12` in `windows/tests/VoiceAI.Core.Tests/TestRunner.cs`.

---

## [Phase 1 — JARVIS Feel] - 2026-11-11

### Added
- **Configurable On-Device Wake-Word Detection** (`TheVoiceAmbientListener.swift`, `WakeWordDetecting`): Added customizable wake phrase (`jarvis` default, `friday`, `voice`, etc.) running with `requiresOnDeviceRecognition = true`, trailing English/Hindi/Hinglish command extraction, Settings UI picker, automatic barge-in on wake trigger, and `EventBus` wake events.
- **Streaming TTS with Barge-In & Selectable Voices** (`KokoroTTSEngine.swift`, `TTSServiceProtocol`, `SpeechPipelineEngine.swift`): Added sentence-chunked streaming speech playback backed by `ttsGeneration` cancellation, instant `bargeIn()` on hold-to-talk/wake-word/typed submission/UI stop, and `KokoroVoicePreset` selection (`af_heart`, `bm_george`, `bf_emma`, etc.).
- **Configurable JARVIS/FRIDAY Persona Layer** (`PersonaManager.swift`, `PersonaManaging`, `PersonaConfiguration`, Windows `PersonaEngine.cs`, `ToolApprovalCoordinator.swift`): Added configurable dry wit (`humorLevel`), honest success probability estimates and localized polite risk cautions on `CONSEQUENTIAL` Notch Approval Cards, and English/Devanagari Hindi/Roman Hinglish prompt adaptation.
- **Long-Term Memory Integration & Interactive Viewer** (`AutonomousAgentExecutor.swift`, `AppState.swift`, `NotchGlassIslandView.swift`, `SettingsView.swift`): Wired semantic long-term memory recall & short-term `.turn` persistence into LLM prompts, added `"remember this"` / `"forget this"` / `"what do you remember"` voice commands (plus Hindi/Hinglish equivalents), and built interactive search/filter/create/delete Memory Viewers in the Notch HUD and Settings.
- **Multi-Step Routines & Protocols** (`RoutineManager.swift`, `RoutineManaging`, Windows `RoutineEngine.cs`, `SettingsView.swift`): Added built-in `"Good Morning Briefing"`, `"Focus Mode Protocol"`, and `"House Party Protocol"` plus customizable editable multi-step user routines with English/Hindi/Hinglish trigger matching and `PermissionTier.consequential` approval gating.
- **Automated Phase 1 Tests**: Added `Suite 34` in `Tests/core/test_core.swift` and `Suite 11` in `windows/tests/VoiceAI.Core.Tests/TestRunner.cs`.

---

## [Phase 0 — Foundations] - 2026-11-11

### Added
- **MCP-Compatible Tool Registry & Permission Tiers** (`PermissionTier.swift`, `ToolRegistry.swift`, `MCPClientAdapter.swift`, Windows `ToolRegistry.cs`): Registered core abilities and app integrations with JSON Schema definitions, MCP `tools/list` export, JSON-RPC 2.0 `initialize`/`tools/list`/`tools/call` client discovery, and `READ_ONLY` / `REVERSIBLE` / `CONSEQUENTIAL` tiers.
- **Real Consequential Action Gate in Notch UI** (`ToolApprovalCoordinator.swift`, `AppState.swift`, `NotchGlassIslandView.swift`): Replaced the legacy stub in `approveCurrentAction()` with an async continuation gate (`ToolApprovalPresenting`) wired to the Notch Approval Card with tier badges, redacted parameter previews, and Cancel/Approve actions.
- **Typed System Event Bus** (`EventBus.swift`, Windows `EventBus.cs`): Thread-safe pub/sub event bus (`SystemEventKind`, `VoiceEvent`, `AsyncStream` & filtered subscriber tokens, 200-event ring buffer) with automatic payload secret scrubbing.
- **Encrypted Per-Account Semantic Memory Store** (`MemoryStore.swift`, `LocalEmbeddingProvider.swift`, Windows `SemanticMemoryStore.cs`): Short-term turns, long-term facts/preferences/projects/people, and user profile encrypted at rest per account via Keychain-bound AES-256 (macOS) / PBKDF2-AES (Windows) with local deterministic semantic embeddings (and optional local Ollama `/api/embeddings`).
- **Centralized Secret Redaction** (`SecretRedactor.swift`, Windows `SecretRedactor.cs`): Extended credential/token/webhook scrubbing across `EncryptedChatHistoryManager`, `VoiceOSTelemetry`, `EventBus`, and `MemoryStore`.
- **Automated Phase 0 Tests**: Added `Suite 33` in `Tests/core/test_core.swift` and `Suite 10` in `windows/tests/VoiceAI.Core.Tests/TestRunner.cs`.

---

## [1.0.0] - 2026-11-06

### Added
- **Dynamic Adaptive Notch Sizing**: Auto-extending and auto-shrinking notch HUD window (`540pt` to `680pt` width, `118pt` to `480pt` height) adapting smoothly to answer length, completely eliminating text truncation and scroll clipping.
- **Interactive Web Source Buttons**: Direct one-click glass buttons (`Open on Wikipedia ↗`, `Open on Google Web Search ↗`) embedded inside answer cards to view full sources in the user's default browser.
- **Now Playing Media Dynamic Island**: Flanking wings displaying active playback title, artist, audio visualizer bars, and media controls for Spotify and YouTube.
- **Voice Playback Commands**: Added voice controls (*"play the current video"*, *"pause it"*, *"change it to next"*, *"previous"*, *"video chalao"*, *"gana badlo"*).
- **Coding Agents Monitor**: Real-time dashboard in the Notch displaying active background coding subagents, completed task checklists, execution timers, and interactive question approval buttons.
- **Google Search Free Mode (Lightweight, No LLM)**: Zero-cost factual search engine combining Google Custom Search API, MediaWiki extracts, Open-Meteo real-time weather, and instant offline mathematical evaluation.
- **Expanded Hindi & Hinglish Command Grammar**: 125 verified colloquial patterns for computer control, music playback, app switching, and volume management.
- **Unified Release Packaging**: Automated single DMG installer (`build/Voice.AI-1.0.0.dmg`) with verified SHA-256 checksums and Sparkle appcast generation.

### Changed
- Refactored `MathEngine` to support conversational Hindi/Hinglish phrasing (`"kitna hota hai"`, `"kya hoga"`, `"into"`, `"bhaag"`) and trailing question marks without syntax errors.
- Enhanced Wikipedia search fallback to use official MediaWiki Action and generator APIs, bypassing Cloudflare REST rate gates.
- Updated `NotchHUDWindowController` canvas dimensions to `700pt × 560pt` for ample visual breathing room.

### Fixed
- Fixed text clipping in compact pill answers where long search descriptions were cut off at line endings.
- Fixed `NSAppleScript` synchronous hang during command-line testing by wrapping automation in 1.5-second timeout safeguards.
- Fixed generic media command disambiguation to dynamically resolve to YouTube when an active video is playing.

