import AppKit
import Foundation
import VoiceOSCore

private func extractFlagValue(_ name: String, from args: [String]) -> String? {
    if let idx = args.firstIndex(of: name), idx + 1 < args.count {
        return args[idx + 1]
    }
    let prefix = "\(name)="
    if let match = args.first(where: { $0.hasPrefix(prefix) }) {
        return String(match.dropFirst(prefix.count))
    }
    return nil
}

let args = CommandLine.arguments
if let textCommand = extractFlagValue("--text", from: args) {
    let isDryRun = args.contains("--dry-run")
    let autoApprove = args.contains("--approve")
    let jsonOutput = args.contains("--json")
    let isDictation = args.contains("--dictation")

    if isDryRun {
        setenv("VOICE_AI_DRY_RUN", "1", 1)
    }
    if let sandboxDir = extractFlagValue("--sandbox", from: args) {
        setenv("VOICE_AI_SANDBOX_DIR", sandboxDir, 1)
    }

    if autoApprove {
        ToolApprovalCoordinator.shared.setTestResponder { _ in true }
    } else if !isDryRun {
        // Default headless behavior fails closed on consequential actions
        ToolApprovalCoordinator.shared.setTestResponder { _ in false }
    } else {
        ToolApprovalCoordinator.shared.setTestResponder { _ in false }
    }

    var completed = false
    var capturedResult: AutonomousExecutionResult?

    Task {
        let mode: VoiceTriggerMode = isDictation ? .dictation : .agent
        let res = await AutonomousAgentExecutor.shared.planAndExecute(
            taskDescription: textCommand,
            triggerMode: mode
        )
        capturedResult = res
        completed = true
    }

    let deadline = Date().addingTimeInterval(20.0)
    while !completed && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
    }

    let finalRes = capturedResult ?? AutonomousExecutionResult(
        success: false,
        summary: "Timed out waiting for agent response.",
        targetAppName: "Timeout"
    )

    if jsonOutput {
        let payload: [String: Any] = [
            "success": finalRes.success,
            "summary": finalRes.summary,
            "targetAppName": finalRes.targetAppName,
            "targetURL": finalRes.targetURL?.absoluteString ?? "",
            "executedSteps": finalRes.executedSteps
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    } else {
        print("[\(finalRes.success ? "OK" : "FAIL")] app=\(finalRes.targetAppName) summary=\(finalRes.summary)")
        if !finalRes.executedSteps.isEmpty {
            print("STEPS: \(finalRes.executedSteps.joined(separator: " | "))")
        }
    }
    exit(finalRes.success ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
