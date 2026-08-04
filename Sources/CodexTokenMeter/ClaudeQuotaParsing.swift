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
