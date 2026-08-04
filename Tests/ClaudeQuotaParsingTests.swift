import Foundation

@main
enum ClaudeQuotaParsingTests {
    private static var failures: [String] = []

    static func main() {
        parsesFableDisplayName()
        parsesStringModelAndAlternatePercentField()
        ignoresOtherScopedModels()
        rejectsNonWeeklyFableLimits()

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

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures.append(message)
        }
    }
}
