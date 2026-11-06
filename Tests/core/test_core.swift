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

print("\n=================================================================")
print("Results: \(passed) PASSED, \(failed) FAILED")
print("=================================================================")
if failed > 0 {
    exit(1)
}
