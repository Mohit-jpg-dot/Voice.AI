# Phase 1: JARVIS Feel Architecture & Documentation

Phase 1 adds natural conversational presence, hands-free wake-word responsiveness, adaptive personality, semantic long-term memory recall, and multi-step routines across both the macOS Swift client and the Windows `.NET` (`VoiceAI.Core`) shared brain.

---

## 1. Configurable On-Device Wake-Word Detection

- **macOS (`TheVoiceAmbientListener.swift`)**:
  - Protocol: `WakeWordDetecting` (`isListening`, `wakePhrase`, `extractCommand(from:wakePhrase:)`).
  - Runs 100% on-device speech recognition (`SFSpeechAudioBufferRecognitionRequest.requiresOnDeviceRecognition = true`) alongside hold-to-talk (`fn` / `⌘`).
  - Default configurable wake phrase (`"jarvis"`) plus `"voice"` alias; supports English, Hindi, and Roman Hinglish trailing commands (e.g. `"Jarvis, open Terminal"`, `"jarvis gana bajao"`).
  - Triggering the wake phrase automatically invokes `SpeechPipelineEngine.shared.bargeIn()` so the user can interrupt mid-sentence and emits `SystemEventKind.custom("wake_word_triggered")` on `EventBus`.
  - Configurable in **Settings → Voice & Wake-Word**.

## 2. Streaming TTS & Barge-In

- **macOS (`KokoroTTSEngine.swift` & `SpeechPipelineEngine.swift`)**:
  - Protocol: `TTSServiceProtocol` with selectable neural voice presets (`KokoroVoicePreset`: `af_heart`, `bm_george`, `bf_emma`, `am_adam`, `am_michael`, `af_bella`, `af_sarah`) persisted via `KokoroTTSEngine.shared.selectedVoiceId`.
  - **Low-latency chunking**: `SpeechPipelineEngine.splitIntoSpeakableChunks(_:)` breaks multi-sentence responses at sentence/clause boundaries and queues them behind an atomic `ttsGeneration` counter.
  - **Mid-sentence Barge-In**: `SpeechPipelineEngine.shared.bargeIn()` clears queued speech chunks, increments `ttsGeneration`, stops `KokoroTTSEngine` / `AVSpeechSynthesizer` immediately, and emits `"tts_barge_in"` on `EventBus`. Automatically invoked when pressing hold-to-talk, speaking the wake word, or submitting a typed prompt.

## 3. Configurable Persona Layer (JARVIS / FRIDAY)

- **macOS (`PersonaManager.swift` & `ToolApprovalCoordinator.swift`)**:
  - Protocol: `PersonaManaging`; `PersonaType` (`jarvis`, `friday`, `ultron`, `roast`) with `PersonaConfiguration` (`humorLevel`, `honestProbabilityEstimates`, `politeWarningsEnabled`, `languageStyle` = `auto | en | hi | hinglish`).
  - `systemPromptDirectives(forUserQuery:)` detects English, Devanagari Hindi, or Roman Hinglish automatically and shapes system prompts.
  - `assessActionConfidenceAndWarning(toolName:tier:target:languageHint:)` attaches candid success probability estimates and localized safety cautions to Notch Approval Cards for `.consequential` tools (`terminal_run`, external mail/messaging).
- **Windows (`windows/VoiceAI.Core/Brain/PersonaEngine.cs`)**:
  - `IPersonaEngine` & `PersonaEngine` mirror the same configuration, English/Hindi/Hinglish directives, and risk assessment APIs.

## 4. Long-Term Memory Integration & Interactive Viewer

- **Voice Commands (`AutonomousAgentExecutor.swift`)**:
  - `"Remember this..."` / `"Remember that..."` / `"yaad rakhna..."` stores facts directly into encrypted per-account `MemoryStore` (`.longTerm`) and updates live UI via `EventBus` (`.memoryUpdated`).
  - `"Forget..."` / `"bhool jao..."` removes matching semantic entries.
  - `"What do you remember..."` recalls and summarizes saved long-term facts.
  - Short-term conversation turns (`.turn`) and top semantic long-term matches are injected automatically into LLM brain & Fn prompts.
- **UI Viewers (`NotchGlassIslandView.swift` & `SettingsView.swift`)**:
  - Upgraded the Notch **Memory** tab with scope filtering (`Long-Term`, `Short-Term`, `Sessions`), live semantic search, quick `"Remember"` input, and per-item `"Forget"` delete controls.
  - Added a dedicated Long-Term Memory section inside **Settings → JARVIS & Routines**.

## 5. Multi-Step Routines & Protocols

- **macOS (`RoutineManager.swift`) & Windows (`RoutineEngine.cs`)**:
  - Protocols: `RoutineManaging` (`macOS`) and `IRoutineEngine` (`Windows`).
  - Built-in workflows: **Good Morning Briefing**, **Focus Mode Protocol**, and **House Party Protocol**, with English and Hindi/Hinglish triggers (`"good morning"`, `"suprabhat"`, `"focus mode"`, `"padhai mode"`, `"house party protocol"`, `"kaam khatam"`).
  - Editable in **Settings → JARVIS & Routines** (enable/disable, create custom multi-step routines, delete custom routines, run manually or by voice).
  - Any routine step assigned `PermissionTier.consequential` gates execution through `ToolApprovalCoordinator` (Notch Approval Card) before continuing.

