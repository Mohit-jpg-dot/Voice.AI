# VoiceOS Notch System: Clean-Room Implementation Notice

This implementation of the VoiceOS notch physical UI follows **Clean-Room Engineering (Path A)** as mandated by the project architecture specification.

## 1. Clean-Room Methodology
- The reference implementation [`TheBoredTeam/boring.notch`](https://github.com/TheBoredTeam/boring.notch) was cloned and analyzed for factual engineering specifications, including:
  - Coordinate mathematics and physical screen hardware calculations (`auxiliaryTopLeftArea`, `safeAreaInsets.top`).
  - Single fixed-size non-resizing `NSPanel` architecture (640x190 content + 20pt shadow padding => 640x210 window).
  - Exact spring physics curves (`response: 0.42, dampingFraction: 0.8` for opening, critically damped `response: 0.45, dampingFraction: 1.0` without overshoot for closing).
  - Hover dwell timing (180ms - 300ms) and mouse exit grace period (100ms - 380ms).
  - Shape geometry interpolation (top concave ear curves quad-bezier flowing out of bezel, corner radii: closed top 6 / bottom 14, open top 19 / bottom 24).
- **Zero code, comments, strings, asset files, Lottie files, or icon artwork were copied or pasted.**
- All Swift and SwiftUI implementations in VoiceOS are completely original clean-room code tailored specifically to macOS Tahoe glass design and VoiceOS agent workflows (voice listening waveforms, live transcription streaming, autonomous task background execution, approval cards, and redirect prompts).

## 2. Study Records
Technical notes, file-by-file factual extractions, and verification references are documented in:
- `docs/notch-study/01-window-and-geometry.md`
- `docs/notch-study/02-animations-and-springs.md`
- `docs/notch-study/03-hover-gestures-and-tracking.md`
- `docs/notch-study/04-live-activities-and-wings.md`
- `docs/notch-study/05-voiceos-adaptation-matrix.md`

