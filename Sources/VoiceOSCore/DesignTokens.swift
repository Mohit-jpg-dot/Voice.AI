import SwiftUI

/// VoiceOS Design System Tokens
/// Derived strictly from DESIGN.md and native screenshots in /design-ref/
public enum DesignTokens {

    // MARK: - Colors
    public enum Colors {
        // Light / Window Palette
        public static let windowBackgroundLight = Color(red: 0.97, green: 0.98, blue: 0.98, opacity: 0.90)
        public static let windowBackgroundDark = Color(red: 0.07, green: 0.07, blue: 0.08, opacity: 0.92)

        public static let surfaceLight = Color(red: 1.0, green: 1.0, blue: 1.0)
        public static let surfaceDark = Color(red: 0.09, green: 0.09, blue: 0.10)

        public static let surfaceElevatedLight = Color(red: 0.95, green: 0.96, blue: 0.96)
        public static let surfaceElevatedDark = Color(red: 0.14, green: 0.14, blue: 0.16)

        // HUD & Notch Palette (Obsidian Dark Glass)
        public static let hudBackground = Color(red: 0.06, green: 0.06, blue: 0.07, opacity: 0.95)
        public static let notchPillBackground = Color(red: 0.0, green: 0.0, blue: 0.0)

        // Typography
        public static let textPrimaryLight = Color(red: 0.07, green: 0.07, blue: 0.07)
        public static let textPrimaryDark = Color(red: 0.96, green: 0.96, blue: 0.97)

        public static let textSecondaryLight = Color(red: 0.43, green: 0.43, blue: 0.45)
        public static let textSecondaryDark = Color(red: 0.63, green: 0.63, blue: 0.67)

        public static let textMutedLight = Color(red: 0.55, green: 0.55, blue: 0.58)
        public static let textMutedDark = Color(red: 0.44, green: 0.44, blue: 0.48)

        // Borders
        public static let borderSubtleLight = Color(red: 0.0, green: 0.0, blue: 0.0, opacity: 0.06)
        public static let borderSubtleDark = Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.09)
        public static let borderStrongLight = Color(red: 0.0, green: 0.0, blue: 0.0, opacity: 0.12)
        public static let borderStrongDark = Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.18)
        public static let glassSpecular = Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.24)
        public static let borderGlassSpecular = glassSpecular

        // Accents
        public static let accentBlue = Color(red: 0.0, green: 0.44, blue: 0.89)
        public static let accentGreen = Color(red: 0.20, green: 0.78, blue: 0.35)
        public static let accentAmber = Color(red: 1.0, green: 0.62, blue: 0.04)
        public static let accentRed = Color(red: 1.0, green: 0.27, blue: 0.23)
        public static let accentPurple = Color(red: 0.69, green: 0.32, blue: 0.87)
        public static let accentCyan = Color(red: 0.12, green: 0.78, blue: 0.96)
        
        // Adaptive Dynamic Tokens for Modern Professional macOS Glass Look
        public static let canvasBackground = Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1.0) :
                NSColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1.0)
        }))
        
        public static let cardBackground = Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 0.88) :
                NSColor(white: 1.0, alpha: 0.92)
        }))
        
        public static let cardBorder = Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(white: 1.0, alpha: 0.12) :
                NSColor(white: 0.0, alpha: 0.08)
        }))
        
        public static let textPrimary = Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1.0) :
                NSColor(red: 0.09, green: 0.10, blue: 0.12, alpha: 1.0)
        }))
        
        public static let textSecondary = Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(red: 0.65, green: 0.68, blue: 0.74, alpha: 1.0) :
                NSColor(red: 0.40, green: 0.42, blue: 0.46, alpha: 1.0)
        }))
        
        public static let textMuted = Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(red: 0.45, green: 0.48, blue: 0.54, alpha: 1.0) :
                NSColor(red: 0.58, green: 0.60, blue: 0.64, alpha: 1.0)
        }))
        
        public static let inputBackground = Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 0.85) :
                NSColor(red: 0.93, green: 0.94, blue: 0.96, alpha: 0.85)
        }))
    }
    
    // MARK: - Minimal Black & White Monochrome Design System (Windows, Setup, Settings)
    public enum Monochrome {
        public static let windowBg = Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1.0) :
                NSColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1.0)
        }))
        
        public static let surface = Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0) :
                NSColor(white: 1.0, alpha: 1.0)
        }))
        
        public static let surfaceElevated = Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(red: 0.14, green: 0.14, blue: 0.15, alpha: 1.0) :
                NSColor(red: 0.94, green: 0.94, blue: 0.95, alpha: 1.0)
        }))
        
        public static let border = Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(white: 1.0, alpha: 0.14) :
                NSColor(white: 0.0, alpha: 0.10)
        }))
        
        public static let borderStrong = Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(white: 1.0, alpha: 0.28) :
                NSColor(white: 0.0, alpha: 0.22)
        }))
        
        public static let textPrimary = Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(white: 1.0, alpha: 1.0) :
                NSColor(white: 0.0, alpha: 1.0)
        }))
        
        public static let textSecondary = Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(red: 0.65, green: 0.65, blue: 0.67, alpha: 1.0) :
                NSColor(red: 0.38, green: 0.38, blue: 0.40, alpha: 1.0)
        }))
        
        public static let textMuted = Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(red: 0.42, green: 0.42, blue: 0.44, alpha: 1.0) :
                NSColor(red: 0.55, green: 0.55, blue: 0.58, alpha: 1.0)
        }))
        
        public static let inputBg = Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0) :
                NSColor(red: 0.95, green: 0.95, blue: 0.96, alpha: 1.0)
        }))
        
        public static let buttonPrimaryBg = Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(white: 1.0, alpha: 1.0) :
                NSColor(white: 0.0, alpha: 1.0)
        }))
        
        public static let buttonPrimaryText = Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(white: 0.0, alpha: 1.0) :
                NSColor(white: 1.0, alpha: 1.0)
        }))
        
        public static let buttonSecondaryBg = Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(white: 0.12, alpha: 1.0) :
                NSColor(white: 0.96, alpha: 1.0)
        }))
    }

    // MARK: - Gradients & Premium Finishes
    public enum Gradients {
        public static let brand = LinearGradient(
            colors: [Color(red: 0.38, green: 0.45, blue: 1.00), Color(red: 0.58, green: 0.35, blue: 0.95)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        public static let voiceWave = LinearGradient(
            colors: [Color(red: 0.15, green: 0.78, blue: 0.98), Color(red: 0.45, green: 0.38, blue: 1.00), Color(red: 0.88, green: 0.35, blue: 0.78)],
            startPoint: .leading,
            endPoint: .trailing
        )
        public static let proBadge = LinearGradient(
            colors: [Color(red: 1.00, green: 0.76, blue: 0.30), Color(red: 0.98, green: 0.55, blue: 0.15)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        public static let cardSpecular = LinearGradient(
            colors: [Color.white.opacity(0.18), Color.white.opacity(0.03)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Radius
    public enum Radius {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 20
        public static let xxl: CGFloat = 24
        public static let pill: CGFloat = 9999
    }

    // MARK: - Spacing
    public enum Spacing {
        public static let unit1: CGFloat = 4
        public static let unit2: CGFloat = 8
        public static let unit3: CGFloat = 12
        public static let unit4: CGFloat = 16
        public static let unit5: CGFloat = 20
        public static let unit6: CGFloat = 24
        public static let unit8: CGFloat = 32
        public static let unit10: CGFloat = 40
        public static let unit12: CGFloat = 48
    }

    // MARK: - Typography
    public enum Typography {
        public static let fontCaption = Font.system(size: 11, weight: .regular)
        public static let fontCaptionBold = Font.system(size: 11, weight: .semibold)
        public static let fontSubheadline = Font.system(size: 13, weight: .regular)
        public static let fontBody = Font.system(size: 14, weight: .regular)
        public static let fontBodyMedium = Font.system(size: 14, weight: .medium)
        public static let fontCallout = Font.system(size: 15, weight: .medium)
        public static let fontTitle3 = Font.system(size: 17, weight: .semibold)
        public static let fontTitle2 = Font.system(size: 20, weight: .bold)
        public static let fontTitle1 = Font.system(size: 24, weight: .bold)
        public static let fontDisplay = Font.system(size: 32, weight: .bold)
        public static let fontKeyCap = Font.system(size: 11, weight: .medium, design: .monospaced)
    }

    // MARK: - Shadows
    public enum Shadows {
        public static let subtle = Shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
        public static let card = Shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
        public static let window = Shadow(color: Color.black.opacity(0.12), radius: 24, x: 0, y: 12)
        public static let hud = Shadow(color: Color.black.opacity(0.35), radius: 32, x: 0, y: 16)
    }

    public struct Shadow {
        public let color: Color
        public let radius: CGFloat
        public let x: CGFloat
        public let y: CGFloat
    }
}

