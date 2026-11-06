# How to Grant macOS Permissions for Voice.AI

Voice.AI is an autonomous native macOS voice computer agent. To control apps, read the screen, stream microphone audio, and execute system commands by voice, macOS requires user authorization in **System Settings**.

---

## 1. Quick Summary of Permissions

| Permission | Needed For | System Settings Path |
| :--- | :--- | :--- |
| **Accessibility** | Reading UI hierarchies, typing into apps, clicking buttons, closing windows | `Privacy & Security` $\rightarrow$ `Accessibility` |
| **Microphone** | Voice recording, VAD metering, real-time STT transcription | `Privacy & Security` $\rightarrow$ `Microphone` |
| **Screen Recording** | Screen Vision, reading visible documents, OCR | `Privacy & Security` $\rightarrow$ `Screen Recording` |
| **Automation** | AppleScript control of Spotify, Music, Chrome, Safari, Finder, Notes | `Privacy & Security` $\rightarrow$ `Automation` |

---

## 2. Step-by-Step Instructions

### Step 1: Accessibility (`AXUIElement`)
1. Open **System Settings** (⌘ + Space, type `System Settings`).
2. Navigate to **Privacy & Security** $\rightarrow$ **Accessibility**.
3. Toggle the switch next to **Voice.AI** to **ON**.
4. If prompted, enter your Touch ID or administrator password.
*(Note: If Voice.AI is not in the list, click the `+` button, navigate to `/Applications`, and select `Voice.AI.app`)*.

### Step 2: Microphone
1. In **System Settings**, navigate to **Privacy & Security** $\rightarrow$ **Microphone**.
2. Toggle the switch next to **Voice.AI** to **ON**.
3. This allows the 16 kHz audio front-end and on-device speech recognizer to capture your voice commands.

### Step 3: Screen Recording (ScreenCaptureKit)
1. In **System Settings**, navigate to **Privacy & Security** $\rightarrow$ **Screen Recording**.
2. Toggle **Voice.AI** to **ON**.
3. macOS will display a prompt: *"Voice.AI will not be able to record the screen until it is quit."*
4. Click **Quit & Reopen** (or restart Voice.AI).

### Step 4: Automation (Apple Events)
1. In **System Settings**, navigate to **Privacy & Security** $\rightarrow$ **Automation**.
2. Expand the **Voice.AI** entry.
3. Ensure switches for **System Events**, **Spotify**, **Google Chrome**, **Safari**, and **Finder** are toggled **ON**.

---

## 3. Using the Built-In Permissions Doctor
Voice.AI includes an integrated **Permissions Doctor**:
1. Click the Voice.AI icon in your menu bar (or open Voice.AI Settings).
2. Scroll to the **Permissions Doctor** card.
3. Check the live status of each permission.
4. Click the **Grant Permission** button next to any missing item — Voice.AI will open the exact System Settings pane directly.
5. Click **Re-check** to verify.

---

## 4. Resetting Permissions for Testing
To completely reset permissions and test the first-launch onboarding flow:
```bash
tccutil reset Accessibility ai.voice.app
tccutil reset Microphone ai.voice.app
tccutil reset ScreenCapture ai.voice.app
tccutil reset AppleEvents ai.voice.app
```

