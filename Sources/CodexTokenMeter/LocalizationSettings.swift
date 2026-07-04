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
    case apiEquivalent
    case apiEquivalentHint
    case before
    case budget
    case cache
    case cacheHit
    case cacheHitDescription
    case cached
    case claudeStatuslineRequired
    case calendar
    case calendarSubtitle
    case clickForDetails
    case claude
    case claudeCode
    case claudeDescription
    case claudeLogs
    case claudeActiveRefresh
    case claudeActiveRefreshHint
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
    case quotaHomeRingHint
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
    case sourceSplit
    case spark
    case sparkDescription
    case sparkModel
    case statusBarDisplay
    case statusBarSource
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

    var english: String {
        switch self {
        case .about: return "About"
        case .aboutSubtitle: return "How the meter reads and groups local usage"
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
        case .claudeStatuslineRequired: return "Needs statusline"
        case .calendar: return "Calendar"
        case .calendarSubtitle: return "Daily usage intensity over the last year"
        case .clickForDetails: return "Click for details"
        case .claude: return "Claude"
        case .claudeCode: return "Claude Code"
        case .claudeDescription: return "Claude Code local logs"
        case .claudeLogs: return "Claude logs"
        case .claudeActiveRefresh: return "Claude active refresh"
        case .claudeActiveRefreshHint: return "Best effort: when enabled, settings open and a roughly once-per-minute jittered timer can briefly start Claude Code in a background pseudo-terminal and may send a tiny OK probe. It can consume Claude quota; failed refreshes keep the previous value."
        case .codex: return "Codex"
        case .codexAppTotal: return "Codex app total"
        case .codexDescription: return "Codex local logs"
        case .combinedUsage: return "Codex + Claude"
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
        case .cycleTimeMarkerHint: return "Tick marks elapsed time"
        case .cycleNow: return "now"
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
        case .codexHomeRing: return "Codex home ring"
        case .codexStatusUnavailable: return "Status unavailable"
        case .dayValue: return "Day value"
        case .dataSource: return "Data Source"
        case .dataSourceLine1: return "The app reads local Codex logs under ~/.codex and Claude Code logs under ~/.claude/projects."
        case .dataSourceLine2: return "Totals are local-observed token usage, not an official billing export."
        case .definitions: return "Definitions"
        case .detectedNotTracked: return "Detected, not counted"
        case .details: return "Details"
        case .detailsWindowTitle: return "AI Token Meter Details"
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
        case .insights: return "Insights"
        case .insightsSubtitle: return "Find long-running repo threads and context compaction"
        case .japanese: return "Japanese"
        case .language: return "Language"
        case .languageHint: return "Changes apply immediately to the popover and details window."
        case .launchAtLogin: return "Open at Login"
        case .launchAtLoginHint: return "Start AI Token Meter automatically when you sign in."
        case .liveQuota: return "Live quota"
        case .liveLimitUnavailable: return "Live limit unavailable"
        case .logFolder: return "Log Folder"
        case .logFolderHint: return "Default scans sessions and archived_sessions; choosing a folder overrides the scan roots."
        case .logFolderChoose: return "Choose..."
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
        case .quotaHomeRingHint: return "Controls the two large rings on the combined Codex + Claude home page."
        case .quotaViews: return "Usage Sources"
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
        case .sourceSplit: return "Codex / Claude split"
        case .spark: return "Spark"
        case .sparkDescription: return "Events whose model is GPT-5.3-Codex-Spark."
        case .sparkModel: return "GPT-5.3-Codex-Spark model"
        case .statusBarDisplay: return "Menu Bar Display"
        case .statusBarSource: return "Menu Bar Source"
        case .statusDailyTokens: return "24h tokens"
        case .statusDisplayHint: return "Choose what the menu bar item shows and which source it uses."
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
        case .usageIntensityHint: return "Hover a week for 7-day totals; click a day for details"
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
        case .aboutSubtitle: return "本地用量的读取和分组方式"
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
        case .claudeStatuslineRequired: return "需 statusline"
        case .calendar: return "日历"
        case .calendarSubtitle: return "过去一年的每日使用强度"
        case .clickForDetails: return "点击查看详情"
        case .claude: return "Claude"
        case .claudeCode: return "Claude Code"
        case .claudeDescription: return "Claude Code 本地日志"
        case .claudeLogs: return "Claude 日志"
        case .claudeActiveRefresh: return "Claude 主动刷新"
        case .claudeActiveRefreshHint: return "尽力刷新：开启后，打开设置页和约每 1 分钟带抖动的计时器会在后台伪终端短暂启动 Claude Code，必要时发送很小的 OK 探测；会消耗 Claude 额度，失败会保留旧值。"
        case .codex: return "Codex"
        case .codexAppTotal: return "Codex 总用量"
        case .codexDescription: return "Codex 本地日志"
        case .combinedUsage: return "Codex + Claude"
        case .copy: return "复制"
        case .costs: return "金额"
        case .costsSubtitle: return "套餐设置和金额估算"
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
        case .cycleTimeMarkerHint: return "刻度线 = 时间进度"
        case .cycleNow: return "至今"
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
        case .codexHomeRing: return "Codex 首页圆环"
        case .dayValue: return "当日价值"
        case .dataSource: return "数据来源"
        case .dataSourceLine1: return "应用读取 ~/.codex 下的 Codex 日志，以及 ~/.claude/projects 下的 Claude Code 日志。"
        case .dataSourceLine2: return "这里是本地观测到的 token 用量，不是官方账单导出。"
        case .definitions: return "定义"
        case .detectedNotTracked: return "已检测，未计入"
        case .details: return "详情"
        case .detailsWindowTitle: return "AI Token Meter 详情"
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
        case .insights: return "洞察"
        case .insightsSubtitle: return "按项目和文件夹定位长线程"
        case .japanese: return "日语"
        case .language: return "语言"
        case .languageHint: return "切换后会立即应用到弹窗和详情窗口。"
        case .launchAtLogin: return "开机启动"
        case .launchAtLoginHint: return "登录 macOS 后自动启动 AI Token Meter。"
        case .liveQuota: return "实时额度"
        case .liveLimitUnavailable: return "实时限额不可用"
        case .logFolder: return "日志目录"
        case .logFolderHint: return "默认扫描 sessions 和 archived_sessions；手动选择目录会覆盖默认扫描范围。"
        case .logFolderChoose: return "选择..."
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
        case .quotaHomeRingHint: return "控制 Codex + Claude 合并首页上方两个大圆环显示 5小时还是周额度。"
        case .quotaViews: return "用量来源"
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
        case .sourceSplit: return "Codex / Claude 占比"
        case .spark: return "Spark"
        case .sparkDescription: return "模型为 GPT-5.3-Codex-Spark 的事件。"
        case .sparkModel: return "GPT-5.3-Codex-Spark 模型"
        case .statusBarDisplay: return "状态栏显示"
        case .statusBarSource: return "状态栏来源"
        case .statusDailyTokens: return "24h 用量"
        case .statusDisplayHint: return "选择菜单栏里直接展示的指标和它使用的数据来源。"
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
        case .usageIntensityHint: return "悬停整周看 7 天汇总，点击日期看单日明细"
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
        case .aboutSubtitle: return "ローカル使用量の読み取りと分類方法"
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
        case .claudeStatuslineRequired: return "statusline 必要"
        case .calendar: return "カレンダー"
        case .calendarSubtitle: return "過去 1 年の日別使用量"
        case .clickForDetails: return "クリックで詳細"
        case .claude: return "Claude"
        case .claudeCode: return "Claude Code"
        case .claudeDescription: return "Claude Code ローカルログ"
        case .claudeLogs: return "Claude ログ"
        case .claudeActiveRefresh: return "Claude アクティブ更新"
        case .claudeActiveRefreshHint: return "ベストエフォート: 有効時、設定を開いた時と約 1 分ごとの揺らぎ付きタイマーで Claude Code を短時間起動し、小さな OK プローブを送信する場合があります。Claude 制限を消費し、失敗時は前回値を保持します。"
        case .codex: return "Codex"
        case .codexAppTotal: return "Codex 全体使用量"
        case .codexDescription: return "Codex ローカルログ"
        case .combinedUsage: return "Codex + Claude"
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
        case .cycleTimeMarkerHint: return "目盛り = 経過時間"
        case .cycleNow: return "現在"
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
        case .codexHomeRing: return "Codex ホームリング"
        case .dayValue: return "当日の価値"
        case .dataSource: return "データソース"
        case .dataSourceLine1: return "このアプリは ~/.codex の Codex ログと ~/.claude/projects の Claude Code ログを読み取ります。"
        case .dataSourceLine2: return "表示値はローカルで観測した token 使用量であり、公式の請求書エクスポートではありません。"
        case .definitions: return "定義"
        case .detectedNotTracked: return "検出済み・未集計"
        case .details: return "詳細"
        case .detailsWindowTitle: return "AI Token Meter 詳細"
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
        case .logFolderHint: return "既定では sessions と archived_sessions をスキャンし、選択したフォルダは既定の範囲を上書きします。"
        case .logFolderChoose: return "選択..."
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
        case .quotaHomeRingHint: return "Codex + Claude 統合ホーム上部の 2 つのリングに 5h と週のどちらを出すかを選びます。"
        case .quotaViews: return "使用量ソース"
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
        case .sourceSplit: return "Codex / Claude 比率"
        case .spark: return "Spark"
        case .sparkDescription: return "モデルが GPT-5.3-Codex-Spark のイベント。"
        case .sparkModel: return "GPT-5.3-Codex-Spark モデル"
        case .statusBarDisplay: return "メニューバー表示"
        case .statusBarSource: return "メニューバーソース"
        case .statusDailyTokens: return "24h 使用量"
        case .statusDisplayHint: return "メニューバーに表示する指標とソースを選びます。"
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
        case .usageIntensityHint: return "週にホバーで7日集計、日付クリックで日別詳細"
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
    static let codexHomeRingMetricKey = "codexHomeRingMetric"
    static let claudeHomeRingMetricKey = "claudeHomeRingMetric"
    static let statusBarQuotaSourceKey = "statusBarQuotaSource"
    static let claudeActiveQuotaRefreshEnabledKey = "claudeActiveQuotaRefreshEnabled"

    static let fallbackModelLimitID = "codex_bengalfox"
    static let fallbackModelLimitName = "GPT-5.3-Codex-Spark"
    static let defaultCodexMonthlyPlanCost: Double = 200
    static let defaultClaudeMonthlyPlanCost: Double = 125

    static var defaultCodexHomeURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex", isDirectory: true)
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

    static var quotaCycleHistoryURL: URL {
        appSupportDirectoryURL.appendingPathComponent("quota-cycle-history.json")
    }

    static var dashboardReportCacheURL: URL {
        appSupportDirectoryURL.appendingPathComponent("dashboard-report-cache.json")
    }

    static var detailsSnapshotCacheURL: URL {
        appSupportDirectoryURL.appendingPathComponent("details-snapshot-cache.json")
    }

    static var claudeStatuslineCaptureURL: URL {
        appSupportDirectoryURL.appendingPathComponent("claude-statusline.json")
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
        }
    }

    static func setMonthlyPlanCost(_ value: Double, for source: QuotaViewOption) {
        switch source {
        case .all:
            return
        case .codex, .claude:
            guard let key = platformCostKey(monthlyPlanCostKey, source: source) else { return }
            UserDefaults.standard.set(max(0, value), forKey: key)
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
        }
    }

    static func setPaymentCurrency(_ currency: CurrencyCode, for source: QuotaViewOption) {
        switch source {
        case .all:
            paymentCurrency = currency
        case .codex, .claude:
            guard let key = platformCostKey(paymentCurrencyKey, source: source) else { return }
            UserDefaults.standard.set(currency.rawValue, forKey: key)
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
        }
    }

    static func setDisplayCurrency(_ currency: CurrencyCode, for source: QuotaViewOption) {
        switch source {
        case .all:
            displayCurrency = currency
        case .codex, .claude:
            guard let key = platformCostKey(displayCurrencyKey, source: source) else { return }
            UserDefaults.standard.set(currency.rawValue, forKey: key)
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

    static var claudeActiveQuotaRefreshEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: claudeActiveQuotaRefreshEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: claudeActiveQuotaRefreshEnabledKey)
        }
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
