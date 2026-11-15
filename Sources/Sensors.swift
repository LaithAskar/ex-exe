import AppKit
import CoreGraphics

struct FrontContext {
    let category: AppCategory
    let label: String       // e.g. "YouTube in Google Chrome"
    let key: String         // stable id for "minutes on this thing"
    let pid: pid_t?
    let bundleID: String
    let name: String
}

final class Sensors {
    private let config: Config
    private var sniffDisabled = false
    private var scripts: [String: NSAppleScript] = [:]

    private static let browserScripts: [String: String] = [
        "com.google.Chrome": "tell application id \"com.google.Chrome\" to if (count of windows) > 0 then get URL of active tab of front window",
        "com.apple.Safari": "tell application id \"com.apple.Safari\" to if (count of documents) > 0 then get URL of front document",
        "company.thebrowser.Browser": "tell application id \"company.thebrowser.Browser\" to if (count of windows) > 0 then get URL of active tab of front window",
    ]

    init(config: Config) { self.config = config }

    static func idleSeconds() -> Double {
        let any = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
    }

    func front() -> FrontContext {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return FrontContext(category: .neutral, label: "nothing", key: "none", pid: nil, bundleID: "", name: "")
        }
        let bid = app.bundleIdentifier ?? ""
        let name = app.localizedName ?? bid
        let pid = app.processIdentifier
        if pid == getpid() {
            return FrontContext(category: .her, label: "me", key: "her", pid: pid, bundleID: bid, name: name)
        }
        if config.matches(config.betrayalApps, bundleID: bid, name: name) {
            return FrontContext(category: .betrayal, label: name, key: bid, pid: pid, bundleID: bid, name: name)
        }
        if config.sniffBrowserURLs, !sniffDisabled, let host = browserHost(bid) {
            if let site = config.betrayalSites.first(where: { host == $0 || host.hasSuffix("." + $0) }) {
                return FrontContext(category: .betrayal, label: "\(Sensors.pretty(site)) in \(name)", key: site, pid: pid, bundleID: bid, name: name)
            }
            if let site = config.productiveSites.first(where: { host == $0 || host.hasSuffix("." + $0) }) {
                return FrontContext(category: .productive, label: "\(Sensors.pretty(site)) in \(name)", key: site, pid: pid, bundleID: bid, name: name)
            }
        }
        let cat: AppCategory = config.matches(config.productiveApps, bundleID: bid, name: name) ? .productive : .neutral
        return FrontContext(category: cat, label: name, key: bid, pid: pid, bundleID: bid, name: name)
    }

    /// Reads ONLY the active tab's URL host. Never page content.
    private func browserHost(_ bid: String) -> String? {
        guard let source = Sensors.browserScripts[bid] else { return nil }
        let script = scripts[bid] ?? NSAppleScript(source: source)!
        scripts[bid] = script
        var err: NSDictionary?
        let result = script.executeAndReturnError(&err)
        if let err {
            let code = err[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 {
                sniffDisabled = true
                log("browser URL sniffing not authorized (System Settings > Privacy > Automation); disabled")
            }
            return nil
        }
        guard let s = result.stringValue, let host = URL(string: s)?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func pretty(_ site: String) -> String {
        let names = ["youtube.com": "YouTube", "reddit.com": "Reddit", "x.com": "Twitter", "twitter.com": "Twitter",
                     "twitch.tv": "Twitch", "netflix.com": "Netflix", "instagram.com": "Instagram", "tiktok.com": "TikTok",
                     "leetcode.com": "LeetCode", "github.com": "GitHub", "linkedin.com": "LinkedIn", "kick.com": "Kick"]
        return names[site] ?? site
    }
}
