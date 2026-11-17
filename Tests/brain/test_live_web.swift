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

print("\n=================================================================")
print("Results: \(passed) PASSED, \(failed) FAILED")
print("=================================================================")
if failed > 0 {
    exit(1)
}
