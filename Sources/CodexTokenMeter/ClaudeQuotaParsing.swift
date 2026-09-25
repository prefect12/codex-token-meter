import Foundation

struct ClaudeScopedQuotaWindow {
    let usedPercent: Double
    let resetsAt: Date?
}

enum ClaudeScopedQuotaParser {
    /// Parses the "Weekly · Fable" entry from Claude's model-scoped limits.
    /// Other scoped model limits are intentionally ignored.
    static func fableWeeklyLimit(from raw: Any?) -> ClaudeScopedQuotaWindow? {
        guard let entries = raw as? [[String: Any]] else { return nil }
        guard let entry = entries.first(where: { entry in
            guard let kind = entry["kind"] as? String,
                  kind.localizedCaseInsensitiveContains("weekly"),
                  let modelName = scopedModelName(entry) else {
                return false
            }
            return modelName.localizedCaseInsensitiveContains("fable")
        }) else {
            return nil
        }
        guard let percent = number(entry["percent"])
                ?? number(entry["utilization"])
                ?? number(entry["used_percentage"]),
              percent >= 0 else {
            return nil
        }
        return ClaudeScopedQuotaWindow(
            usedPercent: min(100, percent),
            resetsAt: date(entry["resets_at"])
        )
    }

    private static func scopedModelName(_ entry: [String: Any]) -> String? {
        func modelName(_ raw: Any?) -> String? {
            if let name = raw as? String {
                return name
            }
            guard let model = raw as? [String: Any] else { return nil }
            return (model["display_name"] as? String)
                ?? (model["name"] as? String)
                ?? (model["id"] as? String)
        }
        if let scope = entry["scope"] as? [String: Any],
           let name = modelName(scope["model"]) {
            return name
        }
        return modelName(entry["model"])
    }

    private static func number(_ raw: Any?) -> Double? {
        if let raw, CFGetTypeID(raw as CFTypeRef) == CFBooleanGetTypeID() {
            return nil
        }
        let value: Double?
        if let raw = raw as? Double {
            value = raw
        } else if let raw = raw as? Int {
            value = Double(raw)
        } else if let raw = raw as? NSNumber {
            value = raw.doubleValue
        } else if let raw = raw as? String {
            value = Double(raw)
        } else {
            value = nil
        }
        guard let value, value.isFinite else { return nil }
        return value
    }

    private static func date(_ raw: Any?) -> Date? {
        if let seconds = number(raw) {
            return Date(timeIntervalSince1970: seconds)
        }
        guard let string = raw as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = fractional.date(from: string) {
            return parsed
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}

struct ClaudeResetGrantSnapshot {
    let capturedAt: Date
    let grants: [ClaudeResetGrant]

    var availableCount: Int { grants.reduce(0) { $0 + $1.resetsLeft } }
    var nextExpiry: Date? { grants.compactMap(\.endsAt).min() }
    var clears: Set<String> { Set(grants.flatMap(\.clears)) }
    var usableNow: Bool { grants.contains { $0.usableNow } }
}

struct ClaudeResetGrant {
    let resetsLeft: Int
    let endsAt: Date?
    let clears: [String]
    let usableNow: Bool
}

enum ClaudeResetGrantParser {
    /// `cedar_ember` is an undocumented, read-only Claude Code usage extension.
    /// A missing or ineligible payload is unknown, never evidence of zero grants.
    static func parse(_ raw: Any?, now: Date) -> ClaudeResetGrantSnapshot? {
        guard let object = raw as? [String: Any],
              object["eligible"] as? Bool == true,
              let entries = object["grants"] as? [[String: Any]] else { return nil }
        let grants = entries.compactMap { entry -> ClaudeResetGrant? in
            guard let left = integer(entry["resets_left"]), left > 0,
                  entry["paused"] as? Bool != true else { return nil }
            let startsAt = date(entry["starts_at"])
            let endsAt = date(entry["ends_at"])
            if let startsAt, now < startsAt { return nil }
            if let endsAt, now >= endsAt { return nil }
            return ClaudeResetGrant(
                resetsLeft: left,
                endsAt: endsAt,
                clears: entry["clears"] as? [String] ?? [],
                usableNow: entry["usable_now"] as? Bool == true
            )
        }
        return ClaudeResetGrantSnapshot(capturedAt: now, grants: grants)
    }

    private static func integer(_ raw: Any?) -> Int? {
        guard let raw, CFGetTypeID(raw as CFTypeRef) != CFBooleanGetTypeID() else { return nil }
        if let value = raw as? Int { return value }
        if let value = raw as? String { return Int(value) }
        return nil
    }

    private static func date(_ raw: Any?) -> Date? {
        guard let value = raw as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
