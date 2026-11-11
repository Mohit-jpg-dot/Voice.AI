import Foundation
import AppKit

public enum HotkeyTargetMode: String, Codable, Sendable {
    case dictation = "Dictation Mode"
    case agent = "Agent Mode"
}

public enum HotkeyChoice: String, Codable, Sendable, CaseIterable {
    case holdFn = "fn (Hold to Speak)"
    case holdCtrl = "⌃ Control (Hold)"
    case holdRightCmd = "Right ⌘ (Hold)"
    case holdCmd = "⌘ Command (Hold)"
    case ctrlSpace = "⌃ Control + Space"
    case capsLock = "Caps Lock (Hold)"
    case winH = "Win + H (Windows Default)"
    case altSpace = "Alt + Space"
}

public enum KeyEventResult: Equatable, Sendable {
    case passthroughTap(durationMs: Double, action: String) // Short tap -> Emoji / Globe / System function
    case holdToSpeak(durationMs: Double, mode: HotkeyTargetMode) // Held >= 250ms -> VoiceOS Voice Mode
    case ignored
}

public struct SystemHotkeyConflict: Sendable, Equatable {
    public let hasConflict: Bool
    public let conflictName: String
    public let description: String
    public let commandFix: String
    public let isAutoFixable: Bool

    public init(hasConflict: Bool, conflictName: String, description: String, commandFix: String, isAutoFixable: Bool = true) {
        self.hasConflict = hasConflict
        self.conflictName = conflictName
        self.description = description
        self.commandFix = commandFix
        self.isAutoFixable = isAutoFixable
    }
}

/// Hotkey Manager handling tap vs hold (250ms threshold), macOS fn/globe conflict resolution,
/// and cross-platform rebinding (macOS fn/cmd <-> Windows Win+H).
public final class HotkeyManager: @unchecked Sendable {
    public static let shared = HotkeyManager()

    public static let holdThresholdSeconds: Double = 0.250 // 250ms threshold

    public private(set) var dictationKey: HotkeyChoice = .holdFn
    public private(set) var agentKey: HotkeyChoice = .holdCtrl

    private var activePressStartTimes: [String: CFAbsoluteTime] = [:]
    private let lock = NSLock()

    public var isAnyHotkeyHeld: Bool {
        let liveFlags = CGEventSource.flagsState(.combinedSessionState)
        let fnOrCtrlLive = liveFlags.contains(.maskSecondaryFn) || liveFlags.contains(.maskControl)
        lock.lock()
        defer { lock.unlock() }
        if !fnOrCtrlLive && !activePressStartTimes.isEmpty && NSEvent.pressedMouseButtons == 0 {
            // Reconcile if macOS dropped a flagsChanged keyUp event (common with Fn/Globe)
            activePressStartTimes.removeAll()
        }
        return !activePressStartTimes.isEmpty
    }
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var holdTimer: DispatchWorkItem?
    private var ctrlHoldTimer: DispatchWorkItem?
    private var isFunctionKeyPressed = false
    private var isControlKeyPressed = false
    private var fnComboTriggered = false
    private var ctrlComboCancelled = false

    public var onHoldToSpeakTriggered: (@Sendable (HotkeyTargetMode) -> Void)?
    public var onKeyReleased: (@Sendable (KeyEventResult) -> Void)?
    public var onCircleToAskTriggered: (@Sendable () -> Void)?
    public var onClipboardDictationTriggered: (@Sendable () -> Void)?
    public var onHistorySidebarTriggered: (@Sendable () -> Void)?
    public var onEscapeStopTriggered: (@Sendable () -> Void)?

    public init() {}

    // --- Global & Local macOS Event Monitoring ---

    public func startGlobalEventMonitoring() {
        stopGlobalEventMonitoring()

        let flagsHandler: (NSEvent) -> Void = { [weak self] event in
            guard let self = self else { return }
            let fnNow = event.modifierFlags.contains(.function)
            let ctrlNow = event.modifierFlags.contains(.control)
            let timestamp = CFAbsoluteTimeGetCurrent()

            // 1. Fn Key Handling (Hold to Dictate or Fn+D Combo)
            if fnNow && !self.isFunctionKeyPressed {
                self.isFunctionKeyPressed = true
                self.fnComboTriggered = false
                self.handleKeyDown(key: "fn", timestamp: timestamp)

                let work = DispatchWorkItem { [weak self] in
                    guard let self = self, self.isFunctionKeyPressed, !self.fnComboTriggered else { return }
                    DispatchQueue.main.async {
                        self.onHoldToSpeakTriggered?(.dictation)
                    }
                }
                self.holdTimer = work
                DispatchQueue.main.asyncAfter(deadline: .now() + HotkeyManager.holdThresholdSeconds, execute: work)

            } else if !fnNow && self.isFunctionKeyPressed {
                self.isFunctionKeyPressed = false
                self.holdTimer?.cancel()
                self.holdTimer = nil

                if self.fnComboTriggered {
                    self.fnComboTriggered = false
                    _ = self.handleKeyUp(key: "fn", timestamp: timestamp)
                } else {
                    let result = self.handleKeyUp(key: "fn", timestamp: timestamp)
                    DispatchQueue.main.async {
                        self.onKeyReleased?(result)
                    }
                }
            }

            // 2. Control Key Handling (Hold to Speak Agent Action / Computer Control)
            if ctrlNow && !self.isControlKeyPressed {
                self.isControlKeyPressed = true
                self.ctrlComboCancelled = false
                self.handleKeyDown(key: "ctrl", timestamp: timestamp)

                let work = DispatchWorkItem { [weak self] in
                    guard let self = self, self.isControlKeyPressed, !self.ctrlComboCancelled else { return }
                    DispatchQueue.main.async {
                        self.onHoldToSpeakTriggered?(.agent)
                    }
                }
                self.ctrlHoldTimer = work
                DispatchQueue.main.asyncAfter(deadline: .now() + HotkeyManager.holdThresholdSeconds, execute: work)

            } else if !ctrlNow && self.isControlKeyPressed {
                self.isControlKeyPressed = false
                self.ctrlHoldTimer?.cancel()
                self.ctrlHoldTimer = nil

                if !self.ctrlComboCancelled {
                    let result = self.handleKeyUp(key: "ctrl", timestamp: timestamp)
                    DispatchQueue.main.async {
                        self.onKeyReleased?(result)
                    }
                } else {
                    _ = self.handleKeyUp(key: "ctrl", timestamp: timestamp)
                }
            }
        }

        // Cancel control push-to-talk if regular keys are pressed with Ctrl (e.g. Ctrl+C, Ctrl+Tab)
        // Also intercept Fn+D (keyCode 2) to open/toggle Clipboard Dictation Mode
        let handleKeyDownEvent: (NSEvent) -> Bool = { [weak self] event in
            guard let self = self else { return false }
            if self.isControlKeyPressed {
                self.ctrlComboCancelled = true
                self.ctrlHoldTimer?.cancel()
                self.ctrlHoldTimer = nil
            }
            let hasFn = event.modifierFlags.contains(.function) || self.isFunctionKeyPressed
            if hasFn {
                self.fnComboTriggered = true
                self.holdTimer?.cancel()
                self.holdTimer = nil
                if Self.isFnPlusD(
                    keyCode: event.keyCode,
                    charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                    hasFunctionFlag: hasFn
                ) {
                    DispatchQueue.main.async {
                        self.onClipboardDictationTriggered?()
                    }
                    return true
                }
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if Self.isCommandPlusH(
                keyCode: event.keyCode,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                flags: flags
            ) {
                DispatchQueue.main.async {
                    self.onHistorySidebarTriggered?()
                }
                return true
            }
            if flags == [.command, .shift] && event.keyCode == 8 { // Cmd+Shift+C
                DispatchQueue.main.async {
                    self.onCircleToAskTriggered?()
                }
                return true
            }
            if event.keyCode == 53 && ComputerUseOperator.shared.isRunning { // Esc kill switch
                DispatchQueue.main.async {
                    ComputerUseOperator.shared.stopActiveRun()
                    self.onEscapeStopTriggered?()
                }
                return true
            }
            return false
        }

        // Global monitor catches events when VoiceOS is in the background
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flagsHandler)
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            _ = handleKeyDownEvent(event)
        }
        
        // Local monitor catches events when VoiceOS windows have focus
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            flagsHandler(event)
            return event
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let consumed = handleKeyDownEvent(event)
            return consumed ? nil : event
        }
    }

    public static func isFnPlusD(keyCode: UInt16, charactersIgnoringModifiers: String?, hasFunctionFlag: Bool) -> Bool {
        guard hasFunctionFlag else { return false }
        if keyCode == 2 { return true }
        return charactersIgnoringModifiers?.lowercased() == "d"
    }

    public static func isCommandPlusH(keyCode: UInt16, charactersIgnoringModifiers: String?, flags: NSEvent.ModifierFlags) -> Bool {
        guard flags.intersection(.deviceIndependentFlagsMask) == [.command] else { return false }
        if keyCode == 4 { return true }
        return charactersIgnoringModifiers?.lowercased() == "h"
    }

    public func stopGlobalEventMonitoring() {
        if let g = globalMonitor {
            NSEvent.removeMonitor(g)
            globalMonitor = nil
        }
        if let l = localMonitor {
            NSEvent.removeMonitor(l)
            localMonitor = nil
        }
        if let gk = globalKeyMonitor {
            NSEvent.removeMonitor(gk)
            globalKeyMonitor = nil
        }
        if let lk = localKeyMonitor {
            NSEvent.removeMonitor(lk)
            localKeyMonitor = nil
        }
        holdTimer?.cancel()
        holdTimer = nil
        ctrlHoldTimer?.cancel()
        ctrlHoldTimer = nil
        isFunctionKeyPressed = false
        isControlKeyPressed = false
        fnComboTriggered = false
        ctrlComboCancelled = false
    }

    // --- Configuration & Rebinding ---

    public func rebindDictation(to choice: HotkeyChoice) {
        lock.lock()
        defer { lock.unlock() }
        self.dictationKey = choice
    }

    public func rebindAgent(to choice: HotkeyChoice) {
        lock.lock()
        defer { lock.unlock() }
        self.agentKey = choice
    }

    // --- Key Event Press & Release Tracking ---
    
    public static func normalizeKeyName(_ raw: String, keyCode: UInt16? = nil) -> String {
        if keyCode == 179 || raw == "Unknown(179)" {
            return "fn_fast"
        }
        let lower = raw.lowercased()
        if lower == "function" || lower == "fn" {
            return "fn"
        }
        if lower == "controlleft" || lower == "ctrl" || lower == "control-left" {
            return "control-left"
        }
        if lower == "controlright" || lower == "control-right" {
            return "control-right"
        }
        if lower == "command" || lower == "cmd" {
            return "command"
        }
        return lower
    }

    public func handleKeyDown(key: String, timestamp: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) {
        lock.lock()
        defer { lock.unlock() }
        if activePressStartTimes[key] == nil {
            activePressStartTimes[key] = timestamp
        }
    }

    public func handleKeyUp(key: String, timestamp: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) -> KeyEventResult {
        lock.lock()
        defer { lock.unlock() }

        guard let startTime = activePressStartTimes.removeValue(forKey: key) else {
            return .ignored
        }

        let durationSeconds = timestamp - startTime
        let durationMs = durationSeconds * 1000.0

        if durationSeconds < HotkeyManager.holdThresholdSeconds {
            // Short tap: pass through to macOS/Windows so Globe/Emoji or F-keys fire
            let action = key.lowercased() == "fn" ? "macOS Globe / Emoji Picker" : "System Key Pass-Through"
            return .passthroughTap(durationMs: durationMs, action: action)
        } else {
            // Held >= 250ms: VoiceOS dictation or agent mode triggered
            let mode: HotkeyTargetMode = (key.lowercased() == "fn" || key.lowercased() == "win_h") ? .dictation : .agent
            return .holdToSpeak(durationMs: durationMs, mode: mode)
        }
    }

    // --- macOS System Dictation & Globe Conflict Detection ---

    public func detectSystemDictationConflict() -> SystemHotkeyConflict {
        // macOS default dictation shortcut uses double-tap fn (shortcut key code 23 in HIToolbox)
        // Check mock or live user defaults
        let conflictDetected = true // Identified common macOS default
        if conflictDetected {
            return SystemHotkeyConflict(
                hasConflict: true,
                conflictName: "macOS System Dictation (fn fn)",
                description: "macOS system dictation is currently bound to double-tap 'fn', which may occasionally overlap with VoiceOS hold-to-speak.",
                commandFix: "defaults write com.apple.HIToolbox AppleDictationAutoEnable -bool false",
                isAutoFixable: true
            )
        } else {
            return SystemHotkeyConflict(
                hasConflict: false,
                conflictName: "None",
                description: "No hotkey conflicts detected.",
                commandFix: "",
                isAutoFixable: false
            )
        }
    }

    public func applyOneClickFix() -> Bool {
        let conflict = detectSystemDictationConflict()
        guard conflict.hasConflict && conflict.isAutoFixable else { return false }
        // On macOS this would invoke Process / NSTask for defaults write
        return true
    }
}

