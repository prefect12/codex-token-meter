import Foundation

@main
enum ClaudeQuotaParsingTests {
    private static var failures: [String] = []

    static func main() {
        parsesFableDisplayName()
        parsesStringModelAndAlternatePercentField()
        ignoresOtherScopedModels()
        rejectsNonWeeklyFableLimits()
        parsesAvailableResetGrant()
        rejectsIneligibleAndExpiredResets()

        if failures.isEmpty {
            print("PASS: ClaudeQuotaParsing")
            return
        }
        for failure in failures {
            FileHandle.standardError.write(Data("FAIL: \(failure)\n".utf8))
        }
        exit(1)
    }

    private static func parsesFableDisplayName() {
        let reset = "2026-08-11T03:15:29Z"
        let raw: [[String: Any]] = [[
            "kind": "weekly_scoped",
            "scope": ["model": ["display_name": "Fable"]],
            "percent": 2,
            "resets_at": reset
        ]]
        let parsed = ClaudeScopedQuotaParser.fableWeeklyLimit(from: raw)
        expect(parsed?.usedPercent == 2, "Fable percent should parse")
        expect(parsed?.resetsAt != nil, "Fable reset date should parse")
    }

    private static func parsesStringModelAndAlternatePercentField() {
        let raw: [[String: Any]] = [[
            "kind": "weekly_scoped",
            "model": "claude-fable",
            "utilization": "101"
        ]]
        let parsed = ClaudeScopedQuotaParser.fableWeeklyLimit(from: raw)
        expect(parsed?.usedPercent == 100, "Fable percent should clamp to 100")
    }

    private static func ignoresOtherScopedModels() {
        let raw: [[String: Any]] = [[
            "kind": "weekly_scoped",
            "scope": ["model": ["display_name": "Opus"]],
            "percent": 37
        ]]
        expect(
            ClaudeScopedQuotaParser.fableWeeklyLimit(from: raw) == nil,
            "another model's weekly quota must not be labeled Fable"
        )
    }

    private static func rejectsNonWeeklyFableLimits() {
        let raw: [[String: Any]] = [[
            "kind": "monthly_scoped",
            "scope": ["model": ["display_name": "Fable"]],
            "percent": 4
        ]]
        expect(
            ClaudeScopedQuotaParser.fableWeeklyLimit(from: raw) == nil,
            "a non-weekly Fable limit must not be shown as weekly"
        )
    }

    private static func parsesAvailableResetGrant() {
        let now = ISO8601DateFormatter().date(from: "2026-09-25T12:00:00Z")!
        let raw: [String: Any] = [
            "eligible": true,
            "grants": [[
                "resets_left": 1,
                "starts_at": "2026-09-22T16:00:00+00:00",
                "ends_at": "2026-10-22T16:00:00+00:00",
                "clears": ["five_hour", "seven_day"],
                "usable_now": true,
                "paused": false
            ]]
        ]
        let parsed = ClaudeResetGrantParser.parse(raw, now: now)
        expect(parsed?.availableCount == 1, "available reset count should parse")
        expect(parsed?.clears.contains("seven_day") == true, "weekly reset scope should parse")
        expect(parsed?.nextExpiry != nil, "grant expiry should parse")
        expect(parsed?.usableNow == true, "usable-now flag should parse")
    }

    private static func rejectsIneligibleAndExpiredResets() {
        let now = ISO8601DateFormatter().date(from: "2026-09-25T12:00:00Z")!
        expect(
            ClaudeResetGrantParser.parse(["eligible": false, "grants": []], now: now) == nil,
            "surface-ineligible response must remain unknown"
        )
        let raw: [String: Any] = [
            "eligible": true,
            "grants": [
                ["resets_left": 2, "ends_at": "2026-09-24T12:00:00Z"],
                ["resets_left": 1, "paused": true],
                ["resets_left": true]
            ]
        ]
        expect(
            ClaudeResetGrantParser.parse(raw, now: now)?.availableCount == 0,
            "expired, paused, and malformed grants must not count"
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures.append(message)
        }
    }
}
