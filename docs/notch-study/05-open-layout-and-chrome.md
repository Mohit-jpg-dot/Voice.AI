# 05 - Open Layout & Chrome Architecture

Reference: `TheBoredTeam/boring.notch`

## 1. Header Structure
- **Source File**: `boringNotch/components/Notch/BoringHeader.swift:11-117`
- **Triptych Header Layout**:
  1. **Left**: Tab capsule pill switcher (`components/Tabs/TabSelectionView.swift`).
     - Selected tab highlighted with `matchedGeometryEffect(id: "capsule", in: animation)`.
     - Capsule fill: `Color(nsColor: .secondarySystemFill)`.
  2. **Center**: Pitch black mask spacer matching the physical notch width (`frame(width: vm.closedNotchSize.width)`). Ensures the physical notch glass remains unblemished.
  3. **Right**: 30pt circular/capsule action buttons with `HoverButton` (`components/HoverButton.swift:20-40`) featuring subtle hover highlighting (`Color.gray.opacity(0.2)`) and spring press feedback.

## 2. Empty States & Feedback
- Illustrated symbol + single descriptive line (`components/EmptyState.swift`).
- High-contrast, typography based on Apple system font weights (`subheadline`, `captionBold`).
- Dark appearance forced throughout (`.preferredColorScheme(.dark)`).

