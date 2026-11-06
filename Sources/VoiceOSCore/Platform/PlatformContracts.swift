import Foundation

public enum OperatingSystemType: String, Codable, Sendable {
    case macOS = "macOS"
    case windows = "Windows"
    case linux = "Linux"

    public static var current: OperatingSystemType {
        #if os(macOS)
        return .macOS
        #elseif os(Windows)
        return .windows
        #elseif os(Linux)
        return .linux
        #else
        return .macOS
        #endif
    }
}

public enum WindowSurfaceMaterial: String, Codable, Sendable {
    case liquidGlass = "macOS Tahoe Liquid Glass"
    case nsVisualEffect = "NSVisualEffectView Material"
    case winMica = "Windows 11 Mica"
    case winAcrylic = "Windows 11 Acrylic"
    case solidFallback = "Solid Background Fallback"
}

public enum TextInsertionStrategy: String, Codable, Sendable {
    case clipboardWithRestore = "Clipboard Paste with Full State Restore"
    case macOSAccessibilityAX = "macOS Accessibility API (AXUIElement)"
    case windowsUIAutomation = "Windows UI Automation (IUIAutomationValuePattern)"
    case directKeystroke = "Direct Keystroke Simulation"
}

public enum ScreenCaptureEngine: String, Codable, Sendable {
    case screenCaptureKit = "ScreenCaptureKit (macOS 12.3+)"
    case windowsGraphicsCapture = "Windows.Graphics.Capture (Windows 10/11)"
    case directXDesktopDuplication = "DirectX Desktop Duplication"
    case fallbackGDI = "BitBlt GDI Fallback"
}

public struct PlatformCapabilities: Sendable {
    public let os: OperatingSystemType
    public let supportsNotchIsland: Bool
    public let supportedMaterial: WindowSurfaceMaterial
    public let primaryInsertion: TextInsertionStrategy
    public let fallbackInsertion: TextInsertionStrategy
    public let screenCaptureEngine: ScreenCaptureEngine
    public let supportsTrayIcon: Bool
    public let defaultActivationHotkey: String

    public static func forPlatform(_ os: OperatingSystemType, hasHardwareNotch: Bool = true) -> PlatformCapabilities {
        switch os {
        case .macOS:
            return PlatformCapabilities(
                os: .macOS,
                supportsNotchIsland: hasHardwareNotch,
                supportedMaterial: .liquidGlass,
                primaryInsertion: .clipboardWithRestore,
                fallbackInsertion: .macOSAccessibilityAX,
                screenCaptureEngine: .screenCaptureKit,
                supportsTrayIcon: false, // Menubar status item instead
                defaultActivationHotkey: "fn"
            )
        case .windows:
            return PlatformCapabilities(
                os: .windows,
                supportsNotchIsland: false, // Pill flush with top screen edge
                supportedMaterial: .winMica,
                primaryInsertion: .clipboardWithRestore,
                fallbackInsertion: .windowsUIAutomation,
                screenCaptureEngine: .windowsGraphicsCapture,
                supportsTrayIcon: true, // System Tray NotifyIcon
                defaultActivationHotkey: "Win + H" // or configurable
            )
        case .linux:
            return PlatformCapabilities(
                os: .linux,
                supportsNotchIsland: false,
                supportedMaterial: .solidFallback,
                primaryInsertion: .clipboardWithRestore,
                fallbackInsertion: .directKeystroke,
                screenCaptureEngine: .fallbackGDI,
                supportsTrayIcon: true,
                defaultActivationHotkey: "Ctrl + Space"
            )
        }
    }
}

public struct ElevatedWindowSecurityGuard: Sendable {
    public static func checkTargetWindowIntegrity(isElevated: Bool) -> (canInsert: Bool, warningMessage: String?) {
        if isElevated {
            return (
                false,
                "Target window is running with Administrator / Elevated privileges. \(AppBrand.name) cannot inject keystrokes without matching UAC elevation. Text copied to clipboard."
            )
        }
        return (true, nil)
    }
}

public struct PlatformIntegrationSupport: Sendable {
    public static let macOSOnlyApps: Set<String> = [
        "imessage",
        "apple mail",
        "reminders",
        "finder",
        "notes",
        "apple calendar"
    ]

    public static func isAppSupportedOnWindows(_ appName: String) -> Bool {
        return !macOSOnlyApps.contains(appName.lowercased())
    }
}

