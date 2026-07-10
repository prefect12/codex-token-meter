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
                hint: "持续记录本机 Codex Token 与账户级官方额度；导出 JSON 和 CSV 后可与其他电脑对比。",
                exportAction: "导出报告…",
                chooseFolder: "选择报告导出位置"
            )
        case .traditionalChinese:
            return MachineUsageReportCopy(
                title: "跨裝置用量報告",
                hint: "持續記錄本機 Codex Token 與帳戶級官方額度；匯出 JSON 和 CSV 後可與其他電腦比較。",
                exportAction: "匯出報告…",
                chooseFolder: "選擇報告匯出位置"
            )
        case .japanese:
            return MachineUsageReportCopy(
                title: "デバイス別使用量レポート",
                hint: "この Mac の Codex Token とアカウント全体の公式クォータを記録し、JSON/CSV で比較できます。",
                exportAction: "レポートを書き出す…",
                chooseFolder: "書き出し先を選択"
            )
        default:
            return MachineUsageReportCopy(
                title: "Cross-device usage report",
                hint: "Records this Mac's Codex tokens and account-level official quota. Export JSON and CSV to compare computers.",
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

    private let lock = NSLock()
    private var history: MachineUsageHistoryFile

    private init() {
        history = Self.load() ?? Self.newHistory()
    }

    func record(localCodexReport: TokenReport?, accountUsage: AccountUsageSnapshot?, liveLimits: [LiveRateLimit]) {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
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
        }

        if let accountUsage {
            history.latestAccountUsage = accountUsage
        }
        if !liveLimits.isEmpty {
            let observation = AccountQuotaObservation(
                observedAt: now,
                limits: liveLimits.map(Self.quotaLimit).sorted { $0.id < $1.id }
            )
            if shouldAppend(observation) {
                history.accountQuotaObservations.append(observation)
                // At most about five weeks of 5-minute samples, plus immediate change samples.
                history.accountQuotaObservations = Array(history.accountQuotaObservations.suffix(12_000))
            }
        }
        history.updatedAt = now
        persist()
    }

    func export(to directory: URL, appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development") throws -> URL {
        lock.lock()
        defer { lock.unlock() }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
        try encoder.encode(report).write(to: directory.appendingPathComponent("machine-usage-report.json"), options: .atomic)
        try Self.dailyCSV(days: days, machine: history.machine).data(using: .utf8)?.write(to: directory.appendingPathComponent("local-codex-daily.csv"), options: .atomic)
        try Self.quotaCSV(history.accountQuotaObservations, machine: history.machine).data(using: .utf8)?.write(to: directory.appendingPathComponent("official-account-quota-observations.csv"), options: .atomic)
        try Self.readme(for: report).data(using: .utf8)?.write(to: directory.appendingPathComponent("README.md"), options: .atomic)
        return directory
    }

    private func shouldAppend(_ candidate: AccountQuotaObservation) -> Bool {
        guard let last = history.accountQuotaObservations.last else { return true }
        guard candidate.observedAt.timeIntervalSince(last.observedAt) < 5 * 60 else { return true }
        return candidate.limits != last.limits
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
            primary: AccountQuotaWindowObservation(usedPercent: limit.primary.usedPercent, windowMinutes: limit.primary.windowMinutes, resetsAt: limit.primary.resetsAt),
            secondary: AccountQuotaWindowObservation(usedPercent: limit.secondary.usedPercent, windowMinutes: limit.secondary.windowMinutes, resetsAt: limit.secondary.resetsAt)
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
                for (name, window) in [("primary", limit.primary), ("secondary", limit.secondary)] {
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
