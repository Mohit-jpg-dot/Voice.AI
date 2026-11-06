# 06 - VoiceOS Adaptation & Content Mapping Matrix

This document maps boring.notch mechanics 1:1 to VoiceOS AI voice-assistant functions:

| boring.notch Component | boring.notch Purpose | VoiceOS Adaptation | Implementation Details |
| :--- | :--- | :--- | :--- |
| **Window Frame** | Fixed 640x210 panel | Fixed 640x210 panel (`NotchPanel`) | Window never resizes. Fixed at top-center of screen. |
| **Closed Idle** | Pure black camouflage | Pure black camouflage (`#000000`) | Seamless fit against physical MacBook notch. |
| **Live Activity (Wings)** | Music playback / visualizer | **Listening Waveform**: Mic icon left wing, reactive 10-band audio waveform right wing. **Speaking**: TTS audio visualizer. | Uses `chinWidth` horizontal wing extension while keeping center black over hardware notch. |
| **Sneak Peek HUD** | Volume / Brightness (1.5s) | **Task Status Sneak Peek**: Shows task completion / approval needed for 1.5s. | Auto-dismisses after 1.5s unless approval is pending. |
| **Open Home Tab** | Calendar & Now Playing | **Ask Tab**: Typed prompt bar, live streaming speech transcript, search knowledge card, AI provider launcher chips. | Key-focus enabled when typing, non-activating when listening. |
| **Open Shelf Tab** | File drop shelf | **Tasks Tab**: Background tasks, autonomous execution steps, durations, and redirect approval buttons. | Allows dropping files/text onto notch to ask questions. |
| **Tab Capsule** | Home / Shelf selector | Ask / Tasks tab capsule switcher | `matchedGeometryEffect` selection pill. |
| **Camera / Mirror** | Webcam preview button | Circle-to-Ask screen analysis trigger | Triggers screen region selection. |
| **Volume Slider** | System volume | Mic sensitivity / TTS speech volume | Interactive slider in HUD. |
| **Key Focus Handling** | Never becomes key | **Conditional Key Focus**: Panel becomes key only when user focuses the typing field; restores focus to prior app upon closing. | Clean AppKit `NSPanel` subclass. |
| **Material** | Solid black container | Top black hardware shield + macOS Tahoe Glass body | Pitch black top seam + glass body with Reduce Transparency fallback. |

