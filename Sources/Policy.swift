import Foundation

// Decides WHEN she talks and WHICH screen action she takes.
// The LLM never chooses actions: it only writes dialogue.

enum ScreenAction: String {
    case summon       // bring her panel to front + bounce
    case sigh         // system sound + shake
    case dim          // darken every screen except her for 3s
    case nudgeCursor  // drag the cursor most of the way toward her
    case hideApp      // NSRunningApplication.hide() on the betrayal app (reversible)
}

struct Cadence {
    var lastSpokeAt: Date?
    private var betrayalTriggerFired = false
    var minGapSeconds: Double = 8

    static let intervals: [Mood: Double] = [
        .chill: 300, .passiveAggressive: 150, .scolding: 60,
        .furious: 35, .sulking: .infinity, .forgiving: .infinity,
    ]

    enum Reason: String { case moodChange, betrayal, periodic }

    mutating func shouldSpeak(mood: Mood, moodChanged: Bool, betrayalSeconds: Double, now: Date) -> Reason? {
        var trigger: Reason? = moodChanged ? .moodChange : nil
        if betrayalSeconds == 0 { betrayalTriggerFired = false }
        if betrayalSeconds >= 10 && !betrayalTriggerFired && mood != .sulking {
            betrayalTriggerFired = true
            trigger = trigger ?? .betrayal
        }
        let since = lastSpokeAt.map { now.timeIntervalSince($0) } ?? .infinity
        guard since >= minGapSeconds else { return nil }
        let interval = Cadence.intervals[mood] ?? 300
        let reason = trigger ?? (since >= interval ? .periodic : nil)
        if reason != nil { lastSpokeAt = now }
        return reason
    }
}

struct ActionPolicy {
    var lastActionAt: Date?
    var cooldownSeconds: Double = 300
    private var rotation = 0

    init(cooldownSeconds: Double = 300) {
        self.cooldownSeconds = cooldownSeconds
    }

    mutating func choose(mood: Mood, category: AppCategory, allowHide: Bool, handsOff: Bool, now: Date) -> ScreenAction? {
        if handsOff { return nil }
        if let last = lastActionAt, now.timeIntervalSince(last) < cooldownSeconds { return nil }
        let menu: [ScreenAction]
        switch mood {
        case .scolding:
            menu = [.summon, .sigh]
        case .furious:
            menu = (category == .betrayal && allowHide) ? [.dim, .nudgeCursor, .hideApp] : [.dim, .nudgeCursor]
        default:
            return nil
        }
        let action = menu[rotation % menu.count]
        rotation += 1
        lastActionAt = now
        return action
    }
}
