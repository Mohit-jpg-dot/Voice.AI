import SwiftUI
import AppKit

/// Single source of truth for all notch physics, spring curves, delays, dimensions, and gesture thresholds.
/// Factual values calibrated to match physical notch mechanics.
public enum NotchAnimations {
    // MARK: - Spring Physics Curves
    
    /// Open animation spring: crisp 0.28s response, 0.85 damping (instant & smooth)
    public static let openSpring: Animation = .spring(response: 0.28, dampingFraction: 0.85, blendDuration: 0)
    
    /// Close animation spring: crisp 0.26s response, 0.96 damping (snappy collapse with near-zero overshoot)
    public static let closeSpring: Animation = .spring(response: 0.26, dampingFraction: 0.96, blendDuration: 0)
    
    /// Interactive gesture spring for live dragging / gesture tracking
    public static let interactiveSpring: Animation = .interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)
    
    /// Gesture follow curve
    public static let gestureFollow: Animation = .smooth
    
    /// Content transition inside open notch: scale from top anchor + opacity
    public static let contentTransition: AnyTransition = .scale(scale: 0.8, anchor: .top)
        .combined(with: .opacity)
        .animation(.smooth(duration: 0.35))
    
    /// Drop / file bounce animation
    public static let dropBounceSpring: Animation = .spring(.bouncy(duration: 0.4))
    
    // MARK: - Timings & Delays
    
    /// Minimum hover duration (dwell) before opening: 300ms continuous hover
    public static let minimumHoverDuration: Double = 0.30
    
    /// Mouse leave grace period before closing: 100ms
    public static let hoverExitGraceSeconds: Double = 0.100
    
    /// Sneak peek transient HUD duration: 1.5s
    public static let sneakPeekDuration: Double = 1.50
    
    /// Expanding notification duration (battery/status): 3.0s
    public static let expandingDuration: Double = 3.00
    
    /// Auto-close timeout when opened via keyboard shortcut: 3.0s
    public static let shortcutAutoCloseDuration: Double = 3.00
    
    /// Pan gesture end timeout: 300ms
    public static let gestureEndTimeout: Double = 0.300
    
    /// File drag-to-notch debounce: 500ms
    public static let dropDebounce: Double = 0.500
    
    /// Notification queue separation: 1.0s between queued events
    public static let notificationQueueSpacing: Double = 1.00
    
    // MARK: - Geometry & Dimensions
    
    /// Content size when open: 640pt width x 190pt height
    public static let openNotchSize = CGSize(width: 640, height: 190)
    
    /// Shadow padding below notch content: 20pt
    public static let shadowPadding: CGFloat = 20
    
    /// Window frame dimensions: fixed 640pt width x 210pt height (window NEVER resizes)
    public static let windowSize = CGSize(width: openNotchSize.width, height: openNotchSize.height + shadowPadding)
    
    /// Extended hover padding around the closed notch hit-test area
    public static let extendedHoverPadding: CGFloat = 30
    public static let zeroHeightHoverPadding: CGFloat = 10
    
    /// Corner radii insets:
    /// Closed: top 6pt (concave ears), bottom 14pt (convex)
    /// Open: top 19pt (concave ears), bottom 24pt (convex)
    public static let cornerRadiusClosedTop: CGFloat = 6
    public static let cornerRadiusClosedBottom: CGFloat = 14
    public static let cornerRadiusOpenTop: CGFloat = 19
    public static let cornerRadiusOpenBottom: CGFloat = 24
    
    // MARK: - Gesture Physics Constants
    
    public static let scrollActivationDistance: CGFloat = 4.0
    public static let scrollAxisDominanceRatio: CGFloat = 1.5
    public static let scrollWheelDeltaScale: CGFloat = 8.0
    public static let scrollNoiseFloor: CGFloat = 0.2
    public static let scrollDefaultSensitivity: CGFloat = 200.0
}

