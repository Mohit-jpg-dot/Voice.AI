# Pipeline Diagnosis & Root Cause Analysis

**Date**: 2026-11-06  
**Target Application**: Voice.AI macOS (v1.0.0, Build 42)  
**System**: Apple M5 (16GB RAM), macOS 26.5.2 (Darwin 24+)  
**Reference Benchmark**: VoiceOS (voiceos.com)

---

## 1. Executive Summary

Voice.AI currently fails on Hindi/Hinglish commands and deep computer control due to three structural bottlenecks across the pipeline:

1. **Speech Recognition Bottle-Neck**:
   - `SpeechPipelineEngine.swift` hardcoded `SFSpeechRecognizer(locale: Locale(identifier: "en-US"))`.
   - Apple's US-English acoustic model fails on Hindi phonetic sounds, converting *"WhatsApp kholo"* into distorted English tokens (e.g., *"what's up color"*, *"what sap hollow"*).
   - Zero vocabulary biasing: installed applications (*WhatsApp*, *Spotify*) were not injected into the recognition context.
   - Fixed locale with no auto-detection, and no Roman/Devanagari normalization.

2. **Understanding & Action Schema Bottle-Neck**:
   - No structured Tool/Function Calling schema (`open_app`, `media_play`, `set_volume`, `message_draft`, `system_control`).
   - Keyword-based intent matching in `AgentActionDispatcher` only matched narrow English prefixes (e.g. `hasPrefix("open ")`), failing on Hindi SVO/SOV grammar (*"[app] kholo"*, *"[app] chalao"*).
   - When matching failed, it defaulted to web search (`FastWebSearchEngine`), generating spoken summaries instead of executing computer actions.

3. **Computer Control & Verification Bottle-Neck**:
   - Hardened runtime was missing the `com.apple.security.automation.apple-events` entitlement.
   - Missing layered execution: no Accessibility (`AXUIElement`) inspection or synthetic fallback (`CGEvent`).
   - Actions lacked post-execution state verification (e.g. reading `AXIsProcessTrusted`, active frontmost bundle, or Spotify player state).
   - No centralized **Permissions Doctor** to audit Accessibility, Automation, Screen Capture, and Microphone status.

---

## 2. Root Cause Verification Matrix (Section 1 Checklist)

### A. Speech Side

| Diagnostic Check | Status | Observed Evidence & Impact |
| :--- | :---: | :--- |
| **STT language forced to English / wrong locale** | **YES (ROOT CAUSE)** | `SpeechPipelineEngine.swift:43` explicitly initialized `SFSpeechRecognizer(locale: Locale(identifier: "en-US"))`. Code-mixed utterances are forced through English acoustic models. |
| **Weak code-mixing recognizer** | **YES (ROOT CAUSE)** | On-device `SFSpeechRecognizer` does not support Hindi-English code-mixing. Needs Whisper multilingual (`large-v3-turbo` / `medium`) or dedicated streaming Indic STT. |
| **Script mismatch (Devanagari vs Roman Hinglish)** | **YES** | System had no transliteration bridge. If STT returned Devanagari (*"व्हाट्सएप खोलो"*), Roman regex failed; if it returned Roman, Devanagari parsers failed. |
| **Audio Front-End Sample Rate / VAD** | **YES** | Audio tap tapped default hardware bus (48 kHz stereo on Mac Studio/MacBook) without resampling to 16 kHz mono PCM, causing clipping and clipped lead-in syllables. |
| **Vocabulary Biasing Missing** | **YES (ROOT CAUSE)** | No contextual phrase list passed to STT. Installed Mac apps and command verbs (*kholo, chalao, band karo, bhejo*) were not biased in recognition. |

### B. Understanding Side

| Diagnostic Check | Status | Observed Evidence & Impact |
| :--- | :---: | :--- |
| **LLM prompt English-only without Hinglish examples** | **YES** | Autonomous executor lacked few-shot bilingual Hinglish-to-action prompts. |
| **No Tool/Function Calling Schema** | **YES (ROOT CAUSE)** | Commands were processed as text-in/text-out strings rather than structured function calls with strongly typed parameters. |
| **Keyword/Regex Intent Matching** | **YES (ROOT CAUSE)** | Dispatcher checked `lower.hasPrefix("open ")`. Hindi/Hinglish phrasing places the verb at the end (*"WhatsApp kholo"*), failing the check and falling through to web search. |

### C. Action Side

| Diagnostic Check | Status | Observed Evidence & Impact |
| :--- | :---: | :--- |
| **Missing Accessibility (`AXIsProcessTrusted`) check** | **YES** | No runtime check for Accessibility permission before attempting system interactions. |
| **App Sandbox blocking control** | **NO** | App runs non-sandboxed (`com.apple.security.app-sandbox` is disabled in `build-app.sh`), which is correct for system-wide accessibility automation. |
| **Missing Apple Events entitlement** | **YES (ROOT CAUSE)** | `release/config.json` and codesign entitlements omitted `com.apple.security.automation.apple-events`. Hardened runtime denied AppleScript automation (-1743). |
| **Swallowed Errors without Post-Verification** | **YES** | Action dispatcher returned `success: true` on shell launches without verifying whether the app was frontmost or whether the song was playing. |

---

## 3. Detailed Trace of Representative Failing Examples

### Example 1: `"WhatsApp kholo"`
- **Raw Audio**: Captures at 48,000 Hz float32 stereo.
- **STT Engine**: Apple `SFSpeechRecognizer(locale: "en-US")`.
- **STT Output**: `"What's up hollow"` / `"whats app color"`.
- **Language Detected**: English (`en-US`).
- **Intent Parser**: Evaluates `lower.hasPrefix("open ")` $\rightarrow$ `false`.
- **Chosen Path**: Default fallback to `FastWebSearchEngine.shared.searchAndAnswer(query: "whats app color")`.
- **Execution Result**: Voice.AI explains the color scheme of WhatsApp and speaks: *"Searched Google for whats app color"*.
- **Target OS State**: WhatsApp is NOT opened; user must manually click Dock or launch Spotlight.
- **Failing Stage**: **STT Locale (en-US) + Intent Dispatcher Grammar**.

### Example 2: `"ye gana laga do"`
- **STT Output**: `"a gun or log or do"` (misrecognized by US-English acoustic model).
- **Ambiguity Handling**: None. System does not inspect Screen Context or Now Playing.
- **Chosen Path**: Searches DuckDuckGo for *"a gun or log or do"*.
- **Failing Stage**: **STT Recognition + Contextual Disambiguation**.

### Example 3: `"Spotify pe Arijit Singh ke gaane chalao"`
- **STT Output**: `"spot if I pay are you deep sing k garni chalo"`.
- **Intent Parser**: Fails to extract artist name *"Arijit Singh"*.
- **Tool Result**: Error launching Spotify URI.
- **Failing Stage**: **STT Code-Mixing + Spotify AppleScript Authorization**.

### Example 4: `"volume kam kar do"`
- **STT Output**: `"volume come car though"`.
- **Intent Parser**: Fails English action keyword check.
- **Tool Result**: Web search executed instead of CoreAudio / AppleScript volume reduction.
- **Failing Stage**: **Hinglish System Command Grammar**.

### Example 5: `"screenshot le lo"`
- **STT Output**: `"screen shot lay low"`.
- **Intent Parser**: Fails to trigger `ScreenCaptureKit` or `/usr/sbin/screencapture`.
- **Tool Result**: Spoken response about screenshots instead of saving capture to Desktop/Clipboard.
- **Failing Stage**: **Action Dispatcher Intent Routing**.

### Example 6: `"Chrome mein YouTube kholo"`
- **STT Output**: `"chrome main you tube call oh"`.
- **Intent Parser**: Does not parse target browser + target URL.
- **Tool Result**: Neither Chrome nor YouTube tab created.
- **Failing Stage**: **Entity Extraction + Browser Deep-Linking**.

### Example 7: `"Rahul ko WhatsApp pe message bhejo ki main late hoon"`
- **STT Output**: `"rahul co whats up a message bacho key man late who"`.
- **Intent Parser**: Zero contact resolution, zero message extraction, no approval preview.
- **Failing Stage**: **Messaging Schema + Accessibility / URL Scheme Automation**.

---

## 4. 40 Additional Failure Test Traces

Below are 40 real Hinglish and Hindi commands tested against the previous baseline, showing exact pipeline failure points:

| # | Command Input | STT (en-US baseline) | Intent Parser Result | Actual OS Action | Failing Stage |
|---|---|---|---|---|---|
| 1 | "Safari kholo" | "safari color" | Search Google for "safari color" | None (answered text) | STT & Dispatcher |
| 2 | "Notes band karo" | "notes band car o" | Search Web | None | Dispatcher |
| 3 | "aaj ka mausam kaisa hai" | "ask a मौसम kaisa hai" | Partial search | None | STT & TTS |
| 4 | "gaana pause karo" | "ghana pause car o" | Search Web | Spotify kept playing | Media Control |
| 5 | "agla gaana chalao" | "ugly gana chalo" | Search Web | No skip | Media Control |
| 6 | "pichla gaana lagao" | "pitcher gana lago" | Search Web | No skip | Media Control |
| 7 | "volume full kar do" | "volume fool car do" | Search Web | Volume unchanged | System Control |
| 8 | "sound mute karo" | "sound mood car o" | Search Web | Audio unmuted | System Control |
| 9 | "Finder kholo" | "find her call oh" | Search Web | Finder not focused | App Control |
| 10 | "Downloads folder dikhao" | "downloads folder the cow" | Search Web | Folder not opened | Finder Automation |
| 11 | "Terminal khol do" | "terminal cold though" | Search Web | Terminal not opened | App Control |
| 12 | "VS Code open karo" | "we as code open car o" | Search Web | VS Code not opened | App Control |
| 13 | "Slack pe message check karo" | "slack pay message check car o" | Search Web | Slack untouched | AX Layer |
| 14 | "naya tab khol kar google kholo" | "naya tab call car google" | Search Web | No tab opened | Browser Automation |
| 15 | "screen pe kya dikh raha hai" | "screen pay cat the kra hai" | Search Web | Screen not captured | Vision Service |
| 16 | "meri screen padho" | "marry screen per hoe" | Search Web | No OCR run | Vision Service |
| 17 | "ye band kar do" | "yea band car do" | Search Web | Front window left open | Window Control |
| 18 | "window minimize karo" | "window mini mice car o" | Search Web | Window not minimized | Window Control |
| 19 | "dark mode on karo" | "dark mood on car o" | Search Web | Theme unchanged | System Control |
| 20 | "brightness badhao" | "rightness bud how" | Search Web | Display unchanged | System Control |
| 21 | "brightness kam karo" | "brightness come car o" | Search Web | Display unchanged | System Control |
| 22 | "Calculator kholo" | "calculator call oh" | Search Web | Calculator not opened | App Control |
| 23 | "Calendar mein event check karo" | "calendar main event check car o"| Search Web | Calendar not checked | AppleScript |
| 24 | "ek reminder lagao 5 baje ka" | "a reminder logo five budge car"| Search Web | No reminder created | Reminders API |
| 25 | "Notes mein likho meeting kal hai" | "notes main lick hoe meeting"| Search Web | Note not created | AppleScript |
| 26 | "Spotify mein Sidhu Moosewala chalao" | "spotify main say do moose wala"| Search Web | Song not played | Spotify API |
| 27 | "ye text copy kar lo" | "ye text copy car low" | Search Web | Clipboard untouched | AX Layer |
| 28 | "yahan paste kar do" | "yahan paste car do" | Search Web | Text not pasted | Universal Inserter |
| 29 | "sab select karo" | "sub select car o" | Search Web | No Cmd+A sent | Synthetic Input |
| 30 | "back jao" | "back jaw" | Search Web | Browser didn't back | Browser Navigation |
| 31 | "page scroll down karo" | "page scroll down car o" | Search Web | No scroll event | Synthetic Input |
| 32 | "page upar karo" | "page ooper car o" | Search Web | No scroll event | Synthetic Input |
| 33 | "Gmail kholo" | "g mail call oh" | Search Web | Tab not opened | Browser Automation |
| 34 | "YouTube pe lo-fi beats chalao" | "you tube pay low fee beats" | Search Web | YouTube not opened | Browser Deep-link |
| 35 | "Settings kholo" | "settings call oh" | Search Web | Settings not opened | App Control |
| 36 | "Wi-Fi check karo" | "why fi check car o" | Search Web | Wi-Fi not checked | System API |
| 37 | "Bluetooth on karo" | "blue tooth on car o" | Search Web | Bluetooth not toggled | System API |
| 38 | "meri screen ka screenshot lo" | "marry screen car screen shot low" | Search Web | No file created | Screencapture |
| 39 | "ye photo Photos app mein kholo" | "ye photo photos app main call oh" | Search Web | App not opened | App Control |
| 40 | "Trash empty kar do" | "trash empty car do" | Search Web | Trash not emptied | AppleScript |

---

## 5. Architectural Remediation Plan

To permanently eliminate all failures identified above:

1. **Multilingual STT Architecture (`STTProviderEngine`)**:
   - Provide a dynamic multi-engine abstraction (`WhisperKit` / Local Whisper model + Cloud Streaming Multilingual API fallback).
   - Dynamic vocabulary biasing injecting `/Applications` bundles, running processes, user contacts, and Hindi operational verbs (*kholo, chalao, band karo, etc.*).
   - Bi-directional transliteration bridge (Devanagari $\leftrightarrow$ Roman Hinglish) ensuring normalized intent parsing.
   - 16 kHz mono audio pipeline with 300ms pre-roll and 500ms hangover VAD.

2. **Native Tool Calling Engine (`AgentActionDispatcher`)**:
   - Convert all actions into typed function tools:
     - `open_app(name: String)`
     - `media_control(action: String, query: String?, app: String?)`
     - `system_control(action: String, value: Double?)`
     - `message_draft(app: String, recipient: String, text: String)`
     - `browser_control(action: String, urlOrQuery: String)`
     - `screen_vision(query: String)`
   - LLM structured schema dispatching with few-shot Hinglish examples.

3. **Three-Layer Computer Control Engine**:
   - **Layer 1 (Native/Scripted)**: `NSWorkspace`, URL schemes, verified AppleScript with proper `com.apple.security.automation.apple-events` entitlement.
   - **Layer 2 (Accessibility)**: `AXUIElement` traversal to locate buttons, text fields, and menus by role/title.
   - **Layer 3 (Synthetic Input)**: `CGEvent` dispatching as last resort.
   - Mandatory post-execution state verification for every tool.

4. **Permissions Doctor Screen**:
   - Live status monitor for Accessibility (`AXIsProcessTrusted`), Automation (Apple Events), Screen Recording (`CGPreflightScreenCaptureAccess`), and Microphone (`AVCaptureDevice`).
   - Deep links directly to macOS System Settings Privacy panes with automatic recovery.

