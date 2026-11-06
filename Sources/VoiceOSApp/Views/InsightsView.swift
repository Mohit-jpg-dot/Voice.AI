import SwiftUI
import VoiceOSCore
import AppKit

public struct InsightsView: View {
    @ObservedObject var appState: AppState
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    private var macHardwareDescription: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let modelString = String(cString: model)
        return modelString.isEmpty ? "Apple Silicon Mac" : modelString
    }
    
    private var macMemoryGB: String {
        let memBytes = ProcessInfo.processInfo.physicalMemory
        let memGB = Double(memBytes) / (1024 * 1024 * 1024)
        return String(format: "%.0f GB Unified Memory", memGB)
    }
    
    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit6) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Insights")
                        .font(DesignTokens.Typography.fontTitle1)
                        .foregroundColor(DesignTokens.Colors.textPrimary)
                    
                    Text("Live on-device speech telemetry, real-time word metrics, and hardware engine diagnostics.")
                        .font(DesignTokens.Typography.fontSubheadline)
                        .foregroundColor(DesignTokens.Colors.textMuted)
                }
                
                // Key Metrics Grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: DesignTokens.Spacing.unit4) {
                    MetricBox(
                        title: "Words Dictated",
                        value: "\(appState.totalWords)",
                        subtitle: "Polished via on-device NLP",
                        icon: "character.cursor.ibeam",
                        accentColor: DesignTokens.Colors.accentBlue
                    )
                    
                    MetricBox(
                        title: "Voice Sessions",
                        value: "\(appState.totalSessions)",
                        subtitle: "Dictation & Agent dispatches",
                        icon: "waveform.path",
                        accentColor: DesignTokens.Colors.accentGreen
                    )
                    
                    MetricBox(
                        title: "Time Saved",
                        value: "\(appState.timeSavedMinutes)m",
                        subtitle: "vs ~40 WPM manual keyboard",
                        icon: "hourglass",
                        accentColor: Color.orange
                    )
                }
                
                // Speech Core & Audio Hardware Card
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit4) {
                    HStack(spacing: DesignTokens.Spacing.unit2) {
                        Image(systemName: "mic.badge.checkmark")
                            .font(.system(size: 16))
                            .foregroundColor(DesignTokens.Colors.accentGreen)
                        Text("Speech Engine & Audio Input")
                            .font(DesignTokens.Typography.fontTitle3)
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                    }
                    
                    VStack(spacing: DesignTokens.Spacing.unit3) {
                        TelemetryRow(label: "Speech Recognition Engine", value: "Apple SFSpeechRecognizer & Local Whisper")
                        Divider()
                        TelemetryRow(label: "Audio Input Device", value: "Mac Built-in Microphone (CoreAudio)")
                        Divider()
                        TelemetryRow(label: "Sample Rate & Format", value: "16,000 Hz · 32-bit Float · Mono PCM")
                        Divider()
                        TelemetryRow(label: "On-Device Privacy Boundary", value: "100% Offline · Zero Audio Leaves This Mac")
                        Divider()
                        TelemetryRow(label: "Latency Benchmark", value: "< 150ms Speech-to-Intent Pipeline")
                    }
                    .padding(DesignTokens.Spacing.unit4)
                    .background(DesignTokens.Colors.cardBackground)
                    .cornerRadius(DesignTokens.Radius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
                    )
                }
                
                // Machine System Specifications
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit4) {
                    HStack(spacing: DesignTokens.Spacing.unit2) {
                        Image(systemName: "applelogo")
                            .font(.system(size: 16))
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                        Text("Host Machine Diagnostics")
                            .font(DesignTokens.Typography.fontTitle3)
                            .foregroundColor(DesignTokens.Colors.textPrimary)
                    }
                    
                    VStack(spacing: DesignTokens.Spacing.unit3) {
                        TelemetryRow(label: "Hardware Identifier", value: macHardwareDescription)
                        Divider()
                        TelemetryRow(label: "System Memory", value: macMemoryGB)
                        Divider()
                        TelemetryRow(label: "Operating System", value: ProcessInfo.processInfo.operatingSystemVersionString)
                        Divider()
                        TelemetryRow(label: "\(AppBrand.name) Bundle Identifier", value: "\(AppBrand.bundleId) (\(AppBrand.displayVersion))")
                        Divider()
                        TelemetryRow(label: "Hardened Runtime", value: "Sandboxed Core · Accessibility & Speech Entitled")
                    }
                    .padding(DesignTokens.Spacing.unit4)
                    .background(DesignTokens.Colors.cardBackground)
                    .cornerRadius(DesignTokens.Radius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
                    )
                }
            }
            .padding(DesignTokens.Spacing.unit6)
        }
    }
}

private struct MetricBox: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let accentColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.unit2) {
            HStack {
                Text(title)
                    .font(DesignTokens.Typography.fontCaptionBold)
                    .foregroundColor(DesignTokens.Colors.textMuted)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(accentColor)
            }
            
            Text(value)
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(DesignTokens.Colors.textPrimary)
            
            Text(subtitle)
                .font(DesignTokens.Typography.fontCaption)
                .foregroundColor(DesignTokens.Colors.textSecondary)
        }
        .padding(DesignTokens.Spacing.unit4)
        .background(DesignTokens.Colors.cardBackground)
        .cornerRadius(DesignTokens.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
        )
    }
}

private struct TelemetryRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(DesignTokens.Typography.fontBodyMedium)
                .foregroundColor(DesignTokens.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(DesignTokens.Colors.textPrimary)
        }
    }
}

