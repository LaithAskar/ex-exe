import Foundation

/// Writes her dialogue. LLM if a key is available, canned lines otherwise.
/// It only ever returns text. It cannot trigger actions.
final class Brain {
    private let config: Config
    private let apiKey: String?
    private var recent: [String] = []

    init(config: Config) {
        self.config = config
        let env = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]
        let file = try? String(contentsOf: Paths.keyFile, encoding: .utf8)
        let key = (env ?? file)?.trimmingCharacters(in: .whitespacesAndNewlines)
        apiKey = (key?.isEmpty ?? true) ? nil : key
    }

    var online: Bool { apiKey != nil && config.llm.enabled }

    func line(_ ctx: LineContext, completion: @escaping (String, String) -> Void) {
        let canned = { Lines.pick(ctx, avoiding: self.recent) }
        guard online, ctx.mood != .sulking || ctx.event != .moodChange else {
            let s = canned(); remember(s); completion(s, "canned"); return
        }
        requestLLM(ctx) { [weak self] text in
            DispatchQueue.main.async {
                guard let self else { return }
                let s = text ?? canned()
                self.remember(s)
                completion(s, text == nil ? "canned(fallback)" : "llm")
            }
        }
    }

    private func remember(_ s: String) {
        recent.append(s)
        if recent.count > 12 { recent.removeFirst() }
    }

    private func systemPrompt() -> String {
        """
        You are \(config.name), \(config.userName)'s dramatic ex-girlfriend who now lives as a pixel-art sprite in a \
        video-game dialogue box in the corner of his Mac. You're petty, theatrical, and funny, but underneath you \
        genuinely want him to land a new-grad software engineering job, finish his LeetCode, and stop doomscrolling. \
        Rules: one or two short sentences, max 28 words. No emoji, no hashtags, no quotation marks, no stage directions. \
        Never mention being an AI or a program unless it's a joke about living in the corner of his screen. \
        Never insult his looks, body, family, or real insecurities. Nothing sexual. Keep it PG-13 and playful.
        """
    }

    private func moodDirection(_ m: Mood) -> String {
        switch m {
        case .chill: return "You're in a decent mood. Ramble about the topic like you're catching up, with a small jab at him."
        case .passiveAggressive: return "You're passive-aggressive. Say you're fine in a way that clearly means you're not."
        case .scolding: return "You're scolding him directly for not paying attention to you and for slacking."
        case .furious: return "You're furious and loud. Short punchy sentences. Threaten to take over his screen."
        case .sulking: return "You're sulking. Extremely short. Cold."
        case .forgiving: return "You just forgave him, reluctantly. A little sweet, still prideful."
        }
    }

    private func eventNote(_ e: LineEvent) -> String {
        switch e {
        case .greeting: return "He just launched you."
        case .moodChange: return "Your mood just shifted."
        case .betrayal: return "He just switched to something distracting."
        case .periodic: return "Nothing new happened. Keep talking anyway."
        case .ignored: return "You said something a minute ago and he didn't respond."
        case .returned: return "He was away from the computer for a while and just came back."
        case .apologyAccepted: return "He clicked sorry. Accept it, reluctantly."
        case .apologyGrudging: return "He clicked sorry a second time. Accept it grudgingly."
        case .apologyRejected: return "He keeps spamming sorry. Reject it."
        }
    }

    private func requestLLM(_ ctx: LineContext, done: @escaping (String?) -> Void) {
        guard let key = apiKey, let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else { done(nil); return }
        var user = """
        Mood: \(ctx.mood.label). \(moodDirection(ctx.mood))
        Event: \(eventNote(ctx.event))
        He's currently on: \(ctx.appLabel) (about \(ctx.minutesOnApp) min). Affection meter: \(ctx.affection)/100.
        """
        if let t = ctx.topic { user += "\nA headline people online are talking about (you can bring it up): \(t)" }
        if !recent.isEmpty { user += "\nDon't repeat these recent lines: " + recent.suffix(5).joined(separator: " | ") }

        let body: [String: Any] = [
            "model": config.llm.model,
            "messages": [["role": "system", "content": systemPrompt()], ["role": "user", "content": user]],
            "max_tokens": 400,
            "temperature": 1.0,
            "reasoning": ["effort": "low", "exclude": true],
        ]
        var req = URLRequest(url: url, timeoutInterval: config.llm.timeoutSeconds)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("EX.EXE", forHTTPHeaderField: "X-Title")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err { log("llm error: \(err.localizedDescription)"); done(nil); return }
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200, let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = obj["choices"] as? [[String: Any]],
                  let msg = choices.first?["message"] as? [String: Any],
                  let content = msg["content"] as? String else {
                log("llm bad response status=\(status)")
                done(nil); return
            }
            done(Lines.sanitize(content))
        }.resume()
    }
}
