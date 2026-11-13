import AppKit
import SwiftUI
import VoiceOSCore
import WebKit

// MARK: - Live WKWebView Preview Wrapper

private struct BuilderWebPreview: NSViewRepresentable {
    let htmlFileURL: URL
    let reloadToken: UUID

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        load(webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastToken != reloadToken || context.coordinator.lastURL != htmlFileURL {
            context.coordinator.lastToken = reloadToken
            context.coordinator.lastURL = htmlFileURL
            load(webView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func load(_ webView: WKWebView) {
        let dir = htmlFileURL.deletingLastPathComponent()
        webView.loadFileURL(htmlFileURL, allowingReadAccessTo: dir)
    }

    final class Coordinator {
        var lastToken: UUID?
        var lastURL: URL?
    }
}

// MARK: - Lovable / Replit App & Website Builder (Beta)

public struct AppBuilderView: View {
    @ObservedObject var appState: AppState
    @State private var promptInput: String = ""
    @State private var attachedImagePaths: [String] = []
    @State private var extractedDesignMarkdown: String = ""
    @State private var isExtractingDesign: Bool = false
    @State private var activeProject: BuilderProject? = nil
    @State private var savedProjects: [BuilderProject] = AppBuilderEngine.shared.savedProjects()
    @State private var isGenerating: Bool = false
    @State private var liveStatusText: String = ""
    @State private var rightPaneTab: Int = 0 // 0 = Preview, 1 = Code
    @State private var isMobileViewport: Bool = false
    @State private var selectedFilePath: String = "index.html"
    @State private var previewReloadToken = UUID()
    @State private var isListeningForBuilderPrompt: Bool = false
    @State private var detectedRoute: BuilderModelRoute? = nil
    @State private var builderErrorMessage: String? = nil

    private let starterIdeas: [(title: String, prompt: String)] = [
        ("SaaS Landing Page", "Build a sleek SaaS landing page for an AI voice studio with features, pricing, and interactive waitlist"),
        ("Pomodoro & Task App", "Build an interactive Pomodoro timer and task list web app with dark mode toggle"),
        ("Portfolio Website", "Build a minimalist developer portfolio website with project cards and contact modal"),
        ("Expense Tracker", "Build a clean personal expense tracker app with category totals and instant add")
    ]

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        Group {
            if let project = activeProject {
                workspaceView(project: project)
            } else {
                heroLandingView
            }
        }
        .onChange(of: appState.currentTranscript) { _, transcript in
            if isListeningForBuilderPrompt && !transcript.isEmpty {
                promptInput = transcript
            }
        }
        .task {
            detectedRoute = await AppBuilderEngine.shared.detectActiveBuilderModel()
        }
    }

    // MARK: - 1. Lovable-Style Hero Landing Page

    private var heroLandingView: some View {
        ZStack {
            // Luminous sky-blue radial aura matching the reference aesthetic
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.98, blue: 1.0),
                    Color(red: 0.89, green: 0.94, blue: 1.0),
                    Color(red: 0.56, green: 0.77, blue: 1.0).opacity(0.75)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay(
                RadialGradient(
                    colors: [
                        Color(red: 0.35, green: 0.63, blue: 1.0).opacity(0.38),
                        Color.clear
                    ],
                    center: .init(x: 0.5, y: 0.86),
                    startRadius: 20,
                    endRadius: 420
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            GeometryReader { geo in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 22) {
                        Spacer(minLength: 20)

                    // BETA Badge + Auto-Detected Model Pill
                    HStack(spacing: 8) {
                        Text("BETA")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(1.2)
                            .foregroundColor(Color(red: 0.25, green: 0.33, blue: 0.45))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.75))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.black.opacity(0.06), lineWidth: 1))

                        if let route = detectedRoute {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(route.badgeLabel.contains("Required") ? Color.orange : Color.green)
                                    .frame(width: 7, height: 7)
                                Text(route.badgeLabel)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Color(red: 0.16, green: 0.23, blue: 0.35))
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.75))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.black.opacity(0.06), lineWidth: 1))
                        }
                    }

                    // Hero Title & Subtitle
                    VStack(spacing: 8) {
                        Text("Tell Voice.AI what to build")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .tracking(-0.6)
                            .foregroundColor(Color(red: 0.06, green: 0.09, blue: 0.16))

                        Text("Describe a website or app in your own words — watch the agent build & preview it live.")
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundColor(Color(red: 0.30, green: 0.36, blue: 0.46))
                            .multilineTextAlignment(.center)
                    }

                    // Floating Prompt Card
                    VStack(alignment: .leading, spacing: 12) {
                        ZStack(alignment: .topLeading) {
                            if promptInput.isEmpty {
                                Text("Build me a sleek SaaS landing page with interactive pricing and dark mode...")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(red: 0.48, green: 0.53, blue: 0.62))
                                    .padding(.top, 8)
                                    .padding(.leading, 6)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $promptInput)
                                .font(.system(size: 14))
                                .foregroundColor(Color(red: 0.08, green: 0.11, blue: 0.18))
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 74, maxHeight: 110)
                        }

                        if !attachedImagePaths.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(attachedImagePaths, id: \.self) { imgPath in
                                        HStack(spacing: 6) {
                                            Image(systemName: "photo.fill")
                                                .font(.system(size: 11))
                                            Text(URL(fileURLWithPath: imgPath).lastPathComponent)
                                                .font(.system(size: 11, weight: .medium))
                                                .lineLimit(1)
                                            Button(action: {
                                                attachedImagePaths.removeAll { $0 == imgPath }
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 11))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .foregroundColor(Color(red: 0.16, green: 0.25, blue: 0.42))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color(red: 0.92, green: 0.95, blue: 1.0))
                                        .clipShape(Capsule())
                                    }
                                }
                            }
                        }

                        if !extractedDesignMarkdown.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Label("design.md extracted", systemImage: "doc.text.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(Color(red: 0.12, green: 0.35, blue: 0.72))
                                    Spacer()
                                    Button("Clear") {
                                        extractedDesignMarkdown = ""
                                    }
                                    .font(.system(size: 10.5))
                                    .buttonStyle(.plain)
                                }
                                Text(extractedDesignMarkdown)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundColor(Color(red: 0.22, green: 0.27, blue: 0.36))
                                    .lineLimit(5)
                            }
                            .padding(10)
                            .background(Color(red: 0.94, green: 0.97, blue: 1.0))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                        HStack(spacing: 10) {
                            Button(action: pickReferenceImages) {
                                HStack(spacing: 6) {
                                    Image(systemName: "photo.badge.plus")
                                        .font(.system(size: 12))
                                    Text(attachedImagePaths.isEmpty ? "Images" : "Images (\(attachedImagePaths.count))")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(Color(red: 0.22, green: 0.27, blue: 0.36))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color(red: 0.95, green: 0.96, blue: 0.98))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.black.opacity(0.06), lineWidth: 1))
                            }
                            .buttonStyle(.plain)

                            if !attachedImagePaths.isEmpty {
                                Button(action: extractDesignFromImages) {
                                    HStack(spacing: 5) {
                                        if isExtractingDesign {
                                            ProgressView().scaleEffect(0.55)
                                        } else {
                                            Image(systemName: "wand.and.stars")
                                                .font(.system(size: 12))
                                        }
                                        Text(isExtractingDesign ? "Extracting..." : "Extract design.md")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .foregroundColor(Color(red: 0.14, green: 0.32, blue: 0.68))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Color(red: 0.90, green: 0.94, blue: 1.0))
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(Color.blue.opacity(0.22), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .disabled(isExtractingDesign)
                            }

                            Button(action: {
                                isListeningForBuilderPrompt.toggle()
                                appState.toggleClipboardDictation()
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: isListeningForBuilderPrompt ? "mic.fill" : "mic")
                                        .font(.system(size: 12))
                                    Text(isListeningForBuilderPrompt ? "Stop Mic" : "Voice")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(isListeningForBuilderPrompt ? .white : Color(red: 0.22, green: 0.27, blue: 0.36))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(isListeningForBuilderPrompt ? Color.red.opacity(0.85) : Color(red: 0.95, green: 0.96, blue: 0.98))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.black.opacity(0.06), lineWidth: 1))
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button(action: { startBuild(with: promptInput) }) {
                                HStack(spacing: 6) {
                                    if isGenerating {
                                        ProgressView()
                                            .scaleEffect(0.6)
                                            .tint(.white)
                                    }
                                    Text(isGenerating ? "Building..." : "Generate")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 9)
                                .background(Color(red: 0.08, green: 0.11, blue: 0.18))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(isGenerating || promptInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.96))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: Color.black.opacity(0.08), radius: 24, x: 0, y: 12)
                    .frame(maxWidth: 620)
                    .padding(.horizontal, 24)

                    // Missing API Key / Local Model Alert Banner
                    if let errMsg = builderErrorMessage {
                        HStack(spacing: 12) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.orange)
                            Text(errMsg)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(red: 0.14, green: 0.16, blue: 0.22))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button("Put API Key in Settings") {
                                appState.activeNavTab = .settings
                            }
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(red: 0.08, green: 0.11, blue: 0.18))
                            .clipShape(Capsule())
                            .buttonStyle(.plain)
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.orange.opacity(0.45), lineWidth: 1))
                        .frame(maxWidth: 620)
                        .padding(.horizontal, 24)
                    }

                    // Starter Template Chips
                    HStack(spacing: 8) {
                        ForEach(starterIdeas, id: \.title) { idea in
                            Button(action: { promptInput = idea.prompt }) {
                                Text(idea.title)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundColor(Color(red: 0.16, green: 0.23, blue: 0.35))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.7))
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(Color.black.opacity(0.07), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Recent Projects Strip
                    if !savedProjects.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Recent Builds")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(red: 0.20, green: 0.27, blue: 0.38))

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                                ForEach(savedProjects.prefix(4)) { proj in
                                    Button(action: {
                                        activeProject = proj
                                        selectedFilePath = proj.files.first?.path ?? "index.html"
                                        previewReloadToken = UUID()
                                    }) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Image(systemName: "globe")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(Color(red: 0.22, green: 0.45, blue: 0.90))
                                                Text(proj.title)
                                                    .font(.system(size: 12.5, weight: .semibold))
                                                    .foregroundColor(Color(red: 0.08, green: 0.11, blue: 0.18))
                                                    .lineLimit(1)
                                            }
                                            Text("\(proj.files.count) files")
                                                .font(.system(size: 10.5))
                                                .foregroundColor(Color(red: 0.40, green: 0.46, blue: 0.56))
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(12)
                                        .background(Color.white.opacity(0.8))
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(Color.black.opacity(0.06), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxWidth: 620)
                        .padding(.horizontal, 24)
                        .padding(.top, 6)
                    }

                    Spacer(minLength: 24)
                }
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 2. Lovable / Replit Split Workspace

    private func workspaceView(project: BuilderProject) -> some View {
        HSplitView {
            // Left Pane: Builder Chat & Live Agent Progress
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button(action: { activeProject = nil }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)

                    Text(project.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(1)

                    Text("BETA")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.18))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())

                    Spacer()

                    if isGenerating {
                        HStack(spacing: 5) {
                            ProgressView().scaleEffect(0.55)
                            Text("Agent Active")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(.green)
                        }
                    }
                }
                .padding(12)
                .background(DesignTokens.Colors.cardBackground)

                Divider().overlay(DesignTokens.Colors.cardBorder)

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(project.turns) { turn in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(turn.role == "user" ? "You" : "Voice.AI Builder")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundColor(turn.role == "user" ? DesignTokens.Colors.accentBlue : .green)
                                Text(turn.text)
                                    .font(.system(size: 12.5))
                                    .foregroundColor(DesignTokens.Colors.textPrimary)
                                if !turn.touchedFiles.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(turn.touchedFiles, id: \.self) { f in
                                            HStack(spacing: 6) {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(size: 10.5))
                                                    .foregroundColor(.green)
                                                Text(f)
                                                    .font(.system(size: 11, design: .monospaced))
                                                    .foregroundColor(DesignTokens.Colors.textMuted)
                                            }
                                        }
                                    }
                                    .padding(.top, 2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(DesignTokens.Colors.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                        if isGenerating && !liveStatusText.isEmpty {
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.6)
                                Text(liveStatusText)
                                    .font(.system(size: 11.5))
                                    .foregroundColor(DesignTokens.Colors.textMuted)
                            }
                            .padding(10)
                        }
                    }
                    .padding(12)
                }

                Divider().overlay(DesignTokens.Colors.cardBorder)

                // Follow-up iteration prompt bar
                HStack(spacing: 8) {
                    TextField("Edit app (e.g. 'make it dark mode', 'add pricing')...", text: $promptInput, onCommit: {
                        startBuild(with: promptInput)
                    })
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(DesignTokens.Colors.textPrimary)

                    Button(action: { startBuild(with: promptInput) }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(DesignTokens.Colors.accentBlue)
                    }
                    .buttonStyle(.plain)
                    .disabled(isGenerating || promptInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(10)
                .background(DesignTokens.Colors.cardBackground)
            }
            .frame(minWidth: 280, idealWidth: 330, maxWidth: 400)

            // Right Pane: Live WKWebView Preview & Code Viewer
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Picker("", selection: $rightPaneTab) {
                        Text("Preview").tag(0)
                        Text("Code").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)

                    if rightPaneTab == 0 {
                        Button(action: { isMobileViewport.toggle() }) {
                            Image(systemName: isMobileViewport ? "iphone" : "laptopcomputer")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .help(isMobileViewport ? "Switch to Desktop" : "Switch to Mobile")
                    }

                    Spacer()

                    Button(action: { previewReloadToken = UUID() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)

                    Button("Open in Browser") {
                        NSWorkspace.shared.open(project.indexFileURL)
                    }
                    .font(.system(size: 11))

                    Button("Folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: project.directoryPath)])
                    }
                    .font(.system(size: 11))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(DesignTokens.Colors.cardBackground)

                Divider().overlay(DesignTokens.Colors.cardBorder)

                if rightPaneTab == 0 {
                    ZStack {
                        Color(nsColor: .windowBackgroundColor)
                        BuilderWebPreview(htmlFileURL: project.indexFileURL, reloadToken: previewReloadToken)
                            .frame(maxWidth: isMobileViewport ? 390 : .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: isMobileViewport ? 18 : 0, style: .continuous))
                            .shadow(radius: isMobileViewport ? 12 : 0)
                            .padding(isMobileViewport ? 14 : 0)
                    }
                } else {
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(project.files) { file in
                                Button(action: { selectedFilePath = file.path }) {
                                    Text(file.path)
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .foregroundColor(selectedFilePath == file.path ? DesignTokens.Colors.accentBlue : DesignTokens.Colors.textPrimary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(selectedFilePath == file.path ? DesignTokens.Colors.accentBlue.opacity(0.14) : Color.clear)
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
                        }
                        .frame(width: 150)
                        .padding(8)
                        .background(DesignTokens.Colors.cardBackground)

                        Divider().overlay(DesignTokens.Colors.cardBorder)

                        ScrollView([.vertical, .horizontal], showsIndicators: true) {
                            let code = project.files.first(where: { $0.path == selectedFilePath })?.content ?? ""
                            Text(code)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundColor(DesignTokens.Colors.textPrimary)
                                .textSelection(.enabled)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .frame(minWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DesignTokens.Colors.cardBorder, lineWidth: 0.7)
        )
    }

    // MARK: - Actions

    private func pickReferenceImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .webP]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            for url in panel.urls where !attachedImagePaths.contains(url.path) {
                attachedImagePaths.append(url.path)
            }
        }
    }

    private func extractDesignFromImages() {
        guard !attachedImagePaths.isEmpty, !isExtractingDesign else { return }
        isExtractingDesign = true
        let imgs = attachedImagePaths
        let ctx = promptInput
        Task {
            let md = await AppBuilderEngine.shared.extractDesignMarkdown(from: imgs, userContext: ctx)
            await MainActor.run {
                extractedDesignMarkdown = md
                isExtractingDesign = false
            }
        }
    }

    private func startBuild(with rawPrompt: String) {
        let clean = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !isGenerating else { return }
        promptInput = ""
        isGenerating = true
        builderErrorMessage = nil
        liveStatusText = "Detecting active AI model..."
        let currentProj = activeProject
        let imgs = attachedImagePaths
        let designMD = extractedDesignMarkdown.isEmpty ? nil : extractedDesignMarkdown
        attachedImagePaths = []
        extractedDesignMarkdown = ""

        Task {
            let outcome = await AppBuilderEngine.shared.buildOrIterateResult(
                prompt: clean,
                existingProject: currentProj,
                attachedImagePaths: imgs,
                designMarkdown: designMD
            ) { status in
                Task { @MainActor in
                    liveStatusText = status
                }
            }
            let updatedRoute = await AppBuilderEngine.shared.detectActiveBuilderModel(probeLocalIfNeeded: false)
            await MainActor.run {
                detectedRoute = updatedRoute
                switch outcome {
                case .success(let built):
                    activeProject = built
                    savedProjects = AppBuilderEngine.shared.savedProjects()
                    selectedFilePath = built.files.first?.path ?? "index.html"
                    previewReloadToken = UUID()
                case .failure(let err):
                    builderErrorMessage = err.message
                    promptInput = clean
                }
                isGenerating = false
                liveStatusText = ""
            }
        }
    }
}

