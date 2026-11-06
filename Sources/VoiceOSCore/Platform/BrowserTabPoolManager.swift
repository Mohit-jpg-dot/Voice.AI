import Foundation
import AppKit

/// Resource-efficient Browser Tab Lifecycle & Pool Manager
/// Keeps background research tabs warm for 30 minutes while the user frequently asks questions,
/// preventing repeated CPU/RAM spikes from opening/closing browser sessions.
/// Automatically closes warm tabs after 30 minutes of inactivity.
public final class BrowserTabPoolManager: @unchecked Sendable {
    public static let shared = BrowserTabPoolManager()
    
    private let idleTimeoutInterval: TimeInterval = 30 * 60 // 30 minutes
    private var idleTimer: Timer?
    private var lastQueryTimestamp: Date = Date()
    private var hasWarmTab: Bool = false
    private var currentTabURL: URL?
    private let lock = NSLock()
    
    public init() {}
    
    /// Records an active query. Reuses existing warm session and resets the 30-minute idle TTL timer.
    public func recordQueryActivity(for url: URL? = nil) {
        lock.lock()
        defer { lock.unlock() }
        
        lastQueryTimestamp = Date()
        hasWarmTab = true
        if let url = url {
            currentTabURL = url
        }
        
        // Reset 30-minute countdown on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.idleTimer?.invalidate()
            self.idleTimer = Timer.scheduledTimer(withTimeInterval: self.idleTimeoutInterval, repeats: false) { [weak self] _ in
                self?.handleIdleExpiration()
            }
        }
    }
    
    /// Called when 30 minutes of inactivity have elapsed without any user query.
    private func handleIdleExpiration() {
        lock.lock()
        guard hasWarmTab else {
            lock.unlock()
            return
        }
        hasWarmTab = false
        currentTabURL = nil
        lock.unlock()
        
        NSLog("[Voice.AI TabPool] 30 minutes of inactivity reached. Automatically closing background research tabs to free CPU/RAM.")
        
        // Close warm research tabs in background browser to reclaim memory
        closeBackgroundResearchTabs()
    }
    
    /// Safely closes background Google/ChatGPT research tabs using AppleScript
    public func closeBackgroundResearchTabs() {
        let script = """
        tell application "Google Chrome"
            if it is running then
                repeat with w in windows
                    tell w
                        set tabList to tabs
                        repeat with i from (count of tabList) to 1 by -1
                            set t to item i of tabList
                            set tabUrl to URL of t
                            if tabUrl contains "google.com/search" or tabUrl contains "chatgpt.com" or tabUrl contains "perplexity.ai" then
                                close t
                            end if
                        end repeat
                    end tell
                end repeat
            end if
        end tell
        tell application "Safari"
            if it is running then
                repeat with w in windows
                    tell w
                        set tabList to tabs
                        repeat with i from (count of tabList) to 1 by -1
                            set t to item i of tabList
                            set tabUrl to URL of t
                            if tabUrl contains "google.com/search" or tabUrl contains "chatgpt.com" or tabUrl contains "perplexity.ai" then
                                close t
                            end if
                        end repeat
                    end tell
                end repeat
            end if
        end tell
        """
        
        _ = AccessibilityControlEngine.shared.executeAppleScript(script)
    }
    
    public var isTabWarm: Bool {
        lock.lock()
        defer { lock.unlock() }
        return hasWarmTab && Date().timeIntervalSince(lastQueryTimestamp) < idleTimeoutInterval
    }
}

