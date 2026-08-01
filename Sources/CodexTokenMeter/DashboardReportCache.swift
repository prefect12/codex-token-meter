import Foundation

// MARK: - Dashboard Report Cache

enum DashboardReportCacheStore {
    // Version 3 invalidates reports written before per-day events and
    // per-model turn counts were persisted.
    private static let version = 3

    private struct Entry: Codable {
        let windowHours: Int
        let quota: String
        let report: TokenReport
    }

    private struct Payload: Codable {
        let version: Int
        let writtenAt: Date
        let entries: [Entry]
    }

    static func read() -> [ReportCacheKey: TokenReport] {
        let url = AppSettings.dashboardReportCacheURL
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.version == version else {
            return [:]
        }
        var cache: [ReportCacheKey: TokenReport] = [:]
        for entry in payload.entries {
            guard let window = WindowOption(rawValue: entry.windowHours),
                  let quota = QuotaViewOption.option(from: entry.quota) else {
                continue
            }
            cache[ReportCacheKey(window: window, quota: quota)] = sanitized(entry.report)
        }
        return cache
    }

    static func write(_ cache: [ReportCacheKey: TokenReport]) {
        let entries = cache
            .filter { !$0.value.byDay.isEmpty || !$0.value.byHour.isEmpty || $0.value.usage.total > 0 }
            .map { key, report in
                Entry(windowHours: key.window.rawValue, quota: key.quota.rawValue, report: sanitized(report))
            }
            .sorted {
                if $0.windowHours != $1.windowHours {
                    return $0.windowHours < $1.windowHours
                }
                return $0.quota < $1.quota
            }
        guard !entries.isEmpty else {
            try? FileManager.default.removeItem(at: AppSettings.dashboardReportCacheURL)
            return
        }
        let payload = Payload(version: version, writtenAt: Date(), entries: entries)
        do {
            try FileManager.default.createDirectory(at: AppSettings.appSupportDirectoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            try data.write(to: AppSettings.dashboardReportCacheURL, options: .atomic)
        } catch {
            NSLog("AI Token Meter dashboard cache write failed: \(error.localizedDescription)")
        }
    }

    private static func sanitized(_ report: TokenReport) -> TokenReport {
        var sanitized = report
        sanitized.topSessions = []
        return sanitized
    }
}
