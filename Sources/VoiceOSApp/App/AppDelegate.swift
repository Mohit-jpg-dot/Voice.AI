import AppKit
import SwiftUI
import VoiceOSCore
import Combine

public final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    public let appState = AppState()
    private var mainWindow: NSWindow?
    private var notchHUDController: NotchHUDWindowController?
    private var floatingOrbController: FloatingOrbWindowController?
    private var historySidebarController: HistorySidebarWindowController?
    private var screenSelectionController: ScreenSelectionOverlayController?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupGlobalHotkey()
        _ = VisualCursorOverlayController.shared
        
        let args = CommandLine.arguments
        if args.contains("--demo-email-composer") || UserDefaults.standard.bool(forKey: "voiceos.demo_email_composer") {
            launchNormalEnvironment()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.appState.openEmailComposerDemo()
            }
            return
        }
        
        if args.contains("--model-setup") || args.contains("--models") {
            launchNormalEnvironment()
            ModelSetupWindowController.shared.showWindow()
            return
        }
        
        if args.contains("--setup") {
            SetupWindowController.shared.showSetupWindow(appState: appState) { [weak self] in
                self?.launchNormalEnvironment()
            }
            return
        }
        
        let isSetupDone = UserDefaults.standard.bool(forKey: "voiceos.setup.completed")
        if isSetupDone {
            launchNormalEnvironment()
        } else {
            SetupWindowController.shared.showSetupWindow(appState: appState) { [weak self] in
                self?.launchNormalEnvironment()
            }
        }
    }
    
    private func launchNormalEnvironment() {
        if mainWindow == nil {
            setupMainWindow(showImmediately: false)
        }
        if notchHUDController == nil {
            setupNotchHUD()
        }
        if floatingOrbController == nil {
            setupFloatingOrb()
        }
        if historySidebarController == nil {
            setupHistorySidebar()
        }
        if screenSelectionController == nil {
            screenSelectionController = ScreenSelectionOverlayController(appState: appState)
        }

        LaunchOrbSplashController.shared.presentAndTransition { [weak self] in
            guard let self else { return }
            self.appState.isNotchHUDVisible = true
            self.notchHUDController?.positionUnderNotch()
            self.notchHUDController?.window?.orderFrontRegardless()
            self.mainWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self.triggerProactiveGreeting()
        }
        
        // Pre-warm Kokoro worker & Whisper diagnostics off main thread for instant first response
        _ = KokoroTTSEngine.shared
        Task.detached(priority: .utility) {
            _ = LocalWhisperProvider.diagnostics(forceRefresh: true)
        }
        
        // Auto-turn on and connect local offline models if user selected Local or Hybrid Mode
        if ModelRouter.shared.currentMode == .local || ModelRouter.shared.currentMode == .hybrid {
            Task {
                _ = await ModelRouter.shared.connectLocalOfflineModels(timeoutSeconds: 8.0)
            }
        }
        
        appState.onToggleMainWindow = { [weak self] in
            DispatchQueue.main.async {
                self?.toggleMainWindow()
            }
        }
        
        // Reactively respond to floating orb visibility changes
        appState.$isFloatingOrbVisible
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visible in
                self?.floatingOrbController?.setVisibility(visible)
            }
            .store(in: &cancellables)
        
        // Reactively present or dismiss Circle-to-Ask / Lasso screen selection overlay
        appState.$isScreenCaptureActive
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in
                if active {
                    self?.screenSelectionController?.presentOverlay()
                } else {
                    self?.screenSelectionController?.dismissOverlay()
                }
            }
            .store(in: &cancellables)
        
        // Automatically start/recover hands-free ambient listener when user returns from granting Privacy permissions
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.appState.isTheVoiceModeEnabled && !TheVoiceAmbientListener.shared.isListening {
                    TheVoiceAmbientListener.shared.startAmbientListening()
                }
            }
            .store(in: &cancellables)

        // Handle "quit yourself" voice command: shut down Ollama + terminate Voice.AI cleanly
        EventBus.shared.subscribe(matching: .custom("app_self_quit_requested")) { evt in
            guard ProcessInfo.processInfo.environment["VOICE_AI_TEST_MODE"] != "1" else { return }
            let quitOllama = (evt.payload["quit_ollama"] != "false")
            DispatchQueue.main.async {
                TheVoiceAmbientListener.shared.stopAmbientListening()
                ComputerAudioListenerService.shared.isEnabled = false
                DispatchQueue.global(qos: .userInitiated).async {
                    if quitOllama {
                        ModelLifecycleManager.shared.shutdownOllamaAndUnloadModels()
                    } else {
                        ModelLifecycleManager.shared.offloadAllModelsImmediately()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }

    private func triggerProactiveGreeting() {
        let greeting = LocalMemoryManager.shared.generateGreeting(
            persona: PersonaManager.shared.getActivePersona().rawValue,
            userName: appState.userName
        )
        // Set default proactive assistance message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            if self.appState.currentAgentReply.isEmpty {
                self.appState.currentAgentReply = greeting
            }
        }
    }

    private func setupGlobalHotkey() {
        let hk = HotkeyManager.shared
        hk.onHoldToSpeakTriggered = { [weak self] mode in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // Interrupt any active agent execution or speech playback
                let triggerMode: VoiceTriggerMode = (mode == .dictation) ? .dictation : .agent
                self.appState.interruptAndExecute(instruction: "", mode: triggerMode)
                self.notchHUDController?.positionUnderNotch()
                self.notchHUDController?.window?.orderFrontRegardless()
            }
        }

        hk.onKeyReleased = { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .holdToSpeak:
                    self.appState.stopVoice()
                case .passthroughTap:
                    // Single tap / press of Fn or Cmd key
                    if self.appState.isCurrentlyListening {
                        // If already listening, tap finishes recording and executes immediately
                        self.appState.stopVoice()
                    } else {
                        // If idle or executing, tap interrupts and begins listening for user command
                        self.appState.interruptAndExecute(instruction: "", mode: .agent)
                        self.notchHUDController?.positionUnderNotch()
                        self.notchHUDController?.window?.orderFrontRegardless()
                    }
                case .ignored:
                    break
                }
            }
        }

        hk.onCircleToAskTriggered = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.appState.isScreenCaptureActive {
                    self.appState.cancelCircleSelection()
                } else {
                    self.appState.triggerCircleToAsk()
                }
            }
        }

        hk.onClipboardDictationTriggered = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.appState.toggleClipboardDictation()
                self.notchHUDController?.positionUnderNotch()
                self.notchHUDController?.window?.orderFrontRegardless()
            }
        }

        hk.onHistorySidebarToggleTriggered = { [weak self] in
            DispatchQueue.main.async {
                self?.toggleHistorySidebar()
            }
        }

        hk.onEscapeStopTriggered = { [weak self] in
            DispatchQueue.main.async {
                ComputerUseOperator.shared.stopActiveRun()
                self?.appState.currentExecutionTask?.cancel()
                self?.appState.executionState = .completed("Stopped.")
            }
        }

        hk.startGlobalEventMonitoring()
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: AppBrand.name)
        }
        
        let menu = NSMenu()

        // 1. Settings (⌘,)
        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        menu.addItem(settingsItem)

        // 2. Open Voice.AI Panel (⌘O)
        let openPanelItem = NSMenuItem(title: "Open \(AppBrand.name) Panel", action: #selector(toggleMainWindow), keyEquivalent: "o")
        openPanelItem.keyEquivalentModifierMask = [.command]
        openPanelItem.target = self
        menu.addItem(openPanelItem)

        // 3. Check for Updates…
        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        // 4. Restart Voice.AI
        let restartItem = NSMenuItem(title: "Restart \(AppBrand.name)", action: #selector(restartApp), keyEquivalent: "")
        restartItem.target = self
        menu.addItem(restartItem)

        // 5. Quit Voice.AI (⌘Q)
        let quitItem = NSMenuItem(title: "Quit \(AppBrand.name)", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    @objc public func openSettings() {
        appState.activeNavTab = .settings
        guard let window = mainWindow else {
            setupMainWindow(showImmediately: true)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func restartApp() {
        let url = Bundle.main.bundleURL
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", url.path]
        try? task.run()
        quitApp()
    }

    @objc private func quitApp() {
        ModelLifecycleManager.shared.shutdownOllamaAndUnloadModels()
        NSApplication.shared.terminate(nil)
    }
    
    @objc private func checkForUpdates() {
        UpdateManager.shared.checkForUpdates(userInitiated: true)
    }
    
    @objc private func openModelSetup() {
        ModelSetupWindowController.shared.showWindow()
    }
    
    @objc private func rerunSetup() {
        SetupWindowController.shared.showSetupWindow(appState: appState) { [weak self] in
            self?.launchNormalEnvironment()
        }
    }
    
    @objc private func toggleAutoUpdates(_ sender: NSMenuItem) {
        let current = UpdateManager.shared.automaticallyChecksForUpdates
        UpdateManager.shared.automaticallyChecksForUpdates = !current
        sender.state = !current ? .on : .off
    }
    
    @objc private func toggleHUD() {
        if let window = notchHUDController?.window {
            if window.isVisible {
                window.orderOut(nil)
            } else {
                notchHUDController?.positionUnderNotch()
                window.orderFrontRegardless()
            }
        }
    }

    @objc private func toggleFloatingOrb() {
        appState.isFloatingOrbVisible.toggle()
    }

    @objc private func toggleAlwaysOnListening(_ sender: NSMenuItem) {
        appState.isAlwaysOnListeningMode.toggle()
        sender.state = appState.isAlwaysOnListeningMode ? .on : .off
    }

    @objc private func toggleComputerAudioListening(_ sender: NSMenuItem) {
        appState.isComputerAudioListeningEnabled.toggle()
        sender.state = appState.isComputerAudioListeningEnabled ? .on : .off
    }

    @objc private func toggleHistorySidebar() {
        if historySidebarController == nil {
            setupHistorySidebar()
        }
        historySidebarController?.positionAtLeftEdge()
        appState.toggleHistorySidebar()
        historySidebarController?.window?.orderFrontRegardless()
    }
    
    @objc private func triggerCircleToAskFromMenu() {
        appState.triggerCircleToAsk()
    }

    @objc private func triggerClipboardDictationFromMenu() {
        appState.toggleClipboardDictation()
        notchHUDController?.positionUnderNotch()
        notchHUDController?.window?.orderFrontRegardless()
    }
    
    @objc public func toggleMainWindow() {
        guard let window = mainWindow else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    private func setupMainWindow(showImmediately: Bool = true) {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 960, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.center()
        window.setFrameAutosaveName("VoiceAIMainWindow")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.minSize = NSSize(width: 880, height: 600)
        window.delegate = self
        
        let hostingView = NSHostingView(rootView: MainWindowView(appState: appState))
        window.contentView = hostingView
        if showImmediately {
            window.makeKeyAndOrderFront(nil)
        }
        
        self.mainWindow = window
    }
    
    private func setupNotchHUD() {
        let hudController = NotchHUDWindowController(appState: appState)
        hudController.window?.orderFrontRegardless()
        self.notchHUDController = hudController
    }

    private func setupFloatingOrb() {
        let orbController = FloatingOrbWindowController(appState: appState)
        if appState.isFloatingOrbVisible {
            orbController.setVisibility(true)
        }
        self.floatingOrbController = orbController
    }

    private func setupHistorySidebar() {
        let sidebarController = HistorySidebarWindowController(appState: appState)
        sidebarController.window?.orderFrontRegardless()
        self.historySidebarController = sidebarController
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        // Automatically shut down Ollama.app and kill all running Ollama processes + free VRAM
        ModelLifecycleManager.shared.shutdownOllamaAndUnloadModels()
    }
}
