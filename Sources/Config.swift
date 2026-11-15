import Foundation

struct LLMConfig: Codable {
    var enabled: Bool = true
    var model: String = "qwen/qwen3.8-flash"
    var timeoutSeconds: Double = 12
}

struct Config: Codable {
    var name: String = "Vex"
    var userName: String = "Laith"
    var tickSeconds: Double = 5
    var ackWindowSeconds: Double = 60
    var awaySeconds: Double = 600
    var topicRefreshMinutes: Double = 30
    var actionCooldownSeconds: Double = 300
    var allowHide: Bool = true
    var voice: Bool = true
    var voiceName: String? = "Samantha"
    var voiceRate: Int = 195
    var sniffBrowserURLs: Bool = true
    var betrayalApps: [String] = []
    var productiveApps: [String] = []
    var protectedApps: [String] = []
    var betrayalSites: [String] = []
    var productiveSites: [String] = []
    var mood: MoodConfig = MoodConfig()
    var llm: LLMConfig = LLMConfig()

    func matches(_ list: [String], bundleID: String, name: String) -> Bool {
        list.contains { $0.caseInsensitiveCompare(bundleID) == .orderedSame || $0.caseInsensitiveCompare(name) == .orderedSame }
    }
}

enum Paths {
    /// Project dir (live-editable web/ and data/) if present, else the app bundle's Resources.
    static let home: URL = {
        if let env = ProcessInfo.processInfo.environment["EXE_HOME"] { return URL(fileURLWithPath: env) }
        let proj = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Projects/ex-exe")
        if FileManager.default.fileExists(atPath: proj.appendingPathComponent("web/index.html").path) { return proj }
        return Bundle.main.resourceURL ?? proj
    }()
    static var web: URL { home.appendingPathComponent("web") }
    static var config: URL { home.appendingPathComponent("data/config.json") }
    static var topics: URL { home.appendingPathComponent("data/topics.json") }
    static var state: URL { home.appendingPathComponent("data/state.json") }
    static var keyFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/ex-exe/openrouter_key")
    }
}

func log(_ msg: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    print("[\(ts)] \(msg)")
    fflush(stdout)
}

extension Config {
    /// Deep-merges data/config.json over the defaults, so a missing key never nukes the whole config.
    static func load() -> Config {
        do {
            let defaults = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Config())) as! [String: Any]
            let data = try Data(contentsOf: Paths.config)
            guard let file = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(domain: "config", code: 1, userInfo: [NSLocalizedDescriptionKey: "top level must be an object"])
            }
            let merged = deepMerge(defaults, file)
            return try JSONDecoder().decode(Config.self, from: JSONSerialization.data(withJSONObject: merged))
        } catch {
            log("config load failed (\(error.localizedDescription)); using defaults")
            return Config()
        }
    }
}

func deepMerge(_ base: [String: Any], _ over: [String: Any]) -> [String: Any] {
    var out = base
    for (k, v) in over {
        if let b = base[k] as? [String: Any], let o = v as? [String: Any] {
            out[k] = deepMerge(b, o)
        } else {
            out[k] = v
        }
    }
    return out
}

struct Topic: Codable { let title: String; let url: String?; let source: String? }
struct TopicFile: Codable { let updated: String?; let topics: [Topic] }

final class TopicPool {
    private var recent: [String] = []

    func next() -> String? {
        guard let data = try? Data(contentsOf: Paths.topics),
              let file = try? JSONDecoder().decode(TopicFile.self, from: data),
              !file.topics.isEmpty else { return nil }
        let fresh = file.topics.filter { !recent.contains($0.title) }
        let pick = (fresh.isEmpty ? file.topics : fresh).randomElement()!
        recent.append(pick.title)
        if recent.count > 8 { recent.removeFirst() }
        var t = pick.title
        if t.count > 70 { t = String(t.prefix(67)) + "..." }
        return t
    }
}
