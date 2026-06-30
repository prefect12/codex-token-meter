import Cocoa
import Foundation
import ServiceManagement
import UserNotifications

// MARK: - Usage Domain Models

struct Usage: Codable {
    var input: Int64 = 0
    var cachedInput: Int64 = 0
    var output: Int64 = 0
    var reasoningOutput: Int64 = 0
    var total: Int64 = 0

    var freshInput: Int64 { max(0, input - cachedInput) }
    var cachePercent: Double { input == 0 ? 0 : Double(cachedInput) / Double(input) * 100 }

    mutating func add(_ other: Usage) {
        input += other.input
        cachedInput += other.cachedInput
        output += other.output
        reasoningOutput += other.reasoningOutput
        total += other.total
    }

    static func delta(from previous: Usage, to current: Usage) -> Usage {
        Usage(
            input: max(0, current.input - previous.input),
            cachedInput: max(0, current.cachedInput - previous.cachedInput),
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

struct DayUsage {
    let day: String
    var usage: Usage
    var turns: Int
    var modelBreakdown: [ModelUsage] = []
}

struct HourUsage {
    let hour: Date
    var usage: Usage
    var turns: Int
}

struct SessionUsage {
    let path: String
    let lastEvent: Date
    var turns: Int
    var usage: Usage
}

struct ModelUsage {
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
}

enum APICostEstimator {
    private static let defaultUnlabeledModelName = "gpt-5.5"

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
        let freshInput = max(Int64(0), totalOnlyInput - cachedInput)
        let value = (
            Double(freshInput) * rate.inputPerMillionUSD
                + Double(cachedInput) * rate.cachedInputPerMillionUSD
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
        return nil
    }
}

struct TokenReport {
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

func mergedTokenReports(_ reports: [TokenReport], scannedAt: Date = Date()) -> TokenReport {
    var merged = TokenReport(scannedAt: scannedAt)
    var dayUsage: [String: Usage] = [:]
    var dayTurns: [String: Int] = [:]
    var dayModels: [String: [String: ModelUsage]] = [:]
    var hourUsage: [Date: Usage] = [:]
    var hourTurns: [Date: Int] = [:]
    var models: [String: ModelUsage] = [:]
    var sessions: [SessionUsage] = []

    for report in reports {
        merged.usage.add(report.usage)
        merged.sessions += report.sessions
        merged.events += report.events
        merged.turns += report.turns
        merged.limitNames.formUnion(report.limitNames)
        sessions.append(contentsOf: report.topSessions)

        for day in report.byDay {
            var usage = dayUsage[day.day] ?? Usage()
            usage.add(day.usage)
            dayUsage[day.day] = usage
            dayTurns[day.day, default: 0] += day.turns
            var bucket = dayModels[day.day] ?? [:]
            for model in day.modelBreakdown {
                var existing = bucket[model.name] ?? ModelUsage(name: model.name, usage: Usage(), events: 0, sessions: 0)
                existing.usage.add(model.usage)
                existing.events += model.events
                existing.sessions += model.sessions
                bucket[model.name] = existing
            }
            dayModels[day.day] = bucket
        }

        for hour in report.byHour {
            var usage = hourUsage[hour.hour] ?? Usage()
            usage.add(hour.usage)
            hourUsage[hour.hour] = usage
            hourTurns[hour.hour, default: 0] += hour.turns
        }

        for model in report.modelBreakdown {
            var existing = models[model.name] ?? ModelUsage(name: model.name, usage: Usage(), events: 0, sessions: 0)
            existing.usage.add(model.usage)
            existing.events += model.events
            existing.sessions += model.sessions
            models[model.name] = existing
        }
    }

    merged.byDay = Set(dayUsage.keys).union(dayTurns.keys)
        .map { day in
            let modelRows = (dayModels[day] ?? [:]).values.sorted { $0.usage.total > $1.usage.total }
            return DayUsage(day: day, usage: dayUsage[day] ?? Usage(), turns: dayTurns[day] ?? 0, modelBreakdown: modelRows)
        }
        .sorted { $0.day < $1.day }
    merged.byHour = Set(hourUsage.keys).union(hourTurns.keys)
        .map { HourUsage(hour: $0, usage: hourUsage[$0] ?? Usage(), turns: hourTurns[$0] ?? 0) }
        .sorted { $0.hour < $1.hour }
    merged.modelBreakdown = models.values.sorted { $0.usage.total > $1.usage.total }
    merged.topSessions = sessions.sorted { $0.usage.total > $1.usage.total }.prefix(8).map { $0 }
    return merged
}

struct RepoInsightDay {
    let day: String
    var conversations: Int
    var turns: Int
    var compressions: Int
}

struct RepoInsightTurnBuckets {
    var short: Int = 0
    var medium: Int = 0
    var long: Int = 0
    var extraLong: Int = 0
}

struct RepoInsightCompressionBuckets {
    var zero: Int = 0
    var one: Int = 0
    var two: Int = 0
    var threePlus: Int = 0
}

struct RepoInsight {
    let key: String
    let displayName: String
    let primaryFolder: String
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

struct RepoInsightsReport {
    var rows: [RepoInsight]
    var scannedAt: Date
    var windowDays: Int
}

struct AccountUsageSummary {
    let lifetimeTokens: Int64?
    let peakDailyTokens: Int64?
    let longestRunningTurnSec: Int64?
    let currentStreakDays: Int64?
    let longestStreakDays: Int64?
}

struct AccountUsageDailyBucket {
    let startDate: String
    let tokens: Int64
}

struct AccountUsageSnapshot {
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
