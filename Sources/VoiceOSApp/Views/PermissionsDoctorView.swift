import SwiftUI
import VoiceOSCore
import AppKit
import AVFoundation

public struct PermissionItem: Identifiable, Sendable {
    public let id = UUID()
    public let title: String
    public let description: String
    public let systemIcon: String
    public let isGranted: Bool
    public let settingsURLString: String
    public let whyNeeded: String
}

public struct PermissionsDoctorView: View {
    @State private var accessibilityGranted: Bool = false
    @State private var micGranted: Bool = false
    @State private var screenCaptureGranted: Bool = false
    @State private var automationGranted: Bool = true
    @State private var lastCheckTime: Date = Date()
    
    public init() {}
    
    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit4) {
            // Header
            HStack {
                Image(systemName: "stethoscope")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(DesignTokens.Colors.accentBlue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Permissions Doctor")
                        .font(DesignTokens.Typography.fontTitle3)
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    Text("Live audit of macOS system privileges required for autonomous voice agent control.")
                        .font(DesignTokens.Typography.fontCaption)
                        .foregroundColor(DesignTokens.Colors.textMuted)
                }
                Spacer()
                Button(action: refreshPermissions) {
                    Label("Re-check", systemImage: "arrow.clockwise")
                        .font(DesignTokens.Typography.fontCaptionBold)
                }
                .buttonStyle(.bordered)
            }
            
            // Cards Grid
            VStack(spacing: DesignTokens.Spacing.unit3) {
                permissionRow(
                    title: "Accessibility (AXUIElement)",
                    description: "Allows Voice.AI to read UI hierarchies, click buttons, switch tabs, and type into active windows.",
                    icon: "hand.point.up.left.fill",
                    isGranted: accessibilityGranted,
                    settingsPane: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
                    onRequest: {
                        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                        _ = AXIsProcessTrustedWithOptions(opts)
                        openSettingsURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                    }
                )
                
                permissionRow(
                    title: "Microphone Access",
                    description: "Required for continuous voice capture, VAD waveform audio metering, and speech recognition.",
                    icon: "mic.fill",
                    isGranted: micGranted,
                    settingsPane: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
                    onRequest: {
                        AVCaptureDevice.requestAccess(for: .audio) { _ in
                            DispatchQueue.main.async { refreshPermissions() }
                        }
                        openSettingsURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
                    }
                )
                
                permissionRow(
                    title: "Screen Recording (ScreenCaptureKit)",
                    description: "Enables screen vision: analyzing visible windows, reading documents, and understanding context.",
                    icon: "rectangle.inset.filled.and.cursorarrow",
                    isGranted: screenCaptureGranted,
                    settingsPane: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
                    onRequest: {
                        if #available(macOS 11.0, *) {
                            CGRequestScreenCaptureAccess()
                        }
                        openSettingsURL("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
                    }
                )
                
                permissionRow(
                    title: "Automation & Apple Events",
                    description: "Controls scriptable macOS applications (Spotify, Safari, Google Chrome, Notes, Finder).",
                    icon: "applescript.fill",
                    isGranted: automationGranted,
                    settingsPane: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
                    onRequest: {
                        let script = "tell application \"System Events\" to get name"
                        _ = AccessibilityControlEngine.shared.executeAppleScript(script)
                        openSettingsURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
                    }
                )
            }
        }
        .padding(DesignTokens.Spacing.unit4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
        .onAppear {
            refreshPermissions()
        }
    }
    
    @ViewBuilder
    private func permissionRow(
        title: String,
        description: String,
        icon: String,
        isGranted: Bool,
        settingsPane: String,
        onRequest: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.unit3) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(isGranted ? DesignTokens.Colors.accentGreen : DesignTokens.Colors.accentAmber)
                .frame(width: 24, height: 24)
                .padding(6)
                .background(
                    Circle()
                        .fill((isGranted ? Color.green : Color.orange).opacity(0.12))
                )
            
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title)
                        .font(DesignTokens.Typography.fontBodyMedium)
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    
                    Spacer()
                    
                    if isGranted {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                            Text("Granted")
                                .font(DesignTokens.Typography.fontCaptionBold)
                        }
                        .foregroundColor(DesignTokens.Colors.accentGreen)
                    } else {
                        Button(action: onRequest) {
                            Text("Grant Permission")
                                .font(DesignTokens.Typography.fontCaptionBold)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignTokens.Colors.accentBlue)
                        .controlSize(.small)
                    }
                }
                
                Text(description)
                    .font(DesignTokens.Typography.fontCaption)
                    .foregroundColor(DesignTokens.Colors.textMutedLight)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DesignTokens.Spacing.unit3)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.textBackgroundColor).opacity(0.4))
        )
    }
    
    private func refreshPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        micGranted = (micStatus == .authorized)
        
        if #available(macOS 11.0, *) {
            screenCaptureGranted = CGPreflightScreenCaptureAccess()
        } else {
            screenCaptureGranted = true
        }
        
        lastCheckTime = Date()
    }
    
    private func openSettingsURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
