import AppKit
import SwiftUI
import VoiceOSCore
import Combine

public final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    public let appState = AppState()
    private var mainWindow: NSWindow?
    private var notchHUDController: NotchHUDWindowController?
    private var floatingOrbController: FloatingOrbWindowController?
    private var screenSelectionController: ScreenSelectionOverlayController?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupGlobalHotkey()
        _ = VisualCursorOverlayController.shared
        
        let args = CommandLine.arguments
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
            setupMainWindow()
        }
        if notchHUDController == nil {
            setupNotchHUD()
        }
        if floatingOrbController == nil {
            setupFloatingOrb()
        }
        if screenSelectionController == nil {
            screenSelectionController = ScreenSelectionOverlayController(appState: appState)
        }
        triggerProactiveGreeting()
        
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
        
        let versionItem = NSMenuItem(title: "\(AppBrand.name) \(AppBrand.displayVersion)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        
        menu.addItem(NSMenuItem.separator())

        let openPanelItem = NSMenuItem(title: "Open \(AppBrand.name) Panel", action: #selector(toggleMainWindow), keyEquivalent: "o")
        openPanelItem.target = self
        menu.addItem(openPanelItem)
        
        let toggleItem = NSMenuItem(title: "Toggle Notch Island", action: #selector(toggleHUD), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        let toggleOrbItem = NSMenuItem(title: "Toggle Floating Orb", action: #selector(toggleFloatingOrb), keyEquivalent: "")
        toggleOrbItem.target = self
        menu.addItem(toggleOrbItem)
        
        let circleItem = NSMenuItem(title: "Circle to Ask (Lasso)", action: #selector(triggerCircleToAskFromMenu), keyEquivalent: "C")
        circleItem.keyEquivalentModifierMask = [.command, .shift]
        circleItem.target = self
        menu.addItem(circleItem)

        let clipboardDictItem = NSMenuItem(title: "Clipboard Dictation (Fn+D)", action: #selector(triggerClipboardDictationFromMenu), keyEquivalent: "")
        clipboardDictItem.target = self
        menu.addItem(clipboardDictItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)
        
        let autoUpdateItem = NSMenuItem(title: "Automatically Check for Updates", action: #selector(toggleAutoUpdates), keyEquivalent: "")
        autoUpdateItem.target = self
        autoUpdateItem.state = UpdateManager.shared.automaticallyChecksForUpdates ? .on : .off
        menu.addItem(autoUpdateItem)
        
        let modelSetupItem = NSMenuItem(title: "Model Setup & Downloads…", action: #selector(openModelSetup), keyEquivalent: "m")
        modelSetupItem.target = self
        menu.addItem(modelSetupItem)
        
        let setupItem = NSMenuItem(title: "Setup Assistant…", action: #selector(rerunSetup), keyEquivalent: "")
        setupItem.target = self
        menu.addItem(setupItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit \(AppBrand.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
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

    private func setupMainWindow() {
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
        window.makeKeyAndOrderFront(nil)
        
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
    
    public func applicationWillTerminate(_ notification: Notification) {
        // Free all unified memory / VRAM immediately when app terminates
        ModelLifecycleManager.shared.offloadAllModelsImmediately()
    }
}
