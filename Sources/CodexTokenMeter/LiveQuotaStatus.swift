import Cocoa
import Foundation
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
        self == .codex
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
    let primary: RateWindow
    let secondary: RateWindow
    let planType: String?
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
            planType: "official-statusline"
        )
    }
}

final class ClaudeStatuslineStore {
    private static let ttlSeconds: TimeInterval = 6 * 60 * 60
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
        let rateLimits = object["rate_limits"] as? [String: Any]
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
        guard fiveHour != nil || sevenDay != nil else { return nil }
        return ClaudeStatuslineSnapshot(capturedAt: capturedAt, readAt: now, isStale: isStale, fiveHour: fiveHour, sevenDay: sevenDay)
    }

    private func parseWindow(_ raw: Any?, now: Date, windowMinutes: Int) -> ClaudeStatuslineWindow? {
        guard let dict = raw as? [String: Any],
              let percent = cleanPercent(dict["used_percentage"]) else {
            return nil
        }
        var usedPercent = percent
        var resetsAt = finiteDouble(dict["resets_at"]).map { Date(timeIntervalSince1970: $0) }
        if let resetDate = resetsAt, now >= resetDate, windowMinutes > 0 {
            let windowSeconds = TimeInterval(windowMinutes) * 60
            let elapsedWindows = floor(now.timeIntervalSince(resetDate) / windowSeconds) + 1
            resetsAt = resetDate.addingTimeInterval(elapsedWindows * windowSeconds)
            usedPercent = 0
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

func combinedLiveLimits(codexReader: LiveRateLimitReader = LiveRateLimitReader(), claudeStore: ClaudeStatuslineStore = ClaudeStatuslineStore()) -> [LiveRateLimit] {
    var limits = codexReader.read()
    if let claude = claudeStore.read()?.liveRateLimit,
       !limits.contains(where: { $0.id == claude.id }) {
        limits.append(claude)
    }
    return limits
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
    private static let componentOrder = [
        "Codex Web",
        "App",
        "Codex API",
        "CLI",
        "VS Code extension"
    ]

    private let summaryURL = URL(string: "https://status.openai.com/api/v2/summary.json")!
    private let session: URLSession
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
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
        Self.componentOrder.firstIndex(of: name) ?? Self.componentOrder.count
    }

    private func isCodexComponent(_ name: String) -> Bool {
        Self.componentOrder.contains(name)
    }

    private func isCodexRelated(_ incident: CodexServiceIncidentStatus) -> Bool {
        let haystack = "\(incident.name)\n\(incident.message)".lowercased()
        if haystack.contains("codex") || haystack.contains("cli") || haystack.contains("vs code") {
            return true
        }
        return false
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
