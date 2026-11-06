# Voice.AI Cross-Platform Architecture Specification

This document details the cross-platform architecture of **Voice.AI**, establishing feature parity between macOS and Windows 10 (22H2+) / Windows 11.

---

## 1. Architectural Philosophy & Strategy

Voice.AI delivers a native, responsive experience on each platform:
- **macOS**: Native Swift, SwiftUI, AppKit, CoreAudio, Accessibility API (`AXUIElement`), Apple Vision OCR.
- **Windows**: Native C# / .NET 8 / WinUI 3 (Windows App SDK), WASAPI audio, Windows UI Automation (UIA), Windows Media Foundation & Speech Synthesis, `Windows.Graphics.Capture`.

### Why Native Shells over Heavy Wrappers
We evaluated Electron, Tauri/WebView2, and Native (WinUI 3 / AppKit):
1. **Input & Hotkey Latency**: Hold-to-talk dictation and low-level global key hooks require sub-millisecond dispatch. Electron adds a 40–80ms event loop delay; native Win32/AppKit hooks execute in under 2ms.
2. **Overlay Performance & Window Alpha**: Windows 11 Mica/Acrylic material, non-activating topmost window styles (`WS_EX_NOACTIVATE | WS_EX_TOPMOST`), click-through regions, and multi-monitor per-DPI scaling (`PerMonitorV2`) require DirectComposition and Windows App SDK APIs.
3. **Hardware Accessibility**: True UI Automation (UIA) control, UIPI elevation detection, and WASAPI audio capture are first-class in .NET WinUI 3 without inter-process IPC overhead.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                             Voice.AI Core Logic                             │
│  - Model Router & Brain (Cloud, Ollama, Google Free, Hybrid)                │
│  - Hindi / Hinglish / English Fast Grammar & Intent Classifier              │
│  - Math Engine (Deterministic arithmetic, roots, percentages, Hindi math)   │
│  - Tool Registry, Consequential Action Approvals & Safety Rules             │
│  - Encrypted Chat History & Local Memory Store                              │
│  - Model Download Manager & Hardware Spec Recommendation                    │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                ┌──────────────────────┴──────────────────────┐
                ▼                                             ▼
┌───────────────────────────────┐             ┌───────────────────────────────┐
│     macOS Platform Shell      │             │    Windows Platform Shell     │
│   (Swift / SwiftUI / AppKit)  │             │     (C# / .NET 8 / WinUI 3)   │
│ - NotchGlassIslandView        │             │ - TopCenterIslandWindow       │
│ - UniversalTextInserter (AX)  │             │ - WindowsUIAutomationService  │
│ - CoreAudio / BoringSound     │             │ - WASAPI / DirectAudio        │
│ - AppleScript / DOM Injection │             │ - Windows Media Session (SMTC)│
│ - Apple Vision OCR            │             │ - Windows.Graphics.Capture    │
│ - macOS Keychain Services     │             │ - Windows Credential Manager  │
└───────────────────────────────┘             └───────────────────────────────┘
```

---

## 2. Platform Adapter Contract Interfaces

The shared architecture defines 16 platform-adapter interfaces implemented identically on both platforms:

| Interface | macOS Implementation | Windows Implementation |
|---|---|---|
| `IAudioCaptureService` | `STTProviderEngine` (AVAudioEngine) | `WindowsAudioCaptureService` (WASAPI) |
| `IHotkeyHookService` | `HotkeyManager` (`CGEventTap`) | `WindowsHotkeyHookService` (`RegisterHotKey` / `SetWindowsHookEx`) |
| `IScreenCaptureService` | `ScreenVisionService` (`screencapture` + Vision) | `WindowsGraphicsCaptureService` (`Windows.Graphics.Capture`) |
| `IComputerControlService`| `AccessibilityControlEngine` (`AXUIElement`) | `WindowsUIAutomationService` (Microsoft UIA + `SendInput`) |
| `IAppLauncherService` | `NSWorkspace.shared.openApplication` | `WindowsAppLauncherService` (ShellExecute + `Get-StartApps`) |
| `IMusicControlService` | `NowPlayingMediaManager` (AppleScript + DOM) | `WindowsMediaSessionManager` (SMTC + Spotify Web API) |
| `IMessagingControl` | AppleScript / Accessibility URL schemes | Windows UIA + `whatsapp:` URI schema |
| `ITTSEngine` | `AVSpeechSynthesizer` / Piper local | `WindowsSpeechEngine` (SpeechSynthesis / Piper) |
| `ISTTEngine` | Apple Speech / whisper.cpp | local whisper.cpp / DirectML |
| `IPermissionsService` | System Preferences deep links (`tccutil`) | `ms-settings:privacy-microphone` deep links |
| `IAutostartService` | `SMAppService.mainApp` | Windows Registry `Run` / Startup Folder |
| `ISecureStorageService`| macOS Keychain (`ai.voice.app.auth`) | Windows Credential Manager / DPAPI |
| `IUpdateService` | Sparkle Framework (`appcast.xml`) | AppInstaller / WinSparkle (`appcast.xml`) |
| `IOverlayWindowService`| `NotchHUDWindowController` (AppKit HUD) | `TopCenterIslandWindow` (WinUI 3 Topmost Non-Activating) |
| `IClipboardService` | `NSPasteboard.general` | `Windows.ApplicationModel.DataTransfer.Clipboard` |
| `INotificationsService`| `UNUserNotificationCenter` | `Microsoft.Windows.AppNotifications` |

---

## 3. Shared Design Tokens (Black & White Minimalist Theme)

Both shells share identical monochrome design tokens:
- **Background**:
  - Closed Island Pill: `#000000` (100% pure black).
  - Expanded Island Drawer: Dark glass `#0D0D0E` with 96% opacity, 1px subtle white border (`rgba(255, 255, 255, 0.12)`).
  - Solid fallback: `#121214`.
- **Foreground & Text**:
  - Primary: `#FFFFFF` (96% opacity).
  - Secondary: `#A1A1AA` (65% opacity).
  - Muted: `#71717A` (45% opacity).
- **Accents**:
  - Green (Spotify / Success): `#1DB954`.
  - Red (Live recording / YouTube): `#EF4444`.
  - Accent Blue: `#007AFF`.
- **Corner Radii**:
  - Rested Pill: `12px` (Capsule).
  - Open Drawer: `18px` top, `22px` bottom.

---

## 4. Windows Specific Constraints & Mitigations

1. **User Interface Privilege Isolation (UIPI)**:
   - *Limitation*: A non-elevated application cannot inject keystrokes or send Windows messages to an elevated (Administrator) window (e.g. Task Manager or elevated Command Prompt).
   - *Mitigation*: `WindowsInsertionService` inspects the target process token (`OpenProcessToken` with `TokenElevation`). If elevated, Voice.AI does not simulate failed keystrokes; it copies the text to clipboard and displays an informative card in Hindi/English with an option to elevate Voice.AI.
2. **User Account Control (UAC) Secure Desktop**:
   - *Limitation*: When UAC darkens the screen, Windows switches to an isolated secure desktop that blocks all user-mode screen capture and input injection.
   - *Mitigation*: Voice.AI detects the active desktop switch, pauses automation, and gracefully resumes once the user confirms or cancels UAC.
3. **No Hardware Notch on Windows**:
   - *Implementation*: Windows uses a floating **Top-Center Island Pill** docked 0px below the top screen bezel on the primary monitor. It auto-hides when a fullscreen DirectX or video app is frontmost.
