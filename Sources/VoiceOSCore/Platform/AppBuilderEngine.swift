import AppKit
import CoreGraphics
import Foundation

public struct BuilderProjectFile: Identifiable, Codable, Sendable, Equatable {
    public var id: String { path }
    public let path: String
    public var content: String

    public init(path: String, content: String) {
        self.path = path
        self.content = content
    }
}

public struct BuilderChatTurn: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let role: String // "user" | "assistant"
    public let text: String
    public let touchedFiles: [String]
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        role: String,
        text: String,
        touchedFiles: [String] = [],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.touchedFiles = touchedFiles
        self.timestamp = timestamp
    }
}

public struct BuilderProject: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var title: String
    public var prompt: String
    public var files: [BuilderProjectFile]
    public var directoryPath: String
    public var turns: [BuilderChatTurn]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        prompt: String,
        files: [BuilderProjectFile],
        directoryPath: String,
        turns: [BuilderChatTurn] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.files = files
        self.directoryPath = directoryPath
        self.turns = turns
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var indexFileURL: URL {
        URL(fileURLWithPath: directoryPath).appendingPathComponent("index.html")
    }
}

public enum BuilderModelRoute: Sendable, Equatable {
    case localOllama(modelName: String)
    case cloud(provider: String, modelName: String)
    case unavailable(reason: String)

    public var badgeLabel: String {
        switch self {
        case .localOllama(let model): return "Local Ollama • \(model)"
        case .cloud(let provider, let model): return "Cloud (\(provider)) • \(model)"
        case .unavailable: return "API Key or Local Model Required"
        }
    }
}

public enum BuilderGenerationError: Error, Sendable, Equatable {
    case missingModelOrAPIKey(String)
    case generationFailed(String)

    public var message: String {
        switch self {
        case .missingModelOrAPIKey(let m), .generationFailed(let m): return m
        }
    }
}

/// Lovable / Replit-style Beta App & Website Builder Engine.
/// Streams live build progress into CodingAgentManager so the Notch Pill Agents tab
/// shows the builder working in real time.
public final class AppBuilderEngine: @unchecked Sendable {
    public static let shared = AppBuilderEngine()

    private let lock = NSLock()
    private var projectsCache: [BuilderProject] = []

    public init() {
        loadSavedProjects()
    }

    public static func workspaceRoot(homeDirectory: String = NSHomeDirectory()) -> URL {
        let base = URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent("VoiceAI-Workspace", isDirectory: true)
            .appendingPathComponent("Apps", isDirectory: true)
        if ProcessInfo.processInfo.environment["VOICE_AI_TEST_MODE"] == "1" {
            return FileManager.default.temporaryDirectory.appendingPathComponent("VoiceAI_BuilderApps", isDirectory: true)
        }
        return base
    }

    public func savedProjects() -> [BuilderProject] {
        lock.withLock { projectsCache }
    }

    /// Auto-detects whether a Local Ollama model is active/running or a Cloud API key is configured.
    public func detectActiveBuilderModel(probeLocalIfNeeded: Bool = true) async -> BuilderModelRoute {
        let router = ModelRouter.shared
        let kc = KeychainService.shared
        let hasOpenAI = !(kc.get(.openAIApiKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasClaude = !(kc.get(.anthropicApiKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAnyCloudKey = hasOpenAI || hasClaude

        func cloudRoute() -> BuilderModelRoute {
            if router.cloudProvider == "claude" && hasClaude {
                return .cloud(provider: "Claude", modelName: router.claudeModel)
            } else if hasOpenAI {
                return .cloud(provider: "OpenAI", modelName: router.openAIModel)
            } else {
                return .cloud(provider: "Claude", modelName: router.claudeModel)
            }
        }

        if probeLocalIfNeeded && ProcessInfo.processInfo.environment["VOICE_AI_TEST_MODE"] != "1" && !OllamaProvider.shared.isInstalledAndRunning {
            _ = await router.connectLocalOfflineModels(timeoutSeconds: 2.5)
        }
        let localRunning = OllamaProvider.shared.isInstalledAndRunning

        switch router.currentMode {
        case .local:
            if localRunning {
                return .localOllama(modelName: router.ollamaChatModel)
            }
            if hasAnyCloudKey {
                return cloudRoute()
            }
            return .unavailable(reason: "Local mode is active, but Ollama is not running and no Cloud API key is set. Start Ollama locally or add an OpenAI/Claude API key in Settings.")
        case .cloud:
            if hasAnyCloudKey {
                return cloudRoute()
            }
            if localRunning {
                return .localOllama(modelName: router.ollamaChatModel)
            }
            return .unavailable(reason: "No Cloud API key is configured and no local Ollama model is running. Please put your OpenAI or Claude API key in Settings (or start Ollama).")
        case .hybrid, .googleSearch:
            if localRunning {
                return .localOllama(modelName: router.ollamaChatModel)
            }
            if hasAnyCloudKey {
                return cloudRoute()
            }
            return .unavailable(reason: "No local model (Ollama) detected and no Cloud API key found. Please add an API key in Settings or start Ollama.")
        }
    }

    /// Extracts visual tokens (palette hexes, dark/light polarity, layout/typography notes)
    /// from one or more reference images into a structured `design.md` specification.
    public func extractDesignMarkdown(
        from imagePaths: [String],
        userContext: String = "",
        customVisionModel: VisionModel? = nil
    ) async -> String {
        let validPaths = imagePaths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !validPaths.isEmpty else { return "" }

        var sampledProfiles: [(name: String, width: Int, height: Int, bgHex: String, surfaceHex: String, textHex: String, accentHex: String, isDark: Bool, visionNotes: String)] = []
        let visionModel: VisionModel? = customVisionModel ?? (ProcessInfo.processInfo.environment["VOICE_AI_TEST_MODE"] == "1" ? nil : (try? ModelRouter.shared.resolveVisionModel()))

        for path in validPaths {
            let name = URL(fileURLWithPath: path).lastPathComponent
            let tokens = sampleImageVisualTokens(atPath: path)
            var vNotes = ""
            if let vm = visionModel, let img = NSImage(contentsOfFile: path) {
                let prompt = "Analyze this UI/website reference image concisely: describe its layout structure, typography style, card/button shapes, spacing, and visual mood in 4 bullet points."
                if let resp = try? await vm.analyzeImage(image: img, prompt: prompt, tools: nil) {
                    vNotes = resp.text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            sampledProfiles.append((name, tokens.width, tokens.height, tokens.bgHex, tokens.surfaceHex, tokens.textHex, tokens.accentHex, tokens.isDark, vNotes))
        }

        let primary = sampledProfiles[0]
        let isDarkTheme = sampledProfiles.filter(\.isDark).count * 2 >= sampledProfiles.count
        let mood = isDarkTheme ? "Dark, high-contrast, sleek modern interface" : "Light, airy, editorial interface"
        let borderHex = isDarkTheme ? "rgba(255, 255, 255, 0.12)" : "rgba(15, 23, 42, 0.08)"
        let mutedHex = isDarkTheme ? "#94A3B8" : "#475569"

        var md = """
        # design.md — Extracted Reference Design System

        ## 1. Visual Aesthetic & Mood
        - **Theme Polarity**: \(isDarkTheme ? "Dark Mode" : "Light Mode")
        - **Mood**: \(mood)
        \(userContext.isEmpty ? "" : "- **User Direction**: \(userContext)\n")
        ## 2. Extracted Color Palette (CSS Variables)
        ```css
        :root {
          --bg: \(primary.bgHex);
          --surface: \(primary.surfaceHex);
          --text: \(primary.textHex);
          --muted: \(mutedHex);
          --accent: \(primary.accentHex);
          --border: \(borderHex);
        }
        ```

        ## 3. Typography & Layout Rules
        - **Display Headings**: Bold geometric sans-serif (`Inter` / `-apple-system`), tight tracking (`-0.03em`), strong hierarchy.
        - **Cards & Containers**: Rounded corners (`16px`–`20px`), `1px solid var(--border)`, subtle surface elevation.
        - **Interactive Controls**: Pill or `12px`-rounded primary buttons using `var(--accent)` with crisp hover transitions.

        ## 4. Reference Images (\(sampledProfiles.count))
        """

        for (idx, p) in sampledProfiles.enumerated() {
            md += "\n### Image \(idx + 1): `\(p.name)` (\(p.width)×\(p.height))\n"
            md += "- Sampled Background: `\(p.bgHex)` | Surface: `\(p.surfaceHex)` | Accent: `\(p.accentHex)` | Polarity: \(p.isDark ? "Dark" : "Light")\n"
            if !p.visionNotes.isEmpty {
                md += "\(p.visionNotes)\n"
            }
        }
        return md
    }

    private func sampleImageVisualTokens(atPath path: String) -> (width: Int, height: Int, bgHex: String, surfaceHex: String, textHex: String, accentHex: String, isDark: Bool) {
        guard let nsImage = NSImage(contentsOfFile: path),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return (0, 0, "#090D16", "#111827", "#F8FAFC", "#3B82F6", true)
        }

        let w = cgImage.width
        let h = cgImage.height
        let sampleW = 32
        let sampleH = 32
        var raw = [UInt8](repeating: 0, count: sampleW * sampleH * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &raw,
            width: sampleW,
            height: sampleH,
            bitsPerComponent: 8,
            bytesPerRow: sampleW * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return (w, h, "#090D16", "#111827", "#F8FAFC", "#3B82F6", true)
        }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleW, height: sampleH))

        var sumR = 0.0, sumG = 0.0, sumB = 0.0
        var maxSat = -1.0
        var accentRGB: (Int, Int, Int) = (59, 130, 246)
        let count = sampleW * sampleH

        for i in 0..<count {
            let r = Int(raw[i * 4])
            let g = Int(raw[i * 4 + 1])
            let b = Int(raw[i * 4 + 2])
            sumR += Double(r)
            sumG += Double(g)
            sumB += Double(b)

            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            let sat = maxC == 0 ? 0.0 : Double(maxC - minC) / Double(maxC)
            if sat > maxSat && maxC > 45 {
                maxSat = sat
                accentRGB = (r, g, b)
            }
        }

        let avgR = Int(sumR / Double(count))
        let avgG = Int(sumG / Double(count))
        let avgB = Int(sumB / Double(count))
        let luminance = (0.299 * Double(avgR) + 0.587 * Double(avgG) + 0.114 * Double(avgB)) / 255.0
        let isDark = luminance < 0.5

        let bgHex = String(format: "#%02X%02X%02X", avgR, avgG, avgB)
        let surfR = isDark ? min(255, avgR + 18) : max(0, avgR - 10)
        let surfG = isDark ? min(255, avgG + 20) : max(0, avgG - 10)
        let surfB = isDark ? min(255, avgB + 26) : max(0, avgB - 8)
        let surfaceHex = String(format: "#%02X%02X%02X", surfR, surfG, surfB)
        let textHex = isDark ? "#F8FAFC" : "#0F172A"
        let accentHex = String(format: "#%02X%02X%02X", accentRGB.0, accentRGB.1, accentRGB.2)

        return (w, h, bgHex, surfaceHex, textHex, accentHex, isDark)
    }

    public func buildOrIterateResult(
        prompt: String,
        existingProject: BuilderProject? = nil,
        attachedImagePaths: [String] = [],
        designMarkdown: String? = nil,
        customModel: ChatModel? = nil,
        onStatus: (@Sendable (String) -> Void)? = nil
    ) async -> Result<BuilderProject, BuilderGenerationError> {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let agentName = existingProject == nil ? "App Builder (Beta)" : "App Builder • Edit (Beta)"
        let agentId = CodingAgentManager.shared.registerAgent(
            name: agentName,
            role: "Web & App Builder",
            initialStep: "Detecting active AI model (Local / Cloud)..."
        )
        onStatus?("Detecting active AI model...")

        let resolvedModel: ChatModel
        let modelLabel: String
        if let custom = customModel {
            resolvedModel = custom
            modelLabel = custom.modelIdentifier
        } else {
            let route = await detectActiveBuilderModel()
            switch route {
            case .localOllama(let modelName):
                modelLabel = "Local Ollama (\(modelName))"
                resolvedModel = OllamaProvider(model: modelName)
            case .cloud(let provider, let modelName):
                modelLabel = "\(provider) (\(modelName))"
                if provider == "Claude" {
                    let key = KeychainService.shared.get(.anthropicApiKey) ?? ""
                    resolvedModel = AnthropicClaudeProvider(apiKey: key, model: modelName)
                } else {
                    let key = KeychainService.shared.get(.openAIApiKey) ?? ""
                    resolvedModel = OpenAIProvider(apiKey: key, model: modelName)
                }
            case .unavailable(let reason):
                CodingAgentManager.shared.failAgent(agentId: agentId, error: reason)
                onStatus?(reason)
                return .failure(.missingModelOrAPIKey(reason))
            }
        }

        var activeDesignMD = designMarkdown ?? existingProject?.files.first(where: { $0.path == "design.md" })?.content
        if (activeDesignMD == nil || activeDesignMD?.isEmpty == true) && !attachedImagePaths.isEmpty {
            CodingAgentManager.shared.setAgentStep(agentId: agentId, step: "Extracting visual design from \(attachedImagePaths.count) image(s) into design.md...", progress: 0.22)
            onStatus?("Extracting visual design into design.md...")
            activeDesignMD = await extractDesignMarkdown(from: attachedImagePaths, userContext: cleanPrompt)
        }

        CodingAgentManager.shared.setAgentStep(agentId: agentId, step: "Generating code with \(modelLabel)...", progress: 0.45)
        onStatus?("Generating code with \(modelLabel)...")

        var generated: (title: String, summary: String, files: [BuilderProjectFile])
        do {
            generated = try await generateFilesWithModel(
                model: resolvedModel,
                prompt: cleanPrompt,
                existingProject: existingProject,
                attachedImagePaths: attachedImagePaths,
                designMarkdown: activeDesignMD
            )
            if let dmd = activeDesignMD, !dmd.isEmpty, !generated.files.contains(where: { $0.path == "design.md" }) {
                generated.files.append(BuilderProjectFile(path: "design.md", content: dmd))
            }
        } catch {
            let msg = "Code generation failed with \(modelLabel): \(error.localizedDescription)"
            CodingAgentManager.shared.failAgent(agentId: agentId, error: msg)
            onStatus?(msg)
            return .failure(.generationFailed(msg))
        }

        CodingAgentManager.shared.setAgentStep(agentId: agentId, step: "Writing \(generated.files.count) files & preparing live preview...", progress: 0.8)
        onStatus?("Writing files to workspace...")

        let slug = sanitizeSlug(generated.title.isEmpty ? "voice-app" : generated.title)
        let dirURL: URL
        if let existing = existingProject {
            dirURL = URL(fileURLWithPath: existing.directoryPath)
        } else {
            dirURL = Self.workspaceRoot().appendingPathComponent("\(slug)-\(UUID().uuidString.prefix(4))", isDirectory: true)
        }

        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        for file in generated.files {
            let fileURL = dirURL.appendingPathComponent(file.path)
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? file.content.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        let userTurn = BuilderChatTurn(role: "user", text: cleanPrompt)
        let assistantTurn = BuilderChatTurn(
            role: "assistant",
            text: "[\(modelLabel)] \(generated.summary)",
            touchedFiles: generated.files.map(\.path)
        )

        let finalProject: BuilderProject
        if var updated = existingProject {
            updated.files = mergeFiles(existing: updated.files, incoming: generated.files)
            updated.turns.append(contentsOf: [userTurn, assistantTurn])
            updated.updatedAt = Date()
            finalProject = updated
        } else {
            finalProject = BuilderProject(
                title: generated.title,
                prompt: cleanPrompt,
                files: generated.files,
                directoryPath: dirURL.path,
                turns: [userTurn, assistantTurn]
            )
        }

        saveProjectMetadata(finalProject)
        CodingAgentManager.shared.completeAgent(
            agentId: agentId,
            summary: "Built '\(finalProject.title)' with \(modelLabel) (\(finalProject.files.count) files)."
        )
        onStatus?("Live preview ready.")
        return .success(finalProject)
    }

    public func buildOrIterate(
        prompt: String,
        existingProject: BuilderProject? = nil,
        attachedImagePath: String? = nil,
        onStatus: (@Sendable (String) -> Void)? = nil
    ) async -> BuilderProject? {
        switch await buildOrIterateResult(
            prompt: prompt,
            existingProject: existingProject,
            attachedImagePaths: attachedImagePath.map { [$0] } ?? [],
            onStatus: onStatus
        ) {
        case .success(let p): return p
        case .failure: return nil
        }
    }

    // MARK: - Real LLM Code Generation

    private func generateFilesWithModel(
        model: ChatModel,
        prompt: String,
        existingProject: BuilderProject?,
        attachedImagePaths: [String],
        designMarkdown: String?
    ) async throws -> (title: String, summary: String, files: [BuilderProjectFile]) {
        let existingContext: String
        if let existing = existingProject {
            let fileSnippets = existing.files.filter { $0.path != "design.md" }.map { "--- \($0.path) ---\n\($0.content.prefix(3500))" }.joined(separator: "\n\n")
            existingContext = "\nExisting project '\(existing.title)':\n\(fileSnippets)\nApply the requested edit cleanly and return the updated files."
        } else {
            existingContext = ""
        }
        let designContext: String
        if let dmd = designMarkdown, !dmd.isEmpty {
            designContext = "\n\n--- design.md (STRICTLY FOLLOW THIS EXTRACTED DESIGN SYSTEM, COLORS, MOOD & LAYOUT) ---\n\(dmd)"
        } else {
            designContext = ""
        }
        let imageNote = attachedImagePaths.isEmpty ? "" : "\nReference images provided: \(attachedImagePaths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", "))."

        let sys = """
        You are Voice.AI App Builder (Beta), a Lovable/Replit-grade web app & website generator.
        Return ONLY valid JSON (no markdown commentary) with this exact schema:
        {"title": "Short Project Title", "summary": "1-2 sentence summary of what you built", "files": [{"path": "index.html", "content": "..."}, {"path": "styles.css", "content": "..."}, {"path": "app.js", "content": "..."}]}
        Requirements:
        - index.html must link styles.css and app.js cleanly with relative paths (<link rel="stylesheet" href="styles.css"> and <script src="app.js" defer></script>).
        - If a design.md specification is provided, match its exact CSS color variables, dark/light polarity, typography, card radii, and layout mood.
        - Write complete, production-quality, responsive, interactive HTML, CSS, and JavaScript tailored specifically to the user's request. Do not use placeholder comments like '// TODO'.
        """
        let userMsg = "Build request: \(prompt)\(imageNote)\(designContext)\(existingContext)"
        let resp = try await model.sendMessage(
            messages: [LLMChatMessage(role: .system, content: sys), LLMChatMessage(role: .user, content: userMsg)],
            tools: nil,
            jsonMode: true
        )
        guard let parsed = parseModelJSON(resp.text) else {
            throw NSError(domain: "AppBuilderEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "Model did not return valid multi-file JSON with index.html."])
        }
        return parsed
    }

    private func parseModelJSON(_ raw: String) -> (title: String, summary: String, files: [BuilderProjectFile])? {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "^```[a-zA-Z]*\\n?", with: "", options: .regularExpression)
                .replacingOccurrences(of: "```$", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // If local model wrapped JSON in prose, extract outermost { ... }
        if !cleaned.hasPrefix("{"), let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}"), start < end {
            cleaned = String(cleaned[start...end])
        }
        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let filesArr = json["files"] as? [[String: Any]] else {
            return nil
        }
        let files = filesArr.compactMap { item -> BuilderProjectFile? in
            guard let path = item["path"] as? String, let content = item["content"] as? String, !path.isEmpty else { return nil }
            return BuilderProjectFile(path: path, content: content)
        }
        guard files.contains(where: { $0.path == "index.html" }) else { return nil }
        let title = (json["title"] as? String) ?? "Voice.AI App"
        let summary = (json["summary"] as? String) ?? "Generated \(files.count) files for \(title)."
        return (title, summary, files)
    }

    private func buildDeterministicFallbackProject(
        prompt: String,
        existingProject: BuilderProject?
    ) -> (title: String, summary: String, files: [BuilderProjectFile]) {
        let lower = prompt.lowercased()
        let title = existingProject?.title ?? inferTitle(from: prompt)

        // If iterating on an existing fallback project, mutate theme/copy cleanly
        if let existing = existingProject,
           let oldHTML = existing.files.first(where: { $0.path == "index.html" })?.content,
           let oldCSS = existing.files.first(where: { $0.path == "styles.css" })?.content,
           let oldJS = existing.files.first(where: { $0.path == "app.js" })?.content {
            var newCSS = oldCSS
            var newHTML = oldHTML
            if lower.contains("dark") {
                newCSS = newCSS.replacingOccurrences(of: "#f8fafc", with: "#090d16")
                    .replacingOccurrences(of: "#0f172a", with: "#f8fafc")
                    .replacingOccurrences(of: "#ffffff", with: "#111827")
            }
            if lower.contains("pricing") && !newHTML.contains("id=\"pricing\"") {
                let pricingBlock = """
                <section id="pricing" class="card-grid">
                  <div class="card"><h3>Starter</h3><p class="price">$0/mo</p><p>Core workspace & live preview.</p></div>
                  <div class="card featured"><h3>Pro</h3><p class="price">$19/mo</p><p>Unlimited builds & exports.</p></div>
                </section>
                """
                newHTML = newHTML.replacingOccurrences(of: "</main>", with: "\(pricingBlock)\n</main>")
            }
            return (
                title,
                "Updated '\(title)' based on your request: \(prompt).",
                [
                    BuilderProjectFile(path: "index.html", content: newHTML),
                    BuilderProjectFile(path: "styles.css", content: newCSS),
                    BuilderProjectFile(path: "app.js", content: oldJS)
                ]
            )
        }

        let safeTitle = escapeHTML(title)
        let safePrompt = escapeHTML(prompt)

        let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1.0" />
          <title>\(safeTitle)</title>
          <link rel="stylesheet" href="styles.css" />
          <script src="app.js" defer></script>
        </head>
        <body>
          <div class="aura"></div>
          <header class="nav">
            <div class="brand"><span class="dot"></span>\(safeTitle)</div>
            <div class="nav-actions">
              <button class="btn ghost" id="themeToggle">Toggle Theme</button>
              <button class="btn primary" id="ctaBtn">Get Started</button>
            </div>
          </header>
          <main class="container">
            <section class="hero">
              <span class="badge">BUILT WITH VOICE.AI BETA</span>
              <h1>\(safeTitle)</h1>
              <p class="subtitle">Generated from your prompt: "\(safePrompt)"</p>
              <div class="interactive-bar">
                <input id="itemInput" type="text" placeholder="Add an item or test interactive state..." />
                <button class="btn primary" id="addBtn">Add</button>
              </div>
              <ul id="itemList" class="item-list"></ul>
            </section>
            <section class="card-grid">
              <div class="card">
                <h3>Live Interactive State</h3>
                <p>Add, toggle, and filter items directly inside the preview.</p>
              </div>
              <div class="card">
                <h3>Responsive Layout</h3>
                <p>Crafted with modern CSS grid, glass cards, and fluid spacing.</p>
              </div>
              <div class="card">
                <h3>Ready to Export</h3>
                <p>Clean multi-file HTML, CSS, and JavaScript saved to your workspace.</p>
              </div>
            </section>
          </main>
        </body>
        </html>
        """

        let css = """
        :root {
          --bg: #f8fafc;
          --surface: #ffffff;
          --text: #0f172a;
          --muted: #475569;
          --accent: #3b82f6;
          --border: rgba(15, 23, 42, 0.08);
        }
        body.dark {
          --bg: #090d16;
          --surface: #111827;
          --text: #f8fafc;
          --muted: #94a3b8;
          --accent: #60a5fa;
          --border: rgba(255, 255, 255, 0.1);
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
          font-family: -apple-system, BlinkMacSystemFont, "Inter", sans-serif;
          background: var(--bg);
          color: var(--text);
          min-height: 100vh;
          transition: background 0.25s, color 0.25s;
        }
        .aura {
          position: fixed; inset: 0; pointer-events: none; z-index: -1;
          background: radial-gradient(circle at 50% 85%, rgba(96, 165, 250, 0.28), transparent 55%);
        }
        .nav {
          max-width: 1040px; margin: 0 auto; padding: 20px 24px;
          display: flex; align-items: center; justify-content: space-between;
        }
        .brand { font-weight: 700; font-size: 16px; display: flex; align-items: center; gap: 8px; }
        .dot { width: 10px; height: 10px; border-radius: 50%; background: var(--accent); display: inline-block; }
        .nav-actions { display: flex; gap: 10px; }
        .container { max-width: 1040px; margin: 0 auto; padding: 48px 24px 80px; }
        .hero { text-align: center; max-width: 680px; margin: 0 auto 48px; }
        .badge {
          display: inline-block; font-size: 11px; font-weight: 700; letter-spacing: 0.08em;
          padding: 5px 12px; border-radius: 999px; background: rgba(59, 130, 246, 0.12); color: var(--accent);
          margin-bottom: 16px;
        }
        h1 { font-size: 42px; line-height: 1.12; letter-spacing: -0.03em; margin-bottom: 14px; }
        .subtitle { color: var(--muted); font-size: 16px; line-height: 1.5; margin-bottom: 28px; }
        .interactive-bar { display: flex; gap: 8px; max-width: 480px; margin: 0 auto 18px; }
        input {
          flex: 1; padding: 12px 14px; border-radius: 12px; border: 1px solid var(--border);
          background: var(--surface); color: var(--text); font-size: 14px; outline: none;
        }
        .btn {
          border: none; border-radius: 999px; padding: 10px 18px; font-size: 13px; font-weight: 600; cursor: pointer;
        }
        .btn.primary { background: #0f172a; color: #ffffff; }
        body.dark .btn.primary { background: #3b82f6; }
        .btn.ghost { background: var(--surface); color: var(--text); border: 1px solid var(--border); }
        .item-list { list-style: none; max-width: 480px; margin: 0 auto; display: flex; flex-direction: column; gap: 8px; text-align: left; }
        .item-list li {
          background: var(--surface); border: 1px solid var(--border); padding: 10px 14px; border-radius: 10px;
          display: flex; justify-content: space-between; align-items: center; font-size: 14px;
        }
        .card-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 18px; }
        .card {
          background: var(--surface); border: 1px solid var(--border); border-radius: 18px; padding: 22px;
          box-shadow: 0 8px 24px rgba(15, 23, 42, 0.04);
        }
        .card h3 { font-size: 16px; margin-bottom: 8px; }
        .card p { font-size: 14px; color: var(--muted); line-height: 1.5; }
        .price { font-size: 28px; font-weight: 700; color: var(--text) !important; margin-bottom: 6px; }
        """

        let js = """
        const list = document.getElementById("itemList");
        const input = document.getElementById("itemInput");
        const addBtn = document.getElementById("addBtn");
        const themeToggle = document.getElementById("themeToggle");
        const ctaBtn = document.getElementById("ctaBtn");

        const seed = ["Explore live preview", "Ask Voice.AI to customize colors"];
        function renderItem(text) {
          const li = document.createElement("li");
          li.innerHTML = `<span>${text}</span><button class="btn ghost" style="padding:4px 10px;font-size:11px;">Done</button>`;
          li.querySelector("button").addEventListener("click", () => li.remove());
          list.appendChild(li);
        }
        seed.forEach(renderItem);

        addBtn.addEventListener("click", () => {
          const val = input.value.trim();
          if (!val) return;
          renderItem(val);
          input.value = "";
        });
        input.addEventListener("keydown", (e) => { if (e.key === "Enter") addBtn.click(); });
        themeToggle.addEventListener("click", () => document.body.classList.toggle("dark"));
        ctaBtn.addEventListener("click", () => input.focus());
        """

        return (
            title,
            "Built '\(title)' with responsive HTML, CSS, and interactive JavaScript.",
            [
                BuilderProjectFile(path: "index.html", content: html),
                BuilderProjectFile(path: "styles.css", content: css),
                BuilderProjectFile(path: "app.js", content: js)
            ]
        )
    }

    // MARK: - Helpers & Persistence

    private func mergeFiles(existing: [BuilderProjectFile], incoming: [BuilderProjectFile]) -> [BuilderProjectFile] {
        var map = Dictionary(uniqueKeysWithValues: existing.map { ($0.path, $0) })
        for f in incoming { map[f.path] = f }
        return Array(map.values).sorted { $0.path < $1.path }
    }

    private func inferTitle(from prompt: String) -> String {
        let cleaned = prompt
            .replacingOccurrences(of: "(?i)^(build|create|make|generate)\\s+(me\\s+)?(a|an)?\\s*", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let words = cleaned.split(separator: " ").prefix(4).map(String.init)
        return words.isEmpty ? "Voice.AI App" : words.joined(separator: " ").capitalized
    }

    private func sanitizeSlug(_ title: String) -> String {
        let lower = title.lowercased()
        let allowed = CharacterSet.alphanumerics
        let mapped = lower.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(mapped).replacingOccurrences(of: "-+", with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func metadataURL() -> URL {
        Self.workspaceRoot().appendingPathComponent("projects_index.json")
    }

    private func loadSavedProjects() {
        guard let data = try? Data(contentsOf: metadataURL()),
              let decoded = try? JSONDecoder().decode([BuilderProject].self, from: data) else {
            return
        }
        lock.withLock { projectsCache = decoded }
    }

    private func saveProjectMetadata(_ project: BuilderProject) {
        lock.withLock {
            projectsCache.removeAll { $0.id == project.id }
            projectsCache.insert(project, at: 0)
            if projectsCache.count > 30 {
                projectsCache = Array(projectsCache.prefix(30))
            }
            let dir = Self.workspaceRoot()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(projectsCache) {
                try? data.write(to: metadataURL(), options: .atomic)
            }
        }
    }
}

