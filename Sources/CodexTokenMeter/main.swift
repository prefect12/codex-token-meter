import Cocoa
import Foundation
import ServiceManagement
import UserNotifications

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

private struct APIModelRate {
    let inputPerMillionUSD: Double
    let cachedInputPerMillionUSD: Double
    let outputPerMillionUSD: Double
}

private enum APICostEstimator {
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

enum WindowOption: Int, CaseIterable {
    case day = 24
    case week = 168
    case month = 720

    var title: String {
        switch self {
        case .day: return t(.past24Hours)
        case .week: return t(.past7Days)
        case .month: return t(.past30Days)
        }
    }

    var shortTitle: String {
        switch self {
        case .day: return "24h"
        case .week: return "7d"
        case .month: return "30d"
        }
    }
}

private enum AppLanguage: String, CaseIterable {
    case english = "en"
    case chinese = "zh"
    case hindi = "hi"
    case portugueseBrazil = "pt-BR"
    case russian = "ru"
    case german = "de"
    case spanish = "es"
    case french = "fr"
    case japanese = "ja"
    case indonesian = "id"
    case traditionalChinese = "zh-Hant"
    case polish = "pl"
    case ukrainian = "uk"
    case korean = "ko"
    case italian = "it"

    static let storageKey = "appLanguage"

    static var current: AppLanguage {
        get {
            if let raw = UserDefaults.standard.string(forKey: storageKey),
               let language = AppLanguage(rawValue: raw) {
                return language
            }
            if UserDefaults.standard.string(forKey: storageKey) == "zh-Hans" {
                return .chinese
            }
            let preferred = Locale.preferredLanguages.first ?? ""
            if preferred.hasPrefix("zh-Hant") || preferred.hasPrefix("zh-HK") || preferred.hasPrefix("zh-TW") {
                return .traditionalChinese
            }
            if preferred.hasPrefix("zh") {
                return .chinese
            }
            if preferred.hasPrefix("hi") { return .hindi }
            if preferred.hasPrefix("pt-BR") || preferred.hasPrefix("pt_BR") { return .portugueseBrazil }
            if preferred.hasPrefix("ru") { return .russian }
            if preferred.hasPrefix("de") { return .german }
            if preferred.hasPrefix("es") { return .spanish }
            if preferred.hasPrefix("fr") { return .french }
            if preferred.hasPrefix("ja") {
                return .japanese
            }
            if preferred.hasPrefix("id") { return .indonesian }
            if preferred.hasPrefix("pl") { return .polish }
            if preferred.hasPrefix("uk") { return .ukrainian }
            if preferred.hasPrefix("ko") { return .korean }
            if preferred.hasPrefix("it") { return .italian }
            return .english
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
        }
    }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "中文"
        case .hindi: return "हिन्दी"
        case .portugueseBrazil: return "Português Brasileiro"
        case .russian: return "Русский"
        case .german: return "Deutsch"
        case .spanish: return "Español"
        case .french: return "Français"
        case .japanese: return "日本語"
        case .indonesian: return "Bahasa Indonesia"
        case .traditionalChinese: return "繁體中文"
        case .polish: return "Polski"
        case .ukrainian: return "Українська"
        case .korean: return "한국어"
        case .italian: return "Italiano"
        }
    }

    func text(_ key: L10nKey) -> String {
        switch self {
        case .english:
            return key.english
        case .chinese:
            return key.chinese
        case .japanese:
            return key.japanese
        default:
            return key.english
        }
    }
}

private enum StatusDisplayOption: String, CaseIterable {
    case fiveHourPercent
    case weeklyPercent
    case weeklyTokens
    case dailyTokens

    static let storageKey = "statusDisplayOption"

    static var current: StatusDisplayOption {
        get {
            guard let raw = UserDefaults.standard.string(forKey: storageKey),
                  let option = StatusDisplayOption(rawValue: raw) else {
                return .fiveHourPercent
            }
            return option
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
        }
    }

    var title: String {
        switch self {
        case .fiveHourPercent: return t(.statusFiveHourPercent)
        case .weeklyPercent: return t(.statusWeeklyPercent)
        case .weeklyTokens: return t(.statusWeeklyTokens)
        case .dailyTokens: return t(.statusDailyTokens)
        }
    }

    var requiredReportWindow: WindowOption? {
        switch self {
        case .weeklyTokens: return .week
        case .dailyTokens: return .day
        case .fiveHourPercent, .weeklyPercent: return nil
        }
    }
}

private enum QuotaDisplayStyle: String, CaseIterable {
    case rings
    case bullet

    static let storageKey = "quotaDisplayStyle"

    static var current: QuotaDisplayStyle {
        get {
            guard let raw = UserDefaults.standard.string(forKey: storageKey),
                  let style = QuotaDisplayStyle(rawValue: raw) else {
                return .rings
            }
            return style
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
        }
    }

    var title: String {
        switch self {
        case .rings: return t(.quotaDisplayRings)
        case .bullet: return t(.quotaDisplayBullet)
        }
    }
}

private enum NumberUnitStyle: String, CaseIterable {
    case english
    case chinese

    static let storageKey = "numberUnitStyle"

    static var availableCases: [NumberUnitStyle] {
        usesChineseUnits ? [.english, .chinese] : [.english]
    }

    static var effective: NumberUnitStyle {
        usesChineseUnits ? current : .english
    }

    static var current: NumberUnitStyle {
        get {
            guard let raw = UserDefaults.standard.string(forKey: storageKey),
                  let style = NumberUnitStyle(rawValue: raw) else {
                return usesChineseUnits ? .chinese : .english
            }
            return style
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
        }
    }

    var title: String {
        switch self {
        case .english: return "English"
        case .chinese: return "中文"
        }
    }

    private static var usesChineseUnits: Bool {
        AppLanguage.current == .chinese || AppLanguage.current == .traditionalChinese
    }
}

private enum L10nKey {
    case about
    case aboutSubtitle
    case all
    case allDescription
    case apiEquivalent
    case apiEquivalentHint
    case before
    case budget
    case cache
    case cacheHit
    case cacheHitDescription
    case cached
    case calendar
    case calendarSubtitle
    case clickForDetails
    case codexAppTotal
    case copy
    case costs
    case costsSubtitle
    case costHistory
    case codexIncident
    case codexNoActiveIncident
    case codexStatus
    case codexStatusDegraded
    case codexStatusInvestigating
    case codexStatusMaintenance
    case codexStatusMajorOutage
    case codexStatusMonitoring
    case codexStatusOperational
    case codexStatusPartialOutage
    case codexStatusResolved
    case codexStatusUnavailable
    case dayValue
    case dataSource
    case dataSourceLine1
    case dataSourceLine2
    case definitions
    case detectedNotTracked
    case details
    case detailsWindowTitle
    case diagnostics
    case diagnosticsSubtitle
    case disabled
    case displayCurrency
    case dayValueHint
    case displayEquivalent
    case enabled
    case english
    case events
    case externalAPICost
    case externalAPICostHint
    case fileMissing
    case filePresent
    case fresh
    case inShort
    case input
    case interfaceLanguage
    case japanese
    case language
    case languageHint
    case launchAtLogin
    case launchAtLoginHint
    case liveQuota
    case liveLimitUnavailable
    case logFolder
    case logFolderHint
    case logFolderChoose
    case logFolderDefault
    case logFolderOpen
    case loadingUsageDetails
    case logs
    case manualRefreshCycle
    case modelLimit
    case modelGroupingNote
    case modelMissingNote
    case monthlySpendHistory
    case models
    case modelsSubtitle
    case next
    case noDailyTokenData
    case noDataLoaded
    case noDaySelected
    case noUsage
    case now
    case future
    case noModelLabelForDay
    case noModelLabelsFound
    case nonSparkUsage
    case numberUnits
    case numberUnitsHint
    case other
    case otherDefinition
    case otherDescription
    case otherTools
    case outShort
    case output
    case overview
    case overviewSubtitle
    case past24Hours
    case past30Days
    case past7Days
    case pastYear
    case peakDay
    case planCost
    case planCostChange
    case planCostHint
    case planCostUnavailable
    case paymentCurrency
    case paymentMonthly
    case paymentStartDate
    case priced
    case profileAPISource
    case profileAPITotals
    case profileAPITotalsHint
    case quotaDisplayBullet
    case quotaDisplayHint
    case quotaDisplayRings
    case quotaDisplayStyle
    case quotaViews
    case quotaWarnings
    case quotaWarningsHint
    case recentRollouts
    case quit
    case refresh
    case refreshing
    case remaining
    case showPastEmptyWeeks
    case showCodexStatus
    case reset
    case sessions
    case settings
    case settingsSubtitle
    case sourceHealth
    case spark
    case sparkDescription
    case sparkModel
    case statusBarDisplay
    case statusDailyTokens
    case statusDisplayHint
    case statusFiveHourPercent
    case statusWeeklyPercent
    case statusWeeklyTokens
    case tokenActivity
    case tokenMeter
    case tracked
    case total
    case totalSpendValue
    case totalSpendValueHint
    case totalWasteValue
    case totalWasteValueHint
    case totalsObservedNote
    case turns
    case todayValue
    case updated
    case used
    case usageDetails
    case usageIntensityHint
    case usageRateHint
    case usageWindow
    case visibleWeekShare
    case week
    case weeklyBudget
    case weeklyQuotaShare
    case weeklyUnusedValue
    case weeklyUsedValue
    case weeklyLeft
    case costHistoryHint
    case usageRate
    case apiEquivalentCostHint
    case externalAPICostCalculationHint
    case month
    case fiveHourLeft
    case chinese

    var english: String {
        switch self {
        case .about: return "About"
        case .aboutSubtitle: return "How the meter reads and groups Codex usage"
        case .all: return "All"
        case .allDescription: return "Everything with token detail"
        case .apiEquivalent: return "API equivalent"
        case .apiEquivalentHint: return "Estimated from official API-style token prices. Unlabeled tokens default to GPT-5.5."
        case .before: return "Before"
        case .budget: return "Budget"
        case .cache: return "Cache"
        case .cacheHit: return "Cache Hit"
        case .cacheHitDescription: return "Cached input divided by total input for the selected window."
        case .cached: return "Cached"
        case .calendar: return "Calendar"
        case .calendarSubtitle: return "Daily usage intensity over the last year"
        case .clickForDetails: return "Click for details"
        case .codexAppTotal: return "Codex app total"
        case .copy: return "Copy"
        case .costs: return "Costs"
        case .costsSubtitle: return "Plan settings and estimated money usage"
        case .costHistory: return "Spend History"
        case .codexIncident: return "Incident"
        case .codexNoActiveIncident: return "No active incidents"
        case .codexStatus: return "Codex Status"
        case .codexStatusDegraded: return "Degraded"
        case .codexStatusInvestigating: return "Investigating"
        case .codexStatusMaintenance: return "Maintenance"
        case .codexStatusMajorOutage: return "Major Outage"
        case .codexStatusMonitoring: return "Monitoring"
        case .codexStatusOperational: return "Operational"
        case .codexStatusPartialOutage: return "Partial Outage"
        case .codexStatusResolved: return "Resolved"
        case .codexStatusUnavailable: return "Status unavailable"
        case .dayValue: return "Day value"
        case .dataSource: return "Data Source"
        case .dataSourceLine1: return "The app reads local Codex session logs under ~/.codex/sessions, ~/.codex/archived_sessions, and CODEX_HOME when set."
        case .dataSourceLine2: return "Totals are local-observed token usage, not an official billing export."
        case .definitions: return "Definitions"
        case .detectedNotTracked: return "Detected, not counted"
        case .details: return "Details"
        case .detailsWindowTitle: return "Codex Token Meter Details"
        case .diagnostics: return "Diagnostics"
        case .diagnosticsSubtitle: return "Data sources, warnings, and tool coverage"
        case .disabled: return "Disabled"
        case .displayCurrency: return "Display currency"
        case .dayValueHint: return "Estimated by converting that day's token usage into money based on your plan price, not official billing."
        case .displayEquivalent: return "Display equivalent"
        case .enabled: return "Enabled"
        case .english: return "English"
        case .events: return "events"
        case .externalAPICost: return "External API cost"
        case .externalAPICostHint: return "Optional local JSON at api-usage.json can add direct OpenAI API usage that bypasses Codex logs."
        case .fileMissing: return "File missing"
        case .filePresent: return "File present"
        case .fresh: return "Fresh"
        case .inShort: return "in"
        case .input: return "Input"
        case .interfaceLanguage: return "Interface Language"
        case .japanese: return "Japanese"
        case .language: return "Language"
        case .languageHint: return "Changes apply immediately to the popover and details window."
        case .launchAtLogin: return "Open at Login"
        case .launchAtLoginHint: return "Start Codex Token Meter automatically when you sign in."
        case .liveQuota: return "Live quota"
        case .liveLimitUnavailable: return "Live limit unavailable"
        case .logFolder: return "Log Folder"
        case .logFolderHint: return "Default scans sessions and archived_sessions; choosing a folder overrides the scan roots."
        case .logFolderChoose: return "Choose..."
        case .logFolderDefault: return "Default"
        case .logFolderOpen: return "Finder"
        case .loadingUsageDetails: return "Loading usage details..."
        case .logs: return "Logs"
        case .manualRefreshCycle: return "OpenAI refresh"
        case .modelLimit: return "Model"
        case .modelGroupingNote: return "Model grouping comes from turn_context.model in local Codex rollout logs."
        case .modelMissingNote: return "Rows without a model label are counted in totals but cannot be assigned to a model."
        case .monthlySpendHistory: return "Monthly spend history"
        case .models: return "Models"
        case .modelsSubtitle: return "Token cost grouped by model"
        case .next: return "next"
        case .noDailyTokenData: return "No daily token data"
        case .noDataLoaded: return "No data loaded"
        case .noDaySelected: return "No Day Selected"
        case .noUsage: return "No usage"
        case .now: return "now"
        case .future: return "Future"
        case .noModelLabelForDay: return "No model label found for this day"
        case .noModelLabelsFound: return "No model labels found in logs"
        case .nonSparkUsage: return "Other model usage"
        case .numberUnits: return "Number units"
        case .numberUnitsHint: return "Controls compact token counts only. Currency formatting is unchanged."
        case .other: return "Other"
        case .otherDefinition: return "All token-detail events after subtracting the model-level limit."
        case .otherDescription: return "All other models"
        case .otherTools: return "Other tools"
        case .outShort: return "out"
        case .output: return "Output"
        case .overview: return "Overview"
        case .overviewSubtitle: return "365-day token usage by quota and model"
        case .past24Hours: return "Past 24 Hours"
        case .past30Days: return "Past 30 Days"
        case .past7Days: return "Past 7 Days"
        case .pastYear: return "Past Year"
        case .peakDay: return "of peak day"
        case .planCost: return "Plan Cost"
        case .planCostChange: return "Change"
        case .planCostHint: return "Estimated from monthly price, local FX rates, and live weekly quota usage; this is not official billing."
        case .planCostUnavailable: return "Cost estimate needs live weekly limit data"
        case .paymentCurrency: return "Payment currency"
        case .paymentMonthly: return "Monthly paid"
        case .paymentStartDate: return "Paid since"
        case .priced: return "priced"
        case .profileAPISource: return "Profile API"
        case .profileAPITotals: return "Profile API totals"
        case .profileAPITotalsHint: return "Uses account/usage/read for official lifetime totals and daily buckets. If an API day is 0 but same-day local logs have usage, daily views fall back to local logs."
        case .quotaDisplayBullet: return "Bullet"
        case .quotaDisplayHint: return "Choose how the 5h and weekly quota pace are shown."
        case .quotaDisplayRings: return "Rings"
        case .quotaDisplayStyle: return "Quota Display"
        case .quotaViews: return "Quota Views"
        case .quotaWarnings: return "Quota warnings"
        case .quotaWarningsHint: return "Notify once when a live quota window drops below 15% remaining."
        case .recentRollouts: return "Recent rollouts"
        case .quit: return "Quit"
        case .refresh: return "Refresh"
        case .refreshing: return "Refreshing..."
        case .remaining: return "Remaining"
        case .showPastEmptyWeeks: return "Show past empty weeks"
        case .showCodexStatus: return "Show Codex status"
        case .reset: return "Reset"
        case .sessions: return "Sessions"
        case .settings: return "Settings"
        case .settingsSubtitle: return "Language and display preferences"
        case .sourceHealth: return "Source health"
        case .spark: return "Spark"
        case .sparkDescription: return "Events whose model is GPT-5.3-Codex-Spark."
        case .sparkModel: return "GPT-5.3-Codex-Spark model"
        case .statusBarDisplay: return "Menu Bar Display"
        case .statusDailyTokens: return "24h tokens"
        case .statusDisplayHint: return "Choose what the menu bar item shows."
        case .statusFiveHourPercent: return "5h %"
        case .statusWeeklyPercent: return "Weekly %"
        case .statusWeeklyTokens: return "7d tokens"
        case .tokenActivity: return "Token Activity"
        case .tokenMeter: return "Token Meter"
        case .tracked: return "Tracked"
        case .total: return "total"
        case .totalSpendValue: return "Total spend"
        case .totalSpendValueHint: return "Accumulated plan value since the paid-start date, estimated from local token usage and weekly quota references."
        case .totalWasteValue: return "Total waste"
        case .totalWasteValueHint: return "Accrued budget minus total spend. Negative values are clamped to zero."
        case .totalsObservedNote: return "local-observed usage, not official billing"
        case .turns: return "turns"
        case .todayValue: return "Today value"
        case .updated: return "Updated"
        case .used: return "Used"
        case .usageDetails: return "Usage Details"
        case .usageIntensityHint: return "darker means more token usage"
        case .usageRateHint: return "This week used value divided by this week budget. Current week prefers live weekly quota usedPercent."
        case .usageWindow: return "Usage window"
        case .visibleWeekShare: return "7d share"
        case .week: return "Week"
        case .weeklyBudget: return "Weekly budget"
        case .weeklyQuotaShare: return "Week quota"
        case .weeklyUnusedValue: return "Week remaining money"
        case .weeklyUsedValue: return "Week used"
        case .weeklyLeft: return "Weekly Left"
        case .costHistoryHint: return "Hover a ring to inspect used, remaining, budget, and usage rate."
        case .usageRate: return "Usage rate"
        case .apiEquivalentCostHint: return "fresh input × input price + cached input × cache price + output × output price. Unlabeled tokens use GPT-5.5."
        case .externalAPICostCalculationHint: return "Direct API usage read from local api-usage.json. It is separate from Codex rollout logs."
        case .month: return "Month"
        case .fiveHourLeft: return "5h Left"
        case .chinese: return "Chinese"
        }
    }

    var chinese: String {
        switch self {
        case .about: return "关于"
        case .aboutSubtitle: return "Codex 用量的读取和分组方式"
        case .all: return "全部"
        case .allDescription: return "包含 token 明细的全部记录"
        case .apiEquivalent: return "API 等价成本"
        case .apiEquivalentHint: return "按官方 API/token 单价估算；没有模型标签的 token 默认按 GPT-5.5。"
        case .before: return "刷新前"
        case .budget: return "预算"
        case .cache: return "缓存"
        case .cacheHit: return "缓存命中"
        case .cacheHitDescription: return "选定时间范围内，缓存输入占总输入的比例。"
        case .cached: return "缓存"
        case .calendar: return "日历"
        case .calendarSubtitle: return "过去一年的每日使用强度"
        case .clickForDetails: return "点击查看详情"
        case .codexAppTotal: return "Codex 总用量"
        case .copy: return "复制"
        case .costs: return "金额"
        case .costsSubtitle: return "套餐设置和金额估算"
        case .costHistory: return "金额历史"
        case .codexIncident: return "故障"
        case .codexNoActiveIncident: return "当前没有故障"
        case .codexStatus: return "Codex 状态"
        case .codexStatusDegraded: return "降级"
        case .codexStatusInvestigating: return "排查中"
        case .codexStatusMaintenance: return "维护中"
        case .codexStatusMajorOutage: return "重大故障"
        case .codexStatusMonitoring: return "观察中"
        case .codexStatusOperational: return "正常"
        case .codexStatusPartialOutage: return "部分中断"
        case .codexStatusResolved: return "已恢复"
        case .codexStatusUnavailable: return "状态暂不可用"
        case .dayValue: return "当日价值"
        case .dataSource: return "数据来源"
        case .dataSourceLine1: return "应用读取 ~/.codex/sessions、~/.codex/archived_sessions，以及已设置的 CODEX_HOME。"
        case .dataSourceLine2: return "这里是本地观测到的 token 用量，不是官方账单导出。"
        case .definitions: return "定义"
        case .detectedNotTracked: return "已检测，未计入"
        case .details: return "详情"
        case .detailsWindowTitle: return "Codex Token Meter 详情"
        case .diagnostics: return "诊断"
        case .diagnosticsSubtitle: return "数据源、提醒和工具覆盖"
        case .disabled: return "已关闭"
        case .displayCurrency: return "展示币种"
        case .dayValueHint: return "按你的套餐价格，把当天 token 开销折算成金额的估算值，不是官方账单。"
        case .displayEquivalent: return "展示折合"
        case .enabled: return "已开启"
        case .english: return "英语"
        case .events: return "事件"
        case .externalAPICost: return "外部 API 成本"
        case .externalAPICostHint: return "可选读取本地 api-usage.json，用来补充绕过 Codex 日志的 OpenAI API 用量。"
        case .fileMissing: return "文件不存在"
        case .filePresent: return "文件存在"
        case .fresh: return "新输入"
        case .inShort: return "输入"
        case .input: return "输入"
        case .interfaceLanguage: return "界面语言"
        case .japanese: return "日语"
        case .language: return "语言"
        case .languageHint: return "切换后会立即应用到弹窗和详情窗口。"
        case .launchAtLogin: return "开机启动"
        case .launchAtLoginHint: return "登录 macOS 后自动启动 Codex Token Meter。"
        case .liveQuota: return "实时额度"
        case .liveLimitUnavailable: return "实时限额不可用"
        case .logFolder: return "日志目录"
        case .logFolderHint: return "默认扫描 sessions 和 archived_sessions；手动选择目录会覆盖默认扫描范围。"
        case .logFolderChoose: return "选择..."
        case .logFolderDefault: return "默认"
        case .logFolderOpen: return "Finder"
        case .loadingUsageDetails: return "正在加载用量详情..."
        case .logs: return "日志"
        case .manualRefreshCycle: return "OpenAI 手动刷新"
        case .modelLimit: return "模型"
        case .modelGroupingNote: return "模型分组来自本地 Codex rollout 日志里的 turn_context.model。"
        case .modelMissingNote: return "没有模型标签的记录会计入总量，但无法归入单个模型。"
        case .monthlySpendHistory: return "月度金额历史"
        case .models: return "模型"
        case .modelsSubtitle: return "按模型统计 token 开销"
        case .next: return "下次"
        case .noDailyTokenData: return "没有每日 token 数据"
        case .noDataLoaded: return "没有加载数据"
        case .noDaySelected: return "未选择日期"
        case .noUsage: return "无用量"
        case .now: return "现在"
        case .future: return "未来"
        case .noModelLabelForDay: return "这一天没有模型标签"
        case .noModelLabelsFound: return "日志中没有模型标签"
        case .nonSparkUsage: return "其他模型用量"
        case .numberUnits: return "数字单位"
        case .numberUnitsHint: return "只影响 token 数字缩写；金额格式不变。"
        case .other: return "其他"
        case .otherDefinition: return "全部 token 明细减去模型级限额用量后的记录。"
        case .otherDescription: return "全部其他模型"
        case .otherTools: return "其他工具"
        case .outShort: return "输出"
        case .output: return "输出"
        case .overview: return "概览"
        case .overviewSubtitle: return "过去 365 天按限额和模型统计"
        case .past24Hours: return "过去 24 小时"
        case .past30Days: return "过去 30 天"
        case .past7Days: return "过去 7 天"
        case .pastYear: return "过去一年"
        case .peakDay: return "峰值日"
        case .planCost: return "套餐成本"
        case .planCostChange: return "修改"
        case .planCostHint: return "基于月费、本地近似汇率和实时周额度使用率估算，不是官方账单。"
        case .planCostUnavailable: return "成本估算需要实时周额度数据"
        case .paymentCurrency: return "付款币种"
        case .paymentMonthly: return "月付金额"
        case .paymentStartDate: return "付费开始日期"
        case .priced: return "已计价"
        case .profileAPISource: return "Profile API"
        case .profileAPITotals: return "Profile API 总量"
        case .profileAPITotalsHint: return "用 account/usage/read 读取官方累计总量和每日桶；如果某天 API 为 0 但本地同日日志有用量，日历会用本地值兜底。"
        case .quotaDisplayBullet: return "子弹图"
        case .quotaDisplayHint: return "选择 5小时和周额度的节奏展示方式。"
        case .quotaDisplayRings: return "圆环"
        case .quotaDisplayStyle: return "额度样式"
        case .quotaViews: return "限额视图"
        case .quotaWarnings: return "额度提醒"
        case .quotaWarningsHint: return "实时额度低于 15% 时，每个窗口只提醒一次。"
        case .recentRollouts: return "近期日志"
        case .quit: return "退出"
        case .refresh: return "刷新"
        case .refreshing: return "刷新中..."
        case .remaining: return "剩余"
        case .showPastEmptyWeeks: return "显示以前的无数据周"
        case .showCodexStatus: return "显示 Codex 状态"
        case .reset: return "重置"
        case .sessions: return "会话"
        case .settings: return "设置"
        case .settingsSubtitle: return "语言和显示偏好"
        case .sourceHealth: return "数据源健康"
        case .spark: return "Spark"
        case .sparkDescription: return "模型为 GPT-5.3-Codex-Spark 的事件。"
        case .sparkModel: return "GPT-5.3-Codex-Spark 模型"
        case .statusBarDisplay: return "状态栏显示"
        case .statusDailyTokens: return "24h 用量"
        case .statusDisplayHint: return "选择菜单栏里直接展示的指标。"
        case .statusFiveHourPercent: return "5h 百分比"
        case .statusWeeklyPercent: return "周百分比"
        case .statusWeeklyTokens: return "7d 用量"
        case .tokenActivity: return "Token 活动"
        case .tokenMeter: return "Token 统计"
        case .tracked: return "已计入"
        case .total: return "总计"
        case .totalSpendValue: return "总开销"
        case .totalSpendValueHint: return "从付费开始日起，按本地 token 用量和周额度参考值折算出的累计套餐价值。"
        case .totalWasteValue: return "总浪费"
        case .totalWasteValueHint: return "已累积预算减去总开销；如果结果为负数则按 0 处理。"
        case .totalsObservedNote: return "本地观测用量，非官方账单"
        case .turns: return "轮次"
        case .todayValue: return "今日价值"
        case .updated: return "已更新"
        case .used: return "已用"
        case .usageDetails: return "用量详情"
        case .usageIntensityHint: return "颜色越深代表 token 用量越高"
        case .usageRateHint: return "本周已用金额除以本周预算；当前周优先使用实时周额度 usedPercent。"
        case .usageWindow: return "用量窗口"
        case .visibleWeekShare: return "占7天用量"
        case .week: return "周"
        case .weeklyBudget: return "周预算"
        case .weeklyQuotaShare: return "占周额度"
        case .weeklyUnusedValue: return "本周剩余金额"
        case .weeklyUsedValue: return "本周已用"
        case .weeklyLeft: return "周额度剩余"
        case .costHistoryHint: return "悬停圆环可查看已用、剩余、预算和使用率。"
        case .usageRate: return "使用率"
        case .apiEquivalentCostHint: return "按模型单价估算：fresh input × 输入价 + cached input × 缓存价 + output × 输出价；没有模型标签时按 GPT-5.5。"
        case .externalAPICostCalculationHint: return "从本地 api-usage.json 读取的直接 API 用量成本，独立于 Codex rollout 日志。"
        case .month: return "月"
        case .fiveHourLeft: return "5小时剩余"
        case .chinese: return "中文"
        }
    }

    var japanese: String {
        switch self {
        case .about: return "概要"
        case .aboutSubtitle: return "Codex 使用量の読み取りと分類方法"
        case .all: return "すべて"
        case .allDescription: return "token 詳細を含むすべての記録"
        case .apiEquivalent: return "API 換算"
        case .apiEquivalentHint: return "公式 API/token 単価から推定します。モデル名のない token は GPT-5.5 として扱います。"
        case .before: return "更新前"
        case .budget: return "予算"
        case .cache: return "キャッシュ"
        case .cacheHit: return "キャッシュ率"
        case .cacheHitDescription: return "選択した期間の総入力に対するキャッシュ入力の割合。"
        case .cached: return "キャッシュ"
        case .calendar: return "カレンダー"
        case .calendarSubtitle: return "過去 1 年の日別使用量"
        case .clickForDetails: return "クリックで詳細"
        case .codexAppTotal: return "Codex 全体使用量"
        case .copy: return "コピー"
        case .costs: return "金額"
        case .costsSubtitle: return "プラン設定と金額推定"
        case .costHistory: return "金額履歴"
        case .codexIncident: return "障害"
        case .codexNoActiveIncident: return "進行中の障害はありません"
        case .codexStatus: return "Codex 状態"
        case .codexStatusDegraded: return "低下"
        case .codexStatusInvestigating: return "調査中"
        case .codexStatusMaintenance: return "メンテ中"
        case .codexStatusMajorOutage: return "大規模障害"
        case .codexStatusMonitoring: return "監視中"
        case .codexStatusOperational: return "正常"
        case .codexStatusPartialOutage: return "一部停止"
        case .codexStatusResolved: return "復旧済み"
        case .codexStatusUnavailable: return "状態を取得できません"
        case .dayValue: return "当日の価値"
        case .dataSource: return "データソース"
        case .dataSourceLine1: return "このアプリは ~/.codex/sessions、~/.codex/archived_sessions、設定済みの CODEX_HOME を読み取ります。"
        case .dataSourceLine2: return "表示値はローカルで観測した token 使用量であり、公式の請求書エクスポートではありません。"
        case .definitions: return "定義"
        case .detectedNotTracked: return "検出済み・未集計"
        case .details: return "詳細"
        case .detailsWindowTitle: return "Codex Token Meter 詳細"
        case .diagnostics: return "診断"
        case .diagnosticsSubtitle: return "データソース、通知、ツール範囲"
        case .disabled: return "無効"
        case .displayCurrency: return "表示通貨"
        case .dayValueHint: return "プラン料金を基準に、その日の token 使用量を金額換算した推定値であり、公式請求ではありません。"
        case .displayEquivalent: return "表示換算"
        case .enabled: return "有効"
        case .english: return "英語"
        case .events: return "イベント"
        case .externalAPICost: return "外部 API コスト"
        case .externalAPICostHint: return "任意のローカル api-usage.json で Codex ログ外の OpenAI API 使用量を補足できます。"
        case .fileMissing: return "ファイルなし"
        case .filePresent: return "ファイルあり"
        case .fresh: return "新規入力"
        case .inShort: return "入力"
        case .input: return "入力"
        case .interfaceLanguage: return "表示言語"
        case .japanese: return "日本語"
        case .language: return "言語"
        case .languageHint: return "変更はポップオーバーと詳細ウィンドウにすぐ反映されます。"
        case .launchAtLogin: return "ログイン時に開く"
        case .launchAtLoginHint: return "macOS にサインインしたときに Codex Token Meter を自動起動します。"
        case .liveQuota: return "リアルタイム制限"
        case .liveLimitUnavailable: return "リアルタイム制限を取得できません"
        case .logFolder: return "ログフォルダ"
        case .logFolderHint: return "既定では sessions と archived_sessions をスキャンし、選択したフォルダは既定の範囲を上書きします。"
        case .logFolderChoose: return "選択..."
        case .logFolderDefault: return "既定"
        case .logFolderOpen: return "Finder"
        case .loadingUsageDetails: return "使用量の詳細を読み込み中..."
        case .logs: return "ログ"
        case .manualRefreshCycle: return "OpenAI 手動更新"
        case .modelLimit: return "モデル"
        case .modelGroupingNote: return "モデル別集計はローカル Codex rollout ログの turn_context.model から取得します。"
        case .modelMissingNote: return "モデル名がない行は合計に含まれますが、個別モデルには割り当てられません。"
        case .monthlySpendHistory: return "月次金額履歴"
        case .models: return "モデル"
        case .modelsSubtitle: return "モデル別の token 使用量"
        case .next: return "次回"
        case .noDailyTokenData: return "日別 token データがありません"
        case .noDataLoaded: return "データ未読み込み"
        case .noDaySelected: return "日付未選択"
        case .noUsage: return "使用なし"
        case .now: return "現在"
        case .future: return "未来"
        case .noModelLabelForDay: return "この日のモデル名は見つかりません"
        case .noModelLabelsFound: return "ログ内にモデル名が見つかりません"
        case .nonSparkUsage: return "その他モデル使用量"
        case .numberUnits: return "数値単位"
        case .numberUnitsHint: return "token 数の省略表示だけに適用します。金額表示は変わりません。"
        case .other: return "その他"
        case .otherDefinition: return "モデル別制限枠を除いた token 詳細イベント。"
        case .otherDescription: return "その他すべてのモデル"
        case .otherTools: return "その他ツール"
        case .outShort: return "出力"
        case .output: return "出力"
        case .overview: return "概要"
        case .overviewSubtitle: return "過去 365 日の制限枠とモデル別使用量"
        case .past24Hours: return "過去 24 時間"
        case .past30Days: return "過去 30 日"
        case .past7Days: return "過去 7 日"
        case .pastYear: return "過去 1 年"
        case .peakDay: return "ピーク日"
        case .planCost: return "プラン費用"
        case .planCostChange: return "変更"
        case .planCostHint: return "月額料金、ローカルの概算為替、リアルタイムの週制限使用率から推定します。公式請求ではありません。"
        case .planCostUnavailable: return "費用推定には週制限データが必要です"
        case .paymentCurrency: return "支払い通貨"
        case .paymentMonthly: return "月額支払い"
        case .paymentStartDate: return "課金開始日"
        case .priced: return "価格対象"
        case .profileAPISource: return "Profile API"
        case .profileAPITotals: return "Profile API 合計"
        case .profileAPITotalsHint: return "account/usage/read で公式の累計と日別バケットを使います。API の日別値が 0 で同日のローカルログに使用量があれば、日別表示はローカル値で補完します。"
        case .quotaDisplayBullet: return "Bullet"
        case .quotaDisplayHint: return "5h と週制限のペース表示を選びます。"
        case .quotaDisplayRings: return "リング"
        case .quotaDisplayStyle: return "制限表示"
        case .quotaViews: return "制限枠ビュー"
        case .quotaWarnings: return "制限通知"
        case .quotaWarningsHint: return "残り 15% 未満になった制限枠ごとに一度だけ通知します。"
        case .recentRollouts: return "最近の rollout"
        case .quit: return "終了"
        case .refresh: return "更新"
        case .refreshing: return "更新中..."
        case .remaining: return "残り"
        case .showPastEmptyWeeks: return "過去の空週を表示"
        case .showCodexStatus: return "Codex 状態を表示"
        case .reset: return "リセット"
        case .sessions: return "セッション"
        case .settings: return "設定"
        case .settingsSubtitle: return "言語と表示設定"
        case .sourceHealth: return "ソース状態"
        case .spark: return "Spark"
        case .sparkDescription: return "モデルが GPT-5.3-Codex-Spark のイベント。"
        case .sparkModel: return "GPT-5.3-Codex-Spark モデル"
        case .statusBarDisplay: return "メニューバー表示"
        case .statusDailyTokens: return "24h 使用量"
        case .statusDisplayHint: return "メニューバーに表示する指標を選びます。"
        case .statusFiveHourPercent: return "5h %"
        case .statusWeeklyPercent: return "週 %"
        case .statusWeeklyTokens: return "7日使用量"
        case .tokenActivity: return "Token アクティビティ"
        case .tokenMeter: return "Token メーター"
        case .tracked: return "集計対象"
        case .total: return "合計"
        case .totalSpendValue: return "総支出"
        case .totalSpendValueHint: return "課金開始日からの累積プラン価値を、ローカル token 使用量と週制限の参照値から推定します。"
        case .totalWasteValue: return "総浪費"
        case .totalWasteValueHint: return "累積予算から総支出を引いた値です。負の値は 0 として扱います。"
        case .totalsObservedNote: return "ローカル観測値であり公式請求ではありません"
        case .turns: return "ターン"
        case .todayValue: return "今日の価値"
        case .updated: return "更新"
        case .used: return "使用済み"
        case .usageDetails: return "使用量詳細"
        case .usageIntensityHint: return "色が濃いほど token 使用量が多い"
        case .usageRateHint: return "今週の使用額を今週の予算で割った値です。現在週はリアルタイム週制限の usedPercent を優先します。"
        case .usageWindow: return "使用量ウィンドウ"
        case .visibleWeekShare: return "7日内比率"
        case .week: return "週"
        case .weeklyBudget: return "週予算"
        case .weeklyQuotaShare: return "週制限内"
        case .weeklyUnusedValue: return "週の残額"
        case .weeklyUsedValue: return "週使用済み"
        case .weeklyLeft: return "週制限の残り"
        case .costHistoryHint: return "リングに重ねると使用額、残額、予算、使用率を確認できます。"
        case .usageRate: return "使用率"
        case .apiEquivalentCostHint: return "fresh input × 入力価格 + cached input × キャッシュ価格 + output × 出力価格で推定します。モデル名のない token は GPT-5.5 として扱います。"
        case .externalAPICostCalculationHint: return "ローカル api-usage.json から読み取る直接 API 使用コストです。Codex rollout ログとは別扱いです。"
        case .month: return "月"
        case .fiveHourLeft: return "5時間残り"
        case .chinese: return "中国語"
        }
    }
}

private func t(_ key: L10nKey) -> String {
    AppLanguage.current.text(key)
}

private enum CurrencyCode: String, CaseIterable {
    case usd = "USD"
    case eur = "EUR"
    case gbp = "GBP"
    case jpy = "JPY"
    case cny = "CNY"
    case hkd = "HKD"
    case aud = "AUD"
    case cad = "CAD"
    case sgd = "SGD"
    case chf = "CHF"
    case krw = "KRW"
    case twd = "TWD"
    case inr = "INR"
    case aed = "AED"
    case thb = "THB"
    case myr = "MYR"
    case idr = "IDR"
    case php = "PHP"
    case vnd = "VND"
    case rub = "RUB"
    case brl = "BRL"
    case mxn = "MXN"
    case sek = "SEK"
    case nok = "NOK"
    case dkk = "DKK"
    case nzd = "NZD"
    case tryl = "TRY"
    case zar = "ZAR"

    var usdValue: Double {
        switch self {
        case .usd: return 1.0
        case .eur: return 1.09
        case .gbp: return 1.27
        case .jpy: return 0.0064
        case .cny: return 0.138
        case .hkd: return 0.128
        case .aud: return 0.66
        case .cad: return 0.73
        case .sgd: return 0.74
        case .chf: return 1.11
        case .krw: return 0.00073
        case .twd: return 0.031
        case .inr: return 0.012
        case .aed: return 0.272
        case .thb: return 0.027
        case .myr: return 0.21
        case .idr: return 0.000061
        case .php: return 0.017
        case .vnd: return 0.000039
        case .rub: return 0.011
        case .brl: return 0.19
        case .mxn: return 0.055
        case .sek: return 0.095
        case .nok: return 0.093
        case .dkk: return 0.146
        case .nzd: return 0.61
        case .tryl: return 0.026
        case .zar: return 0.054
        }
    }

    var fractionDigits: Int {
        switch self {
        case .jpy, .krw, .vnd, .idr: return 0
        default: return 2
        }
    }

    var displayTitle: String {
        let localized = Locale.current.localizedString(forCurrencyCode: rawValue) ?? rawValue
        return "\(rawValue) - \(localized)"
    }
}

private func convertCurrency(_ amount: Double, from source: CurrencyCode, to target: CurrencyCode) -> Double {
    guard source != target else { return amount }
    return amount * source.usdValue / target.usdValue
}

private enum AppSettings {
    static let logFolderKey = "sessionLogFolder"
    static let monthlyPlanCostKey = "monthlyPlanCost"
    static let paymentCurrencyKey = "paymentCurrency"
    static let displayCurrencyKey = "displayCurrency"
    static let selectedCalendarDayKey = "selectedCalendarDay"
    static let showHistoricalEmptyWeeksKey = "showHistoricalEmptyWeeks"
    static let paymentStartDayKey = "paymentStartDay"
    static let learnedModelLimitIDKey = "learnedModelLimitID"
    static let learnedModelLimitNameKey = "learnedModelLimitName"
    static let quotaWarningsEnabledKey = "quotaWarningsEnabled"
    static let externalAPICostPathKey = "externalAPICostPath"
    static let profileAPITotalsEnabledKey = "profileAPITotalsEnabled"
    static let showCodexStatusEnabledKey = "showCodexStatusEnabled"

    static let fallbackModelLimitID = "codex_bengalfox"
    static let fallbackModelLimitName = "GPT-5.3-Codex-Spark"

    static var defaultCodexHomeURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex", isDirectory: true)
    }

    static var environmentCodexHomeURL: URL? {
        guard let path = ProcessInfo.processInfo.environment["CODEX_HOME"], !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    static var defaultLogFolderURL: URL {
        defaultCodexHomeURL.appendingPathComponent("sessions", isDirectory: true)
    }

    static var defaultArchivedLogFolderURL: URL {
        defaultCodexHomeURL.appendingPathComponent("archived_sessions", isDirectory: true)
    }

    static var hasCustomLogFolder: Bool {
        guard let path = UserDefaults.standard.string(forKey: logFolderKey) else { return false }
        return !path.isEmpty
    }

    static var logFolderURLs: [URL] {
        if hasCustomLogFolder {
            return [logFolderURL]
        }

        var roots = [
            defaultLogFolderURL,
            defaultArchivedLogFolderURL
        ]
        if let codexHome = environmentCodexHomeURL {
            roots.append(codexHome.appendingPathComponent("sessions", isDirectory: true))
            roots.append(codexHome.appendingPathComponent("archived_sessions", isDirectory: true))
        }
        return uniqueDirectoryURLs(roots)
    }

    static var logFolderDisplayPath: String {
        if hasCustomLogFolder {
            return displayPath(for: logFolderURL)
        }
        return logFolderURLs.map { displayPath(for: $0) }.joined(separator: " + ")
    }

    static var logFolderOpenURL: URL {
        if hasCustomLogFolder {
            return logFolderURL
        }
        return logFolderURLs.first { FileManager.default.fileExists(atPath: $0.path) } ?? defaultLogFolderURL
    }

    static var appSupportDirectoryURL: URL {
        if let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return url.appendingPathComponent("Codex Token Meter", isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Codex Token Meter", isDirectory: true)
    }

    static var costHistoryURL: URL {
        appSupportDirectoryURL.appendingPathComponent("cost-history.json")
    }

    static var defaultExternalAPICostURL: URL {
        appSupportDirectoryURL.appendingPathComponent("api-usage.json")
    }

    static var logFolderURL: URL {
        get {
            guard let path = UserDefaults.standard.string(forKey: logFolderKey), !path.isEmpty else {
                return defaultLogFolderURL
            }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        set {
            UserDefaults.standard.set(newValue.path, forKey: logFolderKey)
        }
    }

    static func resetLogFolder() {
        UserDefaults.standard.removeObject(forKey: logFolderKey)
    }

    private static func uniqueDirectoryURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var unique: [URL] = []
        for url in urls {
            let standardized = url.standardizedFileURL
            let key = (standardized.path as NSString).standardizingPath
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            unique.append(standardized)
        }
        return unique
    }

    private static func displayPath(for url: URL) -> String {
        let path = url.path
        let home = NSHomeDirectory()
        if path == home {
            return "~"
        }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    static var monthlyPlanCost: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: monthlyPlanCostKey)
            return stored > 0 ? stored : 200
        }
        set {
            UserDefaults.standard.set(max(0, newValue), forKey: monthlyPlanCostKey)
        }
    }

    static var paymentCurrency: CurrencyCode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: paymentCurrencyKey),
                  let currency = CurrencyCode(rawValue: raw) else {
                return .usd
            }
            return currency
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: paymentCurrencyKey)
        }
    }

    static var displayCurrency: CurrencyCode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: displayCurrencyKey),
                  let currency = CurrencyCode(rawValue: raw) else {
                return paymentCurrency
            }
            return currency
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: displayCurrencyKey)
        }
    }

    static var selectedCalendarDay: String? {
        get {
            let value = UserDefaults.standard.string(forKey: selectedCalendarDayKey)
            return (value?.isEmpty == false) ? value : nil
        }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: selectedCalendarDayKey)
            } else {
                UserDefaults.standard.removeObject(forKey: selectedCalendarDayKey)
            }
        }
    }

    static var showHistoricalEmptyWeeks: Bool {
        get {
            if UserDefaults.standard.object(forKey: showHistoricalEmptyWeeksKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: showHistoricalEmptyWeeksKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: showHistoricalEmptyWeeksKey)
        }
    }

    static var paymentStartDay: String? {
        get {
            let value = UserDefaults.standard.string(forKey: paymentStartDayKey)
            return (value?.isEmpty == false) ? value : nil
        }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: paymentStartDayKey)
            } else {
                UserDefaults.standard.removeObject(forKey: paymentStartDayKey)
            }
        }
    }

    static var modelLimitID: String {
        let value = UserDefaults.standard.string(forKey: learnedModelLimitIDKey)
        return (value?.isEmpty == false) ? value! : fallbackModelLimitID
    }

    static var modelLimitName: String {
        let value = UserDefaults.standard.string(forKey: learnedModelLimitNameKey)
        return (value?.isEmpty == false) ? value! : fallbackModelLimitName
    }

    static var modelLimitSegmentTitle: String {
        modelLimitName.localizedCaseInsensitiveContains("spark") ? t(.spark) : t(.modelLimit)
    }

    static func learnModelLimit(from limits: [LiveRateLimit]) {
        guard let modelLimit = limits.first(where: { $0.id != "codex" }) else { return }
        UserDefaults.standard.set(modelLimit.id, forKey: learnedModelLimitIDKey)
        UserDefaults.standard.set(modelLimit.name, forKey: learnedModelLimitNameKey)
    }

    static var quotaWarningsEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: quotaWarningsEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: quotaWarningsEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: quotaWarningsEnabledKey)
        }
    }

    static var profileAPITotalsEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: profileAPITotalsEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: profileAPITotalsEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: profileAPITotalsEnabledKey)
        }
    }

    static var showCodexStatusEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: showCodexStatusEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: showCodexStatusEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: showCodexStatusEnabledKey)
        }
    }

    static var externalAPICostURL: URL {
        get {
            guard let path = UserDefaults.standard.string(forKey: externalAPICostPathKey), !path.isEmpty else {
                return defaultExternalAPICostURL
            }
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        set {
            UserDefaults.standard.set(newValue.path, forKey: externalAPICostPathKey)
        }
    }
}

private enum LoginItemManager {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                NSLog("Codex Token Meter login item update failed: \(error.localizedDescription)")
            }
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }
}

private enum ExternalAPICostStore {
    static func read(url: URL = AppSettings.externalAPICostURL) -> ExternalAPICostSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let usdValue = double(object["usd_value"])
            ?? double(object["total_usd"])
            ?? double(object["usd"])
            ?? double(object["cost_usd"])
            ?? 0
        let totalTokens = int64(object["total_tokens"])
            ?? int64(object["tokens"])
            ?? int64(object["usage_tokens"])
            ?? 0
        let updatedAt = object["updated_at"] as? String ?? object["updatedAt"] as? String
        return ExternalAPICostSnapshot(
            usdValue: usdValue,
            totalTokens: totalTokens,
            updatedAt: updatedAt,
            sourcePath: url.path
        )
    }

    private static func double(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? Int64 { return Double(value) }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? Double { return Int64(value) }
        if let value = value as? String { return Int64(value) }
        return nil
    }
}

final class QuotaWarningManager {
    static let shared = QuotaWarningManager()

    private let threshold: Double = 15
    private var deliveredKeys = Set<String>()

    private init() {}

    func requestAuthorization() {
        guard AppSettings.quotaWarningsEnabled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func evaluate(limits: [LiveRateLimit]) {
        guard AppSettings.quotaWarningsEnabled else { return }
        for limit in limits {
            evaluate(limit: limit, windowName: "5h", window: limit.primary)
            evaluate(limit: limit, windowName: "weekly", window: limit.secondary)
        }
    }

    private func evaluate(limit: LiveRateLimit, windowName: String, window: RateWindow) {
        let remaining = window.remainingPercent
        guard remaining <= threshold else { return }
        let resetKey = window.resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "no-reset"
        let key = "\(limit.id)|\(windowName)|\(resetKey)|\(Int(threshold))"
        guard !deliveredKeys.contains(key) else { return }
        deliveredKeys.insert(key)

        let content = UNMutableNotificationContent()
        content.title = "Codex quota low"
        content.body = "\(limit.name) \(windowName) remaining \(String(format: "%.0f%%", remaining))"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "codex-token-meter-\(key)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

enum QuotaViewOption: String, CaseIterable {
    case all = "codex"
    case other
    case spark

    var scanLimitID: String? {
        switch self {
        case .all, .other: return nil
        case .spark: return AppSettings.modelLimitID
        }
    }

    var excludedScanLimitID: String? {
        switch self {
        case .all, .spark: return nil
        case .other: return AppSettings.modelLimitID
        }
    }

    var includedModelName: String? {
        switch self {
        case .spark: return AppSettings.modelLimitName.lowercased()
        case .all, .other: return nil
        }
    }

    var excludedModelName: String? {
        switch self {
        case .other: return AppSettings.modelLimitName.lowercased()
        case .all, .spark: return nil
        }
    }

    var liveLimitID: String {
        switch self {
        case .all, .other: return "codex"
        case .spark: return AppSettings.modelLimitID
        }
    }

    var shortTitle: String {
        switch self {
        case .all: return t(.all)
        case .spark: return AppSettings.modelLimitSegmentTitle
        case .other: return t(.other)
        }
    }

    var fallbackTitle: String {
        switch self {
        case .all: return t(.codexAppTotal)
        case .spark: return AppSettings.modelLimitName
        case .other: return t(.nonSparkUsage)
        }
    }
}

struct RateWindow {
    let usedPercent: Double
    let windowMinutes: Int
    let resetsAt: Date?

    var remainingPercent: Double { max(0, 100 - usedPercent) }
}

private enum PaceStatus {
    case ahead
    case behind
}

private struct PaceComparison {
    let progressPercent: Double
    let usedPercent: Double
    let status: PaceStatus
}

fileprivate struct RingRemainingComparison {
    let expectedRemainingPercent: Double
    let actualRemainingPercent: Double
    let status: PaceStatus
}

private func paceComparison(for window: RateWindow, now: Date = Date()) -> PaceComparison? {
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

private func localizedCodexStatus(_ status: String) -> String {
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

private func codexStatusColor(_ status: String) -> NSColor {
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
            NSLog("Codex Token Meter failed to save cost history: \(error)")
        }
    }
}

private extension JSONEncoder {
    static var prettySorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private func costEstimateLimit(from limits: [LiveRateLimit]) -> LiveRateLimit? {
    limits.first { $0.id == QuotaViewOption.all.liveLimitID }
}

private func profileReportWithLocalFallback(_ profileReport: TokenReport, localReport: TokenReport?) -> TokenReport {
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

    init?(report: TokenReport, limit: LiveRateLimit?, quotaReferenceReport: TokenReport? = nil) {
        let monthlyCost = AppSettings.monthlyPlanCost
        guard monthlyCost > 0 else { return nil }
        let startDay = effectivePaymentStartDay(in: report)
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

struct ReportCacheKey: Hashable {
    let window: WindowOption
    let quota: QuotaViewOption
}

final class CodexTokenScanner {
    private struct FileModelAggregate: Codable {
        let name: String
        var usage: Usage
        var events: Int
    }

    private struct FileDayAggregate: Codable {
        let day: String
        var usage: Usage
        var turns: Int
        var models: [FileModelAggregate]
    }

    private struct FileCache {
        let size: Int64
        let modifiedAt: Date
        let events: [TokenEvent]
        let turns: [Date]
        let days: [FileDayAggregate]
    }

    private struct DiskFileCache: Codable {
        let version: Int
        let path: String
        let size: Int64
        let modifiedAt: Double
        let events: [TokenEvent]
        let turns: [Date]
        let days: [FileDayAggregate]
    }

    private struct LegacyDiskFileCache: Codable {
        let version: Int
        let path: String
        let size: Int64
        let modifiedAt: Double
        let events: [TokenEvent]
        let turns: [Date]
    }

    private let rootURLs: [URL]
    private let cacheDirectory: URL
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()
    private let isoFormatter: ISO8601DateFormatter
    private let dayFormatter: DateFormatter
    private let calendar: Calendar
    private let eventMsgPattern = Array(#""type":"event_msg""#.utf8)
    private let turnContextPattern = Array(#""type":"turn_context""#.utf8)
    private let taskStartedPattern = Array(#""type":"task_started""#.utf8)
    private let tokenCountPattern = Array(#""type":"token_count""#.utf8)
    private let rateLimitsPattern = Array(#""rate_limits""#.utf8)
    private let timestampKey = Array(#""timestamp":""#.utf8)
    private let inputKey = Array(#""input_tokens":"#.utf8)
    private let cachedInputKey = Array(#""cached_input_tokens":"#.utf8)
    private let outputKey = Array(#""output_tokens":"#.utf8)
    private let reasoningOutputKey = Array(#""reasoning_output_tokens":"#.utf8)
    private let totalKey = Array(#""total_tokens":"#.utf8)
    private let limitIDKey = Array(#""limit_id":""#.utf8)
    private let limitNameKey = Array(#""limit_name":""#.utf8)
    private let modelKey = Array(#""model":""#.utf8)
    private var cache: [String: FileCache] = [:]

    convenience init(rootURL: URL) {
        self.init(rootURLs: [rootURL])
    }

    init(rootURLs: [URL]) {
        self.rootURLs = Self.uniqueRootURLs(rootURLs)
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        self.cacheDirectory = applicationSupport
            .appendingPathComponent("Codex Token Meter", isDirectory: true)
            .appendingPathComponent("ParsedRollouts", isDirectory: true)
        self.isoFormatter = ISO8601DateFormatter()
        self.isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.dayFormatter = DateFormatter()
        self.dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        self.dayFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        self.dayFormatter.dateFormat = "yyyy-MM-dd"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        self.calendar = calendar
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    var rootPaths: [String] {
        rootURLs.map(\.path)
    }

    private static func uniqueRootURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var unique: [URL] = []
        for url in urls {
            let standardized = url.standardizedFileURL
            let key = (standardized.path as NSString).standardizingPath
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            unique.append(standardized)
        }
        return unique
    }

    func scan(window: WindowOption, limitID: String? = nil, excludedLimitID: String? = nil, includedModelName: String? = nil, excludedModelName: String? = nil) -> TokenReport {
        let now = Date()
        switch window {
        case .day:
            return scan(start: now.addingTimeInterval(-24 * 3600), now: now, limitID: limitID, excludedLimitID: excludedLimitID, includedModelName: includedModelName, excludedModelName: excludedModelName, fillDayCount: nil)
        case .week:
            let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -6, to: now) ?? now)
            return scan(start: start, now: now, limitID: limitID, excludedLimitID: excludedLimitID, includedModelName: includedModelName, excludedModelName: excludedModelName, fillDayCount: 7)
        case .month:
            let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -29, to: now) ?? now)
            return scan(start: start, now: now, limitID: limitID, excludedLimitID: excludedLimitID, includedModelName: includedModelName, excludedModelName: excludedModelName, fillDayCount: 30)
        }
    }

    func scan(hours: Int, limitID: String? = nil, excludedLimitID: String? = nil, includedModelName: String? = nil, excludedModelName: String? = nil) -> TokenReport {
        let now = Date()
        let start = now.addingTimeInterval(TimeInterval(-hours * 3600))
        return scan(start: start, now: now, limitID: limitID, excludedLimitID: excludedLimitID, includedModelName: includedModelName, excludedModelName: excludedModelName, fillDayCount: nil)
    }

    func scan(days: Int, limitID: String? = nil, excludedLimitID: String? = nil, includedModelName: String? = nil, excludedModelName: String? = nil) -> TokenReport {
        let now = Date()
        let dayCount = max(days, 1)
        let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -(dayCount - 1), to: now) ?? now)
        return scan(start: start, now: now, limitID: limitID, excludedLimitID: excludedLimitID, includedModelName: includedModelName, excludedModelName: excludedModelName, fillDayCount: dayCount)
    }

    func scan(from start: Date, to now: Date = Date(), limitID: String? = nil, excludedLimitID: String? = nil, includedModelName: String? = nil, excludedModelName: String? = nil) -> TokenReport {
        scan(start: start, now: now, limitID: limitID, excludedLimitID: excludedLimitID, includedModelName: includedModelName, excludedModelName: excludedModelName, fillDayCount: nil)
    }

    private func scan(start: Date, now: Date, limitID: String?, excludedLimitID: String?, includedModelName: String?, excludedModelName: String?, fillDayCount: Int?) -> TokenReport {
        if limitID == nil, excludedLimitID == nil, fillDayCount != nil {
            return scanDayAggregates(start: start, now: now, includedModelName: includedModelName, excludedModelName: excludedModelName, fillDayCount: fillDayCount)
        }

        var report = TokenReport(scannedAt: now)
        var dayBuckets: [String: Usage] = [:]
        var dayTurns: [String: Int] = [:]
        var dayModelBuckets: [String: [String: Usage]] = [:]
        var dayModelEvents: [String: [String: Int]] = [:]
        var dayModelSessions: [String: [String: Int]] = [:]
        var hourBuckets: [Date: Usage] = [:]
        var hourTurns: [Date: Int] = [:]
        var modelBuckets: [String: Usage] = [:]
        var modelEvents: [String: Int] = [:]
        var modelSessions: [String: Int] = [:]
        var sessions: [SessionUsage] = []

        for fileURL in rolloutFiles(modifiedSince: start) {
            let file = cachedFile(fileURL)
            let isUnfilteredScan = limitID == nil && excludedLimitID == nil && includedModelName == nil && excludedModelName == nil
            let events = file.events.filter {
                $0.timestamp >= start
                    && $0.timestamp <= now
                    && matchesLimit($0, limitID: limitID)
                    && !matchesExcludedLimit($0, excludedLimitID: excludedLimitID)
                    && matchesModel($0, modelName: includedModelName)
                    && !matchesExcludedModel($0, modelName: excludedModelName)
            }
            let rawTurns = file.turns.filter { $0 >= start && $0 <= now }
            let turns = isUnfilteredScan ? rawTurns : events.map { $0.timestamp }
            guard !events.isEmpty || !turns.isEmpty else { continue }

            var sessionUsage = Usage()
            var lastEvent = file.events.last?.timestamp ?? now
            var sessionModels = Set<String>()
            var sessionDayModels: [String: Set<String>] = [:]
            for event in events {
                sessionUsage.add(event.usage)
                lastEvent = event.timestamp
                if let limitName = event.limitName {
                    report.limitNames.insert(limitName)
                }
                let modelName = modelDisplayName(for: event)
                var modelUsage = modelBuckets[modelName] ?? Usage()
                modelUsage.add(event.usage)
                modelBuckets[modelName] = modelUsage
                modelEvents[modelName, default: 0] += 1
                sessionModels.insert(modelName)

                let day = dayFormatter.string(from: event.timestamp)
                sessionDayModels[day, default: []].insert(modelName)
                var usage = dayBuckets[day] ?? Usage()
                usage.add(event.usage)
                dayBuckets[day] = usage
                var dayModels = dayModelBuckets[day] ?? [:]
                var dayModelUsage = dayModels[modelName] ?? Usage()
                dayModelUsage.add(event.usage)
                dayModels[modelName] = dayModelUsage
                dayModelBuckets[day] = dayModels
                var dayEvents = dayModelEvents[day] ?? [:]
                dayEvents[modelName, default: 0] += 1
                dayModelEvents[day] = dayEvents

                let hour = calendar.dateInterval(of: .hour, for: event.timestamp)?.start ?? event.timestamp
                var hourUsage = hourBuckets[hour] ?? Usage()
                hourUsage.add(event.usage)
                hourBuckets[hour] = hourUsage
            }

            for turn in turns {
                dayTurns[dayFormatter.string(from: turn), default: 0] += 1
                let hour = calendar.dateInterval(of: .hour, for: turn)?.start ?? turn
                hourTurns[hour, default: 0] += 1
            }

            if isUnfilteredScan || !events.isEmpty {
                report.sessions += 1
                report.events += events.count
                report.turns += turns.count
                report.usage.add(sessionUsage)
                sessions.append(SessionUsage(path: fileURL.path, lastEvent: lastEvent, turns: turns.count, usage: sessionUsage))
                for model in sessionModels {
                    modelSessions[model, default: 0] += 1
                }
                for (day, models) in sessionDayModels {
                    var sessionsForDay = dayModelSessions[day] ?? [:]
                    for model in models {
                        sessionsForDay[model, default: 0] += 1
                    }
                    dayModelSessions[day] = sessionsForDay
                }
            }
        }

        let days: Set<String>
        if let fillDayCount {
            days = Set((0..<fillDayCount).compactMap { offset in
                calendar.date(byAdding: .day, value: offset, to: start).map { dayFormatter.string(from: $0) }
            })
        } else {
            days = Set(dayBuckets.keys).union(dayTurns.keys)
        }
        report.byDay = days
            .map { day in
                let models = (dayModelBuckets[day] ?? [:]).map { name, usage in
                    ModelUsage(
                        name: name,
                        usage: usage,
                        events: dayModelEvents[day]?[name] ?? 0,
                        sessions: dayModelSessions[day]?[name] ?? 0
                    )
                }
                .sorted { $0.usage.total > $1.usage.total }
                return DayUsage(day: day, usage: dayBuckets[day] ?? Usage(), turns: dayTurns[day] ?? 0, modelBreakdown: models)
            }
            .sorted { $0.day < $1.day }
        let hours = Set(hourBuckets.keys).union(hourTurns.keys)
        report.byHour = hours
            .map { HourUsage(hour: $0, usage: hourBuckets[$0] ?? Usage(), turns: hourTurns[$0] ?? 0) }
            .sorted { $0.hour < $1.hour }
        report.topSessions = sessions.sorted { $0.usage.total > $1.usage.total }.prefix(8).map { $0 }
        report.modelBreakdown = modelBuckets.map { name, usage in
            ModelUsage(name: name, usage: usage, events: modelEvents[name] ?? 0, sessions: modelSessions[name] ?? 0)
        }
        .sorted { $0.usage.total > $1.usage.total }
        return report
    }

    private func scanDayAggregates(start: Date, now: Date, includedModelName: String?, excludedModelName: String?, fillDayCount: Int?) -> TokenReport {
        var report = TokenReport(scannedAt: now)
        let startDay = dayFormatter.string(from: start)
        let endDay = dayFormatter.string(from: now)
        let isUnfilteredScan = includedModelName == nil && excludedModelName == nil
        var dayBuckets: [String: Usage] = [:]
        var dayTurns: [String: Int] = [:]
        var dayModelBuckets: [String: [String: Usage]] = [:]
        var dayModelEvents: [String: [String: Int]] = [:]
        var dayModelSessions: [String: [String: Int]] = [:]
        var modelBuckets: [String: Usage] = [:]
        var modelEvents: [String: Int] = [:]
        var modelSessions: [String: Int] = [:]
        var sessions: [SessionUsage] = []

        for fileURL in rolloutFiles(modifiedSince: start) {
            let file = cachedFile(fileURL)
            var sessionUsage = Usage()
            var sessionTurns = 0
            var lastEvent = now
            var hasLastEvent = false
            var sessionModels = Set<String>()
            var sessionDayModels: [String: Set<String>] = [:]

            for day in file.days where day.day >= startDay && day.day <= endDay {
                let matchingModels = day.models.filter {
                    matchesAggregateModel($0.name, includedModelName: includedModelName, excludedModelName: excludedModelName)
                }
                let dayUsage: Usage
                let selectedTurns: Int
                if isUnfilteredScan {
                    dayUsage = day.usage
                    selectedTurns = day.turns
                } else {
                    dayUsage = matchingModels.reduce(Usage()) { partial, model in
                        var next = partial
                        next.add(model.usage)
                        return next
                    }
                    selectedTurns = matchingModels.reduce(0) { $0 + $1.events }
                }
                guard dayUsage.total > 0 || dayUsage.input > 0 || dayUsage.output > 0 || selectedTurns > 0 else {
                    continue
                }

                sessionUsage.add(dayUsage)
                sessionTurns += selectedTurns
                dayTurns[day.day, default: 0] += selectedTurns
                var usage = dayBuckets[day.day] ?? Usage()
                usage.add(dayUsage)
                dayBuckets[day.day] = usage
                if let date = dayFormatter.date(from: day.day) {
                    lastEvent = date
                    hasLastEvent = true
                }

                for model in matchingModels {
                    let modelName = model.name
                    sessionModels.insert(modelName)
                    sessionDayModels[day.day, default: []].insert(modelName)
                    var totalModelUsage = modelBuckets[modelName] ?? Usage()
                    totalModelUsage.add(model.usage)
                    modelBuckets[modelName] = totalModelUsage
                    modelEvents[modelName, default: 0] += model.events

                    var dayModels = dayModelBuckets[day.day] ?? [:]
                    var dayModelUsage = dayModels[modelName] ?? Usage()
                    dayModelUsage.add(model.usage)
                    dayModels[modelName] = dayModelUsage
                    dayModelBuckets[day.day] = dayModels

                    var dayEvents = dayModelEvents[day.day] ?? [:]
                    dayEvents[modelName, default: 0] += model.events
                    dayModelEvents[day.day] = dayEvents
                }
            }

            guard sessionUsage.total > 0 || sessionUsage.input > 0 || sessionUsage.output > 0 || sessionTurns > 0 else {
                continue
            }
            report.sessions += 1
            report.events += isUnfilteredScan ? file.days
                .filter { $0.day >= startDay && $0.day <= endDay }
                .reduce(0) { $0 + $1.models.reduce(0) { $0 + $1.events } } : sessionTurns
            report.turns += sessionTurns
            report.usage.add(sessionUsage)
            sessions.append(SessionUsage(path: fileURL.path, lastEvent: hasLastEvent ? lastEvent : now, turns: sessionTurns, usage: sessionUsage))
            for model in sessionModels {
                modelSessions[model, default: 0] += 1
            }
            for (day, models) in sessionDayModels {
                var sessionsForDay = dayModelSessions[day] ?? [:]
                for model in models {
                    sessionsForDay[model, default: 0] += 1
                }
                dayModelSessions[day] = sessionsForDay
            }
        }

        let days: Set<String>
        if let fillDayCount {
            days = Set((0..<fillDayCount).compactMap { offset in
                calendar.date(byAdding: .day, value: offset, to: start).map { dayFormatter.string(from: $0) }
            })
        } else {
            days = Set(dayBuckets.keys).union(dayTurns.keys)
        }
        report.byDay = days
            .map { day in
                let models = (dayModelBuckets[day] ?? [:]).map { name, usage in
                    ModelUsage(
                        name: name,
                        usage: usage,
                        events: dayModelEvents[day]?[name] ?? 0,
                        sessions: dayModelSessions[day]?[name] ?? 0
                    )
                }
                .sorted { $0.usage.total > $1.usage.total }
                return DayUsage(day: day, usage: dayBuckets[day] ?? Usage(), turns: dayTurns[day] ?? 0, modelBreakdown: models)
            }
            .sorted { $0.day < $1.day }
        report.topSessions = sessions.sorted { $0.usage.total > $1.usage.total }.prefix(8).map { $0 }
        report.modelBreakdown = modelBuckets.map { name, usage in
            ModelUsage(name: name, usage: usage, events: modelEvents[name] ?? 0, sessions: modelSessions[name] ?? 0)
        }
        .sorted { $0.usage.total > $1.usage.total }
        return report
    }

    private func matchesAggregateModel(_ value: String, includedModelName: String?, excludedModelName: String?) -> Bool {
        if let includedModelName, !modelNameMatches(value.lowercased(), target: includedModelName) {
            return false
        }
        if let excludedModelName, modelNameMatches(value.lowercased(), target: excludedModelName) {
            return false
        }
        return true
    }

    private func modelDisplayName(for event: TokenEvent) -> String {
        if let model = event.model, !model.isEmpty {
            return model
        }
        if event.limitID == AppSettings.modelLimitID {
            return AppSettings.modelLimitName
        }
        if let limitName = event.limitName,
           limitName.localizedCaseInsensitiveContains(AppSettings.modelLimitName) {
            return AppSettings.modelLimitName
        }
        return event.limitID ?? "Unknown model"
    }

    private func matchesLimit(_ event: TokenEvent, limitID: String?) -> Bool {
        guard let limitID else { return true }
        if event.limitID == limitID {
            return true
        }
        guard let limitName = event.limitName else {
            return false
        }
        return limitName == limitID || limitName.hasPrefix("\(limitID) ")
    }

    private func matchesExcludedLimit(_ event: TokenEvent, excludedLimitID: String?) -> Bool {
        guard let excludedLimitID else { return false }
        return matchesLimit(event, limitID: excludedLimitID)
    }

    private func matchesModel(_ event: TokenEvent, modelName: String?) -> Bool {
        guard let modelName else { return true }
        return modelNameMatches(normalizedModelName(for: event), target: modelName)
    }

    private func matchesExcludedModel(_ event: TokenEvent, modelName: String?) -> Bool {
        guard let modelName else { return false }
        return modelNameMatches(normalizedModelName(for: event), target: modelName)
    }

    private func normalizedModelName(for event: TokenEvent) -> String {
        modelDisplayName(for: event).lowercased()
    }

    private func modelNameMatches(_ value: String, target: String) -> Bool {
        let normalizedTarget = target.lowercased()
        return value == normalizedTarget
            || value.contains(normalizedTarget)
            || normalizedTarget.contains(value)
    }

    private func rolloutFiles(modifiedSince start: Date) -> [URL] {
        var files: [URL] = []
        var seen = Set<String>()

        for rootURL in rootURLs {
            for url in rolloutFiles(in: rootURL, modifiedSince: start) {
                let key = (url.path as NSString).standardizingPath
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                files.append(url)
            }
        }

        return files.sorted { $0.path < $1.path }
    }

    private func rolloutFiles(in rootURL: URL, modifiedSince start: Date) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL else { return nil }
            guard url.lastPathComponent.hasPrefix("rollout-"), url.pathExtension == "jsonl" else { return nil }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if let modifiedAt = values?.contentModificationDate, modifiedAt < start {
                return nil
            }
            return url
        }
    }

    private func cachedFile(_ fileURL: URL) -> FileCache {
        let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modifiedAt = values?.contentModificationDate ?? .distantPast
        let size = Int64(values?.fileSize ?? 0)
        let key = fileURL.path

        if let cached = cache[key], cached.modifiedAt == modifiedAt, cached.size == size {
            return cached
        }

        if let cached = readDiskCache(fileURL: fileURL, size: size, modifiedAt: modifiedAt) {
            cache[key] = cached
            return cached
        }

        let parsed = parse(fileURL: fileURL)
        let file = FileCache(
            size: size,
            modifiedAt: modifiedAt,
            events: parsed.events,
            turns: parsed.turns,
            days: dayAggregates(events: parsed.events, turns: parsed.turns)
        )
        cache[key] = file
        writeDiskCache(file, fileURL: fileURL)
        return file
    }

    private func readDiskCache(fileURL: URL, size: Int64, modifiedAt: Date) -> FileCache? {
        let url = diskCacheURL(for: fileURL)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        if let disk = try? jsonDecoder.decode(DiskFileCache.self, from: data),
              disk.version == 3,
              disk.path == fileURL.path,
              disk.size == size,
              abs(disk.modifiedAt - modifiedAt.timeIntervalSinceReferenceDate) < 0.001 {
            return FileCache(size: disk.size, modifiedAt: modifiedAt, events: disk.events, turns: disk.turns, days: disk.days)
        }

        if let legacy = try? jsonDecoder.decode(LegacyDiskFileCache.self, from: data),
           legacy.version == 2,
           legacy.path == fileURL.path,
           legacy.size == size,
           abs(legacy.modifiedAt - modifiedAt.timeIntervalSinceReferenceDate) < 0.001 {
            let file = FileCache(
                size: legacy.size,
                modifiedAt: modifiedAt,
                events: legacy.events,
                turns: legacy.turns,
                days: dayAggregates(events: legacy.events, turns: legacy.turns)
            )
            writeDiskCache(file, fileURL: fileURL)
            return file
        }

        return nil
    }

    private func writeDiskCache(_ file: FileCache, fileURL: URL) {
        let disk = DiskFileCache(
            version: 3,
            path: fileURL.path,
            size: file.size,
            modifiedAt: file.modifiedAt.timeIntervalSinceReferenceDate,
            events: file.events,
            turns: file.turns,
            days: file.days
        )
        guard let data = try? jsonEncoder.encode(disk) else { return }
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: diskCacheURL(for: fileURL), options: [.atomic])
    }

    private func dayAggregates(events: [TokenEvent], turns: [Date]) -> [FileDayAggregate] {
        var dayBuckets: [String: Usage] = [:]
        var dayTurns: [String: Int] = [:]
        var dayModelBuckets: [String: [String: Usage]] = [:]
        var dayModelEvents: [String: [String: Int]] = [:]

        for turn in turns {
            dayTurns[dayFormatter.string(from: turn), default: 0] += 1
        }

        for event in events {
            let day = dayFormatter.string(from: event.timestamp)
            var usage = dayBuckets[day] ?? Usage()
            usage.add(event.usage)
            dayBuckets[day] = usage

            let modelName = modelDisplayName(for: event)
            var dayModels = dayModelBuckets[day] ?? [:]
            var modelUsage = dayModels[modelName] ?? Usage()
            modelUsage.add(event.usage)
            dayModels[modelName] = modelUsage
            dayModelBuckets[day] = dayModels

            var modelEvents = dayModelEvents[day] ?? [:]
            modelEvents[modelName, default: 0] += 1
            dayModelEvents[day] = modelEvents
        }

        return Set(dayBuckets.keys).union(dayTurns.keys)
            .map { day in
                let models = (dayModelBuckets[day] ?? [:])
                    .map { name, usage in
                        FileModelAggregate(name: name, usage: usage, events: dayModelEvents[day]?[name] ?? 0)
                    }
                    .sorted { $0.usage.total > $1.usage.total }
                return FileDayAggregate(day: day, usage: dayBuckets[day] ?? Usage(), turns: dayTurns[day] ?? 0, models: models)
            }
            .sorted { $0.day < $1.day }
    }

    private func diskCacheURL(for fileURL: URL) -> URL {
        cacheDirectory.appendingPathComponent("\(fnv1a64(fileURL.path)).json")
    }

    private func fnv1a64(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    private func parse(fileURL: URL) -> (events: [TokenEvent], turns: [Date]) {
        guard let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]) else {
            return ([], [])
        }

        var previousTotal = Usage()
        var events: [TokenEvent] = []
        var turns: [Date] = []
        var currentModel: String?

        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            let count = rawBuffer.count
            var lineStart = 0

            func handleLine(_ lineEnd: Int) {
                guard lineEnd > lineStart else { return }
                let range = lineStart..<lineEnd
                guard let timestampString = self.extractString(base, range: range, key: self.timestampKey),
                      let timestamp = self.parseDate(timestampString) else {
                    return
                }

                if self.contains(base, range: range, pattern: self.turnContextPattern),
                   let model = self.extractString(base, range: range, key: self.modelKey),
                   !model.isEmpty {
                    currentModel = model
                    return
                }

                guard self.contains(base, range: range, pattern: self.eventMsgPattern) else {
                    return
                }

                if self.contains(base, range: range, pattern: self.taskStartedPattern) {
                    turns.append(timestamp)
                    return
                }

                guard self.contains(base, range: range, pattern: self.tokenCountPattern) else {
                    return
                }

                let currentTotal = Usage(
                    input: self.extractInt64(base, range: range, key: self.inputKey),
                    cachedInput: self.extractInt64(base, range: range, key: self.cachedInputKey),
                    output: self.extractInt64(base, range: range, key: self.outputKey),
                    reasoningOutput: self.extractInt64(base, range: range, key: self.reasoningOutputKey),
                    total: self.extractInt64(base, range: range, key: self.totalKey)
                )
                let delta = Usage.delta(from: previousTotal, to: currentTotal)
                previousTotal = currentTotal
                guard delta.total > 0 || delta.input > 0 || delta.output > 0 else {
                    return
                }

                var limitID: String?
                var limitName: String?
                if self.contains(base, range: range, pattern: self.rateLimitsPattern) {
                    limitID = self.extractString(base, range: range, key: self.limitIDKey) ?? "unknown"
                    if let name = self.extractString(base, range: range, key: self.limitNameKey), !name.isEmpty {
                        limitName = "\(limitID ?? "unknown") (\(name))"
                    } else {
                        limitName = limitID
                    }
                }

                events.append(TokenEvent(timestamp: timestamp, usage: delta, limitID: limitID, limitName: limitName, model: currentModel))
            }

            for index in 0..<count {
                if base[index] == 10 {
                    handleLine(index)
                    lineStart = index + 1
                }
            }
            if lineStart < count {
                handleLine(count)
            }
        }

        return (events, turns)
    }

    private func contains(_ base: UnsafePointer<UInt8>, range: Range<Int>, pattern: [UInt8]) -> Bool {
        find(base, range: range, pattern: pattern) != nil
    }

    private func find(_ base: UnsafePointer<UInt8>, range: Range<Int>, pattern: [UInt8]) -> Int? {
        guard !pattern.isEmpty, range.count >= pattern.count else { return nil }
        let lastStart = range.upperBound - pattern.count
        var index = range.lowerBound
        while index <= lastStart {
            if base[index] == pattern[0] {
                var matched = true
                for offset in 1..<pattern.count where base[index + offset] != pattern[offset] {
                    matched = false
                    break
                }
                if matched { return index }
            }
            index += 1
        }
        return nil
    }

    private func extractString(_ base: UnsafePointer<UInt8>, range: Range<Int>, key: [UInt8]) -> String? {
        guard let keyIndex = find(base, range: range, pattern: key) else { return nil }
        let start = keyIndex + key.count
        var end = start
        while end < range.upperBound, base[end] != 34 {
            end += 1
        }
        guard end > start, end < range.upperBound else { return nil }
        return String(decoding: UnsafeBufferPointer(start: base + start, count: end - start), as: UTF8.self)
    }

    private func extractInt64(_ base: UnsafePointer<UInt8>, range: Range<Int>, key: [UInt8]) -> Int64 {
        guard let keyIndex = find(base, range: range, pattern: key) else { return 0 }
        var index = keyIndex + key.count
        var value: Int64 = 0
        var found = false
        while index < range.upperBound {
            let byte = base[index]
            guard byte >= 48, byte <= 57 else { break }
            value = value * 10 + Int64(byte - 48)
            found = true
            index += 1
        }
        return found ? value : 0
    }

    private func extractString(_ line: String, key: String) -> String? {
        guard let keyRange = line.range(of: key) else { return nil }
        let start = keyRange.upperBound
        guard let end = line[start...].firstIndex(of: "\"") else { return nil }
        return String(line[start..<end])
    }

    private func extractInt64(_ line: String, key: String) -> Int64 {
        guard let keyRange = line.range(of: key) else { return 0 }
        var index = keyRange.upperBound
        var value = ""
        while index < line.endIndex {
            let char = line[index]
            if char < "0" || char > "9" {
                break
            }
            value.append(char)
            index = line.index(after: index)
        }
        return Int64(value) ?? 0
    }

    private func jsonObject(from line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private func parseDate(_ value: String) -> Date? {
        if let date = isoFormatter.date(from: value) {
            return date
        }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: value)
    }

    private func usage(from dict: [String: Any]) -> Usage {
        Usage(
            input: int64(dict["input_tokens"]),
            cachedInput: int64(dict["cached_input_tokens"]),
            output: int64(dict["output_tokens"]),
            reasoningOutput: int64(dict["reasoning_output_tokens"]),
            total: int64(dict["total_tokens"])
        )
    }

    private func int64(_ value: Any?) -> Int64 {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? Double { return Int64(value) }
        if let value = value as? String { return Int64(value) ?? 0 }
        return 0
    }
}

final class LiveRateLimitReader {
    func read(timeout: TimeInterval = 12) -> [LiveRateLimit] {
        guard let codexPath = Self.codexExecutablePath() else {
            return []
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server"]
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
        } catch {
            return []
        }

        let outputLock = NSLock()
        var outputData = Data()
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            outputLock.lock()
            outputData.append(chunk)
            outputLock.unlock()
        }

        let errorLock = NSLock()
        var errorData = Data()
        error.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            errorLock.lock()
            errorData.append(chunk)
            errorLock.unlock()
        }

        let writer = input.fileHandleForWriting
        let messages = [
            #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"codex-token-meter","version":"0.2.0"},"capabilities":{}}}"#,
            #"{"method":"initialized"}"#,
            #"{"id":2,"method":"account/read","params":{"refreshAuth":false}}"#,
            #"{"id":3,"method":"account/rateLimits/read"}"#
        ]
        let requestBody = messages.joined(separator: "\n") + "\n"
        if let data = requestBody.data(using: .utf8) {
            writer.write(data)
        }

        let deadline = Date().addingTimeInterval(timeout)
        let rateLimitsMarker = Data(#""rateLimits""#.utf8)
        while process.isRunning && Date() < deadline {
            outputLock.lock()
            let hasRateLimits = outputData.range(of: rateLimitsMarker) != nil
            outputLock.unlock()
            if hasRateLimits {
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        try? writer.close()
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.2)
        }

        output.fileHandleForReading.readabilityHandler = nil
        error.fileHandleForReading.readabilityHandler = nil
        outputLock.lock()
        let data = outputData
        outputLock.unlock()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        if ProcessInfo.processInfo.environment["CODEX_TOKEN_METER_DEBUG_LIVE"] == "1" {
            errorLock.lock()
            let errorData = errorData
            errorLock.unlock()
            let errorText = String(data: errorData, encoding: .utf8) ?? ""
            FileHandle.standardError.write(Data("LIVE RAW OUTPUT:\n\(text)\n".utf8))
            FileHandle.standardError.write(Data("LIVE RAW ERROR:\n\(errorText)\n".utf8))
        }
        return parse(text)
    }

    static func codexExecutablePath() -> String? {
        let candidates = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func parse(_ text: String) -> [LiveRateLimit] {
        var results: [LiveRateLimit] = []
        for line in text.split(separator: "\n") {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = object["result"] as? [String: Any] else {
                continue
            }
            guard result["rateLimits"] != nil || result["rateLimitsByLimitId"] != nil else {
                continue
            }

            if let byID = result["rateLimitsByLimitId"] as? [String: Any] {
                for (_, value) in byID {
                    if let dict = value as? [String: Any], let limit = liveLimit(from: dict) {
                        results.append(limit)
                    }
                }
            } else if let dict = result["rateLimits"] as? [String: Any], let limit = liveLimit(from: dict) {
                results.append(limit)
            }
        }
        return results.sorted { $0.id < $1.id }
    }

    private func liveLimit(from dict: [String: Any]) -> LiveRateLimit? {
        guard let id = dict["limitId"] as? String ?? dict["limit_id"] as? String,
              let primaryDict = dict["primary"] as? [String: Any],
              let secondaryDict = dict["secondary"] as? [String: Any] else {
            return nil
        }

        let name = dict["limitName"] as? String ?? dict["limit_name"] as? String ?? id
        return LiveRateLimit(
            id: id,
            name: name,
            primary: window(from: primaryDict),
            secondary: window(from: secondaryDict),
            planType: dict["planType"] as? String ?? dict["plan_type"] as? String
        )
    }

    private func window(from dict: [String: Any]) -> RateWindow {
        let used = double(dict["usedPercent"] ?? dict["used_percent"])
        let minutes = Int(double(dict["windowDurationMins"] ?? dict["window_minutes"]))
        let resetSeconds = double(dict["resetsAt"] ?? dict["resets_at"])
        let resetDate = resetSeconds > 0 ? Date(timeIntervalSince1970: resetSeconds) : nil
        return RateWindow(usedPercent: used, windowMinutes: minutes, resetsAt: resetDate)
    }

    private func double(_ value: Any?) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? Int64 { return Double(value) }
        if let value = value as? String { return Double(value) ?? 0 }
        return 0
    }
}

final class AccountUsageReader {
    func read(timeout: TimeInterval = 12) -> AccountUsageSnapshot? {
        guard let codexPath = LiveRateLimitReader.codexExecutablePath() else {
            return nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server"]
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
        } catch {
            return nil
        }

        let outputLock = NSLock()
        var outputData = Data()
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            outputLock.lock()
            outputData.append(chunk)
            outputLock.unlock()
        }

        let errorLock = NSLock()
        var errorData = Data()
        error.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            errorLock.lock()
            errorData.append(chunk)
            errorLock.unlock()
        }

        let writer = input.fileHandleForWriting
        let messages = [
            #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"codex-token-meter","version":"0.2.0"},"capabilities":{"experimentalApi":true}}}"#,
            #"{"method":"initialized"}"#,
            #"{"id":2,"method":"account/read","params":{"refreshAuth":false}}"#,
            #"{"id":3,"method":"account/usage/read"}"#
        ]
        let requestBody = messages.joined(separator: "\n") + "\n"
        if let data = requestBody.data(using: .utf8) {
            writer.write(data)
        }

        let deadline = Date().addingTimeInterval(timeout)
        let usageMarker = Data(#""dailyUsageBuckets""#.utf8)
        while process.isRunning && Date() < deadline {
            outputLock.lock()
            let hasUsage = outputData.range(of: usageMarker) != nil
            outputLock.unlock()
            if hasUsage {
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        try? writer.close()
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.2)
        }

        output.fileHandleForReading.readabilityHandler = nil
        error.fileHandleForReading.readabilityHandler = nil
        outputLock.lock()
        let data = outputData
        outputLock.unlock()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        if ProcessInfo.processInfo.environment["CODEX_TOKEN_METER_DEBUG_PROFILE"] == "1" {
            errorLock.lock()
            let errorData = errorData
            errorLock.unlock()
            let errorText = String(data: errorData, encoding: .utf8) ?? ""
            FileHandle.standardError.write(Data("PROFILE RAW OUTPUT:\n\(text)\n".utf8))
            FileHandle.standardError.write(Data("PROFILE RAW ERROR:\n\(errorText)\n".utf8))
        }
        return parse(text)
    }

    private func parse(_ text: String) -> AccountUsageSnapshot? {
        for line in text.split(separator: "\n") {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = object["result"] as? [String: Any],
                  let summaryDict = result["summary"] as? [String: Any] else {
                continue
            }
            let bucketsRaw = result["dailyUsageBuckets"] as? [[String: Any]]
                ?? result["daily_usage_buckets"] as? [[String: Any]]
                ?? []
            let buckets = bucketsRaw.compactMap { dict -> AccountUsageDailyBucket? in
                let startDate = dict["startDate"] as? String ?? dict["start_date"] as? String
                let tokens = int64(dict["tokens"])
                guard let startDate, let tokens else { return nil }
                return AccountUsageDailyBucket(startDate: startDate, tokens: tokens)
            }
            let summary = AccountUsageSummary(
                lifetimeTokens: int64(summaryDict["lifetimeTokens"] ?? summaryDict["lifetime_tokens"]),
                peakDailyTokens: int64(summaryDict["peakDailyTokens"] ?? summaryDict["peak_daily_tokens"]),
                longestRunningTurnSec: int64(summaryDict["longestRunningTurnSec"] ?? summaryDict["longest_running_turn_sec"]),
                currentStreakDays: int64(summaryDict["currentStreakDays"] ?? summaryDict["current_streak_days"]),
                longestStreakDays: int64(summaryDict["longestStreakDays"] ?? summaryDict["longest_streak_days"])
            )
            return AccountUsageSnapshot(summary: summary, dailyUsageBuckets: buckets.sorted { $0.startDate < $1.startDate }, readAt: Date())
        }
        return nil
    }

    private func int64(_ value: Any?) -> Int64? {
        if value == nil || value is NSNull { return nil }
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? Double { return Int64(value) }
        if let value = value as? String { return Int64(value) }
        return nil
    }
}

final class RingView: NSView {
    var percent: Double = 0 { didSet { needsDisplay = true } }
    var title: String = "" { didSet { needsDisplay = true } }
    var subtitle: String = "" { didSet { needsDisplay = true } }
    var color: NSColor = NSColor.systemGreen { didSet { needsDisplay = true } }
    fileprivate var resetTooltip: String? {
        didSet { updateTooltip() }
    }
    fileprivate var remainingComparison: RingRemainingComparison? {
        didSet {
            needsDisplay = true
            updateTooltip()
        }
    }

    override var isFlipped: Bool { true }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityLabel() -> String? { title }
    override func accessibilityValue() -> Any? {
        "\(Int(round(percent)))%, \(subtitle)"
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let bounds = self.bounds.insetBy(dx: 8, dy: 8)
        let labelReserve: CGFloat = 20
        let diameter = min(bounds.width, bounds.height - labelReserve)
        let rect = NSRect(x: bounds.midX - diameter / 2, y: bounds.minY, width: diameter, height: diameter)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = diameter / 2 - 8
        let lineWidth: CGFloat = 8
        let start = -CGFloat.pi * 0.82
        let end = CGFloat.pi * 0.82

        drawArc(center: center, radius: radius, lineWidth: lineWidth, start: start, end: end, percent: 100, color: NSColor.white.withAlphaComponent(0.10))
        drawArc(center: center, radius: radius, lineWidth: lineWidth, start: start, end: end, percent: percent, color: color)

        if let remainingComparison {
            drawRemainingComparison(
                remainingComparison,
                center: center,
                radius: radius,
                lineWidth: lineWidth,
                start: start,
                end: end
            )
        } else {
            let pText = "\(Int(round(percent)))%"
            drawCenteredAt(pText, center: center, font: meterNumberFont(ofSize: 23), color: .white)
        }
        drawCentered(title, rect: NSRect(x: bounds.minX, y: rect.maxY + 2, width: bounds.width, height: 18), font: .systemFont(ofSize: 13, weight: .semibold), color: NSColor.white.withAlphaComponent(0.86))
        drawCentered(subtitle, rect: NSRect(x: bounds.minX, y: rect.maxY + 20, width: bounds.width, height: 16), font: .systemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.45))
    }

    private func drawArc(center: CGPoint, radius: CGFloat, lineWidth: CGFloat, start: CGFloat, end: CGFloat, percent: Double, color: NSColor) {
        let clamped = max(0, min(100, percent)) / 100
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        color.setStroke()
        path.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: start * 180 / .pi,
            endAngle: (start + (end - start) * CGFloat(clamped)) * 180 / .pi,
            clockwise: false
        )
        path.stroke()
    }

    private func drawRemainingComparison(
        _ comparison: RingRemainingComparison,
        center: CGPoint,
        radius: CGFloat,
        lineWidth: CGFloat,
        start: CGFloat,
        end: CGFloat
    ) {
        let markerColor = expectedRemainingMarkerColor(
            expected: comparison.expectedRemainingPercent,
            actual: comparison.actualRemainingPercent
        )
        drawExpectedRemainingMarker(
            percent: comparison.expectedRemainingPercent,
            center: center,
            radius: radius,
            lineWidth: lineWidth,
            start: start,
            end: end,
            color: markerColor
        )
        drawComparisonValue(
            value: "\(Int(round(comparison.actualRemainingPercent)))%",
            center: center,
            fontSize: 23,
            maxWidth: 76,
            valueColor: .white
        )
    }

    private func drawExpectedRemainingMarker(percent: Double, center: CGPoint, radius: CGFloat, lineWidth: CGFloat, start: CGFloat, end: CGFloat, color: NSColor) {
        let clamped = max(0, min(100, percent)) / 100
        let angle = start + (end - start) * CGFloat(clamped)
        let markerLineWidth = max(2.4, lineWidth * 0.32)
        let markerCenter = CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
        let radial = CGPoint(x: cos(angle), y: sin(angle))
        let markerLength = max(15, lineWidth * 1.9)
        let halfLength = markerLength / 2
        let startPoint = CGPoint(
            x: markerCenter.x - radial.x * halfLength,
            y: markerCenter.y - radial.y * halfLength
        )
        let endPoint = CGPoint(
            x: markerCenter.x + radial.x * halfLength,
            y: markerCenter.y + radial.y * halfLength
        )

        let marker = NSBezierPath()
        marker.lineWidth = markerLineWidth
        marker.lineCapStyle = .round
        marker.move(to: startPoint)
        marker.line(to: endPoint)
        color.setStroke()
        marker.stroke()
    }

    private func expectedRemainingMarkerColor(expected: Double, actual: Double) -> NSColor {
        if actual >= expected {
            return NSColor(calibratedRed: 0.56, green: 1.0, blue: 0.16, alpha: 0.98)
        }
        return NSColor.systemYellow.withAlphaComponent(0.98)
    }

    private func drawComparisonValue(value: String, center: CGPoint, fontSize: CGFloat, maxWidth: CGFloat, valueColor: NSColor) {
        var valueFontSize = fontSize
        var valueFont = meterNumberFont(ofSize: valueFontSize)
        var valueAttributes: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: valueColor
        ]
        var valueSize = (value as NSString).size(withAttributes: valueAttributes)
        while valueSize.width > maxWidth, valueFontSize > 12 {
            valueFontSize -= 0.5
            valueFont = meterNumberFont(ofSize: valueFontSize)
            valueAttributes = [.font: valueFont, .foregroundColor: valueColor]
            valueSize = (value as NSString).size(withAttributes: valueAttributes)
        }
        let rowHeight = valueSize.height
        let valueY = center.y - ceil(valueSize.height) / 2 - 0.5
        (value as NSString).draw(
            in: NSRect(x: center.x - ceil(valueSize.width) / 2, y: valueY, width: ceil(valueSize.width), height: ceil(rowHeight)),
            withAttributes: valueAttributes
        )
    }

    private func updateTooltip() {
        guard remainingComparison != nil || resetTooltip != nil else {
            toolTip = nil
            return
        }
        var lines: [String] = []
        if let comparison = remainingComparison {
            let statusText: String
            switch comparison.status {
            case .ahead:
                statusText = "实际剩余低于预计，用得偏快"
            case .behind:
                statusText = "实际剩余高于预计，用得较少"
            }
            lines.append("圈内数字：实际剩余 \(Int(round(comparison.actualRemainingPercent)))%")
            lines.append("彩色标记：预计剩余 \(Int(round(comparison.expectedRemainingPercent)))%")
            lines.append(statusText)
        }
        if let resetTooltip {
            lines.append("重置：\(resetTooltip)")
        }
        toolTip = lines.joined(separator: "\n")
    }

    private func meterNumberFont(ofSize size: CGFloat) -> NSFont {
        for name in ["DIN Alternate", "DIN Condensed", "Avenir Next Condensed Heavy", "Menlo-Bold"] {
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }
        return .monospacedDigitSystemFont(ofSize: size, weight: .bold)
    }

    private func drawCenteredAt(_ text: String, center: CGPoint, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        let size = (text as NSString).size(withAttributes: attributes)
        let rect = NSRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2 - 1,
            width: size.width,
            height: size.height
        )
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }

    private func drawCentered(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        let size = (text as NSString).size(withAttributes: attributes)
        let textRect = NSRect(
            x: rect.minX,
            y: rect.midY - ceil(size.height) / 2,
            width: rect.width,
            height: ceil(size.height)
        )
        (text as NSString).draw(in: textRect, withAttributes: attributes)
    }
}

final class QuotaBulletView: NSView {
    var actualRemainingPercent: Double = 0 { didSet { needsDisplay = true } }
    var title: String = "" { didSet { needsDisplay = true } }
    var subtitle: String = "" { didSet { needsDisplay = true } }
    var color: NSColor = NSColor.systemGreen { didSet { needsDisplay = true } }
    fileprivate var resetTooltip: String? {
        didSet { updateTooltip() }
    }
    fileprivate var remainingComparison: RingRemainingComparison? {
        didSet {
            needsDisplay = true
            updateTooltip()
        }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let bounds = self.bounds.insetBy(dx: 2, dy: 2)
        let valueFont = meterNumberFont(ofSize: 16)
        let value = "\(Int(round(actualRemainingPercent)))%"
        let valueWidth = max(48, measuredTextWidth(value, font: valueFont) + 4)
        let titleFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let titleWidth = min(bounds.width - valueWidth - 16, measuredTextWidth(title, font: titleFont) + 2)
        drawText(title, rect: NSRect(x: bounds.minX, y: bounds.minY + 1, width: titleWidth, height: 16), font: titleFont, color: NSColor.white.withAlphaComponent(0.86))
        drawText(subtitle, rect: NSRect(x: bounds.minX + titleWidth + 7, y: bounds.minY + 1, width: max(0, bounds.width - titleWidth - valueWidth - 18), height: 16), font: .systemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.42))
        drawRight(value, rect: NSRect(x: bounds.maxX - valueWidth, y: bounds.minY - 2, width: valueWidth, height: 20), font: valueFont, color: color.withAlphaComponent(0.96))

        let bar = NSRect(x: bounds.minX, y: bounds.minY + 24, width: bounds.width, height: 10)
        drawTrack(in: bar)

        let actualRatio = CGFloat(max(0, min(100, actualRemainingPercent)) / 100)
        let fillWidth = max(actualRatio <= 0 ? 0 : 4, bar.width * actualRatio)
        if fillWidth > 0 {
            let fill = NSRect(x: bar.minX, y: bar.minY, width: min(bar.width, fillWidth), height: bar.height)
            color.withAlphaComponent(0.86).setFill()
            NSBezierPath(roundedRect: fill, xRadius: 5, yRadius: 5).fill()
        }

        if let comparison = remainingComparison {
            drawExpectedMarker(comparison: comparison, bar: bar)
        }
    }

    private func drawTrack(in rect: NSRect) {
        NSColor.white.withAlphaComponent(0.11).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        NSColor.white.withAlphaComponent(0.05).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5).stroke()
    }

    private func drawExpectedMarker(comparison: RingRemainingComparison, bar: NSRect) {
        let expected = max(0, min(100, comparison.expectedRemainingPercent))
        let x = bar.minX + bar.width * CGFloat(expected / 100)
        let markerColor = expectedRemainingMarkerColor(
            expected: comparison.expectedRemainingPercent,
            actual: comparison.actualRemainingPercent
        )
        let markerRect = NSRect(x: x - 1.5, y: bar.minY - 5, width: 3, height: bar.height + 10)
        markerColor.setFill()
        NSBezierPath(roundedRect: markerRect, xRadius: 2, yRadius: 2).fill()
    }

    private func updateTooltip() {
        guard remainingComparison != nil || resetTooltip != nil else {
            toolTip = nil
            return
        }
        var lines: [String] = []
        if let comparison = remainingComparison {
            let statusText: String
            switch comparison.status {
            case .ahead:
                statusText = "实际剩余低于预计，用得偏快"
            case .behind:
                statusText = "实际剩余高于预计，用得较少"
            }
            lines.append("填充条：实际剩余 \(Int(round(comparison.actualRemainingPercent)))%")
            lines.append("竖标线：预计剩余 \(Int(round(comparison.expectedRemainingPercent)))%")
            lines.append(statusText)
        }
        if let resetTooltip {
            lines.append("重置：\(resetTooltip)")
        }
        toolTip = lines.joined(separator: "\n")
    }

    private func expectedRemainingMarkerColor(expected: Double, actual: Double) -> NSColor {
        if actual >= expected {
            return NSColor(calibratedRed: 0.56, green: 1.0, blue: 0.16, alpha: 0.98)
        }
        return NSColor.systemYellow.withAlphaComponent(0.98)
    }

    private func meterNumberFont(ofSize size: CGFloat) -> NSFont {
        for name in ["DIN Alternate", "DIN Condensed", "Avenir Next Condensed Heavy", "Menlo-Bold"] {
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }
        return .monospacedDigitSystemFont(ofSize: size, weight: .bold)
    }

    private func drawText(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color])
    }

    private func drawRight(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }

    private func measuredTextWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}

final class UsageChartView: NSView {
    var selectedWindow: WindowOption = .week { didSet { needsDisplay = true } }
    var days: [DayUsage] = [] { didSet { hoveredIndex = nil; needsDisplay = true } }
    var hours: [HourUsage] = [] { didSet { hoveredIndex = nil; needsDisplay = true } }
    var weeklyQuotaUsedPercent: Double? { didSet { needsDisplay = true } }
    var weeklyQuotaReferenceTotal: Int64? { didSet { needsDisplay = true } }
    var costEstimator: CostEstimator? { didSet { needsDisplay = true } }
    var apiEstimate: APICostEstimate? { didSet { needsDisplay = true } }
    private var hoveredIndex: Int?
    private var hoverPoint: CGPoint?

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if selectedWindow == .day {
            updateHourlyHover(at: point)
        } else {
            updateDailyHover(at: point)
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredIndex = nil
        hoverPoint = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.06).setFill()
        bounds.fill()

        if selectedWindow == .day {
            drawHourlyBars()
        } else {
            drawDailyBars()
        }
        drawHoverTooltip()
    }

    private func drawHourlyBars() {
        guard !hours.isEmpty else { return }
        let plot = bounds.insetBy(dx: 12, dy: 10)
        let labelHeight: CGFloat = 16
        let chart = NSRect(x: plot.minX, y: plot.minY, width: plot.width, height: plot.height - labelHeight)
        let series = continuousHours()
        let maxTotal = max(series.map { $0.usage.total }.max() ?? 1, 1)
        let gap: CGFloat = 4
        let width = max(4, (chart.width - gap * CGFloat(series.count - 1)) / CGFloat(max(series.count, 1)))

        for (index, hour) in series.enumerated() {
            let x = chart.minX + CGFloat(index) * (width + gap)
            let ratio = CGFloat(Double(hour.usage.total) / Double(maxTotal))
            let height = hour.usage.total > 0 ? max(3, chart.height * ratio) : 2
            let bar = NSRect(x: x, y: chart.maxY - height, width: width, height: height)
            let isHovered = hoveredIndex == index
            (isHovered ? NSColor.systemGreen : NSColor.systemGreen.withAlphaComponent(hour.usage.total > 0 ? 0.78 : 0.20)).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 2.5, yRadius: 2.5).fill()
            if isHovered {
                NSColor.white.withAlphaComponent(0.55).setStroke()
                let outline = NSBezierPath(roundedRect: bar.insetBy(dx: -1, dy: -1), xRadius: 3.5, yRadius: 3.5)
                outline.lineWidth = 1
                outline.stroke()
            }
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "HH:mm"
        let labels = [(0, series.first?.hour), (series.count / 2, series.indices.contains(series.count / 2) ? series[series.count / 2].hour : nil), (max(0, series.count - 1), series.last?.hour)]
        for (index, date) in labels {
            guard let date else { continue }
            let x = chart.minX + CGFloat(index) * (width + gap) + width / 2
            drawLabel(formatter.string(from: date), rect: NSRect(x: x - 28, y: plot.maxY - labelHeight + 2, width: 56, height: labelHeight))
        }
    }

    private func drawDailyBars() {
        guard !days.isEmpty else { return }
        let maxTotal: Int64 = max(days.map { $0.usage.total }.max() ?? 1, 1)
        let minNonZero: Int64 = days.map { $0.usage.total }.filter { $0 > 0 }.min() ?? maxTotal
        let gap: CGFloat = days.count > 14 ? 3 : 6
        let labelHeight: CGFloat = 16
        let plot = bounds.insetBy(dx: 10, dy: 8)
        let width = max(3, (plot.width - gap * CGFloat(days.count - 1)) / CGFloat(days.count))
        let labelIndexes = labelIndexesForDailyBars()

        for (index, day) in days.enumerated() {
            let x = plot.minX + CGFloat(index) * (width + gap)
            let ratio = dailyBarRatio(total: day.usage.total, maxTotal: maxTotal, minNonZero: minNonZero)
            let h = max(4, (plot.height - labelHeight) * ratio)
            let bar = NSRect(x: x, y: plot.maxY - labelHeight - h, width: width, height: h)
            let isHovered = hoveredIndex == index
            (isHovered ? NSColor.systemGreen : NSColor.systemGreen.withAlphaComponent(0.78)).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 3, yRadius: 3).fill()
            if isHovered {
                NSColor.white.withAlphaComponent(0.55).setStroke()
                let outline = NSBezierPath(roundedRect: bar.insetBy(dx: -1, dy: -1), xRadius: 4, yRadius: 4)
                outline.lineWidth = 1
                outline.stroke()
            }

            if labelIndexes.contains(index) {
                let label = selectedWindow == .month ? compactDayLabel(day.day) : String(day.day.suffix(5))
                drawLabel(label, rect: NSRect(x: x - 22, y: plot.maxY - labelHeight + 2, width: width + 44, height: labelHeight))
            }
        }
    }

    private func dailyBarRatio(total: Int64, maxTotal: Int64, minNonZero: Int64) -> CGFloat {
        guard total > 0, maxTotal > 0 else { return 0 }
        let linear = Double(total) / Double(maxTotal)
        let needsCompression = selectedWindow == .month && maxTotal / max(minNonZero, 1) > 80
        if needsCompression {
            return CGFloat(pow(linear, 0.35))
        }
        return CGFloat(linear)
    }

    private func updateDailyHover(at point: CGPoint) {
        guard !days.isEmpty else { return clearHoverIfNeeded() }
        let gap: CGFloat = days.count > 14 ? 3 : 6
        let labelHeight: CGFloat = 16
        let plot = bounds.insetBy(dx: 10, dy: 8)
        let width = max(3, (plot.width - gap * CGFloat(days.count - 1)) / CGFloat(days.count))
        let chart = NSRect(x: plot.minX, y: plot.minY, width: plot.width, height: plot.height - labelHeight)
        guard chart.insetBy(dx: -4, dy: 0).contains(point) else { return clearHoverIfNeeded() }

        let raw = Int((point.x - plot.minX) / (width + gap))
        let index = min(max(raw, 0), days.count - 1)
        let x = plot.minX + CGFloat(index) * (width + gap)
        let hitRect = NSRect(x: x - max(4, gap / 2), y: chart.minY, width: width + max(8, gap), height: chart.height)
        if hitRect.contains(point) {
            hoveredIndex = index
            hoverPoint = point
        } else {
            hoveredIndex = nil
            hoverPoint = nil
        }
        needsDisplay = true
    }

    private func updateHourlyHover(at point: CGPoint) {
        let series = continuousHours()
        guard !series.isEmpty else { return clearHoverIfNeeded() }
        let plot = bounds.insetBy(dx: 12, dy: 10)
        let labelHeight: CGFloat = 16
        let chart = NSRect(x: plot.minX, y: plot.minY, width: plot.width, height: plot.height - labelHeight)
        guard chart.insetBy(dx: -4, dy: 0).contains(point) else { return clearHoverIfNeeded() }

        let gap: CGFloat = 4
        let width = max(4, (chart.width - gap * CGFloat(series.count - 1)) / CGFloat(max(series.count, 1)))
        let raw = Int((point.x - chart.minX) / (width + gap))
        let index = min(max(raw, 0), series.count - 1)
        let x = chart.minX + CGFloat(index) * (width + gap)
        let hitRect = NSRect(x: x - max(3, gap / 2), y: chart.minY, width: width + max(6, gap), height: chart.height)
        if hitRect.contains(point) {
            hoveredIndex = index
            hoverPoint = point
        } else {
            hoveredIndex = nil
            hoverPoint = nil
        }
        needsDisplay = true
    }

    private func clearHoverIfNeeded() {
        if hoveredIndex != nil || hoverPoint != nil {
            hoveredIndex = nil
            hoverPoint = nil
            needsDisplay = true
        }
    }

    private func continuousHours() -> [HourUsage] {
        guard selectedWindow == .day else { return hours }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        guard let last = hours.last?.hour else { return hours }
        let start = calendar.date(byAdding: .hour, value: -23, to: last) ?? last
        let byHour = Dictionary(uniqueKeysWithValues: hours.map { ($0.hour, $0) })
        return (0..<24).map { offset in
            let date = calendar.date(byAdding: .hour, value: offset, to: start) ?? start
            return byHour[date] ?? HourUsage(hour: date, usage: Usage(), turns: 0)
        }
    }

    private func labelIndexesForDailyBars() -> Set<Int> {
        guard !days.isEmpty else { return [] }
        if selectedWindow == .week {
            return Set(days.indices)
        }
        let count = days.count
        let candidates = [0, count / 4, count / 2, count * 3 / 4, count - 1]
        return Set(candidates.filter { $0 >= 0 && $0 < count })
    }

    private func compactDayLabel(_ day: String) -> String {
        let parts = day.split(separator: "-")
        guard parts.count == 3 else { return day }
        return "\(parts[1])/\(parts[2])"
    }

    private func drawHoverTooltip() {
        guard let hoveredIndex, let hoverPoint else { return }
        let title: String
        let usage: Usage

        if selectedWindow == .day {
            let series = continuousHours()
            guard series.indices.contains(hoveredIndex) else { return }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            formatter.dateFormat = "MM/dd HH:mm"
            title = formatter.string(from: series[hoveredIndex].hour)
            usage = series[hoveredIndex].usage
        } else {
            guard days.indices.contains(hoveredIndex) else { return }
            title = days[hoveredIndex].day
            usage = days[hoveredIndex].usage
        }

        var lines = [
            title,
            "\(t(.input))       \(compact(usage.input))",
            "\(t(.output))      \(compact(usage.output))",
            "\(t(.cached))      \(compact(usage.cachedInput))",
            "\(t(.fresh))       \(compact(usage.freshInput))"
        ]
        if let weeklyQuotaPercent = stableWeeklyQuotaShare(for: usage) ?? weeklyQuotaShare(for: usage) {
            lines.append("\(t(.weeklyQuotaShare))   \(String(format: "%.1f%%", weeklyQuotaPercent))")
        } else if let visibleWeekPercent = visibleWeekShare(for: usage) {
            lines.append("\(t(.visibleWeekShare)) \(String(format: "%.1f%%", visibleWeekPercent))")
        }
        if let costEstimator {
            if selectedWindow == .day {
                lines.append("\(t(.dayValue))  \(displayMoney(costEstimator.value(for: usage)))")
            } else {
                lines.append("\(t(.dayValue))  \(displayMoney(costEstimator.tokenValue(forDayKey: title, usage: usage)))")
            }
        }
        if let apiEquivalentUSD = apiEquivalentUSD(for: title, usage: usage) {
            lines.append("\(t(.apiEquivalent))  \(displayAPIMoney(apiEquivalentUSD))")
        }

        let width: CGFloat = 244
        let height = CGFloat(18 + lines.count * 16)
        var origin = CGPoint(x: hoverPoint.x + 12, y: hoverPoint.y - height - 8)
        if origin.x + width > bounds.maxX - 8 {
            origin.x = hoverPoint.x - width - 12
        }
        if origin.y < bounds.minY + 8 {
            origin.y = hoverPoint.y + 14
        }
        origin.x = max(bounds.minX + 8, min(origin.x, bounds.maxX - width - 8))
        origin.y = max(bounds.minY + 8, min(origin.y, bounds.maxY - height - 8))

        let rect = NSRect(origin: origin, size: CGSize(width: width, height: height))
        NSColor(calibratedWhite: 0.025, alpha: 0.96).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        border.lineWidth = 1
        border.stroke()

        for (index, line) in lines.enumerated() {
            let isTitle = index == 0
            let textRect = NSRect(x: rect.minX + 10, y: rect.minY + 8 + CGFloat(index) * 16, width: rect.width - 20, height: 15)
            (line as NSString).draw(
                in: textRect,
                withAttributes: [
                    .font: isTitle ? NSFont.systemFont(ofSize: 11, weight: .bold) : NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
                    .foregroundColor: isTitle ? NSColor.white.withAlphaComponent(0.9) : NSColor.white.withAlphaComponent(0.62)
                ]
            )
        }
    }

    private func weeklyQuotaShare(for usage: Usage) -> Double? {
        guard selectedWindow != .day,
              let weeklyQuotaUsedPercent,
              weeklyQuotaUsedPercent > 0 else {
            return nil
        }
        let referenceTotal = weeklyQuotaReferenceTotal ?? recentWeekTotal()
        guard usage.total > 0, referenceTotal > 0 else { return nil }
        let shareOfVisibleWeek = Double(usage.total) / Double(referenceTotal)
        return shareOfVisibleWeek * weeklyQuotaUsedPercent
    }

    private func stableWeeklyQuotaShare(for usage: Usage) -> Double? {
        guard selectedWindow != .day,
              usage.total > 0,
              let costEstimator else {
            return nil
        }
        return costEstimator.quotaPercent(for: usage)
    }

    private func visibleWeekShare(for usage: Usage) -> Double? {
        guard selectedWindow == .week else { return nil }
        let visibleTotal = days.reduce(Int64(0)) { $0 + $1.usage.total }
        guard usage.total > 0, visibleTotal > 0 else { return nil }
        return Double(usage.total) / Double(visibleTotal) * 100
    }

    private func apiEquivalentUSD(for title: String, usage: Usage) -> Double? {
        guard usage.total > 0 else { return nil }
        if selectedWindow == .day {
            guard let apiEstimate,
                  apiEstimate.hasPricedUsage,
                  apiEstimate.totalTokens > 0 else {
                return nil
            }
            return apiEstimate.usdValue * Double(usage.total) / Double(apiEstimate.totalTokens)
        }
        guard let day = days.first(where: { $0.day == title }) else { return nil }
        let estimate = APICostEstimator.estimate(day: day)
        return estimate.hasPricedUsage ? estimate.usdValue : nil
    }

    private func recentWeekTotal() -> Int64 {
        if selectedWindow == .week {
            return days.reduce(Int64(0)) { $0 + $1.usage.total }
        }
        return days.suffix(7).reduce(Int64(0)) { $0 + $1.usage.total }
    }

    private func drawLabel(_ label: String, rect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        (label as NSString).draw(
            in: rect,
            withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.42), .paragraphStyle: paragraph]
        )
    }
}

final class CodexStatusChipView: NSView {
    var snapshot: CodexServiceStatusSnapshot? { didSet { needsDisplay = true } }

    private let chipFont = NSFont.systemFont(ofSize: 12, weight: .semibold)

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let rect = bounds

        let text = statusText
        let dotColor = statusColor
        dotColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: rect.minX + 4, y: rect.midY - 3, width: 6, height: 6)).fill()
        drawText(
            text,
            rect: NSRect(x: rect.minX + 16, y: rect.minY + 4, width: rect.width - 18, height: rect.height - 8),
            font: chipFont,
            color: NSColor.white.withAlphaComponent(0.82)
        )
    }

    private func drawText(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: rect, withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
    }

    private var statusText: String {
        let label = snapshot.map { localizedCodexStatus($0.overallStatus) } ?? t(.codexStatusUnavailable)
        return "Codex \(label)"
    }

    private var statusColor: NSColor {
        snapshot.map { codexStatusColor($0.overallStatus) } ?? NSColor.white.withAlphaComponent(0.42)
    }

    func preferredWidth(maxWidth: CGFloat) -> CGFloat {
        let textWidth = (statusText as NSString).size(withAttributes: [
            .font: chipFont
        ]).width
        return min(maxWidth, ceil(textWidth) + 22)
    }
}

final class DashboardView: NSView {
    static let idealSize = NSSize(width: 430, height: 610)

    private var state = DashboardState()
    private let logoImageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "Codex Token Meter")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let totalLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let usageLabel = NSTextField(labelWithString: "")
    private let refreshLabel = NSTextField(labelWithString: "")
    private let costLabel = NSTextField(labelWithString: "")
    private let quotaSegment = NSSegmentedControl(labels: QuotaViewOption.allCases.map { $0.shortTitle }, trackingMode: .selectOne, target: nil, action: nil)
    private let segment = NSSegmentedControl(labels: WindowOption.allCases.map { $0.shortTitle }, trackingMode: .selectOne, target: nil, action: nil)
    private let primaryRing = RingView()
    private let weeklyRing = RingView()
    private let cacheRing = RingView()
    private let primaryBullet = QuotaBulletView()
    private let weeklyBullet = QuotaBulletView()
    private let cacheBullet = QuotaBulletView()
    private let dayChart = UsageChartView()
    private let serviceStatusView = CodexStatusChipView()
    private let sessionsLabel = NSTextField(labelWithString: "")
    private let buttonsStack = NSStackView()
    private var buttonsByKey: [L10nKey: NSButton] = [:]

    var onWindowChanged: ((WindowOption) -> Void)?
    var onQuotaChanged: ((QuotaViewOption) -> Void)?
    var onRefresh: (() -> Void)?
    var onOpenDetails: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenCodexStatus: (() -> Void)?
    var onQuit: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { Self.idealSize }

    func update(_ state: DashboardState) {
        self.state = state
        let report = state.report
        let totalReport = state.selectedQuota == .all ? (state.profileReport ?? report) : report
        applyLanguage()
        titleLabel.stringValue = "Codex Token Meter"
        let displayLimit = selectedLimit(from: state.liveLimits, quota: state.selectedQuota)
        subtitleLabel.stringValue = state.selectedQuota.fallbackTitle
        totalLabel.stringValue = compactDashboardTotal(totalReport.usage.total)
        detailLabel.stringValue = state.profileReport != nil && state.selectedQuota == .all
            ? "\(state.selectedWindow.title) · \(t(.profileAPISource))"
            : state.selectedWindow.title
        usageLabel.stringValue = "\(compactDashboardMetric(report.usage.input)) \(t(.inShort))  |  \(compactDashboardMetric(report.usage.output)) \(t(.outShort))"
        refreshLabel.stringValue = state.isLoading ? t(.refreshing) : "\(t(.updated)) \(relative(report.scannedAt))  |  \(t(.next)) \(relative(state.nextRefreshAt))"
        let apiEstimate = APICostEstimator.estimate(report: report)
        let externalAPI = ExternalAPICostStore.read()

        quotaSegment.selectedSegment = QuotaViewOption.allCases.firstIndex(of: state.selectedQuota) ?? 0
        segment.selectedSegment = WindowOption.allCases.firstIndex(of: state.selectedWindow) ?? 1

        let primary = displayLimit?.primary
        let weekly = displayLimit?.secondary
        let primaryComparison = remainingComparison(for: primary)
        let weeklyComparison = remainingComparison(for: weekly)
        let quotaStyle = QuotaDisplayStyle.current
        primaryRing.percent = primary?.remainingPercent ?? 0
        primaryRing.title = t(.fiveHourLeft)
        primaryRing.subtitle = primary.map { "\(t(.reset)) \(compactResetRelative($0.resetsAt))" } ?? t(.liveLimitUnavailable)
        primaryRing.color = colorForRemaining(percent: primaryRing.percent)
        primaryRing.resetTooltip = primary?.resetsAt.map { relative($0) }
        primaryRing.remainingComparison = primaryComparison
        primaryRing.isHidden = quotaStyle != .rings

        primaryBullet.actualRemainingPercent = primary?.remainingPercent ?? 0
        primaryBullet.title = t(.fiveHourLeft)
        primaryBullet.subtitle = primary.map { "\(t(.reset)) \(compactResetRelative($0.resetsAt))" } ?? t(.liveLimitUnavailable)
        primaryBullet.color = colorForRemaining(percent: primaryBullet.actualRemainingPercent)
        primaryBullet.resetTooltip = primary?.resetsAt.map { relative($0) }
        primaryBullet.remainingComparison = primaryComparison
        primaryBullet.isHidden = quotaStyle != .bullet

        weeklyRing.percent = weekly?.remainingPercent ?? 0
        weeklyRing.title = t(.weeklyLeft)
        weeklyRing.subtitle = weekly.map { "\(t(.reset)) \(compactResetRelative($0.resetsAt))" } ?? t(.usageWindow)
        weeklyRing.color = colorForRemaining(percent: weeklyRing.percent)
        weeklyRing.resetTooltip = weekly?.resetsAt.map { relative($0) }
        weeklyRing.remainingComparison = weeklyComparison
        weeklyRing.isHidden = quotaStyle != .rings

        weeklyBullet.actualRemainingPercent = weekly?.remainingPercent ?? 0
        weeklyBullet.title = t(.weeklyLeft)
        weeklyBullet.subtitle = weekly.map { "\(t(.reset)) \(compactResetRelative($0.resetsAt))" } ?? t(.usageWindow)
        weeklyBullet.color = colorForRemaining(percent: weeklyBullet.actualRemainingPercent)
        weeklyBullet.resetTooltip = weekly?.resetsAt.map { relative($0) }
        weeklyBullet.remainingComparison = weeklyComparison
        weeklyBullet.isHidden = quotaStyle != .bullet

        cacheRing.percent = report.usage.cachePercent
        cacheRing.title = t(.cacheHit)
        cacheRing.subtitle = "\(compact(report.usage.freshInput)) \(t(.fresh).lowercased())"
        cacheRing.color = NSColor.systemTeal
        cacheRing.resetTooltip = nil
        cacheRing.remainingComparison = nil
        cacheRing.isHidden = quotaStyle == .bullet

        cacheBullet.actualRemainingPercent = report.usage.cachePercent
        cacheBullet.title = t(.cacheHit)
        cacheBullet.subtitle = "\(compact(report.usage.freshInput)) \(t(.fresh).lowercased())"
        cacheBullet.color = NSColor.systemTeal
        cacheBullet.resetTooltip = nil
        cacheBullet.remainingComparison = nil
        cacheBullet.isHidden = quotaStyle != .bullet

        dayChart.selectedWindow = state.selectedWindow
        dayChart.days = report.byDay
        dayChart.hours = report.byHour
        dayChart.weeklyQuotaUsedPercent = state.selectedWindow == .day ? nil : weekly?.usedPercent
        dayChart.weeklyQuotaReferenceTotal = state.selectedWindow == .day ? nil : report.byDay.suffix(7).reduce(Int64(0)) { $0 + $1.usage.total }
        dayChart.costEstimator = state.selectedWindow == .day ? nil : CostEstimator(report: report, limit: displayLimit)
        dayChart.apiEstimate = apiEstimate
        serviceStatusView.snapshot = state.serviceStatus
        serviceStatusView.isHidden = !AppSettings.showCodexStatusEnabled
        sessionsLabel.stringValue = "\(t(.sessions)) \(report.sessions)   \(t(.turns)) \(report.turns)   \(t(.events)) \(report.events)"
        var costParts: [String] = []
        if apiEstimate.hasPricedUsage {
            let coverage = apiEstimate.coveragePercent < 99.5 ? " \(String(format: "%.0f%%", apiEstimate.coveragePercent)) \(t(.priced))" : ""
            costParts.append("\(t(.apiEquivalent)) \(displayAPIMoney(apiEstimate.usdValue))\(coverage)")
        }
        if let externalAPI, externalAPI.hasData {
            costParts.append("\(t(.externalAPICost)) \(displayAPIMoney(externalAPI.usdValue))")
        }
        if !costParts.isEmpty {
            costLabel.stringValue = costParts.joined(separator: "  |  ")
        } else {
            costLabel.stringValue = ""
        }
        updateAccessibilityLabels(report: report, totalReport: totalReport)
        needsLayout = true
        needsDisplay = true
    }

    func applyLanguage() {
        for (index, option) in QuotaViewOption.allCases.enumerated() {
            quotaSegment.setLabel(option.shortTitle, forSegment: index)
        }
        for (index, option) in WindowOption.allCases.enumerated() {
            segment.setLabel(option.shortTitle, forSegment: index)
        }
        for key in [L10nKey.refresh, .details, .settings, .quit] {
            guard let button = buttonsByKey[key] else { continue }
            button.title = t(key)
            button.toolTip = t(key)
            button.image = symbolImage(for: key)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        let card = bounds.insetBy(dx: 8, dy: 8)
        NSColor(calibratedWhite: 0.045, alpha: 0.98).setFill()
        NSBezierPath(roundedRect: card, xRadius: 26, yRadius: 26).fill()
        NSColor.white.withAlphaComponent(0.09).setStroke()
        let border = NSBezierPath(roundedRect: card.insetBy(dx: 0.5, dy: 0.5), xRadius: 26, yRadius: 26)
        border.lineWidth = 1
        border.stroke()
    }

    override func layout() {
        super.layout()
        let layoutBounds = NSRect(origin: .zero, size: NSSize(width: max(bounds.width, Self.idealSize.width), height: max(bounds.height, Self.idealSize.height)))
        let content = layoutBounds.insetBy(dx: 28, dy: 24)
        let totalWidth: CGFloat = 132
        let totalX = content.maxX - totalWidth
        let titleX = content.minX + 28
        logoImageView.frame = NSRect(x: content.minX, y: content.minY + 2, width: 22, height: 22)
        titleLabel.frame = NSRect(x: titleX, y: content.minY, width: max(132, totalX - titleX - 12), height: 28)
        subtitleLabel.frame = NSRect(x: titleX, y: content.minY + 30, width: max(132, totalX - titleX - 12), height: 18)
        totalLabel.frame = NSRect(x: totalX, y: content.minY, width: totalWidth, height: 36)
        detailLabel.frame = NSRect(x: content.maxX - 172, y: content.minY + 37, width: 162, height: 16)
        quotaSegment.frame = NSRect(x: content.minX, y: content.minY + 52, width: 216, height: 24)
        usageLabel.frame = NSRect(x: content.minX + 228, y: content.minY + 55, width: content.width - 228, height: 16)
        segment.frame = NSRect(x: content.minX, y: content.minY + 82, width: content.width, height: 30)

        let ringY = content.minY + 132
        let ringW = (content.width - 24) / 3
        if QuotaDisplayStyle.current == .bullet {
            let rowH: CGFloat = 40
            let rowGap: CGFloat = 8
            primaryRing.frame = .zero
            weeklyRing.frame = .zero
            cacheRing.frame = .zero
            primaryBullet.frame = NSRect(x: content.minX, y: ringY + 2, width: content.width, height: rowH)
            weeklyBullet.frame = NSRect(x: content.minX, y: ringY + 2 + rowH + rowGap, width: content.width, height: rowH)
            cacheBullet.frame = NSRect(x: content.minX, y: ringY + 2 + (rowH + rowGap) * 2, width: content.width, height: rowH)
        } else {
            primaryRing.frame = NSRect(x: content.minX, y: ringY, width: ringW, height: 136)
            weeklyRing.frame = NSRect(x: content.minX + ringW + 12, y: ringY, width: ringW, height: 136)
            primaryBullet.frame = .zero
            weeklyBullet.frame = .zero
            cacheBullet.frame = .zero
            cacheRing.frame = NSRect(x: content.minX + (ringW + 12) * 2, y: ringY, width: ringW, height: 136)
        }

        let statsY = ringY + 154
        buttonsStack.frame = NSRect(x: content.minX, y: content.maxY - 36, width: content.width, height: 28)
        let showsStatus = AppSettings.showCodexStatusEnabled
        let chipGap: CGFloat = 10
        let maxChipWidth = min(136, max(108, content.width * 0.36))
        let chipWidth = showsStatus ? serviceStatusView.preferredWidth(maxWidth: maxChipWidth) : 0
        let infoWidth = showsStatus ? max(120, content.width - chipWidth - chipGap) : content.width
        refreshLabel.frame = NSRect(x: content.minX, y: buttonsStack.frame.minY - 24, width: infoWidth, height: 18)
        costLabel.frame = NSRect(x: content.minX, y: refreshLabel.frame.minY - 20, width: infoWidth, height: 16)
        sessionsLabel.frame = NSRect(x: content.minX, y: costLabel.frame.minY - 22, width: infoWidth, height: 18)
        if showsStatus {
            let chipHeight: CGFloat = 24
            let chipX = content.maxX - chipWidth
            let chipY = sessionsLabel.frame.minY + max(0, (refreshLabel.frame.maxY - sessionsLabel.frame.minY - chipHeight) / 2)
            serviceStatusView.frame = NSRect(x: chipX, y: chipY, width: chipWidth, height: chipHeight)
        } else {
            serviceStatusView.frame = .zero
        }
        let chartBottom = sessionsLabel.frame.minY
        dayChart.frame = NSRect(x: content.minX, y: statsY, width: content.width, height: max(72, chartBottom - statsY - 12))
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !serviceStatusView.isHidden,
           serviceStatusView.frame.insetBy(dx: -2, dy: -2).contains(point) {
            onOpenCodexStatus?()
            return
        }
        super.mouseDown(with: event)
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        logoImageView.image = NSImage(named: "LogoHeader")
        logoImageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(logoImageView)

        [titleLabel, subtitleLabel, totalLabel, detailLabel, usageLabel, refreshLabel, sessionsLabel, costLabel].forEach {
            $0.isBezeled = false
            $0.drawsBackground = false
            $0.isEditable = false
            $0.isSelectable = false
            addSubview($0)
        }

        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.usesSingleLineMode = true
        titleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.58)
        subtitleLabel.usesSingleLineMode = true
        subtitleLabel.lineBreakMode = .byTruncatingTail
        totalLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .bold)
        totalLabel.alignment = .right
        totalLabel.textColor = NSColor.systemGreen
        totalLabel.usesSingleLineMode = true
        totalLabel.lineBreakMode = .byTruncatingHead
        detailLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        detailLabel.alignment = .right
        detailLabel.textColor = NSColor.white.withAlphaComponent(0.58)
        detailLabel.usesSingleLineMode = true
        detailLabel.lineBreakMode = .byTruncatingTail
        usageLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        usageLabel.alignment = .right
        usageLabel.textColor = NSColor.white.withAlphaComponent(0.52)
        usageLabel.usesSingleLineMode = true
        usageLabel.lineBreakMode = .byTruncatingMiddle
        refreshLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        refreshLabel.textColor = NSColor.white.withAlphaComponent(0.50)
        refreshLabel.usesSingleLineMode = true
        refreshLabel.lineBreakMode = .byTruncatingMiddle
        sessionsLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        sessionsLabel.textColor = NSColor.white.withAlphaComponent(0.56)
        sessionsLabel.usesSingleLineMode = true
        sessionsLabel.lineBreakMode = .byTruncatingTail
        costLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        costLabel.textColor = NSColor.systemTeal.withAlphaComponent(0.88)
        costLabel.usesSingleLineMode = true
        costLabel.lineBreakMode = .byTruncatingTail

        quotaSegment.target = self
        quotaSegment.action = #selector(quotaSegmentChanged)
        quotaSegment.segmentStyle = .rounded
        addSubview(quotaSegment)

        segment.target = self
        segment.action = #selector(segmentChanged)
        segment.segmentStyle = .rounded
        segment.toolTip = t(.usageWindow)
        addSubview(segment)

        [primaryRing, weeklyRing, primaryBullet, weeklyBullet, cacheBullet, cacheRing, dayChart, serviceStatusView].forEach { addSubview($0) }
        serviceStatusView.toolTip = "Open OpenAI Status"

        buttonsStack.orientation = .horizontal
        buttonsStack.spacing = 8
        buttonsStack.distribution = .fillEqually
        addSubview(buttonsStack)
        addButton(.refresh, action: #selector(refreshTapped))
        addButton(.details, action: #selector(detailsTapped))
        addButton(.settings, action: #selector(settingsTapped))
        addButton(.quit, action: #selector(quitTapped))
        applyLanguage()
    }

    private func addButton(_ titleKey: L10nKey, action: Selector) {
        let button = NSButton(title: t(titleKey), target: self, action: action)
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.image = symbolImage(for: titleKey)
        button.imagePosition = .imageLeading
        button.toolTip = t(titleKey)
        buttonsByKey[titleKey] = button
        buttonsStack.addArrangedSubview(button)
    }

    private func symbolImage(for key: L10nKey) -> NSImage? {
        let name: String
        switch key {
        case .refresh:
            name = "arrow.clockwise"
        case .details:
            name = "chart.bar"
        case .settings:
            name = "gearshape"
        case .logs:
            name = "folder"
        case .quit:
            name = "power"
        default:
            return nil
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: t(key))
        image?.isTemplate = true
        return image
    }

    private func updateAccessibilityLabels(report: TokenReport, totalReport: TokenReport) {
        titleLabel.setAccessibilityLabel("Codex Token Meter")
        subtitleLabel.setAccessibilityLabel(subtitleLabel.stringValue)
        totalLabel.setAccessibilityLabel("\(t(.total)) \(compactDashboardTotal(totalReport.usage.total))")
        usageLabel.setAccessibilityLabel("\(t(.input)) \(compactDashboardMetric(report.usage.input)), \(t(.output)) \(compactDashboardMetric(report.usage.output))")
        sessionsLabel.setAccessibilityLabel(sessionsLabel.stringValue)
        refreshLabel.setAccessibilityLabel(refreshLabel.stringValue)
        quotaSegment.setAccessibilityLabel(t(.quotaViews))
        segment.setAccessibilityLabel(t(.usageWindow))
    }

    private func shortenedLimitName(_ value: String) -> String {
        if value.count <= 31 {
            return value
        }
        if let openParen = value.firstIndex(of: "(") {
            let prefix = String(value[..<openParen]).trimmingCharacters(in: .whitespaces)
            if prefix.count <= 28 {
                return prefix
            }
        }
        return String(value.prefix(28)) + "..."
    }

    private func selectedLimit(from limits: [LiveRateLimit], quota: QuotaViewOption) -> LiveRateLimit? {
        if let exact = limits.first(where: { $0.id == quota.liveLimitID }) {
            return exact
        }
        if quota == .spark {
            return limits.first { $0.id != QuotaViewOption.all.liveLimitID }
        }
        return nil
    }

    private func displayName(for limit: LiveRateLimit) -> String {
        limit.id == "codex" ? "Codex quota" : shortenedLimitName(limit.name)
    }

    @objc private func segmentChanged() {
        let index = segment.selectedSegment
        guard index >= 0, index < WindowOption.allCases.count else { return }
        onWindowChanged?(WindowOption.allCases[index])
    }

    @objc private func quotaSegmentChanged() {
        let index = quotaSegment.selectedSegment
        guard index >= 0, index < QuotaViewOption.allCases.count else { return }
        onQuotaChanged?(QuotaViewOption.allCases[index])
    }

    @objc private func refreshTapped() { onRefresh?() }
    @objc private func detailsTapped() { onOpenDetails?() }
    @objc private func settingsTapped() { onOpenSettings?() }
    @objc private func quitTapped() { onQuit?() }

    private func colorFor(percent: Double) -> NSColor {
        if percent >= 85 { return .systemRed }
        if percent >= 65 { return .systemOrange }
        return .systemGreen
    }

    private func colorForRemaining(percent: Double) -> NSColor {
        if percent <= 15 { return .systemRed }
        if percent <= 35 { return .systemOrange }
        return .systemGreen
    }

    private func remainingComparison(for window: RateWindow?) -> RingRemainingComparison? {
        guard let window,
              let comparison = paceComparison(for: window) else {
            return nil
        }
        return RingRemainingComparison(
            expectedRemainingPercent: max(0, min(100, 100 - comparison.progressPercent)),
            actualRemainingPercent: window.remainingPercent,
            status: comparison.status
        )
    }
}

final class DashboardViewController: NSViewController {
    let dashboardView = DashboardView(frame: NSRect(origin: .zero, size: DashboardView.idealSize))

    override func loadView() {
        dashboardView.frame = NSRect(origin: .zero, size: DashboardView.idealSize)
        view = dashboardView
        preferredContentSize = DashboardView.idealSize
    }
}

struct DetailsSnapshot {
    var all: TokenReport
    var spark: TokenReport
    var other: TokenReport
    var liveLimits: [LiveRateLimit]
    var serviceStatus: CodexServiceStatusSnapshot?
    var costReferenceReport: TokenReport?
    var accountUsage: AccountUsageSnapshot? = nil
}

final class UsageDetailsWindowController: NSWindowController, NSWindowDelegate {
    let detailsView = UsageDetailsView(frame: NSRect(x: 0, y: 0, width: 900, height: 660))
    private let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 660))

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = t(.detailsWindowTitle)
        window.contentMinSize = NSSize(width: 860, height: 640)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        detailsView.canDrawConcurrently = false
        scrollView.documentView = detailsView
        window.contentView = scrollView
        super.init(window: window)
        window.delegate = self
        detailsView.onPreferredHeightChanged = { [weak self] in
            self?.updateDocumentLayout()
        }
        updateDocumentLayout()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func showLoading() {
        detailsView.isLoading = true
        showWindow(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        updateDocumentLayout()
    }

    func update(snapshot: DetailsSnapshot) {
        detailsView.snapshot = snapshot
        detailsView.isLoading = false
        updateDocumentLayout()
    }

    func updateLiveLimits(_ limits: [LiveRateLimit], costReferenceReport: TokenReport?, serviceStatus: CodexServiceStatusSnapshot?) {
        guard var snapshot = detailsView.snapshot else { return }
        snapshot.liveLimits = limits
        snapshot.serviceStatus = serviceStatus ?? snapshot.serviceStatus
        if let costReferenceReport {
            snapshot.costReferenceReport = costReferenceReport
        }
        detailsView.snapshot = snapshot
        updateDocumentLayout()
    }

    func updateServiceStatus(_ serviceStatus: CodexServiceStatusSnapshot?) {
        guard var snapshot = detailsView.snapshot else { return }
        snapshot.serviceStatus = serviceStatus
        detailsView.snapshot = snapshot
        updateDocumentLayout()
    }

    func applyLanguage() {
        window?.title = t(.detailsWindowTitle)
        updateDocumentLayout()
        detailsView.needsDisplay = true
    }

    func windowDidResize(_ notification: Notification) {
        updateDocumentLayout()
    }

    private func updateDocumentLayout() {
        let visibleWidth = max(860, scrollView.contentSize.width)
        let visibleHeight = max(640, scrollView.contentSize.height)
        let targetHeight = max(visibleHeight, detailsView.preferredDocumentHeight(for: visibleWidth))
        detailsView.frame = NSRect(x: 0, y: 0, width: visibleWidth, height: targetHeight)
        detailsView.needsLayout = true
        detailsView.needsDisplay = true
    }
}

private enum DetailsSection: CaseIterable {
    case overview
    case models
    case calendar
    case costs
    case settings
    case diagnostics
    case about

    var title: String {
        switch self {
        case .overview: return t(.overview)
        case .models: return t(.models)
        case .calendar: return t(.calendar)
        case .costs: return t(.costs)
        case .settings: return t(.settings)
        case .diagnostics: return t(.diagnostics)
        case .about: return t(.about)
        }
    }

    var subtitle: String {
        switch self {
        case .overview: return t(.overviewSubtitle)
        case .models: return t(.modelsSubtitle)
        case .calendar: return t(.calendarSubtitle)
        case .costs: return t(.costsSubtitle)
        case .settings: return t(.settingsSubtitle)
        case .diagnostics: return t(.diagnosticsSubtitle)
        case .about: return t(.aboutSubtitle)
        }
    }
}

final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    private func centeredRect(for bounds: NSRect) -> NSRect {
        let horizontalPadding: CGFloat = 12
        let measuredHeight = ceil(cellSize.height)
        let centeredY = bounds.minY + floor((bounds.height - measuredHeight) / 2)
        return NSRect(
            x: bounds.minX + horizontalPadding,
            y: max(bounds.minY, centeredY),
            width: max(0, bounds.width - horizontalPadding * 2),
            height: min(bounds.height, measuredHeight)
        )
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        centeredRect(for: rect)
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        centeredRect(for: rect)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: centeredRect(for: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: centeredRect(for: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

final class UsageDetailsView: NSView, NSTextFieldDelegate {
    private struct CostRingCache {
        let key: String
        let image: NSImage
    }

    private struct CostPageData {
        let key: String
        let estimate: PlanCostEstimate?
        let apiEstimate: APICostEstimate
        let weeklyRows: [CostPeriodRow]
        let monthlyRows: [MonthlySpendRow]
    }

    private struct ContributionWeekSummary {
        let key: String
        let startDay: String
        let endDay: String
        let total: Int64
        let activeDays: Int
        let hitRect: NSRect
        let cellRects: [NSRect]
    }

    private struct ContributionDaySummary {
        let day: DayUsage
        let hitRect: NSRect
    }

    private enum CostOverviewInfo: Hashable {
        case usageRate
        case totalSpend
        case apiEquivalent
        case externalAPI
        case totalWaste

        var title: String {
            switch self {
            case .usageRate: return t(.usageRate)
            case .totalSpend: return t(.totalSpendValue)
            case .apiEquivalent: return t(.apiEquivalent)
            case .externalAPI: return t(.externalAPICost)
            case .totalWaste: return t(.totalWasteValue)
            }
        }

        var hint: String {
            switch self {
            case .usageRate: return t(.usageRateHint)
            case .totalSpend: return t(.totalSpendValueHint)
            case .apiEquivalent: return t(.apiEquivalentCostHint)
            case .externalAPI: return t(.externalAPICostCalculationHint)
            case .totalWaste: return t(.totalWasteValueHint)
            }
        }
    }

    var snapshot: DetailsSnapshot? {
        didSet {
            if let snapshot {
                let report = calendarReport(for: snapshot)
                selectedDay = preferredSelectedDay(in: report, fallback: selectedDay)
            }
            onPreferredHeightChanged?()
            needsDisplay = true
            needsLayout = true
        }
    }
    var isLoading = false { didSet { onPreferredHeightChanged?(); needsDisplay = true; needsLayout = true } }
    fileprivate var onLanguageChanged: ((AppLanguage) -> Void)?
    fileprivate var onNumberUnitStyleChanged: ((NumberUnitStyle) -> Void)?
    fileprivate var onStatusDisplayChanged: ((StatusDisplayOption) -> Void)?
    fileprivate var onQuotaDisplayStyleChanged: ((QuotaDisplayStyle) -> Void)?
    fileprivate var onPlanCostChanged: ((Double) -> Void)?
    fileprivate var onPaymentStartDayChanged: ((String) -> Void)?
    fileprivate var onPaymentCurrencyChanged: ((CurrencyCode) -> Void)?
    fileprivate var onDisplayCurrencyChanged: ((CurrencyCode) -> Void)?
    fileprivate var onChooseLogFolder: (() -> Void)?
    fileprivate var onResetLogFolder: (() -> Void)?
    fileprivate var onOpenLogFolder: (() -> Void)?
    fileprivate var onShowHistoricalEmptyWeeksChanged: ((Bool) -> Void)?
    fileprivate var onLaunchAtLoginChanged: ((Bool) -> Void)?
    fileprivate var onShowCodexStatusChanged: ((Bool) -> Void)?
    fileprivate var onQuotaWarningsChanged: ((Bool) -> Void)?
    fileprivate var onProfileAPITotalsChanged: ((Bool) -> Void)?
    fileprivate var onPreferredHeightChanged: (() -> Void)?
    private var selectedSection: DetailsSection = .overview {
        didSet {
            if selectedSection != .costs {
                hoveredCostHistoryIndex = nil
                hoveredCostOverviewInfo = nil
            }
            if selectedSection != .calendar {
                isHoveringDayValueInfo = false
                isHoveringProfileAPIInfo = false
            }
            if selectedSection != .calendar {
                hoveredContributionWeekKey = nil
            }
            if selectedSection != .overview {
                hoveredContributionDay = nil
            }
            onPreferredHeightChanged?()
            needsDisplay = true
            needsLayout = true
        }
    }
    private var sidebarItemRects: [DetailsSection: NSRect] = [:]
    private var numberUnitOptionRects: [NumberUnitStyle: NSRect] = [:]
    private var statusOptionRects: [StatusDisplayOption: NSRect] = [:]
    private var quotaDisplayStyleRects: [QuotaDisplayStyle: NSRect] = [:]
    private var chooseLogFolderRect: NSRect?
    private var resetLogFolderRect: NSRect?
    private var openLogFolderRect: NSRect?
    private var contributionDayRects: [String: NSRect] = [:]
    private var contributionDaySummaries: [String: ContributionDaySummary] = [:]
    private var hoveredContributionDay: String?
    private var contributionWeekSummaries: [String: ContributionWeekSummary] = [:]
    private var hoveredContributionWeekKey: String?
    private var costHistoryBarRects: [Int: NSRect] = [:]
    private var costHistoryRows: [CostPeriodRow] = []
    private var costOverviewInfoRects: [CostOverviewInfo: NSRect] = [:]
    private var dayValueInfoRect: NSRect?
    private var profileAPIInfoRect: NSRect?
    private var showHistoricalEmptyWeeksToggleRect: NSRect?
    private var selectedDay: String?
    private var hoveredCostHistoryIndex: Int?
    private var hoveredCostOverviewInfo: CostOverviewInfo?
    private var isHoveringDayValueInfo = false
    private var isHoveringProfileAPIInfo = false
    private var selectedCostYear = Calendar.current.component(.year, from: Date())
    private var costRingCache: CostRingCache?
    private var costPageDataCache: CostPageData?
    private var costYearOptionsCacheKey: String?
    private var costYearOptionsCache: [Int] = []
    private let costAmountField: NSTextField = {
        let field = NSTextField()
        field.cell = VerticallyCenteredTextFieldCell(textCell: "")
        return field
    }()
    private let paymentStartDayField: NSTextField = {
        let field = NSTextField()
        field.cell = VerticallyCenteredTextFieldCell(textCell: "")
        return field
    }()
    private let paymentCurrencyPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let displayCurrencyPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let costYearPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let showHistoricalEmptyWeeksSwitch = NSSwitch(frame: .zero)
    private let launchAtLoginSwitch = NSSwitch(frame: .zero)
    private let showCodexStatusSwitch = NSSwitch(frame: .zero)
    private let quotaWarningsSwitch = NSSwitch(frame: .zero)
    private let profileAPITotalsSwitch = NSSwitch(frame: .zero)
    private var isUpdatingCostControls = false
    private var detailsTrackingArea: NSTrackingArea?

    func showUsagePage() {
        selectedSection = .overview
    }

    func showSettingsPage() {
        selectedSection = .settings
    }

    private var visibleCostControlFrames: [NSRect] {
        guard selectedSection == .costs else { return [] }
        return [costYearPopup.frame].filter { !$0.isEmpty }
    }

    private var appBackgroundTop: NSColor {
        NSColor(calibratedRed: 0.055, green: 0.066, blue: 0.086, alpha: 1.0)
    }

    private var appBackgroundBottom: NSColor {
        NSColor(calibratedRed: 0.075, green: 0.090, blue: 0.118, alpha: 1.0)
    }

    private var sidebarBackgroundColor: NSColor {
        NSColor(calibratedRed: 0.046, green: 0.055, blue: 0.073, alpha: 1.0)
    }

    private var panelSurfaceColor: NSColor {
        NSColor(calibratedRed: 0.126, green: 0.148, blue: 0.186, alpha: 0.98)
    }

    private var panelElevatedColor: NSColor {
        NSColor(calibratedRed: 0.154, green: 0.178, blue: 0.222, alpha: 0.98)
    }

    private var inputSurfaceColor: NSColor {
        NSColor(calibratedRed: 0.088, green: 0.105, blue: 0.138, alpha: 1.0)
    }

    private var borderColor: NSColor {
        NSColor.white.withAlphaComponent(0.075)
    }

    private var accentBlue: NSColor {
        NSColor(calibratedRed: 0.365, green: 0.548, blue: 1.0, alpha: 1.0)
    }

    private var accentTeal: NSColor {
        NSColor(calibratedRed: 0.279, green: 0.839, blue: 0.702, alpha: 1.0)
    }

    private var accentAmber: NSColor {
        NSColor(calibratedRed: 0.965, green: 0.724, blue: 0.357, alpha: 1.0)
    }

    private var accentRose: NSColor {
        NSColor(calibratedRed: 0.941, green: 0.478, blue: 0.553, alpha: 1.0)
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupControls()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupControls()
    }

    override func layout() {
        super.layout()
        layoutCostControls()
        layoutSettingsControls()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let detailsTrackingArea {
            removeTrackingArea(detailsTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        detailsTrackingArea = trackingArea
    }

    private func setupControls() {
        costAmountField.isBordered = false
        costAmountField.drawsBackground = false
        costAmountField.focusRingType = .default
        costAmountField.isEditable = true
        costAmountField.isSelectable = true
        costAmountField.isEnabled = true
        costAmountField.font = .monospacedDigitSystemFont(ofSize: 18, weight: .bold)
        costAmountField.alignment = .center
        costAmountField.textColor = .white
        costAmountField.usesSingleLineMode = true
        costAmountField.lineBreakMode = .byTruncatingTail
        costAmountField.delegate = self
        costAmountField.isHidden = true
        addSubview(costAmountField)

        paymentStartDayField.isBordered = false
        paymentStartDayField.drawsBackground = false
        paymentStartDayField.focusRingType = .default
        paymentStartDayField.isEditable = true
        paymentStartDayField.isSelectable = true
        paymentStartDayField.isEnabled = true
        paymentStartDayField.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        paymentStartDayField.alignment = .center
        paymentStartDayField.textColor = .white
        paymentStartDayField.placeholderString = "YYYY-MM-DD"
        paymentStartDayField.usesSingleLineMode = true
        paymentStartDayField.lineBreakMode = .byTruncatingTail
        paymentStartDayField.delegate = self
        paymentStartDayField.isHidden = true
        addSubview(paymentStartDayField)

        showHistoricalEmptyWeeksSwitch.controlSize = .small
        showHistoricalEmptyWeeksSwitch.isHidden = true
        showHistoricalEmptyWeeksSwitch.target = self
        showHistoricalEmptyWeeksSwitch.action = #selector(showHistoricalEmptyWeeksChanged)
        addSubview(showHistoricalEmptyWeeksSwitch)

        launchAtLoginSwitch.controlSize = .small
        launchAtLoginSwitch.isHidden = true
        launchAtLoginSwitch.target = self
        launchAtLoginSwitch.action = #selector(launchAtLoginChanged)
        addSubview(launchAtLoginSwitch)

        showCodexStatusSwitch.controlSize = .small
        showCodexStatusSwitch.isHidden = true
        showCodexStatusSwitch.target = self
        showCodexStatusSwitch.action = #selector(showCodexStatusChanged)
        addSubview(showCodexStatusSwitch)

        quotaWarningsSwitch.controlSize = .small
        quotaWarningsSwitch.isHidden = true
        quotaWarningsSwitch.target = self
        quotaWarningsSwitch.action = #selector(quotaWarningsChanged)
        addSubview(quotaWarningsSwitch)

        profileAPITotalsSwitch.controlSize = .small
        profileAPITotalsSwitch.isHidden = true
        profileAPITotalsSwitch.target = self
        profileAPITotalsSwitch.action = #selector(profileAPITotalsChanged)
        addSubview(profileAPITotalsSwitch)

        for popup in [paymentCurrencyPopup, displayCurrencyPopup, costYearPopup, languagePopup] {
            popup.controlSize = .regular
            popup.font = .systemFont(ofSize: 12, weight: .semibold)
            popup.isBordered = false
            popup.isHidden = true
            popup.wantsLayer = true
            popup.layer?.cornerRadius = 8
            popup.layer?.backgroundColor = inputSurfaceColor.cgColor
            popup.appearance = NSAppearance(named: .darkAqua)
            addSubview(popup)
        }
        paymentCurrencyPopup.removeAllItems()
        paymentCurrencyPopup.addItems(withTitles: CurrencyCode.allCases.map(\.displayTitle))
        displayCurrencyPopup.removeAllItems()
        displayCurrencyPopup.addItems(withTitles: CurrencyCode.allCases.map(\.displayTitle))
        costYearPopup.removeAllItems()
        languagePopup.removeAllItems()
        languagePopup.addItems(withTitles: AppLanguage.allCases.map(\.displayName))
        costAmountField.setAccessibilityLabel(t(.paymentMonthly))
        paymentStartDayField.setAccessibilityLabel(t(.paymentStartDate))
        paymentCurrencyPopup.setAccessibilityLabel(t(.paymentCurrency))
        displayCurrencyPopup.setAccessibilityLabel(t(.displayCurrency))
        costYearPopup.setAccessibilityLabel(t(.costHistory))
        languagePopup.setAccessibilityLabel(t(.interfaceLanguage))
        showHistoricalEmptyWeeksSwitch.setAccessibilityLabel(t(.showPastEmptyWeeks))
        launchAtLoginSwitch.setAccessibilityLabel(t(.launchAtLogin))
        quotaWarningsSwitch.setAccessibilityLabel(t(.quotaWarnings))
        profileAPITotalsSwitch.setAccessibilityLabel(t(.profileAPITotals))
        paymentCurrencyPopup.target = self
        paymentCurrencyPopup.action = #selector(paymentCurrencyPopupChanged)
        displayCurrencyPopup.target = self
        displayCurrencyPopup.action = #selector(displayCurrencyPopupChanged)
        costYearPopup.target = self
        costYearPopup.action = #selector(costYearPopupChanged)
        languagePopup.target = self
        languagePopup.action = #selector(languagePopupChanged)
    }

    private func layoutCostControls() {
        let visible = selectedSection == .costs
        costAmountField.isHidden = !visible
        paymentStartDayField.isHidden = !visible
        paymentCurrencyPopup.isHidden = !visible
        displayCurrencyPopup.isHidden = !visible
        costYearPopup.isHidden = !visible
        showHistoricalEmptyWeeksSwitch.isHidden = true
        showHistoricalEmptyWeeksToggleRect = nil
        guard visible else { return }

        let content = NSRect(x: 220 + 28, y: 28, width: bounds.width - 220 - 56, height: bounds.height - 56)
        let settingsRect = NSRect(x: content.minX, y: content.minY + 78, width: content.width, height: 244)
        let controlWidth = min(300, max(252, settingsRect.width * 0.34))
        let controlX = settingsRect.maxX - controlWidth - 16
        costAmountField.frame = NSRect(x: controlX, y: settingsRect.minY + 28, width: controlWidth, height: 44)
        paymentStartDayField.frame = NSRect(x: controlX, y: settingsRect.minY + 82, width: controlWidth, height: 36)
        paymentCurrencyPopup.frame = NSRect(x: controlX, y: settingsRect.minY + 132, width: controlWidth, height: 36)
        displayCurrencyPopup.frame = NSRect(x: controlX, y: settingsRect.minY + 182, width: controlWidth, height: 36)
        let summaryY = settingsRect.maxY + 16
        let summaryHeight: CGFloat = 168
        let chartY = summaryY + summaryHeight + 16
        let chartRect = NSRect(x: content.minX, y: chartY, width: content.width, height: 332)
        let headerLayout = costHistoryHeaderLayout(chartRect: chartRect)
        costYearPopup.frame = headerLayout.yearRect
        updateCostControlsFromSettings()
    }

    private func layoutSettingsControls() {
        let visible = selectedSection == .settings
        languagePopup.isHidden = !visible
        launchAtLoginSwitch.isHidden = !visible
        showCodexStatusSwitch.isHidden = !visible
        quotaWarningsSwitch.isHidden = !visible
        profileAPITotalsSwitch.isHidden = !visible
        guard visible else { return }

        let content = NSRect(x: 220 + 28, y: 28, width: bounds.width - 220 - 56, height: bounds.height - 56)
        let rect = NSRect(x: content.minX, y: content.minY + 78, width: content.width, height: min(612, content.height - 78))
        let popupWidth = min(300, max(252, rect.width * 0.34))
        languagePopup.frame = NSRect(x: rect.maxX - popupWidth - 16, y: rect.minY + 48, width: popupWidth, height: 36)
        let leftSwitchX = rect.midX - 64
        let rightSwitchX = rect.maxX - 64
        showCodexStatusSwitch.frame = NSRect(x: leftSwitchX, y: rect.minY + 474, width: 48, height: 24)
        launchAtLoginSwitch.frame = NSRect(x: rightSwitchX, y: rect.minY + 474, width: 48, height: 24)
        quotaWarningsSwitch.frame = NSRect(x: leftSwitchX, y: rect.minY + 502, width: 48, height: 24)
        profileAPITotalsSwitch.frame = NSRect(x: rightSwitchX, y: rect.minY + 502, width: 48, height: 24)
        updateLanguagePopupFromSettings()
        updateSettingsControlsFromSystem()
    }

    private func updateLanguagePopupFromSettings() {
        if languagePopup.itemArray.map(\.title) != AppLanguage.allCases.map(\.displayName) {
            languagePopup.removeAllItems()
            languagePopup.addItems(withTitles: AppLanguage.allCases.map(\.displayName))
        }
        if let index = AppLanguage.allCases.firstIndex(of: AppLanguage.current) {
            languagePopup.selectItem(at: index)
        }
    }

    private func updateSettingsControlsFromSystem() {
        guard selectedSection == .settings else { return }
        launchAtLoginSwitch.state = LoginItemManager.isEnabled ? .on : .off
        showCodexStatusSwitch.state = AppSettings.showCodexStatusEnabled ? .on : .off
        quotaWarningsSwitch.state = AppSettings.quotaWarningsEnabled ? .on : .off
        profileAPITotalsSwitch.state = AppSettings.profileAPITotalsEnabled ? .on : .off
    }

    private func updateCostControlsFromSettings() {
        guard selectedSection == .costs else { return }
        isUpdatingCostControls = true
        defer { isUpdatingCostControls = false }
        if costAmountField.currentEditor() == nil {
            costAmountField.stringValue = paymentAmount(AppSettings.monthlyPlanCost)
        }
        if paymentStartDayField.currentEditor() == nil {
            paymentStartDayField.stringValue = effectivePaymentStartDay(in: snapshot?.all)
        }
        showHistoricalEmptyWeeksSwitch.state = AppSettings.showHistoricalEmptyWeeks ? .on : .off
        if let paymentIndex = CurrencyCode.allCases.firstIndex(of: AppSettings.paymentCurrency) {
            paymentCurrencyPopup.selectItem(at: paymentIndex)
        }
        if let displayIndex = CurrencyCode.allCases.firstIndex(of: AppSettings.displayCurrency) {
            displayCurrencyPopup.selectItem(at: displayIndex)
        }
        let years = cachedAvailableCostYears(from: snapshot?.all)
        if !years.contains(selectedCostYear), let last = years.last {
            selectedCostYear = last
        }
        let titles = years.map(String.init)
        if costYearPopup.itemArray.map(\.title) != titles {
            costYearPopup.removeAllItems()
            costYearPopup.addItems(withTitles: titles)
        }
        if let yearIndex = years.firstIndex(of: selectedCostYear) {
            if costYearPopup.indexOfSelectedItem != yearIndex {
                costYearPopup.selectItem(at: yearIndex)
            }
        }
    }

    func preferredDocumentHeight(for width: CGFloat) -> CGFloat {
        let minHeight: CGFloat = selectedSection == .calendar ? 620 : 660
        let normalizedWidth = max(860, width)
        let contentWidth = normalizedWidth - 220 - 56

        let targetHeight: CGFloat
        switch selectedSection {
        case .overview:
            targetHeight = 760
        case .models:
            targetHeight = 660
        case .calendar:
            let gridHeight: CGFloat = normalizedWidth >= 1200 ? 236 : 222
            let detailHeight = selectedDayPanelPreferredHeight(contentWidth: contentWidth)
            targetHeight = 174 + gridHeight + detailHeight
        case .costs:
            let monthlyRows: Int
            if let snapshot {
                let limit = costEstimateLimit(from: snapshot.liveLimits)
                monthlyRows = min(costPageData(for: snapshot, limit: limit, year: selectedCostYear).monthlyRows.count, 6)
            } else {
                monthlyRows = 0
            }
            let monthlyTableHeight = max(140, 54 + CGFloat(max(monthlyRows, 1)) * 18 + 28)
            let annualChartHeight: CGFloat = 332
            let topOffset: CGFloat = 78
            let settingsHeight: CGFloat = 244
            let summaryHeight: CGFloat = 168
            let sectionGap: CGFloat = 16
            let bottomPadding: CGFloat = 44
            let firstBlock = topOffset + settingsHeight + sectionGap + summaryHeight
            let secondBlock = sectionGap + annualChartHeight + sectionGap + monthlyTableHeight
            targetHeight = firstBlock + secondBlock + bottomPadding
        case .diagnostics:
            targetHeight = 714
        case .settings:
            targetHeight = 760
        case .about:
            targetHeight = 580
        }
        return max(minHeight, targetHeight)
    }

    private func selectedDayPanelPreferredHeight(contentWidth: CGFloat) -> CGFloat {
        guard let snapshot else { return 248 }
        if usesProfileAPIReport(for: snapshot) {
            let report = calendarReport(for: snapshot)
            let day = selectedDay.flatMap { selected in report.byDay.first { $0.day == selected } }
                ?? report.byDay.last(where: { $0.usage.total > 0 })
                ?? report.byDay.last
            let localDay = day.flatMap { profileDay in snapshot.all.byDay.first { $0.day == profileDay.day } }
            let apiEstimate = day.map { profileAPIDayEstimate(profileDay: $0, localDay: localDay) }
            let metricsCount = 3 + (apiEstimate?.hasPricedUsage == true ? 1 : 0)
            let startX = min(CGFloat(420), max(CGFloat(292), contentWidth * 0.50))
            let gap: CGFloat = 12
            let availableMetricWidth = max(0, contentWidth - startX - 18)
            let columns = metricsCount > 3 && availableMetricWidth >= 500 ? 4 : min(3, metricsCount)
            let metricRows = Int(ceil(Double(metricsCount) / Double(max(columns, 1))))
            let metricH: CGFloat = 74
            let metricsBottom = CGFloat(42) + CGFloat(metricRows) * metricH + CGFloat(max(0, metricRows - 1)) * gap
            let visibleModelRows = max(1, min(localDay?.modelBreakdown.count ?? 0, 5))
            let minimumModelHeight = 22 + CGFloat(visibleModelRows) * 22
            let modelY = max(CGFloat(134), metricsBottom + 18)
            return max(284, modelY + minimumModelHeight + 18)
        }
        let report = snapshot.all
        let day = selectedDay.flatMap { selected in report.byDay.first { $0.day == selected } }
            ?? report.byDay.last(where: { $0.usage.total > 0 })
            ?? report.byDay.last
        guard let day else { return 160 }

        let limit = costEstimateLimit(from: snapshot.liveLimits)
        let cost = planCostEstimate(report: report, selectedDay: day, limit: limit, quotaReferenceReport: snapshot.costReferenceReport)
        let apiEstimate = APICostEstimator.estimate(day: day)
        let metricsCount = 4 + (cost == nil ? 0 : 1) + (apiEstimate.hasPricedUsage ? 1 : 0)
        let startX: CGFloat = 310
        let horizontalPadding: CGFloat = 36
        let availableMetricWidth = max(180, contentWidth - startX - horizontalPadding)
        let columns: Int
        if metricsCount > 4 {
            columns = availableMetricWidth >= 360 ? 3 : 2
        } else {
            columns = availableMetricWidth >= 460 ? 4 : 2
        }
        let metricH: CGFloat
        switch columns {
        case 4:
            metricH = 72
        case 3:
            metricH = 62
        default:
            metricH = 56
        }
        let metricRows = Int(ceil(Double(metricsCount) / Double(columns)))
        let metricsBottom = 24 + CGFloat(metricRows) * metricH + CGFloat(max(0, metricRows - 1)) * 10
        let visibleModelRows = max(1, min(day.modelBreakdown.count, 5))
        let minimumModelHeight = 22 + CGFloat(visibleModelRows) * 22
        let modelY = max(CGFloat(112), metricsBottom + 12)
        let contentHeight = modelY + minimumModelHeight + 18
        return max(248, contentHeight)
    }

    private func usesProfileAPIReport(for snapshot: DetailsSnapshot) -> Bool {
        AppSettings.profileAPITotalsEnabled && snapshot.accountUsage?.hasData == true
    }

    private func calendarReport(for snapshot: DetailsSnapshot) -> TokenReport {
        guard let report = rawProfileCalendarReport(for: snapshot) else {
            return snapshot.all
        }
        return profileReportWithLocalFallback(report, localReport: snapshot.all)
    }

    private func rawProfileCalendarReport(for snapshot: DetailsSnapshot) -> TokenReport? {
        guard usesProfileAPIReport(for: snapshot),
              let accountUsage = snapshot.accountUsage else {
            return nil
        }
        return accountUsage.report(days: 365)
    }

    private func profileLifetimeTotal(for snapshot: DetailsSnapshot) -> Int64? {
        guard usesProfileAPIReport(for: snapshot),
              let value = snapshot.accountUsage?.summary.lifetimeTokens,
              value > 0 else {
            return nil
        }
        return value
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if selectedSection == .costs {
            updateCostHistoryHover(at: point)
            updateCostOverviewInfoHover(at: point)
        } else {
            if hoveredCostHistoryIndex != nil {
                hoveredCostHistoryIndex = nil
                needsDisplay = true
            }
            if hoveredCostOverviewInfo != nil {
                hoveredCostOverviewInfo = nil
                needsDisplay = true
            }
        }
        updateDayValueInfoHover(at: point)
        updateProfileAPIInfoHover(at: point)
        updateContributionDayHover(at: point)
        updateContributionWeekHover(at: point)
    }

    override func mouseExited(with event: NSEvent) {
        hoveredCostHistoryIndex = nil
        hoveredCostOverviewInfo = nil
        hoveredContributionDay = nil
        hoveredContributionWeekKey = nil
        isHoveringDayValueInfo = false
        isHoveringProfileAPIInfo = false
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        var shouldRedraw = false
        if hoveredCostHistoryIndex != nil {
            hoveredCostHistoryIndex = nil
            shouldRedraw = true
        }
        if hoveredCostOverviewInfo != nil {
            hoveredCostOverviewInfo = nil
            shouldRedraw = true
        }
        if hoveredContributionDay != nil {
            hoveredContributionDay = nil
            shouldRedraw = true
        }
        if hoveredContributionWeekKey != nil {
            hoveredContributionWeekKey = nil
            shouldRedraw = true
        }
        if isHoveringDayValueInfo {
            isHoveringDayValueInfo = false
            shouldRedraw = true
        }
        if isHoveringProfileAPIInfo {
            isHoveringProfileAPIInfo = false
            shouldRedraw = true
        }
        if shouldRedraw {
            needsDisplay = true
        }
        super.scrollWheel(with: event)
    }

    private func updateContributionDayHover(at point: CGPoint) {
        guard selectedSection == .overview else {
            if hoveredContributionDay != nil {
                hoveredContributionDay = nil
                needsDisplay = true
            }
            return
        }
        let match = contributionDaySummaries.first {
            $0.value.hitRect.insetBy(dx: -3, dy: -3).contains(point)
        }
        let newDay = match?.key
        if hoveredContributionDay != newDay {
            hoveredContributionDay = newDay
            needsDisplay = true
        }
    }

    private func updateContributionWeekHover(at point: CGPoint) {
        guard selectedSection == .calendar else {
            if hoveredContributionWeekKey != nil {
                hoveredContributionWeekKey = nil
                needsDisplay = true
            }
            return
        }
        let match = contributionWeekSummaries.values.first {
            $0.hitRect.insetBy(dx: -3, dy: -3).contains(point)
        }
        let newKey = match?.key
        if hoveredContributionWeekKey != newKey {
            hoveredContributionWeekKey = newKey
            needsDisplay = true
        }
    }

    private func updateCostHistoryHover(at point: CGPoint) {
        let match = costHistoryBarRects.first { $0.value.insetBy(dx: -4, dy: -4).contains(point) }
        let newIndex = match?.key
        if hoveredCostHistoryIndex != newIndex {
            hoveredCostHistoryIndex = newIndex
            needsDisplay = true
        }
    }

    private func updateCostOverviewInfoHover(at point: CGPoint) {
        let match = costOverviewInfoRects.first { $0.value.insetBy(dx: -4, dy: -4).contains(point) }
        let newInfo = match?.key
        if hoveredCostOverviewInfo != newInfo {
            hoveredCostOverviewInfo = newInfo
            needsDisplay = true
        }
    }

    private func updateDayValueInfoHover(at point: CGPoint) {
        let hovering = selectedSection == .calendar && (dayValueInfoRect?.contains(point) == true)
        if hovering != isHoveringDayValueInfo {
            isHoveringDayValueInfo = hovering
            needsDisplay = true
        }
    }

    private func updateProfileAPIInfoHover(at point: CGPoint) {
        let hovering = selectedSection == .calendar && (profileAPIInfoRect?.insetBy(dx: -4, dy: -4).contains(point) == true)
        if hovering != isHoveringProfileAPIInfo {
            isHoveringProfileAPIInfo = hovering
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for (section, rect) in sidebarItemRects where rect.contains(point) {
            selectedSection = section
            if section == .calendar, let report = snapshot?.all {
                selectedDay = preferredSelectedDay(in: report, fallback: selectedDay)
            }
            return
        }
        if selectedSection == .settings {
            for (style, rect) in numberUnitOptionRects where rect.contains(point) {
                onNumberUnitStyleChanged?(style)
                return
            }
            for (option, rect) in statusOptionRects where rect.contains(point) {
                onStatusDisplayChanged?(option)
                return
            }
            for (style, rect) in quotaDisplayStyleRects where rect.contains(point) {
                onQuotaDisplayStyleChanged?(style)
                return
            }
            if chooseLogFolderRect?.contains(point) == true {
                onChooseLogFolder?()
                return
            }
            if resetLogFolderRect?.contains(point) == true {
                onResetLogFolder?()
                return
            }
            if openLogFolderRect?.contains(point) == true {
                onOpenLogFolder?()
                return
            }
        }
        if selectedSection == .costs,
           showHistoricalEmptyWeeksToggleRect?.insetBy(dx: -8, dy: -6).contains(point) == true {
            onShowHistoricalEmptyWeeksChanged?(!AppSettings.showHistoricalEmptyWeeks)
            hoveredCostHistoryIndex = nil
            needsDisplay = true
            needsLayout = true
            return
        }
        for (day, rect) in contributionDayRects where rect.insetBy(dx: -2, dy: -2).contains(point) {
            selectedDay = day
            AppSettings.selectedCalendarDay = day
            selectedSection = .calendar
            return
        }
        super.mouseDown(with: event)
    }

    private func preferredSelectedDay(in report: TokenReport, fallback: String?) -> String? {
        if let global = AppSettings.selectedCalendarDay,
           report.byDay.contains(where: { $0.day == global }) {
            return global
        }
        if let fallback,
           report.byDay.contains(where: { $0.day == fallback }) {
            return fallback
        }
        return report.byDay.last(where: { $0.usage.total > 0 })?.day ?? report.byDay.last?.day
    }

    @objc private func paymentCurrencyPopupChanged() {
        guard !isUpdatingCostControls,
              paymentCurrencyPopup.indexOfSelectedItem >= 0 else { return }
        let currency = CurrencyCode.allCases[paymentCurrencyPopup.indexOfSelectedItem]
        onPaymentCurrencyChanged?(currency)
        needsDisplay = true
        needsLayout = true
    }

    @objc private func displayCurrencyPopupChanged() {
        guard !isUpdatingCostControls,
              displayCurrencyPopup.indexOfSelectedItem >= 0 else { return }
        let currency = CurrencyCode.allCases[displayCurrencyPopup.indexOfSelectedItem]
        onDisplayCurrencyChanged?(currency)
        needsDisplay = true
    }

    @objc private func costYearPopupChanged() {
        guard !isUpdatingCostControls,
              costYearPopup.indexOfSelectedItem >= 0,
              let title = costYearPopup.selectedItem?.title,
              let year = Int(title) else { return }
        selectedCostYear = year
        hoveredCostHistoryIndex = nil
        needsDisplay = true
    }

    @objc private func languagePopupChanged() {
        guard languagePopup.indexOfSelectedItem >= 0 else { return }
        let language = AppLanguage.allCases[languagePopup.indexOfSelectedItem]
        onLanguageChanged?(language)
        needsDisplay = true
        needsLayout = true
    }

    @objc private func showHistoricalEmptyWeeksChanged() {
        guard !isUpdatingCostControls else { return }
        onShowHistoricalEmptyWeeksChanged?(showHistoricalEmptyWeeksSwitch.state == .on)
        hoveredCostHistoryIndex = nil
        needsDisplay = true
        needsLayout = true
    }

    @objc private func launchAtLoginChanged() {
        onLaunchAtLoginChanged?(launchAtLoginSwitch.state == .on)
        updateSettingsControlsFromSystem()
        needsDisplay = true
    }

    @objc private func showCodexStatusChanged() {
        onShowCodexStatusChanged?(showCodexStatusSwitch.state == .on)
        updateSettingsControlsFromSystem()
        needsDisplay = true
        needsLayout = true
    }

    @objc private func quotaWarningsChanged() {
        onQuotaWarningsChanged?(quotaWarningsSwitch.state == .on)
        updateSettingsControlsFromSystem()
        needsDisplay = true
    }

    @objc private func profileAPITotalsChanged() {
        onProfileAPITotalsChanged?(profileAPITotalsSwitch.state == .on)
        updateSettingsControlsFromSystem()
        needsDisplay = true
        needsLayout = true
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === costAmountField {
            let sanitized = String(costAmountField.stringValue.filter { "0123456789.".contains($0) })
            guard let value = Double(sanitized), value >= 0 else {
                updateCostControlsFromSettings()
                return
            }
            onPlanCostChanged?(value)
            costAmountField.stringValue = paymentAmount(value)
            needsDisplay = true
            needsLayout = true
            return
        }
        if field === paymentStartDayField {
            let value = paymentStartDayField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard dayFormatter().date(from: value) != nil else {
                updateCostControlsFromSettings()
                return
            }
            onPaymentStartDayChanged?(value)
            needsDisplay = true
            needsLayout = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGradient(starting: appBackgroundTop, ending: appBackgroundBottom)?.draw(in: bounds, angle: -90)

        let sidebarWidth: CGFloat = 220
        sidebarBackgroundColor.setFill()
        NSRect(x: 0, y: 0, width: sidebarWidth, height: bounds.height).fill()
        borderColor.setStroke()
        NSBezierPath(rect: NSRect(x: sidebarWidth, y: 0, width: 1, height: bounds.height)).stroke()

        drawSidebar(width: sidebarWidth)

        let content = NSRect(x: sidebarWidth + 28, y: 28, width: bounds.width - sidebarWidth - 56, height: bounds.height - 56)
        drawText(t(.usageDetails), rect: NSRect(x: content.minX, y: content.minY, width: content.width, height: 34), font: .systemFont(ofSize: 26, weight: .bold), color: .white)
        drawText(selectedSection.subtitle, rect: NSRect(x: content.minX, y: content.minY + 36, width: content.width, height: 20), font: .systemFont(ofSize: 13, weight: .medium), color: NSColor.white.withAlphaComponent(0.56))
        contributionDayRects.removeAll()
        contributionDaySummaries.removeAll()
        contributionWeekSummaries.removeAll()
        costHistoryBarRects.removeAll()
        costHistoryRows.removeAll()
        costOverviewInfoRects.removeAll()
        dayValueInfoRect = nil
        profileAPIInfoRect = nil
        numberUnitOptionRects.removeAll()
        statusOptionRects.removeAll()
        quotaDisplayStyleRects.removeAll()
        chooseLogFolderRect = nil
        resetLogFolderRect = nil
        openLogFolderRect = nil

        guard let snapshot else {
            drawText(isLoading ? t(.loadingUsageDetails) : t(.noDataLoaded), rect: NSRect(x: content.minX, y: content.minY + 92, width: content.width, height: 24), font: .systemFont(ofSize: 15, weight: .semibold), color: NSColor.white.withAlphaComponent(0.56))
            return
        }

        switch selectedSection {
        case .overview:
            drawOverview(snapshot: snapshot, content: content)
        case .models:
            drawModelsPage(snapshot: snapshot, content: content)
        case .calendar:
            drawCalendarPage(snapshot: snapshot, content: content)
        case .costs:
            drawCostPage(snapshot: snapshot, content: content)
        case .settings:
            drawSettingsPage(content: content)
        case .diagnostics:
            drawDiagnosticsPage(snapshot: snapshot, content: content)
        case .about:
            drawAboutPage(snapshot: snapshot, content: content)
        }

        if selectedSection == .costs {
            drawCostHistoryTooltip()
            drawCostOverviewInfoTooltip()
        } else if selectedSection == .calendar {
            drawDayValueInfoTooltip()
            drawProfileAPIInfoTooltip()
        }
    }

    private func drawSidebar(width: CGFloat) {
        sidebarItemRects.removeAll()
        drawText("Codex", rect: NSRect(x: 28, y: 28, width: width - 56, height: 28), font: .systemFont(ofSize: 24, weight: .bold), color: .white)
        drawText(t(.tokenMeter), rect: NSRect(x: 28, y: 58, width: width - 56, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: NSColor.white.withAlphaComponent(0.52))
        for (index, section) in DetailsSection.allCases.enumerated() {
            let y = CGFloat(118 + index * 58)
            let rect = NSRect(x: 18, y: y, width: width - 36, height: 42)
            sidebarItemRects[section] = rect
            if section == selectedSection {
                accentBlue.withAlphaComponent(0.82).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
            }
            let textColor = section == selectedSection ? NSColor.white : NSColor.white.withAlphaComponent(0.82)
            drawText(section.title, rect: NSRect(x: rect.minX + 22, y: rect.minY + 10, width: rect.width - 44, height: 22), font: .systemFont(ofSize: 15, weight: .semibold), color: textColor)
        }
    }

    private func drawOverview(snapshot: DetailsSnapshot, content: NSRect) {
        let cardsY = content.minY + 78
        let quotaY = cardsY + 98
        let modelsY = quotaY + 136
        let gridY = modelsY + 146
        let gridReport = calendarReport(for: snapshot)
        let gridTitle = usesProfileAPIReport(for: snapshot)
            ? "\(t(.pastYear)) · \(t(.profileAPISource))"
            : t(.pastYear)
        drawMetricCards(snapshot: snapshot, content: content)
        drawQuotaRows(snapshot: snapshot, content: content, y: quotaY, height: 120)
        drawModelRows(snapshot: snapshot, content: content, y: modelsY, height: 130, maxRows: 4)
        let gridHeight = contributionGridPreferredHeight(report: gridReport, width: content.width, compact: true)
        let gridRect = NSRect(x: content.minX, y: gridY, width: content.width, height: min(gridHeight, max(168, content.maxY - gridY)))
        drawContributionGrid(report: gridReport, rect: gridRect, title: gridTitle, compact: true)
    }

    private func drawMetricCards(snapshot: DetailsSnapshot, content: NSRect) {
        let gap: CGFloat = 12
        let apiEstimate = APICostEstimator.estimate(report: snapshot.all)
        let allTotal = profileLifetimeTotal(for: snapshot) ?? snapshot.all.usage.total
        let allTitle = profileLifetimeTotal(for: snapshot) == nil ? t(.all) : "\(t(.all)) API"
        let cards: [(String, String, NSColor)] = [
            (allTitle, compactDashboardTotal(allTotal), profileLifetimeTotal(for: snapshot) == nil ? .systemGreen : accentTeal),
            (AppSettings.modelLimitSegmentTitle, compactDashboardTotal(snapshot.spark.usage.total), .systemCyan),
            (t(.other), compactDashboardTotal(snapshot.other.usage.total), .systemOrange),
            (t(.cache), String(format: "%.0f%%", snapshot.all.usage.cachePercent), .systemTeal),
            (t(.apiEquivalent), compactDisplayAPIMoney(apiEstimate.usdValue), accentTeal)
        ]
        let cardW = (content.width - gap * CGFloat(cards.count - 1)) / CGFloat(cards.count)
        let valueFontSize: CGFloat = cardW < 136 ? 18 : (cardW < 176 ? 21 : 24)
        let titleFontSize: CGFloat = cardW < 136 ? 11 : 12
        for (index, card) in cards.enumerated() {
            let rect = NSRect(x: content.minX + CGFloat(index) * (cardW + gap), y: content.minY + 78, width: cardW, height: 82)
            drawPanel(rect)
            drawText(card.0, rect: NSRect(x: rect.minX + 14, y: rect.minY + 12, width: rect.width - 28, height: 18), font: .systemFont(ofSize: titleFontSize, weight: .semibold), color: NSColor.white.withAlphaComponent(0.52))
            drawText(card.1, rect: NSRect(x: rect.minX + 14, y: rect.minY + 34, width: rect.width - 28, height: 30), font: .monospacedDigitSystemFont(ofSize: valueFontSize, weight: .bold), color: card.2)
        }
    }

    private func drawQuotaRows(snapshot: DetailsSnapshot, content: NSRect, y: CGFloat, height: CGFloat) {
        let rect = NSRect(x: content.minX, y: y, width: content.width, height: height)
        drawPanel(rect)
        drawText(t(.quotaViews), rect: NSRect(x: rect.minX + 16, y: rect.minY + 12, width: rect.width - 32, height: 20), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
        let rows = [
            (t(.all), t(.allDescription), snapshot.all),
            (AppSettings.modelLimitSegmentTitle, AppSettings.modelLimitName, snapshot.spark),
            (t(.other), t(.otherDescription), snapshot.other)
        ]
        let outputW: CGFloat = 92
        let inputW: CGFloat = 104
        let totalW: CGFloat = 104
        let gap: CGFloat = 14
        let outputX = rect.maxX - 16 - outputW
        let inputX = outputX - gap - inputW
        let totalX = inputX - gap - totalW
        let descriptionX = rect.minX + 104
        let descriptionW = max(92, totalX - descriptionX - 18)
        let headerY = rect.minY + 34
        drawRight(t(.total), rect: NSRect(x: totalX, y: headerY, width: totalW, height: 14), color: NSColor.white.withAlphaComponent(0.38), font: .systemFont(ofSize: 10, weight: .bold))
        drawRight(t(.input), rect: NSRect(x: inputX, y: headerY, width: inputW, height: 14), color: NSColor.white.withAlphaComponent(0.38), font: .systemFont(ofSize: 10, weight: .bold))
        drawRight(t(.output), rect: NSRect(x: outputX, y: headerY, width: outputW, height: 14), color: NSColor.white.withAlphaComponent(0.38), font: .systemFont(ofSize: 10, weight: .bold))
        for (index, row) in rows.enumerated() {
            let y = rect.minY + 52 + CGFloat(index) * 22
            drawText(row.0, rect: NSRect(x: rect.minX + 16, y: y, width: 90, height: 18), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
            drawText(row.1, rect: NSRect(x: descriptionX, y: y, width: descriptionW, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.45))
            drawRight(compactDashboardMetric(row.2.usage.total), rect: NSRect(x: totalX, y: y, width: totalW, height: 18), color: .white)
            drawRight(compactDashboardMetric(row.2.usage.input), rect: NSRect(x: inputX, y: y, width: inputW, height: 18), color: NSColor.white.withAlphaComponent(0.58))
            drawRight(compactDashboardMetric(row.2.usage.output), rect: NSRect(x: outputX, y: y, width: outputW, height: 18), color: NSColor.white.withAlphaComponent(0.58))
        }
    }

    private func drawModelRows(snapshot: DetailsSnapshot, content: NSRect, y: CGFloat, height: CGFloat, maxRows: Int) {
        let rect = NSRect(x: content.minX, y: y, width: content.width, height: height)
        drawPanel(rect)
        drawText(t(.models), rect: NSRect(x: rect.minX + 16, y: rect.minY + 12, width: rect.width - 32, height: 20), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
        let models = Array(snapshot.all.modelBreakdown.prefix(maxRows))
        if models.isEmpty {
            drawText(t(.noModelLabelsFound), rect: NSRect(x: rect.minX + 16, y: rect.minY + 48, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }
        for (index, model) in models.enumerated() {
            let y = rect.minY + 40 + CGFloat(index) * 20
            drawText(model.name, rect: NSRect(x: rect.minX + 16, y: y, width: rect.width - 320, height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: .white)
            drawRight(compact(model.usage.total), rect: NSRect(x: rect.maxX - 300, y: y, width: 90, height: 18), color: .white)
            drawRight("\(model.sessions) \(t(.sessions).lowercased())", rect: NSRect(x: rect.maxX - 204, y: y, width: 90, height: 18), color: NSColor.white.withAlphaComponent(0.52))
            drawRight("\(model.events) \(t(.events).lowercased())", rect: NSRect(x: rect.maxX - 108, y: y, width: 92, height: 18), color: NSColor.white.withAlphaComponent(0.52))
        }
    }

    private func drawMonthlySpendPanel(snapshot: DetailsSnapshot, content: NSRect, y: CGFloat, height: CGFloat) {
        let rect = NSRect(x: content.minX, y: y, width: content.width, height: height)
        drawPanel(rect)
        drawText(t(.monthlySpendHistory), rect: NSRect(x: rect.minX + 16, y: rect.minY + 12, width: 220, height: 20), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
        let rows = monthlySpendRows(report: snapshot.all, limit: costEstimateLimit(from: snapshot.liveLimits))
        guard !rows.isEmpty else {
            drawText(t(.planCostUnavailable), rect: NSRect(x: rect.minX + 16, y: rect.minY + 48, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }
        let visible = Array(rows.prefix(4))
        drawRight(t(.total), rect: NSRect(x: rect.maxX - 210, y: rect.minY + 24, width: 110, height: 14), color: NSColor.white.withAlphaComponent(0.40), font: .systemFont(ofSize: 10, weight: .bold))
        drawRight("%", rect: NSRect(x: rect.maxX - 84, y: rect.minY + 24, width: 68, height: 14), color: NSColor.white.withAlphaComponent(0.40), font: .systemFont(ofSize: 10, weight: .bold))
        for (index, row) in visible.enumerated() {
            let rowY = rect.minY + 42 + CGFloat(index) * 16
            drawText(row.month, rect: NSRect(x: rect.minX + 16, y: rowY, width: 72, height: 14), font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold), color: .white)
            drawRight(displayMoney(row.usedValue), rect: NSRect(x: rect.maxX - 210, y: rowY, width: 110, height: 14), color: .white, font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold))
            drawRight(String(format: "%.0f%%", row.usedPercentOfPlan), rect: NSRect(x: rect.maxX - 84, y: rowY, width: 68, height: 14), color: NSColor.white.withAlphaComponent(0.52), font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold))
        }
    }

    private func drawModelsPage(snapshot: DetailsSnapshot, content: NSRect) {
        drawQuotaRows(snapshot: snapshot, content: content, y: content.minY + 78, height: 128)
        drawModelRows(snapshot: snapshot, content: content, y: content.minY + 222, height: 264, maxRows: 10)
        let noteRect = NSRect(x: content.minX, y: content.minY + 502, width: content.width, height: min(76, content.maxY - (content.minY + 502)))
        drawPanel(noteRect)
        drawText(t(.modelGroupingNote), rect: NSRect(x: noteRect.minX + 16, y: noteRect.minY + 16, width: noteRect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.62))
        drawText(t(.modelMissingNote), rect: NSRect(x: noteRect.minX + 16, y: noteRect.minY + 40, width: noteRect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
    }

    private func drawDiagnosticsPage(snapshot: DetailsSnapshot, content: NSRect) {
        let sourceRect = NSRect(x: content.minX, y: content.minY + 78, width: content.width, height: 268)
        drawPanel(sourceRect)
        drawText(t(.sourceHealth), rect: NSRect(x: sourceRect.minX + 16, y: sourceRect.minY + 14, width: 220, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        drawDiagnosticRows(sourceDiagnostics(snapshot: snapshot), rect: NSRect(x: sourceRect.minX + 16, y: sourceRect.minY + 48, width: sourceRect.width - 32, height: sourceRect.height - 64))

        let apiRect = NSRect(x: content.minX, y: sourceRect.maxY + 16, width: content.width, height: 124)
        drawPanel(apiRect)
        drawText(t(.externalAPICost), rect: NSRect(x: apiRect.minX + 16, y: apiRect.minY + 14, width: 220, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        drawText(t(.externalAPICostHint), rect: NSRect(x: apiRect.minX + 16, y: apiRect.minY + 40, width: apiRect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.52))
        drawDiagnosticRows(apiDiagnostics(), rect: NSRect(x: apiRect.minX + 16, y: apiRect.minY + 66, width: apiRect.width - 32, height: 44))

        let toolsRect = NSRect(x: content.minX, y: apiRect.maxY + 16, width: content.width, height: 168)
        drawPanel(toolsRect)
        drawText(t(.otherTools), rect: NSRect(x: toolsRect.minX + 16, y: toolsRect.minY + 14, width: 220, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        drawDiagnosticRows(otherToolDiagnostics(), rect: NSRect(x: toolsRect.minX + 16, y: toolsRect.minY + 48, width: toolsRect.width - 32, height: toolsRect.height - 64))
    }

    private func drawDiagnosticRows(_ rows: [(String, String, NSColor)], rect: NSRect) {
        let rowHeight = min(CGFloat(28), rect.height / CGFloat(max(rows.count, 1)))
        for (index, row) in rows.enumerated() {
            let y = rect.minY + CGFloat(index) * rowHeight
            guard y + min(22, rowHeight) <= rect.maxY + 0.5 else { break }
            drawText(row.0, rect: NSRect(x: rect.minX, y: y + 2, width: min(220, rect.width * 0.34), height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(0.58))
            let dot = NSRect(x: rect.maxX - 10, y: y + max(5, (rowHeight - 8) / 2), width: 8, height: 8)
            row.2.setFill()
            NSBezierPath(ovalIn: dot).fill()
            drawRight(row.1, rect: NSRect(x: rect.minX + rect.width * 0.34, y: y + 1, width: rect.width * 0.64 - 18, height: 18), color: .white, font: .systemFont(ofSize: 12, weight: .semibold))
        }
    }

    private func sourceDiagnostics(snapshot: DetailsSnapshot) -> [(String, String, NSColor)] {
        let cliPath = LiveRateLimitReader.codexExecutablePath()
        let authURL = AppSettings.defaultCodexHomeURL.appendingPathComponent("auth.json")
        let liveText = snapshot.liveLimits.isEmpty
            ? t(.liveLimitUnavailable)
            : "\(snapshot.liveLimits.count) windows"
        let serviceText = snapshot.serviceStatus.map { localizedCodexStatus($0.overallStatus) } ?? t(.codexStatusUnavailable)
        let serviceColor = snapshot.serviceStatus.map { codexStatusColor($0.overallStatus) } ?? accentAmber
        let incidentText = snapshot.serviceStatus?.activeIncident?.name ?? t(.codexNoActiveIncident)
        let incidentColor = snapshot.serviceStatus?.activeIncident.map { codexStatusColor($0.status) } ?? NSColor.white.withAlphaComponent(0.58)
        let profileText: String
        let profileColor: NSColor
        if !AppSettings.profileAPITotalsEnabled {
            profileText = t(.disabled)
            profileColor = accentAmber
        } else if let accountUsage = snapshot.accountUsage, accountUsage.hasData {
            profileText = accountUsage.summary.lifetimeTokens.map { compact($0) } ?? "\(accountUsage.dailyUsageBuckets.count) days"
            profileColor = accentTeal
        } else {
            profileText = t(.liveLimitUnavailable)
            profileColor = accentRose
        }
        let rollouts = AppSettings.logFolderURLs.reduce(0) { $0 + rolloutCount(in: $1, modifiedWithinDays: 14) }
        return [
            ("Codex CLI", cliPath ?? t(.fileMissing), cliPath == nil ? accentRose : accentTeal),
            ("auth.json", FileManager.default.fileExists(atPath: authURL.path) ? t(.filePresent) : t(.fileMissing), FileManager.default.fileExists(atPath: authURL.path) ? accentTeal : accentAmber),
            (t(.liveQuota), liveText, snapshot.liveLimits.isEmpty ? accentRose : accentTeal),
            (t(.codexStatus), serviceText, serviceColor),
            (t(.codexIncident), incidentText, incidentColor),
            (t(.profileAPITotals), profileText, profileColor),
            (t(.modelLimit), "\(AppSettings.modelLimitName) / \(AppSettings.modelLimitID)", accentTeal),
            (t(.logFolder), "\(AppSettings.logFolderURLs.count) roots", AppSettings.logFolderURLs.isEmpty ? accentRose : accentTeal),
            (t(.recentRollouts), "\(rollouts) files / 14d", rollouts > 0 ? accentTeal : accentAmber),
            (t(.quotaWarnings), AppSettings.quotaWarningsEnabled ? t(.enabled) : t(.disabled), AppSettings.quotaWarningsEnabled ? accentTeal : accentAmber)
        ]
    }

    private func apiDiagnostics() -> [(String, String, NSColor)] {
        let url = AppSettings.externalAPICostURL
        if let snapshot = ExternalAPICostStore.read(url: url), snapshot.hasData {
            let tokenPart = snapshot.totalTokens > 0 ? " · \(compact(snapshot.totalTokens)) tokens" : ""
            return [
                ("api-usage.json", "\(displayAPIMoney(snapshot.usdValue))\(tokenPart)", accentTeal),
                ("Path", shortenedPath(url.path), NSColor.white.withAlphaComponent(0.62))
            ]
        }
        return [
            ("api-usage.json", t(.fileMissing), accentAmber),
            ("Path", shortenedPath(url.path), NSColor.white.withAlphaComponent(0.62))
        ]
    }

    private func otherToolDiagnostics() -> [(String, String, NSColor)] {
        let home = NSHomeDirectory()
        let probes: [(String, String, Bool)] = [
            ("Codex", AppSettings.logFolderDisplayPath, true),
            ("Claude Code", "\(home)/.claude/projects", false),
            ("Cursor", "\(home)/Library/Application Support/Cursor", false),
            ("OpenCode", "\(home)/.local/share/opencode", false),
            ("Gemini CLI", "\(home)/.gemini", false)
        ]
        return probes.map { name, path, tracked in
            let exists = FileManager.default.fileExists(atPath: path)
            let value: String
            if tracked {
                value = t(.tracked)
            } else if exists {
                value = t(.detectedNotTracked)
            } else {
                value = t(.fileMissing)
            }
            let color: NSColor = tracked ? accentTeal : (exists ? accentAmber : NSColor.white.withAlphaComponent(0.36))
            return (name, value, color)
        }
    }

    private func rolloutCount(in root: URL, modifiedWithinDays days: Int) -> Int {
        let start = Date().addingTimeInterval(-TimeInterval(days) * 24 * 3600)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var count = 0
        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasPrefix("rollout-"), url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if (values?.contentModificationDate ?? .distantPast) >= start {
                count += 1
            }
        }
        return count
    }

    private func shortenedPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path.count > 72 ? "..." + path.suffix(69) : path
    }

    private func drawCalendarPage(snapshot: DetailsSnapshot, content: NSRect) {
        let report = calendarReport(for: snapshot)
        let title = usesProfileAPIReport(for: snapshot)
            ? "\(t(.tokenActivity)) · \(t(.profileAPISource))"
            : t(.tokenActivity)
        let preferredGridHeight = contributionGridPreferredHeight(report: report, width: content.width, compact: false)
        let gridHeight = min(preferredGridHeight, max(214, content.height * 0.36))
        let gridRect = NSRect(x: content.minX, y: content.minY + 78, width: content.width, height: gridHeight)
        drawContributionGrid(report: report, rect: gridRect, title: title, compact: false)

        let available = max(248, content.maxY - gridRect.maxY - 16)
        let preferredHeight = selectedDayPanelPreferredHeight(contentWidth: content.width)
        let detailRect = NSRect(x: content.minX, y: gridRect.maxY + 16, width: content.width, height: min(preferredHeight, available))
        if usesProfileAPIReport(for: snapshot) {
            drawProfileSelectedDayPanel(snapshot: snapshot, report: report, rect: detailRect)
        } else {
            drawSelectedDayPanel(snapshot: snapshot, rect: detailRect)
        }
    }

    private func reportCostSignature(_ report: TokenReport?) -> String {
        guard let report else { return "none" }
        let first = report.byDay.first
        let last = report.byDay.last
        return [
            String(format: "%.3f", report.scannedAt.timeIntervalSince1970),
            "\(report.events)",
            "\(report.turns)",
            "\(report.usage.total)",
            "\(report.usage.input)",
            "\(report.usage.cachedInput)",
            "\(report.usage.output)",
            "\(report.modelBreakdown.count)",
            "\(report.byDay.count)",
            first?.day ?? "",
            "\(first?.usage.total ?? 0)",
            last?.day ?? "",
            "\(last?.usage.total ?? 0)"
        ].joined(separator: "|")
    }

    private func cachedAvailableCostYears(from report: TokenReport?) -> [Int] {
        let key = [
            reportCostSignature(report),
            AppSettings.paymentStartDay ?? "",
            todayKey()
        ].joined(separator: "|")
        if costYearOptionsCacheKey == key {
            return costYearOptionsCache
        }
        let years = availableCostYears(from: report)
        costYearOptionsCacheKey = key
        costYearOptionsCache = years
        return years
    }

    private func costPageDataKey(snapshot: DetailsSnapshot, limit: LiveRateLimit?, year: Int) -> String {
        let weekly = limit?.secondary
        return [
            reportCostSignature(snapshot.all),
            "\(year)",
            AppLanguage.current.rawValue,
            String(format: "%.4f", AppSettings.monthlyPlanCost),
            AppSettings.paymentStartDay ?? "",
            AppSettings.paymentCurrency.rawValue,
            AppSettings.showHistoricalEmptyWeeks ? "1" : "0",
            String(format: "%.4f", weekly?.usedPercent ?? -1),
            String(format: "%.4f", weekly?.remainingPercent ?? -1),
            "\(weekly?.windowMinutes ?? 0)",
            "\(snapshot.costReferenceReport?.usage.total ?? -1)",
            String(format: "%.3f", snapshot.costReferenceReport?.scannedAt.timeIntervalSince1970 ?? -1),
            todayKey()
        ].joined(separator: "|")
    }

    private func costPageData(for snapshot: DetailsSnapshot, limit: LiveRateLimit?, year: Int) -> CostPageData {
        let key = costPageDataKey(snapshot: snapshot, limit: limit, year: year)
        if let cached = costPageDataCache, cached.key == key {
            return cached
        }
        let data = CostPageData(
            key: key,
            estimate: planCostEstimate(report: snapshot.all, selectedDay: nil, limit: limit, quotaReferenceReport: snapshot.costReferenceReport),
            apiEstimate: APICostEstimator.estimate(report: snapshot.all),
            weeklyRows: weeklySpendRows(report: snapshot.all, limit: limit, year: year, quotaReferenceReport: snapshot.costReferenceReport),
            monthlyRows: monthlySpendRows(report: snapshot.all, limit: limit, year: year, quotaReferenceReport: snapshot.costReferenceReport)
        )
        costPageDataCache = data
        return data
    }

    private func drawCostOverviewPanel(estimate: PlanCostEstimate?, apiEstimate: APICostEstimate, rect: NSRect) {
        drawPanel(rect)
        let externalAPI = ExternalAPICostStore.read()
        guard let estimate else {
            if apiEstimate.hasUsage {
                let coverage = String(format: "%.0f%%", apiEstimate.coveragePercent)
                drawText(t(.apiEquivalent), rect: NSRect(x: rect.minX + 18, y: rect.minY + 20, width: rect.width - 36, height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(0.56))
                drawText(displayAPIMoney(apiEstimate.usdValue), rect: NSRect(x: rect.minX + 18, y: rect.minY + 48, width: rect.width - 36, height: 34), font: .monospacedDigitSystemFont(ofSize: 26, weight: .bold), color: accentTeal)
                drawText("\(coverage) \(t(.priced)) · \(t(.apiEquivalentHint))", rect: NSRect(x: rect.minX + 18, y: rect.minY + 92, width: rect.width - 36, height: 18), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.48))
                let unavailableY: CGFloat = externalAPI?.hasData == true ? 138 : 124
                if let externalAPI, externalAPI.hasData {
                    drawCostOverviewRow(title: t(.externalAPICost), value: displayAPIMoney(externalAPI.usdValue), color: accentAmber, rect: NSRect(x: rect.minX + 18, y: rect.minY + 116, width: rect.width - 36, height: 20), info: .externalAPI)
                }
                drawText(t(.planCostUnavailable), rect: NSRect(x: rect.minX + 18, y: rect.minY + unavailableY, width: rect.width - 36, height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(0.42))
                return
            }
            if let externalAPI, externalAPI.hasData {
                drawText(t(.externalAPICost), rect: NSRect(x: rect.minX + 18, y: rect.minY + 20, width: rect.width - 36, height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(0.56))
                drawText(displayAPIMoney(externalAPI.usdValue), rect: NSRect(x: rect.minX + 18, y: rect.minY + 48, width: rect.width - 36, height: 34), font: .monospacedDigitSystemFont(ofSize: 26, weight: .bold), color: accentAmber)
                drawText(t(.planCostUnavailable), rect: NSRect(x: rect.minX + 18, y: rect.minY + 92, width: rect.width - 36, height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(0.42))
                return
            }
            drawText(t(.planCostUnavailable), rect: NSRect(x: rect.minX + 16, y: rect.minY + 54, width: rect.width - 32, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: NSColor.white.withAlphaComponent(0.56))
            return
        }

        let inset: CGFloat = 18
        let dividerX = rect.minX + max(282, rect.width * 0.48)
        let leftRect = NSRect(x: rect.minX + inset, y: rect.minY + 16, width: dividerX - rect.minX - inset * 2, height: rect.height - 32)
        let rightRect = NSRect(x: dividerX + 18, y: rect.minY + 16, width: rect.maxX - dividerX - 34, height: rect.height - 32)

        borderColor.setStroke()
        NSBezierPath(rect: NSRect(x: dividerX, y: rect.minY + 18, width: 1, height: rect.height - 36)).stroke()

        let usageRate = estimate.weeklyBudget > 0 ? estimate.weeklyUsedValue / estimate.weeklyBudget : 0
        let clampedRate = min(1, max(0, usageRate))
        let usedColor = usageRate > 1 ? accentAmber : costUsedColor

        drawText(t(.weeklyUsedValue), rect: NSRect(x: leftRect.minX, y: leftRect.minY, width: leftRect.width, height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(0.56))
        drawText(displayMoney(estimate.weeklyUsedValue), rect: NSRect(x: leftRect.minX, y: leftRect.minY + 26, width: leftRect.width - 92, height: 34), font: .monospacedDigitSystemFont(ofSize: 26, weight: .bold), color: usedColor)
        drawRight(String(format: "%.0f%%", usageRate * 100), rect: NSRect(x: leftRect.maxX - 86, y: leftRect.minY + 31, width: 86, height: 24), color: NSColor.white.withAlphaComponent(0.82), font: .monospacedDigitSystemFont(ofSize: 17, weight: .bold))

        let progressRect = NSRect(x: leftRect.minX, y: leftRect.minY + 74, width: leftRect.width, height: 10)
        costRemainingMutedColor.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: progressRect, xRadius: 5, yRadius: 5).fill()
        usedColor.setFill()
        let usedProgressWidth = clampedRate > 0 ? max(6, progressRect.width * CGFloat(clampedRate)) : 0
        if usedProgressWidth > 0 {
            NSBezierPath(roundedRect: NSRect(x: progressRect.minX, y: progressRect.minY, width: usedProgressWidth, height: progressRect.height), xRadius: 5, yRadius: 5).fill()
        }

        let budgetLine = "\(t(.weeklyUnusedValue)) \(displayMoney(estimate.weeklyUnusedValue))  /  \(t(.weeklyBudget)) \(displayMoney(estimate.weeklyBudget))"
        drawText(budgetLine, rect: NSRect(x: leftRect.minX, y: leftRect.minY + 96, width: leftRect.width, height: 18), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.52))

        let planLine = "\(t(.paymentMonthly)) \(paymentMoney(AppSettings.monthlyPlanCost))  ·  \(t(.displayEquivalent)) \(displayMoney(AppSettings.monthlyPlanCost))"
        drawText(planLine, rect: NSRect(x: rightRect.minX, y: rightRect.minY, width: rightRect.width, height: 18), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.54))
        let apiTitle = apiEstimate.hasUsage && apiEstimate.coveragePercent < 99.5
            ? "\(t(.apiEquivalent)) \(String(format: "%.0f%%", apiEstimate.coveragePercent))"
            : t(.apiEquivalent)
        var summaryRows: [(String, String, NSColor, CostOverviewInfo)] = [
            (t(.usageRate), String(format: "%.0f%%", usageRate * 100), usedColor, .usageRate),
            (t(.totalSpendValue), displayMoney(estimate.totalSpentValue), accentAmber, .totalSpend),
            (apiTitle, displayAPIMoney(apiEstimate.usdValue), accentTeal, .apiEquivalent)
        ]
        if let externalAPI, externalAPI.hasData {
            summaryRows.append((t(.externalAPICost), displayAPIMoney(externalAPI.usdValue), accentAmber, .externalAPI))
        }
        summaryRows.append((t(.totalWasteValue), displayMoney(estimate.totalWastedValue), accentRose.withAlphaComponent(0.92), .totalWaste))
        let rowSpacing: CGFloat = summaryRows.count > 4 ? 22 : 26
        for (index, row) in summaryRows.enumerated() {
            drawCostOverviewRow(
                title: row.0,
                value: row.1,
                color: row.2,
                rect: NSRect(x: rightRect.minX, y: rightRect.minY + 28 + CGFloat(index) * rowSpacing, width: rightRect.width, height: 20),
                info: row.3
            )
        }
    }

    private func drawCostOverviewRow(title: String, value: String, color: NSColor, rect: NSRect, info: CostOverviewInfo? = nil) {
        let titleFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let titleRect = NSRect(x: rect.minX, y: rect.minY + 2, width: max(90, rect.width * 0.34), height: 16)
        drawText(title, rect: titleRect, font: titleFont, color: NSColor.white.withAlphaComponent(0.48))
        if let info {
            let titleWidth = min(titleRect.width - 16, measuredTextWidth(title, font: titleFont))
            let iconRect = NSRect(x: titleRect.minX + titleWidth + 5, y: rect.minY + 1, width: 16, height: 16)
            costOverviewInfoRects[info] = iconRect
            drawInfoMark(rect: iconRect, highlighted: hoveredCostOverviewInfo == info)
        }
        drawRight(value, rect: NSRect(x: rect.minX + rect.width * 0.34, y: rect.minY, width: rect.width * 0.66, height: 20), color: color, font: .monospacedDigitSystemFont(ofSize: 15, weight: .bold))
    }

    private func drawToggle(rect: NSRect, isOn: Bool) {
        let trackColor = isOn ? accentTeal.withAlphaComponent(0.72) : NSColor.white.withAlphaComponent(0.13)
        trackColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        NSColor.white.withAlphaComponent(0.12).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: rect.height / 2, yRadius: rect.height / 2).stroke()

        let knobSize = rect.height - 4
        let knobX = isOn ? rect.maxX - knobSize - 2 : rect.minX + 2
        let knobRect = NSRect(x: knobX, y: rect.minY + 2, width: knobSize, height: knobSize)
        NSColor.white.withAlphaComponent(0.88).setFill()
        NSBezierPath(ovalIn: knobRect).fill()
    }

    private struct CostHistoryHeaderLayout {
        let hintRect: NSRect
        let emptyWeeksLabelRect: NSRect
        let emptyWeeksSwitchRect: NSRect
        let yearRect: NSRect
        let ringsRect: NSRect
    }

    private func costHistoryHeaderLayout(chartRect: NSRect) -> CostHistoryHeaderLayout {
        let inset: CGFloat = 16
        let rowGap: CGFloat = 12
        let labelSwitchGap: CGFloat = 6
        let switchWidth: CGFloat = 40
        let switchHeight: CGFloat = 22
        let yearWidth: CGFloat = 152
        let toggleY = chartRect.minY + 12
        let yearY = chartRect.minY + 42
        let labelFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let labelWidth = ceil(measuredTextWidth(t(.showPastEmptyWeeks), font: labelFont)) + 2

        let yearRect = NSRect(
            x: chartRect.maxX - inset - yearWidth,
            y: yearY,
            width: yearWidth,
            height: 28
        )
        let groupWidth = labelWidth + labelSwitchGap + switchWidth
        let groupX = max(chartRect.minX + inset, chartRect.maxX - inset - groupWidth)
        let labelRect = NSRect(
            x: groupX,
            y: toggleY + 4,
            width: labelWidth,
            height: 14
        )
        let switchRect = NSRect(
            x: labelRect.maxX + labelSwitchGap,
            y: toggleY,
            width: switchWidth,
            height: switchHeight
        )
        let maxHintWidth = max(0, yearRect.minX - chartRect.minX - inset - rowGap)
        let hintWidth = min(430, maxHintWidth)
        let hintRect = NSRect(
            x: chartRect.minX + inset,
            y: chartRect.minY + 36,
            width: hintWidth,
            height: 16
        )
        let ringsRect = NSRect(
            x: chartRect.minX + inset,
            y: chartRect.minY + 84,
            width: chartRect.width - inset * 2,
            height: chartRect.height - 102
        )
        return CostHistoryHeaderLayout(
            hintRect: hintRect,
            emptyWeeksLabelRect: labelRect,
            emptyWeeksSwitchRect: switchRect,
            yearRect: yearRect,
            ringsRect: ringsRect
        )
    }

    private func drawCostPage(snapshot: DetailsSnapshot, content: NSRect) {
        let limit = costEstimateLimit(from: snapshot.liveLimits)
        let costData = costPageData(for: snapshot, limit: limit, year: selectedCostYear)
        let estimate = costData.estimate

        let settingsRect = NSRect(x: content.minX, y: content.minY + 78, width: content.width, height: 244)
        let leftColumnWidth = max(240, settingsRect.width - (min(300, max(252, settingsRect.width * 0.34)) + 56))
        drawPanel(settingsRect)
        drawText(t(.planCost), rect: NSRect(x: settingsRect.minX + 16, y: settingsRect.minY + 14, width: 220, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        drawText(t(.paymentMonthly), rect: NSRect(x: settingsRect.minX + 16, y: settingsRect.minY + 52, width: leftColumnWidth, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
        drawMultilineText(t(.planCostHint), rect: NSRect(x: settingsRect.minX + 16, y: settingsRect.minY + 74, width: leftColumnWidth, height: 32), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.52))

        drawText(t(.paymentStartDate), rect: NSRect(x: settingsRect.minX + 16, y: settingsRect.minY + 122, width: leftColumnWidth, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
        drawText(t(.paymentCurrency), rect: NSRect(x: settingsRect.minX + 16, y: settingsRect.minY + 168, width: leftColumnWidth, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
        drawText(t(.displayCurrency), rect: NSRect(x: settingsRect.minX + 16, y: settingsRect.minY + 220, width: leftColumnWidth, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
        drawInputFieldBackground(costAmountField.frame)
        drawInputFieldBackground(paymentStartDayField.frame)

        let summaryY = settingsRect.maxY + 16
        let summaryHeight: CGFloat = 168
        let summaryRect = NSRect(x: content.minX, y: summaryY, width: content.width, height: summaryHeight)
        drawCostOverviewPanel(estimate: estimate, apiEstimate: costData.apiEstimate, rect: summaryRect)

        let chartY = summaryRect.maxY + 16
        let chartRect = NSRect(x: content.minX, y: chartY, width: content.width, height: 332)
        drawPanel(chartRect)
        let headerLayout = costHistoryHeaderLayout(chartRect: chartRect)
        showHistoricalEmptyWeeksToggleRect = headerLayout.emptyWeeksSwitchRect
        drawText(t(.costHistory), rect: NSRect(x: chartRect.minX + 16, y: chartRect.minY + 12, width: 220, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        drawText(t(.costHistoryHint), rect: headerLayout.hintRect, font: .systemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.44))
        drawRight(t(.showPastEmptyWeeks), rect: headerLayout.emptyWeeksLabelRect, color: NSColor.white.withAlphaComponent(0.50), font: .systemFont(ofSize: 11, weight: .semibold))
        drawToggle(rect: headerLayout.emptyWeeksSwitchRect, isOn: AppSettings.showHistoricalEmptyWeeks)

        drawCostRings(rows: costData.weeklyRows, rect: headerLayout.ringsRect, year: selectedCostYear)

        let tableY = chartRect.maxY + 16
        let tableRect = NSRect(x: content.minX, y: tableY, width: content.width, height: max(120, content.maxY - tableY))
        drawPanel(tableRect)
        drawText(t(.monthlySpendHistory), rect: NSRect(x: tableRect.minX + 16, y: tableRect.minY + 12, width: 220, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        let rows = costData.monthlyRows
        if rows.isEmpty {
            let emptyMessage = estimate == nil ? t(.planCostUnavailable) : t(.noUsage)
            drawText(emptyMessage, rect: NSRect(x: tableRect.minX + 16, y: tableRect.minY + 48, width: tableRect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
        } else {
            let visible = Array(rows.prefix(6))
            let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
            let headerFont = NSFont.systemFont(ofSize: 10, weight: .bold)
            let percentW = max(
                measuredTextWidth("%", font: headerFont),
                visible.map { measuredTextWidth(String(format: "%.0f%%", $0.usedPercentOfPlan), font: valueFont) }.max() ?? 0
            ) + 12
            let usedW = max(
                measuredTextWidth(t(.used), font: headerFont),
                visible.map { measuredTextWidth(displayMoney($0.usedValue), font: valueFont) }.max() ?? 0
            ) + 14
            let remainingW = max(
                measuredTextWidth(t(.remaining), font: headerFont),
                visible.map { measuredTextWidth(displayMoney(max(0, AppSettings.monthlyPlanCost - $0.usedValue)), font: valueFont) }.max() ?? 0
            ) + 14
            let percentX = tableRect.maxX - 18 - percentW
            let remainingX = percentX - 18 - remainingW
            let usedX = remainingX - 24 - usedW
            drawRight(t(.used), rect: NSRect(x: usedX, y: tableRect.minY + 20, width: usedW, height: 16), color: NSColor.white.withAlphaComponent(0.40), font: headerFont)
            drawRight(t(.remaining), rect: NSRect(x: remainingX, y: tableRect.minY + 20, width: remainingW, height: 16), color: NSColor.white.withAlphaComponent(0.40), font: headerFont)
            drawRight("%", rect: NSRect(x: percentX, y: tableRect.minY + 20, width: percentW, height: 16), color: NSColor.white.withAlphaComponent(0.40), font: headerFont)
            for (index, row) in visible.enumerated() {
                let rowY = tableRect.minY + 44 + CGFloat(index) * 18
                drawText(row.month, rect: NSRect(x: tableRect.minX + 16, y: rowY, width: max(90, usedX - tableRect.minX - 32), height: 16), font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold), color: .white)
                drawRight(displayMoney(row.usedValue), rect: NSRect(x: usedX, y: rowY, width: usedW, height: 16), color: .white, font: valueFont)
                drawRight(displayMoney(max(0, AppSettings.monthlyPlanCost - row.usedValue)), rect: NSRect(x: remainingX, y: rowY, width: remainingW, height: 16), color: NSColor.white.withAlphaComponent(0.60), font: valueFont)
                drawRight(String(format: "%.0f%%", row.usedPercentOfPlan), rect: NSRect(x: percentX, y: rowY, width: percentW, height: 16), color: NSColor.white.withAlphaComponent(0.52), font: valueFont)
            }
        }
    }

    private func drawProfileSelectedDayPanel(snapshot: DetailsSnapshot, report: TokenReport, rect: NSRect) {
        drawPanel(rect)
        let day = selectedDay.flatMap { selected in report.byDay.first { $0.day == selected } }
            ?? report.byDay.last(where: { $0.usage.total > 0 })
            ?? report.byDay.last
        guard let day else {
            drawText(t(.noDaySelected), rect: NSRect(x: rect.minX + 18, y: rect.minY + 18, width: 220, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
            return
        }

        let localDay = snapshot.all.byDay.first { $0.day == day.day }
        let rawProfileDay = rawProfileCalendarReport(for: snapshot)?.byDay.first { $0.day == day.day }
        let rawProfileTotal = rawProfileDay?.usage.total ?? 0
        let localTotal = localDay?.usage.total ?? 0
        let isLocalFallback = rawProfileTotal == 0 && localTotal > 0 && day.usage.total == localTotal
        let maxTotal = max(report.byDay.map { $0.usage.total }.max() ?? 1, 1)
        let intensity = Double(day.usage.total) / Double(maxTotal)
        drawText(day.day, rect: NSRect(x: rect.minX + 18, y: rect.minY + 18, width: 180, height: 24), font: .monospacedDigitSystemFont(ofSize: 17, weight: .bold), color: .white)
        drawText(compact(day.usage.total), rect: NSRect(x: rect.minX + 18, y: rect.minY + 48, width: 260, height: 34), font: .monospacedDigitSystemFont(ofSize: 28, weight: .bold), color: isLocalFallback ? NSColor.systemGreen : accentTeal)
        let sourceTitle = isLocalFallback ? "\(t(.profileAPISource)) + \(t(.logs))" : t(.profileAPISource)
        let dayMeta = "\(sourceTitle)  |  \(Int(round(intensity * 100)))% \(t(.peakDay))"
        let metaFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let metaRect = NSRect(x: rect.minX + 18, y: rect.minY + 90, width: 420, height: 18)
        drawText(dayMeta, rect: metaRect, font: metaFont, color: NSColor.white.withAlphaComponent(0.48))
        let metaWidth = min(metaRect.width - 22, measuredTextWidth(dayMeta, font: metaFont))
        let iconRect = NSRect(x: metaRect.minX + metaWidth + 6, y: metaRect.minY - 1, width: 16, height: 16)
        profileAPIInfoRect = iconRect
        drawInfoMark(rect: iconRect, highlighted: isHoveringProfileAPIInfo)

        typealias ProfileDayMetric = (title: String, value: String, color: NSColor, footer: String?)
        var metrics: [ProfileDayMetric] = [
            (t(.profileAPISource), rawProfileDay.map { compact($0.usage.total) } ?? "--", accentTeal, nil),
            (t(.logs), localDay.map { compact($0.usage.total) } ?? "--", NSColor.systemGreen, nil),
            (t(.peakDay), snapshot.accountUsage?.summary.peakDailyTokens.map { compact($0) } ?? "--", NSColor.systemCyan, nil)
        ]
        let apiEstimate = profileAPIDayEstimate(profileDay: day, localDay: localDay)
        if apiEstimate.hasPricedUsage {
            let footer = apiEstimate.coveragePercent < 99.5 ? "\(String(format: "%.0f%%", apiEstimate.coveragePercent)) \(t(.priced))" : nil
            metrics.append((t(.apiEquivalent), compactDisplayAPIMoney(apiEstimate.usdValue), accentTeal, footer))
        }

        let startX = rect.minX + min(420, max(292, rect.width * 0.50))
        let gap: CGFloat = 12
        let availableMetricWidth = max(0, rect.maxX - startX - 18)
        let columns = metrics.count > 3 && availableMetricWidth >= 500 ? 4 : min(3, metrics.count)
        let metricW = (availableMetricWidth - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let metricH: CGFloat = 74
        for (index, metric) in metrics.enumerated() {
            let col = index % columns
            let row = index / columns
            let card = NSRect(x: startX + CGFloat(col) * (metricW + gap), y: rect.minY + 42 + CGFloat(row) * (metricH + gap), width: metricW, height: metricH)
            NSColor.black.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: card, xRadius: 7, yRadius: 7).fill()
            let labelH: CGFloat = 16
            let valueH: CGFloat = 22
            let footerH: CGFloat = metric.footer == nil ? 0 : 14
            let blockH = labelH + 3 + valueH + (metric.footer == nil ? 0 : 2 + footerH)
            let blockY = card.midY - blockH / 2
            drawText(metric.title, rect: NSRect(x: card.minX + 12, y: blockY, width: card.width - 24, height: labelH), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.46))
            drawText(metric.value, rect: NSRect(x: card.minX + 12, y: blockY + labelH + 3, width: card.width - 24, height: valueH), font: .monospacedDigitSystemFont(ofSize: metricW < 96 ? 13 : 15, weight: .bold), color: metric.color)
            if let footer = metric.footer {
                drawText(footer, rect: NSRect(x: card.minX + 12, y: blockY + labelH + 3 + valueH + 2, width: card.width - 24, height: footerH), font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.54))
            }
        }

        let metricRows = Int(ceil(Double(metrics.count) / Double(max(columns, 1))))
        let metricsBottom = rect.minY + 42 + CGFloat(metricRows) * metricH + CGFloat(max(0, metricRows - 1)) * gap
        let modelY = max(rect.minY + 134, metricsBottom + 18)
        let modelRect = NSRect(
            x: rect.minX + 18,
            y: modelY,
            width: rect.width - 36,
            height: max(88, rect.maxY - modelY - 18)
        )
        drawSelectedDayModels(localDay?.modelBreakdown ?? [], rect: modelRect)
    }

    private func profileAPIDayEstimate(profileDay: DayUsage, localDay: DayUsage?) -> APICostEstimate {
        guard let localDay else {
            return APICostEstimator.estimate(day: profileDay)
        }
        let modelBreakdown = localDay.modelBreakdown.isEmpty ? profileDay.modelBreakdown : localDay.modelBreakdown
        let usage = profileDay.usage.total > 0 ? profileDay.usage : localDay.usage
        let mergedDay = DayUsage(day: profileDay.day, usage: usage, turns: profileDay.turns, modelBreakdown: modelBreakdown)
        return APICostEstimator.estimate(day: mergedDay)
    }

    private func drawSelectedDayPanel(snapshot: DetailsSnapshot, rect: NSRect) {
        drawPanel(rect)
        let report = snapshot.all
        let day = selectedDay.flatMap { selected in report.byDay.first { $0.day == selected } }
            ?? report.byDay.last(where: { $0.usage.total > 0 })
            ?? report.byDay.last
        guard let day else {
            drawText(t(.noDaySelected), rect: NSRect(x: rect.minX + 18, y: rect.minY + 18, width: 220, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
            return
        }

        let maxTotal = max(report.byDay.map { $0.usage.total }.max() ?? 1, 1)
        let intensity = Double(day.usage.total) / Double(maxTotal)
        drawText(day.day, rect: NSRect(x: rect.minX + 18, y: rect.minY + 18, width: 180, height: 24), font: .monospacedDigitSystemFont(ofSize: 17, weight: .bold), color: .white)
        drawText(compact(day.usage.total), rect: NSRect(x: rect.minX + 18, y: rect.minY + 48, width: 260, height: 34), font: .monospacedDigitSystemFont(ofSize: 28, weight: .bold), color: .systemGreen)
        let limit = costEstimateLimit(from: snapshot.liveLimits)
        let cost = planCostEstimate(report: report, selectedDay: day, limit: limit, quotaReferenceReport: snapshot.costReferenceReport)
        var dayMeta = "\(day.turns) \(t(.turns).lowercased())  |  \(Int(round(intensity * 100)))% \(t(.peakDay))"
        if let cost {
            dayMeta += "  |  \(String(format: "%.1f%%", cost.selectedDayQuotaPercent)) \(t(.weeklyQuotaShare))"
        }
        drawText(dayMeta, rect: NSRect(x: rect.minX + 18, y: rect.minY + 90, width: 420, height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(0.48))

        typealias DayMetric = (title: String, value: String, color: NSColor, infoAnchor: Bool, footer: String?)
        var metrics: [DayMetric] = [
            (t(.input), compact(day.usage.input), NSColor.systemGreen, false, nil),
            (t(.output), compact(day.usage.output), NSColor.systemCyan, false, nil),
            (t(.cached), compact(day.usage.cachedInput), NSColor.systemTeal, false, nil),
            (t(.fresh), compact(day.usage.freshInput), NSColor.systemOrange, false, nil)
        ]
        if let cost {
            metrics.append(("\(t(.dayValue)) ?", displayMoney(cost.selectedDayValue), NSColor.systemGreen, true, nil))
        }
        let apiEstimate = APICostEstimator.estimate(day: day)
        if apiEstimate.hasPricedUsage {
            let footer = apiEstimate.coveragePercent < 99.5 ? "\(String(format: "%.0f%%", apiEstimate.coveragePercent)) \(t(.priced))" : nil
            metrics.append((t(.apiEquivalent), compactDisplayAPIMoney(apiEstimate.usdValue), accentTeal, false, footer))
        }
        let startX = rect.minX + 310
        let gap: CGFloat = 12
        let availableMetricWidth = max(180, rect.maxX - startX - 18)
        let columns: Int
        if metrics.count > 4 {
            columns = availableMetricWidth >= 360 ? 3 : 2
        } else {
            columns = availableMetricWidth >= 460 ? 4 : 2
        }
        let metricW = (availableMetricWidth - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let metricH: CGFloat
        switch columns {
        case 4:
            metricH = 72
        case 3:
            metricH = 62
        default:
            metricH = 56
        }
        for (index, metric) in metrics.enumerated() {
            let col = index % columns
            let row = index / columns
            let card = NSRect(x: startX + CGFloat(col) * (metricW + gap), y: rect.minY + 24 + CGFloat(row) * (metricH + 10), width: metricW, height: metricH)
            if metric.infoAnchor {
                dayValueInfoRect = card
            }
            NSColor.black.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: card, xRadius: 7, yRadius: 7).fill()
            let hasFooter = metric.footer != nil
            let labelH: CGFloat = 16
            let valueH: CGFloat = columns >= 3 ? 20 : 18
            let footerH: CGFloat = hasFooter ? 14 : 0
            let innerGap: CGFloat = columns >= 3 ? 3 : 1
            let footerGap: CGFloat = hasFooter ? 2 : 0
            let blockH = labelH + innerGap + valueH + footerGap + footerH
            let blockY = card.midY - blockH / 2
            drawText(metric.title, rect: NSRect(x: card.minX + 12, y: blockY, width: card.width - 24, height: labelH), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.46))
            drawText(metric.value, rect: NSRect(x: card.minX + 12, y: blockY + labelH + innerGap, width: card.width - 24, height: valueH), font: .monospacedDigitSystemFont(ofSize: columns >= 3 ? 15 : 13, weight: .bold), color: metric.color)
            if let footer = metric.footer {
                drawText(footer, rect: NSRect(x: card.minX + 12, y: blockY + labelH + innerGap + valueH + footerGap, width: card.width - 24, height: footerH), font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.54))
            }
        }

        let metricRows = Int(ceil(Double(metrics.count) / Double(columns)))
        let metricsBottom = rect.minY + 24 + CGFloat(metricRows) * metricH + CGFloat(max(0, metricRows - 1)) * 10
        let visibleModelRows = max(1, min(day.modelBreakdown.count, 5))
        let minimumModelHeight = 22 + CGFloat(visibleModelRows) * 22
        let modelY = max(rect.minY + 112, metricsBottom + 12)
        let modelRect = NSRect(
            x: rect.minX + 18,
            y: modelY,
            width: rect.width - 36,
            height: max(minimumModelHeight, rect.maxY - modelY - 18)
        )
        drawSelectedDayModels(day.modelBreakdown, rect: modelRect)
    }

    private func drawSelectedDayModels(_ models: [ModelUsage], rect: NSRect) {
        drawText(t(.models), rect: NSRect(x: rect.minX, y: rect.minY, width: 120, height: 18), font: .systemFont(ofSize: 13, weight: .bold), color: .white)
        guard !models.isEmpty else {
            drawText(t(.noModelLabelForDay), rect: NSRect(x: rect.minX, y: rect.minY + 24, width: rect.width, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.46))
            return
        }

        let visible = Array(models.prefix(5))
        let maxTotal = max(visible.map { $0.usage.total }.max() ?? 1, 1)
        let totalX = rect.maxX - 82
        let outputX = totalX - 90
        let inputX = outputX - 96
        let nameW = min(220, rect.width * 0.30)
        let barX = rect.minX + nameW + 18
        let barW = max(80, inputX - barX - 16)
        drawRight(t(.input), rect: NSRect(x: inputX, y: rect.minY, width: 80, height: 18), color: NSColor.white.withAlphaComponent(0.42), font: .systemFont(ofSize: 10, weight: .bold))
        drawRight(t(.output), rect: NSRect(x: outputX, y: rect.minY, width: 80, height: 18), color: NSColor.white.withAlphaComponent(0.42), font: .systemFont(ofSize: 10, weight: .bold))
        drawRight(t(.total), rect: NSRect(x: totalX, y: rect.minY, width: 82, height: 18), color: NSColor.white.withAlphaComponent(0.42), font: .systemFont(ofSize: 10, weight: .bold))
        for (index, model) in visible.enumerated() {
            let y = rect.minY + 22 + CGFloat(index) * 22
            guard y + 18 <= rect.maxY else { break }
            drawText(model.name, rect: NSRect(x: rect.minX, y: y, width: nameW, height: 12), font: .systemFont(ofSize: 10, weight: .semibold), color: .white)
            drawText("\(model.events) \(t(.events).lowercased())", rect: NSRect(x: rect.minX, y: y + 11, width: nameW, height: 11), font: .systemFont(ofSize: 8, weight: .semibold), color: NSColor.white.withAlphaComponent(0.42))
            drawRight(compact(model.usage.input), rect: NSRect(x: inputX, y: y + 1, width: 80, height: 16), color: .systemGreen)
            drawRight(compact(model.usage.output), rect: NSRect(x: outputX, y: y + 1, width: 80, height: 16), color: .systemCyan)
            drawRight(compact(model.usage.total), rect: NSRect(x: totalX, y: y + 1, width: 82, height: 16), color: .white)

            let bar = NSRect(x: barX, y: y + 6, width: barW, height: 6)
            NSColor.white.withAlphaComponent(0.07).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 4, yRadius: 4).fill()
            let totalRatio = CGFloat(Double(model.usage.total) / Double(maxTotal))
            let filledWidth = max(4, bar.width * totalRatio)
            let inputOutput = max(model.usage.input + model.usage.output, 1)
            let inputWidth = filledWidth * CGFloat(model.usage.input) / CGFloat(inputOutput)
            NSColor.systemGreen.withAlphaComponent(0.92).setFill()
            NSBezierPath(roundedRect: NSRect(x: bar.minX, y: bar.minY, width: inputWidth, height: bar.height), xRadius: 4, yRadius: 4).fill()
            NSColor.systemCyan.withAlphaComponent(0.92).setFill()
            NSBezierPath(roundedRect: NSRect(x: bar.minX + inputWidth, y: bar.minY, width: max(0, filledWidth - inputWidth), height: bar.height), xRadius: 4, yRadius: 4).fill()
        }
    }

    private func drawSettingsPage(content: NSRect) {
        let rect = NSRect(x: content.minX, y: content.minY + 78, width: content.width, height: min(612, content.height - 78))
        drawPanel(rect)
        drawText(t(.language), rect: NSRect(x: rect.minX + 16, y: rect.minY + 16, width: rect.width - 32, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        drawText(t(.interfaceLanguage), rect: NSRect(x: rect.minX + 16, y: rect.minY + 56, width: 220, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
        drawInputFieldBackground(languagePopup.frame)

        drawText(t(.languageHint), rect: NSRect(x: rect.minX + 16, y: rect.minY + 104, width: rect.width - 32, height: 20), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.52))

        drawText(t(.numberUnits), rect: NSRect(x: rect.minX + 16, y: rect.minY + 138, width: 220, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
        let unitOptionW: CGFloat = 132
        let optionH: CGFloat = 38
        let gap: CGFloat = 12
        let unitY = rect.minY + 130
        let availableUnitStyles = NumberUnitStyle.availableCases
        let unitStartX = rect.maxX - 16 - unitOptionW * CGFloat(availableUnitStyles.count) - gap * CGFloat(max(availableUnitStyles.count - 1, 0))
        for (index, style) in availableUnitStyles.enumerated() {
            let optionRect = NSRect(x: unitStartX + CGFloat(index) * (unitOptionW + gap), y: unitY, width: unitOptionW, height: optionH)
            numberUnitOptionRects[style] = optionRect
            drawSelectablePill(style.title, rect: optionRect, selected: style == NumberUnitStyle.effective)
        }
        drawText(t(.numberUnitsHint), rect: NSRect(x: rect.minX + 16, y: rect.minY + 186, width: rect.width - 32, height: 20), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.52))

        drawText(t(.logFolder), rect: NSRect(x: rect.minX + 16, y: rect.minY + 218, width: 220, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
        let pathRect = NSRect(x: rect.minX + 16, y: rect.minY + 246, width: rect.width - 300, height: 34)
        NSColor.black.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: pathRect, xRadius: 7, yRadius: 7).fill()
        drawText(AppSettings.logFolderDisplayPath, rect: pathRect.insetBy(dx: 12, dy: 9), font: .monospacedSystemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.62))

        let logButtonY = rect.minY + 246
        openLogFolderRect = NSRect(x: rect.maxX - 284, y: logButtonY, width: 76, height: 34)
        resetLogFolderRect = NSRect(x: rect.maxX - 196, y: logButtonY, width: 72, height: 34)
        chooseLogFolderRect = NSRect(x: rect.maxX - 112, y: logButtonY, width: 96, height: 34)
        drawSmallButton(t(.logs), rect: openLogFolderRect!, emphasized: false)
        drawSmallButton(t(.logFolderDefault), rect: resetLogFolderRect!, emphasized: false)
        drawSmallButton(t(.logFolderChoose), rect: chooseLogFolderRect!, emphasized: true)
        drawText(t(.logFolderHint), rect: NSRect(x: rect.minX + 16, y: rect.minY + 286, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.52))

        drawText(t(.statusBarDisplay), rect: NSRect(x: rect.minX + 16, y: rect.minY + 334, width: 220, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
        let statusY = rect.minY + 330
        let statusGap: CGFloat = 10
        let statusOptionW = max(100, (rect.width - 260 - statusGap * CGFloat(StatusDisplayOption.allCases.count - 1)) / CGFloat(StatusDisplayOption.allCases.count))
        let statusStartX = rect.maxX - 16 - statusOptionW * CGFloat(StatusDisplayOption.allCases.count) - statusGap * CGFloat(StatusDisplayOption.allCases.count - 1)
        for (index, option) in StatusDisplayOption.allCases.enumerated() {
            let optionRect = NSRect(x: statusStartX + CGFloat(index) * (statusOptionW + statusGap), y: statusY, width: statusOptionW, height: 36)
            statusOptionRects[option] = optionRect
            drawSelectablePill(option.title, rect: optionRect, selected: option == StatusDisplayOption.current)
        }
        drawText(t(.statusDisplayHint), rect: NSRect(x: rect.minX + 16, y: rect.minY + 378, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.52))

        drawText(t(.quotaDisplayStyle), rect: NSRect(x: rect.minX + 16, y: rect.minY + 410, width: 220, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
        let quotaStyleY = rect.minY + 406
        let quotaStyleGap: CGFloat = 10
        let quotaStyleW: CGFloat = 116
        let quotaStyleStartX = rect.maxX - 16 - quotaStyleW * CGFloat(QuotaDisplayStyle.allCases.count) - quotaStyleGap * CGFloat(QuotaDisplayStyle.allCases.count - 1)
        for (index, style) in QuotaDisplayStyle.allCases.enumerated() {
            let optionRect = NSRect(x: quotaStyleStartX + CGFloat(index) * (quotaStyleW + quotaStyleGap), y: quotaStyleY, width: quotaStyleW, height: 36)
            quotaDisplayStyleRects[style] = optionRect
            drawSelectablePill(style.title, rect: optionRect, selected: style == QuotaDisplayStyle.current)
        }
        drawText(t(.quotaDisplayHint), rect: NSRect(x: rect.minX + 16, y: rect.minY + 452, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.52))

        let leftSwitchLabelW = max(120, showCodexStatusSwitch.frame.minX - rect.minX - 24)
        let rightSwitchLabelX = rect.midX + 18
        let rightSwitchLabelW = max(120, launchAtLoginSwitch.frame.minX - rightSwitchLabelX - 8)
        drawText(t(.showCodexStatus), rect: NSRect(x: rect.minX + 16, y: rect.minY + 476, width: leftSwitchLabelW, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
        drawText(t(.launchAtLogin), rect: NSRect(x: rightSwitchLabelX, y: rect.minY + 476, width: rightSwitchLabelW, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
        drawText(t(.quotaWarnings), rect: NSRect(x: rect.minX + 16, y: rect.minY + 504, width: leftSwitchLabelW, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
        drawText(t(.profileAPITotals), rect: NSRect(x: rightSwitchLabelX, y: rect.minY + 504, width: rightSwitchLabelW, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
    }

    private var costUsedColor: NSColor {
        accentTeal
    }

    private var costRemainingColor: NSColor {
        NSColor(calibratedRed: 0.52, green: 0.58, blue: 0.69, alpha: 1.0)
    }

    private var costRemainingMutedColor: NSColor {
        NSColor(calibratedRed: 0.168, green: 0.196, blue: 0.244, alpha: 1.0)
    }

    private func costUsedColor(for row: CostPeriodRow) -> NSColor {
        guard row.isShortCycle else { return costUsedColor }
        return accentAmber
    }

    private func costRemainingColor(for row: CostPeriodRow) -> NSColor {
        guard row.isShortCycle else { return costRemainingColor }
        return costRemainingColor.withAlphaComponent(0.78)
    }

    private func costRemainingMutedColor(for row: CostPeriodRow) -> NSColor {
        guard row.isShortCycle else { return costRemainingMutedColor }
        return costRemainingMutedColor.withAlphaComponent(0.95)
    }

    private func drawCurrencyOptions(rect: NSRect, y: CGFloat, selected: CurrencyCode, store: inout [CurrencyCode: NSRect]) {
        let optionW: CGFloat = 70
        let optionH: CGFloat = 32
        let gap: CGFloat = 8
        let startX = rect.maxX - 16 - optionW * CGFloat(CurrencyCode.allCases.count) - gap * CGFloat(CurrencyCode.allCases.count - 1)
        for (index, currency) in CurrencyCode.allCases.enumerated() {
            let optionRect = NSRect(x: startX + CGFloat(index) * (optionW + gap), y: y, width: optionW, height: optionH)
            store[currency] = optionRect
            drawSelectablePill(currency.rawValue, rect: optionRect, selected: currency == selected)
        }
    }

    private func drawCostHistoryBars(rows: [CostPeriodRow], rect: NSRect) {
        costHistoryRows = rows
        guard !rows.isEmpty else {
            drawText(t(.planCostUnavailable), rect: NSRect(x: rect.minX, y: rect.minY + 48, width: rect.width, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }
        let legendY = rect.minY
        drawText(t(.used), rect: NSRect(x: rect.minX, y: legendY, width: 48, height: 16), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.78))
        costUsedColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: rect.minX + 54, y: legendY + 4, width: 18, height: 8), xRadius: 4, yRadius: 4).fill()
        drawText(t(.remaining), rect: NSRect(x: rect.minX + 88, y: legendY, width: 58, height: 16), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.62))
        costRemainingColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: rect.minX + 154, y: legendY + 4, width: 18, height: 8), xRadius: 4, yRadius: 4).fill()

        let chart = NSRect(x: rect.minX, y: rect.minY + 24, width: rect.width, height: rect.height - 44)
        let maxValue = max(rows.map { max($0.usedValue + $0.remainingValue, $0.budgetValue) }.max() ?? 1, 1)
        let barWidth = max(34, min(58, (chart.width - CGFloat(rows.count - 1) * 12) / CGFloat(max(rows.count, 1))))
        let gap = max(12, (chart.width - barWidth * CGFloat(rows.count)) / CGFloat(max(rows.count - 1, 1)))
        for (index, row) in rows.enumerated() {
            let x = chart.minX + CGFloat(index) * (barWidth + gap)
            let totalHeight = chart.height - 28
            let usedHeight = totalHeight * CGFloat(row.usedValue / maxValue)
            let remainingHeight = totalHeight * CGFloat(row.remainingValue / maxValue)
            let baseY = chart.maxY - 10
            let fullBarRect = NSRect(x: x, y: baseY - usedHeight - remainingHeight, width: barWidth, height: max(6, usedHeight + remainingHeight))
            costHistoryBarRects[index] = fullBarRect.insetBy(dx: -4, dy: -4)

            costRemainingMutedColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: baseY - totalHeight, width: barWidth, height: totalHeight), xRadius: 6, yRadius: 6).fill()
            if remainingHeight > 0 {
                costRemainingColor.setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: baseY - usedHeight - remainingHeight, width: barWidth, height: remainingHeight), xRadius: 5, yRadius: 5).fill()
            }
            costUsedColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: baseY - usedHeight, width: barWidth, height: max(6, usedHeight)), xRadius: 5, yRadius: 5).fill()

            if hoveredCostHistoryIndex == index {
                NSColor.white.withAlphaComponent(0.22).setStroke()
                let focusRect = fullBarRect.insetBy(dx: -3, dy: -3)
                let focusPath = NSBezierPath(roundedRect: focusRect, xRadius: 8, yRadius: 8)
                focusPath.lineWidth = 1.5
                focusPath.stroke()
            }

            drawCentered(row.label, rect: NSRect(x: x - 8, y: chart.maxY + 2, width: barWidth + 16, height: 14), font: .systemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.46))
        }
    }

    private func drawCostRings(rows: [CostPeriodRow], rect: NSRect, year: Int) {
        costHistoryRows = rows
        guard !rows.isEmpty else {
            drawText(t(.noUsage), rect: NSRect(x: rect.minX, y: rect.minY + 32, width: rect.width, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }

        let cacheKey = costRingCacheKey(rows: rows, rect: rect, year: year)
        if costRingCache?.key != cacheKey {
            costRingCache = CostRingCache(key: cacheKey, image: renderCostRingsImage(rows: rows, rect: rect, year: year))
        }
        costRingCache?.image.draw(in: rect)

        let layout = costRingLayout(rows: rows, rect: rect)
        costHistoryBarRects.removeAll(keepingCapacity: true)
        for (index, cell) in layout.cells.enumerated() {
            costHistoryBarRects[index] = cell.insetBy(dx: -4, dy: -4)
        }

        if let hoveredCostHistoryIndex,
           layout.cells.indices.contains(hoveredCostHistoryIndex) {
            drawCostRing(row: rows[hoveredCostHistoryIndex], rect: layout.cells[hoveredCostHistoryIndex], showLabel: false, highlighted: true)
        }
    }

    private func costRingLayout(rows: [CostPeriodRow], rect: NSRect) -> (cells: [NSRect], legendRect: NSRect, footerRect: NSRect, titleRect: NSRect) {
        let columns = min(13, max(rows.count, 1))
        let rowCount = Int(ceil(Double(rows.count) / Double(columns)))
        let ringGapX: CGFloat = 12
        let ringGapY: CGFloat = 18
        let availableWidth = rect.width
        let availableHeight = rect.height - 36
        let ringSize = floor(min(
            (availableWidth - CGFloat(columns - 1) * ringGapX) / CGFloat(columns),
            (availableHeight - CGFloat(max(rowCount - 1, 0)) * ringGapY) / CGFloat(max(rowCount, 1))
        ))
        let totalGridWidth = CGFloat(columns) * ringSize + CGFloat(columns - 1) * ringGapX
        let startX = rect.minX + max(0, (rect.width - totalGridWidth) / 2)
        let totalGridHeight = CGFloat(rowCount) * ringSize + CGFloat(max(rowCount - 1, 0)) * ringGapY
        let startY = rect.minY + max(20, (rect.height - totalGridHeight) / 2)

        var cells: [NSRect] = []
        cells.reserveCapacity(rows.count)
        for index in rows.indices {
            let gridRow = index / columns
            let gridColumn = index % columns
            let cell = NSRect(
                x: startX + CGFloat(gridColumn) * (ringSize + ringGapX),
                y: startY + CGFloat(gridRow) * (ringSize + ringGapY),
                width: ringSize,
                height: ringSize
            )
            cells.append(cell)
        }

        return (
            cells: cells,
            legendRect: NSRect(x: rect.minX + 96, y: rect.minY, width: 260, height: 16),
            footerRect: NSRect(x: rect.minX, y: rect.maxY - 18, width: rect.width, height: 14),
            titleRect: NSRect(x: rect.minX, y: rect.minY, width: 86, height: 16)
        )
    }

    private func renderCostRingsImage(rows: [CostPeriodRow], rect: NSRect, year: Int) -> NSImage {
        let image = NSImage(size: rect.size)
        image.lockFocusFlipped(true)
        defer { image.unlockFocus() }

        let localRect = NSRect(origin: .zero, size: rect.size)
        let translatedRows = rows
        let layout = costRingLayout(rows: translatedRows, rect: localRect)
        drawText(String(year), rect: layout.titleRect, font: .monospacedDigitSystemFont(ofSize: 11, weight: .bold), color: NSColor.white.withAlphaComponent(0.52))
        drawCostRingLegend(rect: layout.legendRect)
        for (index, cell) in layout.cells.enumerated() {
            drawCostRing(row: translatedRows[index], rect: cell, showLabel: false, highlighted: false)
        }
        drawRight(t(.costHistoryHint), rect: layout.footerRect, color: NSColor.white.withAlphaComponent(0.34), font: .systemFont(ofSize: 10, weight: .medium))
        return image
    }

    private func costRingCacheKey(rows: [CostPeriodRow], rect: NSRect, year: Int) -> String {
        let sizePart = "\(AppLanguage.current.rawValue):\(Int(rect.width.rounded()))x\(Int(rect.height.rounded())):\(year)"
        let rowsPart = rows.map {
            [
                $0.label,
                $0.title,
                $0.subtitle ?? "",
                String(format: "%.4f", $0.usedValue),
                String(format: "%.4f", $0.remainingValue),
                String(format: "%.4f", $0.budgetValue),
                String(format: "%.4f", $0.apiEquivalentUSD ?? -1),
                String(format: "%.2f", $0.apiEquivalentCoveragePercent),
                $0.hasData ? "1" : "0",
                $0.isFuture ? "1" : "0",
                $0.isShortCycle ? "1" : "0",
                "\($0.cycleIndex)"
            ].joined(separator: "|")
        }.joined(separator: ";")
        return sizePart + "#" + rowsPart
    }

    private func drawCostRingLegend(rect: NSRect) {
        let items: [(String, NSColor)] = [
            (t(.used), costUsedColor),
            (t(.remaining), costRemainingColor),
            (t(.noUsage), NSColor.white.withAlphaComponent(0.20)),
            (t(.future), NSColor.white.withAlphaComponent(0.10))
        ]
        var x = rect.minX
        for item in items {
            item.1.setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: rect.minY + 4, width: 8, height: 8)).fill()
            drawText(item.0, rect: NSRect(x: x + 12, y: rect.minY, width: 56, height: rect.height), font: .systemFont(ofSize: 10, weight: .medium), color: NSColor.white.withAlphaComponent(0.44))
            x += 70
        }
    }

    private func drawCostRing(row: CostPeriodRow, rect: NSRect, showLabel: Bool, highlighted: Bool) {
        let labelHeight: CGFloat = showLabel ? 14 : 0
        let inset: CGFloat = 4
        let ringRect = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - labelHeight)
        let circleRect = rect.insetBy(dx: inset, dy: inset)
            .offsetBy(dx: 0, dy: -labelHeight / 2)
        let center = CGPoint(x: circleRect.midX, y: circleRect.midY)
        let radius = min(circleRect.width, circleRect.height) / 2 - 3
        let lineWidth: CGFloat = max(5, min(8, rect.width * 0.14))
        let start = -CGFloat.pi / 2
        let end = start + CGFloat.pi * 2
        let fullCircleRect = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let baseColor = row.isFuture ? NSColor.white.withAlphaComponent(0.055) : costRemainingMutedColor(for: row).withAlphaComponent(row.hasData ? 0.62 : 0.50)

        fillDonut(in: fullCircleRect, thickness: lineWidth, color: baseColor)

        if row.hasData {
            let progress = min(1.0, max(0.0, row.usedPercent / 100))
            let usedEnd = start + CGFloat.pi * 2 * CGFloat(progress)
            if progress < 0.999 {
                fillDonutSegment(
                    center: center,
                    outerRadius: radius,
                    thickness: lineWidth,
                    startAngle: usedEnd,
                    endAngle: end,
                    color: costRemainingColor(for: row).withAlphaComponent(0.58)
                )
            }
            let ringColor: NSColor = row.usedPercent > 100 ? accentAmber : costUsedColor(for: row)
            if progress >= 0.999 {
                fillDonut(in: fullCircleRect, thickness: lineWidth, color: ringColor)
            } else if progress > 0.001 {
                fillDonutSegment(
                    center: center,
                    outerRadius: radius,
                    thickness: lineWidth,
                    startAngle: start,
                    endAngle: usedEnd,
                    color: ringColor
                )
            }
        } else if row.isFuture {
            fillDonut(in: fullCircleRect, thickness: lineWidth, color: NSColor.white.withAlphaComponent(0.075))
        } else {
            fillDonut(in: fullCircleRect, thickness: max(3, lineWidth * 0.72), color: NSColor.white.withAlphaComponent(0.18))
        }

        let ringColor: NSColor = row.usedPercent > 100 ? accentAmber : costUsedColor(for: row)

        if highlighted {
            NSColor.white.withAlphaComponent(0.18).setFill()
            NSBezierPath(ovalIn: ringRect.insetBy(dx: 0.5, dy: 0.5)).fill()
            ringColor.setStroke()
            let focus = NSBezierPath(ovalIn: ringRect.insetBy(dx: 1.5, dy: 1.5))
            focus.lineWidth = 1.5
            focus.stroke()
        }

        if showLabel {
            drawCentered(row.label, rect: NSRect(x: rect.minX - 4, y: rect.maxY - 12, width: rect.width + 8, height: 12), font: .monospacedDigitSystemFont(ofSize: 9, weight: .semibold), color: NSColor.white.withAlphaComponent(row.isFuture ? 0.22 : 0.46))
        }
    }

    private func drawCostHistoryTooltip() {
        guard let hoveredCostHistoryIndex,
              costHistoryRows.indices.contains(hoveredCostHistoryIndex),
              let anchorRect = costHistoryBarRects[hoveredCostHistoryIndex] else {
            return
        }
        let row = costHistoryRows[hoveredCostHistoryIndex]
        var lines: [(String, String, NSColor)] = [
            (t(.used), displayMoney(row.usedValue), costUsedColor(for: row)),
            (t(.remaining), displayMoney(row.remainingValue), costRemainingColor(for: row)),
            (t(.budget), displayMoney(row.budgetValue), .white),
            (t(.usageRate), String(format: "%.1f%%", row.usedPercent), NSColor.white.withAlphaComponent(0.82))
        ]
        if let apiEquivalentUSD = row.apiEquivalentUSD {
            let apiTitle = row.apiEquivalentCoveragePercent > 0 && row.apiEquivalentCoveragePercent < 99.5
                ? "\(t(.apiEquivalent)) \(String(format: "%.0f%%", row.apiEquivalentCoveragePercent))"
                : t(.apiEquivalent)
            lines.insert((apiTitle, displayAPIMoney(apiEquivalentUSD), accentTeal), at: 3)
        }

        let width: CGFloat = 326
        let titleHeight: CGFloat = row.subtitle == nil ? 24 : 38
        let rowHeight: CGFloat = 20
        let height: CGFloat = titleHeight + 18 + CGFloat(lines.count) * rowHeight
        var origin = CGPoint(x: anchorRect.midX - width / 2, y: anchorRect.minY - height - 12)
        var rect = NSRect(origin: origin, size: CGSize(width: width, height: height))
        if visibleCostControlFrames.contains(where: { $0.intersects(rect) }) {
            origin.y = anchorRect.maxY + 12
            rect.origin = origin
        }
        if origin.y < bounds.minY + 12 {
            origin.y = anchorRect.maxY + 12
        }
        origin.x = max(bounds.minX + 12, min(origin.x, bounds.maxX - width - 12))
        origin.y = max(bounds.minY + 12, min(origin.y, bounds.maxY - height - 12))

        rect = NSRect(origin: origin, size: CGSize(width: width, height: height))
        NSColor(calibratedWhite: 0.055, alpha: 0.97).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        border.lineWidth = 1
        border.stroke()

        drawText(row.title, rect: NSRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - 24, height: 16), font: .monospacedDigitSystemFont(ofSize: 11, weight: .bold), color: .white)
        if let subtitle = row.subtitle {
            drawText(subtitle, rect: NSRect(x: rect.minX + 12, y: rect.minY + 26, width: rect.width - 24, height: 14), font: .systemFont(ofSize: 10, weight: .medium), color: NSColor.white.withAlphaComponent(0.45))
        }

        let startY = rect.minY + titleHeight + 6
        let labelWidth: CGFloat = 108
        let valueX = rect.minX + labelWidth + 30
        let valueWidth = rect.maxX - valueX - 14
        for (index, line) in lines.enumerated() {
            let y = startY + CGFloat(index) * rowHeight
            drawText(line.0, rect: NSRect(x: rect.minX + 12, y: y, width: labelWidth, height: 16), font: .systemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.62))
            drawRight(line.1, rect: NSRect(x: valueX, y: y, width: valueWidth, height: 16), color: line.2, font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold))
        }
    }

    private func drawCostOverviewInfoTooltip() {
        guard let info = hoveredCostOverviewInfo,
              let anchorRect = costOverviewInfoRects[info] else {
            return
        }
        let width: CGFloat = 330
        let height: CGFloat = 86
        var origin = CGPoint(x: anchorRect.midX - width / 2, y: anchorRect.maxY + 10)
        if origin.y + height > bounds.maxY - 12 {
            origin.y = anchorRect.minY - height - 10
        }
        origin.x = max(bounds.minX + 12, min(origin.x, bounds.maxX - width - 12))
        origin.y = max(bounds.minY + 12, min(origin.y, bounds.maxY - height - 12))

        let rect = NSRect(origin: origin, size: CGSize(width: width, height: height))
        NSColor(calibratedWhite: 0.055, alpha: 0.97).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        border.lineWidth = 1
        border.stroke()

        drawText(info.title, rect: NSRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - 24, height: 16), font: .systemFont(ofSize: 11, weight: .bold), color: .white)
        drawMultilineText(info.hint, rect: NSRect(x: rect.minX + 12, y: rect.minY + 30, width: rect.width - 24, height: 42), font: .systemFont(ofSize: 10, weight: .medium), color: NSColor.white.withAlphaComponent(0.62))
    }

    private func drawDayValueInfoTooltip() {
        guard isHoveringDayValueInfo, let anchorRect = dayValueInfoRect else { return }
        let width: CGFloat = 300
        let height: CGFloat = 74
        var origin = CGPoint(x: anchorRect.midX - width / 2, y: anchorRect.maxY + 8)
        if origin.x < bounds.minX + 12 {
            origin.x = bounds.minX + 12
        }
        if origin.x + width > bounds.maxX - 12 {
            origin.x = bounds.maxX - width - 12
        }
        if origin.y + height > bounds.maxY - 12 {
            origin.y = anchorRect.minY - height - 8
        }
        origin.y = max(bounds.minY + 12, origin.y)

        let rect = NSRect(origin: origin, size: CGSize(width: width, height: height))
        NSColor(calibratedWhite: 0.055, alpha: 0.97).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        border.lineWidth = 1
        border.stroke()

        drawText(t(.dayValue), rect: NSRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - 24, height: 16), font: .systemFont(ofSize: 11, weight: .bold), color: .white)
        drawMultilineText(t(.dayValueHint), rect: NSRect(x: rect.minX + 12, y: rect.minY + 30, width: rect.width - 24, height: 34), font: .systemFont(ofSize: 10, weight: .medium), color: NSColor.white.withAlphaComponent(0.58))
    }

    private func drawProfileAPIInfoTooltip() {
        guard isHoveringProfileAPIInfo, let anchorRect = profileAPIInfoRect else { return }
        let width: CGFloat = 340
        let height: CGFloat = 82
        var origin = CGPoint(x: anchorRect.midX - width / 2, y: anchorRect.maxY + 8)
        if origin.x < bounds.minX + 12 {
            origin.x = bounds.minX + 12
        }
        if origin.x + width > bounds.maxX - 12 {
            origin.x = bounds.maxX - width - 12
        }
        if origin.y + height > bounds.maxY - 12 {
            origin.y = anchorRect.minY - height - 8
        }
        origin.y = max(bounds.minY + 12, origin.y)

        let rect = NSRect(origin: origin, size: CGSize(width: width, height: height))
        NSColor(calibratedWhite: 0.055, alpha: 0.97).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        border.lineWidth = 1
        border.stroke()

        drawText(t(.profileAPITotals), rect: NSRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - 24, height: 16), font: .systemFont(ofSize: 11, weight: .bold), color: .white)
        drawMultilineText(t(.profileAPITotalsHint), rect: NSRect(x: rect.minX + 12, y: rect.minY + 30, width: rect.width - 24, height: 42), font: .systemFont(ofSize: 10, weight: .medium), color: NSColor.white.withAlphaComponent(0.58))
    }

    private func drawAboutPage(snapshot: DetailsSnapshot, content: NSRect) {
        let rect = NSRect(x: content.minX, y: content.minY + 78, width: content.width, height: 276)
        drawPanel(rect)
        drawText(t(.definitions), rect: NSRect(x: rect.minX + 16, y: rect.minY + 16, width: rect.width - 32, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        let rows = [
            (t(.all), t(.allDescription)),
            (AppSettings.modelLimitSegmentTitle, AppSettings.modelLimitName),
            (t(.other), t(.otherDefinition)),
            (t(.cacheHit), t(.cacheHitDescription))
        ]
        for (index, row) in rows.enumerated() {
            let y = rect.minY + 52 + CGFloat(index) * 38
            drawText(row.0, rect: NSRect(x: rect.minX + 16, y: y, width: 92, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
            drawText(row.1, rect: NSRect(x: rect.minX + 116, y: y, width: rect.width - 132, height: 20), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.56))
        }

        let sourceRect = NSRect(x: content.minX, y: content.minY + 374, width: content.width, height: 126)
        drawPanel(sourceRect)
        drawText(t(.dataSource), rect: NSRect(x: sourceRect.minX + 16, y: sourceRect.minY + 16, width: sourceRect.width - 32, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        drawText(t(.dataSourceLine1), rect: NSRect(x: sourceRect.minX + 16, y: sourceRect.minY + 52, width: sourceRect.width - 32, height: 20), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.58))
        drawText(t(.dataSourceLine2), rect: NSRect(x: sourceRect.minX + 16, y: sourceRect.minY + 78, width: sourceRect.width - 32, height: 20), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
    }

    private func drawContributionGrid(report: TokenReport, rect: NSRect, title: String, compact: Bool) {
        drawPanel(rect)
        drawText(title, rect: NSRect(x: rect.minX + 16, y: rect.minY + 12, width: rect.width - 32, height: 20), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
        let days = report.byDay
        guard !days.isEmpty else {
            drawText(t(.noDailyTokenData), rect: NSRect(x: rect.minX + 16, y: rect.minY + 52, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }

        let maxTotal = max(days.map { $0.usage.total }.max() ?? 1, 1)
        let useCalendarGrid = !compact || days.count > 90
        let enableDayHover = selectedSection == .overview && compact
        let enableWeekHover = selectedSection == .calendar && !compact && useCalendarGrid
        let columns = useCalendarGrid ? Int(ceil(Double(days.count) / 7.0)) : min(days.count, 15)
        let rows = useCalendarGrid ? 7 : Int(ceil(Double(days.count) / Double(max(columns, 1))))
        let gap: CGFloat = useCalendarGrid ? (compact ? 2 : 3) : 6
        let left: CGFloat = compact ? 18 : 26
        let right: CGFloat = compact ? 18 : 26
        let top: CGFloat = compact ? 42 : 48
        let bottom: CGFloat = compact ? 44 : 50
        let availableW = max(40, rect.width - left - right)
        let availableH = max(40, rect.height - top - bottom)
        let square = floor(min((availableW - gap * CGFloat(max(columns - 1, 0))) / CGFloat(max(columns, 1)), (availableH - gap * CGFloat(max(rows - 1, 0))) / CGFloat(max(rows, 1))))
        let gridH = CGFloat(rows) * square + CGFloat(max(rows - 1, 0)) * gap
        let startX = rect.minX + left
        let startY = rect.minY + top
        var cells: [(day: DayUsage, rect: NSRect, column: Int)] = []
        var weekCells: [Int: [NSRect]] = [:]
        var weekStartDays: [Int: String] = [:]
        var weekEndDays: [Int: String] = [:]
        var weekTotals: [Int: Int64] = [:]
        var weekActiveDays: [Int: Int] = [:]

        for (index, day) in days.enumerated() {
            let col = useCalendarGrid ? index / 7 : index % columns
            let row = useCalendarGrid ? index % 7 : index / columns
            let cell = NSRect(x: startX + CGFloat(col) * (square + gap), y: startY + CGFloat(row) * (square + gap), width: square, height: square)
            cells.append((day: day, rect: cell, column: col))
            contributionDayRects[day.day] = cell
            if enableDayHover {
                contributionDaySummaries[day.day] = ContributionDaySummary(day: day, hitRect: cell)
            }
            if enableWeekHover {
                weekCells[col, default: []].append(cell)
                if weekStartDays[col] == nil {
                    weekStartDays[col] = day.day
                }
                weekEndDays[col] = day.day
                weekTotals[col, default: 0] += day.usage.total
                if day.usage.total > 0 {
                    weekActiveDays[col, default: 0] += 1
                }
            }
        }

        if enableWeekHover {
            var summaries: [String: ContributionWeekSummary] = [:]
            for column in 0..<columns {
                guard let rects = weekCells[column], !rects.isEmpty else { continue }
                let key = "week-\(column)-\(weekStartDays[column] ?? "")"
                let unionRect = rects.dropFirst().reduce(rects[0]) { partial, cell in
                    partial.union(cell)
                }.insetBy(dx: -gap / 2, dy: -gap / 2)
                summaries[key] = ContributionWeekSummary(
                    key: key,
                    startDay: weekStartDays[column] ?? "",
                    endDay: weekEndDays[column] ?? "",
                    total: weekTotals[column] ?? 0,
                    activeDays: weekActiveDays[column] ?? 0,
                    hitRect: unionRect,
                    cellRects: rects
                )
            }
            contributionWeekSummaries = summaries
            if let hoveredContributionWeekKey,
               let summary = contributionWeekSummaries[hoveredContributionWeekKey] {
                drawContributionWeekHighlight(summary)
            }
        }

        for cellData in cells {
            let day = cellData.day
            let cell = cellData.rect
            let intensity = Double(day.usage.total) / Double(maxTotal)
            contributionColor(intensity).setFill()
            NSBezierPath(roundedRect: cell, xRadius: 3, yRadius: 3).fill()
            if day.day == selectedDay {
                NSColor.white.withAlphaComponent(0.92).setStroke()
                let path = NSBezierPath(roundedRect: cell.insetBy(dx: -2, dy: -2), xRadius: 5, yRadius: 5)
                path.lineWidth = 2
                path.stroke()
            } else if enableDayHover && day.day == hoveredContributionDay {
                NSColor.white.withAlphaComponent(0.72).setStroke()
                let path = NSBezierPath(roundedRect: cell.insetBy(dx: -2, dy: -2), xRadius: 5, yRadius: 5)
                path.lineWidth = 1.5
                path.stroke()
            }
        }

        let labelY = min(startY + gridH + 10, rect.maxY - 38)
        let hintY = min(labelY + 18, rect.maxY - 20)
        drawContributionMonthLabels(days: days, useCalendarGrid: useCalendarGrid, columns: columns, square: square, gap: gap, startX: startX, y: labelY, compact: compact)
        drawText(t(.usageIntensityHint), rect: NSRect(x: startX, y: hintY, width: min(320, rect.maxX - startX - right), height: 16), font: .systemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.42))
        if enableDayHover,
           let hoveredContributionDay,
           let summary = contributionDaySummaries[hoveredContributionDay] {
            drawContributionDayTooltip(summary, container: rect)
        }
        if enableWeekHover,
           let hoveredContributionWeekKey,
           let summary = contributionWeekSummaries[hoveredContributionWeekKey] {
            drawContributionWeekTooltip(summary, container: rect)
        }
    }

    private func drawContributionDayTooltip(_ summary: ContributionDaySummary, container: NSRect) {
        let width: CGFloat = 214
        let height: CGFloat = 92
        let gap: CGFloat = 12
        var origin = CGPoint(x: summary.hitRect.maxX + gap, y: summary.hitRect.midY - height / 2)
        if origin.x + width > container.maxX - 12 {
            origin.x = summary.hitRect.minX - gap - width
        }
        if origin.x < container.minX + 12 {
            origin.x = summary.hitRect.midX - width / 2
            origin.y = summary.hitRect.minY - height - gap
        }
        if origin.y < container.minY + 10 {
            origin.y = summary.hitRect.maxY + gap
        }
        origin.x = max(container.minX + 12, min(origin.x, container.maxX - width - 12))
        origin.y = max(container.minY + 10, min(origin.y, container.maxY - height - 10))
        let tooltipRect = NSRect(origin: origin, size: NSSize(width: width, height: height))

        NSColor(calibratedWhite: 0.055, alpha: 0.97).setFill()
        NSBezierPath(roundedRect: tooltipRect, xRadius: 8, yRadius: 8).fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        let border = NSBezierPath(roundedRect: tooltipRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        border.lineWidth = 1
        border.stroke()

        let day = summary.day
        let planValue = contributionDayPlanValue(day)
        let apiEstimate = contributionDayAPIEstimate(day)
        let rows: [(String, String)] = [
            ("Token", compactDashboardTotal(day.usage.total)),
            (contributionPlanAmountLabel(), planValue.map { displayMoney($0) } ?? "--"),
            (contributionAPIAmountLabel(), apiEstimate.hasPricedUsage ? displayAPIMoney(apiEstimate.usdValue) : "--")
        ]
        drawText(localizedContributionDate(day.day), rect: NSRect(x: tooltipRect.minX + 10, y: tooltipRect.minY + 8, width: tooltipRect.width - 20, height: 14), font: .systemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.82))
        for (index, row) in rows.enumerated() {
            let y = tooltipRect.minY + 27 + CGFloat(index) * 16
            drawText(row.0, rect: NSRect(x: tooltipRect.minX + 10, y: y, width: 84, height: 14), font: .systemFont(ofSize: 10, weight: .medium), color: NSColor.white.withAlphaComponent(0.52))
            drawRight(row.1, rect: NSRect(x: tooltipRect.minX + 92, y: y - 1, width: tooltipRect.width - 102, height: 15), color: NSColor.white.withAlphaComponent(0.86), font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold))
        }
        drawText(t(.clickForDetails), rect: NSRect(x: tooltipRect.minX + 10, y: tooltipRect.maxY - 18, width: tooltipRect.width - 20, height: 13), font: .systemFont(ofSize: 9, weight: .medium), color: accentTeal.withAlphaComponent(0.74))
    }

    private func contributionDayPlanValue(_ day: DayUsage) -> Double? {
        guard let snapshot else { return nil }
        let report = calendarReport(for: snapshot)
        let reportDay = report.byDay.first { $0.day == day.day } ?? day
        return planCostEstimate(
            report: report,
            selectedDay: reportDay,
            limit: costEstimateLimit(from: snapshot.liveLimits),
            quotaReferenceReport: snapshot.costReferenceReport
        )?.selectedDayValue
    }

    private func contributionDayAPIEstimate(_ day: DayUsage) -> APICostEstimate {
        guard let snapshot, usesProfileAPIReport(for: snapshot) else {
            return APICostEstimator.estimate(day: day)
        }
        let localDay = snapshot.all.byDay.first { $0.day == day.day }
        return profileAPIDayEstimate(profileDay: day, localDay: localDay)
    }

    private func contributionPlanAmountLabel() -> String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese:
            return "对应金额"
        case .japanese:
            return "対応金額"
        default:
            return "Plan value"
        }
    }

    private func contributionAPIAmountLabel() -> String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese:
            return "API 金额"
        case .japanese:
            return "API 金額"
        default:
            return "API cost"
        }
    }

    private func drawContributionWeekHighlight(_ summary: ContributionWeekSummary) {
        let rect = summary.hitRect.insetBy(dx: -4, dy: -4)
        accentTeal.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        accentTeal.withAlphaComponent(0.40).setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        border.lineWidth = 1
        border.stroke()
    }

    private func drawContributionWeekTooltip(_ summary: ContributionWeekSummary, container: NSRect) {
        let line = contributionWeekTooltipLine(summary)
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let textWidth = measuredTextWidth(line, font: font)
        let width = min(max(textWidth + 32, 260), container.width - 32)
        let height: CGFloat = 42
        var origin = CGPoint(x: summary.hitRect.midX - width / 2, y: summary.hitRect.minY - height - 12)
        if origin.y < container.minY + 40 {
            origin.y = summary.hitRect.maxY + 12
        }
        origin.x = max(container.minX + 12, min(origin.x, container.maxX - width - 12))
        origin.y = max(container.minY + 10, min(origin.y, container.maxY - height - 10))
        let tooltipRect = NSRect(origin: origin, size: NSSize(width: width, height: height))

        NSColor(calibratedWhite: 0.18, alpha: 0.96).setFill()
        NSBezierPath(roundedRect: tooltipRect, xRadius: 9, yRadius: 9).fill()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        let border = NSBezierPath(roundedRect: tooltipRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        border.lineWidth = 1
        border.stroke()
        drawCentered(line, rect: tooltipRect.insetBy(dx: 14, dy: 0), font: font, color: .white)
    }

    private func contributionWeekTooltipLine(_ summary: ContributionWeekSummary) -> String {
        let total = compactDashboardTotal(summary.total)
        switch AppLanguage.current {
        case .chinese, .traditionalChinese:
            return "\(localizedContributionDate(summary.startDay)) 当周使用了 \(total) 个 Token"
        case .japanese:
            return "\(localizedContributionDate(summary.startDay)) の週に \(total) Token 使用"
        default:
            return "Week of \(localizedContributionDate(summary.startDay)) used \(total) tokens"
        }
    }

    private func localizedContributionDate(_ day: String) -> String {
        guard let date = dayFormatter().date(from: day) else { return day }
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        switch AppLanguage.current {
        case .chinese, .traditionalChinese:
            formatter.locale = Locale(identifier: "zh_Hans_CN")
            formatter.dateFormat = "yyyy年M月d日"
        case .japanese:
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.dateFormat = "yyyy年M月d日"
        default:
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "MMM d, yyyy"
        }
        return formatter.string(from: date)
    }

    private func contributionGridPreferredHeight(report: TokenReport, width: CGFloat, compact: Bool) -> CGFloat {
        let days = report.byDay
        guard !days.isEmpty else {
            return compact ? 112 : 128
        }
        let useCalendarGrid = !compact || days.count > 90
        let columns = useCalendarGrid ? Int(ceil(Double(days.count) / 7.0)) : min(days.count, 15)
        let rows = useCalendarGrid ? 7 : Int(ceil(Double(days.count) / Double(max(columns, 1))))
        let gap: CGFloat = useCalendarGrid ? (compact ? 2 : 3) : 6
        let left: CGFloat = compact ? 18 : 26
        let right: CGFloat = compact ? 18 : 26
        let top: CGFloat = compact ? 42 : 48
        let availableW = max(40, width - left - right)
        let square = floor((availableW - gap * CGFloat(max(columns - 1, 0))) / CGFloat(max(columns, 1)))
        let gridH = CGFloat(rows) * max(6, square) + CGFloat(max(rows - 1, 0)) * gap
        let labelAndHintHeight: CGFloat = compact ? 48 : 54
        return ceil(top + gridH + labelAndHintHeight)
    }

    private func drawContributionMonthLabels(days: [DayUsage], useCalendarGrid: Bool, columns: Int, square: CGFloat, gap: CGFloat, startX: CGFloat, y: CGFloat, compact: Bool) {
        var lastMonth: String?
        var lastLabelX = -CGFloat.greatestFiniteMagnitude
        let minimumGap: CGFloat = compact ? 42 : 50
        for (index, day) in days.enumerated() {
            let month = String(day.day.prefix(7))
            guard month != lastMonth else { continue }
            lastMonth = month
            let col = useCalendarGrid ? index / 7 : index % columns
            let x = startX + CGFloat(col) * (square + gap)
            guard x - lastLabelX >= minimumGap else { continue }
            let label = contributionMonthLabel(for: day.day)
            drawText(label, rect: NSRect(x: x, y: y, width: 44, height: 14), font: .systemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.44))
            lastLabelX = x
        }
    }

    private func contributionMonthLabel(for day: String) -> String {
        guard let date = dayFormatter().date(from: day) else {
            return String(day.dropFirst(5).prefix(2))
        }
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        switch AppLanguage.current {
        case .english:
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "MMM"
        case .chinese:
            formatter.locale = Locale(identifier: "zh_Hans_CN")
            formatter.dateFormat = "M月"
        case .japanese:
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.dateFormat = "M月"
        default:
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "MMM"
        }
        return formatter.string(from: date)
    }

    private func drawPanel(_ rect: NSRect) {
        panelSurfaceColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        NSColor.white.withAlphaComponent(0.035).setFill()
        NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: min(1.5, rect.height)), xRadius: 0, yRadius: 0).fill()
        borderColor.setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
    }

    private func drawInputFieldBackground(_ rect: NSRect) {
        guard selectedSection == .costs, !rect.isEmpty else { return }
        inputSurfaceColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        let focused = costAmountField.currentEditor() != nil && rect == costAmountField.frame
            || paymentStartDayField.currentEditor() != nil && rect == paymentStartDayField.frame
        (focused ? accentBlue.withAlphaComponent(0.72) : borderColor).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
    }

    private func drawSmallButton(_ title: String, rect: NSRect, emphasized: Bool = false) {
        (emphasized ? accentBlue.withAlphaComponent(0.72) : NSColor.white.withAlphaComponent(0.12)).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        (emphasized ? accentTeal.withAlphaComponent(0.34) : NSColor.white.withAlphaComponent(0.09)).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7).stroke()
        drawCentered(title, rect: rect.insetBy(dx: 6, dy: 0), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(emphasized ? 0.96 : 0.78))
    }

    private func drawInfoMark(rect: NSRect, highlighted: Bool) {
        (highlighted ? accentTeal.withAlphaComponent(0.28) : NSColor.white.withAlphaComponent(0.10)).setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
        (highlighted ? accentTeal.withAlphaComponent(0.74) : NSColor.white.withAlphaComponent(0.18)).setStroke()
        NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5)).stroke()
        drawCentered("?", rect: rect.offsetBy(dx: 0, dy: -0.5), font: .systemFont(ofSize: 10, weight: .bold), color: highlighted ? accentTeal : NSColor.white.withAlphaComponent(0.58))
    }

    private func drawSelectablePill(_ title: String, rect: NSRect, selected: Bool) {
        if selected {
            accentBlue.withAlphaComponent(0.72).setFill()
        } else {
            inputSurfaceColor.withAlphaComponent(0.82).setFill()
        }
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        (selected ? accentTeal.withAlphaComponent(0.38) : borderColor).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
        drawCentered(title, rect: rect.insetBy(dx: 8, dy: 0), font: .systemFont(ofSize: 12, weight: .semibold), color: .white)
    }

    private func contributionColor(_ intensity: Double) -> NSColor {
        if intensity <= 0 { return NSColor.white.withAlphaComponent(0.08) }
        if intensity < 0.25 { return accentTeal.withAlphaComponent(0.30) }
        if intensity < 0.50 { return accentTeal.withAlphaComponent(0.52) }
        if intensity < 0.75 { return accentTeal.withAlphaComponent(0.74) }
        return accentTeal
    }

    private func drawText(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color])
    }

    private func drawMultilineText(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 2
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }

    private func fillDonut(in outerRect: NSRect, thickness: CGFloat, color: NSColor) {
        let innerRect = outerRect.insetBy(dx: thickness, dy: thickness)
        let path = NSBezierPath()
        path.windingRule = .evenOdd
        path.appendOval(in: outerRect)
        path.appendOval(in: innerRect)
        color.setFill()
        path.fill()
    }

    private func fillDonutSegment(center: CGPoint, outerRadius: CGFloat, thickness: CGFloat, startAngle: CGFloat, endAngle: CGFloat, color: NSColor) {
        let innerRadius = max(0, outerRadius - thickness)
        let path = NSBezierPath()
        let startDegrees = startAngle * 180 / .pi
        let endDegrees = endAngle * 180 / .pi
        path.appendArc(withCenter: center, radius: outerRadius, startAngle: startDegrees, endAngle: endDegrees, clockwise: false)
        path.appendArc(withCenter: center, radius: innerRadius, startAngle: endDegrees, endAngle: startDegrees, clockwise: true)
        path.close()
        color.setFill()
        path.fill()
    }

    private func measuredTextWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private func drawCentered(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        let size = (text as NSString).size(withAttributes: attributes)
        let textRect = NSRect(
            x: rect.minX,
            y: rect.midY - ceil(size.height) / 2,
            width: rect.width,
            height: ceil(size.height)
        )
        (text as NSString).draw(in: textRect, withAttributes: attributes)
    }

    private func drawRight(_ text: String, rect: NSRect, color: NSColor, font: NSFont = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let dashboardController = DashboardViewController()
    private let detailsController = UsageDetailsWindowController()
    private var scanner = CodexTokenScanner(rootURLs: AppSettings.logFolderURLs)
    private let rateLimitReader = LiveRateLimitReader()
    private let accountUsageReader = AccountUsageReader()
    private let serviceStatusReader = CodexServiceStatusReader()
    private let localFormatter = DateFormatter()
    private let scanQueue = DispatchQueue(label: "local.codex-token-meter.scan", qos: .utility)
    private let liveQueue = DispatchQueue(label: "local.codex-token-meter.live", qos: .utility)
    private var selectedWindow: WindowOption = .week
    private var selectedQuota: QuotaViewOption = .all
    private var latestState = DashboardState()
    private var reportCache: [ReportCacheKey: TokenReport] = [:]
    private var accountUsage: AccountUsageSnapshot?
    private var liveLimits: [LiveRateLimit] = []
    private var serviceStatus: CodexServiceStatusSnapshot?
    private var refreshTimer: Timer?
    private var liveRefreshTimer: Timer?
    private var activeScans: Set<ReportCacheKey> = []
    private var liveRefreshInFlight = false
    private var statusSpinnerTimer: Timer?
    private var statusSpinnerFrame = 0
    private var statusIsLoading = false
    private let refreshInterval: TimeInterval = 300
    private let liveRefreshInterval: TimeInterval = 60
    private let statusIconSize = NSSize(width: 14, height: 14)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        localFormatter.locale = Locale(identifier: "en_US_POSIX")
        localFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        localFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        selectedWindow = .day
        if let rawQuota = UserDefaults.standard.string(forKey: "selectedQuotaView"),
           let quota = QuotaViewOption(rawValue: rawQuota) {
            selectedQuota = quota
        }

        NSApp.applicationIconImage = NSImage(named: "LogoHeader")
        popover.contentViewController = dashboardController
        popover.contentSize = DashboardView.idealSize
        popover.behavior = .transient
        configureStatusButton()

        dashboardController.dashboardView.onWindowChanged = { [weak self] option in self?.selectWindow(option) }
        dashboardController.dashboardView.onQuotaChanged = { [weak self] option in self?.selectQuota(option) }
        dashboardController.dashboardView.onRefresh = { [weak self] in
            self?.refresh(forceLive: false)
            self?.refreshLiveLimits()
        }
        dashboardController.dashboardView.onOpenDetails = { [weak self] in self?.openUsageDetailsWindow() }
        dashboardController.dashboardView.onOpenSettings = { [weak self] in self?.openSettingsWindow() }
        dashboardController.dashboardView.onOpenCodexStatus = { [weak self] in self?.openCodexStatusPage() }
        dashboardController.dashboardView.onQuit = { NSApp.terminate(nil) }
        detailsController.detailsView.onLanguageChanged = { [weak self] language in
            AppLanguage.current = language
            self?.applyLanguage()
        }
        detailsController.detailsView.onNumberUnitStyleChanged = { [weak self] style in
            self?.changeNumberUnitStyle(style)
        }
        detailsController.detailsView.onStatusDisplayChanged = { [weak self] option in
            guard let self else { return }
            StatusDisplayOption.current = option
            detailsController.detailsView.needsDisplay = true
            updateStatusTitle(report: latestState.report, limits: liveLimits, quota: selectedQuota)
        }
        detailsController.detailsView.onQuotaDisplayStyleChanged = { [weak self] style in
            self?.changeQuotaDisplayStyle(style)
        }
        detailsController.detailsView.onPlanCostChanged = { [weak self] value in self?.changePlanCost(value) }
        detailsController.detailsView.onPaymentStartDayChanged = { [weak self] value in self?.changePaymentStartDay(value) }
        detailsController.detailsView.onPaymentCurrencyChanged = { [weak self] currency in self?.changePaymentCurrency(currency) }
        detailsController.detailsView.onDisplayCurrencyChanged = { [weak self] currency in self?.changeDisplayCurrency(currency) }
        detailsController.detailsView.onShowHistoricalEmptyWeeksChanged = { [weak self] isOn in self?.changeShowHistoricalEmptyWeeks(isOn) }
        detailsController.detailsView.onChooseLogFolder = { [weak self] in self?.chooseLogFolder() }
        detailsController.detailsView.onResetLogFolder = { [weak self] in self?.resetLogFolder() }
        detailsController.detailsView.onOpenLogFolder = { [weak self] in self?.openSessionsFolder() }
        detailsController.detailsView.onLaunchAtLoginChanged = { [weak self] isOn in self?.changeLaunchAtLogin(isOn) }
        detailsController.detailsView.onShowCodexStatusChanged = { [weak self] isOn in self?.changeShowCodexStatus(isOn) }
        detailsController.detailsView.onQuotaWarningsChanged = { [weak self] isOn in self?.changeQuotaWarnings(isOn) }
        detailsController.detailsView.onProfileAPITotalsChanged = { [weak self] isOn in self?.changeProfileAPITotals(isOn) }
        applyLanguage()
        QuotaWarningManager.shared.requestAuthorization()

        refresh(forceLive: false)
        refreshLiveLimits()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh(forceLive: false)
        }
        liveRefreshTimer = Timer.scheduledTimer(withTimeInterval: liveRefreshInterval, repeats: true) { [weak self] _ in
            self?.refreshLiveLimits()
        }
    }

    private func configureStatusButton() {
        statusItem.length = NSStatusItem.variableLength
        guard let button = statusItem.button else { return }
        button.image = statusIconImage()
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.title = "--%"
        button.toolTip = "Codex Token Meter"
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        button.action = #selector(togglePopover)
        button.target = self
    }

    private func statusIconImage() -> NSImage? {
        let image = NSImage(named: "StatusIconTemplate")
        image?.isTemplate = true
        image?.size = statusIconSize
        return image
    }

    private func setStatusLoading(_ loading: Bool) {
        guard statusIsLoading != loading else { return }
        statusIsLoading = loading
        statusSpinnerTimer?.invalidate()
        statusSpinnerTimer = nil

        guard let button = statusItem.button else { return }
        if loading {
            statusSpinnerFrame = 0
            updateStatusSpinnerImage()
            let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
                self?.updateStatusSpinnerImage()
            }
            statusSpinnerTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else {
            button.image = statusIconImage()
        }
    }

    private func updateStatusSpinnerImage() {
        guard let button = statusItem.button else { return }
        button.image = spinnerImage(frame: statusSpinnerFrame)
        statusSpinnerFrame = (statusSpinnerFrame + 1) % 12
    }

    private func spinnerImage(frame: Int) -> NSImage {
        let size = statusIconSize
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setStroke()
        let center = NSPoint(x: size.width / 2, y: size.height / 2)
        let radius: CGFloat = 4.8
        let start = CGFloat(frame) * 30
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: start + 255, clockwise: false)
        path.lineWidth = 1.8
        path.lineCapStyle = .round
        path.stroke()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func applyLanguage() {
        detailsController.applyLanguage()
        dashboardController.dashboardView.applyLanguage()
        dashboardController.dashboardView.update(latestState)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func selectWindow(_ option: WindowOption) {
        selectedWindow = option
        UserDefaults.standard.set(option.rawValue, forKey: "selectedWindowHours")
        showCachedOrLoadingState()
        refresh(forceLive: false)
        if liveLimits.isEmpty {
            refreshLiveLimits()
        }
    }

    private func selectQuota(_ option: QuotaViewOption) {
        selectedQuota = option
        UserDefaults.standard.set(option.rawValue, forKey: "selectedQuotaView")
        showCachedOrLoadingState()
        refresh(forceLive: false)
        if liveLimits.isEmpty {
            refreshLiveLimits()
        }
    }

    private func showCachedOrLoadingState() {
        let key = ReportCacheKey(window: selectedWindow, quota: selectedQuota)
        if let cached = reportCache[key] {
            latestState = DashboardState(
                report: cached,
                profileReport: profileReport(window: selectedWindow, quota: selectedQuota, accountUsage: accountUsage, localReport: cached),
                accountUsage: accountUsage,
                costReferenceReport: costReferenceReport(quota: selectedQuota, fallback: cached),
                liveLimits: liveLimits,
                serviceStatus: serviceStatus,
                selectedWindow: selectedWindow,
                selectedQuota: selectedQuota,
                nextRefreshAt: latestState.nextRefreshAt,
                isLoading: false,
                error: nil
            )
            dashboardController.dashboardView.update(latestState)
            updateStatusTitle(report: cached, limits: liveLimits, quota: selectedQuota)
        } else {
            latestState = DashboardState(
                report: TokenReport(scannedAt: Date()),
                profileReport: profileReport(window: selectedWindow, quota: selectedQuota, accountUsage: accountUsage, localReport: nil),
                accountUsage: accountUsage,
                costReferenceReport: costReferenceReport(quota: selectedQuota, fallback: nil),
                liveLimits: liveLimits,
                serviceStatus: serviceStatus,
                selectedWindow: selectedWindow,
                selectedQuota: selectedQuota,
                nextRefreshAt: latestState.nextRefreshAt,
                isLoading: true,
                error: nil
            )
            dashboardController.dashboardView.update(latestState)
            updateStatusTitle(report: latestState.report, limits: liveLimits, quota: selectedQuota)
        }
    }

    private func refresh(forceLive: Bool) {
        let window = selectedWindow
        let quota = selectedQuota
        let key = ReportCacheKey(window: window, quota: quota)
        guard !activeScans.contains(key) else { return }
        activeScans.insert(key)

        latestState = DashboardState(
            report: reportCache[key] ?? TokenReport(scannedAt: Date()),
            profileReport: profileReport(window: window, quota: quota, accountUsage: accountUsage, localReport: reportCache[key]),
            accountUsage: accountUsage,
            costReferenceReport: costReferenceReport(quota: quota, fallback: reportCache[key]),
            liveLimits: liveLimits,
            serviceStatus: serviceStatus,
            selectedWindow: window,
            selectedQuota: quota,
            nextRefreshAt: latestState.nextRefreshAt,
            isLoading: true,
            error: nil
        )
        dashboardController.dashboardView.update(latestState)
        updateStatusTitle(report: latestState.report, limits: liveLimits, quota: quota)
        let currentLimits = liveLimits
        let currentAccountUsage = accountUsage

        scanQueue.async {
            let report = self.scanner.scan(window: window, includedModelName: quota.includedModelName, excludedModelName: quota.excludedModelName)
            let accountUsage = self.readAccountUsageIfNeeded(fallback: currentAccountUsage)
            let limits = forceLive ? self.rateLimitReader.read() : currentLimits
            if forceLive, !limits.isEmpty {
                AppSettings.learnModelLimit(from: limits)
                CostHistoryStore.shared.record(limits: limits)
                QuotaWarningManager.shared.evaluate(limits: limits)
            }
            let nextRefresh = Date().addingTimeInterval(self.refreshInterval)
            DispatchQueue.main.async {
                self.activeScans.remove(key)
                self.reportCache[key] = report
                if let accountUsage {
                    self.accountUsage = accountUsage
                } else if !AppSettings.profileAPITotalsEnabled {
                    self.accountUsage = nil
                }
                if forceLive, !limits.isEmpty {
                    self.liveLimits = limits
                }
                if self.selectedWindow == window && self.selectedQuota == quota {
                    let effectiveLimits = forceLive && !limits.isEmpty ? limits : self.liveLimits
                    self.latestState = DashboardState(
                        report: report,
                        profileReport: self.profileReport(window: window, quota: quota, accountUsage: self.accountUsage, localReport: report),
                        accountUsage: self.accountUsage,
                        costReferenceReport: self.costReferenceReport(quota: quota, fallback: report),
                        liveLimits: effectiveLimits,
                        serviceStatus: self.serviceStatus,
                        selectedWindow: window,
                        selectedQuota: quota,
                        nextRefreshAt: nextRefresh,
                        isLoading: false,
                        error: effectiveLimits.isEmpty ? "Live limits unavailable" : nil
                    )
                    self.updateStatusTitle(report: report, limits: self.latestState.liveLimits, quota: quota)
                    self.dashboardController.dashboardView.update(self.latestState)
                } else if forceLive, !limits.isEmpty {
                    self.latestState.liveLimits = limits
                    self.latestState.serviceStatus = self.serviceStatus
                    self.latestState.accountUsage = self.accountUsage
                    self.latestState.profileReport = self.profileReport(window: self.latestState.selectedWindow, quota: self.latestState.selectedQuota, accountUsage: self.accountUsage, localReport: self.latestState.report)
                    self.updateStatusTitle(report: self.latestState.report, limits: limits, quota: self.latestState.selectedQuota)
                    self.dashboardController.dashboardView.update(self.latestState)
                }
                self.prewarmAllWindows()
            }
        }
    }

    private func refreshLiveLimits() {
        guard !liveRefreshInFlight else { return }
        liveRefreshInFlight = true
        liveQueue.async {
            let limits = self.rateLimitReader.read()
            let serviceStatus = self.serviceStatusReader.read()
            AppSettings.learnModelLimit(from: limits)
            CostHistoryStore.shared.record(limits: limits)
            QuotaWarningManager.shared.evaluate(limits: limits)
            let costReferenceReport = self.liveCostReferenceReport(limits: limits)
            DispatchQueue.main.async {
                self.liveRefreshInFlight = false
                if let serviceStatus {
                    self.serviceStatus = serviceStatus
                    self.latestState.serviceStatus = serviceStatus
                    self.detailsController.updateServiceStatus(serviceStatus)
                }
                guard !limits.isEmpty else {
                    self.updateStatusTitle(report: self.latestState.report, limits: self.liveLimits, quota: self.latestState.selectedQuota)
                    self.dashboardController.dashboardView.update(self.latestState)
                    return
                }
                self.liveLimits = limits
                self.latestState.liveLimits = limits
                self.latestState.error = nil
                self.updateStatusTitle(report: self.latestState.report, limits: limits, quota: self.latestState.selectedQuota)
                self.dashboardController.dashboardView.update(self.latestState)
                self.detailsController.updateLiveLimits(limits, costReferenceReport: costReferenceReport, serviceStatus: self.serviceStatus)
            }
        }
    }

    private func prewarmAllWindows() {
        for quota in QuotaViewOption.allCases {
            prewarm(window: .day, quota: quota)
            prewarm(window: .week, quota: quota)
            prewarm(window: .month, quota: quota)
        }
    }

    private func prewarm(window: WindowOption, quota: QuotaViewOption) {
        let key = ReportCacheKey(window: window, quota: quota)
        guard reportCache[key] == nil, !activeScans.contains(key) else { return }
        activeScans.insert(key)
        scanQueue.async {
            let report = self.scanner.scan(window: window, includedModelName: quota.includedModelName, excludedModelName: quota.excludedModelName)
            DispatchQueue.main.async {
                self.activeScans.remove(key)
                self.reportCache[key] = report
                self.updateStatusTitle(report: self.latestState.report, limits: self.liveLimits, quota: self.latestState.selectedQuota)
                if self.selectedWindow == window && self.selectedQuota == quota {
                    self.latestState = DashboardState(
                        report: report,
                        profileReport: self.profileReport(window: window, quota: quota, accountUsage: self.accountUsage, localReport: report),
                        accountUsage: self.accountUsage,
                        costReferenceReport: self.costReferenceReport(quota: quota, fallback: report),
                        liveLimits: self.liveLimits,
                        serviceStatus: self.serviceStatus,
                        selectedWindow: window,
                        selectedQuota: quota,
                        nextRefreshAt: self.latestState.nextRefreshAt,
                        isLoading: false,
                        error: nil
                    )
                    self.updateStatusTitle(report: report, limits: self.liveLimits, quota: quota)
                    self.dashboardController.dashboardView.update(self.latestState)
                } else if window == .week && self.selectedQuota == quota {
                    self.latestState.costReferenceReport = report
                    self.dashboardController.dashboardView.update(self.latestState)
                }
            }
        }
    }

    private func readAccountUsageIfNeeded(fallback: AccountUsageSnapshot?) -> AccountUsageSnapshot? {
        guard AppSettings.profileAPITotalsEnabled else { return nil }
        return accountUsageReader.read() ?? fallback
    }

    private func profileReport(window: WindowOption, quota: QuotaViewOption, accountUsage: AccountUsageSnapshot?, localReport: TokenReport?) -> TokenReport? {
        guard AppSettings.profileAPITotalsEnabled,
              quota == .all,
              let accountUsage,
              accountUsage.hasData else {
            return nil
        }
        let report: TokenReport
        if window == .day {
            let todayReport = accountUsage.report(days: 1)
            if todayReport.usage.total == 0, localReport?.usage.total ?? 0 > 0 {
                report = todayReport
            } else {
                report = accountUsage.report(window: window)
            }
        } else {
            report = accountUsage.report(window: window)
        }
        return profileReportWithLocalFallback(report, localReport: localReport)
    }

    private func costReferenceReport(quota: QuotaViewOption, fallback: TokenReport?) -> TokenReport? {
        reportCache[ReportCacheKey(window: .week, quota: quota)] ?? fallback
    }

    private func liveCostReferenceReport(limits: [LiveRateLimit]) -> TokenReport? {
        guard let weekly = costEstimateLimit(from: limits)?.secondary,
              weekly.usedPercent > 0,
              weekly.windowMinutes > 0,
              let resetsAt = weekly.resetsAt else {
            return nil
        }
        let start = resetsAt.addingTimeInterval(-TimeInterval(weekly.windowMinutes) * 60)
        let now = Date()
        guard start < now else { return nil }
        return scanner.scan(from: start, to: now)
    }

    private func updateStatusTitle(report: TokenReport, limits: [LiveRateLimit], quota: QuotaViewOption) {
        statusItem.length = NSStatusItem.variableLength
        guard let button = statusItem.button else { return }
        let option = StatusDisplayOption.current
        requestStatusUsageIfNeeded(option: option, quota: quota)
        let title = statusTitle(report: report, limits: limits, quota: quota, option: option)
        let pending = latestState.isLoading || statusValueIsPending(option: option, quota: quota, limits: limits)
        button.title = title ?? "--"
        setStatusLoading(pending)
    }

    private func statusTitle(report: TokenReport, limits: [LiveRateLimit], quota: QuotaViewOption, option: StatusDisplayOption) -> String? {
        let limit = selectedLimit(from: limits, quota: quota)
        switch option {
        case .fiveHourPercent:
            if let live = limit?.primary.remainingPercent {
                return "\(Int(round(live)))%"
            }
        case .weeklyPercent:
            if let live = limit?.secondary.remainingPercent {
                return "\(Int(round(live)))%"
            }
        case .weeklyTokens:
            if let usage = statusUsage(window: .week, quota: quota)?.usage, usage.total > 0 {
                return compact(usage.total)
            }
        case .dailyTokens:
            if let usage = statusUsage(window: .day, quota: quota)?.usage, usage.total > 0 {
                return compact(usage.total)
            }
        }
        return nil
    }

    private func requestStatusUsageIfNeeded(option: StatusDisplayOption, quota: QuotaViewOption) {
        guard let window = option.requiredReportWindow else { return }
        let key = ReportCacheKey(window: window, quota: quota)
        guard reportCache[key] == nil, !activeScans.contains(key) else { return }
        prewarm(window: window, quota: quota)
    }

    private func statusValueIsPending(option: StatusDisplayOption, quota: QuotaViewOption, limits: [LiveRateLimit]) -> Bool {
        switch option {
        case .fiveHourPercent:
            return selectedLimit(from: limits, quota: quota)?.primary.remainingPercent == nil && liveRefreshInFlight
        case .weeklyPercent:
            return selectedLimit(from: limits, quota: quota)?.secondary.remainingPercent == nil && liveRefreshInFlight
        case .weeklyTokens, .dailyTokens:
            guard let window = option.requiredReportWindow else { return false }
            let key = ReportCacheKey(window: window, quota: quota)
            return reportCache[key] == nil || activeScans.contains(key)
        }
    }

    private func statusUsage(window: WindowOption, quota: QuotaViewOption) -> TokenReport? {
        let key = ReportCacheKey(window: window, quota: quota)
        let localReport = reportCache[key] ?? (latestState.selectedWindow == window && latestState.selectedQuota == quota ? latestState.report : nil)
        if let profileReport = profileReport(window: window, quota: quota, accountUsage: accountUsage, localReport: localReport) {
            return profileReport
        }
        if let cached = reportCache[key] {
            return cached
        }
        if latestState.selectedWindow == window && latestState.selectedQuota == quota {
            return latestState.report
        }
        return nil
    }

    private func selectedLimit(from limits: [LiveRateLimit], quota: QuotaViewOption) -> LiveRateLimit? {
        if let exact = limits.first(where: { $0.id == quota.liveLimitID }) {
            return exact
        }
        if quota == .spark {
            return limits.first { $0.id != QuotaViewOption.all.liveLimitID }
        }
        return nil
    }

    private func openSessionsFolder() {
        NSWorkspace.shared.open(AppSettings.logFolderOpenURL)
    }

    private func openCodexStatusPage() {
        guard let url = URL(string: "https://status.openai.com") else { return }
        NSWorkspace.shared.open(url)
    }

    private func chooseLogFolder() {
        let panel = NSOpenPanel()
        panel.title = t(.logFolder)
        panel.message = t(.logFolderHint)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = AppSettings.logFolderURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        AppSettings.logFolderURL = url
        reloadScannerFromSettings()
    }

    private func resetLogFolder() {
        AppSettings.resetLogFolder()
        reloadScannerFromSettings()
    }

    private func changePlanCost(_ value: Double) {
        AppSettings.monthlyPlanCost = value
        detailsController.detailsView.needsDisplay = true
        detailsController.detailsView.needsLayout = true
        dashboardController.dashboardView.update(latestState)
    }

    private func changePaymentStartDay(_ value: String) {
        AppSettings.paymentStartDay = value
        detailsController.detailsView.needsDisplay = true
        detailsController.detailsView.needsLayout = true
    }

    private func changePaymentCurrency(_ currency: CurrencyCode) {
        let oldCurrency = AppSettings.paymentCurrency
        guard oldCurrency != currency else { return }
        AppSettings.monthlyPlanCost = convertCurrency(AppSettings.monthlyPlanCost, from: oldCurrency, to: currency)
        AppSettings.paymentCurrency = currency
        if UserDefaults.standard.string(forKey: AppSettings.displayCurrencyKey) == nil {
            AppSettings.displayCurrency = currency
        }
        detailsController.detailsView.needsDisplay = true
        detailsController.detailsView.needsLayout = true
        dashboardController.dashboardView.update(latestState)
    }

    private func changeDisplayCurrency(_ currency: CurrencyCode) {
        AppSettings.displayCurrency = currency
        detailsController.detailsView.needsDisplay = true
        detailsController.detailsView.needsLayout = true
        dashboardController.dashboardView.update(latestState)
    }

    private func changeNumberUnitStyle(_ style: NumberUnitStyle) {
        NumberUnitStyle.current = style
        detailsController.detailsView.needsDisplay = true
        dashboardController.dashboardView.update(latestState)
        updateStatusTitle(report: latestState.report, limits: liveLimits, quota: selectedQuota)
    }

    private func changeQuotaDisplayStyle(_ style: QuotaDisplayStyle) {
        QuotaDisplayStyle.current = style
        detailsController.detailsView.needsDisplay = true
        dashboardController.dashboardView.needsLayout = true
        dashboardController.dashboardView.update(latestState)
    }

    private func changeShowHistoricalEmptyWeeks(_ value: Bool) {
        AppSettings.showHistoricalEmptyWeeks = value
        detailsController.detailsView.needsDisplay = true
        detailsController.detailsView.needsLayout = true
    }

    private func changeLaunchAtLogin(_ value: Bool) {
        _ = LoginItemManager.setEnabled(value)
        detailsController.detailsView.needsDisplay = true
        detailsController.detailsView.needsLayout = true
    }

    private func changeShowCodexStatus(_ value: Bool) {
        AppSettings.showCodexStatusEnabled = value
        detailsController.detailsView.needsDisplay = true
        detailsController.detailsView.needsLayout = true
        dashboardController.dashboardView.needsLayout = true
        dashboardController.dashboardView.update(latestState)
    }

    private func changeQuotaWarnings(_ value: Bool) {
        AppSettings.quotaWarningsEnabled = value
        if value {
            QuotaWarningManager.shared.requestAuthorization()
            QuotaWarningManager.shared.evaluate(limits: liveLimits)
        }
        detailsController.detailsView.needsDisplay = true
        detailsController.detailsView.needsLayout = true
    }

    private func changeProfileAPITotals(_ value: Bool) {
        AppSettings.profileAPITotalsEnabled = value
        if !value {
            accountUsage = nil
            latestState.accountUsage = nil
            latestState.profileReport = nil
            if var snapshot = detailsController.detailsView.snapshot {
                snapshot.accountUsage = nil
                detailsController.detailsView.snapshot = snapshot
            }
        }
        detailsController.detailsView.needsDisplay = true
        detailsController.detailsView.needsLayout = true
        dashboardController.dashboardView.update(latestState)
        updateStatusTitle(report: latestState.report, limits: liveLimits, quota: selectedQuota)
        refresh(forceLive: false)
        if detailsController.window?.isVisible == true {
            openDetailsWindow()
        }
    }

    private func reloadScannerFromSettings() {
        scanner = CodexTokenScanner(rootURLs: AppSettings.logFolderURLs)
        reportCache.removeAll()
        activeScans.removeAll()
        detailsController.detailsView.needsDisplay = true
        refresh(forceLive: false)
    }

    private func openUsageDetailsWindow() {
        detailsController.detailsView.showUsagePage()
        openDetailsWindow()
    }

    private func openSettingsWindow() {
        detailsController.detailsView.showSettingsPage()
        openDetailsWindow()
    }

    private func openDetailsWindow() {
        detailsController.showLoading()
        if liveLimits.isEmpty {
            refreshLiveLimits()
        }
        let limits = liveLimits
        let currentServiceStatus = serviceStatus
        let currentAccountUsage = accountUsage
        scanQueue.async {
            let all = self.scanner.scan(days: 365)
            let spark = self.scanner.scan(days: 365, includedModelName: QuotaViewOption.spark.includedModelName)
            let other = self.scanner.scan(days: 365, excludedModelName: QuotaViewOption.other.excludedModelName)
            let costReferenceReport = self.liveCostReferenceReport(limits: limits)
            let accountUsage = self.readAccountUsageIfNeeded(fallback: currentAccountUsage)
            let snapshot = DetailsSnapshot(all: all, spark: spark, other: other, liveLimits: limits, serviceStatus: currentServiceStatus, costReferenceReport: costReferenceReport, accountUsage: accountUsage)
            DispatchQueue.main.async {
                if let accountUsage {
                    self.accountUsage = accountUsage
                    self.latestState.accountUsage = accountUsage
                    self.latestState.profileReport = self.profileReport(window: self.latestState.selectedWindow, quota: self.latestState.selectedQuota, accountUsage: accountUsage, localReport: self.latestState.report)
                    self.dashboardController.dashboardView.update(self.latestState)
                    self.updateStatusTitle(report: self.latestState.report, limits: self.liveLimits, quota: self.selectedQuota)
                } else if !AppSettings.profileAPITotalsEnabled {
                    self.accountUsage = nil
                    self.latestState.accountUsage = nil
                    self.latestState.profileReport = nil
                }
                self.detailsController.update(snapshot: snapshot)
            }
        }
    }

    private func summaryText(state: DashboardState) -> String {
        let report = state.report
        var lines = [
            "Codex Token Meter - \(state.selectedWindow.title)",
            "Scanned: \(localFormatter.string(from: report.scannedAt)) Asia/Shanghai",
            "Next refresh: \(localFormatter.string(from: state.nextRefreshAt)) Asia/Shanghai",
            "Sessions: \(report.sessions)",
            "Turns: \(report.turns)",
            "Total: \(report.usage.total)",
            "Input: \(report.usage.input)",
            "Cached input: \(report.usage.cachedInput)",
            "Fresh input: \(report.usage.freshInput)",
            "Output: \(report.usage.output)",
            "Reasoning output: \(report.usage.reasoningOutput)",
            String(format: "Cache percent: %.1f%%", report.usage.cachePercent)
        ]
        for limit in state.liveLimits {
            lines.append("\(limit.name): 5h \(limit.primary.usedPercent)% used, weekly \(limit.secondary.usedPercent)% used")
        }
        if let limit = selectedLimit(from: state.liveLimits, quota: state.selectedQuota),
           let estimate = planCostEstimate(report: report, selectedDay: nil, limit: limit) {
            lines.append("Payment currency: \(AppSettings.paymentCurrency.rawValue)")
            lines.append("Display currency: \(AppSettings.displayCurrency.rawValue)")
            lines.append("Plan cost: \(paymentMoney(estimate.monthlyCost))/month")
            lines.append("Today value: \(displayMoney(estimate.todayValue))")
            lines.append("Weekly used value: \(displayMoney(estimate.weeklyUsedValue))")
            lines.append("Weekly unused value: \(displayMoney(estimate.weeklyUnusedValue))")
        }
        lines.append("By day:")
        for day in report.byDay {
            lines.append("\(day.day)\t\(day.usage.total)\t\(day.usage.input)\t\(day.usage.cachedInput)\t\(day.usage.output)\tturns=\(day.turns)")
        }
        return lines.joined(separator: "\n")
    }
}

private func format(_ value: Int64) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
}

private func compact(_ value: Int64) -> String {
    let double = Double(value)
    switch NumberUnitStyle.effective {
    case .english:
        if value >= 1_000_000_000 { return String(format: "%.2fB", double / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.1fM", double / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", double / 1_000) }
    case .chinese:
        if value >= 100_000_000 { return String(format: "%.2f亿", double / 100_000_000) }
        if value >= 10_000 { return String(format: "%.1f万", double / 10_000) }
        if value >= 1_000 { return format(value) }
    }
    return "\(value)"
}

private func compactDashboardTotal(_ value: Int64) -> String {
    let double = Double(value)
    switch NumberUnitStyle.effective {
    case .english:
        if value >= 1_000_000_000 { return String(format: "%.2fB", double / 1_000_000_000) }
        if value >= 10_000_000 { return String(format: "%.0fM", double / 1_000_000) }
        if value >= 1_000_000 { return String(format: "%.1fM", double / 1_000_000) }
        if value >= 10_000 { return String(format: "%.0fK", double / 1_000) }
        if value >= 1_000 { return String(format: "%.1fK", double / 1_000) }
    case .chinese:
        if value >= 100_000_000 { return String(format: "%.2f亿", double / 100_000_000) }
        if value >= 10_000 { return String(format: "%.0f万", double / 10_000) }
        if value >= 1_000 { return format(value) }
    }
    return "\(value)"
}

private func compactDashboardMetric(_ value: Int64) -> String {
    let double = Double(value)
    switch NumberUnitStyle.effective {
    case .english:
        if value >= 1_000_000_000 { return String(format: "%.1fB", double / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.0fM", double / 1_000_000) }
        if value >= 1_000 { return String(format: "%.0fK", double / 1_000) }
    case .chinese:
        if value >= 100_000_000 { return String(format: "%.1f亿", double / 100_000_000) }
        if value >= 10_000 { return String(format: "%.0f万", double / 10_000) }
        if value >= 1_000 { return format(value) }
    }
    return "\(value)"
}

private func money(_ value: Double, currency: CurrencyCode) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = value >= 100 ? 0 : min(currency.fractionDigits, 2)
    formatter.maximumFractionDigits = value >= 100 ? 0 : currency.fractionDigits
    let formatted = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    return "\(currency.rawValue) \(formatted)"
}

private func compactMoney(_ value: Double, currency: CurrencyCode) -> String {
    let absValue = abs(value)
    let amount: String
    switch NumberUnitStyle.effective {
    case .english:
        if absValue >= 1_000_000_000 {
            amount = String(format: "%.2fB", value / 1_000_000_000)
        } else if absValue >= 1_000_000 {
            amount = String(format: "%.1fM", value / 1_000_000)
        } else if absValue >= 1_000 {
            amount = String(format: "%.1fK", value / 1_000)
        } else if absValue >= 100 {
            amount = String(format: "%.0f", value)
        } else {
            amount = String(format: "%.2f", value)
        }
    case .chinese:
        if absValue >= 100_000_000 {
            amount = String(format: "%.2f亿", value / 100_000_000)
        } else if absValue >= 10_000 {
            amount = String(format: "%.1f万", value / 10_000)
        } else if absValue >= 1_000 {
            amount = String(format: "%.0f", value)
        } else {
            amount = String(format: "%.2f", value)
        }
    }
    return "\(amount) \(currency.rawValue)"
}

private func paymentMoney(_ value: Double) -> String {
    money(value, currency: AppSettings.paymentCurrency)
}

private func paymentAmount(_ value: Double) -> String {
    let currency = AppSettings.paymentCurrency
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.groupingSeparator = ","
    formatter.usesGroupingSeparator = true
    formatter.minimumFractionDigits = value >= 100 ? 0 : min(currency.fractionDigits, 2)
    formatter.maximumFractionDigits = value >= 100 ? 0 : currency.fractionDigits
    return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
}

private func displayMoney(_ paymentValue: Double) -> String {
    let converted = convertCurrency(paymentValue, from: AppSettings.paymentCurrency, to: AppSettings.displayCurrency)
    return money(converted, currency: AppSettings.displayCurrency)
}

private func displayAPIMoney(_ usdValue: Double) -> String {
    let converted = convertCurrency(usdValue, from: .usd, to: AppSettings.displayCurrency)
    return money(converted, currency: AppSettings.displayCurrency)
}

private func compactDisplayAPIMoney(_ usdValue: Double) -> String {
    let converted = convertCurrency(usdValue, from: .usd, to: AppSettings.displayCurrency)
    return compactMoney(converted, currency: AppSettings.displayCurrency)
}

private func todayKey() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date())
}

private func appCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.firstWeekday = 2
    return calendar
}

private func dayFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}

private func shortMonthDayFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    formatter.dateFormat = "MM-dd"
    return formatter
}

private func shortMonthDayTimeFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    formatter.dateFormat = "MM-dd HH:mm"
    return formatter
}

private func cycleRangeTitle(start: Date?, end: Date?, fallback: String, formatter: DateFormatter) -> String {
    switch (start, end) {
    case let (start?, end?):
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    case let (start?, nil):
        return "\(formatter.string(from: start)) - \(t(.now))"
    case let (nil, end?):
        return "\(t(.before)) \(formatter.string(from: end))"
    default:
        return fallback
    }
}

private func isShortCostCycle(start: Date, end: Date) -> Bool {
    let duration = end.timeIntervalSince(start)
    let fullWeek: TimeInterval = 7 * 24 * 60 * 60
    return duration > 0 && duration < fullWeek - 60
}

private func effectivePaymentStartDay(in report: TokenReport?) -> String {
    let parser = dayFormatter()
    if let stored = AppSettings.paymentStartDay,
       parser.date(from: stored) != nil {
        return stored
    }
    return report?.byDay.map(\.day).sorted().first ?? todayKey()
}

private func availableCostYears(from report: TokenReport?) -> [Int] {
    let currentYear = Calendar.current.component(.year, from: Date())
    let startDay = effectivePaymentStartDay(in: report)
    let startYear = Int(startDay.prefix(4)) ?? currentYear
    let yearsWithUsage = report?.byDay.compactMap { day -> Int? in
        guard day.day >= startDay,
              day.usage.total > 0 else {
            return nil
        }
        return Int(day.day.prefix(4))
    } ?? []
    let distinctYears = Array(Set(yearsWithUsage)).sorted()
    if !distinctYears.isEmpty {
        return distinctYears
    }
    return [max(startYear, currentYear)]
}

private func weekStarts(for year: Int) -> [Date] {
    let calendar = appCalendar()
    guard let firstWeek = calendar.date(from: DateComponents(weekday: calendar.firstWeekday, weekOfYear: 1, yearForWeekOfYear: year)) else {
        return []
    }
    var starts: [Date] = []
    var current = firstWeek
    while calendar.component(.yearForWeekOfYear, from: current) == year {
        starts.append(current)
        guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: current) else { break }
        current = next
    }
    return starts
}

private func weeklyAPICostBuckets(days: [DayUsage], startDay: String) -> [Date: APICostEstimate] {
    let calendar = appCalendar()
    let parser = dayFormatter()
    var buckets: [Date: APICostEstimate] = [:]
    for day in days where day.day >= startDay && day.usage.total > 0 {
        guard let date = parser.date(from: day.day),
              let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start else {
            continue
        }
        var estimate = buckets[weekStart] ?? APICostEstimate()
        estimate.add(APICostEstimator.estimate(day: day))
        buckets[weekStart] = estimate
    }
    return buckets
}

private func proportionalAPICostUSD(estimate: APICostEstimate, usedValue: Double, totalUsedValue: Double) -> Double? {
    guard estimate.hasPricedUsage else { return nil }
    guard totalUsedValue > 0 else { return estimate.usdValue }
    return estimate.usdValue * max(0, usedValue) / totalUsedValue
}

private func weeklySpendRows(report: TokenReport, limit: LiveRateLimit?, year: Int? = nil, quotaReferenceReport: TokenReport? = nil) -> [CostPeriodRow] {
    guard let estimator = CostEstimator(report: report, limit: limit, quotaReferenceReport: quotaReferenceReport),
          estimator.weeklyBudget > 0 else {
        return []
    }
    let calendar = appCalendar()
    let parser = dayFormatter()
    let labelFormatter = shortMonthDayFormatter()
    let titleFormatter = dayFormatter()
    let eventFormatter = shortMonthDayTimeFormatter()
    let eventParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    let startDate = parser.date(from: estimator.startDay) ?? calendar.startOfDay(for: Date())
    let startWeek = calendar.dateInterval(of: .weekOfYear, for: startDate)?.start ?? startDate
    let startWeekYear = calendar.component(.yearForWeekOfYear, from: startDate)
    let buckets = estimator.weeklyBuckets
    let apiBuckets = weeklyAPICostBuckets(days: report.byDay, startDay: estimator.startDay)
    let starts: [Date]
    if let year {
        guard year >= startWeekYear else { return [] }
        let allStarts = Array(weekStarts(for: year).prefix(52))
        if year == startWeekYear {
            starts = allStarts.filter { $0 >= startWeek }
        } else {
            starts = allStarts
        }
    } else {
        starts = Array(buckets.keys.sorted().reversed().prefix(8).reversed())
    }
    let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? calendar.startOfDay(for: Date())
    let rows = starts.flatMap { start -> [CostPeriodRow] in
        let total = buckets[start] ?? 0
        let apiEstimate = apiBuckets[start] ?? APICostEstimate()
        let usedValue = estimator.weeklyUsedValue(forWeekStart: start, total: total)
        let remainingValue = estimator.weeklyUnusedValue(forWeekStart: start, total: total)
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let exclusiveWeekEnd = calendar.date(byAdding: .day, value: 7, to: start) ?? end
        let weekNumber = calendar.component(.weekOfYear, from: start)
        let label = labelFormatter.string(from: start)
        let fullWeekTitle = "\(titleFormatter.string(from: start)) - \(titleFormatter.string(from: end))"
        let subtitle = "\(t(.week)) \(weekNumber)"
        let isFuture = start > currentWeekStart
        let title = start == currentWeekStart
            ? cycleRangeTitle(start: start, end: nil, fallback: fullWeekTitle, formatter: titleFormatter)
            : fullWeekTitle
        let resetEvents = estimator.limitID.map {
            CostHistoryStore.shared.resetEvents(limitID: $0, weekStart: start)
        } ?? []
        let resetDates = resetEvents.compactMap { eventParser.date(from: $0.observedAt) }
        guard !isFuture, !resetEvents.isEmpty else {
            return [CostPeriodRow(
                label: label,
                title: title,
                subtitle: subtitle,
                usedValue: usedValue,
                remainingValue: remainingValue,
                budgetValue: estimator.weeklyBudget,
                apiEquivalentUSD: apiEstimate.hasPricedUsage ? apiEstimate.usdValue : nil,
                apiEquivalentCoveragePercent: apiEstimate.coveragePercent,
                hasData: total > 0 || (start == currentWeekStart && usedValue > 0),
                isFuture: isFuture,
                isShortCycle: false,
                cycleIndex: 0
            )]
        }

        let currentCycleValue = start == currentWeekStart
            ? estimator.weeklyBudget * min(100, max(0, limit?.secondary.usedPercent ?? 0)) / 100
            : 0
        let eventPercents: [Double]
        if !resetEvents.isEmpty {
            eventPercents = resetEvents.map { min(100, max(0, $0.previousUsedPercent)) }
        } else {
            eventPercents = []
        }
        let observedEventValue = eventPercents.reduce(0.0) { partial, percent in
            partial + estimator.weeklyBudget * percent / 100
        }
        let cycleAwareUsedValue = max(usedValue, min(estimator.weeklyBudget * Double(max(eventPercents.count, 1)), observedEventValue) + currentCycleValue)
        let baseUsedValue = min(estimator.weeklyBudget, max(0, eventPercents.first ?? 0) * estimator.weeklyBudget / 100)
        var remainingCycleValue = max(0, cycleAwareUsedValue - baseUsedValue)

        var periodRows: [CostPeriodRow] = [
            CostPeriodRow(
                label: label,
                title: cycleRangeTitle(start: start, end: resetDates.first, fallback: title, formatter: eventFormatter),
                subtitle: subtitle,
                usedValue: baseUsedValue,
                remainingValue: max(0, estimator.weeklyBudget - baseUsedValue),
                budgetValue: estimator.weeklyBudget,
                apiEquivalentUSD: proportionalAPICostUSD(estimate: apiEstimate, usedValue: baseUsedValue, totalUsedValue: cycleAwareUsedValue),
                apiEquivalentCoveragePercent: apiEstimate.coveragePercent,
                hasData: total > 0 || baseUsedValue > 0,
                isFuture: false,
                isShortCycle: isShortCostCycle(start: start, end: resetDates.first ?? exclusiveWeekEnd),
                cycleIndex: 0
            )
        ]

        let extraPercents = Array(eventPercents.dropFirst())
        let extraCycleCount = resetEvents.count
        for cycleIndex in 1...extraCycleCount {
            let resetEvent = resetEvents.indices.contains(cycleIndex - 1) ? resetEvents[cycleIndex - 1] : nil
            let cycleStart = resetDates.indices.contains(cycleIndex - 1) ? resetDates[cycleIndex - 1] : nil
            let cycleEnd = resetDates.indices.contains(cycleIndex) ? resetDates[cycleIndex] : nil
            let isActiveCurrentCycle = start == currentWeekStart && cycleEnd == nil
            let effectiveCycleEnd = cycleEnd ?? (start == currentWeekStart ? Date() : exclusiveWeekEnd)
            let displayedCycleEnd = isActiveCurrentCycle ? nil : effectiveCycleEnd
            let refreshTime = resetEvent
                .flatMap { eventParser.date(from: $0.observedAt) }
                .map { eventFormatter.string(from: $0) }
            let eventValue = extraPercents.indices.contains(cycleIndex - 1)
                ? estimator.weeklyBudget * extraPercents[cycleIndex - 1] / 100
                : remainingCycleValue
            let cycleUsedValue = min(estimator.weeklyBudget, max(0, eventValue))
            remainingCycleValue = max(0, remainingCycleValue - cycleUsedValue)
            periodRows.append(CostPeriodRow(
                label: label,
                title: cycleRangeTitle(start: cycleStart, end: displayedCycleEnd, fallback: title, formatter: eventFormatter),
                subtitle: [subtitle, refreshTime, t(.manualRefreshCycle)].compactMap { $0 }.joined(separator: " · "),
                usedValue: cycleUsedValue,
                remainingValue: max(0, estimator.weeklyBudget - cycleUsedValue),
                budgetValue: estimator.weeklyBudget,
                apiEquivalentUSD: proportionalAPICostUSD(estimate: apiEstimate, usedValue: cycleUsedValue, totalUsedValue: cycleAwareUsedValue),
                apiEquivalentCoveragePercent: apiEstimate.coveragePercent,
                hasData: true,
                isFuture: false,
                isShortCycle: !isActiveCurrentCycle && (cycleStart.map { isShortCostCycle(start: $0, end: effectiveCycleEnd) } ?? false),
                cycleIndex: cycleIndex
            ))
        }
        return periodRows
    }
    guard !AppSettings.showHistoricalEmptyWeeks else { return rows }
    return rows.filter { $0.hasData || $0.isFuture }
}

private func monthlyCostRows(report: TokenReport, limit: LiveRateLimit?, year: Int? = nil, quotaReferenceReport: TokenReport? = nil) -> [CostPeriodRow] {
    guard let estimator = CostEstimator(report: report, limit: limit, quotaReferenceReport: quotaReferenceReport),
          estimator.weeklyBudget > 0 else {
        return []
    }
    let byMonth = estimator.monthlyUsedValues()
    let months: [String]
    if let year {
        months = (1...12).map { String(format: "%04d-%02d", year, $0) }
    } else {
        months = Array(byMonth.keys.sorted().reversed().prefix(6).reversed())
    }
    let currentMonth = String(dayFormatter().string(from: Date()).prefix(7))
    return months.map { month in
        let usedValue = byMonth[month] ?? 0
        let remainingValue = max(0, estimator.monthlyCost - usedValue)
        return CostPeriodRow(
            label: String(month.suffix(2)),
            title: month,
            subtitle: t(.month),
            usedValue: usedValue,
            remainingValue: remainingValue,
            budgetValue: max(estimator.monthlyCost, usedValue),
            apiEquivalentUSD: nil,
            apiEquivalentCoveragePercent: 0,
            hasData: usedValue > 0,
            isFuture: month > currentMonth,
            isShortCycle: false,
            cycleIndex: 0
        )
    }
}

private func monthlySpendRows(report: TokenReport, limit: LiveRateLimit?, year: Int? = nil, quotaReferenceReport: TokenReport? = nil) -> [MonthlySpendRow] {
    guard let estimator = CostEstimator(report: report, limit: limit, quotaReferenceReport: quotaReferenceReport),
          estimator.weeklyBudget > 0 else {
        return []
    }
    let byMonth = estimator.monthlyUsedValues()
    let months = byMonth.keys
        .filter { month in
            guard let year else { return true }
            return month.hasPrefix(String(format: "%04d-", year))
        }
        .sorted()
        .reversed()
        .prefix(12)
    return months.map { month in
        let usedValue = byMonth[month] ?? 0
        let planPercent = estimator.monthlyCost > 0 ? usedValue / estimator.monthlyCost * 100 : 0
        return MonthlySpendRow(month: month, usedValue: usedValue, usedPercentOfPlan: planPercent)
    }
}

private func planCostEstimate(report: TokenReport, selectedDay: DayUsage?, limit: LiveRateLimit?, quotaReferenceReport: TokenReport? = nil) -> PlanCostEstimate? {
    guard let estimator = CostEstimator(report: report, limit: limit, quotaReferenceReport: quotaReferenceReport) else { return nil }

    let today = report.byDay.first { $0.day == todayKey() } ?? report.byDay.suffix(7).last
    let selected = selectedDay ?? today
    let parser = dayFormatter()
    let calendar = appCalendar()
    let startDate = parser.date(from: estimator.startDay) ?? calendar.startOfDay(for: Date())
    let todayDate = parser.date(from: todayKey()) ?? calendar.startOfDay(for: Date())
    let paidDays = max(1, (calendar.dateComponents([.day], from: startDate, to: todayDate).day ?? 0) + 1)
    let totalSpentValue = estimator.totalSpentValue()
    let accruedBudget = Double(paidDays) * (estimator.weeklyBudget / 7)
    let totalWastedValue = max(0, accruedBudget - totalSpentValue)

    return PlanCostEstimate(
        monthlyCost: estimator.monthlyCost,
        weeklyBudget: estimator.weeklyBudget,
        weeklyQuotaTotal: estimator.weeklyReferenceTotal,
        todayValue: today.map { estimator.value(forDay: $0) } ?? 0,
        selectedDayValue: selected.map { estimator.value(forDay: $0) } ?? 0,
        weeklyUsedValue: estimator.weeklyUsedValue(),
        weeklyUnusedValue: estimator.weeklyUnusedValue(),
        totalSpentValue: totalSpentValue,
        totalWastedValue: totalWastedValue,
        selectedDayQuotaPercent: selected.map { estimator.quotaPercent(for: $0.usage) } ?? 0
    )
}

private func relative(_ date: Date?) -> String {
    guard let date else { return "--" }
    return relative(date)
}

private func compactResetRelative(_ date: Date?) -> String {
    guard let date else { return "--" }
    return compactResetRelative(date)
}

private func compactResetRelative(_ date: Date) -> String {
    let seconds = Int(date.timeIntervalSinceNow)
    let absSeconds = abs(seconds)
    let suffix = seconds >= 0 ? "" : " ago"
    if absSeconds < 60 { return "0m\(suffix)" }
    let totalMinutes = absSeconds / 60
    let days = totalMinutes / (24 * 60)
    let hours = (totalMinutes % (24 * 60)) / 60
    let minutes = totalMinutes % 60

    if days > 0 {
        return hours > 0 ? "\(days)d\(hours)h\(suffix)" : "\(days)d\(suffix)"
    }
    if hours > 0 { return "\(hours)h\(suffix)" }
    return "\(minutes)m\(suffix)"
}

private func relative(_ date: Date) -> String {
    let seconds = Int(date.timeIntervalSinceNow)
    let absSeconds = abs(seconds)
    let suffix = seconds >= 0 ? "" : " ago"
    if absSeconds < 60 { return "0m\(suffix)" }
    let totalMinutes = absSeconds / 60
    let days = totalMinutes / (24 * 60)
    let hours = (totalMinutes % (24 * 60)) / 60
    let minutes = totalMinutes % 60

    if days > 0 { return "\(days)d\(hours)h\(minutes)m\(suffix)" }
    if hours > 0 { return "\(hours)h\(minutes)m\(suffix)" }
    return "\(minutes)m\(suffix)"
}

private func requestedWindow(from arguments: [String]) -> WindowOption? {
    arguments.compactMap { argument -> WindowOption? in
        guard argument.hasPrefix("--window=") else { return nil }
        switch argument.dropFirst("--window=".count) {
        case "24h", "day": return .day
        case "7d", "week": return .week
        case "30d", "month": return .month
        default: return nil
        }
    }.first
}

private func requestedQuota(from arguments: [String]) -> QuotaViewOption? {
    arguments.compactMap { argument -> QuotaViewOption? in
        guard argument.hasPrefix("--quota=") else { return nil }
        return QuotaViewOption(rawValue: String(argument.dropFirst("--quota=".count)))
    }.first
}

private func requestedHours(from arguments: [String], defaultValue: Int = WindowOption.week.rawValue) -> Int {
    arguments.compactMap { argument -> Int? in
        guard argument.hasPrefix("--hours=") else { return nil }
        return Int(argument.dropFirst("--hours=".count))
    }.first ?? defaultValue
}

private func writePNG(of view: NSView, to url: URL) throws {
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        throw NSError(domain: "CodexTokenMeter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create bitmap"])
    }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "CodexTokenMeter", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
    }
    try data.write(to: url, options: [.atomic])
}

private func renderDashboardSnapshot(arguments: [String]) throws -> URL {
    let scanner = CodexTokenScanner(rootURLs: AppSettings.logFolderURLs)
    let window = requestedWindow(from: arguments) ?? .week
    let quota = requestedQuota(from: arguments) ?? .other
    let report = scanner.scan(window: window, includedModelName: quota.includedModelName, excludedModelName: quota.excludedModelName)
    let liveLimits = LiveRateLimitReader().read()
    let serviceStatus = CodexServiceStatusReader().read()
    let accountUsage = AppSettings.profileAPITotalsEnabled ? AccountUsageReader().read() : nil
    let profileReport: TokenReport?
    if quota == .all, let accountUsage, accountUsage.hasData {
        profileReport = profileReportWithLocalFallback(accountUsage.report(window: window), localReport: report)
    } else {
        profileReport = nil
    }

    let outputURL = arguments
        .compactMap { argument -> URL? in
            guard argument.hasPrefix("--render-dashboard=") else { return nil }
            return URL(fileURLWithPath: String(argument.dropFirst("--render-dashboard=".count)))
        }
        .first ?? URL(fileURLWithPath: "/tmp/codex-token-meter-dashboard.png")

    let state = DashboardState(
        report: report,
        profileReport: profileReport,
        accountUsage: accountUsage,
        costReferenceReport: nil,
        liveLimits: liveLimits,
        serviceStatus: serviceStatus,
        selectedWindow: window,
        selectedQuota: quota,
        nextRefreshAt: Date().addingTimeInterval(300),
        isLoading: false,
        error: nil
    )

    let view = DashboardView(frame: NSRect(origin: .zero, size: DashboardView.idealSize))
    view.update(state)
    view.layoutSubtreeIfNeeded()
    try writePNG(of: view, to: outputURL)
    return outputURL
}

if CommandLine.arguments.contains("--print-profile") {
    let snapshot = AccountUsageReader().read()
    let payload: [String: Any] = [
        "profile_api_totals_enabled": AppSettings.profileAPITotalsEnabled,
        "present": snapshot != nil,
        "has_data": snapshot?.hasData ?? false,
        "lifetime_tokens": snapshot?.summary.lifetimeTokens ?? 0,
        "peak_daily_tokens": snapshot?.summary.peakDailyTokens ?? 0,
        "longest_running_turn_sec": snapshot?.summary.longestRunningTurnSec ?? 0,
        "current_streak_days": snapshot?.summary.currentStreakDays ?? 0,
        "longest_streak_days": snapshot?.summary.longestStreakDays ?? 0,
        "daily_bucket_count": snapshot?.dailyUsageBuckets.count ?? 0,
        "profile_day_total": snapshot?.report(window: .day).usage.total ?? 0,
        "profile_week_total": snapshot?.report(window: .week).usage.total ?? 0,
        "profile_month_total": snapshot?.report(window: .month).usage.total ?? 0,
        "last_daily_bucket": snapshot?.dailyUsageBuckets.last.map { ["start_date": $0.startDate, "tokens": $0.tokens] } ?? [:]
    ]
    if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
       let text = String(data: data, encoding: .utf8) {
        print(text)
    }
    exit(0)
}

if CommandLine.arguments.contains("--print-live") {
    let limits = LiveRateLimitReader().read()
    AppSettings.learnModelLimit(from: limits)
    CostHistoryStore.shared.record(limits: limits)
    let payload = limits.map { limit in
        [
            "id": limit.id,
            "name": limit.name,
            "primary_percent": limit.primary.usedPercent,
            "primary_remaining_percent": limit.primary.remainingPercent,
            "weekly_percent": limit.secondary.usedPercent,
            "weekly_remaining_percent": limit.secondary.remainingPercent,
            "primary_resets_at": limit.primary.resetsAt?.description ?? "",
            "weekly_resets_at": limit.secondary.resetsAt?.description ?? ""
        ] as [String: Any]
    }
    if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
       let text = String(data: data, encoding: .utf8) {
        print(text)
    }
    exit(0)
}

if CommandLine.arguments.contains("--print-service-status") {
    let snapshot = CodexServiceStatusReader().read()
    let payload: [String: Any] = [
        "present": snapshot != nil,
        "updated_at": snapshot?.statusPageUpdatedAt?.description ?? "",
        "read_at": snapshot?.readAt.description ?? "",
        "overall_status": snapshot?.overallStatus ?? "",
        "degraded_component_count": snapshot?.degradedComponents.count ?? 0,
        "component_count": snapshot?.components.count ?? 0,
        "components": snapshot?.components.map { ["name": $0.name, "status": $0.status] } ?? [],
        "active_incident": snapshot?.activeIncident.map { incident in
            [
                "name": incident.name,
                "status": incident.status,
                "message": incident.message,
                "created_at": incident.createdAt?.description ?? "",
                "updated_at": incident.updatedAt?.description ?? ""
            ] as [String: Any]
        } ?? [:]
    ]
    if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
       let text = String(data: data, encoding: .utf8) {
        print(text)
    }
    exit(0)
}

if CommandLine.arguments.contains("--print") {
    let scanner = CodexTokenScanner(rootURLs: AppSettings.logFolderURLs)
    let requestedWindow = requestedWindow(from: CommandLine.arguments)
    let hours = requestedHours(from: CommandLine.arguments)
    let quota = requestedQuota(from: CommandLine.arguments)
    let report = requestedWindow.map { scanner.scan(window: $0, includedModelName: quota?.includedModelName, excludedModelName: quota?.excludedModelName) }
        ?? scanner.scan(hours: hours, includedModelName: quota?.includedModelName, excludedModelName: quota?.excludedModelName)
    let apiEstimate = APICostEstimator.estimate(report: report)
    let externalAPI = ExternalAPICostStore.read()
    let externalAPIPayload: [String: Any] = [
        "configured_path": AppSettings.externalAPICostURL.path,
        "present": externalAPI != nil,
        "has_data": externalAPI?.hasData ?? false,
        "usd_value": externalAPI?.usdValue ?? 0,
        "total_tokens": externalAPI?.totalTokens ?? 0,
        "updated_at": externalAPI?.updatedAt ?? ""
    ]
    let payload: [String: Any] = [
        "hours": requestedWindow?.rawValue ?? hours,
        "window": requestedWindow?.shortTitle ?? "rolling",
        "quota": quota?.rawValue ?? "all",
        "model_limit_id": AppSettings.modelLimitID,
        "model_limit_name": AppSettings.modelLimitName,
        "log_roots": scanner.rootPaths,
        "sessions": report.sessions,
        "events": report.events,
        "turns": report.turns,
        "input": report.usage.input,
        "cached_input": report.usage.cachedInput,
        "fresh_input": report.usage.freshInput,
        "output": report.usage.output,
        "reasoning_output": report.usage.reasoningOutput,
        "total": report.usage.total,
        "cache_percent": report.usage.cachePercent,
        "api_equivalent_usd": apiEstimate.usdValue,
        "api_equivalent_priced_tokens": apiEstimate.pricedTokens,
        "api_equivalent_total_tokens": apiEstimate.totalTokens,
        "api_equivalent_coverage_percent": apiEstimate.coveragePercent,
        "external_api_cost": externalAPIPayload,
        "hour_buckets": report.byHour.count,
        "model_breakdown": report.modelBreakdown.map { model in
            let modelAPIEstimate = APICostEstimator.estimate(usage: model.usage, modelName: model.name)
            return [
                "name": model.name,
                "sessions": model.sessions,
                "events": model.events,
                "total": model.usage.total,
                "input": model.usage.input,
                "output": model.usage.output,
                "api_equivalent_usd": modelAPIEstimate.usdValue,
                "api_equivalent_priced_tokens": modelAPIEstimate.pricedTokens
            ] as [String: Any]
        },
        "by_day": report.byDay.map { day in
            let dayAPIEstimate = APICostEstimator.estimate(day: day)
            return [
                "day": day.day,
                "turns": day.turns,
                "input": day.usage.input,
                "cached_input": day.usage.cachedInput,
                "fresh_input": day.usage.freshInput,
                "output": day.usage.output,
                "reasoning_output": day.usage.reasoningOutput,
                "total": day.usage.total,
                "api_equivalent_usd": dayAPIEstimate.usdValue,
                "api_equivalent_coverage_percent": dayAPIEstimate.coveragePercent,
                "model_breakdown": day.modelBreakdown.map { model in
                    let modelAPIEstimate = APICostEstimator.estimate(usage: model.usage, modelName: model.name)
                    return [
                        "name": model.name,
                        "sessions": model.sessions,
                        "events": model.events,
                        "total": model.usage.total,
                        "input": model.usage.input,
                        "output": model.usage.output,
                        "api_equivalent_usd": modelAPIEstimate.usdValue
                    ] as [String: Any]
                }
            ] as [String: Any]
        }
    ]
    if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
       let text = String(data: data, encoding: .utf8) {
        print(text)
    }
    exit(0)
}

if CommandLine.arguments.contains("--render-dashboard") || CommandLine.arguments.contains(where: { $0.hasPrefix("--render-dashboard=") }) {
    do {
        let url = try renderDashboardSnapshot(arguments: CommandLine.arguments)
        print(url.path)
    } catch {
        fputs("Failed to render dashboard: \(error)\n", stderr)
        exit(1)
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
