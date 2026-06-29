import Cocoa
import Foundation
import ServiceManagement
import UserNotifications

// MARK: - Cost History And Estimation

struct CostHistoryWeekSnapshot: Codable {
    var limitID: String
    var limitName: String
    var weekStart: String
    var maxUsedPercent: Double
    var lastUsedPercent: Double
    var lastRemainingPercent: Double
    var observedCount: Int
    var firstSeenAt: String
    var updatedAt: String
    var resetAt: String?
}

struct CostHistoryEvent: Codable {
    var type: String
    var limitID: String
    var weekStart: String
    var previousUsedPercent: Double
    var currentUsedPercent: Double
    var observedAt: String
    var note: String
}

struct CostHistoryFile: Codable {
    var version: Int = 1
    var updatedAt: String?
    var weeks: [String: CostHistoryWeekSnapshot] = [:]
    var events: [CostHistoryEvent] = []
}

final class CostHistoryStore {
    static let shared = CostHistoryStore(url: AppSettings.costHistoryURL)

    private static let resetDropThreshold = 1.0
    private static let resetLowWatermark = 0.5

    private let url: URL
    private var file: CostHistoryFile
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(CostHistoryFile.self, from: data) {
            self.file = decoded
        } else {
            self.file = CostHistoryFile()
        }
    }

    func maxUsedPercent(limitID: String, weekStart: Date) -> Double? {
        let key = snapshotKey(limitID: limitID, weekStart: weekStart)
        return file.weeks[key]?.maxUsedPercent
    }

    func resetCycleCount(limitID: String, weekStart: Date) -> Int {
        resetEvents(limitID: limitID, weekStart: weekStart).count
    }

    func resetBaseUsedPercent(limitID: String, weekStart: Date) -> Double? {
        let explicitEvents = resetEvents(limitID: limitID, weekStart: weekStart)
        if let first = explicitEvents.first {
            return first.previousUsedPercent
        }
        return nil
    }

    func resetEvents(limitID: String, weekStart: Date) -> [CostHistoryEvent] {
        let weekStartText = dayFormatter().string(from: weekStart)
        return file.events
            .filter {
                $0.type == "weekly_usage_percent_drop"
                    && $0.limitID == limitID
                    && $0.weekStart == weekStartText
            }
            .sorted {
                eventDate($0) ?? .distantPast < eventDate($1) ?? .distantPast
            }
    }

    func record(limits: [LiveRateLimit], observedAt: Date = Date()) {
        guard !limits.isEmpty else { return }
        var changed = false
        let observedAtText = isoFormatter.string(from: observedAt)
        for limit in limits {
            let weekStart = appCalendar().dateInterval(of: .weekOfYear, for: observedAt)?.start ?? appCalendar().startOfDay(for: observedAt)
            let key = snapshotKey(limitID: limit.id, weekStart: weekStart)
            let usedPercent = max(0, min(100, limit.secondary.usedPercent))
            let remainingPercent = max(0, min(100, limit.secondary.remainingPercent))
            let resetAtText = limit.secondary.resetsAt.map { isoFormatter.string(from: $0) }

            if var snapshot = file.weeks[key] {
                if Self.isResetDrop(previousUsedPercent: snapshot.lastUsedPercent, currentUsedPercent: usedPercent) {
                    file.events.append(CostHistoryEvent(
                        type: "weekly_usage_percent_drop",
                        limitID: limit.id,
                        weekStart: snapshot.weekStart,
                        previousUsedPercent: snapshot.lastUsedPercent,
                        currentUsedPercent: usedPercent,
                        observedAt: observedAtText,
                        note: "OpenAI live quota usage dropped; treating this as a reset/refresh observation."
                    ))
                }
                snapshot.limitName = limit.name
                snapshot.maxUsedPercent = max(snapshot.maxUsedPercent, usedPercent)
                snapshot.lastUsedPercent = usedPercent
                snapshot.lastRemainingPercent = remainingPercent
                snapshot.observedCount += 1
                snapshot.updatedAt = observedAtText
                snapshot.resetAt = resetAtText
                file.weeks[key] = snapshot
                changed = true
            } else {
                file.weeks[key] = CostHistoryWeekSnapshot(
                    limitID: limit.id,
                    limitName: limit.name,
                    weekStart: dayFormatter().string(from: weekStart),
                    maxUsedPercent: usedPercent,
                    lastUsedPercent: usedPercent,
                    lastRemainingPercent: remainingPercent,
                    observedCount: 1,
                    firstSeenAt: observedAtText,
                    updatedAt: observedAtText,
                    resetAt: resetAtText
                )
                changed = true
            }
        }
        if changed {
            file.updatedAt = observedAtText
            file.events = Array(file.events.suffix(200))
            save()
        }
    }

    private func snapshotKey(limitID: String, weekStart: Date) -> String {
        "\(limitID)|\(dayFormatter().string(from: weekStart))"
    }

    private static func isResetDrop(previousUsedPercent: Double, currentUsedPercent: Double) -> Bool {
        let drop = previousUsedPercent - currentUsedPercent
        guard drop >= resetDropThreshold else { return false }
        return currentUsedPercent <= resetLowWatermark
    }

    private func eventDate(_ event: CostHistoryEvent) -> Date? {
        isoFormatter.date(from: event.observedAt)
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.prettySorted.encode(file)
            try data.write(to: url, options: [.atomic])
        } catch {
            NSLog("AI Token Meter failed to save cost history: \(error)")
        }
    }
}

extension JSONEncoder {
    static var prettySorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

func costEstimateLimit(from limits: [LiveRateLimit]) -> LiveRateLimit? {
    limits.first { $0.id == QuotaViewOption.codex.liveLimitID }
}

func mergedTokenReport(_ reports: [TokenReport], scannedAt: Date = Date()) -> TokenReport {
    var merged = TokenReport(scannedAt: scannedAt)
    var dayBuckets: [String: DayUsage] = [:]
    var hourBuckets: [Date: HourUsage] = [:]
    var modelBuckets: [String: ModelUsage] = [:]
    var sessions: [SessionUsage] = []

    for report in reports {
        merged.usage.add(report.usage)
        merged.sessions += report.sessions
        merged.events += report.events
        merged.turns += report.turns
        merged.limitNames.formUnion(report.limitNames)
        sessions.append(contentsOf: report.topSessions)

        for day in report.byDay {
            var existing = dayBuckets[day.day] ?? DayUsage(day: day.day, usage: Usage(), turns: 0, modelBreakdown: [])
            existing.usage.add(day.usage)
            existing.turns += day.turns
            existing.modelBreakdown = mergedModelBreakdown(existing.modelBreakdown + day.modelBreakdown)
            dayBuckets[day.day] = existing
        }

        for hour in report.byHour {
            var existing = hourBuckets[hour.hour] ?? HourUsage(hour: hour.hour, usage: Usage(), turns: 0)
            existing.usage.add(hour.usage)
            existing.turns += hour.turns
            hourBuckets[hour.hour] = existing
        }

        for model in report.modelBreakdown {
            var existing = modelBuckets[model.name] ?? ModelUsage(name: model.name, usage: Usage(), events: 0, sessions: 0)
            existing.usage.add(model.usage)
            existing.events += model.events
            existing.sessions += model.sessions
            modelBuckets[model.name] = existing
        }
    }

    merged.byDay = dayBuckets.values.sorted { $0.day < $1.day }
    merged.byHour = hourBuckets.values.sorted { $0.hour < $1.hour }
    merged.modelBreakdown = modelBuckets.values.sorted { $0.usage.total > $1.usage.total }
    merged.topSessions = sessions.sorted { $0.usage.total > $1.usage.total }.prefix(8).map { $0 }
    return merged
}

private func mergedModelBreakdown(_ models: [ModelUsage]) -> [ModelUsage] {
    var buckets: [String: ModelUsage] = [:]
    for model in models {
        var existing = buckets[model.name] ?? ModelUsage(name: model.name, usage: Usage(), events: 0, sessions: 0)
        existing.usage.add(model.usage)
        existing.events += model.events
        existing.sessions += model.sessions
        buckets[model.name] = existing
    }
    return buckets.values.sorted { $0.usage.total > $1.usage.total }
}

func mergedRepoInsightsReport(_ reports: [RepoInsightsReport], scannedAt: Date = Date(), windowDays: Int) -> RepoInsightsReport {
    var buckets: [String: RepoInsight] = [:]
    for report in reports {
        for row in report.rows {
            if var existing = buckets[row.key] {
                existing.folders.formUnion(row.folders)
                existing.conversations += row.conversations
                existing.turns += row.turns
                existing.compressions += row.compressions
                existing.tokens += row.tokens
                existing.conversationsWithCompression += row.conversationsWithCompression
                existing.longestTurns = max(existing.longestTurns, row.longestTurns)
                existing.longestTokens = max(existing.longestTokens, row.longestTokens)
                existing.maxCompressions = max(existing.maxCompressions, row.maxCompressions)
                existing.abortedTurns += row.abortedTurns
                existing.completedTurns += row.completedTurns
                existing.activeDays.formUnion(row.activeDays)
                existing.turnBuckets.short += row.turnBuckets.short
                existing.turnBuckets.medium += row.turnBuckets.medium
                existing.turnBuckets.long += row.turnBuckets.long
                existing.turnBuckets.extraLong += row.turnBuckets.extraLong
                existing.compressionBuckets.zero += row.compressionBuckets.zero
                existing.compressionBuckets.one += row.compressionBuckets.one
                existing.compressionBuckets.two += row.compressionBuckets.two
                existing.compressionBuckets.threePlus += row.compressionBuckets.threePlus
                existing.days = mergedRepoInsightDays(existing.days + row.days)
                buckets[row.key] = existing
            } else {
                buckets[row.key] = row
            }
        }
    }

    let rows = buckets.values.sorted {
        if $0.compressions != $1.compressions {
            return $0.compressions > $1.compressions
        }
        if $0.conversations != $1.conversations {
            return $0.conversations > $1.conversations
        }
        if $0.tokens != $1.tokens {
            return $0.tokens > $1.tokens
        }
        return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
    }
    return RepoInsightsReport(rows: rows, scannedAt: scannedAt, windowDays: windowDays)
}

private func mergedRepoInsightDays(_ days: [RepoInsightDay]) -> [RepoInsightDay] {
    var buckets: [String: RepoInsightDay] = [:]
    for day in days {
        var existing = buckets[day.day] ?? RepoInsightDay(day: day.day, conversations: 0, turns: 0, compressions: 0)
        existing.conversations += day.conversations
        existing.turns += day.turns
        existing.compressions += day.compressions
        buckets[day.day] = existing
    }
    return buckets.values.sorted { $0.day < $1.day }
}

func profileReportWithLocalFallback(_ profileReport: TokenReport, localReport: TokenReport?) -> TokenReport {
    guard let localReport, !profileReport.byDay.isEmpty, !localReport.byDay.isEmpty else {
        return profileReport
    }

    var localByDay: [String: DayUsage] = [:]
    for day in localReport.byDay {
        localByDay[day.day] = day
    }

    var merged = profileReport
    var fallbackUsage = Usage()
    var fallbackTurns = 0
    var fallbackModels: [String: ModelUsage] = [:]
    var didFallback = false

    merged.byDay = profileReport.byDay.map { profileDay in
        guard profileDay.usage.total == 0,
              let localDay = localByDay[profileDay.day],
              localDay.usage.total > 0 else {
            return profileDay
        }

        didFallback = true
        fallbackUsage.add(localDay.usage)
        fallbackTurns += localDay.turns
        for model in localDay.modelBreakdown {
            var existing = fallbackModels[model.name] ?? ModelUsage(name: model.name, usage: Usage(), events: 0, sessions: 0)
            existing.usage.add(model.usage)
            existing.events += model.events
            existing.sessions += model.sessions
            fallbackModels[model.name] = existing
        }
        return DayUsage(day: profileDay.day, usage: localDay.usage, turns: localDay.turns, modelBreakdown: localDay.modelBreakdown)
    }

    guard didFallback else { return profileReport }

    merged.usage.add(fallbackUsage)
    merged.turns += fallbackTurns
    if !fallbackModels.isEmpty {
        var modelsByName: [String: ModelUsage] = [:]
        for model in merged.modelBreakdown {
            modelsByName[model.name] = model
        }
        for model in fallbackModels.values {
            var existing = modelsByName[model.name] ?? ModelUsage(name: model.name, usage: Usage(), events: 0, sessions: 0)
            existing.usage.add(model.usage)
            existing.events += model.events
            existing.sessions += model.sessions
            modelsByName[model.name] = existing
        }
        merged.modelBreakdown = modelsByName.values.sorted { $0.usage.total > $1.usage.total }
    }
    return merged
}

struct DashboardState {
    var report = TokenReport()
    var codexReport: TokenReport?
    var claudeReport: TokenReport?
    var profileReport: TokenReport?
    var accountUsage: AccountUsageSnapshot?
    var costReferenceReport: TokenReport?
    var liveLimits: [LiveRateLimit] = []
    var serviceStatus: CodexServiceStatusSnapshot?
    var selectedWindow: WindowOption = .week
    var selectedQuota: QuotaViewOption = .all
    var nextRefreshAt = Date()
    var isLoading = false
    var error: String?
}

struct PlanCostEstimate {
    let monthlyCost: Double
    let weeklyBudget: Double
    let weeklyQuotaTotal: Double
    let todayValue: Double
    let selectedDayValue: Double
    let weeklyUsedValue: Double
    let weeklyUnusedValue: Double
    let totalSpentValue: Double
    let totalWastedValue: Double
    let selectedDayQuotaPercent: Double
}

struct MonthlySpendRow {
    let month: String
    let usedValue: Double
    let usedPercentOfPlan: Double
}

struct CostPeriodRow {
    let label: String
    let title: String
    let subtitle: String?
    let usedValue: Double
    let remainingValue: Double
    let budgetValue: Double
    let apiEquivalentUSD: Double?
    let apiEquivalentCoveragePercent: Double
    let hasData: Bool
    let isFuture: Bool
    let isShortCycle: Bool
    let cycleIndex: Int

    var usedPercent: Double {
        guard budgetValue > 0 else { return 0 }
        return min(999, max(0, usedValue / budgetValue * 100))
    }
}

struct CostEstimator {
    private static let historicalFullWeekPeakShare = 0.45

    let report: TokenReport
    let monthlyCost: Double
    let weeklyBudget: Double
    let weeklyReferenceTotal: Double
    let weekly: RateWindow?
    let limitID: String?
    let weeklyBuckets: [Date: Int64]
    let weeklyActiveDays: [Date: Int]
    let recentWeekTotal: Int64
    let startDay: String

    init?(report: TokenReport, limit: LiveRateLimit?, quotaReferenceReport: TokenReport? = nil, monthlyCost: Double = AppSettings.monthlyPlanCost, paymentStartDay: String? = AppSettings.paymentStartDay) {
        guard monthlyCost > 0 else { return nil }
        let startDay = effectivePaymentStartDay(in: report, paymentStartDay: paymentStartDay)
        let weekly = limit?.secondary
        let weeklyBuckets = Self.weeklyUsageBuckets(days: report.byDay, startDay: startDay)
        let weeklyActiveDays = Self.weeklyActiveDayCounts(days: report.byDay, startDay: startDay)
        let recentWeekTotal = Array(report.byDay.suffix(7)).reduce(Int64(0)) { $0 + $1.usage.total }
        guard weeklyBuckets.values.contains(where: { $0 > 0 }),
              let weeklyReferenceTotal = Self.weeklyReferenceTotal(days: report.byDay, startDay: startDay, weekly: weekly, quotaReferenceTotal: quotaReferenceReport?.usage.total),
              weeklyReferenceTotal > 0 else {
            return nil
        }
        self.report = report
        self.monthlyCost = monthlyCost
        self.weeklyBudget = monthlyCost * 12 / 52
        self.weeklyReferenceTotal = weeklyReferenceTotal
        self.weekly = weekly
        self.limitID = limit?.id
        self.weeklyBuckets = weeklyBuckets
        self.weeklyActiveDays = weeklyActiveDays
        self.recentWeekTotal = recentWeekTotal
        self.startDay = startDay
    }

    static func weeklyUsageBuckets(days: [DayUsage], startDay: String? = nil) -> [Date: Int64] {
        let calendar = appCalendar()
        let parser = dayFormatter()
        var buckets: [Date: Int64] = [:]
        for day in days where startDay.map({ day.day >= $0 }) ?? true && day.usage.total > 0 {
            guard let date = parser.date(from: day.day),
                  let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { continue }
            buckets[start, default: 0] += day.usage.total
        }
        return buckets
    }

    static func weeklyActiveDayCounts(days: [DayUsage], startDay: String? = nil) -> [Date: Int] {
        let calendar = appCalendar()
        let parser = dayFormatter()
        var buckets: [Date: Int] = [:]
        for day in days where startDay.map({ day.day >= $0 }) ?? true && day.usage.total > 0 {
            guard let date = parser.date(from: day.day),
                  let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { continue }
            buckets[start, default: 0] += 1
        }
        return buckets
    }

    static func weeklyReferenceTotal(days: [DayUsage], startDay: String? = nil, weekly: RateWindow?, quotaReferenceTotal: Int64? = nil) -> Double? {
        let buckets = weeklyUsageBuckets(days: days, startDay: startDay)
        guard let peakHistoricalTotal = buckets.values.max(), peakHistoricalTotal > 0 else {
            return nil
        }

        let quotaReferenceTotal = quotaReferenceTotal ?? 0
        if quotaReferenceTotal > 0,
           let weekly,
           weekly.usedPercent > 0 {
            let liveCalibratedTotal = Double(quotaReferenceTotal) / max(weekly.usedPercent / 100, 0.0001)
            return max(Double(peakHistoricalTotal), liveCalibratedTotal)
        }

        let calendar = appCalendar()
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? calendar.startOfDay(for: Date())
        let currentWeekTotal = buckets[currentWeekStart] ?? 0
        if buckets.count <= 1,
           currentWeekTotal > 0,
           let weekly,
           weekly.usedPercent > 0 {
            return Double(currentWeekTotal) / max(weekly.usedPercent / 100, 0.0001)
        }

        guard let weekly,
              weekly.usedPercent >= 10,
              currentWeekTotal > 0 else {
            return Double(peakHistoricalTotal)
        }
        let liveCalibratedTotal = Double(currentWeekTotal) / max(weekly.usedPercent / 100, 0.0001)
        return max(Double(peakHistoricalTotal), liveCalibratedTotal)
    }

    func value(for usage: Usage) -> Double {
        value(forTotal: usage.total)
    }

    func value(forDay day: DayUsage) -> Double {
        tokenValue(forDayKey: day.day, usage: day.usage)
    }

    func tokenValue(forDayKey dayKey: String, usage: Usage) -> Double {
        guard usage.total > 0,
              let date = dayFormatter().date(from: dayKey),
              let weekStart = appCalendar().dateInterval(of: .weekOfYear, for: date)?.start else {
            return value(for: usage)
        }
        let weekTotal = weeklyBuckets[weekStart] ?? 0
        guard weekTotal > 0 else {
            return value(for: usage)
        }
        let weekValue = tokenEstimatedWeeklyValue(forWeekStart: weekStart, total: weekTotal)
        return weekValue * Double(usage.total) / Double(weekTotal)
    }

    func value(forTotal total: Int64) -> Double {
        weeklyBudget * Double(total) / weeklyReferenceTotal
    }

    func quotaPercent(for usage: Usage) -> Double {
        quotaPercent(forTotal: usage.total)
    }

    func quotaPercent(forTotal total: Int64) -> Double {
        Double(total) / weeklyReferenceTotal * 100
    }

    func weeklyUsedValue() -> Double {
        let total = weeklyBuckets[currentWeekStart] ?? recentWeekTotal
        return currentWeeklyUsedValue(total: total)
    }

    func weeklyUnusedValue() -> Double {
        max(0, weeklyBudget - weeklyUsedValue())
    }

    func weeklyUsedValue(forWeekStart start: Date, total: Int64) -> Double {
        if start == currentWeekStart {
            return currentWeeklyUsedValue(total: total)
        }
        return localWeeklyUsedValue(forWeekStart: start, total: total)
    }

    func weeklyUnusedValue(forWeekStart start: Date, total: Int64) -> Double {
        max(0, weeklyBudget - weeklyUsedValue(forWeekStart: start, total: total))
    }

    func tokenEstimatedWeeklyValue(forWeekStart start: Date, total: Int64) -> Double {
        localWeeklyUsedValue(forWeekStart: start, total: total)
    }

    func monthlyUsedValues() -> [String: Double] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM"

        var values: [String: Double] = [:]
        var starts = Set(weeklyBuckets.keys)
        if weeklyUsedValue() > 0 {
            starts.insert(currentWeekStart)
        }

        for start in starts {
            let total = weeklyBuckets[start] ?? 0
            let usedValue = weeklyUsedValue(forWeekStart: start, total: total)
            guard usedValue > 0 else { continue }
            values[formatter.string(from: start), default: 0] += usedValue
        }
        return values
    }

    func totalSpentValue() -> Double {
        var starts = Set(weeklyBuckets.keys)
        if weeklyUsedValue() > 0 {
            starts.insert(currentWeekStart)
        }
        return starts.reduce(0.0) { partial, start in
            partial + weeklyUsedValue(forWeekStart: start, total: weeklyBuckets[start] ?? 0)
        }
    }

    private var currentWeekStart: Date {
        let calendar = appCalendar()
        return calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? calendar.startOfDay(for: Date())
    }

    private func currentWeeklyUsedValue(total: Int64) -> Double {
        guard let weekly else {
            return localWeeklyUsedValue(forWeekStart: currentWeekStart, total: total)
        }
        let liveValue = weeklyBudget * max(0, weekly.usedPercent) / 100
        return min(weeklyBudget, liveValue)
    }

    private func localWeeklyUsedValue(forWeekStart start: Date, total: Int64) -> Double {
        guard total > 0 else { return 0 }
        let localValue: Double
        if isHistoricalFullWeek(start: start, total: total) {
            localValue = weeklyBudget
        } else {
            localValue = min(weeklyBudget, value(forTotal: total))
        }
        if start < currentWeekStart,
           let limitID,
           let recordedPercent = CostHistoryStore.shared.maxUsedPercent(limitID: limitID, weekStart: start),
           recordedPercent > 0 {
            let recordedValue = weeklyBudget * min(100, recordedPercent) / 100
            return max(localValue, recordedValue)
        }
        return localValue
    }

    private func isHistoricalFullWeek(start: Date, total: Int64) -> Bool {
        guard start < currentWeekStart,
              total > 0,
              (weeklyActiveDays[start] ?? 0) >= 7,
              let peak = weeklyBuckets.values.max(),
              peak > 0 else {
            return false
        }
        return Double(total) >= Double(peak) * Self.historicalFullWeekPeakShare
    }

}
