# 04 - Live Activities, Wings & Sneak Peek Study

Reference: `TheBoredTeam/boring.notch`

## 1. Wing Live Activities
- **Source File**: `boringNotch/ContentView.swift:61-81, 260-340`, `boringNotch/components/Live activities/`
- **Closed Notch Width Expansion**:
  - Center area remains pure black over the hardware notch (`Rectangle().fill(.black).frame(width: closedNotchWidth)`).
  - Left and right "wings" expand horizontally while maintaining notch height (`effectiveClosedNotchHeight = 32pt`).
  - Left wing houses visualizer/icon; right wing houses status/value/waveform.
  - Expansion width formula:
    `chinWidth = closedNotchWidth + (2 * max(0, effectiveClosedNotchHeight - 12) + 20)` (for compact music/status activities) or expands up to `640` for full notifications.

## 2. Sneak Peek Timings
- **Default Duration**: `1.5s` for transient status updates (e.g. Volume, Brightness, Task progress).
- **Extended Notification**: `3.0s` for battery / status changes; `2.0s` for download completion.
- **Queue Separation**: `1.0s` spacing between queued events to prevent visual collisions.
- **Inline HUD Style**:
  - Icon on left wing, progress / value bar on right wing.
  - Stepping granularity: 1/16 for granular macOS volume/brightness increments.
  - Marquee text with fade edges for titles exceeding available wing width (`components/Live activities/MarqueeTextView.swift`).

