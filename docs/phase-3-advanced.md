# Phase 3: Advanced Capabilities & Security Architecture

Phase 3 completes the Voice.AI JARVIS/FRIDAY roadmap across macOS (`VoiceOSCore` + `VoiceOSApp`) and Windows (`VoiceAI.Core`) while keeping prohibited out-of-scope items (suit control, flight, weapons, satellite/battlefield scanning) completely excluded.

---

## 1. Iron Legion Mode (Parallel Subagents)

- **macOS (`Sources/VoiceOSCore/Agents/IronLegionCoordinator.swift`)** & **Windows (`windows/VoiceAI.Core/Agents/IronLegionCoordinator.cs`)**:
  - Protocol: `IronLegionCoordinating` / `IIronLegionCoordinator`.
  - Executes parallel `TaskGroup` workers (`Research`, `Code`, `Summarize`) anchored to `LocalKnowledgeStore` / `MemoryStore` and local/cloud model routers.
  - Registers and streams step progress into `CodingAgentManager.shared` so every Iron Legion unit appears live inside the Notch **Agents** tab (`iron_legion_dispatch`, `REVERSIBLE`).

## 2. Engineering Studio: Parametric CAD, Physics & 3D Hologram Viewer

- **macOS (`Sources/VoiceOSCore/Engineering/EngineeringStudioEngine.swift`, `Sources/VoiceOSApp/Views/HologramViewerView.swift`)** & **Windows (`EngineeringStudioEngine.cs`)**:
  - Generates parametric **OpenSCAD** (`.scad`) and **CadQuery** (`.py`) geometry scripts (`bracket`, `gear`, `enclosure`, `heatsink`).
  - Runs deterministic engineering physics simulations (`simulateProjectile`, `simulateSpringHarmonic`, `simulateThermal`).
  - Renders interactive wireframe 3D models inside a self-contained offline `WKWebView` hologram viewport (`HologramViewerView`).

## 3. Cyber Defense Monitor & Emergency Lockdown

- **macOS (`Sources/VoiceOSCore/Security/CyberDefenseMonitor.swift`)** & **Windows (`CyberDefenseEngine.cs`)**:
  - Protocol: `CyberDefenseMonitoring` / `ICyberDefenseEngine`.
  - Inspects listening ports/processes (`lsof` / `netstat`) and ARP LAN neighbors for suspicious binaries, high-risk listener ports, and newly joined LAN MAC addresses, publishing `security_anomaly` alerts on `EventBus` (`security_anomaly_scan`, `READ_ONLY`).
  - `executeLockdown()` (`security_lockdown`) locks the display, mutes microphone input, and disables Wi-Fi — strictly guarded at `PermissionTier.consequential` (Notch Approval Card + dry-run safe in tests).

## 4. Local-Only Opt-In Camera Vision & Gesture Control

- **macOS (`Sources/VoiceOSCore/Vision/LocalCameraVisionService.swift`)**:
  - Disabled by default (`isCameraOptedIn == false`); requires explicit opt-in with a clear on-device-only privacy guarantee.
  - Performs local Apple Vision object classification (`VNClassifyImageRequest`) and hand gesture dispatch (`thumbs_up`, `thumbs_down`, `open_palm`, `pinch`).
  - Local face recognition requires a **second explicit opt-in** (`isFaceRecognitionEnabled`) and persists only salted SHA-256 hashed templates on-device with one-click wipe (`wipeFaceTemplates()`).

## 5. Phone Remote Companion Bridge

- **macOS (`Sources/VoiceOSCore/Companion/PhoneCompanionService.swift`)** & **Windows (`PhoneCompanionCoordinator.cs`)**:
  - Implements short-lived 6-digit PIN pairing (`beginPairing` / `completePairing`), Keychain-bound bearer tokens (`.companionSharedSecret`), authenticated remote dictation forwarding, and an `EventBus`-backed approval notification/response bridge (plus optional local `NWListener` LAN HTTP server).

## 6. Runtime Plugin & MCP Loader

- **macOS (`Sources/VoiceOSCore/Marketplace/UserPluginManager.swift`)** & **Windows (`UserPluginLoader.cs`)**:
  - Loads external JSON plugin manifests (`~/.voiceos/plugins/*.json` or programmatic manifests) into `ToolRegistry.shared` at runtime without modifying core code, supporting declarative tools and MCP server auto-discovery via `MCPClientAdapter`.

