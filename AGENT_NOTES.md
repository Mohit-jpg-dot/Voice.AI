# Voice.AI Architecture Notes (`self-heal/2026-11-11`)

Short reference summary recorded in Step 0 before running the real-world test plan.

## Entry Point & Run Modes
- **App Entry Point**: `Sources/VoiceOSApp/main.swift` launches Cocoa `NSApplication` and `AppDelegate` (`Sources/VoiceOSApp/App/AppDelegate.swift`), which manages the menu bar item, global hotkeys (`HotkeyManager`), Notch HUD (`NotchHUDWindowController`), and settings/setup windows.
- **Headless / Test-Input Path**: Adding `--text "<command>"` (with optional `--dry-run`) in `Sources/VoiceOSApp/main.swift` so automated verification can exercise the exact `AutonomousAgentExecutor` pipeline without audio hardware or GUI windows.

## Pipeline Layers (`Sources/VoiceOSCore`)
1. **Speech-to-Text (STT)**
   - `Platform/SpeechPipelineEngine.swift` captures mic input via `AVAudioEngine` and routes to Apple `SFSpeechRecognizer`, `LocalWhisperProvider`, or `Platform/STTProviderEngine.swift` (`DeepgramStreamingClient` / `AudioDeviceManager`).
   - `Platform/TheVoiceAmbientListener.swift` handles on-device ambient wake-word listening; `Platform/HotkeyManager.swift` detects `fn` hold-to-talk, `fn+D` clipboard dictation, `Control` agent mode, and `Esc` abort.
2. **Command Parser & Intent Layer**
   - `Platform/AutonomousAgentExecutor.swift` (`planAndExecute`) orchestrates fast interceptors in order: stop keywords -> `PersonaManager` safety guardrail -> `MemoryStore` ("remember"/"forget") -> `RoutineManager` -> `ModelRouter.switchModelByVoice` -> Phase 2 voice commands -> Circle-to-Ask VLM/OCR -> `Brain/MathEngine.swift` -> `AgentToolParser` -> `ComputerUseOperator` -> `Brain/LLMIntentOrchestrator.swift` -> `ModelRouter` chat or `GoogleSearchEngine`.
   - `Platform/AgentToolSchema.swift` defines `AgentTool` and `AgentToolParser.parse(query:)` (supporting English, Devanagari Hindi, and Roman Hinglish via `Platform/HinglishTransliterator.swift`).
3. **Action / Executor Layer**
   - `Platform/AgentActionDispatcher.swift` executes parsed `AgentTool` intents via `Platform/AccessibilityControlEngine.swift`, `Platform/UniversalTextInserter.swift`, `Connectors/AppIntegrationEngine.swift`, and `ComputerUse/ComputerUseOperator.swift`.
   - `Tools/ToolRegistry.swift`, `Tools/PermissionTier.swift` (`READ_ONLY`, `REVERSIBLE`, `CONSEQUENTIAL`), and `Platform/ToolApprovalCoordinator.swift` mediate confirmation prompts and fail-closed safety.
4. **Text-to-Speech (TTS)**
   - `Platform/SpeechPipelineEngine.swift` and `Platform/KokoroTTSEngine.swift` provide sentence-chunked streaming speech synthesis (`AVSpeechSynthesizer` / Kokoro-82M) with instant barge-in cancellation.

## Storage & Diagnostics
- Account-scoped encrypted storage (`Memory/EncryptedChatHistoryManager.swift`, `Memory/MemoryStore.swift`), Keychain secrets (`Brain/KeychainService.swift`), and `Security/SecretRedactor.swift`.

