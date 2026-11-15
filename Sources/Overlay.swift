import AppKit
import WebKit

final class HerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class Overlay: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    static let dimLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 1)
    static let herLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 2)

    let panel: HerPanel
    let web: WKWebView
    private var ready = false
    private var pending: [String] = []
    private let onMessage: ([String: Any]) -> Void

    init(onMessage: @escaping ([String: Any]) -> Void) {
        self.onMessage = onMessage
        let size = NSSize(width: 460, height: 330)
        panel = HerPanel(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = Overlay.herLevel
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let cfg = WKWebViewConfiguration()
        let ucc = WKUserContentController()
        cfg.userContentController = ucc
        web = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: cfg)
        super.init()
        ucc.add(self, name: "exe")
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")
        panel.contentView = web

        let index = Paths.web.appendingPathComponent("index.html")
        web.loadFileURL(index, allowingReadAccessTo: Paths.web)
        position()
    }

    func position() {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: f.maxX - panel.frame.width - 12, y: f.minY + 12))
    }

    func show() { panel.orderFrontRegardless() }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        if body["type"] as? String == "ready" {
            ready = true
            pending.forEach { web.evaluateJavaScript($0) }
            pending.removeAll()
        }
        onMessage(body)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        log("web load failed: \(error.localizedDescription)")
    }

    func call(_ fn: String, _ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        let js = "window.ex && ex.\(fn)(\(json))"
        if ready { web.evaluateJavaScript(js) } else { pending.append(js) }
    }
}
