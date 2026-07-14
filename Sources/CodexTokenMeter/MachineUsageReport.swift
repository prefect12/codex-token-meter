import Foundation

struct MachineUsageReportCopy {
    let title: String
    let hint: String
    let exportAction: String
    let chooseFolder: String
}

extension AppLanguage {
    var machineUsageReportCopy: MachineUsageReportCopy {
        switch self {
        case .chinese:
            return MachineUsageReportCopy(
                title: "跨设备用量报告",
                hint: "持续记录本机 Codex Token 与账户级官方额度；导出为一个 ZIP 压缩包，可与其他电脑对比。",
                exportAction: "导出报告…",
                chooseFolder: "选择报告导出位置"
            )
        case .traditionalChinese:
            return MachineUsageReportCopy(
                title: "跨裝置用量報告",
                hint: "持續記錄本機 Codex Token 與帳戶級官方額度；匯出為一個 ZIP 壓縮檔，可與其他電腦比較。",
                exportAction: "匯出報告…",
                chooseFolder: "選擇報告匯出位置"
            )
        case .japanese:
            return MachineUsageReportCopy(
                title: "デバイス別使用量レポート",
                hint: "この Mac の Codex Token とアカウント全体の公式クォータを記録し、1 つの ZIP に書き出して比較できます。",
                exportAction: "レポートを書き出す…",
                chooseFolder: "書き出し先を選択"
            )
        default:
            return MachineUsageReportCopy(
                title: "Cross-device usage report",
                hint: "Records this Mac's Codex tokens and account-level official quota. Export one ZIP package to compare computers.",
                exportAction: "Export report…",
                chooseFolder: "Choose an export location"
            )
        }
    }
}

/// Persists only aggregate, machine-local usage and official quota observations.
/// It deliberately never stores session paths, rollout contents, account credentials, or prompts.
final class MachineUsageReportStore {
    static let shared = MachineUsageReportStore()
    private static let quotaRetention: TimeInterval = 35 * 24 * 60 * 60
    private static let detailedQuotaRetention: TimeInterval = 24 * 60 * 60
    private static let quotaSampleInterval: TimeInterval = 5 * 60
    private static let historicalQuotaSampleInterval: TimeInterval = 60 * 60

    private let lock = NSLock()
    private var history: MachineUsageHistoryFile

    private init() {
        history = Self.load() ?? Self.newHistory()
        let compacted = Self.compactedQuotaObservations(history.accountQuotaObservations)
        if compacted.count != history.accountQuotaObservations.count {
            history.accountQuotaObservations = compacted
            history.updatedAt = Date()
            persist()
        }
    }

    func record(localCodexReport: TokenReport?, accountUsage: AccountUsageSnapshot?, liveLimits: [LiveRateLimit]) {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        var didChange = false
        if let localCodexReport {
            for day in localCodexReport.byDay where day.usage.total > 0 {
                let estimate = APICostEstimator.estimate(day: day)
                let firstObserved = history.localCodexByDay[day.day]?.firstObservedAt ?? now
                history.localCodexByDay[day.day] = MachineDayUsageRecord(
                    day: day.day,
                    usage: day.usage,
                    turns: day.turns,
                    modelBreakdown: day.modelBreakdown,
                    apiEquivalentUSD: estimate.usdValue,
                    apiEquivalentPricedTokens: estimate.pricedTokens,
                    firstObservedAt: firstObserved,
                    lastObservedAt: now
                )
            }
            didChange = true
        }

        if let accountUsage {
            history.latestAccountUsage = accountUsage
            didChange = true
        }
        if !liveLimits.isEmpty {
            let observation = AccountQuotaObservation(
                observedAt: now,
                limits: liveLimits.map(Self.quotaLimit).sorted { $0.id < $1.id }
            )
            if shouldAppend(observation) {
                history.accountQuotaObservations.append(observation)
                history.accountQuotaObservations = Self.compactedQuotaObservations(history.accountQuotaObservations, now: now)
                didChange = true
            }
        }
        guard didChange else { return }
        history.updatedAt = now
        persist()
    }

    func exportArchive(to archiveURL: URL, appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development") throws -> URL {
        lock.lock()
        defer { lock.unlock() }

        guard archiveURL.pathExtension.lowercased() == "zip" else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let fileManager = FileManager.default
        let parent = archiveURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let stagingDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(archiveURL.deletingPathExtension().lastPathComponent, isDirectory: true)
        defer { try? fileManager.removeItem(at: stagingDirectory) }
        if fileManager.fileExists(atPath: stagingDirectory.path) {
            try fileManager.removeItem(at: stagingDirectory)
        }
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: archiveURL.path) {
            try fileManager.removeItem(at: archiveURL)
        }

        let days = history.localCodexByDay.values.sorted { $0.day < $1.day }
        let summary = Self.summary(days: days)
        let report = MachineUsageExportReport(
            schemaVersion: 1,
            exportedAt: Date(),
            appVersion: appVersion,
            machine: history.machine,
            semantics: MachineUsageReportSemantics(),
            deviceLocalCodex: MachineLocalUsageExport(summary: summary, dailyUsage: days),
            officialAccount: MachineOfficialAccountExport(
                latestQuota: history.accountQuotaObservations.last,
                quotaObservations: history.accountQuotaObservations,
                latestProfileUsage: history.latestAccountUsage
            )
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: stagingDirectory.appendingPathComponent("machine-usage-report.json"), options: .atomic)
        try Self.dailyCSV(days: days, machine: history.machine).data(using: .utf8)?.write(to: stagingDirectory.appendingPathComponent("local-codex-daily.csv"), options: .atomic)
        try Self.quotaCSV(history.accountQuotaObservations, machine: history.machine).data(using: .utf8)?.write(to: stagingDirectory.appendingPathComponent("official-account-quota-observations.csv"), options: .atomic)
        try Self.readme(for: report).data(using: .utf8)?.write(to: stagingDirectory.appendingPathComponent("README.md"), options: .atomic)
        let zipper = Process()
        zipper.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipper.currentDirectoryURL = stagingDirectory
        zipper.arguments = ["-q", "-r", archiveURL.path, ".", "-x", "*/._*", "__MACOSX/*"]
        try zipper.run()
        zipper.waitUntilExit()
        guard zipper.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
        return archiveURL
    }

    private func shouldAppend(_ candidate: AccountQuotaObservation) -> Bool {
        guard let last = history.accountQuotaObservations.last else { return true }
        guard candidate.observedAt.timeIntervalSince(last.observedAt) < Self.quotaSampleInterval else { return true }
        return Self.quotaWindowIdentity(candidate.limits) != Self.quotaWindowIdentity(last.limits)
    }

    private static func quotaWindowIdentity(_ limits: [AccountQuotaLimitObservation]) -> [String] {
        limits.sorted { $0.id < $1.id }.map { limit in
            let primary = limit.primary.map { String($0.windowMinutes) } ?? "-"
            let secondary = limit.secondary.map { String($0.windowMinutes) } ?? "-"
            return "\(limit.id)|\(limit.planType ?? "")|\(primary)|\(secondary)"
        }
    }

    private static func compactedQuotaObservations(
        _ observations: [AccountQuotaObservation],
        now: Date = Date()
    ) -> [AccountQuotaObservation] {
        let oldest = now.addingTimeInterval(-quotaRetention)
        let detailedCutoff = now.addingTimeInterval(-detailedQuotaRetention)
        var buckets: [String: AccountQuotaObservation] = [:]
        for observation in observations where observation.observedAt >= oldest {
            let interval = observation.observedAt >= detailedCutoff
                ? quotaSampleInterval
                : historicalQuotaSampleInterval
            let bucket = Int(observation.observedAt.timeIntervalSince1970 / interval)
            let key = "\(Int(interval))|\(bucket)"
            if let existing = buckets[key], existing.observedAt >= observation.observedAt {
                continue
            }
            buckets[key] = observation
        }
        return buckets.values.sorted { $0.observedAt < $1.observedAt }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: AppSettings.appSupportDirectoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(history).write(to: AppSettings.machineUsageHistoryURL, options: .atomic)
        } catch {
            NSLog("AI Token Meter machine usage history write failed: \(error.localizedDescription)")
        }
    }

    private static func load() -> MachineUsageHistoryFile? {
        guard let data = try? Data(contentsOf: AppSettings.machineUsageHistoryURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(MachineUsageHistoryFile.self, from: data)
    }

    private static func newHistory() -> MachineUsageHistoryFile {
        let now = Date()
        let host = ProcessInfo.processInfo.hostName
        let name = Host.current().localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return MachineUsageHistoryFile(
            version: 1,
            machine: MachineUsageIdentity(
                installationID: AppSettings.machineUsageInstallationID,
                displayName: name?.isEmpty == false ? name! : host,
                hostName: host,
                timeZoneIdentifier: appTimeZone().identifier,
                trackingStartedAt: now
            ),
            updatedAt: now,
            localCodexByDay: [:],
            accountQuotaObservations: [],
            latestAccountUsage: nil
        )
    }

    private static func quotaLimit(_ limit: LiveRateLimit) -> AccountQuotaLimitObservation {
        AccountQuotaLimitObservation(
            id: limit.id,
            name: limit.name,
            planType: limit.planType,
            primary: limit.primary.map { AccountQuotaWindowObservation(usedPercent: $0.usedPercent, windowMinutes: $0.windowMinutes, resetsAt: $0.resetsAt) },
            secondary: limit.secondary.map { AccountQuotaWindowObservation(usedPercent: $0.usedPercent, windowMinutes: $0.windowMinutes, resetsAt: $0.resetsAt) }
        )
    }

    private static func summary(days: [MachineDayUsageRecord]) -> MachineLocalUsageSummary {
        var usage = Usage()
        var turns = 0
        var value = 0.0
        var pricedTokens: Int64 = 0
        for day in days {
            usage.add(day.usage)
            turns += day.turns
            value += day.apiEquivalentUSD
            pricedTokens += day.apiEquivalentPricedTokens
        }
        return MachineLocalUsageSummary(
            usage: usage,
            turns: turns,
            activeDays: days.count,
            firstDay: days.first?.day,
            lastDay: days.last?.day,
            apiEquivalentUSD: value,
            apiEquivalentPricedTokens: pricedTokens
        )
    }

    private static func dailyCSV(days: [MachineDayUsageRecord], machine: MachineUsageIdentity) -> String {
        var rows = ["installation_id,machine_name,day,input,cached_input,cache_creation_input,cache_creation_input_1h,output,reasoning_output,total,turns,api_equivalent_usd,api_equivalent_priced_tokens,first_observed_at,last_observed_at"]
        let date = ISO8601DateFormatter()
        for day in days {
            rows.append([
                machine.installationID, machine.displayName, day.day, String(day.usage.input), String(day.usage.cachedInput), String(day.usage.cacheCreationInput), String(day.usage.cacheCreationInput1h), String(day.usage.output), String(day.usage.reasoningOutput), String(day.usage.total), String(day.turns), String(format: "%.6f", day.apiEquivalentUSD), String(day.apiEquivalentPricedTokens), date.string(from: day.firstObservedAt), date.string(from: day.lastObservedAt)
            ].map(csv).joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    private static func quotaCSV(_ observations: [AccountQuotaObservation], machine: MachineUsageIdentity) -> String {
        var rows = ["installation_id,machine_name,observed_at,limit_id,limit_name,plan_type,window,used_percent,window_minutes,resets_at"]
        let date = ISO8601DateFormatter()
        for observation in observations {
            for limit in observation.limits {
                let windows: [(String, AccountQuotaWindowObservation)] = [
                    limit.primary.map { ("primary", $0) },
                    limit.secondary.map { ("secondary", $0) }
                ].compactMap { $0 }
                for (name, window) in windows {
                    rows.append([machine.installationID, machine.displayName, date.string(from: observation.observedAt), limit.id, limit.name, limit.planType ?? "", name, String(format: "%.4f", window.usedPercent), String(window.windowMinutes), window.resetsAt.map(date.string) ?? ""].map(csv).joined(separator: ","))
                }
            }
        }
        return rows.joined(separator: "\n") + "\n"
    }

    private static func readme(for report: MachineUsageExportReport) -> String {
        """
        # AI Token Meter cross-device usage export

        - Installation ID: `\(report.machine.installationID)`
        - Machine: \(report.machine.displayName)
        - Exported: \(ISO8601DateFormatter().string(from: report.exportedAt))

        ## Files

        - `machine-usage-report.json`: full, merge-ready report and definitions.
        - `local-codex-daily.csv`: only Codex tokens observed in this installation's configured local logs.
        - `official-account-quota-observations.csv`: official subscription quota observations made by this installation.

        ## Important accounting boundary

        The official quota percentage is account-level and already includes activity from every computer. Do **not** sum quota percentages from multiple exports. To compare computers, group `local-codex-daily.csv` by `installation_id` from the JSON report; only sum local rows when their logs are not duplicated across machines.
        """ + "\n"
    }

    private static func csv(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
