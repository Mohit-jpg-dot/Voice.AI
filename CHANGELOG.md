# Changelog

All notable changes to **Voice.AI** are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Messaging Connectors (Slack, Discord, WhatsApp)] - 2026-11-13

### Added
- **First-Class Messaging Protocol & Architecture** (`MessagingConnector.swift`, `IMessagingConnector.cs`):
  - Created platform-agnostic `MessagingConnector` protocol / interface for authentication, conversation listing, fuzzy contact resolution, message dispatch, thread replies, emoji reactions, unread message scanning, search, channel navigation, and status updates.
  - Implemented `ContactResolver` with Hindi/English/Hinglish transliteration matching (e.g. "Rahul" / "राहुल" / "Rahool"), spoken phone digit normalization, custom alias memory caching ("call him Bunty"), and multi-candidate ambiguity detection (*"Which Rahul? Rahul Sharma or Rahul Verma?"*).
  - Implemented `MessagingRouter` with local fast-path utterance routing ("Slack pe", "on Discord", "WhatsApp se"), fallback to last-used platform, and rate-limiting (max 10 sends/minute).
- **Three Enterprise Connectors**:
  - `SlackConnector`: Official Slack Web API using OAuth User Tokens (`chat:write`, `channels:read`, `im:read`, `search:read`, `reactions:write`, etc.) stored in Keychain `ai.voice.app.auth`.
  - `DiscordConnector`: Official Discord Bot REST endpoints adhering strictly to Discord Terms of Service (zero self-bots/user tokens). Personal DMs fall back to driving Discord Desktop via macOS Accessibility with consequential approval.
  - `WhatsAppConnector`: Dual backends combining (a) official WhatsApp Business Cloud API with 24-hour customer window error code 131047 detection and template guidance, and (b) native desktop app backend via `whatsapp://send?phone=...&text=...` deep-linking and Accessibility typing. Zero unofficial reverse-engineered libraries.
- **Security & Safety Guardrails**:
  - Consequential Notch Approval Card mandatory for every message send, post, or delete.
  - Incoming message content wrapped and isolated in `<UNTRUSTED_MESSAGE_DATA>` with malicious prompt injection neutralization (`[REDACTED_PROMPT_INJECTION]`).
  - Spoken *"stop"* / *"ruko"* and Esc cancel in-flight sends and UI loops immediately.
- **UI & Settings Integration**:
  - Added Messaging Connectors card in `SettingsView.swift` with token management, connection status, test-connection buttons, and scope explanations.
- **Automated Verification**:
  - Added `Suite 56` (14 new tests) in `Tests/core/test_core.swift` (547 total passing).
  - Added new Hindi messaging utterances to `tests/hindi_commands/dataset.json` (131 total passing at 100% intent accuracy).
  - Added `Suite 17` in `windows/tests/VoiceAI.Core.Tests/TestRunner.cs` (149 total passing).
- **Documentation**:
  - Added `docs/setup-slack.md`, `docs/setup-discord.md`, and `docs/setup-whatsapp.md`.
  - Updated `real-test.md`, `SECURITY.md`, `THIRD_PARTY_NOTICES.md`, and `README.md`.

---

## [Voice Email (Draft, Send, Reply, Watch)] - 2026-11-12

### Added
- **Ordered Email Backends & Capability Probe** (`EmailService.swift`): Added `EmailService` protocol, `EmailAddressHelper` (spoken address normalization & Levenshtein lookalike check), `MailAppEmailBackend`, `GmailAPIEmailBackend` (Keychain OAuth, minimal scopes), `IMAPSMTPEmailBackend`, `MailtoDraftFallbackBackend` (draft-only, never reported as sent), and `MockEmailService`.
- **Dictated Drafts, Replies, Approvals & Watch Rules** (`VoiceEmailManager.swift`, `ToolRegistry.swift`, `AutonomousAgentExecutor.swift`, `ProactiveRulesEngine.swift`, `AppState.swift`, `SettingsView.swift`):
  - Persistent encrypted `EmailDraft`s and `WatchRule`s (survive restarts), macOS Contacts disambiguation, `.consequential` approval card for every send/reply/forward, 10 s configurable undo window, 5-in-10m rate limit, `<UNTRUSTED_EMAIL_DATA>` wrapping, 60 s watch polling with exponential backoff, and `"replied while you were away"` launch alerts (no auto-reply).
- **Automated Tests & Windows Core Parity**: Added `Suite 54` in `Tests/core/test_core.swift` (`MockEmailService`), `VoiceEmailLogic.cs` + `Suite 16` in `windows/tests/VoiceAI.Core.Tests/TestRunner.cs`, and 11 live manual QA checks in `real-test.md` (live machine tests pending manual QA).

---

## [Safe Voice Terminal & Persistent Local Memory] - 2026-11-12

### Added
- **Safe Voice Terminal Control** (`CommandPolicy.swift`, `SafeTerminalEngine.swift`, `ToolRegistry.swift`, `AutonomousAgentExecutor.swift`, `SettingsView.swift`, Windows `CommandPolicy.cs`):
  - Registered single `.consequential` tool `run_terminal_command(command, working_directory, purpose)` and routed legacy shell/system paths through `SafeTerminalEngine` or native telemetry (`LiveHostTelemetrySnapshot` / `FileManager`).
  - Added real `ShellTokenizer` + `PathPolicy` (`realpath` canonicalization against `~/Desktop`, `~/Documents`, `~/Downloads`, `~/VoiceAI-Workspace` + manual Settings roots) + `CommandPolicy` (`BLOCKED`, `NEEDS_APPROVAL`, `READ_ONLY`) + command/directory SHA-256 `bindingHash`.
  - Added `TrashDeletionPlanner` (Trash-only deletion with dry-run summary and second confirmation for folders or >20 items), `undoLastCommand()`, `SandboxedProcessRunner` (scrubbed `PATH`/`HOME`/`LANG`, `setpgid`/`kill(-pgid, SIGKILL)` on 30s timeout or `"stop"`/`"ruko"`, 64 KB cap), `<UNTRUSTED_COMMAND_OUTPUT>` + `SecretRedactor`, live-mic-only approval gating (rejecting TTS echo/screen/file text), and Keychain/AES-256 encrypted daily command audit logs (`EncryptedChatHistoryManager`).
  - Added **Safe Voice Terminal & Sandbox** settings in `SettingsView.swift` (`Auto-run read-only commands` OFF by default, `Command Timeout` 30s default, manual `Add Folder...` picker, custom CLI allowlist).
- **Persistent Local Memory & Session Continuity** (`MemoryStore.swift`, `EncryptedChatHistoryManager.swift`, `AppState.swift`, `AutonomousAgentExecutor.swift`, `SettingsView.swift`, Windows `SemanticMemoryStore.cs`):
  - Enforced explicit-consent-only `.longTerm` fact storage (`explicitConsent: false` default on `recordConversationExchange`), `isInstructionLikeMemory` rejection, `SecretRedactor` scrubbing, `WorkingContextState`, rolling session summary compaction (`messages.count > 12`), `<UNTRUSTED_MEMORY_CONTEXT>` retrieval, active session ID persistence across restarts, and voice session commands (`start a new session`, `continue where we left off`, `open the session about ...`, `rename this session to ...`, `what commands did you run today`, `undo that`).
- **Automated Tests**: Added `Suite 52` & `Suite 53` in `Tests/core/test_core.swift`, and `Suite 15` in `windows/tests/VoiceAI.Core.Tests/TestRunner.cs` (live mic audio/UI/real macOS filesystem & Finder Trash behavior remain pending manual QA in `real-test.md`).

---

## [Phase 3 — Advanced] - 2026-11-11

### Added
- **Iron Legion Mode** (`IronLegionCoordinator.swift`, `IronLegionCoordinating`, Windows `IronLegionCoordinator.cs`, `NotchGlassIslandView.swift`): Spawns and coordinates parallel `Research`, `Code`, and `Summarize` subagents streaming live into `CodingAgentManager` and the Notch **Agents** tab (`iron_legion_dispatch`).
- **Engineering Studio: CAD, Physics & 3D Hologram Viewer** (`EngineeringStudioEngine.swift`, `HologramViewerView.swift`, Windows `EngineeringStudioEngine.cs`): Generates parametric OpenSCAD (`.scad`) and CadQuery (`.py`) scripts, runs deterministic projectile/harmonic/thermal physics sims, and renders offline `WKWebView` 3D wireframe holograms in **Settings → Lab & Security**.
- **Cyber Defense & Emergency Lockdown** (`CyberDefenseMonitor.swift`, Windows `CyberDefenseEngine.cs`): Scans listening ports/processes & ARP LAN neighbors for new devices (`security_anomaly_scan`), and gates Emergency Lockdown (lock screen, mute mic, disable Wi-Fi) strictly at `CONSEQUENTIAL` tier (`security_lockdown`).
- **Opt-In Local-Only Camera Vision & Gestures** (`LocalCameraVisionService.swift`): Strictly opt-in (`isCameraOptedIn == false` by default) on-device Apple Vision object detection, reversible hand gesture controls, and separate explicit opt-in hashed local face templates with one-click wipe.
- **Phone Remote Companion** (`PhoneCompanionService.swift`, Windows `PhoneCompanionCoordinator.cs`, `KeychainService.swift`): Completed 6-digit PIN pairing, Keychain bearer tokens, authenticated remote dictation relay, live `EventBus` approval notifications/resolution, and optional LAN HTTP bridge.
- **Runtime Plugin & MCP Loader** (`UserPluginManager.swift`, Windows `UserPluginLoader.cs`): Loads external JSON plugin manifests (`~/.voiceos/plugins/*.json`) and MCP servers dynamically into `ToolRegistry` without modifying core code.
- **Automated Phase 3 Tests**: Added `Suite 36` in `Tests/core/test_core.swift` and `Suite 13` in `windows/tests/VoiceAI.Core.Tests/TestRunner.cs` (including out-of-scope verification).

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

