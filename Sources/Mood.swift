import Foundation

// Pure logic: no AppKit, so it compiles into the test binary too.

enum Mood: String, CaseIterable, Codable {
    case chill, passiveAggressive, scolding, furious, sulking, forgiving

    var label: String {
        switch self {
        case .chill: return "CHILL"
        case .passiveAggressive: return "PASSIVE-AGGRESSIVE"
        case .scolding: return "SCOLDING"
        case .furious: return "FURIOUS"
        case .sulking: return "SULKING"
        case .forgiving: return "FORGIVING"
        }
    }
}

enum AppCategory: String, Codable {
    case betrayal, productive, neutral, her
}

struct TickInput {
    var idleSeconds: Double
    var category: AppCategory
    var ignoredLine: Bool
}

struct MoodConfig: Codable {
    var betrayalPerMinute: Double = 24
    var idlePerMinute: Double = 10
    var idleThresholdSeconds: Double = 120
    var productiveReliefPerMinute: Double = 18
    var neutralReliefPerMinute: Double = 4
    var ignoredPenalty: Double = 12
    var apologyRelief: Double = 30
    var sulkSeconds: Double = 120
    var forgivingSeconds: Double = 25
}

enum ApologyResult: Equatable {
    case accepted, grudging, rejected
}

struct MoodEngine {
    private(set) var annoyance: Double = 10
    private(set) var mood: Mood = .chill
    private(set) var betrayalSeconds: Double = 0
    private var sulkUntil: Date?
    private var forgivingUntil: Date?
    private var apologyTimes: [Date] = []
    let config: MoodConfig

    init(config: MoodConfig = MoodConfig()) {
        self.config = config
    }

    var affection: Int { Int((100 - annoyance).rounded()) }

    /// Advances the simulation by `dt` seconds. Returns the new mood if it changed.
    mutating func tick(_ input: TickInput, dt: Double, now: Date) -> Mood? {
        let minutes = dt / 60
        var delta = 0.0
        let idle = input.idleSeconds >= config.idleThresholdSeconds

        switch input.category {
        case .betrayal:
            delta += config.betrayalPerMinute * minutes
            betrayalSeconds += dt
        case .productive, .her:
            if !idle { delta -= config.productiveReliefPerMinute * minutes }
            betrayalSeconds = 0
        case .neutral:
            if !idle { delta -= config.neutralReliefPerMinute * minutes }
            betrayalSeconds = 0
        }
        if idle { delta += config.idlePerMinute * minutes }
        if input.ignoredLine { delta += config.ignoredPenalty }

        annoyance = min(100, max(0, annoyance + delta))
        return resolve(now: now)
    }

    /// Clicking her dialogue box: small relief for paying attention.
    mutating func acknowledge(now: Date) -> Mood? {
        annoyance = max(0, annoyance - 4)
        return resolve(now: now)
    }

    /// Apologies get cheaper the more you spam them in a 10-minute window.
    mutating func apologize(now: Date) -> (ApologyResult, Mood?) {
        apologyTimes = apologyTimes.filter { now.timeIntervalSince($0) < 600 }
        apologyTimes.append(now)
        let result: ApologyResult
        switch apologyTimes.count {
        case 1:
            result = .accepted
            annoyance = max(0, annoyance - config.apologyRelief)
        case 2:
            result = .grudging
            annoyance = max(0, annoyance - config.apologyRelief / 2)
        default:
            result = .rejected
            annoyance = min(100, annoyance + 5)
        }
        if result != .rejected {
            sulkUntil = nil
            forgivingUntil = now.addingTimeInterval(config.forgivingSeconds)
        }
        return (result, resolve(now: now))
    }

    private mutating func resolve(now: Date) -> Mood? {
        let previous = mood
        if let until = sulkUntil {
            if now < until {
                mood = .sulking
            } else {
                // Silent treatment over. She comes back swinging.
                sulkUntil = nil
                annoyance = min(annoyance, 80)
                mood = .furious
            }
        } else if let until = forgivingUntil, now < until {
            mood = .forgiving
        } else {
            forgivingUntil = nil
            switch annoyance {
            case ..<20: mood = .chill
            case ..<40: mood = .passiveAggressive
            case ..<65: mood = .scolding
            case ..<90: mood = .furious
            default:
                sulkUntil = now.addingTimeInterval(config.sulkSeconds)
                mood = .sulking
            }
        }
        return mood == previous ? nil : mood
    }
}
