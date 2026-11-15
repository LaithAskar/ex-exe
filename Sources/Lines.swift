import Foundation

// Offline dialogue. Used when there's no API key or the LLM call fails.

enum LineEvent: String {
    case greeting, moodChange, betrayal, periodic, ignored, returned
    case apologyAccepted, apologyGrudging, apologyRejected
}

struct LineContext {
    var mood: Mood
    var event: LineEvent
    var appLabel: String
    var minutesOnApp: Int
    var affection: Int
    var topic: String?
}

enum Lines {
    static let byMood: [Mood: [String]] = [
        .chill: [
            "Not that you asked, but everyone's arguing about {topic}. You'd know if you talked to me.",
            "Did you see {topic}? No? Because you never tell me anything anymore.",
            "I was reading about {topic}. Reminded me of you. Overhyped.",
            "Fun fact about {topic}: I don't care. I just wanted you to look at me.",
            "Just checking you're still alive in there.",
        ],
        .passiveAggressive: [
            "Oh, {app}. Cool. Love that for you.",
            "{min} minutes on {app}. I'm not counting. I'm just good at math.",
            "No, it's fine. I'll sit here. In the corner. Like always.",
            "Wow, {app} again. You must really like it. More than some people.",
            "I'm not mad. This is just my face.",
        ],
        .scolding: [
            "{min} minutes on {app}? You said you'd do LeetCode today.",
            "Close {app}. Your job applications aren't going to submit themselves.",
            "You know who doesn't get new-grad offers? People on {app}.",
            "Hello? I'm literally talking to you.",
            "Everyone online is talking about {topic} and you're on {app}. Tragic.",
        ],
        .furious: [
            "THAT'S IT. I'm taking the screen.",
            "{app}. AGAIN. Do you want to be unemployed in January?",
            "I gave you {min} minutes. {min}! Look at me.",
            "One more minute on {app} and I start rearranging your windows.",
        ],
        .sulking: [
            "...",
            "Fine. FINE. I'm not talking to you.",
            "Don't look at me. I'm sulking.",
        ],
        .forgiving: [
            "...okay. Don't make it weird.",
            "Fine. You're forgiven. For now.",
            "Okay. I missed you too. Ugh. Pretend I didn't say that.",
        ],
    ]

    static let byEvent: [LineEvent: [String]] = [
        .greeting: ["Oh. You finally opened me. Took you long enough."],
        .returned: ["Oh. You're back. I didn't notice you were gone. At all.", "Where were you? Don't answer that. Sit down. LeetCode."],
        .ignored: ["Wow. Left on read. By someone who lives on his computer.", "I can SEE you not clicking me."],
        .apologyAccepted: ["...okay. Apology accepted. Don't make it weird."],
        .apologyGrudging: ["You already said that. I'll allow it. Barely."],
        .apologyRejected: ["Apologies are cheap. Close {app} if you mean it.", "Third sorry in ten minutes? That's a pattern, not an apology."],
    ]

    static func pick(_ ctx: LineContext, avoiding recent: [String], random: (Int) -> Int = { Int.random(in: 0..<$0) }) -> String {
        var pool = byEvent[ctx.event] ?? []
        if pool.isEmpty { pool = byMood[ctx.mood] ?? ["..."] }
        if ctx.topic == nil { pool = pool.filter { !$0.contains("{topic}") } }
        let fresh = pool.filter { t in !recent.contains(where: { $0 == fill(t, ctx) }) }
        let choices = fresh.isEmpty ? pool : fresh
        guard !choices.isEmpty else { return "..." }
        return fill(choices[random(choices.count)], ctx)
    }

    static func fill(_ template: String, _ ctx: LineContext) -> String {
        template
            .replacingOccurrences(of: "{app}", with: ctx.appLabel)
            .replacingOccurrences(of: "{min}", with: String(max(1, ctx.minutesOnApp)))
            .replacingOccurrences(of: "{topic}", with: ctx.topic ?? "literally anything")
    }

    /// Trim LLM output to something that fits the dialogue box.
    static func sanitize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”"))
        s = s.replacingOccurrences(of: "\n", with: " ")
        if s.isEmpty { return nil }
        if s.count > 220 { s = String(s.prefix(217)) + "..." }
        return s
    }
}
