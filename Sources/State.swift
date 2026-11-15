import Foundation

/// What survives a restart: her grudge.
struct SavedState: Codable, Equatable {
    var annoyance: Double
    var mood: Mood
    var savedAt: Date
}

enum StateStore {
    static func load(from url: URL) -> SavedState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(SavedState.self, from: data)
    }

    static func save(_ s: SavedState, to url: URL) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(s) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// She holds it against you if you quit her mid-fight and come back within the hour.
    static func isGrudge(_ s: SavedState, now: Date) -> Bool {
        [.scolding, .furious, .sulking].contains(s.mood) && now.timeIntervalSince(s.savedAt) < 3600
    }
}
