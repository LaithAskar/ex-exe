import Foundation

// Minimal test runner: swiftc Sources/{Mood,Policy,Lines}.swift Tests/main.swift
var failures = 0
var passes = 0
func check(_ cond: Bool, _ name: String, line: Int = #line) {
    if cond { passes += 1 } else { failures += 1; print("FAIL [\(line)]: \(name)") }
}

let t0 = Date(timeIntervalSince1970: 1_000_000)
func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }
let distracted = TickInput(idleSeconds: 1, category: .betrayal, ignoredLine: false)
let working = TickInput(idleSeconds: 1, category: .productive, ignoredLine: false)

// 1. Betrayal escalates through every state in order and ends in sulking.
do {
    var e = MoodEngine()
    var seen: [Mood] = [e.mood]
    var t = 0.0
    while t < 600 { t += 5; if let m = e.tick(distracted, dt: 5, now: at(t)) { seen.append(m) } }
    check(Array(seen.prefix(5)) == [.chill, .passiveAggressive, .scolding, .furious, .sulking], "escalation order: \(seen)")
}

// 2. Productive work cools her down.
do {
    var e = MoodEngine()
    for i in 1...24 { _ = e.tick(distracted, dt: 5, now: at(Double(i) * 5)) } // 2 min distracted
    let mad = e.annoyance
    for i in 25...60 { _ = e.tick(working, dt: 5, now: at(Double(i) * 5)) }
    check(e.annoyance < mad, "work reduces annoyance")
    check(e.mood == .chill, "back to chill after 3 min of work, got \(e.mood)")
}

// 3. Idle counts as not paying attention, even on a productive app.
do {
    var e = MoodEngine()
    let before = e.annoyance
    _ = e.tick(TickInput(idleSeconds: 500, category: .productive, ignoredLine: false), dt: 60, now: at(60))
    check(e.annoyance > before, "idle raises annoyance")
}

// 4. Sulk ends after sulkSeconds and returns as furious.
do {
    var cfg = MoodConfig(); cfg.sulkSeconds = 60
    var e = MoodEngine(config: cfg)
    var t = 0.0
    while e.mood != .sulking && t < 1000 { t += 5; _ = e.tick(distracted, dt: 5, now: at(t)) }
    check(e.mood == .sulking, "reached sulking")
    _ = e.tick(working, dt: 30, now: at(t + 30))
    check(e.mood == .sulking, "still sulking mid-window")
    _ = e.tick(working, dt: 35, now: at(t + 65))
    check(e.mood == .furious, "sulk ends furious, got \(e.mood)")
}

// 5. Apology diminishing returns.
do {
    var e = MoodEngine()
    for i in 1...36 { _ = e.tick(distracted, dt: 5, now: at(Double(i) * 5)) }
    let (r1, m1) = e.apologize(now: at(200))
    check(r1 == .accepted && m1 == .forgiving, "first apology accepted -> forgiving")
    let (r2, _) = e.apologize(now: at(210))
    check(r2 == .grudging, "second apology grudging")
    let before = e.annoyance
    let (r3, _) = e.apologize(now: at(220))
    check(r3 == .rejected && e.annoyance > before, "third apology rejected and costs you")
    let (r4, _) = e.apologize(now: at(900))
    check(r4 == .accepted, "apology window resets after 10 min")
}

// 6. Ignoring her is penalized once per ignored line.
do {
    var e = MoodEngine()
    let before = e.annoyance
    _ = e.tick(TickInput(idleSeconds: 1, category: .neutral, ignoredLine: true), dt: 5, now: at(5))
    check(e.annoyance >= before + 11, "ignored penalty applied")
}

// 7. Action policy: never acts when chill, honors cooldown and hands-off, hide only on betrayal.
do {
    var p = ActionPolicy(cooldownSeconds: 300)
    check(p.choose(mood: .chill, category: .betrayal, allowHide: true, handsOff: false, now: at(0)) == nil, "no action when chill")
    check(p.choose(mood: .furious, category: .betrayal, allowHide: true, handsOff: true, now: at(0)) == nil, "hands-off blocks actions")
    check(p.choose(mood: .furious, category: .betrayal, allowHide: true, handsOff: false, now: at(0)) == .dim, "first furious action dim")
    check(p.choose(mood: .furious, category: .betrayal, allowHide: true, handsOff: false, now: at(100)) == nil, "cooldown")
    var seen: [ScreenAction] = [.dim]
    for k in 1...5 { if let a = p.choose(mood: .furious, category: .betrayal, allowHide: true, handsOff: false, now: at(Double(k) * 301)) { seen.append(a) } }
    check(seen.contains(.hideApp), "hide appears in furious rotation on betrayal")
    var q = ActionPolicy(cooldownSeconds: 0)
    var neutralActions: [ScreenAction] = []
    for k in 0..<6 { if let a = q.choose(mood: .furious, category: .neutral, allowHide: true, handsOff: false, now: at(Double(k))) { neutralActions.append(a) } }
    check(!neutralActions.contains(.hideApp), "never hides a non-betrayal app")
}

// 8. Cadence: mood change triggers immediately, min gap respected, sulking stays quiet.
do {
    var c = Cadence()
    check(c.shouldSpeak(mood: .chill, moodChanged: false, betrayalSeconds: 0, now: at(0)) == .periodic, "speaks first time")
    check(c.shouldSpeak(mood: .chill, moodChanged: true, betrayalSeconds: 0, now: at(3)) == nil, "min gap")
    check(c.shouldSpeak(mood: .scolding, moodChanged: true, betrayalSeconds: 0, now: at(10)) == .moodChange, "mood change speaks")
    check(c.shouldSpeak(mood: .scolding, moodChanged: false, betrayalSeconds: 10, now: at(20)) == .betrayal, "betrayal trigger")
    check(c.shouldSpeak(mood: .scolding, moodChanged: false, betrayalSeconds: 15, now: at(30)) == nil, "betrayal trigger fires once")
    check(c.shouldSpeak(mood: .sulking, moodChanged: false, betrayalSeconds: 0, now: at(5000)) == nil, "sulking is silent")
}

// 9. Lines: templates fill, no {topic} leak when no topic, sanitize trims.
do {
    let ctx = LineContext(mood: .scolding, event: .periodic, appLabel: "YouTube in Chrome", minutesOnApp: 7, affection: 40, topic: nil)
    for _ in 0..<50 {
        let s = Lines.pick(ctx, avoiding: [])
        check(!s.contains("{") && !s.contains("literally anything"), "no unfilled template: \(s)")
    }
    check(Lines.sanitize("  \"hi\n there\"  ") == "hi  there", "sanitize")
    check(Lines.sanitize("   ") == nil, "sanitize empty")
    check(Lines.sanitize(String(repeating: "a", count: 400))!.count == 220, "sanitize length")
}

// 10. Config deep-merge: partial user config keeps defaults for missing keys, nested included.
do {
    let defaults = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(Config())) as! [String: Any]
    let partial: [String: Any] = ["name": "Nyx", "mood": ["sulkSeconds": 30]]
    let merged = deepMerge(defaults, partial)
    let cfg = try! JSONDecoder().decode(Config.self, from: JSONSerialization.data(withJSONObject: merged))
    check(cfg.name == "Nyx", "override applied")
    check(cfg.mood.sulkSeconds == 30, "nested override applied")
    check(cfg.mood.betrayalPerMinute == MoodConfig().betrayalPerMinute, "nested default kept")
    check(cfg.awaySeconds == 600 && cfg.llm.model == LLMConfig().model, "top-level defaults kept")
}

// 11. Returned event has its own lines.
do {
    let ctx = LineContext(mood: .furious, event: .returned, appLabel: "Finder", minutesOnApp: 0, affection: 20, topic: nil)
    check(Lines.byEvent[.returned]!.contains(Lines.pick(ctx, avoiding: [])), "returned uses event lines")
}

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
