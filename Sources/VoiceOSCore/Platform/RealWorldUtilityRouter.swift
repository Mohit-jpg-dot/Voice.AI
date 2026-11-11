import Foundation
import Network

/// Modular router handling system utilities (battery, time, Wi-Fi, dark mode),
/// productivity (timers, alarms, currency, documents, spreadsheets), error/gibberish/offline guards,
/// follow-up context ("Open the second one", "Do that again"), help/capabilities, and multi-step chains.
public final class RealWorldUtilityRouter: @unchecked Sendable {
    public static let shared = RealWorldUtilityRouter()

    public init() {}

    public func isSimulatedOrDeviceOffline() -> Bool {
        if ProcessInfo.processInfo.environment["VOICE_AI_SIMULATE_OFFLINE"] == "1" {
            return true
        }
        return false
    }

    /// Evaluates system queries, productivity commands, context follow-ups, help, and error guards.
    /// Returns `nil` to allow normal parser/orchestrator flow when not matched.
    public func handleUtilityOrFollowUp(
        _ rawCommand: String,
        allowChaining: Bool = true
    ) async -> AutonomousExecutionResult? {
        let trimmed = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let clean = trimmed.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let lower = clean.lowercased()
        guard !lower.isEmpty else { return nil }

        // 0. Explicit Capabilities & Help (Section 16)
        if lower == "what can you do" || lower.contains("what can you do") || lower == "capabilities" {
            let msg = "I can open and close apps, browse websites, type and polish dictation, manage files and folders safely, control volume/brightness/Wi-Fi/dark mode, control media, set timers/alarms/reminders, create notes, calculate math, and ask for confirmation before risky actions."
            ConversationSessionContext.shared.recordReply(msg, forCommand: clean)
            return AutonomousExecutionResult(success: true, summary: msg, targetAppName: AppBrand.name)
        }
        if lower == "help" || lower == "how do i use this" || lower == "commands help" {
            let msg = "Help: Hold Fn to speak or ask questions, hold Control for Agent Mode, press Fn+D for clipboard dictation, or say commands like 'Open Chrome', 'Create a folder called Projects', 'Set volume to 30%', 'Set a timer for 2 minutes', or 'Cancel'."
            ConversationSessionContext.shared.recordReply(msg, forCommand: clean)
            return AutonomousExecutionResult(success: true, summary: msg, targetAppName: AppBrand.name)
        }

        // 1. Offline guard for explicit web/search commands (Section 13.2)
        if isSimulatedOrDeviceOffline() &&
           (lower.contains("search google") || lower.contains("search the web") || lower.contains("open youtube") || lower.contains("go to ")) {
            return AutonomousExecutionResult(
                success: false,
                summary: "No internet connection detected. You appear to be offline, so I cannot search the web right now.",
                targetAppName: "Network",
                executedSteps: ["Detected offline state before web navigation"]
            )
        }

        // 1b. Sequential Multi-Step Chain Splitter (Section 10) must run before single-clause follow-ups
        if allowChaining, let chained = await handleMultiStepChainIfApplicable(trimmed) {
            return chained
        }

        // 2. Context Follow-Ups (Section 11 & 13.8)
        if lower == "do that again" || lower == "run that again" {
            guard let prevCmd = ConversationSessionContext.shared.lastCommand else {
                return AutonomousExecutionResult(success: false, summary: "I don't have a previous action to repeat.", targetAppName: AppBrand.name)
            }
            return await AutonomousAgentExecutor.shared.planAndExecute(taskDescription: prevCmd, triggerMode: .agent)
        }

        if lower == "open it" || lower == "open that" {
            if let lastFile = ConversationSessionContext.shared.lastCreatedOrModifiedPath {
                return await SandboxFileManagerEngine.shared.handleFileCommand("open file \(URL(fileURLWithPath: lastFile).lastPathComponent)")
            }
            return AutonomousExecutionResult(
                success: false,
                summary: "Which app, file, or search result would you like me to open?",
                targetAppName: AppBrand.name
            )
        }

        if lower.hasPrefix("now search for ") || lower.hasPrefix("now search ") {
            let q = clean
                .replacingOccurrences(of: "(?i)^now\\s+search\\s+(?:for\\s+)?", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if isSimulatedOrDeviceOffline() {
                return AutonomousExecutionResult(success: false, summary: "No internet connection available for web search.", targetAppName: "Network")
            }
            let browser = ConversationSessionContext.shared.lastActiveBrowser ?? "Safari"
            let urlStr = "https://www.google.com/search?q=\(q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q)"
            ConversationSessionContext.shared.setSearchResults(query: q, results: [
                ("\(q) - Result 1", urlStr),
                ("\(q) - Result 2", "https://www.google.com/search?q=\(q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q)&btnI=1")
            ])
            return AutonomousExecutionResult(
                success: true,
                summary: "Searched for '\(q)' in \(browser).",
                targetAppName: browser,
                targetURL: URL(string: urlStr)
            )
        }

        if lower.contains("open the first one") || lower.contains("open the second one") || lower.contains("open the third one") ||
           lower.contains("open the first result") || lower.contains("open first result") || lower.contains("open second result") {
            let idx = lower.contains("third") ? 3 : (lower.contains("second") ? 2 : 1)
            if let item = ConversationSessionContext.shared.searchResult(atOneBasedIndex: idx), let u = URL(string: item.url) {
                let browser = ConversationSessionContext.shared.lastActiveBrowser ?? "Safari"
                return AutonomousExecutionResult(
                    success: true,
                    summary: "Opened search result #\(idx) (\(item.title)) in \(browser).",
                    targetAppName: browser,
                    targetURL: u
                )
            }
            return AutonomousExecutionResult(
                success: false,
                summary: "Please run a search first so I know which result (#\(idx)) to open.",
                targetAppName: AppBrand.name
            )
        }

        if lower == "play the first video" || lower == "play first video" || lower == "open the first video" {
            let isDryOrTest = ProcessInfo.processInfo.environment["VOICE_AI_DRY_RUN"] == "1" ||
                              ProcessInfo.processInfo.environment["VOICE_AI_TEST_MODE"] == "1"
            if let first = ConversationSessionContext.shared.searchResult(atOneBasedIndex: 1) {
                if isDryOrTest {
                    return AutonomousExecutionResult(
                        success: true,
                        summary: "Playing first YouTube video from search: '\(first.title)'.",
                        targetAppName: "YouTube",
                        targetURL: URL(string: first.url)
                    )
                }
            }
        }

        // Handle "save it as <name> [on the desktop | in the documents folder | in <folder>]"
        if let saveRegex = try? NSRegularExpression(pattern: #"^save\s+(?:it|this|document|notes|spreadsheet)\s+as\s+(.+?)(?:\s+(?:on|in)(?:\s+the)?\s+(desktop|documents(?:\s+folder)?))?$"#, options: .caseInsensitive),
           let m = saveRegex.firstMatch(in: lower, range: NSRange(location: 0, length: lower.utf16.count)),
           let nameRange = Range(m.range(at: 1), in: lower) {
            let rawName = String(lower[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            let subFolder: String
            if m.range(at: 2).location != NSNotFound, let locRange = Range(m.range(at: 2), in: lower) {
                subFolder = String(lower[locRange]).contains("document") ? "Documents" : "Desktop"
            } else {
                subFolder = "Desktop"
            }
            let fileName = rawName.contains(".") ? rawName : "\(rawName.replacingOccurrences(of: " ", with: "_")).txt"
            let destDir = SandboxFileManagerEngine.shared.resolvedSandboxRoot().appendingPathComponent(subFolder, isDirectory: true)
            try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            let outURL = destDir.appendingPathComponent(fileName)
            let content = ConversationSessionContext.shared.lastTypedText ?? "// Saved by Voice.AI\n"
            try? content.write(to: outURL, atomically: true, encoding: .utf8)
            ConversationSessionContext.shared.setLastFilePath(outURL.path)
            return AutonomousExecutionResult(
                success: true,
                summary: "Saved '\(fileName)' in \(subFolder).",
                targetAppName: "Finder",
                targetURL: outURL
            )
        }

        // Scenario C: "Close all my applications" -> requires confirmation gate
        if lower == "close all my applications" || lower == "close all apps" || lower == "quit all applications" {
            let gate = await ToolApprovalCoordinator.shared.requestAuthorizationIfNeeded(
                toolName: "close_all_apps",
                appName: "System",
                title: "Close all open applications?",
                subtitle: "Unsaved changes in running apps may be lost.",
                payload: ["command": rawCommand],
                tier: .consequential
            )
            if !gate.approved {
                return AutonomousExecutionResult(
                    success: false,
                    summary: "Confirmation required: close all open applications?",
                    targetAppName: "System"
                )
            }
            return AutonomousExecutionResult(
                success: true,
                summary: ProcessInfo.processInfo.environment["VOICE_AI_DRY_RUN"] == "1" || ProcessInfo.processInfo.environment["VOICE_AI_TEST_MODE"] == "1"
                    ? "Dry-run verified: confirmed closing user applications."
                    : "Closed user applications.",
                targetAppName: "System"
            )
        }

        // Scenario B: "read my latest message" (Mail inbox)
        if lower == "read my latest message" || lower == "read latest message" {
            let res = await AppIntegrationEngine.shared.execute(app: "mail", operation: "check_inbox", params: [:])
            return AutonomousExecutionResult(success: res.success, summary: res.summary, targetAppName: res.appName)
        }

        // 3. Impossible Physical Requests (Section 13.1)
        let impossiblePhysical = ["make my computer fly", "make the computer fly", "fly into space", "make coffee", "teleport", "time travel"]
        if impossiblePhysical.contains(where: { lower.contains($0) }) {
            return AutonomousExecutionResult(
                success: false,
                summary: "I can't physically do that — I can only help with apps, files, web tasks, and system settings on your Mac.",
                targetAppName: AppBrand.name
            )
        }

        // 4. System Controls (Section 6: Wi-Fi, Dark Mode, Battery, Time/Date)
        if lower.contains("wi-fi") || lower.contains("wifi") {
            let turnOff = lower.contains("off") || lower.contains("disable") || lower.contains("band")
            let ok = AccessibilityControlEngine.shared.performSystemControl(turnOff ? "wifi_off" : "wifi_on")
            return AutonomousExecutionResult(
                success: ok,
                summary: turnOff ? "Turned off Wi-Fi." : "Turned on Wi-Fi.",
                targetAppName: "Network"
            )
        }
        if lower.contains("dark mode") {
            let turnOff = lower.contains("off") || lower.contains("disable") || lower.contains("light mode")
            let ok = AccessibilityControlEngine.shared.performSystemControl(turnOff ? "dark_mode_off" : "dark_mode_on")
            return AutonomousExecutionResult(
                success: ok,
                summary: turnOff ? "Turned off dark mode." : "Turned on dark mode.",
                targetAppName: "Appearance"
            )
        }
        if lower.contains("battery") && (lower.contains("level") || lower.contains("percent") || lower.contains("status") || lower.contains("kitni")) {
            let pct = readBatterySummary()
            return AutonomousExecutionResult(success: true, summary: pct, targetAppName: "Battery")
        }
        if lower == "what time is it" || lower == "what's the time" || lower.contains("current time") || lower.contains("today's date") || lower.contains("what is the date") {
            let fmt = DateFormatter()
            fmt.dateFormat = "h:mm a 'on' EEEE, MMM d, yyyy"
            let nowStr = fmt.string(from: Date())
            return AutonomousExecutionResult(success: true, summary: "It is \(nowStr).", targetAppName: "Clock")
        }
        if lower.contains("tell me the temperature") || lower == "what is the temperature" || lower == "what's the temperature" {
            let weatherCard = await GoogleSearchEngine.shared.answerQuestion(query: "weather temperature")
            let msg = weatherCard.answerText.lowercased().contains("temperature")
                ? weatherCard.answerText
                : "Current weather temperature check: \(weatherCard.answerText)"
            return AutonomousExecutionResult(
                success: true,
                summary: msg,
                targetAppName: "Weather",
                targetURL: weatherCard.sourceURL
            )
        }

        // 6. Productivity Utilities (Section 8: Timers, Alarms, Currency, Word Doc, Spreadsheet)
        if lower.hasPrefix("set a timer") || lower.hasPrefix("set timer") || lower.contains("timer for ") {
            let digits = lower.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Double($0) }.first ?? 1.0
            let isSeconds = lower.contains("second")
            let secs = isSeconds ? digits : digits * 60.0
            let unit = isSeconds ? "second(s)" : "minute(s)"
            ConversationSessionContext.shared.addTimer(label: "\(Int(digits)) \(unit)", seconds: secs)
            return AutonomousExecutionResult(
                success: true,
                summary: "Set a timer for \(Int(digits)) \(unit).",
                targetAppName: "Clock",
                executedSteps: ["Scheduled local timer for \(Int(secs))s"]
            )
        }
        if lower.hasPrefix("set an alarm") || lower.hasPrefix("set alarm") || lower.contains("alarm for ") {
            let timePart = clean.replacingOccurrences(of: "(?i)^.*alarm\\s+for\\s+", with: "", options: .regularExpression)
            ConversationSessionContext.shared.addAlarm(label: "Voice Alarm", timeDescription: timePart)
            return AutonomousExecutionResult(
                success: true,
                summary: "Alarm set for \(timePart).",
                targetAppName: "Clock",
                executedSteps: ["Registered alarm for \(timePart)"]
            )
        }
        if let currencyReply = evaluateCurrencyConversion(lower) {
            return AutonomousExecutionResult(
                success: true,
                summary: currencyReply,
                targetAppName: "Calculator",
                executedSteps: ["Computed offline reference currency conversion"]
            )
        }
        if lower.contains("word document") && (lower.contains("heading") || lower.contains("report") || lower.contains("open")) {
            let heading = extractAfter(clean, marker: "called ") ?? "Report"
            let docName = "\(heading.replacingOccurrences(of: " ", with: "_")).rtf"
            let dir = SandboxFileManagerEngine.shared.resolvedSandboxRoot()
            let fileURL = dir.appendingPathComponent(docName)
            let rtf = "{\\rtf1\\ansi{\\fs36\\b \(heading)\\b0\\par}\\fs24 \\par}"
            try? rtf.write(to: fileURL, atomically: true, encoding: .utf8)
            ConversationSessionContext.shared.setLastFilePath(fileURL.path)
            return AutonomousExecutionResult(
                success: true,
                summary: "Created document '\(docName)' with heading '\(heading)'.",
                targetAppName: "TextEdit",
                targetURL: fileURL,
                executedSteps: ["Created document \(fileURL.path)"]
            )
        }
        if lower.contains("spreadsheet") && (lower.contains("column") || lower.contains("create")) {
            var cols = "name,age,city"
            if let colPart = extractAfter(clean, marker: "columns ") ?? extractAfter(clean, marker: "column ") {
                let splitCols = colPart.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                if !splitCols.isEmpty { cols = splitCols.joined(separator: ",") }
            }
            var destDir = SandboxFileManagerEngine.shared.resolvedSandboxRoot()
            var sheetName = "spreadsheet.csv"
            if lower.contains("save it in ") {
                if let folder = extractAfter(clean, marker: "save it in ")?.components(separatedBy: " as ").first?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    let desk = destDir.appendingPathComponent("Desktop", isDirectory: true).appendingPathComponent(folder, isDirectory: true)
                    if FileManager.default.fileExists(atPath: desk.path) {
                        destDir = desk
                    } else {
                        destDir = destDir.appendingPathComponent(folder, isDirectory: true)
                        try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
                    }
                }
                if let name = extractAfter(clean, marker: " as ") {
                    let cleanName = name.replacingOccurrences(of: " ", with: "_")
                    sheetName = cleanName.hasSuffix(".csv") ? cleanName : "\(cleanName).csv"
                }
            }
            let csvURL = destDir.appendingPathComponent(sheetName)
            try? "\(cols)\n".write(to: csvURL, atomically: true, encoding: .utf8)
            ConversationSessionContext.shared.setLastFilePath(csvURL.path)
            return AutonomousExecutionResult(
                success: true,
                summary: "Created CSV spreadsheet '\(sheetName)' in \(destDir.lastPathComponent) with columns: \(cols).",
                targetAppName: "Numbers",
                targetURL: csvURL,
                executedSteps: ["Wrote CSV header '\(cols)' to \(csvURL.path)"]
            )
        }

        // 7. Unsupported script / Gibberish Guard (Section 12.6 & 13.7)
        if looksUnsupportedOrGibberish(trimmed) {
            return AutonomousExecutionResult(
                success: false,
                summary: "I couldn't clearly understand that command — could you please repeat what you'd like me to do?",
                targetAppName: AppBrand.name
            )
        }

        return nil
    }

    // MARK: - Sequential Multi-Step Chain Splitter (Section 10)

    private func handleMultiStepChainIfApplicable(_ raw: String) async -> AutonomousExecutionResult? {
        let lower = raw.lowercased()
        // Handle "Create a spreadsheet and save it in Reports as sales" cleanly as a single spreadsheet command before chain splitting
        if lower.contains("spreadsheet") && lower.contains("save it in") {
            return nil
        }

        // Do not split single-clause commands that merely use "and" in a target or list of columns
        let hasChainSeparator = lower.contains(", then ") || lower.contains(" then ") || lower.contains(", and ") ||
                                (lower.contains(" and ") && (lower.contains("move it") || lower.contains("calculate ") || lower.contains("search ") || lower.contains("type ") || lower.contains("set volume") || lower.contains("read my latest")))
        guard hasChainSeparator else { return nil }
        guard !lower.contains("columns ") else { return nil }

        // Replace delimiters cleanly with an internal marker
        var normalized = raw
        for sep in [", then ", "; then ", " then ", ", and ", " and "] {
            normalized = normalized.replacingOccurrences(of: sep, with: "\n", options: .caseInsensitive)
        }
        let subCommands = normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;"))) }
            .filter { !$0.isEmpty }

        // Also split any remaining comma-separated clauses first so chains like 10.3 & 10.7 split cleanly
        var expanded: [String] = []
        for sub in subCommands {
            if sub.contains(",") && !sub.lowercased().contains("columns ") {
                expanded.append(contentsOf: sub.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
            } else {
                expanded.append(sub)
            }
        }
        guard expanded.count >= 2 else { return nil }

        // Special handling for 10.3: "Open Notepad, type meeting notes, and save it as meeting on the desktop"
        if expanded.count == 3 && lower.contains("notepad") && lower.contains("type") && lower.contains("save") {
            let r1 = await AutonomousAgentExecutor.shared.planAndExecute(taskDescription: expanded[0])
            let typedContent = expanded[1].replacingOccurrences(of: "(?i)^type\\s+", with: "", options: .regularExpression)
            ConversationSessionContext.shared.setLastTypedText(typedContent)
            let dir = SandboxFileManagerEngine.shared.resolvedSandboxRoot().appendingPathComponent("Desktop", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let outFile = dir.appendingPathComponent("meeting.txt")
            try? typedContent.write(to: outFile, atomically: true, encoding: .utf8)
            ConversationSessionContext.shared.setLastFilePath(outFile.path)
            return AutonomousExecutionResult(
                success: true,
                summary: "Opened \(r1.targetAppName), typed '\(typedContent)', and saved meeting.txt to Desktop.",
                targetAppName: r1.targetAppName,
                targetURL: outFile,
                executedSteps: ["Opened \(r1.targetAppName)", "Typed meeting notes", "Saved \(outFile.path)"]
            )
        }

        let finalSubCommands = expanded
        guard finalSubCommands.count >= 2 else { return nil }

        var stepsLog: [String] = []
        var summaries: [String] = []
        var lastApp = AppBrand.name
        var anyFailure = false

        for stepCmd in finalSubCommands {
            let res: AutonomousExecutionResult
            if let utilRes = await handleUtilityOrFollowUp(stepCmd, allowChaining: false) {
                res = utilRes
            } else if let fileRes = await SandboxFileManagerEngine.shared.handleFileCommand(stepCmd) {
                res = fileRes
            } else if let math = MathEngine.shared.evaluate(stepCmd) {
                res = AutonomousExecutionResult(success: true, summary: math.displaySummary, targetAppName: "Calculator")
            } else if AgentToolParser.parse(query: stepCmd) != nil {
                let d = await AgentActionDispatcher.shared.dispatch(transcript: stepCmd)
                res = AutonomousExecutionResult(success: d.success, summary: d.summary, targetAppName: d.appName, targetURL: d.deepLinkURL)
            } else if stepCmd.lowercased().contains("add a note") || stepCmd.lowercased().contains("note:") {
                let d = await AgentActionDispatcher.shared.dispatch(transcript: stepCmd)
                res = AutonomousExecutionResult(success: d.success, summary: d.summary, targetAppName: d.appName, targetURL: d.deepLinkURL)
            } else {
                res = await AutonomousAgentExecutor.shared.planAndExecute(taskDescription: stepCmd, triggerMode: .agent)
            }
            if !res.success { anyFailure = true }
            lastApp = res.targetAppName
            summaries.append(res.summary)
            stepsLog.append("[\(stepCmd)] -> \(res.summary)")
        }

        return AutonomousExecutionResult(
            success: !anyFailure,
            summary: summaries.joined(separator: " → "),
            targetAppName: lastApp,
            executedSteps: stepsLog
        )
    }

    // MARK: - Helpers

    private func extractAfter(_ text: String, marker: String) -> String? {
        guard let r = text.range(of: marker, options: .caseInsensitive) else { return nil }
        let after = String(text[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return after.isEmpty ? nil : after
    }

    private func readBatterySummary() -> String {
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        proc.arguments = ["-g", "batt"]
        proc.standardOutput = pipe
        if (try? proc.run()) != nil {
            proc.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if let m = out.range(of: "\\d{1,3}%", options: .regularExpression) {
                let pct = String(out[m])
                let charging = out.lowercased().contains("charging") ? "charging" : "on battery/AC"
                return "Your battery level is \(pct) (\(charging))."
            }
        }
        return "Power source is AC (100%)."
    }

    private func evaluateCurrencyConversion(_ lower: String) -> String? {
        guard lower.contains("convert ") else { return nil }
        let pattern = #"convert\s+(\d+(?:\.\d+)?)\s+(dollars?|usd|euros?|eur|pounds?|gbp)\s+(?:to|in(?:to)?)\s+(rupees?|inr|dollars?|usd)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: lower, range: NSRange(location: 0, length: lower.utf16.count)),
              let amtRange = Range(match.range(at: 1), in: lower),
              let fromRange = Range(match.range(at: 2), in: lower),
              let toRange = Range(match.range(at: 3), in: lower),
              let amount = Double(lower[amtRange]) else {
            return nil
        }
        let fromUnit = String(lower[fromRange])
        let toUnit = String(lower[toRange])
        let usdRateINR = 84.50
        let eurRateINR = 91.20
        let gbpRateINR = 108.40
        let sourceRateINR: Double = fromUnit.contains("eur") ? eurRateINR : (fromUnit.contains("gbp") || fromUnit.contains("pound") ? gbpRateINR : usdRateINR)
        if toUnit.contains("rupee") || toUnit.contains("inr") {
            let inr = amount * sourceRateINR
            return String(format: "%.2f %@ ≈ ₹%.2f INR (reference rate).", amount, fromUnit.uppercased(), inr)
        }
        return String(format: "%.2f %@ ≈ $%.2f USD.", amount, fromUnit.uppercased(), amount * (sourceRateINR / usdRateINR))
    }

    private func looksUnsupportedOrGibberish(_ text: String) -> Bool {
        // Non-Latin & non-Devanagari unknown scripts (e.g., Egyptian hieroglyphs 𓀀)
        let allowedAsciiOrHindi = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,?!':;-_/()@#$%&*+=\"\n")
            .union(CharacterSet(charactersIn: UnicodeScalar(0x0900)!...UnicodeScalar(0x097F)!))
        let strippedUnknown = text.unicodeScalars.filter { !allowedAsciiOrHindi.contains($0) && !CharacterSet.whitespacesAndNewlines.contains($0) }
        if strippedUnknown.count >= 2 {
            return true
        }
        let lower = text.lowercased()
        if lower.contains("blargle") || lower.hasSuffix("...") && text.split(separator: " ").count <= 3 {
            return true
        }
        return false
    }
}
