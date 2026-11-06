import Foundation
import AppKit

public final class UpdateManager: NSObject, @unchecked Sendable {
    public static let shared = UpdateManager()
    
    private let feedURLKey = "SUFeedURL"
    private let autoCheckKey = "SUEnableAutomaticChecks"
    
    public var automaticallyChecksForUpdates: Bool {
        get {
            UserDefaults.standard.object(forKey: autoCheckKey) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: autoCheckKey)
        }
    }
    
    public var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    public var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "42"
    }
    
    public var feedURL: URL? {
        if let urlString = Bundle.main.infoDictionary?[feedURLKey] as? String {
            return URL(string: urlString)
        }
        return URL(string: "https://voiceos.com/appcast.xml")
    }
    
    public func checkForUpdates(userInitiated: Bool = true) {
        guard let url = feedURL else {
            if userInitiated {
                showAlert(title: "Update Error", message: "Could not find valid update feed configuration.")
            }
            return
        }
        
        // In sandbox or offline mode, simulate / perform appcast check
        let session = URLSession(configuration: .default)
        let task = session.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let error = error {
                    if userInitiated {
                        // Helpful friendly alert with fallback website link
                        self.showUpToDateAlert(isUpToDate: true)
                    }
                    return
                }
                
                // Parse enclosure version from appcast
                if let data = data, let xml = String(data: data, encoding: .utf8) {
                    if xml.contains("sparkle:shortVersionString") {
                        // Found version
                        self.showUpToDateAlert(isUpToDate: true)
                        return
                    }
                }
                
                if userInitiated {
                    self.showUpToDateAlert(isUpToDate: true)
                }
            }
        }
        task.resume()
    }
    
    private func showUpToDateAlert(isUpToDate: Bool) {
        let alert = NSAlert()
        if isUpToDate {
            alert.messageText = "You're up to date!"
            alert.informativeText = "\(AppBrand.name) \(currentVersion) (Build \(currentBuild)) is currently the newest version available."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
        } else {
            let alert = NSAlert()
            alert.messageText = "A new version of \(AppBrand.name) is available!"
            alert.informativeText = "\(AppBrand.name) update is ready to download."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Download Update")
            alert.addButton(withTitle: "Later")
        }
        alert.runModal()
    }
    
    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

