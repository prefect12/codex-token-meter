import Foundation

/// Merge and freshness rules for the shared Claude quota capture file.
///
/// Two independent writers own `claude-statusline.json`. The Claude Code
/// statusline hook writes every few seconds while any CLI session is open, and
/// the OAuth refresher writes whatever the usage endpoint reports. Only the
/// second one is authoritative: an idle session keeps replaying the rate limits
/// from its last API response, so its writes are frequent but can be hours old.
///
/// These rules therefore separate three questions that a single timestamp used
/// to answer at once: is a window still worth displaying, may an incoming
/// statusline window replace a stored one, and how long ago did the app last
/// hear from the server.
enum ClaudeCaptureMerge {
    static let percentKey = "used_percentage"
    static let resetsAtKey = "resets_at"
    static let capturedAtKey = "captured_at_epoch"
    /// Records which writer produced a window so frequent statusline writes can
    /// never be mistaken for server confirmation.
    static let sourceKey = "source"
    static let oauthSource = "oauth"
    static let statuslineSource = "statusline"

    /// How long a captured window stays trustworthy enough to keep showing.
    /// Displaying a slightly old percentage is much better than blanking the
    /// quota out, so this stays generous.
    static let displayTTLSeconds: TimeInterval = 10 * 60

    /// How long a server-confirmed window stays current enough to skip a fetch.
    /// Short on purpose: the refresher is cheap, and this is the ceiling on how
    /// far the displayed quota can drift behind Claude Code's own `/usage`.
    static let refreshTTLSeconds: TimeInterval = 30

    /// Reset timestamps drift by a second or two between responses; anything
    /// inside this tolerance is the same quota cycle.
    private static let cycleTolerance: TimeInterval = 60

    // MARK: Field access

    static func finiteDouble(_ raw: Any?) -> Double? {
        if let raw, CFGetTypeID(raw as CFTypeRef) == CFBooleanGetTypeID() {
            return nil
        }
        let value: Double?
        if let raw = raw as? Double {
            value = raw
        } else if let raw = raw as? Int {
            value = Double(raw)
        } else if let raw = raw as? String {
            value = Double(raw)
        } else {
            value = nil
        }
        guard let value, value.isFinite else { return nil }
        return value
    }

    static func percent(_ raw: Any?) -> Double? {
        guard let value = finiteDouble(raw), value >= 0 else { return nil }
        if value > 100 {
            return value <= 101 ? 100 : nil
        }
        return value
    }

    static func resetsAt(_ dict: [String: Any]) -> Double? {
        finiteDouble(dict[resetsAtKey])
    }

    static func capturedAt(_ dict: [String: Any]) -> Double? {
        finiteDouble(dict[capturedAtKey])
    }

    static func isOAuthCaptured(_ dict: [String: Any]) -> Bool {
        (dict[sourceKey] as? String) == oauthSource
    }

    /// True once the window's cycle has rolled over, which means its percentage
    /// belongs to a quota period that no longer exists.
    static func resetPassed(_ dict: [String: Any], now: Date) -> Bool {
        guard let resetsAt = resetsAt(dict) else { return false }
        return now.timeIntervalSince1970 >= resetsAt
    }

    /// True when the window was captured longer ago than the display TTL.
    static func displayExpired(_ dict: [String: Any], now: Date) -> Bool {
        guard let captured = capturedAt(dict) else { return false }
        return now.timeIntervalSince1970 - captured > displayTTLSeconds
    }

    // MARK: Merge

    /// Decides which of a freshly delivered statusline window and the stored one
    /// should be kept.
    ///
    /// `stored` must already be filtered to windows that are still displayable.
    /// The incoming window wins by default — it is usually the newer reading —
    /// except where accepting it would move the quota backwards.
    static func mergedStatuslineWindow(
        incoming: Any?,
        stored: [String: Any]?,
        now: Date
    ) -> [String: Any]? {
        guard var incomingDict = incoming as? [String: Any],
              let incomingPercent = percent(incomingDict[percentKey]),
              !resetPassed(incomingDict, now: now) else {
            return stored
        }
        incomingDict[capturedAtKey] = Int(now.timeIntervalSince1970)
        incomingDict[sourceKey] = statuslineSource
        guard let stored, let storedPercent = percent(stored[percentKey]) else {
            return incomingDict
        }
        if let incomingReset = resetsAt(incomingDict), let storedReset = resetsAt(stored) {
            // An incoming window from an older cycle is a session replaying a
            // reading the account has already moved past.
            if incomingReset + cycleTolerance < storedReset { return stored }
            // A later reset means the cycle rolled over, so a lower percentage
            // is a genuine reset rather than stale data.
            if incomingReset > storedReset + cycleTolerance { return incomingDict }
        }
        // Same cycle: usage only ever climbs. A lower number therefore means the
        // session that reported it has been idle since before the stored one.
        return incomingPercent < storedPercent ? stored : incomingDict
    }

    /// Stamps an OAuth-fetched window so later freshness checks can tell it apart
    /// from a statusline write.
    static func oauthWindow(usedPercent: Double, resetsAt: Date?, now: Date) -> [String: Any] {
        var dict: [String: Any] = [
            percentKey: usedPercent,
            capturedAtKey: Int(now.timeIntervalSince1970),
            sourceKey: oauthSource
        ]
        if let resetsAt {
            dict[resetsAtKey] = Int(resetsAt.timeIntervalSince1970)
        }
        return dict
    }

    // MARK: Refresh scheduling

    /// The most recent moment any window was confirmed against the server.
    static func lastOAuthVerification(in rateLimits: [String: Any]) -> Double? {
        rateLimits.values
            .compactMap { $0 as? [String: Any] }
            .filter { isOAuthCaptured($0) }
            .compactMap { capturedAt($0) }
            .max()
    }

    /// Whether the app should query the usage endpoint again.
    ///
    /// Deliberately independent of the statusline writer: a capture file kept
    /// permanently "fresh" by a stream of statusline writes still has to be
    /// re-verified once `refreshTTLSeconds` passes.
    static func needsServerRefresh(rateLimits: [String: Any]?, now: Date) -> Bool {
        guard let rateLimits, !rateLimits.isEmpty else { return true }
        let windows = rateLimits.values.compactMap { $0 as? [String: Any] }
        if windows.contains(where: { resetPassed($0, now: now) }) { return true }
        guard let verifiedAt = lastOAuthVerification(in: rateLimits) else { return true }
        return now.timeIntervalSince1970 - verifiedAt > refreshTTLSeconds
    }
}
