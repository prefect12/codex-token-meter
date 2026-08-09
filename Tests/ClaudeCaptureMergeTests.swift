import Foundation

@main
enum ClaudeCaptureMergeTests {
    private static var failures: [String] = []
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func main() {
        keepsStoredWindowWhenIdleSessionReplaysLowerPercent()
        acceptsHigherStatuslinePercent()
        acceptsLowerPercentAfterCycleRollover()
        rejectsWindowFromPreviousCycle()
        stampsStatuslineWritesWithWriterIdentity()
        dropsIncomingWindowWhoseResetPassed()
        statuslineWritesDoNotCountAsServerVerification()
        recentOAuthWindowSkipsRefresh()
        agedOAuthWindowNeedsRefresh()
        passedResetNeedsRefresh()
        missingRateLimitsNeedsRefresh()

        if failures.isEmpty {
            print("PASS: ClaudeCaptureMerge")
            return
        }
        for failure in failures {
            FileHandle.standardError.write(Data("FAIL: \(failure)\n".utf8))
        }
        exit(1)
    }

    // MARK: Merge

    private static func keepsStoredWindowWhenIdleSessionReplaysLowerPercent() {
        let reset = now.addingTimeInterval(3600).timeIntervalSince1970
        let stored = oauthWindow(percent: 62, reset: reset, capturedAgo: 10)
        let incoming: [String: Any] = ["used_percentage": 45, "resets_at": reset]
        let merged = ClaudeCaptureMerge.mergedStatuslineWindow(incoming: incoming, stored: stored, now: now)
        expect(
            ClaudeCaptureMerge.percent(merged?["used_percentage"]) == 62,
            "an idle session replaying a lower percent must not roll the quota back"
        )
    }

    private static func acceptsHigherStatuslinePercent() {
        let reset = now.addingTimeInterval(3600).timeIntervalSince1970
        let stored = oauthWindow(percent: 62, reset: reset, capturedAgo: 10)
        let incoming: [String: Any] = ["used_percentage": 67, "resets_at": reset]
        let merged = ClaudeCaptureMerge.mergedStatuslineWindow(incoming: incoming, stored: stored, now: now)
        expect(
            ClaudeCaptureMerge.percent(merged?["used_percentage"]) == 67,
            "a higher statusline percent is real usage and must win"
        )
    }

    private static func acceptsLowerPercentAfterCycleRollover() {
        let oldReset = now.addingTimeInterval(600).timeIntervalSince1970
        let newReset = now.addingTimeInterval(604_800).timeIntervalSince1970
        let stored = oauthWindow(percent: 95, reset: oldReset, capturedAgo: 10)
        let incoming: [String: Any] = ["used_percentage": 3, "resets_at": newReset]
        let merged = ClaudeCaptureMerge.mergedStatuslineWindow(incoming: incoming, stored: stored, now: now)
        expect(
            ClaudeCaptureMerge.percent(merged?["used_percentage"]) == 3,
            "a later reset means the cycle rolled over, so a lower percent is genuine"
        )
    }

    private static func rejectsWindowFromPreviousCycle() {
        let oldReset = now.addingTimeInterval(600).timeIntervalSince1970
        let newReset = now.addingTimeInterval(604_800).timeIntervalSince1970
        let stored = oauthWindow(percent: 4, reset: newReset, capturedAgo: 10)
        let incoming: [String: Any] = ["used_percentage": 95, "resets_at": oldReset]
        let merged = ClaudeCaptureMerge.mergedStatuslineWindow(incoming: incoming, stored: stored, now: now)
        expect(
            ClaudeCaptureMerge.percent(merged?["used_percentage"]) == 4,
            "a reading from an already-finished cycle must not overwrite the current one"
        )
    }

    private static func stampsStatuslineWritesWithWriterIdentity() {
        let reset = now.addingTimeInterval(3600).timeIntervalSince1970
        let incoming: [String: Any] = ["used_percentage": 12, "resets_at": reset]
        let merged = ClaudeCaptureMerge.mergedStatuslineWindow(incoming: incoming, stored: nil, now: now)
        expect(
            merged?[ClaudeCaptureMerge.sourceKey] as? String == ClaudeCaptureMerge.statuslineSource,
            "statusline writes must record their writer"
        )
        expect(
            ClaudeCaptureMerge.capturedAt(merged ?? [:]) == now.timeIntervalSince1970,
            "statusline writes must carry their own capture time"
        )
    }

    private static func dropsIncomingWindowWhoseResetPassed() {
        let stored = oauthWindow(percent: 40, reset: now.addingTimeInterval(3600).timeIntervalSince1970, capturedAgo: 10)
        let incoming: [String: Any] = [
            "used_percentage": 99,
            "resets_at": now.addingTimeInterval(-60).timeIntervalSince1970
        ]
        let merged = ClaudeCaptureMerge.mergedStatuslineWindow(incoming: incoming, stored: stored, now: now)
        expect(
            ClaudeCaptureMerge.percent(merged?["used_percentage"]) == 40,
            "a window whose cycle already reset carries a dead percentage"
        )
    }

    // MARK: Refresh scheduling

    private static func statuslineWritesDoNotCountAsServerVerification() {
        let rateLimits: [String: Any] = [
            "five_hour": [
                "used_percentage": 5,
                "captured_at_epoch": Int(now.timeIntervalSince1970),
                "source": ClaudeCaptureMerge.statuslineSource
            ]
        ]
        expect(
            ClaudeCaptureMerge.needsServerRefresh(rateLimits: rateLimits, now: now),
            "a stream of statusline writes must not starve the refresher"
        )
    }

    private static func recentOAuthWindowSkipsRefresh() {
        let rateLimits: [String: Any] = [
            "five_hour": oauthWindow(percent: 5, reset: nil, capturedAgo: 5)
        ]
        expect(
            !ClaudeCaptureMerge.needsServerRefresh(rateLimits: rateLimits, now: now),
            "a just-verified window should not trigger another fetch"
        )
    }

    private static func agedOAuthWindowNeedsRefresh() {
        let aged = ClaudeCaptureMerge.refreshTTLSeconds + 5
        let rateLimits: [String: Any] = [
            "five_hour": oauthWindow(percent: 5, reset: nil, capturedAgo: aged)
        ]
        expect(
            ClaudeCaptureMerge.needsServerRefresh(rateLimits: rateLimits, now: now),
            "a window older than the refresh TTL must be re-verified"
        )
    }

    private static func passedResetNeedsRefresh() {
        let rateLimits: [String: Any] = [
            "five_hour": oauthWindow(
                percent: 95,
                reset: now.addingTimeInterval(-1).timeIntervalSince1970,
                capturedAgo: 1
            )
        ]
        expect(
            ClaudeCaptureMerge.needsServerRefresh(rateLimits: rateLimits, now: now),
            "a rolled-over cycle must be re-fetched immediately"
        )
    }

    private static func missingRateLimitsNeedsRefresh() {
        expect(
            ClaudeCaptureMerge.needsServerRefresh(rateLimits: nil, now: now),
            "no capture at all means fetch"
        )
        expect(
            ClaudeCaptureMerge.needsServerRefresh(rateLimits: [:], now: now),
            "an empty capture means fetch"
        )
    }

    // MARK: Helpers

    private static func oauthWindow(percent: Double, reset: Double?, capturedAgo: TimeInterval) -> [String: Any] {
        var dict: [String: Any] = [
            "used_percentage": percent,
            "captured_at_epoch": Int(now.timeIntervalSince1970 - capturedAgo),
            "source": ClaudeCaptureMerge.oauthSource
        ]
        if let reset {
            dict["resets_at"] = Int(reset)
        }
        return dict
    }

    private static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            failures.append(message)
        }
    }
}
