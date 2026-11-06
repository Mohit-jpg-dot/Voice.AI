# 03 - Hover, Gestures, Delays & Tracking Study

Reference: `TheBoredTeam/boring.notch`

## 1. Dwell & Grace Timing
- **Source File**: `boringNotch/ContentView.swift:513-558`, `boringNotch/models/Constants.swift:79`
- **Minimum Hover Duration (Dwell)**:
  - Default: `0.30s` (`Defaults[.minimumHoverDuration] = 0.3`)
  - Continuous presence required: if cursor exits before 0.3s, `hoverTask?.cancel()` drops the pending open request, preventing false triggers during fast menu-bar sweeps.
- **Exit Grace Period**:
  - `100ms` delay (`Task.sleep(for: .milliseconds(100))`)
  - Moving the cursor briefly outside the boundary does not flicker or close the panel.
- **Protection Lock**:
  - `SharingStateManager.shared.preventNotchClose`: if sharing, popover, or active typing session is in progress, the panel stays locked open until explicitly dismissed or after a 2.0s safety fallback.

## 2. Hit-Testing & Extended Padding
- **Source File**: `boringNotch/ContentView.swift:43-44, 130`
- `extendedHoverPadding: CGFloat = 30` pt
- `zeroHeightHoverPadding: CGFloat = 10` pt
- Hit testing allows forgiving targeting so the user doesn't have to hit exact sub-pixel boundaries.
- Open subviews only receive hit events when `vm.notchState == .open` (`.allowsHitTesting(vm.notchState == .open)`).

## 3. Gestures & Scroll Tracking
- **Source File**: `boringNotch/extensions/PanGesture.swift:1-145`
- Two-finger scroll **DOWN** opens the notch; two-finger scroll **UP** closes it.
- **Gesture Thresholds**:
  - Minimum distance: `4pt`
  - Noise floor: `0.2`
  - Axis dominance ratio: `1.5`
  - Wheel delta scale: `8.0`
  - Gesture-end timeout: `300ms`
- **Drag-to-Drop Tracking**:
  - `observers/DragDetector.swift:1-120` tracks global dragging of files/text entering the notch bounding rect with a `500ms` debounce.

## 4. Haptic Feedback
- **Source File**: `boringNotch/ContentView.swift:184, 523`
- `NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)` / `.sensoryFeedback(.alignment, trigger: haptics)`
- Fires once upon opening to give physical tactile feedback on Mac trackpads.

