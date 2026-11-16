import Foundation

// A scripted ~30s run through every mood and screen action, for recording a clip.
// Pure data so it's testable; AppDelegate plays it.

struct DemoStep {
    let mood: Mood
    let affection: Int
    let text: String
    let action: ScreenAction?
    let hold: Double          // seconds before the next step
    let waitForSorry: Bool    // pause here until [ sorry ] is clicked (or `hold` times out)
}

enum DemoScript {
    static func steps(app: String, topic: String?, onBetrayal: Bool) -> [DemoStep] {
        let opener = topic.map { "Oh, you're back. Did you see \($0)? You'd know if you ever talked to me." }
            ?? "Oh, you're back. Took you long enough."
        let hide: DemoStep = onBetrayal
            ? DemoStep(mood: .furious, affection: 8, text: "There. \(app) is gone. You're welcome.", action: .hideApp, hold: 3.5, waitForSorry: false)
            : DemoStep(mood: .furious, affection: 8, text: "Close \(app). Now.", action: .sigh, hold: 3.0, waitForSorry: false)
        return [
            DemoStep(mood: .chill, affection: 91, text: opener, action: nil, hold: 6.0, waitForSorry: false),
            DemoStep(mood: .passiveAggressive, affection: 72, text: "Oh. \(app). Cool. Love that for you.", action: nil, hold: 3.8, waitForSorry: false),
            DemoStep(mood: .scolding, affection: 46, text: "\(app)? Really? You said you'd do LeetCode today.", action: .summon, hold: 4.2, waitForSorry: false),
            DemoStep(mood: .furious, affection: 19, text: "THAT'S IT. I'm taking the screen.", action: .dim, hold: 3.6, waitForSorry: false),
            DemoStep(mood: .furious, affection: 12, text: "Look. At. Me.", action: .nudgeCursor, hold: 2.6, waitForSorry: false),
            hide,
            DemoStep(mood: .sulking, affection: 4, text: "Fine. I'm not talking to you.", action: nil, hold: 8.0, waitForSorry: true),
            DemoStep(mood: .forgiving, affection: 55, text: "...okay. Apology accepted. Don't make it weird.", action: nil, hold: 4.5, waitForSorry: false),
        ]
    }
}
