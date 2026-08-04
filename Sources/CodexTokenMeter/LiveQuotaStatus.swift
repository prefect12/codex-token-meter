import Cocoa
import Foundation
import Security
import ServiceManagement
import UserNotifications

// MARK: - Live Quota And Service Status

enum QuotaViewOption: String, CaseIterable {
    case all
    case codex
    case claude

    static func option(from rawValue: String) -> QuotaViewOption? {
        switch rawValue {
        case "all":
            return .all
        case "codex", "other":
            return .codex
        case "claude", "spark":
            return .claude
        default:
            return nil
        }
    }

    var scanLimitID: String? {
        nil
    }

    var excludedScanLimitID: String? {
        nil
    }

    var includedModelName: String? {
        nil
    }

    var excludedModelName: String? {
        nil
    }

    var liveLimitID: String {
        switch self {
        case .all, .codex: return "codex"
        case .claude: return "claude"
        }
    }

    var shortTitle: String {
        switch self {
        case .all: return t(.all)
        case .codex: return t(.codex)
        case .claude: return t(.claude)
        }
    }

    var fallbackTitle: String {
        switch self {
        case .all: return t(.combinedUsage)
        case .codex: return t(.codex)
        case .claude: return t(.claude)
        }
    }

    var usesCodexProfileAPI: Bool {
        self == .all || self == .codex
    }
}

struct RateWindow: Codable {
    let usedPercent: Double
    let windowMinutes: Int
    let resetsAt: Date?

    var remainingPercent: Double { max(0, 100 - usedPercent) }
}

enum PaceStatus {
    case ahead
    case behind
}

struct PaceComparison {
    let progressPercent: Double
    let usedPercent: Double
    let status: PaceStatus
}

struct RingRemainingComparison {
    let expectedRemainingPercent: Double
    let actualRemainingPercent: Double
    let status: PaceStatus
}

func paceComparison(for window: RateWindow, now: Date = Date()) -> PaceComparison? {
    guard window.windowMinutes > 0,
          let resetsAt = window.resetsAt else {
        return nil
    }
    let duration = TimeInterval(window.windowMinutes) * 60
    let start = resetsAt.addingTimeInterval(-duration)
    guard duration > 0, start < resetsAt else { return nil }

    let elapsedRatio = min(1, max(0, now.timeIntervalSince(start) / duration))
    let progressPercent = elapsedRatio * 100
    let usedPercent = max(0, window.usedPercent)
    let delta = usedPercent - progressPercent
    let status: PaceStatus
    if delta > 0 {
        status = .ahead
    } else {
        status = .behind
    }

    return PaceComparison(
        progressPercent: progressPercent,
        usedPercent: usedPercent,
        status: status
    )
}

struct LiveRateLimit: Codable {
    let id: String
    let name: String
    let primary: RateWindow?
    let secondary: RateWindow?
    let planType: String?
    let capturedAt: Date?
}

let claudeFableLiveLimitID = "claude_fable_5"

struct RateLimitResetCredit: Codable {
    let status: String
    let grantedAt: Date?
    let expiresAt: Date?
    let expirationIsEstimated: Bool

    var isAvailable: Bool {
        status.lowercased() == "available"
    }
}

struct RateLimitResetCreditsSnapshot: Codable {
    let availableCount: Int
    let totalEarnedCount: Int?
    let credits: [RateLimitResetCredit]
    let readAt: Date
    let source: String

    var availableCredits: [RateLimitResetCredit] {
        credits.filter(\.isAvailable)
    }

    var nextExpiringAvailableCredit: RateLimitResetCredit? {
        availableCredits
            .filter { ($0.expiresAt ?? .distantFuture) > Date() }
            .sorted {
                ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture)
            }
            .first
    }
}

struct ClaudeStatuslineWindow {
    let usedPercent: Double
    let resetsAt: Date?
}

struct ClaudeStatuslineSnapshot {
    let capturedAt: Date?
    let readAt: Date
    let isStale: Bool
    let fiveHour: ClaudeStatuslineWindow?
    let sevenDay: ClaudeStatuslineWindow?
    let fableSevenDay: ClaudeStatuslineWindow?

    var liveRateLimit: LiveRateLimit? {
        guard let fiveHour,
              let sevenDay else {
            return nil
        }
        return LiveRateLimit(
            id: QuotaViewOption.claude.liveLimitID,
            name: "Claude Code",
            primary: RateWindow(usedPercent: fiveHour.usedPercent, windowMinutes: 5 * 60, resetsAt: fiveHour.resetsAt),
            secondary: RateWindow(usedPercent: sevenDay.usedPercent, windowMinutes: 7 * 24 * 60, resetsAt: sevenDay.resetsAt),
            planType: isStale ? "official-statusline-stale" : "official-statusline",
            capturedAt: capturedAt
        )
    }

    var fableLiveRateLimit: LiveRateLimit? {
        guard let fableSevenDay else { return nil }
        return LiveRateLimit(
            id: claudeFableLiveLimitID,
            name: "Fable",
            primary: nil,
            secondary: RateWindow(
                usedPercent: fableSevenDay.usedPercent,
                windowMinutes: 7 * 24 * 60,
                resetsAt: fableSevenDay.resetsAt
            ),
            planType: isStale ? "official-statusline-stale" : "official-statusline",
            capturedAt: capturedAt
        )
    }
}

func liveRateLimitIsStale(_ limit: LiveRateLimit?) -> Bool {
    limit?.planType == "official-statusline-stale"
}

enum LiveRateLimitCacheStore {
    // Fable model-scoped limits are tracked again; reject older cache shapes.
    private static let version = 3

    private struct Payload: Codable {
        let version: Int
        let writtenAt: Date
        let limits: [LiveRateLimit]
    }

    static func read() -> [LiveRateLimit] {
        let url = AppSettings.liveLimitsCacheURL
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.version == version else {
            return []
        }
        return sanitized(payload.limits)
    }

    static func write(_ limits: [LiveRateLimit]) {
        let limits = sanitized(limits)
        guard !limits.isEmpty else { return }
        let payload = Payload(version: version, writtenAt: Date(), limits: limits)
        do {
            try FileManager.default.createDirectory(at: AppSettings.appSupportDirectoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            try data.write(to: AppSettings.liveLimitsCacheURL, options: .atomic)
        } catch {
            NSLog("AI Token Meter live limits cache write failed: \(error.localizedDescription)")
        }
    }

    static func remove() {
        try? FileManager.default.removeItem(at: AppSettings.liveLimitsCacheURL)
    }

    private static func sanitized(_ limits: [LiveRateLimit]) -> [LiveRateLimit] {
        var byID: [String: LiveRateLimit] = [:]
        for limit in limits where isUsable(limit) {
            byID[limit.id] = limit
        }
        return byID.values.sorted { $0.id < $1.id }
    }

    private static func isUsable(_ limit: LiveRateLimit) -> Bool {
        let windows = [limit.primary, limit.secondary].compactMap { $0 }
        return !windows.isEmpty && windows.allSatisfy {
            $0.usedPercent.isFinite && $0.windowMinutes > 0
        }
    }
}

final class ClaudeStatuslineStore {
    private static let ttlSeconds: TimeInterval = 10 * 60
    /// Capture-file key for the model-scoped Fable weekly window.
    static let fableWindowKey = "seven_day_fable"
    private let url: URL

    init(url: URL = AppSettings.claudeStatuslineCaptureURL) {
        self.url = url
    }

    var path: String { url.path }

    func read(now: Date = Date()) -> ClaudeStatuslineSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return readLegacyMonitorCapture(now: now)
        }
        return parseCapture(object, now: now) ?? readLegacyMonitorCapture(now: now)
    }

    func capture(stdinData: Data, now: Date = Date()) throws -> ClaudeStatuslineSnapshot? {
        let object = try JSONSerialization.jsonObject(with: stdinData) as? [String: Any] ?? [:]
        var rateLimits = object["rate_limits"] as? [String: Any]
        // Claude Code's statusline payload does not include model-scoped
        // limits. Preserve a recent OAuth-captured Fable window.
        if rateLimits != nil, rateLimits?[Self.fableWindowKey] == nil,
           let fable = storedFableWindowDict(now: now) {
            rateLimits?[Self.fableWindowKey] = fable
        }
        return try writeCapture(rateLimits: rateLimits, now: now)
    }

    private func storedFableWindowDict(now: Date) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rateLimits = object["rate_limits"] as? [String: Any],
              let dict = rateLimits[Self.fableWindowKey] as? [String: Any],
              parseFableWindow(dict, now: now) != nil else {
            return nil
        }
        return dict
    }

    func captureUsageWindows(
        fiveHour: ClaudeStatuslineWindow,
        sevenDay: ClaudeStatuslineWindow,
        fableSevenDay: ClaudeStatuslineWindow? = nil,
        now: Date = Date()
    ) throws -> ClaudeStatuslineSnapshot? {
        func windowDict(_ window: ClaudeStatuslineWindow) -> [String: Any] {
            var dict: [String: Any] = ["used_percentage": window.usedPercent]
            if let resetsAt = window.resetsAt {
                dict["resets_at"] = Int(resetsAt.timeIntervalSince1970)
            }
            return dict
        }
        var rateLimits: [String: Any] = [
            "five_hour": windowDict(fiveHour),
            "seven_day": windowDict(sevenDay)
        ]
        if let fableSevenDay {
            var dict = windowDict(fableSevenDay)
            dict["captured_at_epoch"] = Int(now.timeIntervalSince1970)
            rateLimits[Self.fableWindowKey] = dict
        }
        return try writeCapture(rateLimits: rateLimits, now: now)
    }

    private func writeCapture(rateLimits: [String: Any]?, now: Date) throws -> ClaudeStatuslineSnapshot? {
        let capture: [String: Any] = [
            "captured_at_epoch": Int(now.timeIntervalSince1970),
            "rate_limits": rateLimits as Any
        ]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: capture, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: [.atomic])
        return parseCapture(capture, now: now)
    }

    func statuslineText(from stdinData: Data, snapshot: ClaudeStatuslineSnapshot?) -> String {
        var parts: [String] = []
        if let object = try? JSONSerialization.jsonObject(with: stdinData) as? [String: Any],
           let model = object["model"] as? [String: Any] {
            if let displayName = model["display_name"] as? String, !displayName.isEmpty {
                parts.append(displayName)
            } else if let name = model["name"] as? String, !name.isEmpty {
                parts.append(name)
            }
        }
        if let percent = snapshot?.fiveHour?.usedPercent {
            parts.append("5h \(Int(round(percent)))%")
        }
        if let percent = snapshot?.sevenDay?.usedPercent {
            parts.append("7d \(Int(round(percent)))%")
        }
        if let percent = snapshot?.fableSevenDay?.usedPercent {
            parts.append("Fable \(Int(round(percent)))%")
        }
        return parts.isEmpty ? "AI Token Meter" : parts.joined(separator: " · ")
    }

    private func readLegacyMonitorCapture(now: Date) -> ClaudeStatuslineSnapshot? {
        let legacy = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude-monitor/statusline/latest.json")
        guard legacy.path != url.path,
              let data = try? Data(contentsOf: legacy),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return parseCapture(object, now: now)
    }

    private func parseCapture(_ object: [String: Any], now: Date) -> ClaudeStatuslineSnapshot? {
        guard let rateLimits = object["rate_limits"] as? [String: Any] else { return nil }
        let capturedAt = finiteDouble(object["captured_at_epoch"]).map { Date(timeIntervalSince1970: $0) }
        let isStale = capturedAt.map { now.timeIntervalSince($0) > Self.ttlSeconds } ?? false
        let fiveHour = parseWindow(rateLimits["five_hour"], now: now, windowMinutes: 5 * 60)
        let sevenDay = parseWindow(rateLimits["seven_day"], now: now, windowMinutes: 7 * 24 * 60)
        let fableSevenDay = parseFableWindow(rateLimits[Self.fableWindowKey], now: now)
        guard fiveHour != nil || sevenDay != nil || fableSevenDay != nil else { return nil }
        return ClaudeStatuslineSnapshot(
            capturedAt: capturedAt,
            readAt: now,
            isStale: isStale,
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            fableSevenDay: fableSevenDay
        )
    }

    private func parseFableWindow(_ raw: Any?, now: Date) -> ClaudeStatuslineWindow? {
        guard let dict = raw as? [String: Any] else { return nil }
        if let captured = finiteDouble(dict["captured_at_epoch"]),
           now.timeIntervalSince(Date(timeIntervalSince1970: captured)) > Self.ttlSeconds {
            return nil
        }
        return parseWindow(dict, now: now, windowMinutes: 7 * 24 * 60)
    }

    private func parseWindow(_ raw: Any?, now: Date, windowMinutes: Int) -> ClaudeStatuslineWindow? {
        guard let dict = raw as? [String: Any],
              let percent = cleanPercent(dict["used_percentage"]) else {
            return nil
        }
        let usedPercent = percent
        var resetsAt = finiteDouble(dict["resets_at"]).map { Date(timeIntervalSince1970: $0) }
        if let resetDate = resetsAt, now >= resetDate, windowMinutes > 0 {
            let windowSeconds = TimeInterval(windowMinutes) * 60
            let elapsedWindows = floor(now.timeIntervalSince(resetDate) / windowSeconds) + 1
            resetsAt = resetDate.addingTimeInterval(elapsedWindows * windowSeconds)
        }
        return ClaudeStatuslineWindow(usedPercent: usedPercent, resetsAt: resetsAt)
    }

    private func cleanPercent(_ raw: Any?) -> Double? {
        guard let value = finiteDouble(raw), value >= 0 else { return nil }
        if value > 100 {
            return value <= 101 ? 100 : nil
        }
        return value
    }

    private func finiteDouble(_ raw: Any?) -> Double? {
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
}

/// Refreshes Claude quota by querying the same server endpoint Claude Code's
/// `/usage` panel uses. Reads the OAuth token Claude Code already stores
/// locally; the query itself consumes no model quota.
final class ClaudeOAuthUsageRefresher {
    static let shared = ClaudeOAuthUsageRefresher()

    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let lock = NSLock()
    private var nextAttemptAt = Date.distantPast
    private let attemptInterval: TimeInterval = 60
    private let failureBackoff: TimeInterval = 15 * 60
    private let credentialFailureBackoff: TimeInterval = 30 * 60
    private let session: URLSession

    private struct UsageWindows {
        let fiveHour: ClaudeStatuslineWindow
        let sevenDay: ClaudeStatuslineWindow
        let fableSevenDay: ClaudeStatuslineWindow?
    }

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    @discardableResult
    func refreshIfNeeded(store: ClaudeStatuslineStore, now: Date = Date()) -> Bool {
        // Statusline captures can keep the top-level windows fresh without
        // carrying Fable. Fetch until Fable is present or its absence was
        // recently confirmed.
        if let snapshot = store.read(now: now), !snapshot.isStale,
           snapshot.fableSevenDay != nil || fableConfirmedAbsent(now: now) {
            setOutcome("fresh-cache")
            return false
        }
        guard shouldAttempt(now: now) else {
            setOutcome("throttled")
            return false
        }
        guard let token = oauthAccessToken(now: now) else {
            // oauthAccessToken records the specific credential failure.
            postpone(now: now, interval: credentialFailureBackoff)
            return false
        }
        guard let windows = fetchUsageWindows(token: token, now: now) else {
            setOutcome("fetch-failed")
            postpone(now: now, interval: failureBackoff)
            return false
        }
        do {
            _ = try store.captureUsageWindows(
                fiveHour: windows.fiveHour,
                sevenDay: windows.sevenDay,
                fableSevenDay: windows.fableSevenDay,
                now: now
            )
            if windows.fableSevenDay == nil {
                markFableAbsent(now: now)
            }
            setOutcome("refreshed")
            return true
        } catch {
            NSLog("AI Token Meter Claude OAuth usage write failed: \(error.localizedDescription)")
            setOutcome("write-failed")
            postpone(now: now, interval: failureBackoff)
            return false
        }
    }

    /// Why the most recent refreshIfNeeded call ended the way it did; surfaced
    /// by the --refresh-claude-usage diagnostic.
    var lastOutcome: String {
        lock.lock()
        defer { lock.unlock() }
        return _lastOutcome
    }

    private var _lastOutcome = "not-attempted"

    private func setOutcome(_ value: String) {
        lock.lock()
        _lastOutcome = value
        lock.unlock()
    }

    private func shouldAttempt(now: Date) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard now >= nextAttemptAt else { return false }
        nextAttemptAt = now.addingTimeInterval(attemptInterval)
        return true
    }

    /// Accounts without a Fable quota would otherwise re-fetch every minute.
    private var fableAbsentUntil = Date.distantPast

    private func fableConfirmedAbsent(now: Date) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return now < fableAbsentUntil
    }

    private func markFableAbsent(now: Date) {
        lock.lock()
        fableAbsentUntil = now.addingTimeInterval(10 * 60)
        lock.unlock()
    }

    private func postpone(now: Date, interval: TimeInterval) {
        lock.lock()
        nextAttemptAt = now.addingTimeInterval(interval)
        lock.unlock()
    }

    // MARK: Credentials

    /// OAuth client id of Claude Code itself; the refresh-token flow must use
    /// the same client the tokens were issued to.
    private static let oauthClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let tokenURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    private static let keychainService = "Claude Code-credentials"

    private enum CredentialSource {
        case file(URL)
        case keychain
    }

    private struct StoredCredentials {
        var root: [String: Any]
        var oauth: [String: Any]
        let source: CredentialSource
    }

    private var cachedToken: (token: String, validUntil: Date)?

    static func disableKeychainInteraction() {
        // Claude uses a legacy macOS Keychain item, for which modern SecItem
        // query flags can still launch SecurityAgent. This process-wide legacy
        // switch is the only reliable background no-UI boundary on macOS.
        _ = SecKeychainSetUserInteractionAllowed(false)
    }

    var needsInitialKeychainAccess: Bool {
        fileCredentials() == nil
    }

    /// Checks only legacy ACL metadata. This never decrypts the credential and
    /// never enables Keychain UI, so app launch can reuse an existing grant
    /// without risking a password prompt.
    var hasPersistentKeychainAccess: Bool {
        Self.disableKeychainInteraction()
        return securityToolHasPersistentAccess(requireUnlocked: false)
    }

    func requestInitialKeychainAccess() -> Bool {
        guard needsInitialKeychainAccess else { return false }
        // Claude Code itself reads this legacy item through Apple's stable
        // /usr/bin/security executable. Authorize that system tool once
        // instead of authorizing each newly built AI Token Meter CDHash.
        return parseCredentials(
            data: keychainCredentialsData(allowInteraction: true),
            source: .keychain
        ) != nil
    }

    private func oauthAccessToken(now: Date) -> String? {
        lock.lock()
        if let cachedToken, cachedToken.validUntil > now {
            let token = cachedToken.token
            lock.unlock()
            return token
        }
        lock.unlock()

        guard let credentials = storedCredentials() else {
            if !AppSettings.claudeKeychainAccessEnabled {
                setOutcome("no-credentials-keychain-disabled")
            } else if lastKeychainStatus == errSecItemNotFound {
                setOutcome("no-credentials")
            } else if lastKeychainStatus == errSecInteractionNotAllowed {
                setOutcome("keychain-locked")
            } else {
                setOutcome("keychain-read-denied-\(lastKeychainStatus)")
            }
            return nil
        }
        let expiresAt = (credentials.oauth["expiresAt"] as? Double)
            .map { Date(timeIntervalSince1970: $0 / 1000) }
        if let token = credentials.oauth["accessToken"] as? String,
           !token.isEmpty,
           let expiresAt,
           expiresAt > now.addingTimeInterval(60) {
            cacheToken(token, validUntil: expiresAt.addingTimeInterval(-60))
            return token
        }
        return refreshAccessToken(credentials: credentials, now: now)
    }

    private var lastKeychainStatus: OSStatus = errSecSuccess

    private func cacheToken(_ token: String, validUntil: Date) {
        lock.lock()
        cachedToken = (token, validUntil)
        lock.unlock()
    }

    private func storedCredentials() -> StoredCredentials? {
        if let credentials = fileCredentials() {
            return credentials
        }
        guard AppSettings.claudeKeychainAccessEnabled else { return nil }
        Self.disableKeychainInteraction()
        return parseCredentials(
            data: keychainCredentialsData(allowInteraction: false),
            source: .keychain
        )
    }

    private func fileCredentials() -> StoredCredentials? {
        let fileURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/.credentials.json")
        return parseCredentials(data: try? Data(contentsOf: fileURL), source: .file(fileURL))
    }

    private func keychainCredentialsData(allowInteraction: Bool) -> Data? {
        if !allowInteraction {
            // The security CLI has no "fail instead of prompt" switch. Inspect
            // the legacy decrypt ACL and keychain lock state first so a
            // background refresh never launches a password dialog.
            guard securityToolHasPersistentAccess(requireUnlocked: true) else {
                if lastKeychainStatus == errSecSuccess {
                    lastKeychainStatus = errSecAuthFailed
                }
                return nil
            }
        }

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password",
            "-s", Self.keychainService,
            "-w"
        ]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            lastKeychainStatus = errSecNotAvailable
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            lastKeychainStatus = errSecAuthFailed
            return nil
        }

        // "Allow" authorizes only this invocation. Require the ACL entry that
        // "Always Allow" adds before enabling future background reads.
        if allowInteraction && !securityToolHasPersistentAccess(requireUnlocked: false) {
            lastKeychainStatus = errSecAuthFailed
            return nil
        }
        lastKeychainStatus = errSecSuccess
        return data
    }

    /// Read-only check for the persistent decrypt authorization Claude Code
    /// and AI Token Meter share through Apple's /usr/bin/security executable.
    /// The legacy ACL API is required because `Claude Code-credentials` is a
    /// legacy login-keychain item rather than a data-protection keychain item.
    private func securityToolHasPersistentAccess(requireUnlocked: Bool) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        lastKeychainStatus = status
        guard status == errSecSuccess,
              let item,
              CFGetTypeID(item) == SecKeychainItemGetTypeID() else {
            return false
        }
        let keychainItem = unsafeBitCast(item, to: SecKeychainItem.self)

        if requireUnlocked {
            var keychain: SecKeychain?
            var keychainStatus: SecKeychainStatus = 0
            guard SecKeychainItemCopyKeychain(keychainItem, &keychain) == errSecSuccess,
                  SecKeychainGetStatus(keychain, &keychainStatus) == errSecSuccess,
                  (keychainStatus & UInt32(kSecUnlockStateStatus)) != 0 else {
                lastKeychainStatus = errSecInteractionNotAllowed
                return false
            }
        }

        var access: SecAccess?
        guard SecKeychainItemCopyAccess(keychainItem, &access) == errSecSuccess,
              let access else {
            lastKeychainStatus = errSecAuthFailed
            return false
        }
        var aclArray: CFArray?
        guard SecAccessCopyACLList(access, &aclArray) == errSecSuccess,
              let acls = aclArray as? [SecACL] else {
            lastKeychainStatus = errSecAuthFailed
            return false
        }

        var securityApplication: SecTrustedApplication?
        guard SecTrustedApplicationCreateFromPath(
            "/usr/bin/security",
            &securityApplication
        ) == errSecSuccess,
              let securityApplication else {
            lastKeychainStatus = errSecAuthFailed
            return false
        }
        var securityApplicationData: CFData?
        guard SecTrustedApplicationCopyData(
            securityApplication,
            &securityApplicationData
        ) == errSecSuccess,
              let securityApplicationData else {
            lastKeychainStatus = errSecAuthFailed
            return false
        }

        for acl in acls {
            let authorizations = SecACLCopyAuthorizations(acl) as? [String]
            guard authorizations?.contains("ACLAuthorizationDecrypt") == true else {
                continue
            }
            var applications: CFArray?
            var description: CFString?
            var selector = SecKeychainPromptSelector()
            guard SecACLCopyContents(
                acl,
                &applications,
                &description,
                &selector
            ) == errSecSuccess else {
                continue
            }
            // A nil list means any application is already trusted.
            if applications == nil {
                lastKeychainStatus = errSecSuccess
                return true
            }
            for application in (applications as? [SecTrustedApplication]) ?? [] {
                var applicationData: CFData?
                if SecTrustedApplicationCopyData(
                    application,
                    &applicationData
                ) == errSecSuccess,
                   applicationData == securityApplicationData {
                    lastKeychainStatus = errSecSuccess
                    return true
                }
            }
        }
        lastKeychainStatus = errSecAuthFailed
        return false
    }

    private func parseCredentials(data: Data?, source: CredentialSource) -> StoredCredentials? {
        guard let data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              oauth["accessToken"] is String || oauth["refreshToken"] is String else {
            return nil
        }
        return StoredCredentials(root: root, oauth: oauth, source: source)
    }

    /// Exchanges the stored refresh token for a fresh access token. Rotated
    /// credentials are written back to their original shared source so Claude
    /// Code and AI Token Meter never race on different refresh-token versions.
    private func refreshAccessToken(credentials: StoredCredentials, now: Date) -> String? {
        guard let refreshToken = credentials.oauth["refreshToken"] as? String, !refreshToken.isEmpty else {
            setOutcome("no-refresh-token")
            NSLog("AI Token Meter Claude OAuth: access token expired and no refresh token available")
            return nil
        }
        if case .keychain = credentials.source {
            // Prove the rotated tokens can be written back BEFORE consuming the
            // refresh token; a rotation we could not persist would strand
            // Claude Code with a dead refresh token.
            guard let currentData = try? JSONSerialization.data(withJSONObject: credentials.root),
                  updateKeychainCredentials(data: currentData) else {
                setOutcome("keychain-write-denied")
                NSLog("AI Token Meter Claude OAuth: cannot write back rotated tokens; skipping keychain token refresh")
                return nil
            }
        }
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.oauthClientID
        ])

        guard let result = performRequest(request), let data = result.data else {
            setOutcome("token-refresh-failed")
            NSLog("AI Token Meter Claude OAuth token refresh failed")
            return nil
        }
        let status = result.status
        guard (200..<300).contains(status),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = object["access_token"] as? String,
              !accessToken.isEmpty else {
            setOutcome("token-refresh-rejected-\(status)")
            NSLog("AI Token Meter Claude OAuth token refresh rejected with status \(status)")
            return nil
        }

        var updatedOAuth = credentials.oauth
        updatedOAuth["accessToken"] = accessToken
        if let rotated = object["refresh_token"] as? String, !rotated.isEmpty {
            updatedOAuth["refreshToken"] = rotated
        }
        var expiresAt = now.addingTimeInterval(8 * 60 * 60)
        if let expiresIn = object["expires_in"] as? Double, expiresIn > 0 {
            expiresAt = now.addingTimeInterval(expiresIn)
        }
        updatedOAuth["expiresAt"] = expiresAt.timeIntervalSince1970 * 1000
        var updatedRoot = credentials.root
        updatedRoot["claudeAiOauth"] = updatedOAuth
        switch credentials.source {
        case .file(let fileURL):
            writeBackCredentials(root: updatedRoot, fileURL: fileURL)
        case .keychain:
            if let data = try? JSONSerialization.data(withJSONObject: updatedRoot),
               !updateKeychainCredentials(data: data) {
                NSLog("AI Token Meter Claude OAuth: failed to write rotated tokens back to keychain")
            }
        }

        cacheToken(accessToken, validUntil: expiresAt.addingTimeInterval(-60))
        return accessToken
    }

    private func updateKeychainCredentials(data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let attributes = result as? [String: Any],
              let account = attributes[kSecAttrAccount as String] as? String,
              !account.isEmpty,
              let credential = String(data: data, encoding: .utf8) else {
            return false
        }

        // Keep credential writes tied to Apple's stable /usr/bin/security
        // executable, just like reads. Direct SecItemUpdate calls authorize
        // this app's ad-hoc CDHash; every rebuild can then leave another stale
        // trusted-application entry and cause recurring password prompts.
        //
        // Run security's interactive command parser through stdin so the value
        // never appears in argv / process listings. The direct `-w` prompt is
        // backed by readpassphrase(3) and truncates values at 128 bytes, which
        // is far too small for Claude's JSON credential. `security -i` accepts
        // the complete command stream without that limit.
        func quotedSecurityArgument(_ value: String) -> String {
            "\"" + value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let command = [
            "add-generic-password",
            "-U",
            "-a", quotedSecurityArgument(account),
            "-s", quotedSecurityArgument(Self.keychainService),
            "-w", quotedSecurityArgument(credential)
        ].joined(separator: " ") + "\n"

        let process = Process()
        let input = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["-i"]
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            try input.fileHandleForWriting.write(contentsOf: Data(command.utf8))
            try input.fileHandleForWriting.close()
        } catch {
            try? input.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
            }
            return false
        }
        process.waitUntilExit()
        return process.terminationReason == .exit && process.terminationStatus == 0
    }

    private func writeBackCredentials(root: [String: Any], fileURL: URL) {
        guard let data = try? JSONSerialization.data(withJSONObject: root) else { return }
        do {
            try data.write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            NSLog("AI Token Meter Claude OAuth: failed to write credentials file: \(error.localizedDescription)")
        }
    }

    // MARK: Fetch

    private func performRequest(_ request: URLRequest) -> (data: Data?, status: Int)? {
        let semaphore = DispatchSemaphore(value: 0)
        let resultLock = NSLock()
        var responseData: Data?
        var statusCode: Int?

        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            guard error == nil, let http = response as? HTTPURLResponse else { return }
            resultLock.lock()
            statusCode = http.statusCode
            responseData = data
            resultLock.unlock()
        }
        task.resume()
        if semaphore.wait(timeout: .now() + 16) == .timedOut {
            task.cancel()
            return nil
        }

        resultLock.lock()
        defer { resultLock.unlock() }
        guard let statusCode else { return nil }
        return (responseData, statusCode)
    }

    private func fetchUsageWindows(token: String, now: Date) -> UsageWindows? {
        var request = URLRequest(url: Self.usageURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let result = performRequest(request) else {
            NSLog("AI Token Meter Claude OAuth usage fetch failed")
            return nil
        }
        guard (200..<300).contains(result.status), let data = result.data else {
            NSLog("AI Token Meter Claude OAuth usage fetch failed with status \(result.status)")
            return nil
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fiveHour = parseUsageWindow(object["five_hour"], now: now),
              let sevenDay = parseUsageWindow(object["seven_day"], now: now) else {
            NSLog("AI Token Meter Claude OAuth usage response missing five_hour/seven_day windows")
            return nil
        }
        return UsageWindows(
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            fableSevenDay: Self.parseFableScopedLimit(object["limits"])
        )
    }

    /// Parses the "Weekly · Fable" entry from Claude's model-scoped limits.
    /// Other scoped model limits are intentionally ignored.
    static func parseFableScopedLimit(_ raw: Any?) -> ClaudeStatuslineWindow? {
        guard let parsed = ClaudeScopedQuotaParser.fableWeeklyLimit(from: raw) else { return nil }
        return ClaudeStatuslineWindow(
            usedPercent: parsed.usedPercent,
            resetsAt: parsed.resetsAt
        )
    }

    private func parseUsageWindow(_ raw: Any?, now: Date) -> ClaudeStatuslineWindow? {
        guard let dict = raw as? [String: Any] else { return nil }
        guard let percent = Self.usageNumber(dict["utilization"]) ?? Self.usageNumber(dict["used_percentage"]),
              percent >= 0 else {
            return nil
        }
        let resetsAt = Self.usageDate(dict["resets_at"])
        return ClaudeStatuslineWindow(usedPercent: min(100, percent), resetsAt: resetsAt)
    }

    private static func usageNumber(_ raw: Any?) -> Double? {
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

    private static func usageDate(_ raw: Any?) -> Date? {
        if let epoch = usageNumber(raw), epoch > 0 {
            return Date(timeIntervalSince1970: epoch)
        }
        guard let string = raw as? String else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}

func combinedLiveLimits(codexReader: LiveRateLimitReader = LiveRateLimitReader(), claudeStore: ClaudeStatuslineStore = ClaudeStatuslineStore()) -> [LiveRateLimit] {
    var limits = codexReader.read()
    let claudeSnapshot = claudeStore.read()
    if let claude = claudeSnapshot?.liveRateLimit,
       !limits.contains(where: { $0.id == claude.id }) {
        limits.append(claude)
    }
    if let fable = claudeSnapshot?.fableLiveRateLimit,
       !limits.contains(where: { $0.id == fable.id }) {
        limits.append(fable)
    }
    return limits.sorted { $0.id < $1.id }
}

func codexTrackedLiveLimits(_ limits: [LiveRateLimit]) -> [LiveRateLimit] {
    limits.filter {
        $0.id != QuotaViewOption.claude.liveLimitID
            && $0.id != claudeFableLiveLimitID
    }
}

struct CodexServiceComponentStatus: Codable {
    let name: String
    let status: String
}

struct CodexServiceIncidentStatus: Codable {
    let name: String
    let status: String
    let message: String
    let createdAt: Date?
    let updatedAt: Date?
}

struct CodexServiceStatusSnapshot: Codable {
    let statusPageUpdatedAt: Date?
    let readAt: Date
    let components: [CodexServiceComponentStatus]
    let incidents: [CodexServiceIncidentStatus]

    var activeIncident: CodexServiceIncidentStatus? { incidents.first }

    var degradedComponents: [CodexServiceComponentStatus] {
        components.filter { $0.status != "operational" }
    }

    var overallStatus: String {
        let statuses = degradedComponents.map(\.status)
        if statuses.contains(where: { $0 == "major_outage" }) { return "major_outage" }
        if statuses.contains(where: { $0 == "partial_outage" }) { return "partial_outage" }
        if statuses.contains(where: { $0 == "under_maintenance" }) { return "under_maintenance" }
        if statuses.contains(where: { $0 == "degraded_performance" }) { return "degraded_performance" }
        return "operational"
    }
}

final class CodexServiceStatusReader {
    private static let codexComponentOrder = [
        "Codex in ChatGPT Desktop",
        "Codex Web",
        "App",
        "Codex API",
        "CLI",
        "VS Code extension"
    ]

    private let summaryURL: URL
    private let componentOrder: [String]
    /// Substrings that mark an incident as relevant; nil accepts all incidents.
    private let incidentKeywords: [String]?
    private let session: URLSession
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(
        summaryURL: URL = URL(string: "https://status.openai.com/api/v2/summary.json")!,
        componentOrder: [String] = CodexServiceStatusReader.codexComponentOrder,
        incidentKeywords: [String]? = ["codex", "cli", "vs code"]
    ) {
        self.summaryURL = summaryURL
        self.componentOrder = componentOrder
        self.incidentKeywords = incidentKeywords
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    /// status.claude.com is a standard Statuspage instance; component names
    /// carry suffixes like "Claude API (api.anthropic.com)", so matching is
    /// by prefix. All incidents on that page are Claude-related.
    static func claude() -> CodexServiceStatusReader {
        CodexServiceStatusReader(
            summaryURL: URL(string: "https://status.claude.com/api/v2/summary.json")!,
            componentOrder: ["Claude Code", "Claude API", "claude.ai", "Claude Console"],
            incidentKeywords: nil
        )
    }

    deinit {
        session.invalidateAndCancel()
    }

    func read(timeout: TimeInterval = 12) -> CodexServiceStatusSnapshot? {
        guard let data = fetch(url: summaryURL, timeout: timeout) else {
            return nil
        }
        return parse(data: data)
    }

    private func fetch(url: URL, timeout: TimeInterval) -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout

        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var responseData: Data?

        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            guard error == nil,
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let data else {
                return
            }
            lock.lock()
            responseData = data
            lock.unlock()
        }
        task.resume()

        let deadline = DispatchTime.now() + timeout + 1
        if semaphore.wait(timeout: deadline) == .timedOut {
            task.cancel()
            return nil
        }

        lock.lock()
        let data = responseData
        lock.unlock()
        return data
    }

    private func parse(data: Data) -> CodexServiceStatusSnapshot? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let components = ((object["components"] as? [[String: Any]]) ?? [])
            .compactMap(parseComponent)
            .sorted { componentSortIndex($0.name) < componentSortIndex($1.name) }

        guard !components.isEmpty else { return nil }

        let allIncidents = ((object["incidents"] as? [[String: Any]]) ?? [])
            .compactMap(parseIncident)
            .sorted { lhs, rhs in
                (lhs.updatedAt ?? lhs.createdAt ?? .distantPast) > (rhs.updatedAt ?? rhs.createdAt ?? .distantPast)
            }

        var incidents = allIncidents.filter(isCodexRelated)
        if incidents.isEmpty,
           !components.filter({ $0.status != "operational" }).isEmpty,
           allIncidents.count == 1 {
            incidents = allIncidents
        }

        let pageUpdatedAt = ((object["page"] as? [String: Any])?["updated_at"] as? String).flatMap(parseDate)

        return CodexServiceStatusSnapshot(
            statusPageUpdatedAt: pageUpdatedAt,
            readAt: Date(),
            components: components,
            incidents: incidents
        )
    }

    private func parseComponent(_ dict: [String: Any]) -> CodexServiceComponentStatus? {
        guard let name = dict["name"] as? String,
              let status = dict["status"] as? String,
              isCodexComponent(name) else {
            return nil
        }
        return CodexServiceComponentStatus(name: name, status: status)
    }

    private func parseIncident(_ dict: [String: Any]) -> CodexServiceIncidentStatus? {
        guard let name = dict["name"] as? String else { return nil }
        let createdAt = (dict["created_at"] as? String).flatMap(parseDate)
        let updatedAt = (dict["updated_at"] as? String).flatMap(parseDate)
        let updates = (dict["incident_updates"] as? [[String: Any]]) ?? []
        let latestUpdate = updates.max { lhs, rhs in
            let left = ((lhs["updated_at"] as? String).flatMap(parseDate))
                ?? ((lhs["created_at"] as? String).flatMap(parseDate))
                ?? .distantPast
            let right = ((rhs["updated_at"] as? String).flatMap(parseDate))
                ?? ((rhs["created_at"] as? String).flatMap(parseDate))
                ?? .distantPast
            return left < right
        }
        let status = (latestUpdate?["status"] as? String) ?? (dict["status"] as? String) ?? "investigating"
        let message = (latestUpdate?["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let latestUpdatedAt = (latestUpdate?["updated_at"] as? String).flatMap(parseDate)
            ?? (latestUpdate?["created_at"] as? String).flatMap(parseDate)

        return CodexServiceIncidentStatus(
            name: name,
            status: status,
            message: message,
            createdAt: createdAt,
            updatedAt: latestUpdatedAt ?? updatedAt
        )
    }

    private func componentSortIndex(_ name: String) -> Int {
        componentOrder.firstIndex { name == $0 || name.hasPrefix($0) } ?? componentOrder.count
    }

    private func isCodexComponent(_ name: String) -> Bool {
        componentOrder.contains { name == $0 || name.hasPrefix($0) }
    }

    private func isCodexRelated(_ incident: CodexServiceIncidentStatus) -> Bool {
        guard let incidentKeywords else { return true }
        let haystack = "\(incident.name)\n\(incident.message)".lowercased()
        return incidentKeywords.contains { haystack.contains($0) }
    }

    private func parseDate(_ value: String) -> Date? {
        if let date = isoFormatter.date(from: value) {
            return date
        }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: value)
    }
}

func localizedCodexStatus(_ status: String) -> String {
    switch status {
    case "operational":
        return t(.codexStatusOperational)
    case "degraded_performance":
        return t(.codexStatusDegraded)
    case "partial_outage":
        return t(.codexStatusPartialOutage)
    case "major_outage":
        return t(.codexStatusMajorOutage)
    case "under_maintenance":
        return t(.codexStatusMaintenance)
    case "investigating":
        return t(.codexStatusInvestigating)
    case "identified":
        return t(.codexStatusDegraded)
    case "monitoring":
        return t(.codexStatusMonitoring)
    case "resolved":
        return t(.codexStatusResolved)
    default:
        return status.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

func codexStatusColor(_ status: String) -> NSColor {
    switch status {
    case "operational":
        return NSColor.systemGreen
    case "degraded_performance", "identified", "monitoring":
        return NSColor.systemOrange
    case "investigating", "partial_outage":
        return NSColor.systemYellow
    case "major_outage":
        return NSColor.systemRed
    case "under_maintenance":
        return NSColor.systemBlue
    case "resolved":
        return NSColor.systemGreen
    default:
        return NSColor.white.withAlphaComponent(0.58)
    }
}
