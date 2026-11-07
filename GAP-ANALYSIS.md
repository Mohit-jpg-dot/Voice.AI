# VoiceOS Comprehensive Gap Analysis & Rebuild Audit

> **Source of Truth**: `APP-SECRET.md` (Teardown of VoiceOS v0.1.40)  
> **Audited Target**: Current VoiceOS Repository (`/Users/mohit/Downloads/voiceOs`)  
> **Audit Date**: 2026-11-07  
> **Status**: Phase 1 Complete — Awaiting Approval to Proceed to Phase 2

---

## 1. Executive Summary

This gap analysis provides an exhaustive, component-by-component audit comparing the current codebase against `APP-SECRET.md` (the reverse-engineered specification of the original VoiceOS `0.1.40` bundle).

The current project has built significant native macOS foundation layers in Swift (such as the Continuous Notch Glass Island, Screen Vision grounding, local Llama/Ollama orchestration, multi-lingual Hinglish transcribing, accessibility click engines, and menu bar overlays). However, there are major architectural discrepancies, missing IPC/preload contract boundaries, missing Supabase/ConnectRPC data schemas, absent SQLite metrics tables, and design token deviations that must be bridged to achieve 100% parity with the original VoiceOS.

---

## 2. Feature Gaps Audit

Status definitions:
- ✅ **Exists + Works**: Fully implemented with behavioral parity.
- ⚠️ **Exists but Broken/Partial**: Implemented partially, has diverging interfaces, or lacks edge-case handling.
- ❌ **Missing**: Not yet present in the current codebase.

### 2.1. Recording & Audio Subsystem
| Feature / Contract | Status | Current Codebase Location | Gap / Parity Analysis |
|---|:---:|---|---|
| Native Audio Recording (`startNativeRecording`, `stopNativeRecording`) | ⚠️ | `SpeechPipelineEngine.swift` | Captures microphone via `AVAudioEngine`, but lacks the explicit named IPC entrypoints, sample-rate negotiation (16kHz PCM), and backpressure buffer management. |
| Device Enumeration (`getNativeAudioDevices`, `getNativeAudioDevicesWithInfo`) | ❌ | None | Only queries system default microphone. Missing input device enumeration list and device change notifications. |
| Default Mic Name (`getDefaultMicrophoneName`) | ⚠️ | `AudioEngine` | Uses system default, but does not expose a discrete query returning the active CoreAudio device localized name. |
| Live Volume Metering Stream (`onVolumeUpdate`) | ⚠️ | `SpeechPipelineEngine.swift:35` | Computes audio levels for waveform rendering (`audioLevels`), but uses an internal Swift callback rather than the standardized `onVolumeUpdate` stream. |
| Buffer Streaming to Transcription | ⚠️ | `STTProviderEngine.swift` | Streams buffers to Apple Speech / local Whisper, but Deepgram-style binary WebSocket streaming chunker is not wired. |

### 2.2. Keyboard & Global Shortcut Pipeline
| Feature / Contract | Status | Current Codebase Location | Gap / Parity Analysis |
|---|:---:|---|---|
| Global Hotkey Listener (`startKeyListener`, `stopKeyListener`) | ✅ | `HotkeyManager.swift` | Global and local event taps catch `.flagsChanged` and `.keyDown` with 250ms tap vs. hold threshold. |
| Key Normalization (`fn`, `control-left`, `control-right`, `fn_fast`) | ⚠️ | `HotkeyManager.swift` | Normalizes Fn and Control keys, but does not yet handle `control-right` or `fn_fast` (HID keycode 179) normalization. |
| Key Blocking & Unblocking (`blockKeys`, `unblockKey`, `getBlockedKeys`) | ❌ | None | Hotkey manager listens to events passively; no active key suppression / interception table (`blockKeys`) exists. |
| Native Binary Error & Diagnostics (`getKeyListenerError`, `onNativeBinaryError`) | ❌ | None | Errors are printed to console; no structured diagnostic pipeline reporting native binary crashes. |
| Stock Dictation Migration & Conflict Check | ✅ | `HotkeyManager.swift:235` | Detects macOS default dictation shortcut conflicts and provides one-click fix via `defaults write`. |

### 2.3. Authentication & Session Management
| Feature / Contract | Status | Current Codebase Location | Gap / Parity Analysis |
|---|:---:|---|---|
| Supabase Auth Integration (`https://bqxtklamhmqgkixvgqhc.supabase.co`) | ⚠️ | `AccountAuthService.swift` | Implements local PBKDF2-SHA512 auth with PKCE Google OAuth, but does not connect to Supabase backend or support Supabase JWT verification. |
| Auth Code Exchange (`generateNewAuthState`, `exchangeAuthCode`) | ❌ | None | Missing the exact OAuth state generator and auth code exchange handlers. |
| Session Token Persistence (`window.electron.store.get("auth")`) | ⚠️ | `AccountAuthService.swift:95` | Tokens stored in Keychain under `voiceos.auth.session_token`, but not in a unified `auth` store structure. |
| Self-Hosted Flag (`isSelfHosted`) | ❌ | None | No flag or toggle allowing headless/self-hosted authentication bypass. |
| Auth View Routing (`WelcomeKit`, `OnboardingRecovery`, `HomeKit`, password reset) | ⚠️ | `SetupFlowView.swift` | Setup wizard exists, but component naming and state transitions do not match `WelcomeKit` vs `HomeKit` vs `OnboardingRecovery`. |

### 2.4. Windows, Overlays, Notches & Surfaces
| Feature / Contract | Status | Current Codebase Location | Gap / Parity Analysis |
|---|:---:|---|---|
| Continuous Notch Glass Island (`agent-notch-*`) | ✅ | `NotchGlassIslandView.swift`, `NotchHUDWindowController.swift` | Physical notch avoidance, response-adaptive morphing, resting wings, and spring transitions implemented. |
| Click-Through / Mouse Ignore (`pill-set-mouse-events`) | ⚠️ | `NotchHUDWindowController.swift` | Window toggles `ignoresMouseEvents`, but lacks precise mouse-tracking coordinates forwarding from renderer. |
| Window Corners & Liquid-Glass Material (`window_corners.node`) | ⚠️ | `NotchShape.swift`, `VisualEffectView.swift` | Modeled using SwiftUI shapes and NSVisualEffectView; native C++ `.node` corner module is not present. |
| Floating Voice Pill / Orb (`voiceos-widget:`) | ✅ | `FloatingOrbWindowController.swift`, `FloatingOrbView.swift` | Floating draggable voice orb with pulsing aura and drag gesture exists. |
| Spotlight History / Switcher (`spotlight:*`) | ⚠️ | `MainWindowView.swift`, `HistoryFullView.swift` | History and search exist in main window, but separate spotlight overlay window (`spotlight.start`) is missing. |

### 2.5. Text Injection, Media & System Actions
| Feature / Contract | Status | Current Codebase Location | Gap / Parity Analysis |
|---|:---:|---|---|
| Native Text Injection (`text-injector`) | ✅ | `UniversalTextInserter.swift`, `AccessibilityControlEngine.swift` | Clipboard paste with pre/post state restore and AXUIElement accessibility direct insertion. |
| Media Key Sender (`media-key-sender`) | ✅ | `AccessibilityControlEngine.swift`, `NowPlayingMediaManager.swift` | Sends hardware play/pause/skip keystrokes and controls Spotify / YouTube playback. |
| Apple Music Integration & User-Agent | ⚠️ | `NowPlayingMediaManager.swift` | AppleScript controls Apple Music, but missing the exact user-agent string `VoiceOS/AppleMusic (https://voiceos.com)`. |
| Calibrated Real Hardware Clicking | ✅ | `CalibratedClickEngine.swift` | Dual `.cgSessionEventTap` + `.cghidEventTap` mouse move + click with AppleScript fallback. |

### 2.6. Integrations, Composio & MCP
| Feature / Contract | Status | Current Codebase Location | Gap / Parity Analysis |
|---|:---:|---|---|
| Connected / Installed / Suggested Integrations Store | ⚠️ | `ConnectorRegistry.swift` | Hardcoded 24 connectors exist; dynamic local JSON/SQLite persistence of user integration state is incomplete. |
| Composio Integration & OAuth Logos (`https://logos.composio.dev/...`) | ⚠️ | `ConnectorRegistry.swift` | Connectors list actions and deep links, but Composio remote OAuth flow and remote logo resolution are missing. |
| MCP Server Discovery & Validation (`customMcpServers`, zod) | ⚠️ | `MCPHandshakeService.swift` | Introspects SSE/HTTP endpoints and synthesizes manifests; missing strict JSON-RPC schema validation and live execution pipeline. |
| Integration Tool Confirmation Dialog | ⚠️ | `AgentHubView.swift` | Prompts user before dangerous actions, but lacks the dedicated `integration-widget-tools:*` floating confirmation surface. |

### 2.7. Reminders, Calendar & Native Helpers
| Feature / Contract | Status | Current Codebase Location | Gap / Parity Analysis |
|---|:---:|---|---|
| Reminders Native Helper (`reminders-helper`) | ❌ | None | No dedicated EventKit / AppleScript reminders bridge executable. |
| Location Core (`location_core.node` / `location-now`) | ❌ | None | CoreLocation native lookup and deep link routing for Apple Maps / Google Maps is missing. |
| Window Text Reader (`window-text-reader`) | ⚠️ | `ScreenVisionService.swift` | Takes screen capture and runs vision OCR, but lacks fast native AXUIElement text extraction of the frontmost focused app. |

### 2.8. Local Storage, SQLite & Settings
| Feature / Contract | Status | Current Codebase Location | Gap / Parity Analysis |
|---|:---:|---|---|
| Electron Store Defaults (`config.json`) | ⚠️ | `UserSettings.swift`, `KeychainService.swift` | Settings are split across `UserDefaults` and Keychain rather than a unified `config.json` schema. |
| SQLite Database & Table `voice_session_insights` | ❌ | None | `voice_session_insights` table schema with index `idx_voice_session_insights_user` is not created. |
| Settings Toggles (`launchAtLogin`, `startInBackground`, `showInDock`, `auto-paste`, `shareUserData`) | ⚠️ | `SettingsView.swift` | Hotkeys, sounds, and models are configurable, but `launchAtLogin`, `startInBackground`, `showInDock`, and `auto-paste` toggles are missing. |
| Dictionary Synchronization (`UpdateDictionaryItemRequestSchema`) | ❌ | None | No custom pronunciation/spelling dictionary sync engine. |

### 2.9. ConnectRPC & Protobuf Schemas
| Schema Name in APP-SECRET.md | Status | Current Codebase Location | Gap / Parity Analysis |
|---|:---:|---|---|
| `StreamMessageSchema` | ❌ | None | Missing typed streaming response message schema. |
| `ScreenshotContextSchema` | ❌ | None | Missing typed screen context payload schema. |
| `MatchAppIntentRequestSchema` | ❌ | None | Missing typed intent matching request schema. |
| `ListVoiceSessionsRequestSchema` | ❌ | None | Missing voice session query schema. |
| `RecordVoiceSessionUsageRequestSchema` | ❌ | None | Missing session metrics usage schema. |
| `UpdateVoiceSessionRequestSchema` | ❌ | None | Missing voice session update schema. |
| `UpdateDictionaryItemRequestSchema` | ❌ | None | Missing dictionary item modification schema. |
| `ModeUpdateSchema` | ❌ | None | Missing mode transition event schema. |
| `WordModificationSchema` | ❌ | None | Missing word-level diff schema. |
| `file_voiceos` | ❌ | None | Missing protobuf package namespace definition. |

### 2.10. Rich Editor, Math & Telemetry
| Feature / Contract | Status | Current Codebase Location | Gap / Parity Analysis |
|---|:---:|---|---|
| TipTap / ProseMirror Rich Text Editor | ⚠️ | `DictationStudioView.swift` | Uses standard SwiftUI `TextField` / `TextEditor`; lacks rich formatting (lists, underline, highlight). |
| KaTeX Math Rendering | ❌ | None | Math syntax is displayed as raw text rather than formatted KaTeX equations. |
| Canvas Confetti Celebration | ❌ | None | Onboarding completion does not trigger celebratory confetti. |
| OpenDyslexic Font Option | ❌ | None | No dyslexic-friendly font toggle or stylesheet integration. |
| Sentry Error Reporting & Breadcrumbs | ❌ | None | No Sentry breadcrumb collection or error capture. |
| PostHog Product Telemetry | ❌ | None | PostHog events (`onboardingIntroPresented`, `recording_discarded`, etc.) are not emitted. |

---

## 3. Architecture Gaps Audit

```text
DOCUMENTED TARGET ARCHITECTURE (APP-SECRET.md):
┌─────────────────────────────────────────────────────────────┐
│ Electron Main Process / Native Host                         │
│ - Window Managers (Notch, Widget, Spotlight, Dashboard)     │
│ - Native Helpers (keyboard-listener, text-injector, etc.)   │
│ - SQLite3 (voice_session_insights, dictionary, sessions)    │
│ - electron-store (config.json)                              │
│ - Network: Supabase Auth, ConnectRPC, WebSocket, Deepgram   │
└──────────────────────────────┬──────────────────────────────┘
                               │ Context-Isolated IPC (window.api)
┌──────────────────────────────▼──────────────────────────────┐
│ Renderer Layer                                              │
│ - Auth State Machine (WelcomeKit, HomeKit, Onboarding)      │
│ - State Management (Zustand / Hooks)                        │
│ - TipTap Rich Text Editor + KaTeX + Canvas Confetti         │
│ - Unified Design System Tokens (Dark Codex & Monochrome)    │
└─────────────────────────────────────────────────────────────┘

CURRENT CODEBASE ARCHITECTURE:
┌─────────────────────────────────────────────────────────────┐
│ Native macOS Swift Package (VoiceOSCore + VoiceOSApp)       │
│ - AppKit Window Controllers (NotchHUD, FloatingOrb, Main)   │
│ - Internal Swift Services (HotkeyManager, SpeechPipeline)   │
│ - Encrypted JSON Files + UserDefaults / Keychain            │
│ - Direct HTTP to local Ollama / Cloud LLM APIs              │
└──────────────────────────────┬──────────────────────────────┘
                               │ Internal Swift @Published / Observable
┌──────────────────────────────▼──────────────────────────────┐
│ SwiftUI View Layer + Web Demo Showcase (app/)               │
│ - AppState ObservableObject                                 │
│ - SwiftUI Views (NotchGlassIslandView, MainWindowView)      │
│ - DesignTokens.swift (approximate tokens)                   │
└─────────────────────────────────────────────────────────────┘
```

### Architectural Divergences:
1. **Contract Boundary Layer (IPC Surface)**:
   - Target defines a strict 316-property contract interface (`window.api`).
   - Current codebase communicates via direct Swift class method calls on shared singletons (`SpeechPipelineEngine.shared`, `HotkeyManager.shared`, `AppState.shared`).
   - **Resolution Plan**: Introduce a dedicated `VoiceOSIPCBridge` and `IPCContract` protocol in `VoiceOSCore` that formalizes the exact 316-method API surface documented in `APP-SECRET.md`. Whether called from native Swift or embedded Web/renderer components, the contract signatures and event names (`voiceos-widget:`, `onVolumeUpdate`, `pill-set-mouse-events`, etc.) will match 100%.

2. **Data Storage & Database Schema**:
   - Target uses an SQLite database for structured data with `CREATE TABLE voice_session_insights (id TEXT PRIMARY KEY, user_id TEXT, source_updated_at TEXT NOT NULL, metrics_json TEXT NOT NULL)` and an index `idx_voice_session_insights_user`. Settings reside in a single `config.json`.
   - Current codebase uses scattered `UserDefaults` keys and encrypted JSON files in `~/Library/Application Support/VoiceOS/`.
   - **Resolution Plan**: Implement an embedded SQLite persistence manager that creates the exact `voice_session_insights` table and schema, and consolidate user preferences into a structured `config.json` store matching `APP-SECRET.md`.

3. **Authentication & Session Flow**:
   - Target relies on Supabase OAuth code exchange (`generateNewAuthState`, `exchangeAuthCode`), storing session JWTs under the `auth` key in `config.json`.
   - Current codebase implements a custom PBKDF2 local account engine.
   - **Resolution Plan**: Refactor `AccountAuthService` to provide the Supabase auth endpoints and session token structure (`token`, `refreshToken`, `accountId`, `isSelfHosted`), with a fully working local mock mode marked `// LOCAL-STUB`.

4. **Network & Protocol Layer**:
   - Target communicates with `https://api.voiceos.com` and WebSocket transcription services via ConnectRPC and protobuf schemas (`StreamMessageSchema`, `MatchAppIntentRequestSchema`, etc.).
   - Current codebase makes raw REST calls to Ollama and OpenAI/Claude.
   - **Resolution Plan**: Implement typed Swift Codable representations of all ConnectRPC schemas and create the WebSocket streaming adapter for transcription.

---

## 4. UI & Design System Gaps Audit

A side-by-side comparison of current design tokens vs. `APP-SECRET.md` design system:

| Design Token / Element | Documented Target (APP-SECRET.md) | Current Codebase (`DesignTokens.swift`) | Gap Status |
|---|---|---|:---:|
| **Widget Background** | `#181818` | `rgba(14, 14, 16, 0.94)` / `#09090b` | ⚠️ Diverged |
| **Sidebar Background** | `#1d1d1d` | `#0d0d0d` / `#161618` | ⚠️ Diverged |
| **Surface Background** | `#282828` | `#222226` / `#161618` | ⚠️ Diverged |
| **Composer / Input Background** | `#363636` | `rgba(255, 255, 255, 0.07)` / `#1c1c1e` | ⚠️ Diverged |
| **Widget Text Primary** | `#f3f3f3` | `#ffffff` / `#f5f5f7` | ⚠️ Diverged |
| **Widget Text Muted** | `#b5b5b5` | `#a1a1aa` / `#6e6e73` | ⚠️ Diverged |
| **Widget Text Faint** | `#949494` | `#71717a` / `#444448` | ⚠️ Diverged |
| **Focus Outline Accent** | `#339cff` | `#0071e3` / `#0044e3` | ⚠️ Diverged |
| **Dashboard Gradient Start** | `#18191d` | `#09090b` | ⚠️ Diverged |
| **Chart Color 1** | `#2662d9` | `#0071e3` | ⚠️ Diverged |
| **Chart Color 2** | `#2eb88a` | `#34c759` | ⚠️ Diverged |
| **Chart Color 3** | `#e88c30` | `#ff9f0a` | ⚠️ Diverged |
| **Chart Color 4** | `#af57db` | `#af52de` | ⚠️ Diverged |
| **Chart Color 5** | `#e23670` | `#ff453a` | ⚠️ Diverged |
| **Installer Accent** | `#126ff6` | Missing | ❌ Missing |
| **Installer Background & Text** | `#ffffff`, `#202b3b` | Missing | ❌ Missing |
| **Base Font Family** | `-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif` | `SF Pro Display`, `SF Pro Text` | ✅ Parity |
| **OpenDyslexic Font Option** | `https://fonts.cdnfonts.com/css/opendyslexic` | Missing | ❌ Missing |
| **Corner Radius Scale** | `xs: 4, sm: 8, md: 12, lg: 16, xl: 20, xxl: 24, pill: 9999` | Same scale | ✅ Parity |
| **Spacing Scale** | `unit 4, 8, 12, 16, 20, 24, 32, 40, 48` | Same scale | ✅ Parity |
| **Celebration Confetti** | `canvas-confetti` effect on onboarding complete | Missing | ❌ Missing |
| **TipTap Editor Styling** | Rich formatting marks, highlight, lists | Plain text editor | ❌ Missing |

---

## 5. Prioritized Implementation Roadmap

To ensure maximum stability and zero regressions, work will proceed in strict hierarchical dependency order (Foundations $\rightarrow$ Features $\rightarrow$ UI Design $\rightarrow$ Verification):

### Phase 2: Foundations (Architecture & Core Contracts)
1. **IPC & Preload Surface Alignment**:
   - Create `VoiceOSIPCSurface.swift` implementing all high-level categories (Recording, Keyboard, Auth, Windows/Notches, Spotlight, Integrations, Agent, Data/Settings).
   - Stub all 316 handler properties and map them cleanly to `VoiceOSCore` engines.
2. **Persistence & SQLite Alignment**:
   - Implement `VoiceOSDatabaseManager.swift` with SQLite3, creating table `voice_session_insights` and index `idx_voice_session_insights_user`.
   - Consolidate settings storage into `config.json` matching the Electron Store schema.
3. **Auth & Session Layer Alignment**:
   - Implement Supabase auth exchange types (`generateNewAuthState`, `exchangeAuthCode`, `logout`) with `// LOCAL-STUB` offline fallback.
4. **Structured Logging & Diagnostics**:
   - Implement `VoiceOSLogger.swift` with sanitized logging and Sentry/PostHog event emitters.

### Phase 3: Features & Native Integrations
1. **Audio & Recording Subsystem**:
   - Implement `getNativeAudioDevicesWithInfo`, `getDefaultMicrophoneName`, and standardized `onVolumeUpdate` stream.
   - Implement Deepgram-style streaming audio WebSocket chunker with `// LOCAL-STUB`.
2. **Keyboard Listener & Key Normalization**:
   - Update `HotkeyManager` to normalize `control-right` and `fn_fast` (keycode 179).
   - Implement `blockKeys`, `unblockKey`, and `getBlockedKeys` native interception logic.
3. **Protobuf & ConnectRPC Schemas**:
   - Create typed models for `StreamMessageSchema`, `ScreenshotContextSchema`, `MatchAppIntentRequestSchema`, `ListVoiceSessionsRequestSchema`, `RecordVoiceSessionUsageRequestSchema`, etc.
4. **Native Helper Bridges**:
   - Implement native Reminders helper bridge (`reminders-helper`).
   - Implement native Location helper bridge (`location_core` / `location-now`).
   - Implement fast focused-app window text reader (`window-text-reader`).
5. **Integrations, Composio & MCP**:
   - Implement Composio OAuth flow and logo resolution (`https://logos.composio.dev/api/...`).
   - Wire MCP tool execution into agent planning loop.
   - Implement floating integration confirmation surface.
6. **Settings & System Toggles**:
   - Add `launchAtLogin`, `startInBackground`, `showInDock`, and `auto-paste` capabilities.

### Phase 4: UI Design System & Component Polishing
1. **Exact Design Tokens**:
   - Update `DesignTokens.swift` and `tokens.css` with exact hex colors (`#181818`, `#1d1d1d`, `#282828`, `#363636`, `#f3f3f3`, `#b5b5b5`, `#949494`, `#339cff`, `#18191d`, and Charts 1-5).
2. **Component Rebuild to Spec**:
   - Rebuild Sidebar, Chat messages, Notch Island, and Voice Pill to match the exact visual tokens.
   - Implement `WelcomeKit`, `HomeKit`, and `OnboardingRecovery` screen flow.
   - Implement rich formatted editor with math syntax support.
   - Add OpenDyslexic font option and celebration confetti on completion.

### Phase 5: Integration Testing, Verification & Cleanup
1. Run all 28 existing test suites + new Phase 2/3 test suites.
2. Verify full end-to-end user journey: launch $\rightarrow$ onboarding $\rightarrow$ auth $\rightarrow$ voice dictation $\rightarrow$ computer control $\rightarrow$ settings.
3. Update `README.md` with architecture documentation, `// LOCAL-STUB` registry, and verification evidence.

---

## 6. Awaiting User Approval

Per Phase 1 instructions, no functional code has been modified yet. Please review this audit and provide your approval to begin **Phase 2 — Foundations**.

