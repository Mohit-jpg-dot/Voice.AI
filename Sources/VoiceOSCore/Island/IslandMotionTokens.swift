// Ported from islandcn, MIT License, Copyright (c) 2026 Leo. Modified for Swift.
// Physics constants and timing tokens mapped from islandcn motion engine.

import Foundation

public struct SpringSpec: Sendable, Equatable {
    public let response: Double
    public let dampingFraction: Double
    public let delay: Double

    public init(response: Double, dampingFraction: Double, delay: Double = 0.0) {
        self.response = response
        self.dampingFraction = dampingFraction
        self.delay = delay
    }
}

public enum IslandMotionTokens {
    // Alert and Group Timings (fitted in seconds)
    public static let alertHold: Double = 5.975
    public static let alertHoldIdle: Double = 5.969
    public static let groupHandoff: Double = 1.445
    public static let groupWindow: Double = 6.014
    public static let alertContentDelay: Double = 0.160
    public static let reducedMotionDuration: Double = 0.200

    // Shape Springs (width, left/right edges)
    public static let shapeAppear = SpringSpec(response: 0.483, dampingFraction: 0.62)
    public static let shapeExpand = SpringSpec(response: 0.517, dampingFraction: 0.824)
    public static let shapePressExpand = SpringSpec(response: 0.387, dampingFraction: 0.792)
    public static let shapeAppearExpand = SpringSpec(response: 0.540, dampingFraction: 0.811)
    public static let shapeSwap = SpringSpec(response: 0.498, dampingFraction: 0.829)
    public static let shapeCollapse = SpringSpec(response: 0.479, dampingFraction: 0.894)
    public static let shapeAlertCollapse = SpringSpec(response: 0.535, dampingFraction: 0.840)
    public static let shapeCollapseSplit = SpringSpec(response: 0.400, dampingFraction: 0.900)
    public static let shapeSplit = SpringSpec(response: 0.505, dampingFraction: 0.815)
    public static let shapeUnsplit = SpringSpec(response: 0.487, dampingFraction: 0.794)
    public static let shapeDismiss = SpringSpec(response: 0.432, dampingFraction: 1.019)
    public static let shapeResize = SpringSpec(response: 0.500, dampingFraction: 0.820)

    // Body Springs (height, vertical translation)
    public static let bodyAppear = SpringSpec(response: 0.483, dampingFraction: 0.62)
    public static let bodyExpand = SpringSpec(response: 0.497, dampingFraction: 0.825)
    public static let bodyPressExpand = SpringSpec(response: 0.388, dampingFraction: 0.791)
    public static let bodyAppearExpand = SpringSpec(response: 0.523, dampingFraction: 0.817)
    public static let bodySwap = SpringSpec(response: 0.492, dampingFraction: 0.832, delay: 0.223)
    public static let bodyCollapse = SpringSpec(response: 0.453, dampingFraction: 0.928)
    public static let bodyAlertCollapse = SpringSpec(response: 0.481, dampingFraction: 0.908)
    public static let bodyCollapseSplit = SpringSpec(response: 0.481, dampingFraction: 0.884)
    public static let bodySplit = SpringSpec(response: 0.505, dampingFraction: 0.815)
    public static let bodyDismiss = SpringSpec(response: 0.442, dampingFraction: 0.970)

    // Corner Radius Springs (continuous squircles)
    public static let cornerAppear = SpringSpec(response: 0.483, dampingFraction: 0.62)
    public static let cornerExpand = SpringSpec(response: 0.448, dampingFraction: 0.870, delay: 0.018)
    public static let cornerPressExpand = SpringSpec(response: 0.320, dampingFraction: 0.831, delay: 0.019)
    public static let cornerAppearExpand = SpringSpec(response: 0.452, dampingFraction: 0.865, delay: 0.020)
    public static let cornerSwap = SpringSpec(response: 0.410, dampingFraction: 0.888, delay: 0.244)
    public static let cornerCollapse = SpringSpec(response: 0.449, dampingFraction: 0.940, delay: 0.010)
    public static let cornerAlertCollapse = SpringSpec(response: 0.470, dampingFraction: 0.860, delay: 0.009)
    public static let cornerCollapseSplit = SpringSpec(response: 0.360, dampingFraction: 0.865)
}

