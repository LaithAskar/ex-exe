import AppKit
import WebKit

// Renders the real web/ UI offscreen in each mood -> PNGs + a contact sheet.
// Usage: snapshot <webdir> <outdir>
let args = CommandLine.arguments
let webDir = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2])

struct Shot { let mood, label: String; let affection: Int; let app, text, caption: String }
let shots: [Shot] = [
    Shot(mood: "chill", label: "CHILL", affection: 88, app: "Cursor",
         text: "Not that you asked, but everyone's arguing about Your Agent Will Pick the Hackable One. You'd know if you talked to me.",
         caption: "chill: rambling about a live headline"),
    Shot(mood: "passiveAggressive", label: "PASSIVE-AGGRESSIVE", affection: 68, app: "Reddit in Google Chrome",
         text: "4 minutes on Reddit in Google Chrome. I'm not counting. I'm just good at math.",
         caption: "passive-aggressive: caught on Reddit"),
    Shot(mood: "scolding", label: "SCOLDING", affection: 47, app: "YouTube in Google Chrome",
         text: "12 minutes on YouTube in Google Chrome? You said you'd do LeetCode today.",
         caption: "scolding: YouTube detected via tab host"),
    Shot(mood: "furious", label: "FURIOUS", affection: 18, app: "YouTube in Google Chrome",
         text: "THAT'S IT. I'm taking the screen.",
         caption: "furious: about to dim / drag cursor / hide app"),
    Shot(mood: "sulking", label: "SULKING", affection: 6, app: "YouTube in Google Chrome",
         text: "Fine. FINE. I'm not talking to you.",
         caption: "sulking: 2-minute silent treatment"),
    Shot(mood: "forgiving", label: "FORGIVING", affection: 52, app: "LeetCode in Google Chrome",
         text: "...okay. Apology accepted. Don't make it weird.",
         caption: "forgiving: after [ sorry ]"),
    Shot(mood: "furious", label: "FURIOUS", affection: 23, app: "Finder",
         text: "You QUIT me? While I was mad? Bold.",
         caption: "grudge: relaunched after quitting her mid-fight"),
    Shot(mood: "scolding", label: "SCOLDING", affection: 41, app: "Twitter in Google Chrome",
         text: "Everyone online is talking about Rust (trending on X) and you're on Twitter in Google Chrome. Tragic.",
         caption: "X topic: trend format from x_reader"),
]

let W: CGFloat = 460, H: CGFloat = 330
let clearFx = "document.getElementById('fx').replaceChildren();"

final class Runner: NSObject, WKNavigationDelegate {
    let web: WKWebView
    let window: NSWindow
    var i = 0
    var images: [NSImage] = []
    override init() {
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: W, height: H))
        window = NSWindow(contentRect: NSRect(x: -3000, y: 0, width: W, height: H), styleMask: .borderless, backing: .buffered, defer: false)
        super.init()
        web.setValue(false, forKey: "drawsBackground")
        window.contentView = web
        window.orderBack(nil)
        web.navigationDelegate = self
        web.loadFileURL(webDir.appendingPathComponent("index.html"), allowingReadAccessTo: webDir)
    }
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) { next() }

    func next() {
        guard i < shots.count else { sheet(); NSApp.terminate(nil); return }
        let s = shots[i]
        let payload: [String: Any] = ["mood": s.mood, "label": s.label, "affection": s.affection, "app": s.app, "name": "Vex"]
        let json = String(data: try! JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
        let text = String(data: try! JSONSerialization.data(withJSONObject: [s.text]), encoding: .utf8)!
        // Offscreen WebKit throttles timers/transitions, so render the final frame directly.
        let noAnim = "if(!document.getElementById('snapcss')){const s=document.createElement('style');s.id='snapcss';s.textContent='#hpfill{transition:none!important}';document.head.appendChild(s)}"
        let js = "\(noAnim); ex.setState(\(json)); ex.say({text: \(text)[0], instant: true}); \(clearFx)"
        web.evaluateJavaScript(js) { _, err in
            if let err { print("js error", err) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.web.evaluateJavaScript(clearFx) { _, _ in
                    self.web.takeSnapshot(with: nil) { img, _ in
                        if let img { self.images.append(img); self.write(img, "vex-\(self.i + 1)-\(s.mood).png") }
                        self.i += 1
                        self.next()
                    }
                }
            }
        }
    }

    func write(_ img: NSImage, _ name: String) {
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        let url = outDir.appendingPathComponent(name)
        try? png.write(to: url)
        print("wrote", url.path)
    }

    // 2-column contact sheet on a desktop-ish gradient so the transparency reads correctly.
    func sheet() {
        let cols = 2, rows = Int(ceil(Double(images.count) / 2))
        let pad: CGFloat = 28, cap: CGFloat = 26, head: CGFloat = 70
        let size = NSSize(width: CGFloat(cols) * (W + pad) + pad, height: head + CGFloat(rows) * (H + cap + pad) + pad)
        let out = NSImage(size: size)
        out.lockFocus()
        NSGradient(colors: [NSColor(red: 0.10, green: 0.14, blue: 0.24, alpha: 1), NSColor(red: 0.28, green: 0.16, blue: 0.36, alpha: 1)])!
            .draw(in: NSRect(origin: .zero, size: size), angle: -60)
        let title: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 26, weight: .heavy), .foregroundColor: NSColor.white]
        let sub: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor(white: 1, alpha: 0.65)]
        ("EX.EXE" as NSString).draw(at: NSPoint(x: pad, y: size.height - 46), withAttributes: title)
        ("Vex, rendered offscreen from web/. Real UI code, real line templates." as NSString).draw(at: NSPoint(x: pad + 120, y: size.height - 40), withAttributes: sub)
        let capAttr: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white]
        for (k, img) in images.enumerated() {
            let c = k % cols, r = k / cols
            let x = pad + CGFloat(c) * (W + pad)
            let yTop = size.height - head - CGFloat(r) * (H + cap + pad)
            (shots[k].caption as NSString).draw(at: NSPoint(x: x + 4, y: yTop - 18), withAttributes: capAttr)
            img.draw(in: NSRect(x: x, y: yTop - cap - H, width: W, height: H))
        }
        out.unlockFocus()
        write(out, "vex-sheet.png")
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let runner = Runner()
app.run()
