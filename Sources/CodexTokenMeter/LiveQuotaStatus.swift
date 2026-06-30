import Cocoa
import Foundation
import ServiceManagement
import UserNotifications

// MARK: - Live Quota And Service Status

enum QuotaViewOption: String, CaseIterable {
    case all
    case codex
    case other
    case spark
    case claude

    static var allCases: [QuotaViewOption] {
        [.all, .codex, .claude, .other, .spark]
    }

    static func option(from rawValue: String) -> QuotaViewOption? {
        switch rawValue {
        case "all":
            return .all
        case "codex":
            return .codex
        case "claude":
            return .claude
        case "other":
            return .codex
        case "spark":
            return .claude
        default:
            return nil
        }
    }

    static var visibleCases: [QuotaViewOption] {
        [.all, .codex, .claude]
    }

    var scanLimitID: String? {
        switch self {
        case .all, .codex, .other, .claude: return nil
        case .spark: return AppSettings.modelLimitID
        }
    }

    var excludedScanLimitID: String? {
        switch self {
        case .all, .codex, .spark, .claude: return nil
        case .other: return AppSettings.modelLimitID
        }
    }

    var includedModelName: String? {
        switch self {
        case .spark: return AppSettings.modelLimitName.lowercased()
        case .all, .codex, .other, .claude: return nil
        }
    }

    var excludedModelName: String? {
        switch self {
        case .other: return AppSettings.modelLimitName.lowercased()
        case .all, .codex, .spark, .claude: return nil
        }
    }

    var liveLimitID: String {
        switch self {
        case .all, .codex, .other: return "codex"
        case .spark: return AppSettings.modelLimitID
        case .claude: return "claude"
        }
    }

    var shortTitle: String {
        switch self {
        case .all: return t(.all)
        case .codex: return "Codex"
        case .spark: return AppSettings.modelLimitSegmentTitle
        case .other: return t(.other)
        case .claude: return "Claude"
        }
    }

    var fallbackTitle: String {
        switch self {
        case .all: return "Codex + Claude"
        case .codex: return t(.codexAppTotal)
        case .spark: return AppSettings.modelLimitName
        case .other: return t(.nonSparkUsage)
        case .claude: return "Claude Code"
        }
    }

    var outputName: String {
        switch self {
        case .all: return "all"
        case .codex: return "codex"
        case .other: return "other"
        case .spark: return "spark"
        case .claude: return "claude"
        }
    }

    var usesCodexProfileAPI: Bool {
        self == .codex
    }
}

struct RateWindow {
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

struct LiveRateLimit {
    let id: String
    let name: String
    let primary: RateWindow
    let secondary: RateWindow
    let planType: String?
}

struct CodexServiceComponentStatus {
    let name: String
    let status: String
}

struct CodexServiceIncidentStatus {
    let name: String
    let status: String
    let message: String
    let createdAt: Date?
    let updatedAt: Date?
}

struct CodexServiceStatusSnapshot {
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
