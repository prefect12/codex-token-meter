import Foundation

// MARK: - Details Snapshot Cache

enum DetailsSnapshotCacheStore {
    private static let version = 3

    private struct Payload: Codable {
        let version: Int
        let writtenAt: Date
        let snapshot: DetailsSnapshot
    }

    static func read() -> DetailsSnapshot? {
        let url = AppSettings.detailsSnapshotCacheURL
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.version == version else {
            return nil
        }
        return sanitized(payload.snapshot)
    }

    static func isFresh(maxAge: TimeInterval, now: Date = Date()) -> Bool {
        let url = AppSettings.detailsSnapshotCacheURL
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.version == version else {
            return false
        }
        return now.timeIntervalSince(payload.writtenAt) <= maxAge
    }

    static func write(_ snapshot: DetailsSnapshot) {
        let payload = Payload(version: version, writtenAt: Date(), snapshot: sanitized(snapshot))
        do {
            try FileManager.default.createDirectory(at: AppSettings.appSupportDirectoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            try data.write(to: AppSettings.detailsSnapshotCacheURL, options: .atomic)
        } catch {
            NSLog("AI Token Meter details snapshot cache write failed: \(error.localizedDescription)")
        }
    }

    static func remove() {
        try? FileManager.default.removeItem(at: AppSettings.detailsSnapshotCacheURL)
    }

    private static func sanitized(_ snapshot: DetailsSnapshot) -> DetailsSnapshot {
        DetailsSnapshot(
            all: sanitized(snapshot.all),
            codex: sanitized(snapshot.codex),
            claude: sanitized(snapshot.claude),
            repoInsights: sanitized(snapshot.repoInsights),
            repoInsightReports: sanitize(snapshot.repoInsightReports),
            codexRepoInsights: sanitized(snapshot.codexRepoInsights),
            codexRepoInsightReports: sanitize(snapshot.codexRepoInsightReports),
            claudeRepoInsights: sanitized(snapshot.claudeRepoInsights),
            claudeRepoInsightReports: sanitize(snapshot.claudeRepoInsightReports),
            liveLimits: snapshot.liveLimits,
            serviceStatus: snapshot.serviceStatus,
            costReferenceReport: snapshot.costReferenceReport.map(sanitized),
            accountUsage: snapshot.accountUsage,
            resetCredits: snapshot.resetCredits
        )
    }

    private static func sanitized(_ report: TokenReport) -> TokenReport {
        var sanitized = report
        sanitized.topSessions = []
        return sanitized
    }

    private static func sanitize(_ reports: [Int: RepoInsightsReport]) -> [Int: RepoInsightsReport] {
        reports.mapValues(sanitized)
    }

    private static func sanitized(_ report: RepoInsightsReport) -> RepoInsightsReport {
        RepoInsightsReport(
            rows: report.rows.map(sanitized),
            scannedAt: report.scannedAt,
            windowDays: report.windowDays
        )
    }

    private static func sanitized(_ row: RepoInsight) -> RepoInsight {
        var sanitized = row
        let displayName = sanitizedRepoDisplayName(row.displayName)
        sanitized.key = displayName
        sanitized.displayName = displayName
        sanitized.primaryFolder = displayName
        sanitized.folders = []
        return sanitized
    }

    private static func sanitizedRepoDisplayName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return value }
        let separators = CharacterSet(charactersIn: "/\\")
        let parts = trimmed
            .trimmingCharacters(in: separators)
            .components(separatedBy: separators)
            .filter { !$0.isEmpty && $0 != "~" && $0 != "." }
        return parts.last ?? trimmed
    }
}
