import SwiftUI
import AppKit
import VoiceOSCore

public struct IntegrationSetupView: View {
    @ObservedObject var appState: AppState
    public let descriptor: IntegrationSetupDescriptor
    public var onDismiss: () -> Void

    @State private var selectedMethodIndex: Int = 0
    @State private var stepStatuses: [String: IntegrationStepStatus] = [:]
    @State private var testOutput: String? = nil
    @State private var isTesting: Bool = false
    @State private var showScopesExplanation: Bool = false
    @State private var isHindiText: Bool = false
    @State private var pollTimer: Timer? = nil

    public init(
        appState: AppState,
        descriptor: IntegrationSetupDescriptor,
        onDismiss: @escaping () -> Void
    ) {
        self.appState = appState
        self.descriptor = descriptor
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            HStack(spacing: 12) {
                // App Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 42, height: 42)

                    Image(systemName: descriptor.iconSystemName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(descriptor.name)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        // Status Badge
                        HStack(spacing: 5) {
                            Circle()
                                .fill(badgeColor)
                                .frame(width: 7, height: 7)

                            Text(descriptor.status.badgeText)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(badgeColor)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(badgeColor.opacity(0.15))
                        .clipShape(Capsule())
                    }

                    Text(descriptor.category)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.50))
                }

                Spacer()

                // Language toggle (EN / हिन्दी)
                Button(action: {
                    isHindiText.toggle()
                }) {
                    Text(isHindiText ? "हिन्दी" : "English")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.75))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Toggle instruction language")

                // Close Button
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.50))
                        .padding(6)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .background(Color(white: 0.12))

            Divider().background(Color.white.opacity(0.10))

            // MARK: - Body Content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    // Features list
                    VStack(alignment: .leading, spacing: 6) {
                        Text("WHAT YOU CAN DO WITH THIS")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.45))

                        ForEach(descriptor.features, id: \.self) { feature in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(red: 0.20, green: 0.85, blue: 0.45))
                                    .padding(.top, 2)

                                Text(feature)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(Color.white.opacity(0.90))
                            }
                        }
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    // Connection Methods (if multiple available)
                    if descriptor.methods.count > 1 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CONNECTION METHOD")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(Color.white.opacity(0.45))

                            ForEach(Array(descriptor.methods.enumerated()), id: \.offset) { idx, method in
                                Button(action: {
                                    selectedMethodIndex = idx
                                }) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 6) {
                                                Text(method.title)
                                                    .font(.system(size: 13.5, weight: .semibold))
                                                    .foregroundColor(.white)

                                                if method.isRecommended {
                                                    Text("RECOMMENDED")
                                                        .font(.system(size: 9, weight: .bold))
                                                        .foregroundColor(Color.blue)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(Color.blue.opacity(0.15))
                                                        .clipShape(Capsule())
                                                }
                                            }

                                            if !method.description.isEmpty {
                                                Text(method.description)
                                                    .font(.system(size: 12))
                                                    .foregroundColor(Color.white.opacity(0.60))
                                            }
                                        }

                                        Spacer()

                                        Image(systemName: selectedMethodIndex == idx ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 16))
                                            .foregroundColor(selectedMethodIndex == idx ? Color.blue : Color.white.opacity(0.30))
                                    }
                                    .padding(12)
                                    .background(selectedMethodIndex == idx ? Color.blue.opacity(0.12) : Color.white.opacity(0.04))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(selectedMethodIndex == idx ? Color.blue.opacity(0.40) : Color.white.opacity(0.08), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Setup Steps with Live Status
                    if !descriptor.steps.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("SETUP STEPS")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(Color.white.opacity(0.45))

                            ForEach(Array(descriptor.steps.enumerated()), id: \.offset) { idx, step in
                                let status = stepStatuses[step.id] ?? .pending
                                HStack(alignment: .top, spacing: 12) {
                                    // Step Indicator
                                    ZStack {
                                        Circle()
                                            .fill(status == .done ? Color(red: 0.20, green: 0.85, blue: 0.45) : Color.white.opacity(0.15))
                                            .frame(width: 22, height: 22)

                                        if status == .done {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.black)
                                        } else {
                                            Text("\(idx + 1)")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .padding(.top, 2)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(step.title)
                                            .font(.system(size: 13.5, weight: .semibold))
                                            .foregroundColor(.white)

                                        Text(isHindiText ? (step.instructionsHindi ?? step.instructions) : step.instructions)
                                            .font(.system(size: 12.5))
                                            .foregroundColor(Color.white.opacity(0.70))
                                            .fixedSize(horizontal: false, vertical: true)

                                        if let buttonTitle = step.actionButtonTitle {
                                            Button(action: {
                                                if let url = step.actionURL {
                                                    NSWorkspace.shared.open(url)
                                                }
                                                Task {
                                                    try? await step.executeAction?()
                                                    await checkConditions()
                                                }
                                            }) {
                                                HStack(spacing: 4) {
                                                    Text(buttonTitle)
                                                        .font(.system(size: 12, weight: .semibold))
                                                    Image(systemName: "arrow.up.right")
                                                        .font(.system(size: 9))
                                                }
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 5)
                                                .background(Color.blue)
                                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                            }
                                            .buttonStyle(.plain)
                                            .padding(.top, 4)
                                        }
                                    }

                                    Spacer()
                                }
                                .padding(12)
                                .background(Color.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }

                    // Scopes Explanation ("Why we ask for this")
                    if !descriptor.scopes.isEmpty {
                        DisclosureGroup(
                            isExpanded: $showScopesExplanation,
                            content: {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(descriptor.scopes) { scope in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(scope.name)
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(.white)
                                            Text(scope.reason)
                                                .font(.system(size: 11.5))
                                                .foregroundColor(Color.white.opacity(0.65))
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                                .padding(.top, 6)
                            },
                            label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "lock.shield")
                                        .font(.system(size: 12))
                                    Text("Why we ask for these permissions")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(Color.white.opacity(0.70))
                            }
                        )
                        .padding(12)
                        .background(Color.white.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    // Test output banner (if triggered)
                    if let output = testOutput {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(Color.blue)
                            Text(output)
                                .font(.system(size: 12.5))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.blue.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .padding(18)
            }

            Divider().background(Color.white.opacity(0.10))

            // MARK: - Footer Actions
            HStack(spacing: 12) {
                // Open Setup Guide link button
                Button(action: {
                    openSetupGuide()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "book.pages")
                            .font(.system(size: 12))
                        Text("Open Setup Guide")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(Color.white.opacity(0.70))
                }
                .buttonStyle(.plain)

                Spacer()

                // Disconnect action (if connected)
                if descriptor.status.isConnected, let disconnect = descriptor.disconnectAction {
                    Button(action: {
                        Task {
                            await disconnect()
                            await MainActor.run {
                                testOutput = "Account disconnected successfully."
                            }
                        }
                    }) {
                        Text("Disconnect")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.red.opacity(0.90))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.red.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                // Test Connection Button
                if let test = descriptor.testAction {
                    Button(action: {
                        runTest(action: test)
                    }) {
                        HStack(spacing: 5) {
                            if isTesting {
                                ProgressView()
                                    .scaleEffect(0.55)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text("Test Connection")
                                .font(.system(size: 12.5, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isTesting)
                }
            }
            .padding(14)
            .background(Color(white: 0.10))
        }
        .frame(width: 520, height: 600)
        .background(Color(white: 0.08))
        .onAppear {
            startLivePolling()
        }
        .onDisappear {
            stopLivePolling()
        }
    }

    private var badgeColor: Color {
        switch descriptor.status {
        case .connected: return Color(red: 0.20, green: 0.85, blue: 0.45)
        case .connecting: return Color.blue
        case .needsAttention: return Color.red
        case .notConnected: return Color.gray
        case .comingSoon: return Color.purple
        }
    }

    private func startLivePolling() {
        Task { await checkConditions() }
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            Task { await checkConditions() }
        }
    }

    private func stopLivePolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func checkConditions() async {
        for step in descriptor.steps {
            if let condition = step.checkCondition {
                let passed = await condition()
                await MainActor.run {
                    stepStatuses[step.id] = passed ? .done : .pending
                }
            }
        }
    }

    private func runTest(action: @escaping @Sendable () async throws -> String) {
        isTesting = true
        testOutput = nil
        Task {
            do {
                let res = try await action()
                await MainActor.run {
                    self.testOutput = res
                    self.isTesting = false
                    BoringSoundEngine.shared.playDone()
                }
            } catch {
                await MainActor.run {
                    self.testOutput = "Test failed: \(error.localizedDescription)"
                    self.isTesting = false
                    BoringSoundEngine.shared.playError()
                }
            }
        }
    }

    private func openSetupGuide() {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let guideURL = repoRoot.appendingPathComponent("set-up-guide.md")
        if FileManager.default.fileExists(atPath: guideURL.path) {
            NSWorkspace.shared.open(guideURL)
        } else {
            NSWorkspace.shared.open(URL(string: "https://voiceai.app/docs/set-up-guide")!)
        }
    }
}

