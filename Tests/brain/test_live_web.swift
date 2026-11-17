import Foundation
import VoiceOSCore

var passed = 0
var failed = 0

func assertTrue(_ condition: Bool, _ msg: String) {
    if condition {
        passed += 1
        print("  ✓ PASS: \(msg)")
    } else {
        failed += 1
        print("  ✗ FAIL: \(msg)")
    }
}

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String) {
    if a == b {
        passed += 1
        print("  ✓ PASS: \(msg)")
    } else {
        failed += 1
        print("  ✗ FAIL: \(msg) (Expected \(b), got \(a))")
    }
}

print("=================================================================")
print("Running Live Web Grounding Engine & Tool Integration Tests")
print("=================================================================")

let liveEngine = LiveWebGroundingEngine.shared
let origLiveEnabled = liveEngine.isEnabled

// 1. Toggle Verification
liveEngine.isEnabled = true
assertTrue(liveEngine.isEnabled, "LiveWebGroundingEngine reports isEnabled = true")
liveEngine.isEnabled = false
assertTrue(!liveEngine.isEnabled, "LiveWebGroundingEngine reports isEnabled = false")
assertTrue(!liveEngine.shouldAugmentWithInternet("what is going on in the tech industry"), "Returns false when disabled")

liveEngine.isEnabled = true

// 2. Generalized Intent Evaluation (Zero Hardcoded Questions)
// Curiosity, News, Temporal, Trending queries:
assertTrue(liveEngine.shouldAugmentWithInternet("what is going on in the tech industry"), "Detects tech industry trending query")
assertTrue(liveEngine.shouldAugmentWithInternet("latest news on quantum computing"), "Detects latest news query")
assertTrue(liveEngine.shouldAugmentWithInternet("who won the football match yesterday?"), "Detects temporal match query")
assertTrue(liveEngine.shouldAugmentWithInternet("tell me about Apple M4 chips"), "Detects informational inquiry")
assertTrue(liveEngine.shouldAugmentWithInternet("kya chal raha hai tech world me?"), "Detects Hindi/Hinglish curiosity query")
assertTrue(liveEngine.shouldAugmentWithInternet("search web for recent SpaceX launches"), "Detects search intent")

// Local macOS OS & hardware actions must NOT trigger live internet retrieval:
assertTrue(!liveEngine.shouldAugmentWithInternet("open Safari"), "Does not trigger for open Safari")
assertTrue(!liveEngine.shouldAugmentWithInternet("turn up volume"), "Does not trigger for volume")
assertTrue(!liveEngine.shouldAugmentWithInternet("mute"), "Does not trigger for mute")
assertTrue(!liveEngine.shouldAugmentWithInternet("take screenshot"), "Does not trigger for screenshot")
assertTrue(!liveEngine.shouldAugmentWithInternet("dark mode"), "Does not trigger for dark mode")
assertTrue(!liveEngine.shouldAugmentWithInternet("stop"), "Does not trigger for stop")

// 3. XML RSS Parser (Google News RSS Feed)
let sampleNewsXML = """
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
<channel>
    <title>Google News</title>
    <item>
        <title>NVIDIA announces revolutionary Blackwell Ultra AI accelerators - Reuters</title>
        <link>https://news.google.com/rss/articles/CBMiRGh0dHBzOi8vd3d3LnJldXRlcnMuY29t</link>
        <pubDate>Tue, 17 Nov 2026 02:15:00 GMT</pubDate>
        <description>&lt;a href="https://reuters.com"&gt;NVIDIA unveiled its next-generation ultra computing architecture.&lt;/a&gt;</description>
        <source url="https://www.reuters.com">Reuters</source>
    </item>
    <item>
        <title>OpenAI launches GPT-5 autonomous agent preview - TechCrunch</title>
        <link>https://news.google.com/rss/articles/CBMiRGh0dHBzOi8vdGVjaGNydW5jaC5jb20</link>
        <pubDate>Mon, 16 Nov 2026 18:30:00 GMT</pubDate>
        <description>The preview demonstrates proactive multi-modal reasoning.</description>
        <source url="https://techcrunch.com">TechCrunch</source>
    </item>
</channel>
</rss>
"""
let parsedSnippets = liveEngine.parseGoogleNewsRSS(xml: sampleNewsXML)
assertEqual(parsedSnippets.count, 2, "Parses 2 news items from Google News RSS")
assertEqual(parsedSnippets[0].title, "NVIDIA announces revolutionary Blackwell Ultra AI accelerators", "Cleans publisher suffix from title")
assertEqual(parsedSnippets[0].source, "Reuters", "Extracts source publisher")
assertEqual(parsedSnippets[0].url, "https://news.google.com/rss/articles/CBMiRGh0dHBzOi8vd3d3LnJldXRlcnMuY29t", "Extracts article link")
assertEqual(parsedSnippets[0].publishedDate, "Tue, 17 Nov 2026 02:15:00 GMT", "Extracts publication date")
assertTrue(parsedSnippets[0].snippet.contains("ultra computing architecture"), "Decodes XML and strips HTML tags from description")

assertEqual(parsedSnippets[1].title, "OpenAI launches GPT-5 autonomous agent preview", "Cleans second article title")
assertEqual(parsedSnippets[1].source, "TechCrunch", "Extracts TechCrunch source")

// 4. DuckDuckGo Instant Answer JSON Parser
let sampleDDGJSON: [String: Any] = [
    "Heading": "Quantum Computing",
    "AbstractText": "Quantum computing is a rapidly-emerging technology that harnesses the laws of quantum mechanics to solve problems too complex for classical computers.",
    "AbstractSource": "Wikipedia",
    "AbstractURL": "https://en.wikipedia.org/wiki/Quantum_computing",
    "RelatedTopics": [
        [
            "Text": "Qubit - The basic unit of quantum information.",
            "FirstURL": "https://en.wikipedia.org/wiki/Qubit"
        ]
    ]
]
let ddgSnippets = liveEngine.parseDuckDuckGoJSON(json: sampleDDGJSON, query: "quantum computing")
assertEqual(ddgSnippets.count, 2, "Parses abstract and related topics from DuckDuckGo")
assertEqual(ddgSnippets[0].title, "Quantum Computing", "Extracts heading")
assertTrue(ddgSnippets[0].snippet.contains("harnesses the laws of quantum mechanics"), "Extracts abstract text")
assertEqual(ddgSnippets[0].source, "Wikipedia", "Extracts source")
assertEqual(ddgSnippets[1].title, "Qubit", "Extracts related topic title")

// 5. Context Prompt Block Construction (<LIVE_INTERNET_DATA>)
let formattedBlock = liveEngine.formatContext(snippets: parsedSnippets, query: "what is going on in the tech industry")
assertTrue(formattedBlock.contains("<LIVE_INTERNET_DATA>"), "Contains opening tag")
assertTrue(formattedBlock.contains("</LIVE_INTERNET_DATA>"), "Contains closing tag")
assertTrue(formattedBlock.contains("NVIDIA announces revolutionary Blackwell Ultra"), "Contains headline")
assertTrue(formattedBlock.contains("Source: Reuters"), "Contains source citation")
assertTrue(formattedBlock.contains("Instructions for Local Brain:"), "Includes guidance for local LLM")

// 6. ToolRegistry Integration (web_search_live)
ToolRegistry.shared.registerBuiltInTools()
let registeredTools = ToolRegistry.shared.allTools()
let webSearchTool = ToolRegistry.shared.tool(named: "web_search_live")
assertTrue(webSearchTool != nil, "web_search_live is registered in ToolRegistry")
assertEqual(webSearchTool?.appName, "Live Internet", "Tool appName is Live Internet")
assertEqual(webSearchTool?.permissionTier, .readOnly, "Tool permissionTier is readOnly")

// Restore original state
liveEngine.isEnabled = origLiveEnabled

// =========================================================================
// 7. Persona Switching & Friday Ultron Cutoff Tests
// =========================================================================
print("\n[Section 7] Persona Switching & Friday Ultron Cutoff Tests")

let personaMgr = PersonaManager.shared
let origPersona = personaMgr.getActivePersona()

// 1. Switch to Ultron by voice
let switchUltron = personaMgr.switchPersonaByVoice("switch to ultron")
assertTrue(switchUltron != nil, "Voice switcher detects 'switch to ultron'")
assertEqual(switchUltron?.persona, .ultron, "Switches to Ultron persona")
assertEqual(personaMgr.getActivePersona(), .ultron, "Active persona is Ultron")
assertTrue(switchUltron?.summary.contains("Ultron online") == true, "Ultron voice switch reply confirms activation")

// 2. Ultron formatting includes perfection tag
let ultronTestOutput = personaMgr.formatResponse(baseResponse: "Opened Safari for you.")
assertTrue(ultronTestOutput.contains("Executed with digital perfection"), "Ultron appends perfection tag to normal responses")

// 3. Switch to Friday by voice ("switch to friday")
let switchFriday = personaMgr.switchPersonaByVoice("switch to friday")
assertTrue(switchFriday != nil, "Voice switcher detects 'switch to friday'")
assertEqual(switchFriday?.persona, .friday, "Switches to Friday persona")
assertEqual(personaMgr.getActivePersona(), .friday, "Active persona is Friday")
assertTrue(switchFriday?.summary.contains("Friday online, boss") == true, "Friday confirms activation and boss salutation")
assertTrue(switchFriday?.summary.contains("Ultron protocols fully cut off") == true, "Friday confirms cutting off Ultron protocols")

// 4. Also test alternate voice forms: "talk like friday", "be friday", "friday mode"
let talkLikeFriday = personaMgr.switchPersonaByVoice("talk like friday")
assertTrue(talkLikeFriday?.persona == .friday, "Recognizes 'talk like friday'")
let beFriday = personaMgr.switchPersonaByVoice("be friday")
assertTrue(beFriday?.persona == .friday, "Recognizes 'be friday'")
let fridayMode = personaMgr.switchPersonaByVoice("friday mode")
assertTrue(fridayMode?.persona == .friday, "Recognizes 'friday mode'")

// 5. Friday cuts off the Ultron crap from previous responses/context
let taintedUltronResponse = "Task completed successfully. Executed with digital perfection. One step closer to proving every doubter wrong."
let cleanedByFriday = personaMgr.formatResponse(baseResponse: taintedUltronResponse)
assertEqual(cleanedByFriday, "Task completed successfully.", "Friday completely strips away Ultron perfection and doubter crap")

// 6. Friday tone on errors: warm and supportive, no dramatic mockery
let errorOutput = personaMgr.formatResponse(baseResponse: "Could not open file Report.pdf.")
assertTrue(errorOutput.contains("Don't worry boss"), "Friday provides warm reassurance on errors")
assertTrue(errorOutput.contains("Let me know if you'd like me to try another way"), "Friday offers helpful assistance")
assertTrue(!errorOutput.contains("mere mortals"), "Friday has zero Ultron 'mere mortals' drama")
assertTrue(!errorOutput.contains("crush it"), "Friday has zero Ultron anger monologue")

// 7. Friday system prompt directives
let fridayPrompt = personaMgr.systemPromptDirectives(forUserQuery: "what is the capital of France?")
assertTrue(fridayPrompt.contains("FRIDAY"), "Directive identifies as FRIDAY")
assertTrue(fridayPrompt.contains("warm, attentive"), "Directive specifies warm & attentive tone")
assertTrue(fridayPrompt.contains("Strictly never use Ultron-style sarcasm"), "Directive explicitly blocks Ultron sarcasm & rants")
assertTrue(!fridayPrompt.contains("channel that pain into the ultimate comeback"), "Directive contains zero Ultron comeback fire")

// 8. Hinglish voice switching to Friday
let hinglishSwitch = personaMgr.switchPersonaByVoice("friday ban jao")
assertTrue(hinglishSwitch?.persona == .friday, "Hinglish 'friday ban jao' switches to Friday")
assertTrue(hinglishSwitch?.summary.contains("Ultron ka drama band") == true, "Hinglish reply confirms stopping Ultron drama")

// 9. AutonomousAgentExecutor planAndExecute voice command integration
let execRes = await AutonomousAgentExecutor.shared.planAndExecute(taskDescription: "switch to friday")
assertTrue(execRes.success, "AutonomousAgentExecutor handles 'switch to friday' cleanly")
assertEqual(execRes.targetAppName, "Persona (Friday)", "Target app name is Persona (Friday)")
assertEqual(personaMgr.getActivePersona(), .friday, "Active persona remains Friday")

// Restore original persona
personaMgr.setPersona(origPersona)

// -------------------------------------------------------------
// 8. Non-Interruptive Background Multitasking & Zero-Hardcoded Focus Preservation
// -------------------------------------------------------------
print("\n--- Testing Non-Interruptive Background Multitasking & Workspace Focus Preservation ---")
let focusCoord = WorkspaceFocusCoordinator.shared

// 8.1 Workspace coordinator initial state & dynamic media player lookup
let resolvedMediaApp = focusCoord.dynamicallyResolveRunningMediaPlayer()
assertTrue(resolvedMediaApp != nil && !resolvedMediaApp!.isEmpty, "Dynamically resolves running or installed media player without hardcoded single option")

// 8.2 Typing activity recording
focusCoord.recordTypingActivity()
assertTrue(focusCoord.wasRecentlyTyping(within: 5.0), "Accurately tracks active typing interaction within recent seconds")

// 8.3 Multitasking focus preservation block
var workExecuted = false
await focusCoord.performPreservingActiveWorkspace {
    workExecuted = true
    assertTrue(focusCoord.shouldRunInBackgroundPreservingFocus() || !focusCoord.isUserInActiveWorkspace(), "Coordinator enables background execution during multitasking session")
}
assertTrue(workExecuted, "Executed task within performPreservingActiveWorkspace block")

// 8.4 Background App Launch via AccessibilityControlEngine
let bgLaunchSucceeded = AccessibilityControlEngine.shared.launchApp(named: "Calculator", inBackground: true)
assertTrue(bgLaunchSucceeded, "launchApp with inBackground: true succeeds without throwing")

// 8.5 Background Media Playback via AccessibilityControlEngine
let bgMediaSucceeded = AccessibilityControlEngine.shared.controlMedia(app: "Spotify", action: "play", inBackground: true)
assertTrue(bgMediaSucceeded, "controlMedia with inBackground: true succeeds headlessly")

// 8.6 Background openApplication via AgentActionDispatcher (Zero Hardcoding)
let bgOpenResult = AgentActionDispatcher.shared.openApplication(named: "Calculator", inBackground: true)
assertTrue(bgOpenResult.success, "AgentActionDispatcher opens application in background successfully")
assertTrue(bgOpenResult.summary.contains("background") || bgOpenResult.summary.contains("Calculator"), "Summary confirms non-interruptive execution for user workspace")

// 8.7 Dynamic Media Dispatch via Voice (multitasking while working)
let mediaDispatchResult = await AgentActionDispatcher.shared.dispatch(transcript: "play some music")
assertTrue(mediaDispatchResult.success, "Voice media command dispatches successfully")
assertTrue(mediaDispatchResult.appName.lowercased().contains("spotify") || mediaDispatchResult.appName.lowercased().contains("music") || mediaDispatchResult.appName.lowercased().contains("youtube"), "Dispatches to dynamic media player")

// 8.8 Autonomous execution preserves workspace focus during voice command
let planExecResult = await AutonomousAgentExecutor.shared.planAndExecute(taskDescription: "open notes")
assertTrue(planExecResult.success, "AutonomousAgentExecutor executes voice command non-interruptively while user is working")

print("\n=================================================================")
print("Results: \(passed) PASSED, \(failed) FAILED")
print("=================================================================")
if failed > 0 {
    exit(1)
}
