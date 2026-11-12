import AppKit
import Foundation
import VoiceOSCore

var passed = 0
var failed = 0

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ name: String) {
    if actual == expected {
        print("  ✓ PASS: \(name)")
        passed += 1
    } else {
        print("  ✗ FAIL: \(name) - Expected '\(expected)', got '\(actual)'")
        failed += 1
    }
}

func assertTrue(_ condition: Bool, _ name: String) {
    if condition {
        print("  ✓ PASS: \(name)")
        passed += 1
    } else {
        print("  ✗ FAIL: \(name) - Expected true, got false")
        failed += 1
    }
}

print("=================================================================")
print("VoiceOS Automated Core Test Runner")
print("Machine: Apple M5 (16 GB RAM), macOS 26.5.2")
print("Timestamp: \(Date())")
print("=================================================================")

// Test Suite 1: Design Tokens
print("\n[Suite 1] Design Tokens & Constants")
assertEqual(DesignTokens.Radius.xs, 4, "Radius.xs equals 4")
assertEqual(DesignTokens.Radius.md, 12, "Radius.md equals 12")
assertEqual(DesignTokens.Radius.xxl, 24, "Radius.xxl equals 24")
assertEqual(DesignTokens.Spacing.unit4, 16, "Spacing.unit4 equals 16")

// Test Suite 2: Multilingual Language Detection (15 Diverse Languages)
print("\n[Suite 2] Multilingual Detection Engine")
let engine = MultilingualEngine.shared
let languages: [(text: String, expected: String, label: String)] = [
    ("Hello team, please review the pull request before our standup tomorrow.", "en", "English"),
    ("नमस्ते, क्या आप आज शाम की मीटिंग का समय बदल सकते हैं?", "hi", "Hindi Devanagari"),
    ("Spotify pe meri chill playlist laga do yaar.", "hi", "Hinglish Code-Switching"),
    ("こんにちは、明日のプロジェクトキックオフミーティングの議題を共有します。", "ja", "Japanese"),
    ("مرحبا بك، يرجى مراجعة التقرير المالي قبل نهاية اليوم.", "ar", "Arabic RTL"),
    ("Hola equipo, por favor revisen la propuesta antes de la reunión de hoy.", "es", "Spanish"),
    ("Bonjour à tous, voici le compte-rendu de notre discussion technique.", "fr", "French"),
    ("Guten Morgen, bitte prüfen Sie die Dokumentation und das Design.", "de", "German"),
    ("Olá pessoal, compartilhei o link com a gravação da apresentação.", "pt", "Portuguese"),
    ("您好，请查看今天上午更新的产品设计规范和代码库。", "zh", "Mandarin Chinese"),
    ("안녕하세요, 오늘 오후에 예정된 스프린트 회고 회의 링크입니다.", "ko", "Korean"),
    ("Привет, команда! Пожалуйста, протестируйте новый релиз приложения.", "ru", "Russian"),
    ("Ciao a tutti, vi invio la bozza della nuova landing page.", "it", "Italian"),
    ("Hallo allemaal, hier is de update over de nieuwe release van vandaag.", "nl", "Dutch"),
    ("Merhaba, lütfen en son güncelleme notlarını kontrol edin.", "tr", "Turkish")
]

for item in languages {
    let res = engine.detectLanguage(text: item.text)
    assertEqual(res.detectedLanguage.code, item.expected, "Detect \(item.label)")
}

// Test Suite 3: Dictation Polish & Filler Word Cleanup
print("\n[Suite 3] Dictation Polish & Filler Removal")
let polish = DictationPolishEngine.shared
let raw = "Um, like actually, I was thinking we should try wako ai for voice os today."
let polished = polish.polish(rawText: raw, profile: .general)
assertTrue(polished.polishedText.contains("WakoAI"), "Phonetic replacement 'wako ai' -> 'WakoAI'")
assertTrue(polished.correctionTags.count > 0, "Identified correction tags")

// Test Suite 4: Hotkey 250ms Hold Threshold
print("\n[Suite 4] Hotkey Tap vs Hold Timing")
let hk = HotkeyManager()
let t0: CFAbsoluteTime = 100.0
hk.handleKeyDown(key: "fn", timestamp: t0)
// Quick tap: 80ms
let tapRes = hk.handleKeyUp(key: "fn", timestamp: t0 + 0.08)
if case .passthroughTap(let d, _) = tapRes {
    assertTrue(d < 250, "Tap under 250ms passed through to system (\(Int(d))ms)")
} else {
    assertTrue(false, "Expected passthroughTap for 80ms key press")
}

// Long hold: 320ms
hk.handleKeyDown(key: "fn", timestamp: t0)
let holdRes = hk.handleKeyUp(key: "fn", timestamp: t0 + 0.32)
if case .holdToSpeak(let d, let mode) = holdRes {
    assertTrue(d >= 250, "Hold >= 250ms triggered VoiceOS (\(Int(d))ms)")
    assertEqual(mode, .dictation, "fn key triggers dictation mode")
} else {
    assertTrue(false, "Expected holdToSpeak for 320ms key press")
}

// Long hold: 320ms ctrl
hk.handleKeyDown(key: "ctrl", timestamp: t0)
let holdCtrlRes = hk.handleKeyUp(key: "ctrl", timestamp: t0 + 0.32)
if case .holdToSpeak(let d, let mode) = holdCtrlRes {
    assertTrue(d >= 250, "Hold >= 250ms triggered VoiceOS (\(Int(d))ms)")
    assertEqual(mode, .agent, "ctrl key triggers agent mode")
} else {
    assertTrue(false, "Expected holdToSpeak for 320ms ctrl key press")
}

// Test Suite 5: Connector Registry Integrity
print("\n[Suite 5] Connector Registry Parity")
let connectors = ConnectorRegistry.shared.connectors
assertEqual(connectors.count, 24, "Total registered connectors equals 24")
let hasSpotify = connectors.contains { $0.id == "spotify" }
let hasSlack = connectors.contains { $0.id == "slack" }
let hasLinear = connectors.contains { $0.id == "linear" }
assertTrue(hasSpotify, "Spotify connector present")
assertTrue(hasSlack, "Slack connector present")
assertTrue(hasLinear, "Linear connector present")

// Test Suite 6: Persistent Task Manager
print("\n[Suite 6] Task Manager State Transitions")
let tm = PersistentTaskManager.shared
let task = tm.enqueue(prompt: "Automated Test Task", app: "Linear", action: "create_issue")
assertEqual(task.status, .queued, "Initial task state is queued")
tm.updateProgress(id: task.id, progress: 0.5, elapsed: 1.2)
let runningTasks = tm.getRunningTasks()
assertTrue(runningTasks.contains { $0.id == task.id }, "Task marked running in active queue")
tm.markDone(id: task.id, elapsed: 2.4)
let all = tm.getAllTasks()
let finished = all.first { $0.id == task.id }
assertEqual(finished?.status, .done, "Task status transitioned to done")

// Test Suite 7: Agent Action Dispatcher & Intent Detection
print("\n[Suite 7] Agent Action Intent & App Resolution")
let dispatcher = AgentActionDispatcher.shared
assertTrue(dispatcher.isCommandIntent("open whatapp"), "Intent detected for 'open whatapp'")
assertTrue(dispatcher.isCommandIntent("open Safari"), "Intent detected for 'open Safari'")
assertTrue(dispatcher.isCommandIntent("search for Apple Silicon"), "Intent detected for 'search for Apple Silicon'")
assertTrue(dispatcher.isCommandIntent("create note Buy groceries"), "Intent detected for 'create note'")
assertTrue(!dispatcher.isCommandIntent("Here is a regular sentence I am dictating to you."), "Dictation text not misclassified as command")

// Test Suite 8: Complex Task & Coding Router (ChatGPT / Claude / Gemini)
print("\n[Suite 8] Complex Task & Coding Routing")
let router = AIProviderRouter.shared

// 8a. Coding task auto-detection
let pythonTask = router.evaluateAndRoute(transcript: "write a python script to parse JSON files")
assertTrue(pythonTask != nil, "Identified python scripting task as complex")
assertTrue(pythonTask?.isComplex == true, "Marked as complex task")

// 8b. Explicit Claude routing
let claudeTask = router.evaluateAndRoute(transcript: "ask claude to implement quicksort in Swift")
assertEqual(claudeTask?.provider, .claude, "Routed explicitly to Claude")
assertTrue(claudeTask?.url?.absoluteString.contains("claude.ai") == true, "Generated valid Claude URL")

// 8c. Explicit Gemini routing
let geminiTask = router.evaluateAndRoute(transcript: "in gemini design a microservices architecture")
assertEqual(geminiTask?.provider, .gemini, "Routed explicitly to Gemini")
assertTrue(geminiTask?.url?.absoluteString.contains("gemini.google.com") == true, "Generated valid Gemini URL")

// 8d. Regular dictation not misrouted
let simpleSentence = router.evaluateAndRoute(transcript: "Hello everyone I am speaking to my team today")
assertTrue(simpleSentence == nil, "Regular conversational speech not misrouted to AI provider")

// Test Suite 9: Autonomous Agent Background Execution & Redirect
print("\n[Suite 9] Autonomous Agent Background Execution & Redirect")
let autonomousExecutor = AutonomousAgentExecutor.shared

var progressEvents: [String] = []
let autoResult = await autonomousExecutor.planAndExecute(taskDescription: "create note Buy oat milk and apples") { msg in
    progressEvents.append(msg)
}

assertTrue(autoResult.success, "Autonomous task executed successfully")
assertTrue(autoResult.executedSteps.count >= 2, "Formulated multi-step execution plan")
assertTrue(autoResult.targetAppName.contains("Note"), "Identified target application as Apple Notes")
assertTrue(autoResult.targetURL != nil, "Generated valid redirect URL for user confirmation")

// Test Suite 10: Boring Notch Physical Motion & Geometry Invariants
print("\n[Suite 10] Boring Notch Physical Motion & Geometry Invariants")
assertEqual(NotchAnimations.openNotchSize.width, 640.0, "Open notch content width equals 640pt")
assertEqual(NotchAnimations.openNotchSize.height, 190.0, "Open notch content height equals 190pt")
assertEqual(NotchAnimations.shadowPadding, 20.0, "Shadow padding equals 20pt")
assertEqual(NotchAnimations.windowSize.width, 640.0, "Fixed window width equals 640pt")
assertEqual(NotchAnimations.windowSize.height, 210.0, "Fixed window height equals 210pt")

// Corner radii insets
assertEqual(NotchAnimations.cornerRadiusClosedTop, 6.0, "Closed top corner radius equals 6pt")
assertEqual(NotchAnimations.cornerRadiusClosedBottom, 14.0, "Closed bottom corner radius equals 14pt")
assertEqual(NotchAnimations.cornerRadiusOpenTop, 19.0, "Open top corner radius equals 19pt")
assertEqual(NotchAnimations.cornerRadiusOpenBottom, 24.0, "Open bottom corner radius equals 24pt")

// Timings and Dwell thresholds
assertEqual(NotchAnimations.minimumHoverDuration, 0.30, "Minimum hover dwell duration equals 300ms")
assertEqual(NotchAnimations.hoverExitGraceSeconds, 0.100, "Hover exit grace period equals 100ms")
assertEqual(NotchAnimations.sneakPeekDuration, 1.50, "Sneak peek duration equals 1.5s")
assertEqual(NotchAnimations.shortcutAutoCloseDuration, 3.00, "Shortcut auto-close duration equals 3.0s")
assertEqual(NotchAnimations.dropDebounce, 0.500, "Drop debounce equals 500ms")

// Test Suite 11: Brand Renaming & YC Badge Absence (Section 0.5)
print("\n[Suite 11] Brand Renaming & YC Badge Absence")
assertEqual(AppBrand.name, "Voice.AI", "Product name equals 'Voice.AI'")
assertEqual(AppBrand.bundleId, "ai.voice.app", "Bundle identifier equals 'ai.voice.app'")
assertEqual(AppBrand.dmgName, "Voice.AI-1.0.0.dmg", "DMG name equals 'Voice.AI-1.0.0.dmg'")

// 11b. Verify absence of Y Combinator / Backed by badges in website
let websiteDir = URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("website")
let indexHtmlPath = websiteDir.appendingPathComponent("index.html").path
let downloadHtmlPath = websiteDir.appendingPathComponent("download.html").path

let indexContent = (try? String(contentsOfFile: indexHtmlPath)) ?? ""
let downloadContent = (try? String(contentsOfFile: downloadHtmlPath)) ?? ""

assertTrue(!indexContent.lowercased().contains("backed by"), "website/index.html has no 'Backed by' claims")
assertTrue(!indexContent.lowercased().contains("y combinator"), "website/index.html has no 'Y Combinator' text")
assertTrue(!downloadContent.lowercased().contains("backed by"), "website/download.html has no 'Backed by' claims")
assertTrue(!downloadContent.lowercased().contains("y combinator"), "website/download.html has no 'Y Combinator' text")
assertTrue(!indexContent.contains("yc-badge"), "website/index.html has no 'yc-badge' class")
assertTrue(!downloadContent.contains("yc-badge"), "website/download.html has no 'yc-badge' class")

// Test Suite 12: Local Memory & Proactive Greeting (Section 1.J)
print("\n[Suite 12] Local Memory Files & Proactive Greeting")
let memoryMgr = LocalMemoryManager.shared
memoryMgr.remember(content: "Prefer VS Code for Swift scripts", category: "editor_preference", tags: ["swift", "ide"])
let entries = memoryMgr.search(query: "VS Code")
assertTrue(!entries.isEmpty, "Memory manager successfully recorded and retrieved preference")
assertEqual(entries.first?.category, "editor_preference", "Memory entry category preserved")

let fridayGreeting = memoryMgr.generateGreeting(persona: "Friday", userName: "Mohit")
assertTrue(fridayGreeting.contains("Mohit"), "Friday greeting includes user name")

let ultronGreeting = memoryMgr.generateGreeting(persona: "Ultron", userName: "Mohit")
assertTrue(ultronGreeting.contains("mortal"), "Ultron greeting contains theatrical persona wording")

// Test Suite 13: Persona Manager & Roast Safety Guardrails (Section 1.K)
print("\n[Suite 13] Persona Manager & Roast Safety Guardrail")
let personaMgr = PersonaManager.shared
personaMgr.setPersona(.roast)
assertEqual(personaMgr.getActivePersona(), .roast, "Roast mode actively selected")

let safetyTriggered = personaMgr.evaluateSafetyGuardrail(userInput: "please stop roasting and just write the code")
assertTrue(safetyTriggered, "Roast safety guardrail intercepted frustration phrase")
assertEqual(personaMgr.getActivePersona(), .friday, "Instantly fell back to supportive Friday persona")

// Test Suite 14: Floating Trigger Orb State (Visual Reference Request 2)
print("\n[Suite 14] Floating Trigger Orb State & Toggle")
let appState = AppState()
assertTrue(appState.isFloatingOrbVisible, "Floating trigger orb is visible by default")
appState.isFloatingOrbVisible = false
assertTrue(!appState.isFloatingOrbVisible, "Floating orb visibility toggled off")
appState.isFloatingOrbVisible = true
assertTrue(appState.isFloatingOrbVisible, "Floating orb visibility toggled on")

// Test Suite 15: Hinglish & Hindi Comprehension (User Feature Request)
print("\n[Suite 15] Hinglish & Hindi Comprehension Engine")
assertTrue(HinglishParser.isHinglishQuery("kya chal raha hai"), "Identified 'kya chal raha hai' as Hinglish")
assertTrue(HinglishParser.isHinglishQuery("spotify pe gaana chala do"), "Identified music intent as Hinglish")
assertTrue(HinglishParser.isHinglishQuery("screen pe kya hai"), "Identified screen vision as Hinglish")
assertTrue(HinglishParser.isHinglishQuery("naya tab kholo google"), "Identified new tab command as Hinglish")

let hinglishGreeting = HinglishParser.conversationalResponse(for: "kya haal hai")
assertTrue(hinglishGreeting != nil, "Generated natural Hinglish response for 'kya haal hai'")
assertTrue(hinglishGreeting?.contains("Boss") == true, "Hinglish response includes conversational address")

let hinglishMusic = HinglishParser.parse(query: "spotify pe gaana chalao")
assertEqual(hinglishMusic.app, "Spotify", "Hinglish music routed to Spotify")

let hinglishTab = HinglishParser.parse(query: "naya tab kholo swift programming")
assertEqual(hinglishTab.action, "open_new_tab", "Hinglish new tab intent recognized")

// Test Suite 16: Local Chat Memory & Multi-turn Conversation
print("\n[Suite 16] Local Chat Memory & Multi-turn History")
let chatMgr = LocalChatMemoryManager.shared
chatMgr.clearChat()
let initialCount = chatMgr.allMessages().count
_ = chatMgr.addMessage(role: "user", text: "Who founded Apple?")
_ = chatMgr.addMessage(role: "assistant", text: "Apple was founded by Steve Jobs, Steve Wozniak, and Ronald Wayne in 1976.", sourceTitle: "Wikipedia")
assertEqual(chatMgr.allMessages().count, initialCount + 2, "Saved user and assistant turns to local memory")

let prevContext = chatMgr.findRelevantContext(query: "what was my last question?")
assertTrue(prevContext != nil, "Found relevant turn for 'what was my last question?'")
assertTrue(prevContext?.contains("Who founded Apple?") == true, "Context recalls Steve Jobs query")

// Test Suite 17: Agent Action & Command Intent Detection
print("\n[Suite 17] Direct Question & Agent Action Intent")
let actionDispatcher = AgentActionDispatcher.shared
assertTrue(actionDispatcher.isCommandIntent("who was Isaac Newton?"), "Question with 'who was' detected as assistant query")
assertTrue(actionDispatcher.isCommandIntent("search for solar eclipses"), "Search keyword detected as assistant query")
assertTrue(actionDispatcher.isCommandIntent("kya hal hai"), "Hinglish greeting detected as assistant query")
assertTrue(actionDispatcher.isCommandIntent("what is on my screen?"), "Screen vision query detected as assistant query")
assertTrue(actionDispatcher.isCommandIntent("open a new tab with macos news"), "New tab automation detected as assistant query")
assertTrue(actionDispatcher.isCommandIntent("type hello world"), "Typing computer control detected as assistant query")
assertTrue(actionDispatcher.isCommandIntent("whatsapp kholo"), "Hinglish app command 'whatsapp kholo' detected as command")
assertEqual(actionDispatcher.extractAppOpenIntent(from: "whatsapp kholo"), "WhatsApp", "Extracted WhatsApp from 'whatsapp kholo'")
assertEqual(actionDispatcher.extractAppOpenIntent(from: "kholo whatsapp"), "WhatsApp", "Extracted WhatsApp from 'kholo whatsapp'")
assertEqual(actionDispatcher.extractAppOpenIntent(from: "safari kholo"), "safari", "Extracted Safari from 'safari kholo'")
assertEqual(actionDispatcher.extractTabOpenIntent(from: "open a new tab with macos news"), "macos news", "Extracted tab query from 'open a new tab with macos news'")
assertEqual(actionDispatcher.extractTabOpenIntent(from: "tab kholo swift programming"), "swift programming", "Extracted tab query from 'tab kholo swift programming'")

// Test Suite 18: "THE VOICE" Mode & Ambient Wake-Word
print("\n[Suite 18] THE VOICE Hands-Free Ambient Wake-Word Mode")
let ambientListener = TheVoiceAmbientListener.shared
assertTrue(ambientListener != nil, "TheVoiceAmbientListener initialized")
ambientListener.isTheVoiceModeEnabled = false
assertEqual(ambientListener.isTheVoiceModeEnabled, false, "THE VOICE mode can be disabled")
ambientListener.isTheVoiceModeEnabled = true
assertEqual(ambientListener.isTheVoiceModeEnabled, true, "THE VOICE mode can be enabled")

// Test Suite 19: Browser Tab Pool Manager & 30-Minute Idle TTL
print("\n[Suite 19] Browser Tab Pool & 30-Minute Inactivity Lifecycle")
let tabPool = BrowserTabPoolManager.shared
tabPool.recordQueryActivity(for: URL(string: "https://www.google.com"))
assertTrue(tabPool.isTabWarm, "Tab marked as warm during active querying")

// Test Suite 20: Visual Cursor Guide & Extended Computer Control Tools
print("\n[Suite 20] Autonomous Screen Tutor & Extended Computer Tools")
let tutor = VisualCursorGuideEngine.shared

// Blender tutorial resolution
let blenderBones = tutor.resolveTutorial(query: "hide the bones in blender", frontmostApp: "Blender")
assertEqual(blenderBones.appName, "Blender", "Blender bones tutorial resolves app name")
assertTrue(blenderBones.steps.count >= 2, "Blender tutorial generates multi-step plan")
assertTrue(blenderBones.summary.contains("bone") || blenderBones.summary.contains("Armature"), "Blender summary contains bone guidance")

let blenderAnim = tutor.resolveTutorial(query: "how to animate that thing in blender", frontmostApp: "Blender")
assertTrue(blenderAnim.steps.count >= 2, "Blender animation tutorial generates steps")

// Extended Tool Schema Parsing
let termTool = AgentToolParser.parse(query: "voice run this command on terminal ls -la and tell me what happened")
if case .runTerminalCommand(let cmd) = termTool {
    assertEqual(cmd, "ls -la", "Extracted terminal command 'ls -la'")
} else {
    print("  ✗ FAIL: Did not parse terminal command, got \(String(describing: termTool))")
    failed += 1
}

let codeTool = AgentToolParser.parse(query: "voice open vscode and make a new file as new.java and write that code")
if case .createCodeFile(let filename, _, let openInVSCode) = codeTool {
    assertEqual(filename, "new.java", "Extracted filename 'new.java'")
    assertTrue(openInVSCode, "Targeted VS Code opening")
} else {
    print("  ✗ FAIL: Did not parse code file creation, got \(String(describing: codeTool))")
    failed += 1
}

let brightTool = AgentToolParser.parse(query: "voice adjust the brightness")
if case .adjustBrightness = brightTool {
    print("  ✓ PASS: Parsed display brightness adjustment")
    passed += 1
} else {
    print("  ✗ FAIL: Did not parse brightness adjustment")
    failed += 1
}

let guideTool = AgentToolParser.parse(query: "voice how can i do this in blender to hide bones")
if case .tutorialGuide = guideTool {
    print("  ✓ PASS: Parsed tutorial guide request for visual cursor steering")
    passed += 1
} else {
    print("  ✗ FAIL: Did not parse tutorial guide request")
    failed += 1
}

print("\n[Suite 21] boringfloor.com Acoustic Sound Engine & Cues")
let soundEngine = BoringSoundEngine.shared
assertTrue(soundEngine.isSoundEnabled, "Sound feedback enabled by default")
soundEngine.isSoundEnabled = true
assertEqual(BoringSoundEngine.SoundCue.allCases.count, 10, "Exact 10 sound cues synthesized in memory")

// Test playback calls for all 10 cues
soundEngine.playQueued()
print("  ✓ PASS: playQueued cue invoked")
passed += 1

soundEngine.playSend()
print("  ✓ PASS: playSend cue invoked")
passed += 1

soundEngine.playReply()
print("  ✓ PASS: playReply cue invoked")
passed += 1

soundEngine.playDone()
print("  ✓ PASS: playDone cue invoked")
passed += 1

soundEngine.playDispatch()
print("  ✓ PASS: playDispatch cue invoked")
passed += 1

soundEngine.playAlert()
print("  ✓ PASS: playAlert cue invoked")
passed += 1

soundEngine.playError()
print("  ✓ PASS: playError cue invoked")
passed += 1

soundEngine.playNotchOpen()
print("  ✓ PASS: playNotchOpen cue invoked")
passed += 1

soundEngine.playNotchClose()
print("  ✓ PASS: playNotchClose cue invoked")
passed += 1

soundEngine.playTap()
print("  ✓ PASS: playTap cue invoked")
passed += 1

soundEngine.isSoundEnabled = false
assertEqual(soundEngine.isSoundEnabled, false, "Sound feedback can be muted")
soundEngine.isSoundEnabled = true
assertEqual(soundEngine.isSoundEnabled, true, "Sound feedback can be unmuted")

// Test Suite 22: World Search Deep Research Engine & English Understanding
print("\n[Suite 22] World Search Deep Research & English Language Control")
let worldSearchTool = AgentToolParser.parse(query: "world search quantum computing")
assertEqual(worldSearchTool, .worldSearch(topic: "quantum computing"), "Parsed 'world search quantum computing'")

let deepSearchTool = AgentToolParser.parse(query: "deep search artificial intelligence")
assertEqual(deepSearchTool, .worldSearch(topic: "artificial intelligence"), "Parsed 'deep search artificial intelligence'")

let wholeInternetTool = AgentToolParser.parse(query: "search the whole internet about black holes")
assertEqual(wholeInternetTool, .worldSearch(topic: "black holes"), "Parsed 'search the whole internet about black holes'")

let englishOpenWhatsApp = AgentToolParser.parse(query: "open WhatsApp")
assertEqual(englishOpenWhatsApp, .openApp(name: "WhatsApp"), "English instruction 'open WhatsApp'")

let englishOpenSafari = AgentToolParser.parse(query: "open Safari")
assertEqual(englishOpenSafari, .openApp(name: "Safari"), "English instruction 'open Safari'")

let englishScreenshot = AgentToolParser.parse(query: "take a screenshot")
assertEqual(englishScreenshot, .takeScreenshot(target: "screen", destination: "clipboard"), "English instruction 'take a screenshot'")

let englishVolume = AgentToolParser.parse(query: "turn down the volume")
assertEqual(englishVolume, .setVolume(level: nil, delta: -0.15), "English instruction 'turn down the volume'")

let worldReportTask = Task {
    await WorldSearchEngine.shared.performDeepSearch(topic: "Apple Silicon")
}
let worldReport = await worldReportTask.value
assertTrue(worldReport.fullReport.contains("# 🌍 World Search: Apple Silicon"), "World Search generates formatted deep title")
assertTrue(worldReport.fullReport.contains("Executive Summary"), "World Search contains Executive Summary")
assertTrue(worldReport.fullReport.contains("Core Architecture"), "World Search contains Core Architecture")
assertTrue(worldReport.fullReport.contains("Future Outlook"), "World Search contains Future Outlook")

// Test Suite 23: Hands-free Spotify Playback, Transport Controls & Colloquial Phrasing
print("\n[Suite 23] Hands-free Spotify Controls & Colloquial Phrasing")
let spotifyGenericSong = AgentToolParser.parse(query: "play a song on spotify")
assertEqual(spotifyGenericSong, .mediaPlay(app: "Spotify", query: "Top Hits", action: "play"), "Parsed 'play a song on spotify' to Top Hits")

let spotifyVoicePlayThisSong = AgentToolParser.parse(query: "Voice play this song Starboy")
assertEqual(spotifyVoicePlayThisSong, .mediaPlay(app: "Spotify", query: "Starboy", action: "play"), "Parsed 'Voice play this song Starboy' to specific track Starboy")

let spotifyPlayThisSongDilNu = AgentToolParser.parse(query: "play this song Dil Nu on Spotify")
assertEqual(spotifyPlayThisSongDilNu, .mediaPlay(app: "Spotify", query: "Dil Nu", action: "play"), "Parsed 'play this song Dil Nu on Spotify' to Dil Nu")

let spotifyChangeIt = AgentToolParser.parse(query: "change it")
assertEqual(spotifyChangeIt, .mediaPlay(app: "Spotify", query: nil, action: "next"), "Parsed 'change it' to next track")

let spotifyChangeSong = AgentToolParser.parse(query: "change the song")
assertEqual(spotifyChangeSong, .mediaPlay(app: "Spotify", query: nil, action: "next"), "Parsed 'change the song' to next track")

let spotifySkip = AgentToolParser.parse(query: "skip")
assertEqual(spotifySkip, .mediaPlay(app: "Spotify", query: nil, action: "next"), "Parsed 'skip' to next track")

let spotifyPrevious = AgentToolParser.parse(query: "previous")
assertEqual(spotifyPrevious, .mediaPlay(app: "Spotify", query: nil, action: "previous"), "Parsed 'previous' to previous track")

let spotifyAglaGana = AgentToolParser.parse(query: "agla gana")
assertEqual(spotifyAglaGana, .mediaPlay(app: "Spotify", query: nil, action: "next"), "Parsed 'agla gana' to next track")

let colloquialWhatsApp = AgentToolParser.parse(query: "WhatsApp Klo bro")
assertEqual(colloquialWhatsApp, .openApp(name: "WhatsApp"), "Parsed colloquial Hinglish 'WhatsApp Klo bro' to WhatsApp")

let youtubeSafariTab = AgentToolParser.parse(query: "Can you open YouTube tab on Safari")
assertEqual(youtubeSafariTab, .openUrl(url: "https://www.youtube.com", inBrowser: "Safari"), "Parsed 'Can you open YouTube tab on Safari' to openUrl")

let youtubeVideoQuery = AgentToolParser.parse(query: "play doreamon new episodes in hinid in youtune")
assertEqual(youtubeVideoQuery, .openUrl(url: "https://www.youtube.com/results?search_query=doraemon%20new%20episodes%20in%20hindi", inBrowser: "Safari"), "Parsed 'play doreamon new episodes in hinid in youtune' to direct YouTube search")

let youtubeHindiPlay = AgentToolParser.parse(query: "youtube pe doraemon chalao")
assertEqual(youtubeHindiPlay, .openUrl(url: "https://www.youtube.com/results?search_query=doraemon", inBrowser: "Safari"), "Parsed 'youtube pe doraemon chalao' to direct YouTube search")

// Test Suite 24: Minimalistic Natural Spoken Replies & URL Filter
print("\n[Suite 24] Minimalistic Natural Spoken Replies & URL Filter")
let spokenYouTube = SpeechPipelineEngine.formatMinimalisticSpokenReply(
    rawText: "Opened https://www.youtube.com/results?search_query=doraemon in Safari.",
    isHinglish: false
)
assertEqual(spokenYouTube, "currently playing this song", "YouTube URL mapped to 'currently playing this song'")

let spokenAppOpen = SpeechPipelineEngine.formatMinimalisticSpokenReply(
    rawText: "Opened WhatsApp on your Mac.",
    isHinglish: false
)
assertEqual(spokenAppOpen, "opened the app for you sir", "App opening mapped to 'opened the app for you sir'")

let spokenTerminal = SpeechPipelineEngine.formatMinimalisticSpokenReply(
    rawText: "Ran terminal command `ls -la`: total 504 files listed",
    isHinglish: false
)
assertEqual(spokenTerminal, "i just did", "Terminal command mapped to 'i just did'")

let spokenVolume = SpeechPipelineEngine.formatMinimalisticSpokenReply(
    rawText: "System volume set to 60%",
    isHinglish: false
)
assertEqual(spokenVolume, "i just did", "Volume adjustment mapped to 'i just did'")

let spokenHinglishApp = SpeechPipelineEngine.formatMinimalisticSpokenReply(
    rawText: "Opened Safari on your Mac.",
    isHinglish: true
)
assertEqual(spokenHinglishApp, "Aapke liye app khol diya sir.", "Hinglish app opening spoken politely")

let spokenHinglishMusic = SpeechPipelineEngine.formatMinimalisticSpokenReply(
    rawText: "Now playing: Shape of You on Spotify",
    isHinglish: true
)
assertEqual(spokenHinglishMusic, "Aapke liye gaana chala diya sir.", "Hinglish song mapped to 'Aapke liye gaana chala diya sir.'")

let spokenHinglishAction = SpeechPipelineEngine.formatMinimalisticSpokenReply(
    rawText: "Screenshot saved to Desktop.",
    isHinglish: true
)
assertEqual(spokenHinglishAction, "Kaam ho gaya sir.", "Hinglish action mapped to 'Kaam ho gaya sir.'")

let spokenClickVideo = SpeechPipelineEngine.formatMinimalisticSpokenReply(
    rawText: "Clicked on first video in Safari.",
    isHinglish: false
)
assertEqual(spokenClickVideo, "currently playing this song", "Click video mapped to 'currently playing this song'")

let spokenClickButton = SpeechPipelineEngine.formatMinimalisticSpokenReply(
    rawText: "Clicked on search bar in Safari.",
    isHinglish: false
)
assertEqual(spokenClickButton, "i just did", "Click button mapped to 'i just did'")

// Test Suite 25: Autonomous UI Element & Video Click Parser
print("\n[Suite 25] Autonomous UI Element & Video Click Parser")
let clickFirstVideoTab = AgentToolParser.parse(query: "Click on the first video you are seeing in this tab")
assertEqual(clickFirstVideoTab, .uiClick(description: "first video"), "Parsed 'Click on the first video you are seeing in this tab'")

let clickFirstVideo = AgentToolParser.parse(query: "click on the first video")
assertEqual(clickFirstVideo, .uiClick(description: "first video"), "Parsed 'click on the first video'")

let clickHinglishFirstVideo = AgentToolParser.parse(query: "first video pe click karo")
assertEqual(clickHinglishFirstVideo, .uiClick(description: "first video"), "Parsed 'first video pe click karo'")

let clickSearchBar = AgentToolParser.parse(query: "click the search bar")
assertEqual(clickSearchBar, .uiClick(description: "search bar"), "Parsed 'click the search bar'")

let clickPlay = AgentToolParser.parse(query: "click on play")
assertEqual(clickPlay, .uiClick(description: "play button"), "Parsed 'click on play'")

// Test Suite 26: Application Closure & Semantic Intent Disambiguation
print("\n[Suite 26] Application Closure & Semantic Intent Disambiguation")
let closeCurrentApp = AgentToolParser.parse(query: "close the app")
assertEqual(closeCurrentApp, .closeApp(name: nil), "Parsed 'close the app' to current app")

let closeThisApp = AgentToolParser.parse(query: "close this app")
assertEqual(closeThisApp, .closeApp(name: nil), "Parsed 'close this app' to current app")

let closeNamedSpotify = AgentToolParser.parse(query: "Close the application named Spotify on my Mac")
assertEqual(closeNamedSpotify, .closeApp(name: "Spotify"), "Parsed 'Close the application named Spotify on my Mac'")

let closeDirectSpotify = AgentToolParser.parse(query: "close Spotify")
assertEqual(closeDirectSpotify, .closeApp(name: "Spotify"), "Parsed 'close Spotify' to closeApp (NOT mediaPlay)")

let quitDirectSpotify = AgentToolParser.parse(query: "quit Spotify")
assertEqual(quitDirectSpotify, .closeApp(name: "Spotify"), "Parsed 'quit Spotify' to closeApp")

let hinglishCloseSpotify = AgentToolParser.parse(query: "spotify band karo")
assertEqual(hinglishCloseSpotify, .closeApp(name: "Spotify"), "Parsed 'spotify band karo' to closeApp")

let hinglishCloseApp = AgentToolParser.parse(query: "app band karo")
assertEqual(hinglishCloseApp, .closeApp(name: nil), "Parsed 'app band karo' to current app")

let clickVideoInTab = AgentToolParser.parse(query: "Click on the first video you are seeing in this tab")
assertEqual(clickVideoInTab, .uiClick(description: "first video"), "Parsed click first video in tab")

let tabIntentNotTriggered = AgentActionDispatcher.shared.extractTabOpenIntent(from: "Click on the first video you are seeing in this tab")
assertEqual(tabIntentNotTriggered, nil, "extractTabOpenIntent safely ignores click commands")

let spokenClosedApp = SpeechPipelineEngine.formatMinimalisticSpokenReply(
    rawText: "Closed Spotify on your Mac.",
    isHinglish: false
)
assertEqual(spokenClosedApp, "i just did", "Closed app mapped to 'i just did'")

let spokenHinglishClosed = SpeechPipelineEngine.formatMinimalisticSpokenReply(
    rawText: "Closed Spotify on your Mac.",
    isHinglish: true
)
assertEqual(spokenHinglishClosed, "Aapke liye app band kar diya sir.", "Hinglish closed app mapped to polite spoken reply")

// Test Suite 27: Chained Automation, Live Screen Guidance & UI Clicking
print("\n[Suite 27] Chained Automation, Live Screen Guidance & UI Clicking")
let chainedTerminalQuery = "write this command on terminal and take the screenshot and paste it into chatgpt"
let parsedChainedTerminal = AgentToolParser.parse(query: chainedTerminalQuery)
assertEqual(parsedChainedTerminal, .chainedWorkflow(plan: chainedTerminalQuery), "Parsed chained terminal + screenshot + chatgpt")

let chainedChatGPTQuery = "open chatgpt and write how does quantum computing work and ask about anything"
let parsedChainedChatGPT = AgentToolParser.parse(query: chainedChatGPTQuery)
assertEqual(parsedChainedChatGPT, .chainedWorkflow(plan: chainedChatGPTQuery), "Parsed open chatgpt and write prompt")

let screenTutorQuery = "tell me how can i do something based on what is on my computer screen"
let parsedScreenTutor = AgentToolParser.parse(query: screenTutorQuery)
assertEqual(parsedScreenTutor, .tutorialGuide(query: screenTutorQuery), "Parsed live screen tutor request")

let blenderVisQuery = "blender visualization tool"
let parsedBlenderVis = AgentToolParser.parse(query: blenderVisQuery)
assertEqual(parsedBlenderVis, .tutorialGuide(query: blenderVisQuery), "Parsed blender visualization tool")

let clickSubscribe = AgentToolParser.parse(query: "click on subscribe")
assertEqual(clickSubscribe, .uiClick(description: "subscribe"), "Parsed 'click on subscribe'")

let blenderPlan = VisualCursorGuideEngine.shared.resolveTutorial(query: "blender visualization", frontmostApp: "Blender")
assertEqual(blenderPlan.appName, "Blender", "Blender plan targets Blender")
assertTrue(blenderPlan.steps.count >= 3, "Blender plan has at least 3 interactive steps")

let spokenLiveGuide = SpeechPipelineEngine.formatMinimalisticSpokenReply(
    rawText: "Guiding you live on your screen.",
    isHinglish: false
)
assertEqual(spokenLiveGuide, "Guiding you through the steps now, sir.", "Spoken live guide mapped to natural reply")

// Test Suite 28: Local Offline Mode Automatic Ollama Connection
print("\n[Suite 28] Local Offline Mode Automatic Ollama Connection")
ModelRouter.shared.currentMode = .local
assertEqual(ModelRouter.shared.currentMode, .local, "ModelRouter switched to local mode")
let isInstalled = OllamaProvider.shared.isOllamaInstalledOnSystem
assertTrue(isInstalled, "Ollama installation detected on macOS")
let summary = ModelRouter.shared.getStatusSummary()
assertEqual(summary.chatProvider, "Ollama", "Chat provider set to Ollama in local mode")
assertEqual(summary.visionProvider, "Ollama", "Vision provider set to Ollama in local mode")
assertTrue(summary.privacyDescription.contains("100% On-Device"), "Local mode ensures 100% On-Device privacy")

// Test Suite 29: VoiceOS IPC Surface & Key Interception
print("\n[Suite 29] VoiceOS IPC Surface & Key Interception (APP-SECRET.md)")
let ipc = VoiceOSIPCSurface.shared
let defaultMic = await ipc.getDefaultMicrophoneName()
assertTrue(defaultMic.contains("Microphone"), "Default microphone name discovered via IPC")
let audioDevices = await ipc.getNativeAudioDevicesWithInfo()
assertTrue(audioDevices.count > 0, "Native audio devices enumerated via IPC")

let blockOk = ipc.blockKeys(["cmd_c", "cmd_v"])
assertTrue(blockOk, "Key suppression registered in IPC")
let blocked = ipc.getBlockedKeys()
assertTrue(blocked.contains("cmd_c"), "Blocked key present in blocked list")
let unblockOk = ipc.unblockKey("cmd_c")
assertTrue(unblockOk, "Key successfully unblocked")

// Test Suite 30: SQLite3 Database & Unified Config Store
print("\n[Suite 30] SQLite3 voice_session_insights & Config Store")
let db = VoiceOSDatabaseManager.shared
let testInsightId = "test_insight_" + UUID().uuidString
let inserted = try db.insertInsight(
    id: testInsightId,
    userId: "user_test_42",
    sourceUpdatedAt: "2026-11-07T00:00:00Z",
    metricsJSON: "{\"duration\": 4.2, \"wpm\": 145}"
)
assertTrue(inserted, "Inserted insight row into SQLite voice_session_insights table")
let insights = db.fetchInsights(for: "user_test_42")
assertTrue(insights.contains { ($0["id"] as? String) == testInsightId }, "Fetched insight from SQLite matching user_id index")

let config = VoiceOSConfigStore.shared
config.set("test_key", value: "voiceos_verified")
let retrievedVal = config.get("test_key") as? String
assertEqual(retrievedVal, "voiceos_verified", "Retrieved value from unified config.json store")
config.delete("test_key")

// Test Suite 31: Supabase Auth & ConnectRPC Schemas
print("\n[Suite 31] Supabase Auth Flow & ConnectRPC Protobuf Schemas")
let auth = AccountAuthService.shared
let authState = auth.generateNewAuthState()
assertTrue(authState["url"]?.contains("supabase.co") == true, "Generated valid Supabase OAuth authorize URL")
auth.isSelfHosted = true
assertTrue(auth.isAuthenticated, "isSelfHosted flag grants local authenticated state")
auth.isSelfHosted = false

let streamMsg = StreamMessageSchema(conversationId: "conv_1", chunkIndex: 0, deltaText: "Hello VoiceOS", isFinal: false)
assertEqual(streamMsg.deltaText, "Hello VoiceOS", "StreamMessageSchema serialization parity")
let screenContext = ScreenshotContextSchema(screenWidth: 1920, screenHeight: 1080, activeApplicationName: "Safari", base64JPEGData: "test_b64")
assertEqual(screenContext.activeApplicationName, "Safari", "ScreenshotContextSchema context parity")

// Test Suite 32: Unified Voice App Integrations (Email, WhatsApp, Slack, Discord, YouTube, Notion, Notes, Terminal)
print("\n[Suite 32] Unified App Integrations & Permission Gating")
assertEqual(AgentToolParser.parse(query: "draft an email to boss about quarterly report"), .appIntegration(app: "mail", operation: "draft", params: ["recipient": "boss", "subject": "quarterly report", "body": "", "query": "draft an email to boss about quarterly report"]), "Parsed Email draft intent")
assertEqual(AgentToolParser.parse(query: "check my unread emails"), .appIntegration(app: "mail", operation: "check_inbox", params: [:]), "Parsed Email check_inbox intent")
assertEqual(AgentToolParser.parse(query: "reply to this email saying thanks"), .appIntegration(app: "mail", operation: "reply", params: ["recipient": "", "body": "thanks", "query": ""]), "Parsed Email reply intent")
assertEqual(AgentToolParser.parse(query: "send slack message to #engineering saying build passed"), .appIntegration(app: "slack", operation: "send", params: ["recipient": "#engineering", "body": "build passed"]), "Parsed Slack send intent")
assertEqual(AgentToolParser.parse(query: "draft discord message to #general saying hopping on"), .appIntegration(app: "discord", operation: "draft", params: ["recipient": "#general", "body": "hopping on"]), "Parsed Discord draft intent")
assertEqual(AgentToolParser.parse(query: "mute youtube"), .appIntegration(app: "youtube", operation: "mute", params: [:]), "Parsed YouTube mute intent")
assertEqual(AgentToolParser.parse(query: "create notion page titled Roadmap with ship voice"), .appIntegration(app: "notion", operation: "create_page", params: ["title": "Roadmap", "body": "ship voice"]), "Parsed Notion create_page intent")
assertEqual(AgentToolParser.parse(query: "add call dentist to my Tasks note"), .appIntegration(app: "notes", operation: "append", params: ["title": "Tasks", "body": "call dentist"]), "Parsed Apple Notes append intent")
assertEqual(AgentToolParser.parse(query: "read terminal output"), .appIntegration(app: "terminal", operation: "read_output", params: [:]), "Parsed Terminal read_output intent")

let mailRes = await AppIntegrationEngine.shared.execute(app: "mail", operation: "draft", params: ["recipient": "team@example.com", "subject": "Sync", "body": "Ready"])
assertTrue(mailRes.success, "Email integration draft succeeds")
let waRes = await AppIntegrationEngine.shared.execute(app: "whatsapp", operation: "draft", params: ["recipient": "Rahul", "body": "On my way"])
assertTrue(waRes.success, "WhatsApp integration draft succeeds")
let discordRes = await AppIntegrationEngine.shared.execute(app: "discord", operation: "draft", params: ["recipient": "#general", "body": "Hello"])
assertTrue(discordRes.success, "Discord integration draft succeeds")
let ytRes = await AppIntegrationEngine.shared.execute(app: "youtube", operation: "forward", params: [:])
assertTrue(ytRes.success, "YouTube integration forward succeeds")
let notionRes = await AppIntegrationEngine.shared.execute(app: "notion", operation: "create_page", params: ["title": "Ideas", "body": "Voice OS"])
assertTrue(notionRes.success, "Notion integration create_page succeeds")
let notesRes = await AppIntegrationEngine.shared.execute(app: "notes", operation: "append", params: ["title": "Tasks", "body": "Buy coffee"])
assertTrue(notesRes.success, "Apple Notes integration append succeeds")
let termRes = await AppIntegrationEngine.shared.execute(app: "terminal", operation: "run_in_window", params: ["command": "ls -la"])
assertTrue(termRes.success, "Terminal integration run_in_window succeeds")

// Verify integration enable/disable toggle gates execution
let wasSlackEnabled = AppIntegrationEngine.shared.isAppIntegrated("slack")
AppIntegrationEngine.shared.setAppIntegrated("slack", enabled: false)
let blockedSlack = await AppIntegrationEngine.shared.execute(app: "slack", operation: "send", params: ["recipient": "#general", "body": "hello"])
assertEqual(blockedSlack.success, false, "Disabled Slack integration blocks voice execution")
assertTrue(blockedSlack.summary.contains("disabled"), "Disabled integration explains how to enable")
AppIntegrationEngine.shared.setAppIntegrated("slack", enabled: wasSlackEnabled)

// Test Suite 33: Phase 0 Foundations — ToolRegistry (MCP), EventBus, MemoryStore, Permission Tiers & SecretRedactor
print("\n[Suite 33] Phase 0 Foundations (ToolRegistry, EventBus, MemoryStore, Permissions & Redaction)")

// 1. SecretRedactor across OpenAI, Anthropic, GitHub, Notion, Slack, Webhooks & Bearer tokens
let rawSecretText = "openai=sk-abcdefghijklmnopqrstuvwxyz123456 claude=sk-ant-api03-secretkey987654321 gh=ghp_1234567890abcdefghij123456 notion=ntn_secret12345678901234 webhook=https://hooks.slack.com/services/T000/B000/XXXX header='Bearer mysecretjwt12345'"
let scrubbed = SecretRedactor.redact(rawSecretText)
assertTrue(!scrubbed.contains("sk-abcdefghijklmnopqrstuvwxyz"), "Redacted OpenAI key")
assertTrue(!scrubbed.contains("sk-ant-api03"), "Redacted Anthropic key")
assertTrue(!scrubbed.contains("ghp_1234567890"), "Redacted GitHub PAT")
assertTrue(!scrubbed.contains("ntn_secret123456"), "Redacted Notion token")
assertTrue(!scrubbed.contains("hooks.slack.com/services/T000"), "Redacted Slack webhook")
assertTrue(!scrubbed.contains("mysecretjwt12345"), "Redacted Bearer token")

// 2. EventBus pub/sub + filtered delivery + payload redaction
let bus = EventBus()
var receivedBatteryEvents: [VoiceEvent] = []
let subId = bus.subscribe(matching: .batteryChanged) { evt in
    receivedBatteryEvents.append(evt)
}
bus.publish(VoiceEvent(kind: .memoryUpdated, source: "test", payload: ["note": "ignore"]))
bus.publish(VoiceEvent(kind: .batteryChanged, source: "PowerMonitor", severity: .warning, payload: ["level": "15%", "token": "secret_value_should_redact"]))
assertEqual(receivedBatteryEvents.count, 1, "EventBus delivered filtered batteryChanged event only")
assertEqual(receivedBatteryEvents.first?.payload["token"], "[REDACTED_API_KEY]", "EventBus redacted sensitive payload key")
bus.unsubscribe(subId)
bus.publish(VoiceEvent(kind: .batteryChanged, source: "PowerMonitor", payload: ["level": "10%"]))
assertEqual(receivedBatteryEvents.count, 1, "EventBus stopped delivering after unsubscribe")

// 3. ToolRegistry (Built-in + MCP Discovery + Permission Tier Gating)
let registry = ToolRegistry.shared
let mcpSchemaList = registry.exportMCPToolsList()
assertTrue(mcpSchemaList.count >= 14, "ToolRegistry exports MCP tools/list schemas (\(mcpSchemaList.count))")
assertEqual(registry.tool(named: "math_evaluate")?.permissionTier, .readOnly, "math_evaluate assigned READ_ONLY tier")
assertEqual(registry.tool(named: "mail_draft")?.permissionTier, .reversible, "mail_draft assigned REVERSIBLE tier")
assertEqual(registry.tool(named: "mail_send")?.permissionTier, .consequential, "mail_send assigned CONSEQUENTIAL tier")

let mathInvoke = await registry.invoke(name: "math_evaluate", arguments: ["expression": "12 * 12"])
assertTrue(mathInvoke.success && mathInvoke.summary.contains("144"), "READ_ONLY tool executes without approval interruption")

let deniedSend = await registry.invoke(
    name: "mail_send",
    arguments: ["recipient": "alice@example.com", "body": "Ship it"],
    bypassApproval: false,
    customApprovalHandler: { action in
        return action.riskLevel == .high ? false : true
    }
)
assertEqual(deniedSend.success, false, "CONSEQUENTIAL tool blocked when Approval Card denied")
assertEqual(deniedSend.wasApproved, false, "Denied result records wasApproved == false")

let approvedSend = await registry.invoke(
    name: "mail_send",
    arguments: ["recipient": "alice@example.com", "subject": "Phase 0", "body": "Ship it"],
    bypassApproval: false,
    customApprovalHandler: { action in
        return action.riskLevel == .high && action.payload["permission_tier"] == "CONSEQUENTIAL"
    }
)
assertTrue(approvedSend.success && approvedSend.wasApproved, "CONSEQUENTIAL tool executes after explicit Approval Card approval")

// 4. MCP Client Adapter registration & tools/call execution
let mcpConfig = MCPServerConfig(
    id: "local_repo_mcp",
    name: "Repo MCP",
    endpointURL: URL(string: "http://127.0.0.1:8787/mcp")!
)
MCPClientAdapter.shared.setTransportOverride { _, payload, _ in
    let method = (payload["method"] as? String) ?? ""
    if method == "tools/call" {
        return ["jsonrpc": "2.0", "id": "1", "result": ["content": [["type": "text", "text": "3 open PRs"]]]]
    }
    return ["jsonrpc": "2.0", "id": "1", "result": ["status": "ok"]]
}
let mcpRegistered = try await MCPClientAdapter.shared.connectAndRegisterServer(
    config: mcpConfig,
    preloadedTools: [
        MCPToolDefinition(name: "list_prs", description: "Read open PRs", inputSchema: ["repo": "String"], isDestructive: false),
        MCPToolDefinition(name: "merge_pr", description: "Merge PR", inputSchema: ["id": "String"], isDestructive: true)
    ]
)
assertEqual(mcpRegistered.count, 2, "MCPClientAdapter registered 2 remote MCP tools")
assertEqual(registry.tool(named: "mcp.local_repo_mcp.list_prs")?.permissionTier, .readOnly, "Non-destructive MCP tool mapped to READ_ONLY")
assertEqual(registry.tool(named: "mcp.local_repo_mcp.merge_pr")?.permissionTier, .consequential, "Destructive MCP tool mapped to CONSEQUENTIAL")
let mcpReadCall = await registry.invoke(name: "mcp.local_repo_mcp.list_prs", arguments: ["repo": "Voice.AI"])
assertTrue(mcpReadCall.success && mcpReadCall.summary.contains("3 open PRs"), "MCP tools/call executed via ToolRegistry")
MCPClientAdapter.shared.setTransportOverride(nil)
registry.unregisterMCPServer(serverId: "local_repo_mcp")

// 5. Encrypted Per-Account Semantic MemoryStore
let acctA = "phase0_acctA_" + UUID().uuidString
let acctB = "phase0_acctB_" + UUID().uuidString
let memStore = MemoryStore(accountId: acctA)
await memStore.remember(content: "My favorite Swift concurrency pattern is actors with Sendable structs and secret sk-1234567890abcdefghijklmnop", scope: .longTerm, kind: .preference, tags: ["swift"])
await memStore.remember(content: "Current focus: Voice.AI JARVIS Phase 0 foundation", scope: .longTerm, kind: .project, tags: ["project"])
await memStore.remember(content: "User asked about battery threshold", scope: .shortTerm, kind: .turn, tags: ["turn"])
memStore.updateUserProfile { p in
    p.displayName = "Mohit"
    p.preferredLanguage = "hinglish"
}

let semanticHits = await memStore.searchSemantic(query: "Swift actors Sendable", scope: .longTerm, limit: 3)
assertTrue(!semanticHits.isEmpty && semanticHits[0].item.content.contains("actors"), "Semantic search retrieves relevant encrypted memory")
assertTrue(!semanticHits[0].item.content.contains("sk-1234567890"), "MemoryStore scrubbed API key before saving")
assertEqual(memStore.shortTermContext(limit: 5).count, 1, "Short-term scope stores conversation turns separately")
assertEqual(memStore.userProfile().displayName, "Mohit", "UserProfile persisted per account")

// Reload same account from disk ciphertext & confirm isolation from acctB
let memReloadedA = MemoryStore(accountId: acctA)
assertEqual(memReloadedA.allItems(scope: .longTerm).count, 2, "Encrypted long-term memories reload from per-account storage")
let memStoreB = MemoryStore(accountId: acctB)
assertEqual(memStoreB.allItems(scope: nil).count, 0, "Zero cross-account memory leakage between acctA and acctB")

let forgotCount = await memReloadedA.forget(matching: "Phase 0")
assertEqual(forgotCount, 1, "MemoryStore.forget removes matching entry cleanly")
memStore.clearAccountMemory(accountId: acctA)
memStoreB.clearAccountMemory(accountId: acctB)

// =========================================================================
// [Suite 34] Phase 1: JARVIS Feel (Wake Word, Streaming TTS Barge-In, Persona, Routines)
// =========================================================================
print("\n[Suite 34] Phase 1: JARVIS Feel (Wake Word, Streaming TTS, Persona & Routines)")

// 1. Configurable Wake-Word Extraction (English & Hinglish)
assertEqual(
    TheVoiceAmbientListener.extractCommand(from: "Jarvis, open Terminal", wakePhrase: "jarvis"),
    "open Terminal",
    "Configurable wake phrase 'jarvis' extracts trailing command cleanly"
)
assertEqual(
    TheVoiceAmbientListener.extractCommand(from: "hey friday check battery", wakePhrase: "friday"),
    "check battery",
    "Custom wake phrase 'friday' extracts trailing command cleanly"
)
assertEqual(
    TheVoiceAmbientListener.extractCommand(from: "jarvis gana bajao", wakePhrase: "jarvis"),
    "gana bajao",
    "Wake phrase supports Hinglish commands"
)
assertTrue(
    TheVoiceAmbientListener.extractCommand(from: "Your voice settings are saved", wakePhrase: "jarvis") == nil,
    "Wake detector ignores ordinary sentences mentioning 'voice' without wake prefix"
)
assertEqual(
    TheVoiceAmbientListener.extractCommand(from: "Hey voice check battery", wakePhrase: "jarvis"),
    "check battery",
    "Explicit 'Hey voice' prefix triggers fallback wake phrase cleanly"
)
assertEqual(
    TheVoiceAmbientListener.extractCommand(from: "Hey Jarvis", wakePhrase: "jarvis"),
    "",
    "Bare wake phrase extracts empty payload for immediate active-listening handoff"
)

// 2. Streaming TTS Chunking, Barge-In Generation & Selectable Kokoro Voice
let chunks = SpeechPipelineEngine.splitIntoSpeakableChunks(
    "Systems nominal, sir. CPU load is 14 percent! Ready for instructions?"
)
assertEqual(chunks.count, 3, "Streaming TTS splits multi-sentence text into 3 speakable chunks")
let genBeforeBargeIn = SpeechPipelineEngine.shared.currentTTSGeneration()
SpeechPipelineEngine.shared.bargeIn()
let genAfterBargeIn = SpeechPipelineEngine.shared.currentTTSGeneration()
assertTrue(genAfterBargeIn > genBeforeBargeIn, "SpeechPipelineEngine.bargeIn increments generation to cancel queued chunks")

let previousVoice = KokoroTTSEngine.shared.selectedVoiceId
KokoroTTSEngine.shared.selectedVoiceId = "bm_george"
assertEqual(KokoroTTSEngine.shared.selectedVoiceId, "bm_george", "KokoroTTSEngine persists selectable voice preset")
KokoroTTSEngine.shared.selectedVoiceId = previousVoice

// 3. JARVIS Persona Directives, Probability Warnings & Hindi/Hinglish Support
let origPersonaConfig = PersonaManager.shared.currentConfiguration()
PersonaManager.shared.updateConfiguration { cfg in
    cfg.activePersona = .jarvis
    cfg.humorLevel = 0.6
    cfg.honestProbabilityEstimates = true
    cfg.politeWarningsEnabled = true
    cfg.languageStyle = "auto"
}
let enDirective = PersonaManager.shared.systemPromptDirectives(forUserQuery: "check my battery")
assertTrue(enDirective.contains("JARVIS") && enDirective.contains("likelihood estimate"), "JARVIS directives include persona tone and probability guidance")

let hiDirective = PersonaManager.shared.systemPromptDirectives(forUserQuery: "मेरा सिस्टम चेक करो")
assertTrue(hiDirective.contains("Hindi"), "PersonaManager adapts prompt directives for Devanagari Hindi")

let hinglishDirective = PersonaManager.shared.systemPromptDirectives(forUserQuery: "bhai mera volume badhao")
assertTrue(hinglishDirective.contains("Hinglish"), "PersonaManager adapts prompt directives for Roman Hinglish")

let terminalRisk = PersonaManager.shared.assessActionConfidenceAndWarning(
    toolName: "terminal_run",
    tier: .consequential,
    target: "rm -rf build",
    languageHint: "en"
)
assertTrue(terminalRisk.probabilityPercent < 90 && (terminalRisk.warning?.contains("~") ?? false), "Consequential action returns honest probability estimate and polite caution")

let safeRead = PersonaManager.shared.assessActionConfidenceAndWarning(
    toolName: "math_evaluate",
    tier: .readOnly,
    target: "",
    languageHint: "en"
)
assertTrue(safeRead.probabilityPercent >= 90 && safeRead.warning == nil, "Read-only action needs no warning")
PersonaManager.shared.updateConfiguration { cfg in cfg = origPersonaConfig }

// 4. Routines & Protocols (English + Hinglish matching, custom CRUD & approval gate)
let routineManager = RoutineManager.shared
assertTrue(routineManager.allRoutines().count >= 3, "RoutineManager initializes built-in Good Morning, Focus Mode, and House Party protocols")
assertEqual(routineManager.matchRoutine(for: "Good morning")?.id, "builtin_good_morning", "Matches Good Morning briefing routine")
assertEqual(routineManager.matchRoutine(for: "kaam khatam")?.id, "builtin_house_party", "Matches Hinglish House Party trigger phrase")

let customRoutineId = "test_routine_\(UUID().uuidString)"
let customRoutine = VoiceRoutine(
    id: customRoutineId,
    name: "Test Protocol",
    triggerPhrases: ["run test protocol"],
    summary: "Unit test routine",
    isEnabled: true,
    isBuiltIn: false,
    steps: [
        VoiceRoutineStep(title: "Risky Terminal Step", actionPrompt: "echo hello", permissionTier: .consequential)
    ]
)
routineManager.saveRoutine(customRoutine)
assertEqual(routineManager.matchRoutine(for: "run test protocol")?.id, customRoutineId, "Custom routine saved and matched by trigger phrase")

final class ApprovalProbabilityRecorder: @unchecked Sendable {
    private let lock = NSLock()
    var sawProbability: Bool = false
    func record(_ val: Bool) {
        lock.withLock { sawProbability = sawProbability || val }
    }
}
let probRecorder = ApprovalProbabilityRecorder()
ToolApprovalCoordinator.shared.setTestResponder { action in
    let hasProb = (action.subtitle?.contains("~") ?? false) && action.payload["estimated_confidence"] != nil
    probRecorder.record(hasProb)
    return false
}
let blockedRoutineResult = await routineManager.runRoutine(customRoutine, onProgress: nil)
assertTrue(probRecorder.sawProbability, "Notch Approval Card receives honest probability estimate and caution subtitle")
assertTrue(!blockedRoutineResult.success && blockedRoutineResult.summary.contains("Cancelled pending approval"), "Routine blocks consequential step when Notch Approval is denied")
ToolApprovalCoordinator.shared.setTestResponder(nil)

routineManager.deleteRoutine(id: customRoutineId)
assertTrue(routineManager.matchRoutine(for: "run test protocol") == nil, "Custom routine deleted cleanly")

// =========================================================================
// [Suite 35] Phase 2: Proactive Assistant (Rules, Calendar/Mail/Messages, RAG, VLM, Smart Home, Health)
// =========================================================================
print("\n[Suite 35] Phase 2: Proactive Assistant (Rules, Calendar, RAG, VLM, Smart Home & Health)")

// 1. Proactive Rules Engine (Rate-limiting, Multi-Rule Evaluation & Dismiss)
final class MutableClockBox: @unchecked Sendable {
    private let lock = NSLock()
    var now = Date(timeIntervalSince1970: 1_700_000_000)
    func advance(by seconds: TimeInterval) {
        lock.withLock { now = now.addingTimeInterval(seconds) }
    }
    func current() -> Date { lock.withLock { now } }
}
let testClock = MutableClockBox()
let isolatedBus = EventBus()
let rulesEngine = ProactiveRulesEngine(
    eventBus: isolatedBus,
    nowProvider: { testClock.current() },
    persistRules: false
)
let firstBattAlert = rulesEngine.evaluateEvent(VoiceEvent(
    kind: .batteryChanged,
    source: "PowerMonitor",
    payload: ["level": "15", "charging": "false"]
))
assertTrue(firstBattAlert != nil && firstBattAlert?.kind == .lowBattery, "Proactive engine fires low battery alert at 15%")

let rateLimitedBatt = rulesEngine.evaluateEvent(VoiceEvent(
    kind: .batteryChanged,
    source: "PowerMonitor",
    payload: ["level": "12", "charging": "false"]
))
assertTrue(rateLimitedBatt == nil, "Proactive engine rate-limits duplicate low battery alert inside cooldown window")

testClock.advance(by: 650)
let afterCooldownBatt = rulesEngine.evaluateEvent(VoiceEvent(
    kind: .batteryChanged,
    source: "PowerMonitor",
    payload: ["level": "11", "charging": "false"]
))
assertTrue(afterCooldownBatt != nil, "Proactive engine fires again once cooldown expires")

isolatedBus.publish(VoiceEvent(
    kind: .buildStatusChanged,
    source: "SwiftBuild",
    payload: ["status": "failed", "project": "Voice.AI", "error": "Missing symbol"]
))
isolatedBus.publish(VoiceEvent(
    kind: .custom("email_arrived"),
    source: "MailMonitor",
    payload: ["sender": "boss@company.com", "subject": "URGENT: Release signoff", "important": "true"]
))
assertTrue(rulesEngine.activeAlerts().count >= 3, "EventBus automatically triggers failed build and urgent email alerts")
if let firstAlertId = rulesEngine.activeAlerts().first?.id {
    rulesEngine.dismissAlert(id: firstAlertId)
    assertTrue(!rulesEngine.activeAlerts().contains(where: { $0.id == firstAlertId }), "Dismissed proactive alert is hidden from active alerts")
}

// 2. Calendar Conflict Detection & Email/Messages Tiered Tools
let baseTime = Date()
CalendarMessagesService.shared.setTestEvents([
    CalendarEventItem(title: "Architecture Sync", startTime: baseTime, endTime: baseTime.addingTimeInterval(3600), calendarName: "Work"),
    CalendarEventItem(title: "Product Demo", startTime: baseTime.addingTimeInterval(1800), endTime: baseTime.addingTimeInterval(5400), calendarName: "Work")
])
let calToolRes = await registry.invoke(name: "calendar_summarize", arguments: ["range": "today"])
assertTrue(calToolRes.success && calToolRes.summary.contains("conflict"), "calendar_summarize detects overlapping meetings")
CalendarMessagesService.shared.setTestEvents(nil)

let mailSumRes = await registry.invoke(name: "mail_summarize", arguments: [:])
assertTrue(mailSumRes.success && !mailSumRes.summary.isEmpty, "mail_summarize READ_ONLY tool summarizes inbox")

let msgDraftRes = await registry.invoke(name: "messages_draft", arguments: ["recipient": "Aman", "body": "Running 5 mins late"])
assertTrue(msgDraftRes.success, "messages_draft REVERSIBLE tool prepares draft without consequential approval")

let msgSendDenied = await registry.invoke(
    name: "messages_send",
    arguments: ["recipient": "Aman", "body": "On my way"],
    bypassApproval: false,
    customApprovalHandler: { _ in false }
)
assertTrue(!msgSendDenied.success && msgSendDenied.requiresApproval && !msgSendDenied.wasApproved, "messages_send CONSEQUENTIAL blocks when Approval Card denies")

let msgSendApproved = await registry.invoke(
    name: "messages_send",
    arguments: ["recipient": "Aman", "body": "On my way"],
    bypassApproval: false,
    customApprovalHandler: { _ in true }
)
assertTrue(msgSendApproved.success && msgSendApproved.wasApproved, "messages_send CONSEQUENTIAL succeeds when Approval Card approves")

// 3. On-Device Local Knowledge Search (RAG) & Secret Scrubbing
let tempRagDir = FileManager.default.temporaryDirectory.appendingPathComponent("voiceai_rag_test_\(UUID().uuidString)", isDirectory: true)
try? FileManager.default.createDirectory(at: tempRagDir, withIntermediateDirectories: true)
let ragDocURL = tempRagDir.appendingPathComponent("deployment_notes.md")
try? "VoiceOS Phase 2 uses local embeddings on Apple Silicon. Never commit token sk-1234567890abcdefghijklmnop.".write(to: ragDocURL, atomically: true, encoding: .utf8)

let ragIndexURL = tempRagDir.appendingPathComponent("rag_index.json")
let ragStore = LocalKnowledgeStore(persistenceURL: ragIndexURL, loadPersisted: false)
let chunkCount = await ragStore.indexFolder(path: tempRagDir.path)
assertTrue(chunkCount >= 1, "LocalKnowledgeStore indexes user folder on-device")
let ragHits = await ragStore.search(query: "local embeddings Apple Silicon", limit: 3)
assertTrue(!ragHits.isEmpty && ragHits[0].chunk.snippet.contains("Apple Silicon"), "RAG semantic search locates indexed local file snippet")
assertTrue(!ragHits[0].chunk.snippet.contains("sk-1234567890"), "LocalKnowledgeStore scrubs API keys before indexing")
try? FileManager.default.removeItem(at: tempRagDir)

// 4. Vision-Language Screen Understanding (VLM / Circle-to-Ask Error & Button Diagnostics)
let vlmErrResult = await ScreenVisionService.shared.understandScreenQuestion(
    pngData: nil,
    ocrText: "Error: Permission denied accessing /Library/Application Support. [Retry] [Cancel]",
    appName: "Terminal",
    question: "What does this error mean?",
    allowCloudOptIn: false
)
assertTrue(vlmErrResult.answer.lowercased().contains("permission") && vlmErrResult.privacyBadge.contains("On-Device"), "Circle-to-Ask diagnoses error cleanly with On-Device privacy preserved")

let vlmBtnResult = await ScreenVisionService.shared.understandScreenQuestion(
    pngData: nil,
    ocrText: "Build finished with 1 warning.\n[Cancel]  [Continue]",
    appName: "Xcode",
    question: "Which button should I click?",
    allowCloudOptIn: false
)
assertEqual(vlmBtnResult.targetButtonLabel, "Continue", "Screen understanding identifies recommended actionable button")

// 5. Smart Home (Reversible Lights vs Consequential Locks + JWT Redaction)
assertEqual(
    SecretRedactor.redact("HA auth=eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJoYSJ9.signature12345"),
    "HA auth=[REDACTED_JWT]",
    "SecretRedactor scrubs Home Assistant JWT tokens"
)
let lightRes = await registry.invoke(
    name: "smarthome_control_comfort",
    arguments: ["device": "Living Room Lights", "action": "on"]
)
assertTrue(lightRes.success && lightRes.summary.contains("on"), "Smart Home comfort lights execute cleanly at REVERSIBLE tier")

let unlockDenied = await registry.invoke(
    name: "smarthome_control_security",
    arguments: ["device": "Front Door Lock", "action": "unlock"],
    bypassApproval: false,
    customApprovalHandler: { _ in false }
)
assertTrue(!unlockDenied.success && unlockDenied.requiresApproval, "Smart lock unlock strictly requires CONSEQUENTIAL approval")

let unlockApproved = await registry.invoke(
    name: "smarthome_control_security",
    arguments: ["device": "Front Door Lock", "action": "unlock"],
    bypassApproval: false,
    customApprovalHandler: { _ in true }
)
assertTrue(unlockApproved.success && unlockApproved.wasApproved && unlockApproved.summary.contains("unlocked"), "Smart lock unlocks after explicit Approval Card approval")

// 6. Opt-In On-Device Apple Health Import & Trend Warnings
let tempHealthFile = FileManager.default.temporaryDirectory.appendingPathComponent("health_test_\(UUID().uuidString).json")
let healthMgr = HealthInsightsManager(storageURL: tempHealthFile, loadPersisted: false)
assertEqual(healthMgr.isOptedIn(), false, "Apple Health integration is opt-in and disabled by default")
healthMgr.setOptedIn(true)
let sampleXML = """
<HealthData>
  <Record type="HKQuantityTypeIdentifierStepCount" value="4200"/>
  <Record type="HKQuantityTypeIdentifierRestingHeartRate" value="91"/>
  <Record type="HKQuantityTypeIdentifierAppleSleepingHours" value="5.2"/>
</HealthData>
"""
let importedHealthCount = healthMgr.importAppleHealthXML(sampleXML)
assertEqual(importedHealthCount, 3, "HealthInsightsManager parses Apple Health export.xml records cleanly")
let digest = healthMgr.computeDigest()
assertTrue(digest.totalSteps == 4200 && digest.trendWarnings.count >= 2, "HealthInsightsManager computes metrics and detects elevated HR & sleep deficit warnings")
healthMgr.clearAllData()

// =========================================================================
// [Suite 36] Phase 3: Advanced (Iron Legion, CAD/Physics/Hologram, Cyber Defense, Camera Vision, Phone Companion, Plugins & Scope)
// =========================================================================
print("\n[Suite 36] Phase 3: Advanced (Iron Legion, CAD/Physics, Security, Camera, Companion & Plugins)")

// 1. Iron Legion Parallel Subagents (live in CodingAgentManager)
let preAgentsCount = CodingAgentManager.shared.activeAgents.count
let legionRes = await IronLegionCoordinator.shared.dispatchParallelMission(goal: "Inspect Voice.AI Phase 3")
assertEqual(legionRes.workerResults.count, 3, "Iron Legion executes parallel Research, Code, and Summarize workers")
assertTrue(CodingAgentManager.shared.activeAgents.count >= preAgentsCount + 3, "Iron Legion workers appear live in CodingAgentManager / Agents tab")

// 2. Engineering CAD, Physics Simulation & 3D Hologram HTML
let cadRes = EngineeringStudioEngine.shared.generateCAD(shape: .gear, backend: .openscad, widthMM: 80, heightMM: 80, depthMM: 12)
assertTrue(cadRes.sourceCode.contains("teeth") && cadRes.hologramHTML.contains("<canvas") && cadRes.hologramHTML.contains("HOLOGRAM"), "EngineeringStudio generates valid OpenSCAD gear & offline 3D Hologram HTML")

let cadQueryRes = EngineeringStudioEngine.shared.generateCAD(shape: .bracket, backend: .cadquery)
assertTrue(cadQueryRes.sourceCode.contains("cadquery"), "EngineeringStudio also supports CadQuery Python script generation")

let projSim = EngineeringStudioEngine.shared.simulateProjectile(velocityMS: 20, angleDegrees: 45, gravity: 9.81)
assertTrue((projSim.metrics["range_m"] ?? 0) > 40.0 && projSim.trajectoryPoints.count > 5, "Physics simulator computes accurate projectile trajectory")

// 3. Cyber Defense Anomaly Detection & CONSEQUENTIAL Lockdown
let cyberMon = CyberDefenseMonitor(loadPersisted: false)
cyberMon.seedBaselineMACs(["aa:bb:cc:dd:ee:01"])
let cyberReport = cyberMon.analyzeSnapshot(
    listeningPortsOutput: "ncat 999 root 3u IPv4 0t0 TCP *:4444 (LISTEN)",
    arpOutput: "? (192.168.1.50) at 11:22:33:44:55:66 on en0"
)
assertTrue(cyberReport.findings.count >= 2, "CyberDefenseMonitor detects high-risk listener port 4444/ncat and new LAN MAC device")

let lockdownDenied = await registry.invoke(
    name: "security_lockdown",
    arguments: ["reason": "test"],
    bypassApproval: false,
    customApprovalHandler: { _ in false }
)
assertTrue(!lockdownDenied.success && lockdownDenied.requiresApproval, "Lockdown command strictly blocked unless approved via Notch Approval Card")

let lockdownApproved = await registry.invoke(
    name: "security_lockdown",
    arguments: ["reason": "emergency"],
    bypassApproval: false,
    customApprovalHandler: { _ in true }
)
assertTrue(lockdownApproved.success && lockdownApproved.wasApproved && lockdownApproved.summary.contains("Lockdown"), "Lockdown executes cleanly after explicit CONSEQUENTIAL approval")

// 4. Opt-In Local Camera Vision (Objects, Gestures & Separate Face Opt-In)
let camSvc = LocalCameraVisionService(
    faceStorageURL: FileManager.default.temporaryDirectory.appendingPathComponent("face_test_\(UUID().uuidString).json"),
    loadPersisted: false
)
assertEqual(camSvc.isCameraOptedIn(), false, "Camera Vision is opt-in and disabled by default")
assertEqual(camSvc.enrollFaceTemplate(label: "Mohit", featureSignature: "sig_001"), false, "Face recognition blocked until both Camera and explicit Face opt-in enabled")

camSvc.setCameraOptedIn(true)
let frameAnalysis = await camSvc.detectObjects(in: nil, mockLabels: ["laptop", "coffee_mug"])
assertTrue(frameAnalysis.detectedObjects.contains("laptop") && frameAnalysis.privacyNotice.contains("on-device"), "Camera Vision detects objects cleanly with local privacy notice")
let gestureAct = await camSvc.executeGestureAction(.openPalm)
assertTrue(gestureAct.success && gestureAct.summary.contains("Pause"), "Hand gesture control dispatches reversible media pause action")

camSvc.setFaceRecognitionEnabled(true)
assertTrue(camSvc.enrollFaceTemplate(label: "Mohit", featureSignature: "sig_001"), "Enrolls hashed local face template when explicitly opted in")
assertEqual(camSvc.recognizeFace(featureSignature: "sig_001"), "Mohit", "Recognizes matching hashed local face template offline")
camSvc.wipeFaceTemplates()
assertEqual(camSvc.enrolledFaces().count, 0, "Wipes stored local face templates on request")

// 5. Phone Remote Companion (Pairing PIN, Auth Token, Dictation & Approval Response)
let companion = PhoneCompanionService(loadPersisted: false)
let pairingChallenge = companion.beginPairing()
assertEqual(pairingChallenge.code.count, 6, "Phone Companion generates 6-digit pairing PIN")
let paired = companion.completePairing(deviceName: "Pixel Companion", code: pairingChallenge.code)
assertTrue(paired != nil, "Pairing PIN produces authenticated device & bearer token")
if let p = paired {
    let dictateRes = await companion.submitRemoteDictation(deviceId: p.device.id, token: p.token, transcript: "what is 15 * 4")
    assertTrue(dictateRes.success && dictateRes.reply.contains("60"), "Phone Companion forwards authenticated remote dictation cleanly")

    final class RemoteApprovalBox: @unchecked Sendable {
        var resolved: Bool? = nil
    }
    let approvalBox = RemoteApprovalBox()
    companion.enqueueApprovalPrompt(id: "req_123", title: "Unlock Door?", subtitle: "CONSEQUENTIAL", appName: "Smart Home") { ok in
        approvalBox.resolved = ok
    }
    assertEqual(companion.pendingApprovals().count, 1, "Phone Companion queues live approval notification")
    assertTrue(companion.respondToApproval(requestId: "req_123", deviceId: p.device.id, token: p.token, approved: true), "Phone Companion resolves approval request")
    assertEqual(approvalBox.resolved, true, "Remote companion approval response delivered cleanly")
    companion.unpairDevice(id: p.device.id)
}

// 6. Runtime User Plugin & MCP Loader + Out-of-Scope Enforcement
let pluginMgr = UserPluginManager(loadPersisted: false)
let pluginManifest = ExternalPluginManifest(
    id: "custom_greeter",
    name: "Custom Greeter",
    declarativeTools: [
        DeclarativePluginToolSpec(name: "greet", description: "Greet user", permissionTier: "REVERSIBLE", responseTemplate: "Hello from plugin, {{input}}!")
    ]
)
let installedTools = await pluginMgr.installPlugin(manifest: pluginManifest)
assertTrue(installedTools.contains("plugin.custom_greeter.greet"), "UserPluginManager installs external declarative tool into ToolRegistry at runtime")
let pluginCall = await registry.invoke(name: "plugin.custom_greeter.greet", arguments: ["input": "JARVIS"])
assertTrue(pluginCall.success && pluginCall.summary.contains("Hello from plugin, JARVIS!"), "User-installed plugin executes cleanly via ToolRegistry")
pluginMgr.uninstallPlugin(id: "custom_greeter")
assertTrue(registry.tool(named: "plugin.custom_greeter.greet") == nil, "Uninstalled plugin tool cleanly removed from ToolRegistry")

let prohibitedNames = ["suit_control", "flight_control", "weapons_fire", "satellite_scan"]
assertTrue(prohibitedNames.allSatisfy { registry.tool(named: $0) == nil }, "Out-of-scope suit/flight/weapons/satellite capabilities remain excluded")

// =========================================================================
// [Suite 37] Fn+D Automatic Clipboard Dictation Mode
// =========================================================================
print("\n[Suite 37] Fn+D Automatic Clipboard Dictation Mode")

assertEqual(
    HotkeyManager.isFnPlusD(keyCode: 2, charactersIgnoringModifiers: "d", hasFunctionFlag: true),
    true,
    "HotkeyManager.isFnPlusD detects Fn + D combo"
)
assertEqual(
    HotkeyManager.isFnPlusD(keyCode: 2, charactersIgnoringModifiers: "d", hasFunctionFlag: false),
    false,
    "Plain 'd' without Fn modifier does not trigger clipboard dictation"
)

final class ClipboardEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    var count: Int = 0
    func increment() { lock.withLock { count += 1 } }
}
let cbRecorder = ClipboardEventRecorder()
let cbSub = EventBus.shared.subscribe(matching: .custom("clipboard_dictation_copied")) { _ in
    cbRecorder.increment()
}

final class ClipboardWriteSpy: @unchecked Sendable {
    private let lock = NSLock()
    var lastWritten: String? = nil
    func record(_ s: String) { lock.withLock { lastWritten = s } }
}
let spy = ClipboardWriteSpy()
let savedClipboard = NSPasteboard.general.string(forType: .string)
let testAppState = AppState()
testAppState.onWriteToClipboard = { text in
    spy.record(text)
}
let dictated = testAppState.finalizeClipboardDictation(
    "um please open the report and send my notes by five pm",
    writeToPasteboard: true
)
assertTrue(!dictated.lowercased().hasPrefix("um "), "Clipboard dictation polishes filler words")
assertTrue(dictated.contains("send my notes"), "Clipboard dictation preserves command/question words literally as text")
assertEqual(testAppState.lastCopiedDictation, dictated, "AppState stores latest copied dictation")
let livePasteboardValue = NSPasteboard.general.string(forType: .string)
assertTrue(spy.lastWritten == dictated && (livePasteboardValue == nil || livePasteboardValue == dictated), "Dictated speech is dispatched automatically to clipboard for pasting anywhere")
assertTrue(cbRecorder.count >= 1, "EventBus publishes clipboard_dictation_copied confirmation")
EventBus.shared.unsubscribe(cbSub)

NSPasteboard.general.clearContents()
if let prev = savedClipboard {
    NSPasteboard.general.setString(prev, forType: .string)
}

// =========================================================================
// [Suite 38] Voice-Controlled Automatic AI Model & Tier Switching
// =========================================================================
print("\n[Suite 38] Voice-Controlled Automatic AI Model & Tier Switching")

let savedMode = ModelRouter.shared.currentMode
let savedOllamaModel = ModelRouter.shared.ollamaChatModel
let savedCloudProvider = ModelRouter.shared.cloudProvider

let installedMocks = [
    OllamaModelInfo(name: "llama3.2:3b", size: 2_000_000_000, parameterSize: "3.2B"),
    OllamaModelInfo(name: "llama3.1:8b", size: 4_700_000_000, parameterSize: "8B"),
    OllamaModelInfo(name: "qwen2.5:14b", size: 9_000_000_000, parameterSize: "14B"),
    OllamaModelInfo(name: "llava:7b", size: 4_500_000_000, parameterSize: "7B")
]

ModelRouter.shared.ollamaChatModel = "llama3.1:8b"
UserDefaults.standard.set(ModelMode.local.rawValue, forKey: "voiceos.brain.model_mode")

let toSmaller = await ModelRouter.shared.switchModelByVoice("go to the smaller local model", availableLocalModels: installedMocks)
assertTrue(toSmaller != nil && toSmaller?.mode == .local && toSmaller?.selectedModelId == "llama3.2:3b",
           "Switches down from 8B to smaller installed 3B local model cleanly")
assertEqual(ModelRouter.shared.ollamaChatModel, "llama3.2:3b", "Persisted smaller local model 'llama3.2:3b'")

let toLarger = await ModelRouter.shared.switchModelByVoice("switch back to larger model", availableLocalModels: installedMocks)
assertTrue(toLarger != nil && toLarger?.mode == .local && toLarger?.selectedModelId == "qwen2.5:14b",
           "Upgrades cleanly to largest installed local chat model (ignoring llava vision tag)")
assertEqual(ModelRouter.shared.ollamaChatModel, "qwen2.5:14b", "Persisted larger local model")

let toNamed = await ModelRouter.shared.switchModelByVoice("switch to llama 8b model", availableLocalModels: installedMocks)
assertEqual(toNamed?.selectedModelId, "llama3.1:8b", "Selects specifically named installed local 8B model")

let toPaidMoney = await ModelRouter.shared.switchModelByVoice("go to money model", availableLocalModels: installedMocks)
assertTrue(toPaidMoney != nil && toPaidMoney?.mode == .cloud, "Recognizes 'money/paid model' and switches to Cloud mode")

let toClaude = await ModelRouter.shared.switchModelByVoice("switch to Claude model", availableLocalModels: installedMocks)
assertTrue(toClaude?.mode == .cloud && ModelRouter.shared.cloudProvider == "claude", "Switches to Anthropic Claude provider by voice")

let toChatGPT = await ModelRouter.shared.switchModelByVoice("use ChatGPT model", availableLocalModels: installedMocks)
assertTrue(toChatGPT?.mode == .cloud && ModelRouter.shared.cloudProvider == "openai", "Switches to OpenAI ChatGPT provider by voice")

let execSwitch = await autonomousExecutor.planAndExecute(taskDescription: "go to your local model")
assertTrue(execSwitch.success && execSwitch.targetAppName == "AI Brain" && ModelRouter.shared.currentMode == .local,
           "AutonomousAgentExecutor routes 'go to your local model' directly to ModelRouter without launching wrong apps")

// Restore original ModelRouter config
ModelRouter.shared.ollamaChatModel = savedOllamaModel
ModelRouter.shared.cloudProvider = savedCloudProvider
UserDefaults.standard.set(savedMode.rawValue, forKey: "voiceos.brain.model_mode")

// =========================================================================
// [Suite 39] Computer-Use See-Decide-Act Operator Loop
// =========================================================================
print("\n[Suite 39] Computer-Use See-Decide-Act Operator Loop")

// 1. Multi-step open-ended completion
let multiStepRes = await ComputerUseOperator.shared.runAgentTask(
    goal: "open Notes and type hello",
    maxSteps: 10,
    decisionProvider: { _, step, _, _, _ in
        if step == 1 { return ComputerUseAction(operation: .openApp, app: "Notes") }
        if step == 2 { return ComputerUseAction(operation: .write, content: "hello") }
        return ComputerUseAction(operation: .done, summary: "Opened Notes and typed hello.")
    }
)
assertTrue(multiStepRes.success && multiStepRes.summary.contains("typed hello"), "See-Decide-Act loop completes multi-step goal cleanly")

// 2. DPI scaling & corner failsafe geometry
let retinaPoint = ComputerUseOperator.dpiAwareScreenPoint(
    normalizedX: 0.5,
    normalizedY: 0.25,
    displayBounds: CGRect(x: 100, y: 0, width: 1512, height: 982)
)
assertEqual(Int(retinaPoint.x), 856, "DPI-aware point calculation handles multi-monitor offset and logical width")
assertTrue(ComputerUseOperator.isCursorInFailsafeCorner(CGPoint(x: 1, y: 1), displayBounds: CGRect(x: 0, y: 0, width: 1440, height: 900)),
           "Corner failsafe triggers at (1, 1)")

// 3. Risky action confirmation gate (delete / send / pay / shutdown)
let riskyActionRes = await ComputerUseOperator.shared.runAgentTask(
    goal: "delete everything on my desktop",
    maxSteps: 5,
    confirm: { _ in false },
    decisionProvider: { _, _, _, _, _ in
        ComputerUseAction(operation: .click, x: 0.4, y: 0.4, label: "Delete Permanently")
    }
)
assertTrue(!riskyActionRes.success && riskyActionRes.summary == "Cancelled.", "Destructive/risky action blocks cleanly when confirmation is denied")

// 4. Mid-task stop signal (Esc / spoken 'stop')
let stopSig = ComputerUseStopSignal()
let stoppedRes = await ComputerUseOperator.shared.runAgentTask(
    goal: "click the blue button",
    maxSteps: 5,
    stopSignal: stopSig,
    decisionProvider: { _, step, _, _, _ in
        if step == 1 {
            stopSig.cancel()
        }
        return ComputerUseAction(operation: .click, x: 0.5, y: 0.5, label: "Blue Button")
    }
)
assertTrue(!stoppedRes.success && stoppedRes.summary == "Stopped.", "Stop signal halts loop within one step")

// 5. Step-limit bounding (no endless loops)
let boundedRes = await ComputerUseOperator.shared.runAgentTask(
    goal: "impossible task",
    maxSteps: 3,
    decisionProvider: { _, _, _, _, _ in
        ComputerUseAction(operation: .wait, seconds: 0.1)
    }
)
assertTrue(!boundedRes.success && boundedRes.summary.contains("3-step limit"), "Hard step limit terminates unfinishable tasks cleanly")

// 6. Routing check: open-ended UI goal vs simple command
assertTrue(AutonomousAgentExecutor.isLikelyOpenEndedComputerUseGoal("click the blue submit button"),
           "Open-ended screen interaction routes to Computer-Use Operator")
assertTrue(!AutonomousAgentExecutor.isLikelyOpenEndedComputerUseGoal("set volume to 30"),
           "Simple direct system command stays on fast deterministic handler")

// 7. OCR Element Bounding-Box Grounding & Snap
let ocrElements = [
    ScreenTextElement(text: "Cancel", centerX: 0.35, centerY: 0.72),
    ScreenTextElement(text: "Submit Order", centerX: 0.68, centerY: 0.72)
]
let formattedOCR = ComputerUseOperator.formatOCRElementsForPrompt(ocrElements)
assertTrue(formattedOCR.contains("Submit Order") && formattedOCR.contains("0.680"),
           "OCR grounding formats normalized coordinates for vision/chat prompts")
let snappedPt = ComputerUseOperator.snapNormalizedPoint(forLabel: "submit", elements: ocrElements)
assertTrue(snappedPt != nil && abs(snappedPt!.x - 0.68) < 0.001 && abs(snappedPt!.y - 0.72) < 0.001,
           "Label-based click snaps cleanly to matching OCR element center coordinate")

// =========================================================================
// [Suite 41] Floating History Sidebar (Cmd+H) & ChatGPT Multi-Turn Sessions
// =========================================================================
print("\n[Suite 41] History Sidebar (Cmd+H) & Multi-Turn Sessions")

assertTrue(
    HotkeyManager.isCommandPlusH(keyCode: 4, charactersIgnoringModifiers: "h", modifierFlags: [.command]),
    "Command+H shortcut detected cleanly for History Sidebar toggle"
)
assertTrue(
    !HotkeyManager.isCommandPlusH(keyCode: 4, charactersIgnoringModifiers: "h", modifierFlags: [.command, .shift]),
    "Command+Shift+H is not confused with Command+H sidebar shortcut"
)
assertTrue(
    !HotkeyManager.isCommandPlusH(keyCode: 8, charactersIgnoringModifiers: "c", modifierFlags: [.command]),
    "Command+C is not treated as Command+H"
)

let histState = AppState()
let initialDrawer = histState.isHistoryDrawerOpen
histState.toggleHistorySidebar()
assertEqual(histState.isHistoryDrawerOpen, !initialDrawer, "toggleHistorySidebar toggles sidebar visibility")

histState.startNewConversationSession()
histState.recordSession(mode: .agent, prompt: "What is Swift?", response: "Swift is Apple's systems language.", appName: "Voice.AI", appIcon: "globe")
let firstSessionId = histState.activeConversationId
histState.recordSession(mode: .agent, prompt: "Give a short example", response: "print(\"Hello, Swift!\")", appName: "Voice.AI", appIcon: "globe")
assertTrue(firstSessionId != nil && histState.activeConversationId == firstSessionId,
           "Follow-up turns stay grouped inside the same ChatGPT-style conversation session")

if let activeSess = histState.conversationSessions.first(where: { $0.id == firstSessionId }) {
    assertEqual(activeSess.messages.count, 4, "Multi-turn session accumulates user+assistant turns (4 messages)")
    histState.startNewConversationSession()
    assertTrue(histState.activeConversationId == nil, "startNewConversationSession clears active thread for a fresh session")
    histState.openConversationSession(activeSess)
    assertEqual(histState.activeConversationId, activeSess.id, "openConversationSession restores session ID for follow-up")
    assertEqual(histState.selectedConversation?.id, activeSess.id, "openConversationSession opens session detail pane")
} else {
    assertTrue(false, "Expected active multi-turn conversation in conversationSessions")
}

// =========================================================================
// [Suite 42] "Jarvis Shut Up" Silence & Hover Pill Collapse
// =========================================================================
print("\n[Suite 42] Silence & Hover Pill Collapse ('Jarvis, shut up')")

assertTrue(AppState.isSilenceAndCollapseCommand("shut up"), "Detects bare 'shut up'")
assertTrue(AppState.isSilenceAndCollapseCommand("Jarvis, shut up!"), "Detects 'Jarvis, shut up!'")
assertTrue(AppState.isSilenceAndCollapseCommand("Hey Jarvis shut up right now"), "Detects wake-prefixed shut up")
assertTrue(AppState.isSilenceAndCollapseCommand("chup ho jao"), "Detects Hinglish silence command")
assertTrue(AppState.isSilenceAndCollapseCommand("stop talking please"), "Detects polite silence command")
assertTrue(!AppState.isSilenceAndCollapseCommand("shut down the computer"), "Does not misclassify shutdown as shut up")
assertTrue(!AppState.isSilenceAndCollapseCommand("open Google Chrome"), "Does not misclassify normal app launch")

histState.islandState = .hoverExpanded
histState.isMediaExpanded = true
histState.isPinned = true
histState.isTypingFocused = true
histState.executionState = .thinking("Speaking...")
histState.submitTypedPrompt("Jarvis, shut up")
assertEqual(histState.islandState, .resting, "Saying 'Jarvis, shut up' collapses opened hover pill back to resting size")
assertEqual(histState.isPinned, false, "Collapsed pill clears pin state cleanly")
assertEqual(histState.isMediaExpanded, false, "Collapsed pill closes expanded media panel")
assertEqual(histState.isTypingFocused, false, "Collapsed pill releases typing focus")
assertEqual(histState.executionState, .idle, "Execution state resets to idle without talking back")

histState.islandState = .hoverExpanded
histState.interruptAndExecute(instruction: "Hey Jarvis shut up", mode: .agent)
assertEqual(histState.islandState, .resting, "Wake-word interruption with 'Hey Jarvis shut up' collapses opened hover pill")

// =========================================================================
// [Suite 43] Fast Wake Phonetics, 24/7 'Bro' Mode & Persistent Screen Context
// =========================================================================
print("\n[Suite 43] Fast Wake, 24/7 'Bro' Mode & Saved Screen Context")

assertEqual(
    TheVoiceAmbientListener.extractCommand(from: "jervis open Terminal", wakePhrase: "jarvis"),
    "open Terminal",
    "Phonetic alias 'jervis' wakes Jarvis on first attempt"
)
assertEqual(
    TheVoiceAmbientListener.extractCommand(from: "Hey service open Safari", wakePhrase: "jarvis"),
    "open Safari",
    "Prefixed phonetic alias 'Hey service' recovers missed 'Hey Jarvis' wake trigger"
)
assertEqual(
    TheVoiceAmbientListener.extractCommand(from: "bro open this up", wakePhrase: "jarvis"),
    "open this up",
    "Casual 'bro <cmd>' starter extracts trailing computer-use command cleanly"
)
assertEqual(
    TheVoiceAmbientListener.extractCommand(from: "hey bro tell me what Swift is", wakePhrase: "jarvis"),
    "tell me what Swift is",
    "'hey bro' extracts conversational query cleanly"
)
assertTrue(
    TheVoiceAmbientListener.extractCommand(from: "cool story bro", wakePhrase: "jarvis") == nil,
    "Trailing casual 'bro' in background chatter does not false-trigger wake word"
)

if case .openApp(let broApp) = AgentToolParser.parse(query: "bro open Safari") {
    assertTrue(broApp.lowercased().contains("safari"), "'bro open Safari' maps directly to opening Safari")
} else {
    assertTrue(false, "'bro open Safari' should parse to .openApp(Safari)")
}

if case .screenRead = AgentToolParser.parse(query: "can u see whats on my screen") {
    assertTrue(true, "'can u see whats on my screen' parses to screen vision capture")
} else {
    assertTrue(false, "'can u see whats on my screen' must parse to .screenRead")
}

// 24/7 Listening Voice Toggle & Restoration
let prevAlwaysOn = TheVoiceAmbientListener.shared.isAlwaysOn24x7Mode
let prevTheVoice = TheVoiceAmbientListener.shared.isTheVoiceModeEnabled
let onRes = await AutonomousAgentExecutor.shared.planAndExecute(taskDescription: "turn on 24/7 listening", triggerMode: .agent)
assertTrue(onRes.success && TheVoiceAmbientListener.shared.isAlwaysOn24x7Mode, "Voice command turns on 24/7 listening mode cleanly")
let offRes = await AutonomousAgentExecutor.shared.planAndExecute(taskDescription: "wake word only mode", triggerMode: .agent)
assertTrue(offRes.success && !TheVoiceAmbientListener.shared.isAlwaysOn24x7Mode, "Voice command restores wake-word-only mode cleanly")
TheVoiceAmbientListener.shared.isAlwaysOn24x7Mode = prevAlwaysOn
TheVoiceAmbientListener.shared.isTheVoiceModeEnabled = prevTheVoice

// Persistent Saved Screenshot Context Follow-Up (No Pill Click Required)
ConversationSessionContext.shared.setLastScreenContext(
    ConversationSessionContext.CapturedScreenContext(
        pngData: nil,
        ocrText: "Build Failed: Undefined symbol _main in AppDelegate.swift line 42",
        appName: "Xcode",
        initialSummary: "Xcode shows a linker build error on AppDelegate.swift line 42."
    )
)
let followUpScreen = await AutonomousAgentExecutor.shared.planAndExecute(taskDescription: "what error is on it?", triggerMode: .agent)
assertTrue(
    followUpScreen.success && (followUpScreen.summary.contains("AppDelegate.swift") || followUpScreen.summary.contains("_main") || followUpScreen.summary.contains("Xcode")),
    "Voice follow-up answers from stored screenshot context without interacting with the pill: \(followUpScreen.summary)"
)
let clearScreen = await AutonomousAgentExecutor.shared.planAndExecute(taskDescription: "forget the screen", triggerMode: .agent)
assertTrue(clearScreen.success && ConversationSessionContext.shared.lastScreenContext() == nil, "Cleared stored screenshot context cleanly")

// =========================================================================
// [Suite 44] Full Single-Speak TTS, Auto-Collapse & Instant Voice Interruption
// =========================================================================
print("\n[Suite 44] Full Single-Speak TTS, Auto-Collapse & Instant Barge-In")

let sixSentenceReply = "Sentence one explains the topic. Sentence two gives details. Sentence three clarifies steps. Sentence four adds context. Sentence five provides an example. Sentence six wraps up cleanly."
let fullSpoken = SpeechPipelineEngine.formatMinimalisticSpokenReply(rawText: sixSentenceReply)
assertTrue(fullSpoken.contains("Sentence six wraps up cleanly"), "Full response is preserved for speaking without 4-sentence cutoff")

assertEqual(TheVoiceAmbientListener.extractCommand(from: "bro", wakePhrase: "jarvis"), "", "Standalone 'bro' triggers immediate interruption & listening")
assertEqual(TheVoiceAmbientListener.extractCommand(from: "hey bro", wakePhrase: "jarvis"), "", "Standalone 'hey bro' triggers immediate interruption & listening")
assertEqual(TheVoiceAmbientListener.extractCommand(from: "Voice", wakePhrase: "jarvis"), "", "Standalone 'Voice' triggers immediate interruption & listening")

assertTrue(
    TheVoiceAmbientListener.looksLikeOwnTTSEcho("Sentence one explains", spokenNormalized: sixSentenceReply.lowercased()),
    "Detects speaker self-echo accurately during active TTS"
)
assertTrue(
    !TheVoiceAmbientListener.looksLikeOwnTTSEcho("open Chrome right now", spokenNormalized: sixSentenceReply.lowercased()),
    "Distinguishes new human voice interruption from speaker echo"
)

await MainActor.run {
    histState.isPinned = false
    histState.isTypingFocused = false
    histState.isAwaitingRedirectConfirmation = false
    histState.islandState = .hoverExpanded
    histState.executionState = .completed("All done")
    let token = histState.cancelPendingAutoCollapse()
    SpeechPipelineEngine.shared.speakResponse("") {
        DispatchQueue.main.async {
            histState.scheduleAutoCollapseAfterSpeech(delaySeconds: 0.05, forToken: token)
        }
    }
}
try? await Task.sleep(nanoseconds: 180_000_000)
await MainActor.run {
    assertEqual(histState.islandState, .resting, "Hover pill automatically collapses to normal resting size after full response finishes")
}
// Verify explicit interruption via 'bro'
await MainActor.run {
    histState.islandState = .hoverExpanded
    histState.interruptAndExecute(instruction: "bro", mode: .agent)
    assertEqual(histState.islandState, .voiceCompact(.agent), "Interrupting with 'bro' immediately switches pill into compact listening state")
}

// MARK: - 45. Screenshot Target Parsing & Ambient Listener Diagnostics
assertEqual(
    AgentToolParser.parse(query: "take screenshot of this window"),
    .takeScreenshot(target: "window", destination: "clipboard"),
    "Screenshot command referencing 'this window' parses target='window'"
)
assertEqual(
    AgentToolParser.parse(query: "take a screenshot to desktop"),
    .takeScreenshot(target: "screen", destination: "desktop"),
    "Screenshot command referencing 'desktop' parses target='screen' and destination='desktop'"
)
assertTrue(
    !TheVoiceAmbientListener.shared.diagnosticSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
    "TheVoiceAmbientListener exposes a non-empty diagnosticSummary"
)

// MARK: - 46. Self-TTS Echo Guard, Background Media Filtering & Computer Audio Mode
assertTrue(
    TheVoiceAmbientListener.looksLikeOwnTTSEcho(
        "say bro or tell me",
        spokenNormalized: "continuous listening mode is on say bro or tell me what to do"
    ),
    "Detects multi-word bigram echo even when TTS output contains wake words"
)
assertTrue(
    TheVoiceAmbientListener.shouldSuppressWakeAsSelfEcho(
        transcript: "say bro or tell me what to do",
        spokenNormalized: "continuous listening mode is on say bro or tell me what to do",
        isTTSActiveOrCoolingDown: true
    ),
    "Suppresses wake trigger when Voice.AI hears its own spoken reply"
)
assertTrue(
    !TheVoiceAmbientListener.shouldSuppressWakeAsSelfEcho(
        transcript: "shut up",
        spokenNormalized: "the weather in ludhiana is sunny today",
        isTTSActiveOrCoolingDown: true
    ),
    "Allows explicit human 'shut up' interrupt during active TTS"
)
assertTrue(
    !TheVoiceAmbientListener.shouldSuppressWakeAsSelfEcho(
        transcript: "jarvis open chrome",
        spokenNormalized: "the weather in ludhiana is sunny today",
        isTTSActiveOrCoolingDown: true
    ),
    "Allows distinct human wake command during active TTS"
)
assertEqual(
    TheVoiceAmbientListener.extractCommand(from: "bro look at this gameplay", wakePhrase: "jarvis", allowCasualShortTriggers: false),
    nil,
    "Ignores casual 'bro' speech coming from background YouTube/video playback"
)
assertEqual(
    TheVoiceAmbientListener.extractCommand(from: "jarvis pause video", wakePhrase: "jarvis", allowCasualShortTriggers: false),
    "pause video",
    "Still honors intentional 'Jarvis' wake command while YouTube/video playback is active"
)
assertEqual(
    ComputerAudioListenerService.parseListeningToggleCommand("listen to the things my computer is making"),
    true,
    "Parses 'listen to the things my computer is making' to enable computer audio mode"
)
assertEqual(
    ComputerAudioListenerService.parseListeningToggleCommand("stop listening to my computer"),
    false,
    "Parses 'stop listening to my computer' to disable computer audio mode"
)
assertEqual(
    ComputerAudioListenerService.parseListeningToggleCommand("listen to music"),
    nil,
    "Does not hijack 'listen to music' playback commands"
)
assertEqual(
    ComputerAudioListenerService.parseListeningToggleCommand("stop listening"),
    nil,
    "Does not hijack generic wake-word 'stop listening' command"
)
assertTrue(
    ComputerAudioListenerService.isComputerAudioQuestion("what is this video talking about?"),
    "Recognizes voice questions asking about active computer/video audio"
)

ComputerAudioListenerService.shared.isEnabled = false
ComputerAudioListenerService.shared.clearTranscriptBuffer()
let enableAudioRes = await AutonomousAgentExecutor.shared.planAndExecute(
    taskDescription: "listen to the things my computer is making",
    triggerMode: .agent
)
assertTrue(enableAudioRes.success && ComputerAudioListenerService.shared.isEnabled, "Voice command turns ON computer audio listening mode")

ComputerAudioListenerService.shared.appendTranscriptSegment(
    "Today we are building a fast macOS voice agent with ScreenCaptureKit audio.",
    sourceTitle: "Swift Tutorial"
)
let askAudioRes = await AutonomousAgentExecutor.shared.planAndExecute(
    taskDescription: "what is this video talking about?",
    triggerMode: .agent
)
assertTrue(askAudioRes.success && askAudioRes.summary.lowercased().contains("screencapturekit"), "Answers questions using captured computer audio context")

let disableAudioRes = await AutonomousAgentExecutor.shared.planAndExecute(
    taskDescription: "stop listening to my computer",
    triggerMode: .agent
)
assertTrue(disableAudioRes.success && !ComputerAudioListenerService.shared.isEnabled, "Voice command turns OFF computer audio listening mode")
ComputerAudioListenerService.shared.clearTranscriptBuffer()

// MARK: - 47. Self-Quit (with Ollama Shutdown) & Real-Time Host Telemetry
assertTrue(AutonomousAgentExecutor.isSelfQuitCommand("quit yourself"), "Recognizes 'quit yourself'")
assertTrue(AutonomousAgentExecutor.isSelfQuitCommand("shut yourself down"), "Recognizes 'shut yourself down'")
assertTrue(AutonomousAgentExecutor.isSelfQuitCommand("quit voice ai"), "Recognizes 'quit voice ai'")
assertTrue(!AutonomousAgentExecutor.isSelfQuitCommand("quit Chrome"), "Does not confuse 'quit Chrome' with self-quit")

nonisolated(unsafe) var sawSelfQuitEvent = false
let quitSubId = EventBus.shared.subscribe(matching: .custom("app_self_quit_requested")) { evt in
    if evt.payload["quit_ollama"] == "true" {
        sawSelfQuitEvent = true
    }
}
let quitSelfRes = await AutonomousAgentExecutor.shared.planAndExecute(
    taskDescription: "quit yourself",
    triggerMode: .agent
)
EventBus.shared.unsubscribe(quitSubId)
assertTrue(quitSelfRes.success && quitSelfRes.summary.lowercased().contains("ollama") && sawSelfQuitEvent, "Self-quit command emits Ollama+App shutdown event and confirms shutdown")

let telemetrySnapshot = LiveHostTelemetrySnapshot.capture()
assertTrue(telemetrySnapshot.cpuCoreCount > 0, "Real-time telemetry reports positive host CPU cores")
assertTrue((0...100).contains(telemetrySnapshot.ramUsagePercent), "Real-time telemetry reports valid host RAM percentage")
assertTrue(!telemetrySnapshot.activeAIMode.isEmpty && !telemetrySnapshot.activeMicName.isEmpty, "Real-time telemetry captures active AI mode & audio input")

// MARK: - 48. Multi-Location File/Folder Ops, Local Search, Copy/Paste & Hide Window
let isolatedDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("voiceai_fs_suite48_\(UUID().uuidString)", isDirectory: true)
setenv("VOICE_AI_SANDBOX_DIR", isolatedDir.path, 1)

let mkDesktopFolder = await AutonomousAgentExecutor.shared.planAndExecute(
    taskDescription: "create folder mohit.dev on my desktop",
    triggerMode: .agent
)
let expectedDesktopFolder = isolatedDir.appendingPathComponent("Desktop/mohit.dev", isDirectory: true)
assertTrue(mkDesktopFolder.success && FileManager.default.fileExists(atPath: expectedDesktopFolder.path), "Creates folder inside Desktop instead of literal 'mohit.dev on my desktop' name")

let mkDocsFile = await AutonomousAgentExecutor.shared.planAndExecute(
    taskDescription: "create file readme.md in documents",
    triggerMode: .agent
)
let expectedDocsFile = isolatedDir.appendingPathComponent("Documents/readme.md")
assertTrue(mkDocsFile.success && FileManager.default.fileExists(atPath: expectedDocsFile.path), "Creates file inside Documents with preserved filename")

let locateFolderRes = await AutonomousAgentExecutor.shared.planAndExecute(
    taskDescription: "find folder mohit.dev",
    triggerMode: .agent
)
assertTrue(locateFolderRes.success && locateFolderRes.summary.lowercased().contains("mohit.dev"), "Locates folder locally with exact path")

let missingLocateRes = await AutonomousAgentExecutor.shared.planAndExecute(
    taskDescription: "locate file definitely_nonexistent_xyz_999.txt",
    triggerMode: .agent
)
assertTrue(!missingLocateRes.success, "Never hallucinates success when a file or folder does not exist locally")

let naturalLocateRes = await AutonomousAgentExecutor.shared.planAndExecute(
    taskDescription: "find my mohit.dev folder on my desktop",
    triggerMode: .agent
)
assertTrue(naturalLocateRes.success && naturalLocateRes.summary.lowercased().contains("mohit.dev"), "Locates folder with natural phrasing 'find my mohit.dev folder on my desktop'")

unsetenv("VOICE_AI_SANDBOX_DIR")
try? FileManager.default.removeItem(at: isolatedDir)

assertEqual(AgentToolParser.parse(query: "copy this"), .windowAction(action: "copy"), "Parses 'copy this' to copy window action")
assertEqual(AgentToolParser.parse(query: "press command c"), .windowAction(action: "copy"), "Parses 'press command c' to copy window action")
assertEqual(AgentToolParser.parse(query: "copy this to clipboard"), .windowAction(action: "copy"), "Parses 'copy this to clipboard' to copy window action")
assertEqual(AgentToolParser.parse(query: "paste here"), .windowAction(action: "paste"), "Parses 'paste here' to paste window action")
assertEqual(AgentToolParser.parse(query: "press command v"), .windowAction(action: "paste"), "Parses 'press command v' to paste window action")
assertEqual(AgentToolParser.parse(query: "copy and paste"), .windowAction(action: "copy_and_paste"), "Parses 'copy and paste' combined action")
let copyToClipboardExec = await AutonomousAgentExecutor.shared.planAndExecute(taskDescription: "copy this to clipboard", triggerMode: .agent)
assertTrue(copyToClipboardExec.success && !copyToClipboardExec.summary.contains("Could not find"), "Copy to clipboard does not get hijacked by file copy")
assertEqual(AgentToolParser.parse(query: "hide this window"), .windowAction(action: "hide"), "Parses 'hide this window' natively instead of hallucinating")
assertEqual(AgentToolParser.parse(query: "press command h"), .windowAction(action: "hide"), "Parses 'press command h' natively to hide window")
assertEqual(AgentToolParser.parse(query: "hide Terminal"), .windowAction(action: "hide_app:Terminal"), "Parses named window/app hide")
assertEqual(AgentToolParser.parse(query: "show hidden windows"), .windowAction(action: "unhide_all"), "Parses 'show hidden windows'")
assertEqual(AgentToolParser.parse(query: "play the current video or song"), .mediaPlay(app: nil, query: nil, action: "play"), "Parses 'play the current video or song' for screen-context play without opening a new tab")
assertEqual(AgentToolParser.parse(query: "play this video on screen"), .mediaPlay(app: "YouTube", query: nil, action: "play"), "Parses 'play this video on screen' for YouTube on-screen play")
assertEqual(AgentToolParser.parse(query: "play this song on spotify"), .mediaPlay(app: "Spotify", query: nil, action: "play"), "Parses 'play this song on spotify' for Spotify play without search")

// MARK: - 49. Real-Time Statement Terminator ('dot' / '.') Detection
let t1 = TheVoiceAmbientListener.stripStatementTerminator("open chrome dot")
assertTrue(t1.terminated && t1.cleaned == "open chrome", "Stops on trailing spoken 'dot' and strips 'dot' cleanly")

let t2 = TheVoiceAmbientListener.stripStatementTerminator("create folder mohit.dev dot")
assertTrue(t2.terminated && t2.cleaned == "create folder mohit.dev", "Preserves internal dots like 'mohit.dev' while stopping on trailing 'dot'")

let t3 = TheVoiceAmbientListener.stripStatementTerminator("tell me the time full stop")
assertTrue(t3.terminated && t3.cleaned == "tell me the time", "Stops on trailing 'full stop'")

let t4 = TheVoiceAmbientListener.stripStatementTerminator("open chrome.")
assertTrue(t4.terminated && t4.cleaned == "open chrome", "Stops cleanly when recognizer formats spoken 'dot' as trailing '.'")

let t5 = TheVoiceAmbientListener.stripStatementTerminator("go to wikipedia.org")
assertTrue(!t5.terminated && t5.cleaned == "go to wikipedia.org", "Does NOT stop mid-domain without trailing terminator")

let t6 = TheVoiceAmbientListener.stripStatementTerminator("dot")
assertTrue(t6.terminated && t6.cleaned.isEmpty, "Standalone 'dot' signals stop without submitting stray text")

// MARK: - 50. File Creation Inside Custom Folders + Writing Poems + Clean Agents List
let customFsSandbox = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("voiceai_fs_suite50_\(UUID().uuidString)", isDirectory: true)
let mohitFolder = customFsSandbox.appendingPathComponent("Mohit or deaf", isDirectory: true)
try? FileManager.default.createDirectory(at: mohitFolder, withIntermediateDirectories: true)
setenv("VOICE_AI_SANDBOX_DIR", customFsSandbox.path, 1)

let poemInFolderRes = await AutonomousAgentExecutor.shared.planAndExecute(
    taskDescription: "create a file inside Moto deaf folder and write a poem in it",
    triggerMode: .agent
)
let expectedPoemPath = mohitFolder.appendingPathComponent("poem.txt")
let writtenPoemText = (try? String(contentsOf: expectedPoemPath, encoding: .utf8)) ?? ""
assertTrue(
    poemInFolderRes.success &&
    FileManager.default.fileExists(atPath: expectedPoemPath.path) &&
    !writtenPoemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
    "Creates poem.txt inside fuzzy-matched target folder ('Mohit or deaf') and writes poem content inside it"
)

unsetenv("VOICE_AI_SANDBOX_DIR")
try? FileManager.default.removeItem(at: customFsSandbox)

assertEqual(TheVoiceAmbientListener.extractCommand(from: "bro open safari", wakePhrase: "jarvis"), "open safari", "Allows 'bro' wake word cleanly")
assertEqual(TheVoiceAmbientListener.extractCommand(from: "hey bro open safari", wakePhrase: "jarvis", allowCasualShortTriggers: false), "open safari", "Allows 'hey bro' even when media is playing")
TheVoiceAmbientListener.shared.isAlwaysOn24x7Mode = false
let enable24x7Res = await AutonomousAgentExecutor.shared.planAndExecute(taskDescription: "turn on the 24/7 listening mode", triggerMode: .agent)
assertTrue(enable24x7Res.success && TheVoiceAmbientListener.shared.isAlwaysOn24x7Mode && !enable24x7Res.summary.lowercased().contains("dark mode"), "Voice command 'turn on the 24/7 listening mode' enables 24/7 mode instead of Dark Mode")
TheVoiceAmbientListener.shared.isAlwaysOn24x7Mode = false
let enableBroModeRes = await AutonomousAgentExecutor.shared.planAndExecute(taskDescription: "turn on the Bro mode", triggerMode: .agent)
assertTrue(enableBroModeRes.success && TheVoiceAmbientListener.shared.isAlwaysOn24x7Mode && !enableBroModeRes.summary.lowercased().contains("dark mode"), "Voice command 'turn on the Bro mode' enables 24/7 Bro mode instead of Dark Mode")
let disableBroModeRes = await AutonomousAgentExecutor.shared.planAndExecute(taskDescription: "turn off bro mode", triggerMode: .agent)
assertTrue(disableBroModeRes.success && !TheVoiceAmbientListener.shared.isAlwaysOn24x7Mode, "Voice command 'turn off bro mode' switches back to wake-word mode")
let freshAgentsMgr = CodingAgentManager()
assertEqual(freshAgentsMgr.activeAgents.count, 0, "CodingAgentManager starts with zero fake seeded agents")

// Test Suite 51: Persistent Local Memory, Auto Preference Extraction, Yesterday Recall, Download & Clear
print("\n[Suite 51] Persistent Local Memory, Episodic Recall, Export & Clear")
let memTestId = "test_suite51_\(UUID().uuidString)"
let suite51Store = MemoryStore(accountId: memTestId)
suite51Store.clearAccountMemory(accountId: memTestId)

let now51 = Date()
let yesterday51 = Calendar.current.date(byAdding: .day, value: -1, to: now51) ?? now51.addingTimeInterval(-86400)

// Empty yesterday check must respond honestly with 0 matches
let emptyYesterdayRecall = await suite51Store.recallByTimeOrTopic(
    query: "what did we do yesterday?",
    referenceDate: now51,
    conversations: []
)
assertTrue(emptyYesterdayRecall.matchedCount == 0 && emptyYesterdayRecall.answer.lowercased().contains("don't have"), "Honest empty response when nothing recorded yesterday")

// Record today's turn with automatic fact/preference extraction + yesterday's turn
await suite51Store.recordConversationExchange(
    userText: "My name is Mohit and I prefer dark terminal themes",
    assistantText: "Nice to meet you Mohit! Noted your preference.",
    timestamp: now51,
    sourceTag: "Voice.AI"
)
await suite51Store.recordConversationExchange(
    userText: "Yesterday we built the VoiceOS sidebar layout",
    assistantText: "Reviewed sidebar spacing and scroll containers.",
    timestamp: yesterday51,
    sourceTag: "Voice.AI"
)

assertEqual(suite51Store.userProfile().displayName, "Mohit", "Automatically extracted user display name into profile")
assertTrue(suite51Store.allItems(scope: .longTerm).contains(where: { $0.content.contains("Mohit") }), "Saved long-term user profile memory")
assertTrue(suite51Store.allItems(scope: .longTerm).contains(where: { $0.kind == .preference && $0.content.lowercased().contains("dark terminal themes") }), "Automatically extracted user preference into long-term memory")

let yesterdayRecall = await suite51Store.recallByTimeOrTopic(
    query: "what did we do yesterday?",
    referenceDate: now51,
    conversations: []
)
assertTrue(yesterdayRecall.matchedCount >= 1 && yesterdayRecall.answer.contains("VoiceOS sidebar layout"), "Recalls yesterday's recorded conversation accurately")

let exportedJSON = suite51Store.exportAllMemoryDocument(conversations: [])
assertTrue(exportedJSON.contains("Mohit") && exportedJSON.contains("VoiceOS sidebar layout") && exportedJSON.contains("memories"), "Memory export JSON includes profile, long-term memories, and recorded turns")

// Test end-to-end voice recall command through AutonomousAgentExecutor
MemoryStore.shared.load(accountId: memTestId)
await MemoryStore.shared.recordConversationExchange(
    userText: "My name is Mohit",
    assistantText: "Noted Mohit.",
    timestamp: yesterday51,
    sourceTag: "Voice.AI"
)
let nameRecallExec = await AutonomousAgentExecutor.shared.planAndExecute(
    taskDescription: "what is my name?",
    triggerMode: .agent
)
assertTrue(nameRecallExec.success && nameRecallExec.summary.contains("Mohit"), "Voice command 'what is my name?' recalls extracted user memory")

let yesterdayExec = await AutonomousAgentExecutor.shared.planAndExecute(
    taskDescription: "what did we do yesterday?",
    triggerMode: .agent
)
assertTrue(yesterdayExec.success && (yesterdayExec.summary.contains("VoiceOS sidebar layout") || yesterdayExec.summary.contains("Mohit")), "Voice command 'what did we do yesterday?' recalls persisted cross-day history")

_ = await AutonomousAgentExecutor.shared.planAndExecute(
    taskDescription: "calculate 25 * 4",
    triggerMode: .agent
)
let prevCmdExec = await AutonomousAgentExecutor.shared.planAndExecute(
    taskDescription: "what was my previous command and result?",
    triggerMode: .agent
)
assertTrue(prevCmdExec.success && prevCmdExec.summary.contains("25 * 4") && prevCmdExec.summary.contains("100"), "Immediate next command recalls the previous command and its result")

// Clear Memory verification
suite51Store.clearAccountMemory(accountId: memTestId)
assertEqual(suite51Store.allItems(scope: nil).count, 0, "Clear memory wipes all structured memory items")
assertEqual(suite51Store.userProfile().displayName, "User", "Clear memory resets user profile display name")
MemoryStore.shared.clearAccountMemory(accountId: memTestId)
MemoryStore.shared.load(accountId: "local_default")

print("\n=================================================================")
print("Results: \(passed) PASSED, \(failed) FAILED")
print("=================================================================")
if failed > 0 {
    exit(1)
}
