# 02 - Animations & Physics Springs Study

Reference: `TheBoredTeam/boring.notch`

## 1. Spring Physics Parameters
- **Source File**: `boringNotch/ContentView.swift:41, 122-129`
- **Open Animation**:
  ```swift
  Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
  ```
  - Yields deliberate, weighty deceleration with minimal natural overshoot (~2-3%).
- **Close Animation**:
  ```swift
  Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
  ```
  - `dampingFraction: 1.0` is **critically damped**.
  - **Zero overshoot/bounce on close**: it snaps cleanly flush into the hardware notch without vibrating into the display area.
- **Interactive Gesture Spring**:
  ```swift
  Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)
  ```
  - Used for real-time cursor dragging and pan gesture resize.
- **Gesture Follow**:
  ```swift
  .animation(.smooth, value: gestureProgress)
  ```
- **Content Transition inside Open Notch**:
  ```swift
  .scale(scale: 0.8, anchor: .top).combined(with: .opacity).animation(.smooth(duration: 0.35))
  ```
  - Scaled from the top anchor so content smoothly expands downward as the notch body unfurls.

## 2. Dynamic Corner Radii Interpolation
- Animated through `currentNotchShape` using `AnimatablePair`:
  ```swift
  var animatableData: AnimatablePair<CGFloat, CGFloat> {
      get { .init(topCornerRadius, bottomCornerRadius) }
      set { topCornerRadius = newValue.first; bottomCornerRadius = newValue.second }
  }
  ```
  - Closed: `top: 6, bottom: 14` -> Open: `top: 19, bottom: 24`
  - Interpolates in lockstep with the frame height spring so corners don't snap or pop.

## 3. Drop & Shimmer Animations
- **Drop / File Bounce**: `.spring(.bouncy(duration: 0.4))` (`animations/drop.swift`)
- **Hello Startup Line**: 0.6s delay -> 4.0s ease-in-out glowing line -> auto-close (`animations/HelloAnimation.swift`).
- **Shadow Physics**:
  - `shadow(color: isHovering || isOpen ? .black.opacity(0.7) : .clear, radius: 6)`
  - Animated with the open/close spring; completely hidden when closed and not hovered.

