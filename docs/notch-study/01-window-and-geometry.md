# 01 - Window Architecture & Geometry Study

Reference: `TheBoredTeam/boring.notch`

## 1. Single Fixed-Size Window Architecture
- **Source File**: `boringNotch/components/Notch/BoringNotchWindow.swift:10-50`, `boringNotch/sizing/matters.swift:15-18`
- **Core Principle**: ONE fixed-size, borderless, non-activating `NSPanel` per display. The window frame **NEVER resizes** during open, close, or spring animations. Only the SwiftUI contents inside animate within the fixed bounds.
- **Window Dimensions**:
  - Open content: `width = 640`, `height = 190` (`openNotchSize: CGSize = .init(width: 640, height: 190)`)
  - Shadow padding: `shadowPadding: CGFloat = 20`
  - Window frame size: `width = 640`, `height = 210` (`windowSize = (640, 210)`)
- **Window Positioning** (`boringNotchApp.swift:273-278`):
  - `x = screen.frame.origin.x + (screen.frame.width / 2) - window.frame.width / 2`
  - `y = screen.frame.origin.y + screen.frame.height - window.frame.height`
  - Stays flush to the top edge, perfectly centered over the physical notch.
- **Panel Attributes**:
  - `isFloatingPanel = true`
  - `level = .mainMenu + 3`
  - `collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]`
  - `canBecomeKey = false`, `canBecomeMain = false`
  - `backgroundColor = .clear`, `isOpaque = false`, `hasShadow = false` (shadow is rendered inside SwiftUI)

## 2. Hardware Notch Geometry Math
- **Source File**: `boringNotch/sizing/matters.swift:39-78`
- **Notch Detection**: `screen.safeAreaInsets.top > 0`
- **Physical Notch Width Calculation**:
  - `notchWidth = screen.frame.width - screen.auxiliaryTopLeftArea.width - screen.auxiliaryTopRightArea.width + 4`
  - On 14" / 16" MacBook Pro M-series displays, this evaluates to ~185pt.
  - The `+ 4` prevents subpixel aliasing seams against the bezel.
- **Corner Radii** (`sizing/matters.swift:18`, `components/Notch/NotchShape.swift:11-120`):
  - Closed: `top = 6`, `bottom = 14`
  - Open: `top = 19`, `bottom = 24`
  - Top corners are concave ears created with quadratic Bezier curves (`addQuadCurve`) that flow out of the bezel edge.
  - Radii are animatable using `AnimatablePair<CGFloat, CGFloat>` in `NotchShape`.
- **Top Seam Camouflage**:
  - A 1px black rectangle overlay at the very top (`Rectangle().fill(.black).frame(height: 1).padding(.horizontal, topCornerRadius)`) in `ContentView.swift:105-110` eliminates any gap between the panel and the physical screen edge.

