import Cocoa
import Foundation
import ServiceManagement
import UserNotifications

// MARK: - Usage Domain Models

struct Usage: Codable {
    var input: Int64 = 0
    var cachedInput: Int64 = 0
    var cacheCreationInput: Int64 = 0
    var cacheCreationInput1h: Int64 = 0
    var output: Int64 = 0
    var reasoningOutput: Int64 = 0
    var total: Int64 = 0

    var freshInput: Int64 { max(0, input - cachedInput - cacheCreationInput - cacheCreationInput1h) }
    var cachePercent: Double { input == 0 ? 0 : Double(cachedInput) / Double(input) * 100 }
    var totalCacheCreationInput: Int64 { cacheCreationInput + cacheCreationInput1h }

    init(
        input: Int64 = 0,
        cachedInput: Int64 = 0,
        cacheCreationInput: Int64 = 0,
        cacheCreationInput1h: Int64 = 0,
        output: Int64 = 0,
        reasoningOutput: Int64 = 0,
        total: Int64 = 0
    ) {
        self.input = input
        self.cachedInput = cachedInput
        self.cacheCreationInput = cacheCreationInput
        self.cacheCreationInput1h = cacheCreationInput1h
        self.output = output
        self.reasoningOutput = reasoningOutput
        self.total = total
    }

    private enum CodingKeys: String, CodingKey {
        case input
        case cachedInput
        case cacheCreationInput
        case cacheCreationInput1h
        case output
        case reasoningOutput
        case total
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        input = try container.decodeIfPresent(Int64.self, forKey: .input) ?? 0
        cachedInput = try container.decodeIfPresent(Int64.self, forKey: .cachedInput) ?? 0
        cacheCreationInput = try container.decodeIfPresent(Int64.self, forKey: .cacheCreationInput) ?? 0
        cacheCreationInput1h = try container.decodeIfPresent(Int64.self, forKey: .cacheCreationInput1h) ?? 0
        output = try container.decodeIfPresent(Int64.self, forKey: .output) ?? 0
        reasoningOutput = try container.decodeIfPresent(Int64.self, forKey: .reasoningOutput) ?? 0
        total = try container.decodeIfPresent(Int64.self, forKey: .total) ?? 0
    }

    mutating func add(_ other: Usage) {
        input += other.input
        cachedInput += other.cachedInput
        cacheCreationInput += other.cacheCreationInput
        cacheCreationInput1h += other.cacheCreationInput1h
        output += other.output
        reasoningOutput += other.reasoningOutput
        total += other.total
    }

    static func delta(from previous: Usage, to current: Usage) -> Usage {
        Usage(
            input: max(0, current.input - previous.input),
            cachedInput: max(0, current.cachedInput - previous.cachedInput),
            cacheCreationInput: max(0, current.cacheCreationInput - previous.cacheCreationInput),
            cacheCreationInput1h: max(0, current.cacheCreationInput1h - previous.cacheCreationInput1h),
            output: max(0, current.output - previous.output),
            reasoningOutput: max(0, current.reasoningOutput - previous.reasoningOutput),
            total: max(0, current.total - previous.total)
        )
    }
}

struct TokenEvent: Codable {
    let timestamp: Date
    let usage: Usage
    let limitID: String?
    let limitName: String?
    let model: String?
}

struct DayUsage: Codable {
    let day: String
    var usage: Usage
    var turns: Int
    var modelBreakdown: [ModelUsage] = []
}

struct HourUsage: Codable {
    let hour: Date
    var usage: Usage
    var turns: Int
}

struct SessionUsage: Codable {
    let path: String
    let lastEvent: Date
    var turns: Int
    var usage: Usage
}

struct ModelUsage: Codable {
    let name: String
    var usage: Usage
    var events: Int
    var sessions: Int
}

struct APICostEstimate {
    var usdValue: Double = 0
    var pricedTokens: Int64 = 0
    var totalTokens: Int64 = 0

    var hasUsage: Bool { totalTokens > 0 }
    var hasPricedUsage: Bool { pricedTokens > 0 }
    var coveragePercent: Double {
        guard totalTokens > 0 else { return 0 }
        return Double(pricedTokens) / Double(totalTokens) * 100
    }

    mutating func add(_ other: APICostEstimate) {
        usdValue += other.usdValue
        pricedTokens += other.pricedTokens
        totalTokens += other.totalTokens
    }
}

struct ExternalAPICostSnapshot {
    let usdValue: Double
    let totalTokens: Int64
    let updatedAt: String?
    let sourcePath: String

    var hasData: Bool {
        usdValue > 0 || totalTokens > 0
    }
}

struct APIModelRate {
    let inputPerMillionUSD: Double
    let cachedInputPerMillionUSD: Double
    let outputPerMillionUSD: Double
    var cacheCreationInputPerMillionUSD: Double? = nil
    var cacheCreationInput1hPerMillionUSD: Double? = nil
}

enum APICostEstimator {
    private static let defaultUnlabeledModelName = "gpt-5.6-sol"

    static func estimate(report: TokenReport) -> APICostEstimate {
        var estimate = APICostEstimate()
        if report.modelBreakdown.isEmpty {
            return Self.estimateAsDefaultModel(usage: report.usage)
        }

        var modelTotal: Int64 = 0
        for model in report.modelBreakdown {
            modelTotal += model.usage.total
            estimate.add(Self.estimate(usage: model.usage, modelName: model.name))
        }
        if report.usage.total > modelTotal {
            estimate.add(Self.estimateAsDefaultModel(totalTokens: report.usage.total - modelTotal))
        }
        return estimate
    }

    static func estimate(day: DayUsage) -> APICostEstimate {
        var estimate = APICostEstimate()
        if day.modelBreakdown.isEmpty {
            return Self.estimateAsDefaultModel(usage: day.usage)
        }

        var modelTotal: Int64 = 0
        for model in day.modelBreakdown {
            modelTotal += model.usage.total
            estimate.add(Self.estimate(usage: model.usage, modelName: model.name))
        }
        if day.usage.total > modelTotal {
            estimate.add(Self.estimateAsDefaultModel(totalTokens: day.usage.total - modelTotal))
        }
        return estimate
    }

    static func estimate(usage: Usage, modelName: String) -> APICostEstimate {
        guard let rate = rate(for: modelName) else {
            return APICostEstimate(usdValue: 0, pricedTokens: 0, totalTokens: usage.total)
        }
        let totalOnlyInput = usage.input == 0 && usage.output == 0 && usage.total > 0 ? usage.total : usage.input
        let cachedInput = max(Int64(0), min(usage.cachedInput, totalOnlyInput))
        let cacheCreationInput = max(Int64(0), min(usage.cacheCreationInput, max(0, totalOnlyInput - cachedInput)))
        let cacheCreationInput1h = max(Int64(0), min(usage.cacheCreationInput1h, max(0, totalOnlyInput - cachedInput - cacheCreationInput)))
        let freshInput = max(Int64(0), totalOnlyInput - cachedInput - cacheCreationInput - cacheCreationInput1h)
        let cacheCreationRate = rate.cacheCreationInputPerMillionUSD ?? rate.inputPerMillionUSD
        let cacheCreation1hRate = rate.cacheCreationInput1hPerMillionUSD ?? cacheCreationRate
        let value = (
            Double(freshInput) * rate.inputPerMillionUSD
                + Double(cachedInput) * rate.cachedInputPerMillionUSD
                + Double(cacheCreationInput) * cacheCreationRate
                + Double(cacheCreationInput1h) * cacheCreation1hRate
                + Double(usage.output) * rate.outputPerMillionUSD
        ) / 1_000_000
        return APICostEstimate(usdValue: value, pricedTokens: usage.total, totalTokens: usage.total)
    }

    private static func estimateAsDefaultModel(totalTokens: Int64) -> APICostEstimate {
        guard totalTokens > 0 else { return APICostEstimate() }
        return estimate(
            usage: Usage(input: totalTokens, cachedInput: 0, output: 0, reasoningOutput: 0, total: totalTokens),
            modelName: defaultUnlabeledModelName
        )
    }

    private static func estimateAsDefaultModel(usage: Usage) -> APICostEstimate {
        if usage.input == 0 && usage.output == 0 && usage.total > 0 {
            return estimateAsDefaultModel(totalTokens: usage.total)
        }
        return estimate(usage: usage, modelName: defaultUnlabeledModelName)
    }

    private static func rate(for modelName: String) -> APIModelRate? {
        let name = modelName.lowercased()
        if name.contains("gpt-5.6-luna") || name.contains("gpt-5.6 luna") {
            return APIModelRate(inputPerMillionUSD: 1, cachedInputPerMillionUSD: 0.1, outputPerMillionUSD: 6, cacheCreationInputPerMillionUSD: 1.25)
        }
        if name.contains("gpt-5.6-terra") || name.contains("gpt-5.6 terra") {
            return APIModelRate(inputPerMillionUSD: 2.5, cachedInputPerMillionUSD: 0.25, outputPerMillionUSD: 15, cacheCreationInputPerMillionUSD: 3.125)
        }
        if name.contains("gpt-5.6-sol") || name.contains("gpt-5.6 sol") || name == "gpt-5.6" {
            return APIModelRate(inputPerMillionUSD: 5, cachedInputPerMillionUSD: 0.5, outputPerMillionUSD: 30, cacheCreationInputPerMillionUSD: 6.25)
        }
        if name.contains("gpt-5.5") && name.contains("cyber") {
            return APIModelRate(inputPerMillionUSD: 20, cachedInputPerMillionUSD: 2, outputPerMillionUSD: 120)
        }
        if name.contains("gpt-5.5") {
            return APIModelRate(inputPerMillionUSD: 5, cachedInputPerMillionUSD: 0.5, outputPerMillionUSD: 30)
        }
        if name.contains("gpt-5.4-mini") || name.contains("gpt-5.4 mini") {
            return APIModelRate(inputPerMillionUSD: 0.75, cachedInputPerMillionUSD: 0.075, outputPerMillionUSD: 4.5)
        }
        if name.contains("gpt-5.4") {
            return APIModelRate(inputPerMillionUSD: 2.5, cachedInputPerMillionUSD: 0.25, outputPerMillionUSD: 15)
        }
        if name.contains("gpt-5.3-codex-spark") {
            return APIModelRate(inputPerMillionUSD: 1.75, cachedInputPerMillionUSD: 0.175, outputPerMillionUSD: 14)
        }
        if name.contains("gpt-5.3-codex") || name.contains("gpt-5.2-codex") || name.contains("gpt-5.2") || name.contains("gpt-5-codex") {
            return APIModelRate(inputPerMillionUSD: 1.75, cachedInputPerMillionUSD: 0.175, outputPerMillionUSD: 14)
        }
        if name.contains("claude-fable-5") || name.contains("claude-mythos-5") {
            return APIModelRate(inputPerMillionUSD: 10, cachedInputPerMillionUSD: 1, outputPerMillionUSD: 50, cacheCreationInputPerMillionUSD: 12.5, cacheCreationInput1hPerMillionUSD: 20)
        }
        if name.contains("claude-opus-4-8")
            || name.contains("claude-opus-4-7")
            || name.contains("claude-opus-4-6")
            || name.contains("claude-opus-4-5") {
            return APIModelRate(inputPerMillionUSD: 5, cachedInputPerMillionUSD: 0.5, outputPerMillionUSD: 25, cacheCreationInputPerMillionUSD: 6.25, cacheCreationInput1hPerMillionUSD: 10)
        }
        if name.contains("claude-opus-4-1")
            || name.contains("claude-opus-4") {
            return APIModelRate(inputPerMillionUSD: 15, cachedInputPerMillionUSD: 1.5, outputPerMillionUSD: 75, cacheCreationInputPerMillionUSD: 18.75, cacheCreationInput1hPerMillionUSD: 30)
        }
        if name.contains("claude-sonnet-4-6")
            || name.contains("claude-sonnet-4-5") {
            return APIModelRate(inputPerMillionUSD: 3, cachedInputPerMillionUSD: 0.3, outputPerMillionUSD: 15, cacheCreationInputPerMillionUSD: 3.75, cacheCreationInput1hPerMillionUSD: 6)
        }
        if name.contains("claude-haiku-4-5") {
            return APIModelRate(inputPerMillionUSD: 1, cachedInputPerMillionUSD: 0.1, outputPerMillionUSD: 5, cacheCreationInputPerMillionUSD: 1.25, cacheCreationInput1hPerMillionUSD: 2)
        }
        if name.contains("claude-haiku-3") {
            return APIModelRate(inputPerMillionUSD: 0.25, cachedInputPerMillionUSD: 0.025, outputPerMillionUSD: 1.25, cacheCreationInputPerMillionUSD: 0.3, cacheCreationInput1hPerMillionUSD: 0.5)
        }
        return nil
    }
}

struct TokenReport: Codable {
    var usage = Usage()
    var sessions = 0
    var events = 0
    var turns = 0
    var byDay: [DayUsage] = []
    var byHour: [HourUsage] = []
    var topSessions: [SessionUsage] = []
    var modelBreakdown: [ModelUsage] = []
    var limitNames: Set<String> = []
    var scannedAt = Date()
}

// MARK: - Cross-device usage reporting

struct MachineUsageIdentity: Codable {
    var installationID: String
    var displayName: String
    var hostName: String
    var timeZoneIdentifier: String
    var trackingStartedAt: Date
}

struct MachineDayUsageRecord: Codable {
    var day: String
    var usage: Usage
    var turns: Int
    var modelBreakdown: [ModelUsage]
    var apiEquivalentUSD: Double
    var apiEquivalentPricedTokens: Int64
    var firstObservedAt: Date
    var lastObservedAt: Date
}

struct AccountQuotaWindowObservation: Codable, Equatable {
    var usedPercent: Double
    var windowMinutes: Int
    var resetsAt: Date?
}

struct AccountQuotaLimitObservation: Codable, Equatable {
    var id: String
    var name: String
    var planType: String?
    var primary: AccountQuotaWindowObservation
    var secondary: AccountQuotaWindowObservation
}

struct AccountQuotaObservation: Codable {
    var observedAt: Date
    var limits: [AccountQuotaLimitObservation]
}

struct MachineUsageHistoryFile: Codable {
    var version: Int
    var machine: MachineUsageIdentity
    var updatedAt: Date
    var localCodexByDay: [String: MachineDayUsageRecord]
    var accountQuotaObservations: [AccountQuotaObservation]
    var latestAccountUsage: AccountUsageSnapshot?
}

struct MachineLocalUsageSummary: Codable {
    var usage: Usage
    var turns: Int
    var activeDays: Int
    var firstDay: String?
    var lastDay: String?
    var apiEquivalentUSD: Double
    var apiEquivalentPricedTokens: Int64
}

struct MachineUsageReportSemantics: Codable {
    let accountQuotaScope = "Official account-level quota observed by this installation; it already includes activity from all devices and must not be summed across machines."
    let deviceUsageScope = "Codex tokens found in local rollout logs configured on this installation; compare or sum these rows by installation_id only when logs are not duplicated between machines."
    let apiEquivalentScope = "Estimated API-equivalent value of local tokens; it is not a subscription bill or an official charge."
}

struct MachineLocalUsageExport: Codable {
    var summary: MachineLocalUsageSummary
    var dailyUsage: [MachineDayUsageRecord]
}

struct MachineOfficialAccountExport: Codable {
    var latestQuota: AccountQuotaObservation?
    var quotaObservations: [AccountQuotaObservation]
    var latestProfileUsage: AccountUsageSnapshot?
}

struct MachineUsageExportReport: Codable {
    var schemaVersion: Int
    var exportedAt: Date
    var appVersion: String
    var machine: MachineUsageIdentity
    var semantics: MachineUsageReportSemantics
    var deviceLocalCodex: MachineLocalUsageExport
    var officialAccount: MachineOfficialAccountExport
}

struct RepoInsightDay: Codable {
    let day: String
    var conversations: Int
    var turns: Int
    var compressions: Int
}

struct RepoInsightTurnBuckets: Codable {
    var short: Int = 0
    var medium: Int = 0
    var long: Int = 0
    var extraLong: Int = 0
}

struct RepoInsightCompressionBuckets: Codable {
    var zero: Int = 0
    var one: Int = 0
    var two: Int = 0
    var threePlus: Int = 0
}

struct RepoInsightHour: Codable {
    let hour: Int
    var conversations: Int
    var turns: Int
    var tokens: Int64
}

struct RepoInsight: Codable {
    var key: String
    var displayName: String
    var primaryFolder: String
    var folders: Set<String>
    var conversations: Int
    var turns: Int
    var compressions: Int
    var tokens: Int64
    var conversationsWithCompression: Int
    var longestTurns: Int
    var longestTokens: Int64
    var maxCompressions: Int
    var abortedTurns: Int
    var completedTurns: Int
    var activeDays: Set<String>
    var turnBuckets: RepoInsightTurnBuckets
    var compressionBuckets: RepoInsightCompressionBuckets
    var days: [RepoInsightDay]
    var hours: [RepoInsightHour]

    var averageTurnsPerConversation: Double {
        conversations == 0 ? 0 : Double(turns) / Double(conversations)
    }

    var averageCompressionsPerConversation: Double {
        conversations == 0 ? 0 : Double(compressions) / Double(conversations)
    }

    var compressionConversationRate: Double {
        conversations == 0 ? 0 : Double(conversationsWithCompression) / Double(conversations)
    }

    var risk: RepoInsightRisk {
        if averageCompressionsPerConversation >= 1.0
            || maxCompressions >= 8
            || compressionConversationRate >= 0.45 {
            return .frequentCompression
        }
        if averageCompressionsPerConversation >= 0.35
            || longestTurns >= 40
            || averageTurnsPerConversation >= 12 {
            return .longRunning
        }
        if conversations >= 10
            && averageTurnsPerConversation <= 5
            && averageCompressionsPerConversation < 0.2 {
            return .wellSplit
        }
        return .healthy
    }
}

enum RepoInsightRisk {
    case frequentCompression
    case longRunning
    case wellSplit
    case healthy
}

struct RepoInsightsReport: Codable {
    var rows: [RepoInsight]
    var scannedAt: Date
    var windowDays: Int
}

struct AccountUsageSummary: Codable {
    let lifetimeTokens: Int64?
    let peakDailyTokens: Int64?
    let longestRunningTurnSec: Int64?
    let currentStreakDays: Int64?
    let longestStreakDays: Int64?
}

struct AccountUsageDailyBucket: Codable {
    let startDate: String
    let tokens: Int64
}

struct AccountUsageSnapshot: Codable {
    let summary: AccountUsageSummary
    let dailyUsageBuckets: [AccountUsageDailyBucket]
    let readAt: Date

    var hasData: Bool {
        (summary.lifetimeTokens ?? 0) > 0 || dailyUsageBuckets.contains { $0.tokens > 0 }
    }

    func report(days dayCount: Int, useLifetimeTotal: Bool = false) -> TokenReport {
        let count = max(dayCount, 1)
        let calendar = appCalendar()
        let formatter = dayFormatter()
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -(count - 1), to: today) ?? today
        var byDate: [String: Int64] = [:]
        for bucket in dailyUsageBuckets {
            byDate[String(bucket.startDate.prefix(10)), default: 0] += bucket.tokens
        }
        var report = TokenReport(scannedAt: readAt)
        report.byDay = (0..<count).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: start) ?? start
            let key = formatter.string(from: date)
            let total = byDate[key] ?? 0
            return DayUsage(day: key, usage: Usage(total: total), turns: 0)
        }
        let dailyTotal = report.byDay.reduce(Int64(0)) { $0 + $1.usage.total }
        report.usage.total = useLifetimeTotal ? max(summary.lifetimeTokens ?? 0, dailyTotal) : dailyTotal
        return report
    }

    func report(window: WindowOption) -> TokenReport {
        switch window {
        case .day:
            let todayReport = report(days: 1)
            if todayReport.usage.total > 0 {
                return todayReport
            }
            return latestDayReport() ?? todayReport
        case .week:
            return report(days: 7)
        case .month:
            return report(days: 30)
        }
    }

    private func latestDayReport() -> TokenReport? {
        guard let bucket = dailyUsageBuckets.last(where: { $0.tokens > 0 }) else {
            return nil
        }
        var report = TokenReport(scannedAt: readAt)
        let day = String(bucket.startDate.prefix(10))
        report.usage.total = bucket.tokens
        report.byDay = [DayUsage(day: day, usage: Usage(total: bucket.tokens), turns: 0)]
        return report
    }
}
