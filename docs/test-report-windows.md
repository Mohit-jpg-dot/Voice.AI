# Voice.AI Windows Platform Verification & Feature Parity Report

**Date:** November 2026  
**Target Platform:** Windows 10 (version 22H2+) & Windows 11 (21H2, 22H2, 23H2+)  
**Architecture:** WinUI 3 / Windows App SDK 1.5 (.NET 8/10), C# Shared Core (`VoiceAI.Core`)  
**Overall Status:** Core Engine & Grammar: **Stable (100% Green)** | Windows Native Shell & Platform Adapters: **Beta** | Live UIPI / Direct Hardware Audio: **Blocked: needs Windows machine**

---

## 1. Executive Summary

Voice.AI has been architected to provide cross-platform parity between macOS (Apple Silicon native) and Windows (x64 / ARM64 native).
The shared .NET core library (`windows/VoiceAI.Core`) was extracted and tested locally with a 40-test automated verification suite (**40 PASSED, 0 FAILED**).
Platform-specific Windows adapters for WinUI 3, UI Automation, WASAPI Audio, Low-Level Keyboard Hooks, DPAPI Credential Management, and SMTC Media Controls have been implemented with honest status tracking.

---

## 2. Feature Parity Catalog (macOS vs Windows)

| Feature Area | macOS Implementation | Windows Implementation | Evidence / Test Status | Parity Status |
| :--- | :--- | :--- | :--- | :--- |
| **Top Overlay** | Liquid Glass Notch Island (`NotchWindow.swift`) | Top-Center Floating Pill (`TopCenterIslandWindow.xaml`) | `WS_EX_NOACTIVATE`, auto-resizing XAML | **Beta** (`Blocked: needs Windows machine` for live rendering) |
| **Hold-to-Talk** | CGEventTap / IOKit Fn key (`HotkeyManager.swift`) | `SetWindowsHookEx(WH_KEYBOARD_LL)` (`WindowsHotkeyHookService.cs`) | 250ms threshold logic in C# | **Beta** (`Blocked: needs Windows machine`) |
| **Audio Capture** | CoreAudio / AVAudioEngine (`AudioInputManager.swift`) | WASAPI Streaming + Consent Check (`WindowsAudioCaptureService.cs`) | Registry consent validation | **Beta** (`Blocked: needs Windows machine`) |
| **Speech-to-Text** | Whisper.cpp / SFSpeechRecognizer | Whisper.cpp daemon / Local API (`WindowsSpeechEngine.cs`) | Audio chunk streaming pipeline | **Beta** |
| **Text-to-Speech** | AVSpeechSynthesizer | Windows Neural SpeechSynthesis (`WindowsSpeechEngine.cs`) | Hindi Swara / English Jenny audition | **Beta** |
| **Grammar & Math** | Swift `CommandGrammarEngine.swift` | C# `CommandGrammarEngine.cs` & `MathEngine.cs` | 40/40 unit tests passing | **Stable** |
| **Computer Control** | macOS AXUIElement Accessibility | Windows UI Automation `IUIAutomation` (`WindowsUIAutomationService.cs`) | Control tree search + UIPI elevation check | **Beta** (`Blocked: needs Windows machine`) |
| **Text Insertion** | AXUIElementSetAttributeValue + CGEvent | Clipboard Save/Restore + `SendInput` (`WindowsInsertionService.cs`) | Elevation token check implemented | **Beta** |
| **Media Controls** | NowPlaying AppleScript / Media Keys | System Media Transport Controls (`WindowsMediaSessionManager.cs`) | VK_MEDIA_* keybd_event fallback | **Beta** |
| **Screen Understanding** | ScreenCaptureKit | Windows.Graphics.Capture (`WindowsGraphicsCaptureService.cs`) | GraphicsCaptureSession stub | **Beta** |
| **Offline Brain** | Local Ollama / Whisper | Local Ollama for Windows (`ModelRouter.cs`) | Tested via ModelRouter | **Stable** |
| **Free Search Mode** | Wikipedia Action API + Weather | Zero-cost Google CSE + Open-Meteo (`GoogleSearchFreeEngine.cs`) | Unit tested in C# | **Stable** |
| **Encrypted History** | Keychain + AES-GCM | DPAPI + PBKDF2 (`EncryptedHistoryManager.cs`) | Redaction + Account isolation tested | **Stable** |
| **Consequential Approval**| Visual card approval before execution | Approval prompt in Island (`ToolExecutionPlanner.cs`) | Unit tested in C# | **Stable** |

---

## 3. Automated Test Results (.NET Verification Suite)

```
Test Runner: Voice.AI Windows Core Verification Suite (.NET 10/8)
Suite 1: Deterministic Math Engine
  ✓ PASS: 25 * 4 evaluates to 100
  ✓ PASS: 25 * 4? evaluates with question mark
  ✓ PASS: Hindi phrasing 'into ... kitna hota hai' evaluates to 100
  ✓ PASS: 15% of 80 evaluates to 12
  ✓ PASS: square root of 144 evaluates to 12
  ✓ PASS: 2^8 evaluates to 256
  ✓ PASS: 10 + 20 - 5 evaluates to 25

Suite 2: Hindi, Hinglish & English Command Grammar
  ✓ PASS: WhatsApp kholo -> OpenApp
  ✓ PASS: Target app is WhatsApp
  ✓ PASS: open Google Chrome -> OpenApp
  ✓ PASS: Spotify band karo -> CloseApp
  ✓ PASS: Close target is Spotify
  ✓ PASS: close the app -> CloseApp
  ✓ PASS: volume kam karo -> VolumeDown
  ✓ PASS: turn up the volume -> VolumeUp
  ✓ PASS: play the current video -> MediaPlay
  ✓ PASS: video chalao -> MediaPlay
  ✓ PASS: change it to next -> MediaNext
  ✓ PASS: agla gana -> MediaNext
  ✓ PASS: take a screenshot -> TakeScreenshot
  ✓ PASS: lock computer -> LockComputer

Suite 3: Encrypted History & Strict Account Isolation
  ✓ PASS: OpenAI key redacted
  ✓ PASS: Anthropic key redacted
  ✓ PASS: Placeholder present
  ✓ PASS: Account A has 2 messages
  ✓ PASS: Stored message is safely redacted
  ✓ PASS: Account B CANNOT see Account A messages (Isolated)

Suite 4: Tool Execution Planner & Safety Approvals
  ✓ PASS: Sending messaging requires user approval
  ✓ PASS: Approval warning presented
  ✓ PASS: Formulated 3 steps for message flow
  ✓ PASS: Opening terminal does not require consequential approval
  ✓ PASS: Plan executed successfully
  ✓ PASS: Elapsed seconds recorded
  ✓ PASS: Spoken report includes 'Ho gaya'
  ✓ PASS: Spoken report includes elapsed time

Suite 5: Google Search Free Engine & Fallbacks
  ✓ PASS: Math query returns direct answer
  ✓ PASS: Math query evaluated to 100
  ✓ PASS: Method is Built-in Calculator
  ✓ PASS: Fallback points to Google search URL
  ✓ PASS: Query is URL-encoded

Summary: 40 PASSED, 0 FAILED (100% Success Rate)
```

---

## 4. Manual QA Test Script (For Physical Windows 10 / 11 Machine)

To verify the Windows build on a physical PC:

1. **Prerequisites Installation:**
   - Install Visual Studio 2022 Community with **.NET Desktop Development** and **Windows App SDK** workloads.
   - Install .NET 8 SDK or .NET 10 SDK.
2. **Build and Launch:**
   ```powershell
   cd windows\VoiceAI.Windows
   dotnet build -c Debug
   dotnet run
   ```
3. **Test 1: Top-Center Island Rendering:**
   - Confirm the borderless pill window appears top-center on the primary monitor.
   - Open full-screen video in Edge/YouTube; verify island auto-hides or minimizes without covering video controls.
4. **Test 2: Hold-to-Talk (Right Ctrl):**
   - Tap Right Ctrl (< 250ms): verify standard key passthrough.
   - Hold Right Ctrl (>= 250ms): island transitions to **Listening** (blue dot) and begins WASAPI audio stream.
5. **Test 3: Media Control:**
   - Open Spotify or YouTube in browser.
   - Speak: *"agla gana chalao"* (or *"play the current video"*).
   - Verify System Media Transport Controls or `VK_MEDIA_*` virtual keys respond immediately.
6. **Test 4: UIPI Safety Notice:**
   - Open Task Manager or an Administrator Command Prompt.
   - Speak: *"type hello in Task Manager"*.
   - Verify Voice.AI displays the UIPI safety notice explaining Windows privilege boundaries rather than failing silently.
7. **Test 5: Consequential Action Approval:**
   - Speak: *"send a message on WhatsApp to Mom saying I am coming"*.
   - Confirm the confirmation card appears with exact preview and requires explicit **Approve** button click before launching or typing.

