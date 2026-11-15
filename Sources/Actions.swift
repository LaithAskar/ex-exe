import AppKit
import CoreGraphics

/// The ONLY things she can do to your machine. All reversible, none type or click.
final class Actions {
    private let overlay: Overlay
    private let config: Config
    private var dimWindows: [NSWindow] = []

    init(overlay: Overlay, config: Config) {
        self.overlay = overlay
        self.config = config
    }

    /// Returns a human-readable description of what happened (for the log), or nil if refused.
    func perform(_ action: ScreenAction, front: FrontContext) -> String? {
        switch action {
        case .summon:
            overlay.panel.orderFrontRegardless()
            overlay.call("fx", ["name": "summon"])
            return "summoned herself"
        case .sigh:
            NSSound(named: "Sosumi")?.play()
            overlay.call("fx", ["name": "shake"])
            return "sighed loudly"
        case .dim:
            dim(seconds: 3)
            overlay.call("fx", ["name": "spotlight"])
            return "dimmed the screen"
        case .nudgeCursor:
            nudgeCursor()
            return "dragged the cursor toward herself"
        case .hideApp:
            guard config.allowHide, front.category == .betrayal, let pid = front.pid,
                  !config.matches(config.protectedApps, bundleID: front.bundleID, name: front.name),
                  pid != getpid(),
                  let app = NSRunningApplication(processIdentifier: pid) else { return nil }
            app.hide()
            overlay.call("fx", ["name": "shake"])
            return "hid \(front.name)"
        }
    }

    private func dim(seconds: Double) {
        guard dimWindows.isEmpty else { return }
        for screen in NSScreen.screens {
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.backgroundColor = .black
            w.isOpaque = false
            w.alphaValue = 0
            w.ignoresMouseEvents = true
            w.level = Overlay.dimLevel
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            w.orderFrontRegardless()
            dimWindows.append(w)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                w.animator().alphaValue = 0.62
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self else { return }
            let windows = self.dimWindows
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.5
                windows.forEach { $0.animator().alphaValue = 0 }
            }, completionHandler: {
                windows.forEach { $0.orderOut(nil) }
                self.dimWindows.removeAll()
            })
        }
    }

    private func nudgeCursor() {
        guard let primary = NSScreen.screens.first else { return }
        let target = NSPoint(x: overlay.panel.frame.midX, y: overlay.panel.frame.midY)
        let start = NSEvent.mouseLocation
        let steps = 35
        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.018) {
                let p = Double(i) / Double(steps)
                let t = 0.75 * (1 - pow(1 - p, 3)) // ease-out, stop 75% of the way
                let x = start.x + (target.x - start.x) * t
                let y = start.y + (target.y - start.y) * t
                CGWarpMouseCursorPosition(CGPoint(x: x, y: primary.frame.height - y))
                CGAssociateMouseAndMouseCursorPosition(1)
            }
        }
    }
}

final class Speaker {
    private var proc: Process?
    private let config: Config
    var muted = false

    init(config: Config) { self.config = config }

    func say(_ text: String) {
        guard config.voice, !muted, text != "..." else { return }
        proc?.terminate()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        var args = ["-r", String(config.voiceRate)]
        if let v = config.voiceName { args += ["-v", v] }
        p.arguments = args + [text]
        try? p.run()
        proc = p
    }

    func stop() { proc?.terminate() }
}
