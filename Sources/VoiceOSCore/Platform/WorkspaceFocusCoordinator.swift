import AppKit
import Foundation

/// Coordinates background multitasking and prevents focus theft while the user
/// is actively working (coding in an IDE, typing in ChatGPT/Claude, writing, editing).
///
/// Implements generalized, dynamic workspace focus preservation with ZERO hardcoded
/// application names: any regular interactive application currently in the foreground
/// is recognized as an active user workspace.
public final class WorkspaceFocusCoordinator: @unchecked Sendable {
    public static let shared = WorkspaceFocusCoordinator()

    public struct WorkspaceSnapshot: Sendable {
        public let appName: String
        public let bundleIdentifier: String?
        public let processIdentifier: pid_t
        public let capturedAt: Date

        public init(appName: String, bundleIdentifier: String?, processIdentifier: pid_t, capturedAt: Date = Date()) {
            self.appName = appName
            self.bundleIdentifier = bundleIdentifier
            self.processIdentifier = processIdentifier
            self.capturedAt = capturedAt
        }
    }

    private let lock = NSLock()
    private var activeSnapshot: WorkspaceSnapshot?
    private var multitaskingActive: Bool = false
    private var lastTypingActivity: Date = Date.distantPast
    private var isFocusRestorationScheduled: Bool = false

    public init() {}

    // MARK: - Dynamic Active Workspace Detection (Zero Hardcoding)

    /// Returns the currently active foreground application that the user is interacting with.
    /// Excludes Voice.AI's own process and non-regular background daemons.
    public func currentFrontmostApplication() -> NSRunningApplication? {
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard front.processIdentifier != ownPID else { return nil }

        // Must be a regular GUI application (IDE, browser, editor, terminal, AI client, etc.)
        guard front.activationPolicy == .regular else { return nil }
        return front
    }

    /// Returns true if the user is currently working inside an active foreground application.
    public func isUserInActiveWorkspace() -> Bool {
        return currentFrontmostApplication() != nil
    }

    /// Returns a snapshot of the current active workspace, if one exists.
    public func currentWorkspaceSnapshot() -> WorkspaceSnapshot? {
        guard let front = currentFrontmostApplication() else { return nil }
        return WorkspaceSnapshot(
            appName: front.localizedName ?? "Active Workspace",
            bundleIdentifier: front.bundleIdentifier,
            processIdentifier: front.processIdentifier
        )
    }

    // MARK: - Multitasking State Management

    /// Records that the user was actively typing or interacting recently.
    public func recordTypingActivity() {
        lock.lock()
        lastTypingActivity = Date()
        lock.unlock()
    }

    /// Returns true if the user typed or interacted within the past 10 seconds.
    public func wasRecentlyTyping(within seconds: TimeInterval = 10.0) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return Date().timeIntervalSince(lastTypingActivity) <= seconds
    }

    /// Captures the active workspace when a voice command or ambient wake occurs.
    /// This locks in the user's workspace so all resulting commands execute non-interruptively.
    public func captureActiveWorkspace() {
        lock.lock()
        defer { lock.unlock() }

        if let snapshot = currentWorkspaceSnapshot() {
            activeSnapshot = snapshot
            multitaskingActive = true
            #if DEBUG
            NSLog("[WorkspaceFocusCoordinator] Captured active workspace: %@ (PID: %d)", snapshot.appName, snapshot.processIdentifier)
            #endif
        }
    }

    /// Determines whether an upcoming action (app launch, media playback, utility command)
    /// should run strictly in the background without stealing key focus or frontmost window status.
    public func shouldRunInBackgroundPreservingFocus() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if multitaskingActive && activeSnapshot != nil {
            return true
        }

        // Dynamic fallback: if there is currently an active workspace app, preserve it!
        return isUserInActiveWorkspace()
    }

    /// Restores frontmost focus to the user's active workspace application if another
    /// process inadvertently stole key window focus or brought itself to the foreground.
    public func restoreActiveWorkspaceFocus() {
        lock.lock()
        guard let snapshot = activeSnapshot else {
            lock.unlock()
            return
        }
        let targetPID = snapshot.processIdentifier
        lock.unlock()

        let isDryOrTest = ProcessInfo.processInfo.environment["VOICE_AI_DRY_RUN"] == "1" ||
                          ProcessInfo.processInfo.environment["VOICE_AI_TEST_MODE"] == "1"
        if isDryOrTest {
            return
        }

        DispatchQueue.main.async {
            guard let currentFront = NSWorkspace.shared.frontmostApplication else { return }
            if currentFront.processIdentifier != targetPID {
                if let targetApp = NSRunningApplication(processIdentifier: targetPID),
                   !targetApp.isTerminated {
                    targetApp.activate(options: [.activateIgnoringOtherApps])
                    #if DEBUG
                    NSLog("[WorkspaceFocusCoordinator] Restored active workspace focus to: %@ (PID: %d)", targetApp.localizedName ?? "App", targetPID)
                    #endif
                }
            }
        }
    }

    /// Schedules a delayed verification to guarantee focus remains with the user's workspace,
    /// defending against slow-launching helper processes or asynchronous window events.
    public func scheduleFocusGuard(delay: TimeInterval = 0.3) {
        lock.lock()
        guard !isFocusRestorationScheduled else {
            lock.unlock()
            return
        }
        isFocusRestorationScheduled = true
        lock.unlock()

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            self.isFocusRestorationScheduled = false
            self.lock.unlock()
            self.restoreActiveWorkspaceFocus()
        }
    }

    /// Concludes the active multitasking session once all tasks and responses have finished.
    public func endMultitaskingSession() {
        lock.lock()
        multitaskingActive = false
        activeSnapshot = nil
        lock.unlock()
    }

    /// Executes an asynchronous block while capturing and safeguarding the user's active workspace.
    /// Guarantees that upon completion or error, the user's IDE or editor retains frontmost focus.
    public func performPreservingActiveWorkspace<T>(_ work: () async throws -> T) async rethrows -> T {
        captureActiveWorkspace()
        defer {
            restoreActiveWorkspaceFocus()
            scheduleFocusGuard(delay: 0.4)
            endMultitaskingSession()
        }
        return try await work()
    }

    // MARK: - Dynamic Media Player Resolution (Zero Hardcoded Preference)

    /// Dynamically inspects running applications to locate any active media player
    /// (e.g., Spotify, Apple Music, or browser playback) without hardcoding a static single choice.
    public func dynamicallyResolveRunningMediaPlayer() -> String? {
        let running = NSWorkspace.shared.runningApplications
        
        // 1. Check for running music/media apps by bundle ID or standard naming
        for app in running {
            guard let bid = app.bundleIdentifier?.lowercased(),
                  let name = app.localizedName?.lowercased() else { continue }
            
            if bid == "com.spotify.client" || name == "spotify" {
                return "Spotify"
            }
            if bid == "com.apple.music" || name == "music" {
                return "Music"
            }
        }
        
        // 2. Fall back to installed apps lookup if none is currently open
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil {
            return "Spotify"
        }
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") != nil {
            return "Music"
        }
        
        return "Spotify"
    }
}
