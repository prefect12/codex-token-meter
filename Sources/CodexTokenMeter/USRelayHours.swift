import Foundation

/// Reads only the private relay's local schedule. Never connects to the VPS or a model.
struct USRelayPolicy: Decodable, Equatable {
    let version: Int
    let outside_hours_mode: String
    let timezone: String
    let weekdays: [Int]
    let start_hour: Int
    let end_hour: Int
    let night_start_hour: Int
    let night_end_hour: Int

    static let approved = USRelayPolicy(version: 2, outside_hours_mode: "warn", timezone: "America/New_York", weekdays: [0, 1, 2, 3, 4],
        start_hour: 9, end_hour: 18, night_start_hour: 22, night_end_hour: 8)

    static func decode(_ data: Data) -> USRelayPolicy? {
        let keys: Set<String> = ["version", "outside_hours_mode", "timezone", "weekdays", "start_hour", "end_hour", "night_start_hour", "night_end_hour"]
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == keys,
              let policy = try? JSONDecoder().decode(Self.self, from: data), policy == .approved else { return nil }
        return policy
    }
}

enum USRelayWindow: String { case open, closed, night, unavailable }

struct USRelaySnapshot {
    let state: USRelayWindow
    let clock: String
    let menuClock: String
    let nextOpen: Date?
    var allowed: Bool { state != .unavailable }
    var inWorkingHours: Bool { state == .open }
}

enum USRelayHours {
    static var rootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude VPS Relay")
    }
    static var isConfigured: Bool { FileManager.default.fileExists(atPath: policyURL.path) }
    static var usageURL: URL { rootURL.appendingPathComponent("usage", isDirectory: true) }
    static var quotaURL: URL { rootURL.appendingPathComponent("quota-capture.json") }
    static var policyURL: URL {
        rootURL.appendingPathComponent("policy.json")
    }

    static func current(now: Date = Date(), policyURL: URL = policyURL) -> USRelaySnapshot? {
        guard FileManager.default.fileExists(atPath: policyURL.path) else { return nil }
        guard let data = try? Data(contentsOf: policyURL), let policy = USRelayPolicy.decode(data) else {
            return USRelaySnapshot(state: .unavailable, clock: "", menuClock: "", nextOpen: nil)
        }
        return snapshot(policy: policy, now: now)
    }

    static func snapshot(policy: USRelayPolicy, now: Date) -> USRelaySnapshot {
        guard policy == .approved, let zone = TimeZone(identifier: policy.timezone) else {
            return USRelaySnapshot(state: .unavailable, clock: "", menuClock: "", nextOpen: nil)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let weekday = (calendar.component(.weekday, from: now) + 5) % 7
        let hour = calendar.component(.hour, from: now)
        let allowed = policy.weekdays.contains(weekday) && hour >= policy.start_hour && hour < policy.end_hour
        let night = hour >= policy.night_start_hour || hour < policy.night_end_hour
        var nextOpen: Date?
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let candidate = calendar.date(bySettingHour: policy.start_hour, minute: 0, second: 0, of: day),
                  policy.weekdays.contains((calendar.component(.weekday, from: candidate) + 5) % 7),
                  candidate > now else { continue }
            nextOpen = candidate
            break
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "EEE HH:mm z"
        let clock = formatter.string(from: now)
        formatter.dateFormat = "HH:mm"
        return USRelaySnapshot(state: allowed ? .open : night ? .night : .closed,
            clock: clock, menuClock: formatter.string(from: now), nextOpen: nextOpen)
    }
}
