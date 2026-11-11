import SwiftUI
import WebKit

/// Interactive offline 3D Wireframe Hologram viewer backed by WKWebView.
public struct HologramViewerView: NSViewRepresentable {
    public let htmlString: String

    public init(htmlString: String) {
        self.htmlString = htmlString
    }

    public func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(htmlString, baseURL: nil)
        return webView
    }

    public func updateNSView(_ nsView: WKWebView, context: Context) {
        nsView.loadHTMLString(htmlString, baseURL: nil)
    }
}

