import SwiftUI
import AppKit
import VoiceOSCore

public struct ModelSetupDashboardView: View {
    @ObservedObject private var downloadManager = LocalModelDownloadManager.shared
    @State private var hardwareInfo = HardwareProfileDetector.shared.detectHardware()
    @State private var isDownloadingAll = false
    @State private var selectedExecutionMode: RecommendedExecutionMode = .hybrid
    
    // Ollama Detection State
    @State private var isOllamaRunning: Bool = false
    @State private var isCheckingOllama: Bool = false
    @State private var installedOllamaModels: [OllamaModelInfo] = []
    @State private var ollamaStatusMessage: String = "Probing http://localhost:11434..."
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Model Setup & Settings")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        Text("Manage on-device vision, language, and voice models with zero terminal commands.")
                            .font(.system(size: 13))
                            .foregroundColor(Color(white: 0.7))
                    }
                    Spacer()
                    
                    // Hardware Summary Pill
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "memorychip")
                                .foregroundColor(hardwareInfo.hasLowMemoryGuardrail ? .orange : .green)
                            Text("\(Int(hardwareInfo.totalRamGigabytes)) GB RAM")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        
                        Divider().frame(height: 14).background(Color.white.opacity(0.2))
                        
                        HStack(spacing: 6) {
                            Image(systemName: "internaldrive")
                                .foregroundColor(.blue)
                            Text("\(String(format: "%.1f", hardwareInfo.freeDiskGigabytes)) GB Free")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
                
                // Hardware Guardrail Alert (if RAM <= 8GB)
                if hardwareInfo.hasLowMemoryGuardrail {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 18))
                            .padding(.top, 2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("8 GB Unified Memory Detected — Guardrail Active")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.orange)
                            Text("Running 7B Vision models locally on 8GB systems may cause macOS memory pressure. We recommend Hybrid Mode: Local Brain (3B) + Cloud Vision API for smooth, zero-freeze execution.")
                                .font(.system(size: 12))
                                .foregroundColor(Color(white: 0.85))
                                .lineSpacing(2)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.3), lineWidth: 1))
                }
                
                // Mode Selector Picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Select Execution Architecture")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(white: 0.6))
                        .textCase(.uppercase)
                    
                    Picker("Execution Mode", selection: $selectedExecutionMode) {
                        Text("Hybrid (Local Brain + Cloud Vision) — Recommended").tag(RecommendedExecutionMode.hybrid)
                        Text("100% Local Offline (Requires 16GB RAM for Vision)").tag(RecommendedExecutionMode.localOffline)
                        Text("Cloud API Only (OpenAI / Claude / Gemini)").tag(RecommendedExecutionMode.cloudOnly)
                    }
                    .pickerStyle(.segmented)
                }
                
                // Ollama Daemon Status Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(isOllamaRunning ? Color.green : Color.orange)
                                .frame(width: 10, height: 10)
                            
                            Text("Ollama Runtime Engine")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text(isOllamaRunning ? "(localhost:11434 • Connected)" : "(Not Responding)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(isOllamaRunning ? Color.green : Color.orange)
                        }
                        
                        Spacer()
                        
                        if isCheckingOllama {
                            ProgressView().controlSize(.small)
                        } else {
                            Button(action: {
                                Task { await checkOllamaStatus() }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                    Text("Check Status")
                                }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if !isOllamaRunning {
                            Button(action: {
                                launchOllamaApp()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "play.circle.fill")
                                    Text("Launch Ollama")
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    Text(ollamaStatusMessage)
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.65))
                    
                    if !installedOllamaModels.isEmpty || downloadManager.isItemReady(id: "voice.kokoro.82m") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                Text("Ready on this device:")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Color(white: 0.5))
                                
                                ForEach(installedOllamaModels, id: \.name) { model in
                                    Text("\(model.name) (Ollama)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(Color.green)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.15))
                                        .cornerRadius(4)
                                }
                                
                                if downloadManager.isItemReady(id: "voice.kokoro.82m") {
                                    Text("kokoro-82m (Neural Audio)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(Color.green)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.15))
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.04))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(isOllamaRunning ? Color.green.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1))
                
                // Core Models Catalog Section
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Core Architecture Models")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                        
                        Button(action: {
                            Task {
                                isDownloadingAll = true
                                await downloadManager.startAllCoreDownloads()
                                isDownloadingAll = false
                            }
                        }) {
                            HStack(spacing: 6) {
                                if isDownloadingAll {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.down.circle.fill")
                                }
                                Text(isDownloadingAll ? "Downloading..." : "1-Click Download & Setup All")
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .disabled(isDownloadingAll)
                    }
                    
                    ForEach(downloadManager.tasksList) { task in
                        ModelCardRow(
                            task: task,
                            hasMemoryGuardrail: hardwareInfo.hasLowMemoryGuardrail,
                            onDownloadClicked: {
                                Task {
                                    await downloadManager.startDownload(for: task.catalogItem)
                                }
                            }
                        )
                    }
                }
            }
            .padding(24)
        }
        .background(Color(red: 0.08, green: 0.08, blue: 0.09))
        .onAppear {
            Task {
                await downloadManager.refreshInstalledStatuses()
                await checkOllamaStatus()
            }
        }
    }
    
    private func checkOllamaStatus() async {
        isCheckingOllama = true
        defer { isCheckingOllama = false }
        
        do {
            let running = await OllamaProvider.shared.isRunning()
            if running {
                let models = (try? await OllamaProvider.shared.listLocalModels()) ?? []
                installedOllamaModels = models
                isOllamaRunning = true
                ollamaStatusMessage = "Ollama is running. \(models.count) local models discovered."
                await downloadManager.refreshInstalledStatuses()
            } else {
                isOllamaRunning = false
                installedOllamaModels = []
                ollamaStatusMessage = "Ollama is not running. Launch the Ollama application or run 'ollama serve'."
            }
        }
    }
    
    private func launchOllamaApp() {
        if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.ollama.ollama") {
            NSWorkspace.shared.openApplication(at: appUrl, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        } else if FileManager.default.fileExists(atPath: "/Applications/Ollama.app") {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Ollama.app"))
        } else {
            let script = "tell application \"Terminal\" to do script \"ollama serve\""
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
            }
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await checkOllamaStatus()
        }
    }
}

private struct ModelCardRow: View {
    let task: ActiveDownloadTask
    let hasMemoryGuardrail: Bool
    let onDownloadClicked: () -> Void
    
    var item: ModelCatalogItem { task.catalogItem }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                // Role Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(roleColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: roleIcon)
                        .foregroundColor(roleColor)
                        .font(.system(size: 20))
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(item.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text(item.roleTitle)
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(roleColor.opacity(0.2))
                            .foregroundColor(roleColor)
                            .cornerRadius(6)
                        
                        Text(item.category == "voice" ? "ON-DEVICE AUDIO" : "OLLAMA ENGINE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(item.category == "voice" ? Color.green.opacity(0.15) : Color.blue.opacity(0.15))
                            .foregroundColor(item.category == "voice" ? Color.green : Color.blue)
                            .cornerRadius(4)
                        
                        if item.id.contains("vision") && hasMemoryGuardrail {
                            Text("Cloud Vision Recommended")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .foregroundColor(.orange)
                                .cornerRadius(4)
                        }
                    }
                    
                    Text(item.purposeDescription)
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.75))
                        .lineLimit(2)
                }
                
                Spacer()
                
                // Action Button / Status
                HStack(spacing: 12) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Size: ~\(String(format: "%.1f", Double(item.downloadSizeMB) / 1000.0)) GB")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(white: 0.6))
                        Text("RAM: \(String(format: "%.1f", item.ramRequiredGB)) GB")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(white: 0.6))
                    }
                    
                    switch task.status {
                    case .ready:
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Ready")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.12))
                        .cornerRadius(6)
                        
                    case .downloading(let progress, let speed, let eta):
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int(progress * 100))% (\(String(format: "%.1f", speed)) MB/s)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.blue)
                            Text("ETA: \(eta)s")
                                .font(.system(size: 10))
                                .foregroundColor(Color(white: 0.5))
                        }
                        
                    case .verifying:
                        Text("Verifying SHA...")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.orange)
                        
                    case .installing:
                        Text("Installing...")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.purple)
                        
                    case .failed(let reason):
                        HStack(spacing: 8) {
                            Text(reason.isEmpty ? "Failed" : reason)
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                                .lineLimit(1)
                            Button(action: onDownloadClicked) {
                                Text("Retry")
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(Color.red.opacity(0.2))
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                        
                    case .queued, .paused:
                        Button(action: onDownloadClicked) {
                            Text("Download")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Progress Bar if downloading
            if case .downloading(let progress, let speed, let eta) = task.status {
                VStack(spacing: 6) {
                    ProgressView(value: max(0.01, min(1.0, progress)))
                        .progressViewStyle(LinearProgressViewStyle(tint: Color.blue))
                    
                    HStack {
                        Text("\(Int(progress * 100))% downloaded • \(String(format: "%.1f", speed)) MB/s")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.blue)
                        Spacer()
                        Text(eta > 0 ? "ETA: \(eta)s" : "Registering...")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(white: 0.6))
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
    
    private var roleIcon: String {
        switch item.category {
        case "brain": return "brain.head.profile"
        case "vision": return "eye.fill"
        case "voice": return "waveform"
        default: return "cpu"
        }
    }
    
    private var roleColor: Color {
        switch item.category {
        case "brain": return .purple
        case "vision": return .blue
        case "voice": return .green
        default: return .orange
        }
    }
}

