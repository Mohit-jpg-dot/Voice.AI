# Phase 2: Proactive Assistant Architecture & Documentation

Phase 2 turns Voice.AI from a reactive command runner into a proactive, locally-grounded assistant across macOS (`VoiceOSCore` + `VoiceOSApp`) and Windows (`VoiceAI.Core`), while keeping audio, local files, health data, and screen pixels on-device by default.

---

## 1. Proactive Alert Rules Engine (`ProactiveRulesEngine`)

- **macOS (`Sources/VoiceOSCore/Proactive/ProactiveRulesEngine.swift`)** & **Windows (`windows/VoiceAI.Core/Proactive/ProactiveRulesEngine.cs`)**:
  - Protocol: `ProactiveRuleManaging` / `IProactiveRuleEngine`.
  - Subscribes to typed `EventBus` streams and evaluates configurable rules:
    1. `low_battery` (battery level <= threshold, not charging)
    2. `high_cpu_memory` (CPU or memory pressure >= threshold)
    3. `failed_build` (`SystemEventKind.buildStatusChanged` with `status == "failed"`)
    4. `calendar_conflict` (`SystemEventKind.calendarUpcoming` with `conflict == "true"`)
    5. `important_email` (`email_arrived` marked important or urgent)
  - **Rate Limiting & Dismissal**: Per-rule `cooldownSeconds` suppresses duplicate spam alerts; individual alerts can be dismissed from the Notch Alert Strip or **Settings → Proactive & Home**, and each rule's enable state/threshold is persisted.

## 2. Unified Calendar, Email & Messages Workflows (`CalendarMessagesService`)

- **macOS (`Sources/VoiceOSCore/Connectors/CalendarMessagesService.swift`)** & `ToolRegistry`:
  - Protocol: `CommunicationAndCalendarManaging`.
  - Registered tools & strict permission tiers:
    - `calendar_summarize` (`READ_ONLY`): Summarizes today's/weekly schedule and detects overlapping calendar conflicts onto `EventBus`.
    - `calendar_create_event` (`REVERSIBLE`): Schedules events via Apple Calendar.
    - `mail_summarize` (`READ_ONLY`), `mail_check_inbox` (`READ_ONLY`), `mail_draft` (`REVERSIBLE`), `mail_send` (`CONSEQUENTIAL`).
    - `messages_read` (`READ_ONLY`), `messages_draft` (`REVERSIBLE`), `messages_send` (`CONSEQUENTIAL` gated via Notch Approval Card).

## 3. On-Device Local File & Knowledge Search (RAG)

- **macOS (`Sources/VoiceOSCore/Knowledge/LocalKnowledgeStore.swift`)** & **Windows (`windows/VoiceAI.Core/Knowledge/LocalKnowledgeEngine.cs`)**:
  - Protocol: `LocalKnowledgeSearching` / `ILocalKnowledgeEngine`.
  - User-chosen folders are indexed locally using overlapping 520-character chunks across Markdown, text, source code, JSON, CSV, and logs.
  - Every chunk passes through `SecretRedactor.redact(...)` before local embedding (`LocalEmbeddingProvider`) and storage. Zero file content is uploaded off-device.
  - Registered tools: `rag_search_files` (`READ_ONLY`), `rag_index_folder` (`REVERSIBLE`).

## 4. Vision-Language Screen Understanding & Circle-to-Ask Beacon

- **macOS (`ScreenVisionService.swift`, `AutonomousAgentExecutor.swift`, `NotchGlassIslandView.swift`)**:
  - `ScreenVisionService.understandScreenQuestion(...)` augments Apple Vision OCR with an optional VLM (local Ollama Vision by default, or Cloud VLM **only** when Cloud mode or explicit `hasUserConsentedToCloudUpload` opt-in is enabled).
  - Handles diagnostic questions like *"What does this error mean?"* and *"Which button should I click?"* with extracted UI button recommendations and a visible **On-Device / Opt-In Cloud** privacy badge inside the finished Circle-to-Ask Beacon HUD.

## 5. Smart Home Integration (Home Assistant / HomeKit / MQTT)

- **macOS (`Sources/VoiceOSCore/SmartHome/SmartHomeManager.swift`)** & **Windows (`windows/VoiceAI.Core/SmartHome/SmartHomeCoordinator.cs`)**:
  - Protocol: `SmartHomeManaging` / `ISmartHomeCoordinator` with pluggable `SmartHomeTransport`.
  - Credentials (`homeAssistantToken`, `mqttPassword`) are stored exclusively in Keychain (`KeychainService`) and Home Assistant JWT tokens are scrubbed via `SecretRedactor`.
  - **Strict Permission Tiers**:
    - `smarthome_status` (`READ_ONLY`)
    - `smarthome_control_comfort` (`REVERSIBLE`): Lights, thermostat setpoints, scenes.
    - `smarthome_control_security` (`CONSEQUENTIAL`): Smart locks and security alarms always require explicit Notch Approval Card confirmation.

## 6. Opt-In Apple Health & Wearables Import

- **macOS (`Sources/VoiceOSCore/Health/HealthInsightsManager.swift`)** & **Windows (`windows/VoiceAI.Core/Health/HealthInsightsEngine.cs`)**:
  - Strictly **opt-in** (`isOptedIn` defaults to `false`).
  - Parses Apple Health `export.xml` (`StepCount`, `HeartRate`, `RestingHeartRate`, `ActiveEnergyBurned`, `SleepAnalysis`) and JSON files locally on-device.
  - Computes daily digests, wellness reminders (`health_add_reminder`), and trend warnings (elevated resting HR, sleep deficit, sudden step drop).

