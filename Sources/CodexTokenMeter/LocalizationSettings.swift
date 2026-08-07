import Cocoa
import Foundation
import ServiceManagement
import UserNotifications

// MARK: - Localization And Settings

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

enum AppLanguage: String, CaseIterable {
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

    var usesChineseInsightCopy: Bool {
        self == .chinese || self == .traditionalChinese
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

enum StatusDisplayOption: String, CaseIterable {
    case fiveHourPercent
    case weeklyPercent
    case quotaPercents
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
        case .quotaPercents: return t(.statusQuotaPercents)
        case .weeklyTokens: return t(.statusWeeklyTokens)
        case .dailyTokens: return t(.statusDailyTokens)
        }
    }

    var requiredReportWindow: WindowOption? {
        switch self {
        case .weeklyTokens: return .week
        case .dailyTokens: return .day
        case .fiveHourPercent, .weeklyPercent, .quotaPercents: return nil
        }
    }
}

enum StatusBarMetric: String, CaseIterable {
    case codexFiveHour
    case codexWeekly
    case claudeFiveHour
    case claudeWeekly
    case fableWeekly

    var title: String {
        switch self {
        case .codexFiveHour: return t(.statusCodexFiveHour)
        case .codexWeekly: return t(.statusCodexWeekly)
        case .claudeFiveHour: return t(.statusClaudeFiveHour)
        case .claudeWeekly: return t(.statusClaudeWeekly)
        case .fableWeekly: return t(.statusFableWeekly)
        }
    }

    var source: QuotaViewOption {
        switch self {
        case .codexFiveHour, .codexWeekly:
            return .codex
        case .claudeFiveHour, .claudeWeekly, .fableWeekly:
            return .claude
        }
    }

    var quotaMetric: HomeQuotaRingMetric {
        switch self {
        case .codexFiveHour, .claudeFiveHour:
            return .fiveHour
        case .codexWeekly, .claudeWeekly, .fableWeekly:
            return .weekly
        }
    }

    var liveLimitID: String {
        self == .fableWeekly ? claudeFableLiveLimitID : source.liveLimitID
    }

    static func metric(source: QuotaViewOption, quotaMetric: HomeQuotaRingMetric) -> StatusBarMetric {
        let normalizedSource: QuotaViewOption = source == .claude ? .claude : .codex
        switch (normalizedSource, quotaMetric) {
        case (.codex, .fiveHour): return .codexFiveHour
        case (.codex, .weekly): return .codexWeekly
        case (.claude, .fiveHour): return .claudeFiveHour
        case (.claude, .weekly): return .claudeWeekly
        case (.all, .fiveHour): return .codexFiveHour
        case (.all, .weekly): return .codexWeekly
        case (.api, .fiveHour): return .codexFiveHour
        case (.api, .weekly): return .codexWeekly
        }
    }
}

enum StatusBarMetricSlot: CaseIterable {
    case first
    case second

    var title: String {
        switch self {
        case .first: return t(.statusBarMetricOne)
        case .second: return t(.statusBarMetricTwo)
        }
    }
}

enum QuotaDisplayStyle: String, CaseIterable {
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

enum HomeQuotaRingMetric: String, CaseIterable {
    case fiveHour
    case weekly

    var title: String {
        switch self {
        case .fiveHour: return t(.fiveHourLeft)
        case .weekly: return t(.weeklyLeft)
        }
    }
}

enum ClaudeThirdRingMetric: String, CaseIterable {
    case cacheHit
    case fable = "fable5"

    var title: String {
        switch self {
        case .cacheHit: return t(.cacheHit)
        case .fable: return "Fable"
        }
    }
}

enum NumberUnitStyle: String, CaseIterable {
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

enum L10nKey {
    case about
    case aboutSubtitle
    case all
    case allDescription
    case apiDescription
    case apiEquivalent
    case apiEquivalentHint
    case before
    case budget
    case cache
    case cacheHit
    case cacheHitDescription
    case cached
    case claudeStatuslineRequired
    case staleData
    case staleDataFormat
    case calendar
    case calendarSubtitle
    case clickForDetails
    case claude
    case claudeCode
    case claudeDescription
    case claudeLogs
    case codex
    case codexAppTotal
    case codexDescription
    case combinedUsage
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
    case codexAPISources
    case codexAPISourcesHint
    case codexAPISourcesChoose
    case codexHomeRing
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
    case displayCurrencyHint
    case visibleUsageSources
    case visibleUsageSourcesHint
    case selectedDayQuotaShareHint
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
    case insights
    case insightsSubtitle
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
    case loadingAllUsage
    case loadingClaudeUsage
    case loadingCodexUsage
    case loadingFinalizing
    case loadingOtherUsage
    case loadingProfileTotals
    case loadingRepoInsights
    case loadingSparkUsage
    case loadingUsageDetails
    case loadingUsageDetailsHint
    case logs
    case manualRefreshCycle
    case modelLimit
    case modelGroupingNote
    case modelMissingNote
    case modelNoSearchResults
    case modelSearchPlaceholder
    case modelSortCost
    case modelSortName
    case modelSortTokens
    case modelTrustIdentificationFormat
    case modelTrustPricingFormat
    case modelTrustSourceFormat
    case modelVisibleCountFormat
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
    case claudeHomeRing
    case claudeThirdRing
    case claudeThirdRingHint
    case showCombinedFable
    case showCombinedFableHint
    case past24Hours
    case past30Days
    case past7Days
    case pastYear
    case peakDay
    case peakWeek
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
    case quotaHomeRingHint
    case quotaViews
    case quotaWarnings
    case quotaWarningsHint
    case recentRollouts
    case quit
    case refresh
    case refreshing
    case remaining
    case resetCredits
    case resetCreditCountFormat
    case resetCreditEstimated
    case resetCreditExpiresAt
    case resetCreditExpiryUnavailable
    case resetCreditGrantedAt
    case resetCreditNoCredits
    case showPastEmptyWeeks
    case reset
    case sessions
    case settings
    case settingsSubtitle
    case sourceHealth
    case sourceSplit
    case spark
    case sparkDescription
    case sparkModel
    case statusBarDisplay
    case statusBarMetricOne
    case statusBarMetricTwo
    case statusBarSource
    case statusCodexFiveHour
    case statusCodexWeekly
    case statusDailyTokens
    case statusDisplayHint
    case statusFiveHourPercent
    case statusMetricOff
    case statusClaudeFiveHour
    case statusClaudeWeekly
    case statusFableWeekly
    case statusQuotaPercents
    case statusWeeklyPercent
    case statusWeeklyTokens
    case tokenActivity
    case tokenMeter
    case tracked
    case total
    case totalEvents
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
    case quotaCycles
    case quotaCyclesSubtitle
    case fiveHourWindow
    case weeklyWindow
    case cyclePeak
    case cycleInProgress
    case cycleHistoryTitle
    case cycleHistoryHint
    case fiveHourCyclesTitle
    case fiveHourCyclesHint
    case cyclePartial
    case cycleBackfilled
    case cycleCappedFormat
    case cycleNoHistory
    case cyclePaceAheadFormat
    case cyclePaceBehindFormat
    case cycleTimeMarkerHint
    case cycleNow
    case cycleEarlyRefresh
    case cycleEarlyRefreshFootnote
    case cycleNormalReset
    case cycleEarlierBand
    case cycleAvgPeakFormat
    case cycleCappedCountFormat
    case cycleEarlyCountFormat
    case cycleDurationDaysFormat
    case cycleCurrentDayFormat
    case cycleBandGrowHint
    case cycleDurationLabel
    case cycleDeltaLabel
    case cyclePaceCapEtaFormat
    case cyclePaceEndProjectionFormat
    case cycleMoneySummaryValueFormat
    case cycleMoneyUsedTitle
    case cycleMoneyWastedTitle
    case cycleMoneyRemainTitle
    case cycleMoneyPerCycleFormat
    case cycleMoneyHint
    case cycleWasteLabel
    case cycleValueLabel
    case cycleCurrentTitle
    case cycleDailyHint
    case cycleTokensApproxFormat

    var english: String {
        switch self {
        case .about: return "About"
        case .aboutSubtitle: return "How the meter reads and groups local usage"
        case .all: return "All"
        case .allDescription: return "Everything with token detail"
        case .apiDescription: return "All non-subscription provider usage + local imports"
        case .apiEquivalent: return "API equivalent"
        case .apiEquivalentHint: return "Estimated from model-specific API prices. Unlabeled or unknown models remain unpriced."
        case .before: return "Before"
        case .budget: return "Budget"
        case .cache: return "Cache"
        case .cacheHit: return "Cache Hit"
        case .cacheHitDescription: return "Cached input divided by total input for the selected window."
        case .cached: return "Cached"
        case .claudeStatuslineRequired: return "Needs statusline"
        case .staleData: return "Stale"
        case .staleDataFormat: return "Stale · %@ ago"
        case .calendar: return "Calendar"
        case .calendarSubtitle: return "Daily usage intensity over the last year"
        case .clickForDetails: return "Click for details"
        case .claude: return "Claude"
        case .claudeCode: return "Claude Code"
        case .claudeDescription: return "Claude Code local logs"
        case .claudeLogs: return "Claude logs"
        case .codex: return "Codex"
        case .codexAppTotal: return "Codex app total"
        case .codexDescription: return "Codex local logs"
        case .combinedUsage: return "Codex + Claude + API"
        case .copy: return "Copy"
        case .costs: return "Costs"
        case .costsSubtitle: return "Plan settings and estimated money usage"
        case .quotaCycles: return "Quota Cycles"
        case .quotaCyclesSubtitle: return "When quotas reset and how much each cycle used"
        case .fiveHourWindow: return "5h window"
        case .weeklyWindow: return "Weekly window"
        case .cyclePeak: return "Peak"
        case .cycleInProgress: return "In progress"
        case .cycleHistoryTitle: return "Weekly Cycles"
        case .cycleHistoryHint: return "Split by observed reset times, not calendar weeks"
        case .fiveHourCyclesTitle: return "Recent 5h Cycles"
        case .fiveHourCyclesHint: return "Each bar is one 5h cycle's peak usage"
        case .cyclePartial: return "partial samples"
        case .cycleBackfilled: return "estimated from legacy weekly data"
        case .cycleCappedFormat: return "%d capped / %d cycles"
        case .cycleNoHistory: return "No cycle history yet. Keep the app running to collect reset cycles."
        case .cyclePaceAheadFormat: return "%dpt ahead of even pace"
        case .cyclePaceBehindFormat: return "%dpt behind even pace"
        case .cycleTimeMarkerHint: return "Elapsed"
        case .cycleNow: return "now"
        case .cycleEarlyRefresh: return "Early refresh"
        case .cycleEarlyRefreshFootnote: return "Early refresh: quota refreshed before the scheduled reset time (e.g. provider promotion)"
        case .cycleNormalReset: return "Scheduled reset"
        case .cycleEarlierBand: return "Earlier cycles"
        case .cycleAvgPeakFormat: return "Avg peak %d%%"
        case .cycleCappedCountFormat: return "%d capped"
        case .cycleEarlyCountFormat: return "%d early refresh"
        case .cycleDurationDaysFormat: return "%.1f days"
        case .cycleCurrentDayFormat: return "day %.1f"
        case .cycleBandGrowHint: return "Earlier cycles will appear here as history accumulates."
        case .cycleDurationLabel: return "Duration"
        case .cycleDeltaLabel: return "vs prev"
        case .cyclePaceCapEtaFormat: return "caps in %@ at this pace"
        case .cyclePaceEndProjectionFormat: return "ends near %d%% at this pace"
        case .cycleMoneySummaryValueFormat: return "Last %d cycles value"
        case .cycleMoneyUsedTitle: return "Value used"
        case .cycleMoneyWastedTitle: return "Money wasted"
        case .cycleMoneyRemainTitle: return "Left this cycle"
        case .cycleMoneyPerCycleFormat: return "%@/mo · %@ per cycle"
        case .cycleMoneyHint: return "Cycle value = monthly × 12 ÷ 52 · early-refresh cycles pro-rated by span"
        case .cycleWasteLabel: return "Wasted"
        case .cycleValueLabel: return "Cycle value"
        case .cycleCurrentTitle: return "Current cycle"
        case .cycleDailyHint: return "Daily usage this cycle"
        case .cycleTokensApproxFormat: return "≈ %@ tokens"
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
        case .codexAPISources: return "Codex API sources"
        case .codexAPISourcesHint: return "CODEX_HOME roots used for official live quota, Profile API totals, and reset credits. They do not change local log scanning."
        case .codexAPISourcesChoose: return "Choose..."
        case .codexHomeRing: return "Codex home ring"
        case .codexStatusUnavailable: return "Status unavailable"
        case .dayValue: return "Day value"
        case .dataSource: return "Data Source"
        case .dataSourceLine1: return "The app reads local Codex logs under ~/.codex and Claude Code logs under ~/.claude/projects."
        case .dataSourceLine2: return "For 24h, the big \"total\" and input/output breakdown use the same rolling local-log window. For 7d and 30d, the big \"total\" uses Codex's official Profile API (account-level usage) when available, while input/output and Details views use local logs, so those longer-window totals can differ."
        case .definitions: return "Definitions"
        case .detectedNotTracked: return "Detected, not counted"
        case .details: return "Details"
        case .detailsWindowTitle: return "AI Token Meter Details"
        case .diagnostics: return "Diagnostics"
        case .diagnosticsSubtitle: return "Data sources, warnings, and tool coverage"
        case .disabled: return "Disabled"
        case .displayCurrency: return "Display currency"
        case .displayCurrencyHint: return "Controls money displays in the dashboard and details."
        case .visibleUsageSources: return "Visible usage sources"
        case .visibleUsageSourcesHint: return "Choose which sources appear in the dashboard and details. Total includes only enabled sources."
        case .selectedDayQuotaShareHint: return "That day's token usage as a share of the estimated weekly quota. The model table shows the contribution from each model."
        case .displayEquivalent: return "Display equivalent"
        case .enabled: return "Enabled"
        case .english: return "English"
        case .events: return "Usage records"
        case .externalAPICost: return "External API cost"
        case .externalAPICostHint: return "API includes all non-subscription usage identified by provider or provider-qualified model ID. Optional api-usage.json adds calls made outside Codex."
        case .fileMissing: return "File missing"
        case .filePresent: return "File present"
        case .fresh: return "Fresh"
        case .inShort: return "in"
        case .input: return "Input"
        case .interfaceLanguage: return "Interface Language"
        case .insights: return "Insights"
        case .insightsSubtitle: return "Find long-running repo sessions and context compaction"
        case .japanese: return "Japanese"
        case .language: return "Language"
        case .languageHint: return "Changes apply immediately to the popover and details window."
        case .launchAtLogin: return "Open at Login"
        case .launchAtLoginHint: return "Start AI Token Meter automatically when you sign in."
        case .liveQuota: return "Live quota"
        case .liveLimitUnavailable: return "Live limit unavailable"
        case .logFolder: return "Log Folder"
        case .logFolderHint: return "Default scans sessions and archived_sessions; added folders extend the scan roots."
        case .logFolderChoose: return "Add..."
        case .logFolderDefault: return "Default"
        case .logFolderOpen: return "Finder"
        case .loadingAllUsage: return "Scanning all usage..."
        case .loadingClaudeUsage: return "Scanning Claude usage..."
        case .loadingCodexUsage: return "Scanning Codex usage..."
        case .loadingFinalizing: return "Preparing details..."
        case .loadingOtherUsage: return "Scanning other models..."
        case .loadingProfileTotals: return "Reading Profile API totals..."
        case .loadingRepoInsights: return "Building repo insights..."
        case .loadingSparkUsage: return "Scanning Spark usage..."
        case .loadingUsageDetails: return "Loading usage details..."
        case .loadingUsageDetailsHint: return "This can take a moment when the local Codex log cache is cold."
        case .logs: return "Logs"
        case .manualRefreshCycle: return "OpenAI refresh"
        case .modelLimit: return "Model"
        case .modelGroupingNote: return "Model grouping comes from local Codex rollout logs and Claude Code assistant usage entries."
        case .modelMissingNote: return "Rows without a model label are counted in totals but cannot be assigned to a model."
        case .modelNoSearchResults: return "No matching models"
        case .modelSearchPlaceholder: return "Search models"
        case .modelSortCost: return "API cost"
        case .modelSortName: return "Name"
        case .modelSortTokens: return "Token share"
        case .modelTrustIdentificationFormat: return "Model labels %.1f%% · %d unknown hidden"
        case .modelTrustPricingFormat: return "API price coverage %.1f%% · %d unpriced models"
        case .modelTrustSourceFormat: return "Local %@ logs · scanned %@"
        case .modelVisibleCountFormat: return "%d of %d models"
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
        case .overviewSubtitle: return "365-day token usage by source and model"
        case .claudeHomeRing: return "Claude home ring"
        case .claudeThirdRing: return "Claude third ring"
        case .claudeThirdRingHint: return "Choose whether the third equal-size ring shows cache hit rate or the separate Fable weekly quota."
        case .showCombinedFable: return "Show Fable on combined page"
        case .showCombinedFableHint: return "Adds the compact Fable weekly quota ring beside Claude on the combined dashboard."
        case .past24Hours: return "Past 24 Hours"
        case .past30Days: return "Past 30 Days"
        case .past7Days: return "Past 7 Days"
        case .pastYear: return "Past Year"
        case .peakDay: return "of peak day"
        case .peakWeek: return "of peak week"
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
        case .profileAPITotalsHint: return "Uses the read-only ChatGPT profile endpoint for official lifetime totals and daily buckets. If an API day is 0 but same-day local logs have usage, daily views fall back to local logs."
        case .quotaDisplayBullet: return "Bullet"
        case .quotaDisplayHint: return "Choose how the 5h and weekly quota pace are shown."
        case .quotaDisplayRings: return "Rings"
        case .quotaDisplayStyle: return "Quota Display"
        case .quotaHomeRingHint: return "Controls the two large rings on the combined Codex + Claude home page."
        case .quotaViews: return "Usage Sources"
        case .quotaWarnings: return "Quota warnings"
        case .quotaWarningsHint: return "Notify once when a live quota window drops below 15% remaining."
        case .recentRollouts: return "Recent rollouts"
        case .quit: return "Quit"
        case .refresh: return "Refresh"
        case .refreshing: return "Refreshing..."
        case .remaining: return "Remaining"
        case .resetCredits: return "Reset Credits"
        case .resetCreditCountFormat: return "%d left"
        case .resetCreditEstimated: return "estimated"
        case .resetCreditExpiresAt: return "Expires"
        case .resetCreditExpiryUnavailable: return "Expiry unavailable"
        case .resetCreditGrantedAt: return "Granted"
        case .resetCreditNoCredits: return "No credits"
        case .showPastEmptyWeeks: return "Show past empty weeks"
        case .reset: return "Reset"
        case .sessions: return "Sessions"
        case .settings: return "Settings"
        case .settingsSubtitle: return "Language and display preferences"
        case .sourceHealth: return "Source health"
        case .sourceSplit: return "Codex / Claude split"
        case .spark: return "Spark"
        case .sparkDescription: return "Usage records attributed to GPT-5.3-Codex-Spark."
        case .sparkModel: return "GPT-5.3-Codex-Spark model"
        case .statusBarDisplay: return "Menu Bar Display"
        case .statusBarMetricOne: return "Menu Bar Number 1"
        case .statusBarMetricTwo: return "Menu Bar Number 2"
        case .statusBarSource: return "Menu Bar Source"
        case .statusCodexFiveHour: return "Codex 5h"
        case .statusCodexWeekly: return "Codex 1w"
        case .statusDailyTokens: return "24h tokens"
        case .statusDisplayHint: return "Choose one or two live quota percentages. Number 2 can be turned off."
        case .statusFiveHourPercent: return "5h %"
        case .statusMetricOff: return "Off"
        case .statusClaudeFiveHour: return "Claude 5h"
        case .statusClaudeWeekly: return "Claude 1w"
        case .statusFableWeekly: return "Fable 1w"
        case .statusQuotaPercents: return "5h | Weekly %"
        case .statusWeeklyPercent: return "Weekly %"
        case .statusWeeklyTokens: return "7d tokens"
        case .tokenActivity: return "Token Activity"
        case .tokenMeter: return "Token Meter"
        case .tracked: return "Tracked"
        case .total: return "total"
        case .totalEvents: return "Total usage records"
        case .totalSpendValue: return "Total spend"
        case .totalSpendValueHint: return "Accumulated plan value since the paid-start date, estimated from local token usage and weekly quota references."
        case .totalWasteValue: return "Total waste"
        case .totalWasteValueHint: return "Accrued budget minus total spend. Negative values are clamped to zero."
        case .totalsObservedNote: return "local-observed usage, not official billing"
        case .turns: return "Turns"
        case .todayValue: return "Today value"
        case .updated: return "Updated"
        case .used: return "Used"
        case .usageDetails: return "Usage Details"
        case .usageIntensityHint: return "Click a day or week; hold Command to multi-select; drag to marquee-select"
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
        case .apiEquivalentCostHint: return "fresh input × input price + cached input × cache price + output × output price. Unknown models remain unpriced."
        case .externalAPICostCalculationHint: return "Non-subscription providers are detected in Codex rollouts. OpenRouter supplies the current model price catalog; optional api-usage.json supplements calls made elsewhere."
        case .month: return "Month"
        case .fiveHourLeft: return "5h Left"
        case .chinese: return "Chinese"
        }
    }

    var chinese: String {
        switch self {
        case .about: return "关于"
        case .aboutSubtitle: return "本地用量的读取和分组方式"
        case .all: return "全部"
        case .allDescription: return "包含 token 明细的全部记录"
        case .apiDescription: return "所有非订阅 provider 用量和本地导入"
        case .apiEquivalent: return "API 等价成本"
        case .apiEquivalentHint: return "按具体模型的 API 单价估算；没有标签或未知模型保持未定价。"
        case .before: return "刷新前"
        case .budget: return "预算"
        case .cache: return "缓存"
        case .cacheHit: return "缓存命中"
        case .cacheHitDescription: return "选定时间范围内，缓存输入占总输入的比例。"
        case .cached: return "缓存"
        case .claudeStatuslineRequired: return "需 statusline"
        case .staleData: return "已过期"
        case .staleDataFormat: return "数据过期 · %@前"
        case .calendar: return "日历"
        case .calendarSubtitle: return "过去一年的每日使用强度"
        case .clickForDetails: return "点击查看详情"
        case .claude: return "Claude"
        case .claudeCode: return "Claude Code"
        case .claudeDescription: return "Claude Code 本地日志"
        case .claudeLogs: return "Claude 日志"
        case .codex: return "Codex"
        case .codexAppTotal: return "Codex 总用量"
        case .codexDescription: return "Codex 本地日志"
        case .combinedUsage: return "Codex + Claude + API"
        case .copy: return "复制"
        case .costs: return "成本"
        case .costsSubtitle: return "订阅额度周期与直接 API 成本"
        case .quotaCycles: return "额度周期"
        case .quotaCyclesSubtitle: return "额度重置时间与每个周期的用量"
        case .fiveHourWindow: return "5 小时窗口"
        case .weeklyWindow: return "周窗口"
        case .cyclePeak: return "峰值"
        case .cycleInProgress: return "进行中"
        case .cycleHistoryTitle: return "周额度周期历史"
        case .cycleHistoryHint: return "按实际重置时刻切分，而非自然周"
        case .fiveHourCyclesTitle: return "最近 5 小时周期"
        case .fiveHourCyclesHint: return "每根柱是一个 5h 周期的峰值用量"
        case .cyclePartial: return "采样不完整"
        case .cycleBackfilled: return "旧版周数据估算"
        case .cycleCappedFormat: return "%d 次触顶 / %d 周期"
        case .cycleNoHistory: return "暂无周期记录，保持应用运行即可自动积累。"
        case .cyclePaceAheadFormat: return "超前匀速 %dpt"
        case .cyclePaceBehindFormat: return "低于匀速 %dpt"
        case .cycleTimeMarkerHint: return "时间进度"
        case .cycleNow: return "至今"
        case .cycleEarlyRefresh: return "提前刷新"
        case .cycleEarlyRefreshFootnote: return "提前刷新：在计划重置时间之前观察到额度刷新（如官方活动）"
        case .cycleNormalReset: return "正常重置"
        case .cycleEarlierBand: return "更早周期"
        case .cycleAvgPeakFormat: return "平均峰值 %d%%"
        case .cycleCappedCountFormat: return "触顶 %d 次"
        case .cycleEarlyCountFormat: return "提前刷新 %d 次"
        case .cycleDurationDaysFormat: return "%.1f 天"
        case .cycleCurrentDayFormat: return "第 %.1f 天"
        case .cycleBandGrowHint: return "更早周期会随记录自动出现在这里，逐渐排满一整年。"
        case .cycleDurationLabel: return "时长"
        case .cycleDeltaLabel: return "较上轮"
        case .cyclePaceCapEtaFormat: return "按此节奏 %@ 后触顶"
        case .cyclePaceEndProjectionFormat: return "按此节奏周期末约 %d%%"
        case .cycleMoneySummaryValueFormat: return "近 %d 轮总价值"
        case .cycleMoneyUsedTitle: return "用出来的价值"
        case .cycleMoneyWastedTitle: return "浪费掉的钱"
        case .cycleMoneyRemainTitle: return "本轮剩余可用"
        case .cycleMoneyPerCycleFormat: return "%@/月 · 每轮 %@"
        case .cycleMoneyHint: return "每轮价值 = 月费×12÷52 · 提前刷新轮按实际时长折算"
        case .cycleWasteLabel: return "浪费"
        case .cycleValueLabel: return "周期价值"
        case .cycleCurrentTitle: return "本轮"
        case .cycleDailyHint: return "本轮每日消耗"
        case .cycleTokensApproxFormat: return "≈ %@ token"
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
        case .codexAPISources: return "Codex 官方接口来源"
        case .codexAPISourcesHint: return "用于读取官方实时额度、Profile API 总量和重置机会的 CODEX_HOME 根目录；不影响本地日志扫描。"
        case .codexAPISourcesChoose: return "选择..."
        case .codexHomeRing: return "Codex 首页圆环"
        case .dayValue: return "当日价值"
        case .dataSource: return "数据来源"
        case .dataSourceLine1: return "应用读取 ~/.codex 下的 Codex 日志，以及 ~/.claude/projects 下的 Claude Code 日志。"
        case .dataSourceLine2: return "24h 下，顶部“总量”和输入/输出都使用同一段滚动 24 小时本地日志。7d/30d 下，顶部“总量”会在可用时使用 Codex 官方 Profile API（账户级用量），输入/输出和详情页仍使用本地日志，因此较长时间窗口的总量可能不同。"
        case .definitions: return "定义"
        case .detectedNotTracked: return "已检测，未计入"
        case .details: return "详情"
        case .detailsWindowTitle: return "AI Token Meter 详情"
        case .diagnostics: return "诊断"
        case .diagnosticsSubtitle: return "数据源、提醒和工具覆盖"
        case .disabled: return "已关闭"
        case .displayCurrency: return "展示币种"
        case .displayCurrencyHint: return "控制概览和详情里的金额显示币种。"
        case .visibleUsageSources: return "显示数据源"
        case .visibleUsageSourcesHint: return "选择概览和详情中显示的数据源；“全部”只汇总已开启的来源。"
        case .selectedDayQuotaShareHint: return "当天 Token 用量占估算周额度的比例；下方模型表会分别列出每个模型贡献的占比。"
        case .displayEquivalent: return "展示折合"
        case .enabled: return "已开启"
        case .english: return "英语"
        case .events: return "用量记录"
        case .externalAPICost: return "外部 API 成本"
        case .externalAPICostHint: return "API 会按 provider 或“厂商/模型”ID 统计所有非订阅用量；可选 api-usage.json 补充 Codex 之外的调用。"
        case .fileMissing: return "文件不存在"
        case .filePresent: return "文件存在"
        case .fresh: return "新输入"
        case .inShort: return "输入"
        case .input: return "输入"
        case .interfaceLanguage: return "界面语言"
        case .insights: return "洞察"
        case .insightsSubtitle: return "按项目和文件夹定位长会话"
        case .japanese: return "日语"
        case .language: return "语言"
        case .languageHint: return "切换后会立即应用到弹窗和详情窗口。"
        case .launchAtLogin: return "开机启动"
        case .launchAtLoginHint: return "登录 macOS 后自动启动 AI Token Meter。"
        case .liveQuota: return "实时额度"
        case .liveLimitUnavailable: return "实时限额不可用"
        case .logFolder: return "日志目录"
        case .logFolderHint: return "默认扫描 sessions 和 archived_sessions；添加的目录会扩展扫描范围，可一次选择多个。"
        case .logFolderChoose: return "添加..."
        case .logFolderDefault: return "默认"
        case .logFolderOpen: return "Finder"
        case .loadingAllUsage: return "正在扫描全部用量..."
        case .loadingClaudeUsage: return "正在扫描 Claude 用量..."
        case .loadingCodexUsage: return "正在扫描 Codex 用量..."
        case .loadingFinalizing: return "正在整理详情..."
        case .loadingOtherUsage: return "正在扫描其他模型..."
        case .loadingProfileTotals: return "正在读取 Profile API 总量..."
        case .loadingRepoInsights: return "正在生成 Repo 洞察..."
        case .loadingSparkUsage: return "正在扫描 Spark 用量..."
        case .loadingUsageDetails: return "正在加载用量详情..."
        case .loadingUsageDetailsHint: return "本地 Codex 日志缓存冷启动时可能需要一点时间。"
        case .logs: return "日志"
        case .manualRefreshCycle: return "OpenAI 手动刷新"
        case .modelLimit: return "模型"
        case .modelGroupingNote: return "模型分组来自本地 Codex rollout 日志和 Claude Code assistant usage 记录。"
        case .modelMissingNote: return "没有模型标签的记录会计入总量，但无法归入单个模型。"
        case .modelNoSearchResults: return "没有匹配的模型"
        case .modelSearchPlaceholder: return "搜索模型"
        case .modelSortCost: return "API 成本"
        case .modelSortName: return "名称"
        case .modelSortTokens: return "Token 比例"
        case .modelTrustIdentificationFormat: return "模型识别覆盖 %.1f%% · 已隐藏 %d 个未知模型"
        case .modelTrustPricingFormat: return "API 价格覆盖 %.1f%% · %d 个模型尚未定价"
        case .modelTrustSourceFormat: return "本地 %@ 日志 · 扫描于 %@"
        case .modelVisibleCountFormat: return "显示 %d / %d 个模型"
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
        case .overviewSubtitle: return "过去 365 天按来源和模型统计"
        case .claudeHomeRing: return "Claude 首页圆环"
        case .claudeThirdRing: return "Claude 第三个圆环"
        case .claudeThirdRingHint: return "选择第三个同尺寸圆环显示缓存命中率，还是独立的 Fable 周额度。"
        case .showCombinedFable: return "合并页显示 Fable"
        case .showCombinedFableHint: return "在 Codex + Claude 合并页的 Claude 右侧显示 Fable 周额度小圆环。"
        case .past24Hours: return "过去 24 小时"
        case .past30Days: return "过去 30 天"
        case .past7Days: return "过去 7 天"
        case .pastYear: return "过去一年"
        case .peakDay: return "峰值日"
        case .peakWeek: return "峰值周"
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
        case .profileAPITotalsHint: return "用只读 ChatGPT Profile 接口读取官方累计总量和每日桶；如果某天 API 为 0 但本地同日日志有用量，日历会用本地值兜底。"
        case .quotaDisplayBullet: return "子弹图"
        case .quotaDisplayHint: return "选择 5小时和周额度的节奏展示方式。"
        case .quotaDisplayRings: return "圆环"
        case .quotaDisplayStyle: return "额度样式"
        case .quotaHomeRingHint: return "控制 Codex + Claude 合并首页上方两个大圆环显示 5小时还是周额度。"
        case .quotaViews: return "用量来源"
        case .quotaWarnings: return "额度提醒"
        case .quotaWarningsHint: return "实时额度低于 15% 时，每个窗口只提醒一次。"
        case .recentRollouts: return "近期日志"
        case .quit: return "退出"
        case .refresh: return "刷新"
        case .refreshing: return "刷新中..."
        case .remaining: return "剩余"
        case .resetCredits: return "重置机会"
        case .resetCreditCountFormat: return "%d 次"
        case .resetCreditEstimated: return "估算"
        case .resetCreditExpiresAt: return "到期"
        case .resetCreditExpiryUnavailable: return "无法读取过期时间"
        case .resetCreditGrantedAt: return "获得"
        case .resetCreditNoCredits: return "暂无可用机会"
        case .showPastEmptyWeeks: return "显示以前的无数据周"
        case .reset: return "重置"
        case .sessions: return "会话"
        case .settings: return "设置"
        case .settingsSubtitle: return "语言和显示偏好"
        case .sourceHealth: return "数据源健康"
        case .sourceSplit: return "Codex / Claude 占比"
        case .spark: return "Spark"
        case .sparkDescription: return "归属于 GPT-5.3-Codex-Spark 的用量记录。"
        case .sparkModel: return "GPT-5.3-Codex-Spark 模型"
        case .statusBarDisplay: return "状态栏显示"
        case .statusBarMetricOne: return "状态栏数字 1"
        case .statusBarMetricTwo: return "状态栏数字 2"
        case .statusBarSource: return "状态栏来源"
        case .statusCodexFiveHour: return "Codex 5h"
        case .statusCodexWeekly: return "Codex 1周"
        case .statusDailyTokens: return "24h 用量"
        case .statusDisplayHint: return "选择 1 个或 2 个实时额度百分比；数字 2 可关闭。"
        case .statusFiveHourPercent: return "5h 百分比"
        case .statusMetricOff: return "关闭"
        case .statusClaudeFiveHour: return "Claude 5h"
        case .statusClaudeWeekly: return "Claude 1周"
        case .statusFableWeekly: return "Fable 1周"
        case .statusQuotaPercents: return "5h | 周百分比"
        case .statusWeeklyPercent: return "周百分比"
        case .statusWeeklyTokens: return "7d 用量"
        case .tokenActivity: return "Token 活动"
        case .tokenMeter: return "Token 统计"
        case .tracked: return "已计入"
        case .total: return "总计"
        case .totalEvents: return "用量记录总数"
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
        case .usageIntensityHint: return "点击日期或周圆点；按住 Command 可多选，拖动可圈选"
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
        case .apiEquivalentCostHint: return "按模型单价估算：fresh input × 输入价 + cached input × 缓存价 + output × 输出价；未知模型保持未定价。"
        case .externalAPICostCalculationHint: return "自动识别 Codex rollout 中所有非订阅 provider，并用 OpenRouter 目录补充当前模型价格；api-usage.json 可导入其他 API 调用。"
        case .month: return "月"
        case .fiveHourLeft: return "5小时剩余"
        case .chinese: return "中文"
        }
    }

    var japanese: String {
        switch self {
        case .about: return "概要"
        case .aboutSubtitle: return "ローカル使用量の読み取りと分類方法"
        case .all: return "すべて"
        case .allDescription: return "token 詳細を含むすべての記録"
        case .apiDescription: return "サブスクリプション外プロバイダーの使用量とローカル取り込み"
        case .apiEquivalent: return "API 換算"
        case .apiEquivalentHint: return "モデル別 API 単価から推定します。不明なモデルは未価格のまま表示します。"
        case .before: return "更新前"
        case .budget: return "予算"
        case .cache: return "キャッシュ"
        case .cacheHit: return "キャッシュ率"
        case .cacheHitDescription: return "選択した期間の総入力に対するキャッシュ入力の割合。"
        case .cached: return "キャッシュ"
        case .claudeStatuslineRequired: return "statusline 必要"
        case .staleData: return "期限切れ"
        case .staleDataFormat: return "%@前のデータ"
        case .calendar: return "カレンダー"
        case .calendarSubtitle: return "過去 1 年の日別使用量"
        case .clickForDetails: return "クリックで詳細"
        case .claude: return "Claude"
        case .claudeCode: return "Claude Code"
        case .claudeDescription: return "Claude Code ローカルログ"
        case .claudeLogs: return "Claude ログ"
        case .codex: return "Codex"
        case .codexAppTotal: return "Codex 全体使用量"
        case .codexDescription: return "Codex ローカルログ"
        case .combinedUsage: return "Codex + Claude + API"
        case .copy: return "コピー"
        case .costs: return "金額"
        case .costsSubtitle: return "プラン設定と金額推定"
        case .quotaCycles: return "クォータ周期"
        case .quotaCyclesSubtitle: return "リセット時刻と各周期の使用率"
        case .fiveHourWindow: return "5時間ウィンドウ"
        case .weeklyWindow: return "週ウィンドウ"
        case .cyclePeak: return "ピーク"
        case .cycleInProgress: return "進行中"
        case .cycleHistoryTitle: return "週クォータ周期の履歴"
        case .cycleHistoryHint: return "暦週ではなく実際のリセット時刻で区切ります"
        case .fiveHourCyclesTitle: return "直近の5時間周期"
        case .fiveHourCyclesHint: return "各バーは1周期のピーク使用率"
        case .cyclePartial: return "サンプル不足"
        case .cycleBackfilled: return "旧週次データからの推定"
        case .cycleCappedFormat: return "上限到達 %d / %d 周期"
        case .cycleNoHistory: return "周期履歴はまだありません。アプリを起動したままにすると記録されます。"
        case .cyclePaceAheadFormat: return "均等ペースより%dpt先行"
        case .cyclePaceBehindFormat: return "均等ペースより%dpt低い"
        case .cycleTimeMarkerHint: return "経過"
        case .cycleNow: return "現在"
        case .cycleEarlyRefresh: return "前倒し更新"
        case .cycleEarlyRefreshFootnote: return "前倒し更新：予定リセットより早いクォータ更新（公式キャンペーン等）"
        case .cycleNormalReset: return "定期リセット"
        case .cycleEarlierBand: return "以前の周期"
        case .cycleAvgPeakFormat: return "平均ピーク %d%%"
        case .cycleCappedCountFormat: return "上限到達 %d回"
        case .cycleEarlyCountFormat: return "前倒し更新 %d回"
        case .cycleDurationDaysFormat: return "%.1f日"
        case .cycleCurrentDayFormat: return "%.1f日目"
        case .cycleBandGrowHint: return "以前の周期は記録が貯まるとここに表示されます。"
        case .cycleDurationLabel: return "期間"
        case .cycleDeltaLabel: return "前周期比"
        case .cyclePaceCapEtaFormat: return "このペースだと%@後に上限"
        case .cyclePaceEndProjectionFormat: return "このペースで周期末は約%d%%"
        case .cycleMoneySummaryValueFormat: return "直近%d周期の総価値"
        case .cycleMoneyUsedTitle: return "使った価値"
        case .cycleMoneyWastedTitle: return "無駄になった金額"
        case .cycleMoneyRemainTitle: return "今周期の残り"
        case .cycleMoneyPerCycleFormat: return "%@/月 · 1周期 %@"
        case .cycleMoneyHint: return "周期価値 = 月額×12÷52 · 前倒し周期は期間で按分"
        case .cycleWasteLabel: return "未使用"
        case .cycleValueLabel: return "周期価値"
        case .cycleCurrentTitle: return "今周期"
        case .cycleDailyHint: return "今周期の日別消費"
        case .cycleTokensApproxFormat: return "≈ %@ tokens"
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
        case .codexAPISources: return "Codex API ソース"
        case .codexAPISourcesHint: return "公式のライブ制限、Profile API 合計、リセット機会を読む CODEX_HOME ルートです。ローカルログのスキャンには影響しません。"
        case .codexAPISourcesChoose: return "選択..."
        case .codexHomeRing: return "Codex ホームリング"
        case .dayValue: return "当日の価値"
        case .dataSource: return "データソース"
        case .dataSourceLine1: return "このアプリは ~/.codex の Codex ログと ~/.claude/projects の Claude Code ログを読み取ります。"
        case .dataSourceLine2: return "24h では、上部の「総量」と入出力の内訳に同じローリング 24 時間のローカルログを使用します。7d/30d では、利用可能な場合に上部の「総量」は Codex 公式 Profile API（アカウント単位の使用量）を使い、入出力と詳細画面はローカルログを使うため、長い期間の合計は一致しない場合があります。"
        case .definitions: return "定義"
        case .detectedNotTracked: return "検出済み・未集計"
        case .details: return "詳細"
        case .detailsWindowTitle: return "AI Token Meter 詳細"
        case .diagnostics: return "診断"
        case .diagnosticsSubtitle: return "データソース、通知、ツール範囲"
        case .disabled: return "無効"
        case .displayCurrency: return "表示通貨"
        case .displayCurrencyHint: return "ダッシュボードと詳細の金額表示に使う通貨です。"
        case .visibleUsageSources: return "表示する使用元"
        case .visibleUsageSourcesHint: return "ダッシュボードと詳細に表示する使用元を選びます。合計には有効な使用元だけを含めます。"
        case .selectedDayQuotaShareHint: return "当日の Token 使用量が推定週制限に占める割合です。下のモデル表にモデル別の寄与を表示します。"
        case .displayEquivalent: return "表示換算"
        case .enabled: return "有効"
        case .english: return "英語"
        case .events: return "使用量レコード"
        case .externalAPICost: return "外部 API コスト"
        case .externalAPICostHint: return "provider または provider/model ID で非サブスクリプション使用量を集計し、任意の api-usage.json で外部呼び出しを補足します。"
        case .fileMissing: return "ファイルなし"
        case .filePresent: return "ファイルあり"
        case .fresh: return "新規入力"
        case .inShort: return "入力"
        case .input: return "入力"
        case .interfaceLanguage: return "表示言語"
        case .insights: return "洞察"
        case .insightsSubtitle: return "プロジェクトとフォルダ別に長いスレッドを特定"
        case .japanese: return "日本語"
        case .language: return "言語"
        case .languageHint: return "変更はポップオーバーと詳細ウィンドウにすぐ反映されます。"
        case .launchAtLogin: return "ログイン時に開く"
        case .launchAtLoginHint: return "macOS にサインインしたときに AI Token Meter を自動起動します。"
        case .liveQuota: return "リアルタイム制限"
        case .liveLimitUnavailable: return "リアルタイム制限を取得できません"
        case .logFolder: return "ログフォルダ"
        case .logFolderHint: return "既定では sessions と archived_sessions をスキャンし、追加したフォルダでスキャン範囲を拡張します。複数選択できます。"
        case .logFolderChoose: return "追加..."
        case .logFolderDefault: return "既定"
        case .logFolderOpen: return "Finder"
        case .loadingAllUsage: return "全体の使用量をスキャン中..."
        case .loadingClaudeUsage: return "Claude 使用量をスキャン中..."
        case .loadingCodexUsage: return "Codex 使用量をスキャン中..."
        case .loadingFinalizing: return "詳細を準備中..."
        case .loadingOtherUsage: return "その他モデルをスキャン中..."
        case .loadingProfileTotals: return "Profile API 合計を読み込み中..."
        case .loadingRepoInsights: return "Repo 洞察を生成中..."
        case .loadingSparkUsage: return "Spark 使用量をスキャン中..."
        case .loadingUsageDetails: return "使用量の詳細を読み込み中..."
        case .loadingUsageDetailsHint: return "ローカル Codex ログのキャッシュが冷えている場合は少し時間がかかります。"
        case .logs: return "ログ"
        case .manualRefreshCycle: return "OpenAI 手動更新"
        case .modelLimit: return "モデル"
        case .modelGroupingNote: return "モデル別集計はローカル Codex rollout ログと Claude Code assistant usage から取得します。"
        case .modelMissingNote: return "モデル名がない行は合計に含まれますが、個別モデルには割り当てられません。"
        case .modelNoSearchResults: return "一致するモデルはありません"
        case .modelSearchPlaceholder: return "モデルを検索"
        case .modelSortCost: return "API コスト"
        case .modelSortName: return "名前"
        case .modelSortTokens: return "Token 比率"
        case .modelTrustIdentificationFormat: return "モデル識別率 %.1f%% · 不明 %d 件を非表示"
        case .modelTrustPricingFormat: return "API 価格カバー率 %.1f%% · 未価格モデル %d 件"
        case .modelTrustSourceFormat: return "ローカル %@ ログ · スキャン %@"
        case .modelVisibleCountFormat: return "%d / %d モデルを表示"
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
        case .overviewSubtitle: return "過去 365 日のソースとモデル別使用量"
        case .claudeHomeRing: return "Claude ホームリング"
        case .claudeThirdRing: return "Claude の 3 番目のリング"
        case .claudeThirdRingHint: return "3 つ目の同サイズリングにキャッシュ率または Fable の週制限を表示します。"
        case .showCombinedFable: return "統合ページに Fable を表示"
        case .showCombinedFableHint: return "Codex + Claude 統合ページで Claude の横に Fable の週制限リングを表示します。"
        case .past24Hours: return "過去 24 時間"
        case .past30Days: return "過去 30 日"
        case .past7Days: return "過去 7 日"
        case .pastYear: return "過去 1 年"
        case .peakDay: return "ピーク日"
        case .peakWeek: return "ピーク週"
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
        case .profileAPITotalsHint: return "読み取り専用の ChatGPT Profile API で公式の累計と日別バケットを使います。API の日別値が 0 で同日のローカルログに使用量があれば、日別表示はローカル値で補完します。"
        case .quotaDisplayBullet: return "Bullet"
        case .quotaDisplayHint: return "5h と週制限のペース表示を選びます。"
        case .quotaDisplayRings: return "リング"
        case .quotaDisplayStyle: return "制限表示"
        case .quotaHomeRingHint: return "Codex + Claude 統合ホーム上部の 2 つのリングに 5h と週のどちらを出すかを選びます。"
        case .quotaViews: return "使用量ソース"
        case .quotaWarnings: return "制限通知"
        case .quotaWarningsHint: return "残り 15% 未満になった制限枠ごとに一度だけ通知します。"
        case .recentRollouts: return "最近の rollout"
        case .quit: return "終了"
        case .refresh: return "更新"
        case .refreshing: return "更新中..."
        case .remaining: return "残り"
        case .resetCredits: return "リセット枠"
        case .resetCreditCountFormat: return "%d回"
        case .resetCreditEstimated: return "推定"
        case .resetCreditExpiresAt: return "期限"
        case .resetCreditExpiryUnavailable: return "期限を取得できません"
        case .resetCreditGrantedAt: return "付与"
        case .resetCreditNoCredits: return "利用可能な枠なし"
        case .showPastEmptyWeeks: return "過去の空週を表示"
        case .reset: return "リセット"
        case .sessions: return "セッション"
        case .settings: return "設定"
        case .settingsSubtitle: return "言語と表示設定"
        case .sourceHealth: return "ソース状態"
        case .sourceSplit: return "Codex / Claude 比率"
        case .spark: return "Spark"
        case .sparkDescription: return "GPT-5.3-Codex-Spark に記録された使用量レコード。"
        case .sparkModel: return "GPT-5.3-Codex-Spark モデル"
        case .statusBarDisplay: return "メニューバー表示"
        case .statusBarMetricOne: return "メニューバー数値 1"
        case .statusBarMetricTwo: return "メニューバー数値 2"
        case .statusBarSource: return "メニューバーソース"
        case .statusCodexFiveHour: return "Codex 5h"
        case .statusCodexWeekly: return "Codex 1週"
        case .statusDailyTokens: return "24h 使用量"
        case .statusDisplayHint: return "ライブ制限の割合を 1 つまたは 2 つ選択します。数値 2 はオフにできます。"
        case .statusFiveHourPercent: return "5h %"
        case .statusMetricOff: return "オフ"
        case .statusClaudeFiveHour: return "Claude 5h"
        case .statusClaudeWeekly: return "Claude 1週"
        case .statusFableWeekly: return "Fable 1週"
        case .statusQuotaPercents: return "5h | 週 %"
        case .statusWeeklyPercent: return "週 %"
        case .statusWeeklyTokens: return "7日使用量"
        case .tokenActivity: return "Token アクティビティ"
        case .tokenMeter: return "Token メーター"
        case .tracked: return "集計対象"
        case .total: return "合計"
        case .totalEvents: return "使用量レコード合計"
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
        case .usageIntensityHint: return "日付または週をクリック。Commandを押しながら複数選択、ドラッグで囲んで選択"
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
        case .apiEquivalentCostHint: return "fresh input × 入力価格 + cached input × キャッシュ価格 + output × 出力価格で推定します。不明なモデルは未価格です。"
        case .externalAPICostCalculationHint: return "Codex rollout 内の非サブスクリプション provider を検出し、OpenRouter のモデル価格一覧と api-usage.json を利用します。"
        case .month: return "月"
        case .fiveHourLeft: return "5時間残り"
        case .chinese: return "中国語"
        }
    }
}

func t(_ key: L10nKey) -> String {
    AppLanguage.current.text(key)
}

enum CurrencyCode: String, CaseIterable {
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

func convertCurrency(_ amount: Double, from source: CurrencyCode, to target: CurrencyCode) -> Double {
    guard source != target else { return amount }
    return amount * source.usdValue / target.usdValue
}

enum AppSettings {
    static let logFolderKey = "sessionLogFolder"
    static let logFoldersKey = "sessionLogFolders"
    static let codexAPISourceHomesKey = "codexAPISourceHomes"
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
    static let visibleUsageSourcesKey = "visibleUsageSources"
    static let codexHomeRingMetricKey = "codexHomeRingMetric"
    static let claudeHomeRingMetricKey = "claudeHomeRingMetric"
    static let claudeThirdRingMetricKey = "claudeThirdRingMetric"
    static let showCombinedFableEnabledKey = "showCombinedFableEnabled"
    static let statusBarQuotaSourceKey = "statusBarQuotaSource"
    static let statusBarPrimaryMetricKey = "statusBarPrimaryMetric"
    static let statusBarSecondaryMetricKey = "statusBarSecondaryMetric"
    static let claudeKeychainAccessRequestedKey = "claudeKeychainAccessRequested"
    static let claudeKeychainAccessEnabledKey = "claudeKeychainAccessEnabled"
    static let machineUsageInstallationIDKey = "machineUsageInstallationID"
    static let codexDefaultsProtectionEnabledKey =
        CodexModelRoutingProtectionPreferences.enabledKey
    static let codexProtectedRoutingStateKey =
        CodexModelRoutingProtectionPreferences.protectedStateKey
    static let statusBarMetricOffRawValue = "off"

    static let fallbackModelLimitID = "codex_bengalfox"
    static let fallbackModelLimitName = "GPT-5.3-Codex-Spark"
    static let defaultCodexMonthlyPlanCost: Double = 200
    static let defaultClaudeMonthlyPlanCost: Double = 125

    static var visibleUsageSources: [QuotaViewOption] {
        let stored = UserDefaults.standard.stringArray(forKey: visibleUsageSourcesKey) ?? []
        let parsed = stored.compactMap(QuotaViewOption.option(from:)).filter { $0 != .all }
        let ordered = QuotaViewOption.platformCases.filter(parsed.contains)
        return ordered.isEmpty ? QuotaViewOption.platformCases : ordered
    }

    static func setVisibleUsageSources(_ sources: Set<QuotaViewOption>) {
        let ordered = QuotaViewOption.platformCases.filter(sources.contains)
        guard !ordered.isEmpty else { return }
        UserDefaults.standard.set(ordered.map(\.rawValue), forKey: visibleUsageSourcesKey)
    }

    static var defaultCodexHomeURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex", isDirectory: true)
    }

    static var defaultCodexAPIHomeURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex-api", isDirectory: true)
    }

    static var defaultClaudeHomeURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude", isDirectory: true)
    }

    static var defaultClaudeProjectsURL: URL {
        defaultClaudeHomeURL.appendingPathComponent("projects", isDirectory: true)
    }

    static var xdgClaudeProjectsURL: URL {
        let xdgConfigHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
            .flatMap { $0.isEmpty ? nil : $0 }
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config", isDirectory: true)
        return xdgConfigHome
            .appendingPathComponent("claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
    }

    static var environmentClaudeProjectsURLs: [URL] {
        guard let raw = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !raw.isEmpty else {
            return []
        }
        return raw.split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { path in
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
                return url.lastPathComponent == "projects" ? url : url.appendingPathComponent("projects", isDirectory: true)
            }
    }

    static var claudeLogFolderURLs: [URL] {
        uniqueDirectoryURLs(environmentClaudeProjectsURLs + [xdgClaudeProjectsURL, defaultClaudeProjectsURL])
    }

    static var claudeLogFolderDisplayPath: String {
        claudeLogFolderURLs.map { displayPath(for: $0) }.joined(separator: " + ")
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
        !customLogFolderURLs.isEmpty
    }

    static var logFolderURLs: [URL] {
        var roots = [
            defaultLogFolderURL,
            defaultArchivedLogFolderURL
        ]
        roots.append(contentsOf: apiUsageLogFolderURLs)
        if let codexHome = environmentCodexHomeURL {
            roots.append(codexHome.appendingPathComponent("sessions", isDirectory: true))
            roots.append(codexHome.appendingPathComponent("archived_sessions", isDirectory: true))
        }
        roots.append(contentsOf: customLogFolderURLs)
        return uniqueDirectoryURLs(roots)
    }

    static var apiUsageLogFolderURLs: [URL] {
        uniqueDirectoryURLs([
            defaultCodexAPIHomeURL.appendingPathComponent("sessions", isDirectory: true),
            defaultCodexAPIHomeURL.appendingPathComponent("archived_sessions", isDirectory: true)
        ])
    }

    static var logFolderDisplayPath: String {
        return logFolderURLs.map { displayPath(for: $0) }.joined(separator: " + ")
    }

    static var defaultCodexAPISourceHomeURLs: [URL] {
        var roots: [URL] = []
        if let codexHome = environmentCodexHomeURL {
            roots.append(codexHome)
        }
        roots.append(defaultCodexAPIHomeURL)
        roots.append(defaultCodexHomeURL)
        return uniqueDirectoryURLs(roots)
    }

    static var codexAPISourceHomeURLs: [URL] {
        let custom = customCodexAPISourceHomeURLs
        return custom.isEmpty ? defaultCodexAPISourceHomeURLs : custom
    }

    static var customCodexAPISourceHomeURLs: [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: codexAPISourceHomesKey) ?? []
        return uniqueDirectoryURLs(paths.compactMap { rawPath in
            let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { return nil }
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        })
    }

    static var hasCustomCodexAPISourceHomes: Bool {
        !customCodexAPISourceHomeURLs.isEmpty
    }

    static var codexAPISourceDisplayPath: String {
        codexAPISourceHomeURLs.map { displayPath(for: $0) }.joined(separator: " + ")
    }

    static var codexAPISourceOpenURL: URL {
        codexAPISourceHomeURLs.first { FileManager.default.fileExists(atPath: $0.path) } ?? defaultCodexHomeURL
    }

    static func setCodexAPISourceHomeURLs(_ urls: [URL]) {
        let selected = uniqueDirectoryURLs(urls)
        if selected.isEmpty {
            resetCodexAPISourceHomeURLs()
        } else {
            UserDefaults.standard.set(selected.map(\.path), forKey: codexAPISourceHomesKey)
        }
    }

    static func resetCodexAPISourceHomeURLs() {
        UserDefaults.standard.removeObject(forKey: codexAPISourceHomesKey)
    }

    static var logFolderOpenURL: URL {
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

    static var quotaCycleHistoryURL: URL {
        appSupportDirectoryURL.appendingPathComponent("quota-cycle-history.json")
    }

    static var dashboardReportCacheURL: URL {
        appSupportDirectoryURL.appendingPathComponent("dashboard-report-cache.json")
    }

    static var detailsSnapshotCacheURL: URL {
        appSupportDirectoryURL.appendingPathComponent("details-snapshot-cache.json")
    }

    static var liveLimitsCacheURL: URL {
        appSupportDirectoryURL.appendingPathComponent("live-limits-cache.json")
    }

    static var claudeStatuslineCaptureURL: URL {
        appSupportDirectoryURL.appendingPathComponent("claude-statusline.json")
    }

    static var defaultExternalAPICostURL: URL {
        appSupportDirectoryURL.appendingPathComponent("api-usage.json")
    }

    static var openRouterPricingCatalogCacheURL: URL {
        appSupportDirectoryURL.appendingPathComponent("openrouter-model-pricing.json")
    }

    static var logFolderURL: URL {
        get {
            customLogFolderURLs.last ?? defaultLogFolderURL
        }
        set {
            addLogFolderURLs([newValue])
        }
    }

    static var customLogFolderURLs: [URL] {
        let defaults = UserDefaults.standard
        var paths = defaults.stringArray(forKey: logFoldersKey) ?? []
        if let legacyPath = defaults.string(forKey: logFolderKey), !legacyPath.isEmpty {
            paths.append(legacyPath)
        }
        return uniqueDirectoryURLs(paths.compactMap { rawPath in
            let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { return nil }
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        })
    }

    static func addLogFolderURLs(_ urls: [URL]) {
        let merged = uniqueDirectoryURLs(customLogFolderURLs + urls)
        UserDefaults.standard.set(merged.map(\.path), forKey: logFoldersKey)
        UserDefaults.standard.removeObject(forKey: logFolderKey)
    }

    static func resetLogFolder() {
        UserDefaults.standard.removeObject(forKey: logFolderKey)
        UserDefaults.standard.removeObject(forKey: logFoldersKey)
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
            return stored > 0 ? stored : defaultCodexMonthlyPlanCost
        }
        set {
            UserDefaults.standard.set(max(0, newValue), forKey: monthlyPlanCostKey)
        }
    }

    private static func platformCostKey(_ base: String, source: QuotaViewOption) -> String? {
        switch source {
        case .codex:
            return "codex.\(base)"
        case .claude:
            return "claude.\(base)"
        case .all:
            return nil
        case .api:
            return nil
        }
    }

    private static func defaultMonthlyPlanCost(for source: QuotaViewOption) -> Double {
        switch source {
        case .all:
            return defaultCodexMonthlyPlanCost + defaultClaudeMonthlyPlanCost
        case .codex:
            return monthlyPlanCost
        case .claude:
            return defaultClaudeMonthlyPlanCost
        case .api:
            return 0
        }
    }

    static func monthlyPlanCost(for source: QuotaViewOption) -> Double {
        switch source {
        case .all:
            let display = displayCurrency(for: .all)
            return [.codex, .claude].reduce(0) { total, source in
                total + convertCurrency(monthlyPlanCost(for: source), from: paymentCurrency(for: source), to: display)
            }
        case .codex, .claude:
            guard let key = platformCostKey(monthlyPlanCostKey, source: source) else { return defaultMonthlyPlanCost(for: source) }
            let stored = UserDefaults.standard.double(forKey: key)
            return stored > 0 ? stored : defaultMonthlyPlanCost(for: source)
        case .api:
            return 0
        }
    }

    static func setMonthlyPlanCost(_ value: Double, for source: QuotaViewOption) {
        switch source {
        case .all:
            return
        case .codex, .claude:
            guard let key = platformCostKey(monthlyPlanCostKey, source: source) else { return }
            UserDefaults.standard.set(max(0, value), forKey: key)
        case .api:
            return
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

    static func paymentCurrency(for source: QuotaViewOption) -> CurrencyCode {
        switch source {
        case .all:
            return displayCurrency
        case .codex, .claude:
            guard let key = platformCostKey(paymentCurrencyKey, source: source),
                  let raw = UserDefaults.standard.string(forKey: key),
                  let currency = CurrencyCode(rawValue: raw) else {
                return paymentCurrency
            }
            return currency
        case .api:
            return displayCurrency
        }
    }

    static func setPaymentCurrency(_ currency: CurrencyCode, for source: QuotaViewOption) {
        switch source {
        case .all:
            paymentCurrency = currency
        case .codex, .claude:
            guard let key = platformCostKey(paymentCurrencyKey, source: source) else { return }
            UserDefaults.standard.set(currency.rawValue, forKey: key)
        case .api:
            return
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

    static func displayCurrency(for source: QuotaViewOption) -> CurrencyCode {
        switch source {
        case .all:
            return displayCurrency
        case .codex, .claude:
            guard let key = platformCostKey(displayCurrencyKey, source: source),
                  let raw = UserDefaults.standard.string(forKey: key),
                  let currency = CurrencyCode(rawValue: raw) else {
                return displayCurrency
            }
            return currency
        case .api:
            return displayCurrency
        }
    }

    static func setDisplayCurrency(_ currency: CurrencyCode, for source: QuotaViewOption) {
        switch source {
        case .all:
            displayCurrency = currency
        case .codex, .claude:
            guard let key = platformCostKey(displayCurrencyKey, source: source) else { return }
            UserDefaults.standard.set(currency.rawValue, forKey: key)
        case .api:
            return
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

    static func paymentStartDay(for source: QuotaViewOption) -> String? {
        switch source {
        case .all:
            return paymentStartDay
        case .codex, .claude:
            guard let key = platformCostKey(paymentStartDayKey, source: source) else { return paymentStartDay }
            let value = UserDefaults.standard.string(forKey: key)
            return (value?.isEmpty == false) ? value : paymentStartDay
        case .api:
            return nil
        }
    }

    static func setPaymentStartDay(_ value: String?, for source: QuotaViewOption) {
        switch source {
        case .all:
            paymentStartDay = value
        case .codex, .claude:
            guard let key = platformCostKey(paymentStartDayKey, source: source) else { return }
            if let value, !value.isEmpty {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        case .api:
            return
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
        guard let modelLimit = limits.first(where: { $0.id != "codex" && $0.id != QuotaViewOption.claude.liveLimitID }) else { return }
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

    static var claudeKeychainAccessRequested: Bool {
        get { UserDefaults.standard.bool(forKey: claudeKeychainAccessRequestedKey) }
        set { UserDefaults.standard.set(newValue, forKey: claudeKeychainAccessRequestedKey) }
    }

    static var claudeKeychainAccessEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: claudeKeychainAccessEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: claudeKeychainAccessEnabledKey) }
    }

    static var codexHomeRingMetric: HomeQuotaRingMetric {
        get {
            guard let raw = UserDefaults.standard.string(forKey: codexHomeRingMetricKey),
                  let metric = HomeQuotaRingMetric(rawValue: raw) else {
                return .weekly
            }
            return metric
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: codexHomeRingMetricKey)
        }
    }

    static var claudeHomeRingMetric: HomeQuotaRingMetric {
        get {
            guard let raw = UserDefaults.standard.string(forKey: claudeHomeRingMetricKey),
                  let metric = HomeQuotaRingMetric(rawValue: raw) else {
                return .weekly
            }
            return metric
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: claudeHomeRingMetricKey)
        }
    }

    static var claudeThirdRingMetric: ClaudeThirdRingMetric {
        get {
            guard let raw = UserDefaults.standard.string(forKey: claudeThirdRingMetricKey),
                  let metric = ClaudeThirdRingMetric(rawValue: raw) else {
                return .fable
            }
            return metric
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: claudeThirdRingMetricKey)
        }
    }

    static var showCombinedFableEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: showCombinedFableEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: showCombinedFableEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: showCombinedFableEnabledKey)
        }
    }

    static var statusBarQuotaSource: QuotaViewOption {
        get {
            guard let raw = UserDefaults.standard.string(forKey: statusBarQuotaSourceKey),
                  let source = QuotaViewOption.option(from: raw) else {
                return .all
            }
            return source
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: statusBarQuotaSourceKey)
        }
    }

    static var statusBarPrimaryMetric: StatusBarMetric {
        get {
            guard let raw = UserDefaults.standard.string(forKey: statusBarPrimaryMetricKey),
                  let metric = StatusBarMetric(rawValue: raw) else {
                return legacyStatusBarMetrics().first ?? .codexFiveHour
            }
            return metric
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: statusBarPrimaryMetricKey)
        }
    }

    static var statusBarSecondaryMetric: StatusBarMetric? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: statusBarSecondaryMetricKey) else {
                let legacyMetrics = legacyStatusBarMetrics()
                return legacyMetrics.count > 1 ? legacyMetrics[1] : nil
            }
            guard raw != statusBarMetricOffRawValue else { return nil }
            return StatusBarMetric(rawValue: raw)
        }
        set {
            UserDefaults.standard.set(newValue?.rawValue ?? statusBarMetricOffRawValue, forKey: statusBarSecondaryMetricKey)
        }
    }

    static var statusBarMetrics: [StatusBarMetric] {
        var metrics = [statusBarPrimaryMetric]
        if let secondary = statusBarSecondaryMetric {
            metrics.append(secondary)
        }
        return metrics
    }

    private static func legacyStatusBarMetrics() -> [StatusBarMetric] {
        let source = statusBarQuotaSource
        switch StatusDisplayOption.current {
        case .fiveHourPercent:
            return [StatusBarMetric.metric(source: source, quotaMetric: .fiveHour)]
        case .weeklyPercent:
            return [StatusBarMetric.metric(source: source, quotaMetric: .weekly)]
        case .quotaPercents:
            return [
                StatusBarMetric.metric(source: source, quotaMetric: .fiveHour),
                StatusBarMetric.metric(source: source, quotaMetric: .weekly)
            ]
        case .weeklyTokens, .dailyTokens:
            return [StatusBarMetric.metric(source: source, quotaMetric: .weekly)]
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

    static var machineUsageHistoryURL: URL {
        appSupportDirectoryURL.appendingPathComponent("machine-usage-history.json")
    }

    static var machineUsageInstallationID: String {
        if let value = UserDefaults.standard.string(forKey: machineUsageInstallationIDKey), !value.isEmpty {
            return value
        }
        let value = UUID().uuidString.lowercased()
        UserDefaults.standard.set(value, forKey: machineUsageInstallationIDKey)
        return value
    }
}

enum LoginItemManager {
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
                NSLog("AI Token Meter login item update failed: \(error.localizedDescription)")
            }
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }
}

enum ExternalAPICostStore {
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
            if let primary = limit.primary {
                evaluate(limit: limit, windowName: "5h", window: primary)
            }
            if let secondary = limit.secondary {
                evaluate(limit: limit, windowName: "weekly", window: secondary)
            }
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
