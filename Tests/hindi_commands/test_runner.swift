import Foundation
import VoiceOSCore

// Test Runner for Hindi / Hinglish Voice Computer Control Pipeline
// Executes 120 dataset utterances against HinglishTransliterator, AgentToolParser, and AgentActionDispatcher.

struct TestItem: Codable {
    let id: Int
    let category: String
    let script: String
    let utterance: String
    let expected_tool: String
    let expected_args: [String: String]
}

let datasetPath = "tests/hindi_commands/dataset.json"
guard let data = FileManager.default.contents(atPath: datasetPath),
      let items = try? JSONDecoder().decode([TestItem].self, from: data) else {
    print("❌ Failed to load dataset from \(datasetPath)")
    exit(1)
}

print("=================================================================")
print("  Voice.AI Hindi & Hinglish Computer Control Test Suite (120/120)")
print("=================================================================")
print("Loaded \(items.count) test utterances across Devanagari & Roman Hinglish.\n")

var intentPassCount = 0
var argsPassCount = 0
var routingPassCount = 0

var categoryStats: [String: (total: Int, passed: Int)] = [:]

for item in items {
    let currentCategory = item.category
    var stat = categoryStats[currentCategory] ?? (total: 0, passed: 0)
    stat.total += 1
    
    // Step 1: Normalization
    let normalized = HinglishTransliterator.normalize(item.utterance)
    
    // Step 2: Semantic Intent Parsing & Schema Mapping
    guard let parsedTool = AgentToolParser.parse(query: normalized) else {
        print("❌ [ID: \(item.id)] Intent Failed: '\(item.utterance)' -> Normalized: '\(normalized)' -> Tool: nil (Expected: \(item.expected_tool))")
        categoryStats[currentCategory] = stat
        continue
    }
    
    let isIntentMatch = (parsedTool.toolName == item.expected_tool)
    if isIntentMatch {
        intentPassCount += 1
    } else {
        print("❌ [ID: \(item.id)] Intent Mismatch: '\(item.utterance)' -> Got \(parsedTool.toolName), Expected: \(item.expected_tool)")
    }
    
    // Step 3: Argument Extraction Check
    var isArgsMatch = true
    switch parsedTool {
    case .openApp(let name):
        if let expectedName = item.expected_args["name"] {
            isArgsMatch = (name.lowercased() == expectedName.lowercased())
        }
    case .mediaPlay(let app, _, let action):
        if let expAction = item.expected_args["action"], action != expAction {
            isArgsMatch = false
        }
        if let expApp = item.expected_args["app"], (app ?? "").lowercased() != expApp.lowercased() {
            isArgsMatch = false
        }
    case .setVolume(_, let delta):
        if let expDelta = item.expected_args["delta"], let expD = Double(expDelta), let d = delta {
            isArgsMatch = (abs(d - expD) < 0.05)
        }
    case .openUrl(let url, _):
        if let expUrl = item.expected_args["url"], !url.contains(expUrl.replacingOccurrences(of: "https://www.", with: "").replacingOccurrences(of: "https://", with: "")) {
            isArgsMatch = false
        }
    case .messageDraft(let app, let recipient, _):
        if let expApp = item.expected_args["app"], app.lowercased() != expApp.lowercased() {
            isArgsMatch = false
        }
        if let expRecip = item.expected_args["recipient"], recipient.lowercased() != expRecip.lowercased() {
            isArgsMatch = false
        }
    case .systemControl(let action):
        if let expAct = item.expected_args["action"], action != expAct {
            isArgsMatch = false
        }
    case .windowAction(let action):
        if let expAct = item.expected_args["action"], action != expAct {
            isArgsMatch = false
        }
    default:
        break
    }
    
    if isArgsMatch {
        argsPassCount += 1
    } else {
        print("⚠️ [ID: \(item.id)] Args Mismatch: '\(item.utterance)' -> Tool: \(parsedTool)")
    }
    
    // Step 4: Routing & Dispatch Execution Readiness
    let isCommand = AgentActionDispatcher.shared.isCommandIntent(item.utterance)
    if isIntentMatch && isCommand {
        routingPassCount += 1
        stat.passed += 1
    }
    categoryStats[currentCategory] = stat
}

let total = Double(items.count)
let intentAccuracy = (Double(intentPassCount) / total) * 100.0
let argsAccuracy = (Double(argsPassCount) / total) * 100.0
let routingAccuracy = (Double(routingPassCount) / total) * 100.0

print("\n-----------------------------------------------------------------")
print("                        TEST RESULTS MATRIX                      ")
print("-----------------------------------------------------------------")
print(String(format: "Total Utterances:            %d", items.count))
print(String(format: "Intent Classification:       %d / %d (%.1f%%) [Target >= 95%%]", intentPassCount, items.count, intentAccuracy))
print(String(format: "Tool Argument Extraction:    %d / %d (%.1f%%) [Target >= 95%%]", argsPassCount, items.count, argsAccuracy))
print(String(format: "Routing & Execution Ready:   %d / %d (%.1f%%) [Target >= 90%%]", routingPassCount, items.count, routingAccuracy))
print("-----------------------------------------------------------------")

print("\nPer-Category Breakdown:")
for (cat, stat) in categoryStats.sorted(by: { $0.key < $1.key }) {
    let pct = (Double(stat.passed) / Double(stat.total)) * 100.0
    let padded = cat.padding(toLength: 16, withPad: " ", startingAt: 0)
    print("  • \(padded): \(stat.passed) / \(stat.total) (\(String(format: "%.1f", pct))%)")
}

if intentAccuracy >= 95.0 && argsAccuracy >= 95.0 && routingAccuracy >= 90.0 {
    print("\n✅ ALL TARGET BENCHMARKS ACHIEVED: Intent >= 95%, Args >= 95%, Routing >= 90%.")
    exit(0)
} else {
    print("\n❌ Benchmark target missed.")
    exit(1)
}
