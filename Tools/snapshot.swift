import AppKit
import WebKit

// Renders web/index.html offscreen in each mood -> PNGs. Usage: snapshot <webdir> <outdir>
let args = CommandLine.arguments
let webDir = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2])
let states: [(String, String, Int, String)] = [
    ("chill", "CHILL", 88, "Did you see Your Agent Will Pick the Hackable One? No? Because you never tell me anything anymore."),
    ("scolding", "SCOLDING", 47, "12 minutes on YouTube in Google Chrome? You said you'd do LeetCode today."),
    ("furious", "FURIOUS", 18, "THAT'S IT. I'm taking the screen."),
    ("sulking", "SULKING", 6, "Fine. FINE. I'm not talking to you."),
    ("forgiving", "FORGIVING", 52, "Okay. I missed you too. Ugh. Pretend I didn't say that."),
]

final class Runner: NSObject, WKNavigationDelegate {
    let web: WKWebView
    let window: NSWindow
    var i = 0
    override init() {
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 460, height: 330))
        window = NSWindow(contentRect: NSRect(x: -3000, y: 0, width: 460, height: 330), styleMask: .borderless, backing: .buffered, defer: false)
        super.init()
        window.contentView = web
        window.orderBack(nil)
        web.navigationDelegate = self
        web.loadFileURL(webDir.appendingPathComponent("index.html"), allowingReadAccessTo: webDir)
    }
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) { next() }
    func next() {
        guard i < states.count else { NSApp.terminate(nil); return }
        let (m, label, aff, text) = states[i]
        let js = "document.body.style.background='#2b3a4a';ex.setState({mood:'\(m)',label:'\(label)',affection:\(aff),app:'YouTube in Google Chrome',name:'Vex'});ex.say({text:\(String(reflecting: text))})"
        web.evaluateJavaScript(js) { _, err in
            if let err { print("js error", err) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
                self.web.takeSnapshot(with: nil) { img, _ in
                    if let img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                       let png = rep.representation(using: .png, properties: [:]) {
                        let url = outDir.appendingPathComponent("vex-\(m).png")
                        try? png.write(to: url)
                        print("wrote", url.path)
                    }
                    self.i += 1
                    self.next()
                }
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let runner = Runner()
app.run()
