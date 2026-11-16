import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var config = Config()
    private var engine = MoodEngine()
    private var cadence = Cadence()
    private var policy = ActionPolicy()
    private var overlay: Overlay!
    private var sensors: Sensors!
    private var actions: Actions!
    private var brain: Brain!
    private var speaker: Speaker!
    private let topics = TopicPool()
    private var statusItem: NSStatusItem!
    private var handsOffItem: NSMenuItem!
    private var muteItem: NSMenuItem!
    private var timer: Timer?

    private var lastTick = Date()
    private var handsOff = false
    private var awaitingAckSince: Date?
    private var currentKey = ""
    private var currentKeySince = Date()
    private var lastFront: FrontContext?
    private var lineInFlight = false
    private var screenLocked = false
    private var displayAsleep = false
    private var away = false
    private var openingLine: LineEvent? = .greeting   // said once, when he's actually present
    private var lastSaveAt = Date.distantPast
    private var sigtermSource: DispatchSourceSignal?
    private var topicRefresh: Process?
    private var lastTopicRefreshAt = Date()
    private var demoToken = 0                 // bumping it cancels a running demo
    private var demoRunning = false
    private var demoSorry: (() -> Void)?
    private var demoItem: NSMenuItem!
    private var usr1Source: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ n: Notification) {
        config = Config.load()
        engine = MoodEngine(config: config.mood)
        if let saved = StateStore.load(from: Paths.state) {
            let now = Date()
            if StateStore.isGrudge(saved, now: now) { openingLine = .grudge }
            _ = engine.restore(annoyance: saved.annoyance, savedAt: saved.savedAt, now: now)
            log("restored state: was \(saved.mood.rawValue) \(Int(100 - saved.annoyance)) affection, now \(engine.affection) (\(engine.mood.rawValue))")
        }
        policy = ActionPolicy(cooldownSeconds: config.actionCooldownSeconds)
        sensors = Sensors(config: config)
        brain = Brain(config: config)
        speaker = Speaker(config: config)
        overlay = Overlay { [weak self] msg in self?.handleUI(msg) }
        actions = Actions(overlay: overlay, config: config)
        setupStatusItem()

        HotKey.installHandler()
        HotKey.register(keyCode: kVK_ANSI_X, id: 1) { [weak self] in self?.toggleHandsOff() }
        HotKey.register(keyCode: kVK_ANSI_Q, id: 2) { NSApp.terminate(nil) }
        HotKey.register(keyCode: kVK_ANSI_M, id: 3) { [weak self] in self?.toggleMute() }
        HotKey.register(keyCode: kVK_ANSI_D, id: 4) { [weak self] in self?.toggleDemo() }

        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.screenLocked = true }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in self?.screenLocked = false }
        let wnc = NSWorkspace.shared.notificationCenter
        wnc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.displayAsleep = true }
        wnc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.displayAsleep = false }

        // launchctl/pkill send SIGTERM, which skips applicationWillTerminate. Route it through a clean quit so the grudge is saved.
        signal(SIGTERM, SIG_IGN)
        let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        term.setEventHandler { NSApp.terminate(nil) }
        term.resume()
        sigtermSource = term
        // scripts/demo.sh sends SIGUSR1 so a demo can be started from a terminal / screen recorder.
        signal(SIGUSR1, SIG_IGN)
        let usr1 = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        usr1.setEventHandler { [weak self] in self?.toggleDemo() }
        usr1.resume()
        usr1Source = usr1

        overlay.show()
        timer = Timer.scheduledTimer(withTimeInterval: config.tickSeconds, repeats: true) { [weak self] _ in self?.tick() }
        // First topic refresh shortly after launch (launch-at-login skips run.sh), then every topicRefreshMinutes.
        lastTopicRefreshAt = Date().addingTimeInterval(-config.topicRefreshMinutes * 60 + 30)
        log("EX.EXE online. home=\(Paths.home.path) llm=\(brain.online ? config.llm.model : "offline (canned lines)")")
        log("kill switch: ctrl+opt+cmd+X hands-off, ctrl+opt+cmd+Q quit, ctrl+opt+cmd+M mute, ctrl+opt+cmd+D demo")
    }

    func applicationWillTerminate(_ n: Notification) {
        saveState()
        topicRefresh?.terminate()
        speaker?.stop()
        log("EX.EXE offline")
    }

    // MARK: loop

    private func tick() {
        if demoRunning { lastTick = Date(); return }
        let now = Date()
        let dt = min(now.timeIntervalSince(lastTick), 30) // don't punish across sleep
        lastTick = now

        let idle = Sensors.idleSeconds()
        if userIsAway(idle: idle) {
            // You're not ignoring her if you're not here. Freeze everything.
            if !away {
                away = true
                awaitingAckSince = nil
                speaker.stop()
                log("away (locked=\(screenLocked) asleep=\(displayAsleep) idle=\(Int(idle))s) - frozen")
            }
            return
        }

        let front = sensors.front()
        lastFront = front
        if front.key != currentKey { currentKey = front.key; currentKeySince = now }
        if now.timeIntervalSince(lastSaveAt) >= 60 { saveState() }
        if now.timeIntervalSince(lastTopicRefreshAt) >= config.topicRefreshMinutes * 60 { refreshTopics() }

        if away || openingLine != nil {
            if away { log("back - affection \(engine.affection)") }
            away = false
            pushState(front)
            cadence.lastSpokeAt = now
            speak(openingLine ?? .returned, front)
            openingLine = nil
            return
        }

        var ignored = false
        if let since = awaitingAckSince, now.timeIntervalSince(since) > config.ackWindowSeconds {
            ignored = true
            awaitingAckSince = nil
        }

        let changed = engine.tick(TickInput(idleSeconds: idle, category: front.category, ignoredLine: ignored), dt: dt, now: now)
        if let m = changed { log("mood -> \(m.rawValue) (affection \(engine.affection)) on \(front.label)") }
        pushState(front)

        if let reason = cadence.shouldSpeak(mood: engine.mood, moodChanged: changed != nil, betrayalSeconds: engine.betrayalSeconds, now: now) {
            let event: LineEvent
            switch reason {
            case .moodChange: event = .moodChange
            case .betrayal: event = .betrayal
            case .periodic: event = ignored ? .ignored : .periodic
            }
            speak(event, front)
        } else if ignored {
            speak(.ignored, front)
        }

        if let action = policy.choose(mood: engine.mood, category: front.category, allowHide: config.allowHide, handsOff: handsOff, now: now),
           let what = actions.perform(action, front: front) {
            log("ACTION \(action.rawValue): \(what)")
        }
    }

    private func saveState() {
        StateStore.save(SavedState(annoyance: engine.annoyance, mood: engine.mood, savedAt: Date()), to: Paths.state)
        lastSaveAt = Date()
    }

    /// Runs scripts/refresh_topics.py (HN + X reader) in the background. Never blocks the UI.
    private func refreshTopics() {
        lastTopicRefreshAt = Date()
        guard topicRefresh?.isRunning != true else { return }
        let script = Paths.home.appendingPathComponent("scripts/refresh_topics.py")
        guard FileManager.default.fileExists(atPath: script.path) else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = [script.path]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.terminationHandler = { proc in
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let summary = out.split(separator: "\n").suffix(2).joined(separator: " | ")
            DispatchQueue.main.async { log("topics refreshed (exit \(proc.terminationStatus)): \(summary)") }
        }
        do { try p.run(); topicRefresh = p } catch { log("topic refresh failed to start: \(error.localizedDescription)") }
    }

    private func userIsAway(idle: Double = Sensors.idleSeconds()) -> Bool {
        let frontBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        return screenLocked || displayAsleep || idle >= config.awaySeconds || frontBundle == "com.apple.loginwindow"
    }

    private func speak(_ event: LineEvent, _ front: FrontContext) {
        guard !lineInFlight else { return }
        lineInFlight = true
        let mins = Int(Date().timeIntervalSince(currentKeySince) / 60)
        let wantsTopic = engine.mood == .chill || Int.random(in: 0..<3) == 0
        let ctx = LineContext(mood: engine.mood, event: event, appLabel: front.label, minutesOnApp: mins,
                              affection: engine.affection, topic: wantsTopic ? topics.next() : nil)
        brain.line(ctx) { [weak self] text, source in
            guard let self else { return }
            self.lineInFlight = false
            log("SAY [\(self.engine.mood.rawValue)/\(event.rawValue)/\(source)] \(text)")
            self.overlay.call("say", ["text": text])
            self.speaker.say(text)
            if text != "..." { self.awaitingAckSince = Date() }
        }
    }

    private func pushState(_ front: FrontContext) {
        overlay.call("setState", [
            "mood": engine.mood.rawValue, "label": engine.mood.label, "affection": engine.affection,
            "app": front.label, "handsOff": handsOff, "name": config.name,
        ])
        statusItem.button?.title = "\(heart()) \(engine.affection)"
    }

    private func heart() -> String {
        switch engine.mood {
        case .chill, .forgiving: return "♥"
        case .passiveAggressive, .scolding: return "♡"
        case .furious: return "💢"
        case .sulking: return "…"
        }
    }

    // MARK: UI events

    private func handleUI(_ msg: [String: Any]) {
        let now = Date()
        let front = lastFront ?? sensors.front()
        switch msg["type"] as? String {
        case "ready":
            pushState(front)
            if userIsAway() { away = true; log("launched while away - greeting deferred"); return }
            speak(openingLine ?? .greeting, front)
            openingLine = nil
            cadence.lastSpokeAt = now
        case "ack":
            awaitingAckSince = nil
            if let m = engine.acknowledge(now: now) { log("mood -> \(m.rawValue) (ack)") }
            pushState(front)
        case "sorry" where demoRunning:
            demoSorry?()
        case "ack" where demoRunning:
            break
        case "sorry":
            awaitingAckSince = nil
            let (result, _) = engine.apologize(now: now)
            log("apology \(result)")
            pushState(front)
            cadence.lastSpokeAt = now
            switch result {
            case .accepted: speak(.apologyAccepted, front)
            case .grudging: speak(.apologyGrudging, front)
            case .rejected: speak(.apologyRejected, front)
            }
        default:
            break
        }
    }

    // MARK: demo

    private func toggleDemo() {
        if demoRunning { endDemo(reason: "cancelled"); return }
        let front = sensors.front()
        lastFront = front
        let label = front.category == .her ? "your computer" : front.label
        let steps = DemoScript.steps(app: label, topic: topics.next(preferTrend: true), onBetrayal: front.category == .betrayal)
        demoRunning = true
        demoToken += 1
        demoItem.state = .on
        log("DEMO start on \(front.label) (\(steps.count) steps)")
        playDemo(steps, at: 0, token: demoToken, front: front)
    }

    private func playDemo(_ steps: [DemoStep], at i: Int, token: Int, front: FrontContext) {
        guard token == demoToken, demoRunning else { return }
        guard i < steps.count else { endDemo(reason: "done"); return }
        let s = steps[i]
        overlay.call("setState", ["mood": s.mood.rawValue, "label": s.mood.label, "affection": s.affection,
                                  "app": front.label, "handsOff": handsOff, "name": config.name])
        statusItem.button?.title = "\(s.mood == .furious ? "💢" : s.mood == .sulking ? "…" : "♥") \(s.affection)"
        overlay.call("say", ["text": s.text])
        speaker.say(s.text)
        log("DEMO \(i + 1)/\(steps.count) [\(s.mood.rawValue)] \(s.text)")
        if let a = s.action, !handsOff {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, token == self.demoToken, self.demoRunning else { return }
                if let what = self.actions.perform(a, front: front) { log("DEMO ACTION \(a.rawValue): \(what)") }
            }
        }
        let advance = { [weak self] in
            guard let self, token == self.demoToken else { return }
            self.demoSorry = nil
            self.playDemo(steps, at: i + 1, token: token, front: front)
        }
        if s.waitForSorry {
            overlay.call("fx", ["name": "pulse"])
            var fired = false
            let once = { if !fired { fired = true; advance() } }
            demoSorry = once
            DispatchQueue.main.asyncAfter(deadline: .now() + s.hold) { once() }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + s.hold) { advance() }
        }
    }

    private func endDemo(reason: String) {
        demoRunning = false
        demoToken += 1
        demoSorry = nil
        demoItem.state = .off
        let now = Date()
        cadence.lastSpokeAt = now
        policy.lastActionAt = now      // no real action right after the show
        awaitingAckSince = nil
        lastTick = now
        if let f = lastFront { pushState(f) }
        log("DEMO \(reason); back to real mood \(engine.mood.rawValue) (\(engine.affection))")
    }

    // MARK: menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "♥ \(engine.affection)"
        let menu = NSMenu()
        handsOffItem = NSMenuItem(title: "Hands off my screen (⌃⌥⌘X)", action: #selector(toggleHandsOffMenu), keyEquivalent: "")
        muteItem = NSMenuItem(title: "Mute voice (⌃⌥⌘M)", action: #selector(toggleMuteMenu), keyEquivalent: "")
        let sorry = NSMenuItem(title: "Apologize", action: #selector(apologizeMenu), keyEquivalent: "")
        let quit = NSMenuItem(title: "Quit EX.EXE (⌃⌥⌘Q)", action: #selector(quitMenu), keyEquivalent: "")
        demoItem = NSMenuItem(title: "Run demo (⌃⌥⌘D)", action: #selector(demoMenu), keyEquivalent: "")
        for item in [handsOffItem!, muteItem!, sorry, demoItem!] { item.target = self; menu.addItem(item) }
        menu.addItem(.separator())
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func toggleHandsOff() {
        handsOff.toggle()
        handsOffItem.state = handsOff ? .on : .off
        log("hands-off \(handsOff ? "ON" : "OFF")")
        overlay.call("say", ["text": handsOff ? "Fine. I won't touch your precious screen." : "Oh, I'm allowed to touch things again?"])
        if let f = lastFront { pushState(f) }
    }

    private func toggleMute() {
        speaker.muted.toggle()
        if speaker.muted { speaker.stop() }
        muteItem.state = speaker.muted ? .on : .off
        log("voice \(speaker.muted ? "muted" : "on")")
    }

    @objc private func toggleHandsOffMenu() { toggleHandsOff() }
    @objc private func toggleMuteMenu() { toggleMute() }
    @objc private func apologizeMenu() { handleUI(["type": "sorry"]) }
    @objc private func quitMenu() { NSApp.terminate(nil) }
    @objc private func demoMenu() { toggleDemo() }
}
