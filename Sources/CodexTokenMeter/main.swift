import Cocoa
import Foundation

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
    case japanese = "ja"

    static let storageKey = "appLanguage"

    static var current: AppLanguage {
        get {
            if let raw = UserDefaults.standard.string(forKey: storageKey),
               let language = AppLanguage(rawValue: raw) {
                return language
            }
            if Locale.preferredLanguages.first?.hasPrefix("zh") == true {
                return .chinese
            }
            if Locale.preferredLanguages.first?.hasPrefix("ja") == true {
                return .japanese
            }
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
        case .japanese: return "日本語"
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

private enum L10nKey {
    case about
    case aboutSubtitle
    case all
    case allDescription
    case budget
    case cache
    case cacheHit
    case cached
    case calendar
    case calendarSubtitle
    case codexAppTotal
    case copy
    case costs
    case costsSubtitle
    case costHistory
    case dayValue
    case dataSource
    case dataSourceLine1
    case dataSourceLine2
    case definitions
    case details
    case detailsWindowTitle
    case displayCurrency
    case dayValueHint
    case displayEquivalent
    case english
    case events
    case fresh
    case inShort
    case input
    case interfaceLanguage
    case japanese
    case language
    case languageHint
    case liveLimitUnavailable
    case logFolder
    case logFolderHint
    case logFolderChoose
    case logFolderDefault
    case logFolderOpen
    case loadingUsageDetails
    case logs
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
    case future
    case noModelLabelForDay
    case noModelLabelsFound
    case nonSparkUsage
    case other
    case otherDefinition
    case otherDescription
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
    case quotaViews
    case quit
    case refresh
    case refreshing
    case remaining
    case showPastEmptyWeeks
    case reset
    case sessions
    case settings
    case settingsSubtitle
    case spark
    case sparkDescription
    case sparkModel
    case statusBarDisplay
    case statusDailyTokens
    case statusDisplayHint
    case statusFiveHourPercent
    case statusWeeklyPercent
    case statusWeeklyTokens
    case tokenMeter
    case total
    case totalSpendValue
    case totalWasteValue
    case totalsObservedNote
    case turns
    case todayValue
    case updated
    case used
    case usageDetails
    case usageIntensityHint
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
    case month
    case fiveHourLeft
    case chinese

    var english: String {
        switch self {
        case .about: return "About"
        case .aboutSubtitle: return "How the meter reads and groups Codex usage"
        case .all: return "All"
        case .allDescription: return "Everything with token detail"
        case .budget: return "Budget"
        case .cache: return "Cache"
        case .cacheHit: return "Cache Hit"
        case .cached: return "Cached"
        case .calendar: return "Calendar"
        case .calendarSubtitle: return "Daily usage intensity over the last year"
        case .codexAppTotal: return "Codex app total"
        case .copy: return "Copy"
        case .costs: return "Costs"
        case .costsSubtitle: return "Plan settings and estimated money usage"
        case .costHistory: return "Spend History"
        case .dayValue: return "Day value"
        case .dataSource: return "Data Source"
        case .dataSourceLine1: return "The app reads local Codex session logs under ~/.codex/sessions and live rate-limit data from the local Codex runtime."
        case .dataSourceLine2: return "Totals are local-observed token usage, not an official billing export."
        case .definitions: return "Definitions"
        case .details: return "Details"
        case .detailsWindowTitle: return "Codex Token Meter Details"
        case .displayCurrency: return "Display currency"
        case .dayValueHint: return "Estimated by converting that day's token usage into money based on your plan price, not official billing."
        case .displayEquivalent: return "Display equivalent"
        case .english: return "English"
        case .events: return "events"
        case .fresh: return "Fresh"
        case .inShort: return "in"
        case .input: return "Input"
        case .interfaceLanguage: return "Interface Language"
        case .japanese: return "Japanese"
        case .language: return "Language"
        case .languageHint: return "Changes apply immediately to the popover and details window."
        case .liveLimitUnavailable: return "Live limit unavailable"
        case .logFolder: return "Log Folder"
        case .logFolderHint: return "Choose the Codex session log folder used for scanning."
        case .logFolderChoose: return "Choose..."
        case .logFolderDefault: return "Default"
        case .logFolderOpen: return "Open"
        case .loadingUsageDetails: return "Loading usage details..."
        case .logs: return "Logs"
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
        case .future: return "Future"
        case .noModelLabelForDay: return "No model label found for this day"
        case .noModelLabelsFound: return "No model labels found in logs"
        case .nonSparkUsage: return "Non-Spark usage"
        case .other: return "Other"
        case .otherDefinition: return "All token-detail events after subtracting the Spark model."
        case .otherDescription: return "All non-Spark models"
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
        case .quotaViews: return "Quota Views"
        case .quit: return "Quit"
        case .refresh: return "Refresh"
        case .refreshing: return "Refreshing..."
        case .remaining: return "Remaining"
        case .showPastEmptyWeeks: return "Show past empty weeks"
        case .reset: return "Reset"
        case .sessions: return "Sessions"
        case .settings: return "Settings"
        case .settingsSubtitle: return "Language and display preferences"
        case .spark: return "Spark"
        case .sparkDescription: return "Events whose model is GPT-5.3-Codex-Spark."
        case .sparkModel: return "GPT-5.3-Codex-Spark model"
        case .statusBarDisplay: return "Menu Bar Display"
        case .statusDailyTokens: return "24h tokens"
        case .statusDisplayHint: return "Choose what the menu bar item shows."
        case .statusFiveHourPercent: return "5h %"
        case .statusWeeklyPercent: return "Weekly %"
        case .statusWeeklyTokens: return "7d tokens"
        case .tokenMeter: return "Token Meter"
        case .total: return "total"
        case .totalSpendValue: return "Total spend"
        case .totalWasteValue: return "Total waste"
        case .totalsObservedNote: return "local-observed usage, not official billing"
        case .turns: return "turns"
        case .todayValue: return "Today value"
        case .updated: return "Updated"
        case .used: return "Used"
        case .usageDetails: return "Usage Details"
        case .usageIntensityHint: return "darker means more token usage"
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
        case .budget: return "预算"
        case .cache: return "缓存"
        case .cacheHit: return "缓存命中"
        case .cached: return "缓存"
        case .calendar: return "日历"
        case .calendarSubtitle: return "过去一年的每日使用强度"
        case .codexAppTotal: return "Codex 总用量"
        case .copy: return "复制"
        case .costs: return "金额"
        case .costsSubtitle: return "套餐设置和金额估算"
        case .costHistory: return "金额历史"
        case .dayValue: return "当日价值"
        case .dataSource: return "数据来源"
        case .dataSourceLine1: return "应用读取 ~/.codex/sessions 下的本地 Codex 会话日志，以及本地 Codex 运行时的实时限额。"
        case .dataSourceLine2: return "这里是本地观测到的 token 用量，不是官方账单导出。"
        case .definitions: return "定义"
        case .details: return "详情"
        case .detailsWindowTitle: return "Codex Token Meter 详情"
        case .displayCurrency: return "展示币种"
        case .dayValueHint: return "按你的套餐价格，把当天 token 开销折算成金额的估算值，不是官方账单。"
        case .displayEquivalent: return "展示折合"
        case .english: return "英语"
        case .events: return "事件"
        case .fresh: return "新输入"
        case .inShort: return "输入"
        case .input: return "输入"
        case .interfaceLanguage: return "界面语言"
        case .japanese: return "日语"
        case .language: return "语言"
        case .languageHint: return "切换后会立即应用到弹窗和详情窗口。"
        case .liveLimitUnavailable: return "实时限额不可用"
        case .logFolder: return "日志目录"
        case .logFolderHint: return "选择用于扫描的 Codex 会话日志目录。"
        case .logFolderChoose: return "选择..."
        case .logFolderDefault: return "默认"
        case .logFolderOpen: return "打开"
        case .loadingUsageDetails: return "正在加载用量详情..."
        case .logs: return "日志"
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
        case .future: return "未来"
        case .noModelLabelForDay: return "这一天没有模型标签"
        case .noModelLabelsFound: return "日志中没有模型标签"
        case .nonSparkUsage: return "非 Spark 用量"
        case .other: return "其他"
        case .otherDefinition: return "全部 token 明细减去 Spark 模型后的记录。"
        case .otherDescription: return "全部非 Spark 模型"
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
        case .quotaViews: return "限额视图"
        case .quit: return "退出"
        case .refresh: return "刷新"
        case .refreshing: return "刷新中..."
        case .remaining: return "剩余"
        case .showPastEmptyWeeks: return "显示以前的无数据周"
        case .reset: return "重置"
        case .sessions: return "会话"
        case .settings: return "设置"
        case .settingsSubtitle: return "语言和显示偏好"
        case .spark: return "Spark"
        case .sparkDescription: return "模型为 GPT-5.3-Codex-Spark 的事件。"
        case .sparkModel: return "GPT-5.3-Codex-Spark 模型"
        case .statusBarDisplay: return "状态栏显示"
        case .statusDailyTokens: return "24h 用量"
        case .statusDisplayHint: return "选择菜单栏里直接展示的指标。"
        case .statusFiveHourPercent: return "5h 百分比"
        case .statusWeeklyPercent: return "周百分比"
        case .statusWeeklyTokens: return "7d 用量"
        case .tokenMeter: return "Token 统计"
        case .total: return "总计"
        case .totalSpendValue: return "总开销"
        case .totalWasteValue: return "总浪费"
        case .totalsObservedNote: return "本地观测用量，非官方账单"
        case .turns: return "轮次"
        case .todayValue: return "今日价值"
        case .updated: return "已更新"
        case .used: return "已用"
        case .usageDetails: return "用量详情"
        case .usageIntensityHint: return "颜色越深代表 token 用量越高"
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
        case .budget: return "予算"
        case .cache: return "キャッシュ"
        case .cacheHit: return "キャッシュ率"
        case .cached: return "キャッシュ"
        case .calendar: return "カレンダー"
        case .calendarSubtitle: return "過去 1 年の日別使用量"
        case .codexAppTotal: return "Codex 全体使用量"
        case .copy: return "コピー"
        case .costs: return "金額"
        case .costsSubtitle: return "プラン設定と金額推定"
        case .costHistory: return "金額履歴"
        case .dayValue: return "当日の価値"
        case .dataSource: return "データソース"
        case .dataSourceLine1: return "このアプリは ~/.codex/sessions のローカル Codex セッションログと、ローカル実行環境のリアルタイム制限を読み取ります。"
        case .dataSourceLine2: return "表示値はローカルで観測した token 使用量であり、公式の請求書エクスポートではありません。"
        case .definitions: return "定義"
        case .details: return "詳細"
        case .detailsWindowTitle: return "Codex Token Meter 詳細"
        case .displayCurrency: return "表示通貨"
        case .dayValueHint: return "プラン料金を基準に、その日の token 使用量を金額換算した推定値であり、公式請求ではありません。"
        case .displayEquivalent: return "表示換算"
        case .english: return "英語"
        case .events: return "イベント"
        case .fresh: return "新規入力"
        case .inShort: return "入力"
        case .input: return "入力"
        case .interfaceLanguage: return "表示言語"
        case .japanese: return "日本語"
        case .language: return "言語"
        case .languageHint: return "変更はポップオーバーと詳細ウィンドウにすぐ反映されます。"
        case .liveLimitUnavailable: return "リアルタイム制限を取得できません"
        case .logFolder: return "ログフォルダ"
        case .logFolderHint: return "スキャンに使う Codex セッションログのフォルダを選択します。"
        case .logFolderChoose: return "選択..."
        case .logFolderDefault: return "既定"
        case .logFolderOpen: return "開く"
        case .loadingUsageDetails: return "使用量の詳細を読み込み中..."
        case .logs: return "ログ"
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
        case .future: return "未来"
        case .noModelLabelForDay: return "この日のモデル名は見つかりません"
        case .noModelLabelsFound: return "ログ内にモデル名が見つかりません"
        case .nonSparkUsage: return "Spark 以外の使用量"
        case .other: return "その他"
        case .otherDefinition: return "Spark モデルを除いた token 詳細イベント。"
        case .otherDescription: return "Spark 以外のすべてのモデル"
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
        case .quotaViews: return "制限枠ビュー"
        case .quit: return "終了"
        case .refresh: return "更新"
        case .refreshing: return "更新中..."
        case .remaining: return "残り"
        case .showPastEmptyWeeks: return "過去の空週を表示"
        case .reset: return "リセット"
        case .sessions: return "セッション"
        case .settings: return "設定"
        case .settingsSubtitle: return "言語と表示設定"
        case .spark: return "Spark"
        case .sparkDescription: return "モデルが GPT-5.3-Codex-Spark のイベント。"
        case .sparkModel: return "GPT-5.3-Codex-Spark モデル"
        case .statusBarDisplay: return "メニューバー表示"
        case .statusDailyTokens: return "24h 使用量"
        case .statusDisplayHint: return "メニューバーに表示する指標を選びます。"
        case .statusFiveHourPercent: return "5h %"
        case .statusWeeklyPercent: return "週 %"
        case .statusWeeklyTokens: return "7日使用量"
        case .tokenMeter: return "Token メーター"
        case .total: return "合計"
        case .totalSpendValue: return "総支出"
        case .totalWasteValue: return "総浪費"
        case .totalsObservedNote: return "ローカル観測値であり公式請求ではありません"
        case .turns: return "ターン"
        case .todayValue: return "今日の価値"
        case .updated: return "更新"
        case .used: return "使用済み"
        case .usageDetails: return "使用量詳細"
        case .usageIntensityHint: return "色が濃いほど token 使用量が多い"
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

    static var defaultLogFolderURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/sessions", isDirectory: true)
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
}

enum QuotaViewOption: String, CaseIterable {
    case all = "codex"
    case spark
    case other

    var scanLimitID: String? {
        switch self {
        case .all, .other: return nil
        case .spark: return "codex_bengalfox"
        }
    }

    var excludedScanLimitID: String? {
        switch self {
        case .all, .spark: return nil
        case .other: return "codex_bengalfox"
        }
    }

    var includedModelName: String? {
        switch self {
        case .spark: return "gpt-5.3-codex-spark"
        case .all, .other: return nil
        }
    }

    var excludedModelName: String? {
        switch self {
        case .other: return "gpt-5.3-codex-spark"
        case .all, .spark: return nil
        }
    }

    var liveLimitID: String {
        switch self {
        case .all, .other: return "codex"
        case .spark: return "codex_bengalfox"
        }
    }

    var shortTitle: String {
        switch self {
        case .all: return t(.all)
        case .spark: return t(.spark)
        case .other: return t(.other)
        }
    }

    var fallbackTitle: String {
        switch self {
        case .all: return t(.codexAppTotal)
        case .spark: return "GPT-5.3-Codex-Spark"
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

struct LiveRateLimit {
    let id: String
    let name: String
    let primary: RateWindow
    let secondary: RateWindow
    let planType: String?
}

struct DashboardState {
    var report = TokenReport()
    var costReferenceReport: TokenReport?
    var liveLimits: [LiveRateLimit] = []
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

private enum CostHistoryWindow: CaseIterable {
    case week
    case month

    var title: String {
        switch self {
        case .week: return t(.week)
        case .month: return t(.month)
        }
    }
}

struct CostPeriodRow {
    let label: String
    let title: String
    let subtitle: String?
    let usedValue: Double
    let remainingValue: Double
    let budgetValue: Double
    let hasData: Bool
    let isFuture: Bool

    var usedPercent: Double {
        guard budgetValue > 0 else { return 0 }
        return min(999, max(0, usedValue / budgetValue * 100))
    }
}

struct ReportCacheKey: Hashable {
    let window: WindowOption
    let quota: QuotaViewOption
}

final class CodexTokenScanner {
    private struct FileCache {
        let size: Int64
        let modifiedAt: Date
        let events: [TokenEvent]
        let turns: [Date]
    }

    private struct DiskFileCache: Codable {
        let version: Int
        let path: String
        let size: Int64
        let modifiedAt: Double
        let events: [TokenEvent]
        let turns: [Date]
    }

    private let rootURL: URL
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

    init(rootURL: URL) {
        self.rootURL = rootURL
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

    private func scan(start: Date, now: Date, limitID: String?, excludedLimitID: String?, includedModelName: String?, excludedModelName: String?, fillDayCount: Int?) -> TokenReport {
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

    private func modelDisplayName(for event: TokenEvent) -> String {
        if let model = event.model, !model.isEmpty {
            return model
        }
        if event.limitID == "codex_bengalfox" {
            return "GPT-5.3-Codex-Spark"
        }
        if let limitName = event.limitName, limitName.contains("GPT-5.3-Codex-Spark") {
            return "GPT-5.3-Codex-Spark"
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
        return normalizedModelName(for: event) == modelName.lowercased()
    }

    private func matchesExcludedModel(_ event: TokenEvent, modelName: String?) -> Bool {
        guard let modelName else { return false }
        return normalizedModelName(for: event) == modelName.lowercased()
    }

    private func normalizedModelName(for event: TokenEvent) -> String {
        modelDisplayName(for: event).lowercased()
    }

    private func rolloutFiles(modifiedSince start: Date) -> [URL] {
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
        let file = FileCache(size: size, modifiedAt: modifiedAt, events: parsed.events, turns: parsed.turns)
        cache[key] = file
        writeDiskCache(file, fileURL: fileURL)
        return file
    }

    private func readDiskCache(fileURL: URL, size: Int64, modifiedAt: Date) -> FileCache? {
        let url = diskCacheURL(for: fileURL)
        guard let data = try? Data(contentsOf: url),
              let disk = try? jsonDecoder.decode(DiskFileCache.self, from: data),
            disk.version == 2,
              disk.path == fileURL.path,
              disk.size == size,
              abs(disk.modifiedAt - modifiedAt.timeIntervalSinceReferenceDate) < 0.001 else {
            return nil
        }
        return FileCache(size: disk.size, modifiedAt: modifiedAt, events: disk.events, turns: disk.turns)
    }

    private func writeDiskCache(_ file: FileCache, fileURL: URL) {
        let disk = DiskFileCache(
            version: 2,
            path: fileURL.path,
            size: file.size,
            modifiedAt: file.modifiedAt.timeIntervalSinceReferenceDate,
            events: file.events,
            turns: file.turns
        )
        guard let data = try? jsonEncoder.encode(disk) else { return }
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: diskCacheURL(for: fileURL), options: [.atomic])
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
    func read(timeout: TimeInterval = 8) -> [LiveRateLimit] {
        guard let codexPath = codexExecutablePath() else {
            return []
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server"]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }

        let writer = input.fileHandleForWriting
        let messages = [
            #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"codex-token-meter","version":"0.2.0"},"capabilities":{}}}"#,
            #"{"method":"initialized"}"#,
            #"{"id":2,"method":"account/rateLimits/read"}"#
        ]
        DispatchQueue.global(qos: .utility).async {
            for message in messages {
                if let data = (message + "\n").data(using: .utf8) {
                    try? writer.write(contentsOf: data)
                }
                Thread.sleep(forTimeInterval: 0.35)
            }
            Thread.sleep(forTimeInterval: 4.5)
            try? writer.close()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.2)
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return parse(text)
    }

    private func codexExecutablePath() -> String? {
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
                  let id = object["id"] as? Int,
                  id == 2,
                  let result = object["result"] as? [String: Any] else {
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

final class RingView: NSView {
    var percent: Double = 0 { didSet { needsDisplay = true } }
    var title: String = "" { didSet { needsDisplay = true } }
    var subtitle: String = "" { didSet { needsDisplay = true } }
    var color: NSColor = NSColor.systemGreen { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let bounds = self.bounds.insetBy(dx: 8, dy: 8)
        let diameter = min(bounds.width, bounds.height - 20)
        let rect = NSRect(x: bounds.midX - diameter / 2, y: bounds.minY, width: diameter, height: diameter)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = diameter / 2 - 8
        let lineWidth: CGFloat = 8
        let start = -CGFloat.pi * 0.82
        let end = CGFloat.pi * 0.82

        NSColor.white.withAlphaComponent(0.10).setStroke()
        let bg = NSBezierPath()
        bg.lineWidth = lineWidth
        bg.lineCapStyle = .round
        bg.appendArc(withCenter: center, radius: radius, startAngle: start * 180 / .pi, endAngle: end * 180 / .pi, clockwise: false)
        bg.stroke()

        color.setStroke()
        let fg = NSBezierPath()
        fg.lineWidth = lineWidth
        fg.lineCapStyle = .round
        let clamped = max(0, min(100, percent)) / 100
        fg.appendArc(withCenter: center, radius: radius, startAngle: start * 180 / .pi, endAngle: (start + (end - start) * clamped) * 180 / .pi, clockwise: false)
        fg.stroke()

        let pText = "\(Int(round(percent)))%"
        drawCenteredAt(pText, center: center, font: .systemFont(ofSize: 22, weight: .bold), color: .white)
        drawCentered(title, rect: NSRect(x: bounds.minX, y: rect.maxY + 2, width: bounds.width, height: 18), font: .systemFont(ofSize: 13, weight: .semibold), color: NSColor.white.withAlphaComponent(0.86))
        drawCentered(subtitle, rect: NSRect(x: bounds.minX, y: rect.maxY + 20, width: bounds.width, height: 16), font: .systemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.45))
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

final class UsageChartView: NSView {
    var selectedWindow: WindowOption = .week { didSet { needsDisplay = true } }
    var days: [DayUsage] = [] { didSet { hoveredIndex = nil; needsDisplay = true } }
    var hours: [HourUsage] = [] { didSet { hoveredIndex = nil; needsDisplay = true } }
    var weeklyQuotaUsedPercent: Double? { didSet { needsDisplay = true } }
    var weeklyQuotaReferenceTotal: Int64? { didSet { needsDisplay = true } }
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
            drawHourlyLine()
        } else {
            drawDailyBars()
        }
        drawHoverTooltip()
    }

    private func drawHourlyLine() {
        guard !hours.isEmpty else { return }
        let plot = bounds.insetBy(dx: 12, dy: 10)
        let labelHeight: CGFloat = 16
        let chart = NSRect(x: plot.minX, y: plot.minY, width: plot.width, height: plot.height - labelHeight)
        let series = continuousHours()
        let maxTotal = max(series.map { $0.usage.total }.max() ?? 1, 1)
        let points = series.enumerated().map { index, hour -> CGPoint in
            let x = chart.minX + (series.count == 1 ? chart.width : CGFloat(index) / CGFloat(series.count - 1) * chart.width)
            let ratio = CGFloat(Double(hour.usage.total) / Double(maxTotal))
            let y = chart.maxY - max(2, chart.height * ratio)
            return CGPoint(x: x, y: y)
        }

        let fillPath = NSBezierPath()
        if let first = points.first {
            fillPath.move(to: CGPoint(x: first.x, y: chart.maxY))
            fillPath.line(to: first)
            for point in points.dropFirst() {
                fillPath.line(to: point)
            }
            if let last = points.last {
                fillPath.line(to: CGPoint(x: last.x, y: chart.maxY))
            }
            fillPath.close()
            NSColor.systemGreen.withAlphaComponent(0.18).setFill()
            fillPath.fill()
        }

        let linePath = NSBezierPath()
        if let first = points.first {
            linePath.move(to: first)
            for point in points.dropFirst() {
                linePath.line(to: point)
            }
            linePath.lineWidth = 2.2
            NSColor.systemGreen.setStroke()
            linePath.stroke()
        }

        if let hoveredIndex, points.indices.contains(hoveredIndex) {
            let point = points[hoveredIndex]
            NSColor.systemGreen.setFill()
            NSBezierPath(ovalIn: NSRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)).fill()
            NSColor.white.withAlphaComponent(0.65).setStroke()
            let guide = NSBezierPath()
            guide.lineWidth = 1
            guide.move(to: CGPoint(x: point.x, y: chart.minY))
            guide.line(to: CGPoint(x: point.x, y: chart.maxY))
            guide.stroke()
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "HH:mm"
        let labels = [(0, series.first?.hour), (series.count / 2, series.indices.contains(series.count / 2) ? series[series.count / 2].hour : nil), (max(0, series.count - 1), series.last?.hour)]
        for (index, date) in labels {
            guard let date else { continue }
            let x = chart.minX + (series.count == 1 ? chart.width : CGFloat(index) / CGFloat(max(1, series.count - 1)) * chart.width)
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
        guard chart.insetBy(dx: 6, dy: 0).contains(point) else { return clearHoverIfNeeded() }

        let ratio = max(0, min(1, (point.x - chart.minX) / max(1, chart.width)))
        let index = Int(round(ratio * CGFloat(max(1, series.count - 1))))
        hoveredIndex = min(max(index, 0), series.count - 1)
        hoverPoint = point
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
        if let weeklyQuotaPercent = weeklyQuotaShare(for: usage) {
            lines.append("\(t(.weeklyQuotaShare))   \(String(format: "%.1f%%", weeklyQuotaPercent))")
        } else if let visibleWeekPercent = visibleWeekShare(for: usage) {
            lines.append("\(t(.visibleWeekShare)) \(String(format: "%.1f%%", visibleWeekPercent))")
        }
        if let paymentValue = paymentValueForDayUsage(usage, weeklyQuotaUsedPercent: weeklyQuotaUsedPercent, weeklyQuotaReferenceTotal: weeklyQuotaReferenceTotal) {
            lines.append("\(t(.dayValue))  \(displayMoney(paymentValue))")
        }

        let width: CGFloat = 214
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

    private func visibleWeekShare(for usage: Usage) -> Double? {
        guard selectedWindow == .week else { return nil }
        let visibleTotal = days.reduce(Int64(0)) { $0 + $1.usage.total }
        guard usage.total > 0, visibleTotal > 0 else { return nil }
        return Double(usage.total) / Double(visibleTotal) * 100
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

final class DashboardView: NSView {
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
    private let dayChart = UsageChartView()
    private let sessionsLabel = NSTextField(labelWithString: "")
    private let buttonsStack = NSStackView()
    private var buttonsByKey: [L10nKey: NSButton] = [:]

    var onWindowChanged: ((WindowOption) -> Void)?
    var onQuotaChanged: ((QuotaViewOption) -> Void)?
    var onRefresh: (() -> Void)?
    var onCopy: (() -> Void)?
    var onOpenDetails: (() -> Void)?
    var onOpenLogs: (() -> Void)?
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

    func update(_ state: DashboardState) {
        self.state = state
        let report = state.report
        applyLanguage()
        titleLabel.stringValue = "Codex Token Meter"
        let displayLimit = selectedLimit(from: state.liveLimits, quota: state.selectedQuota)
        subtitleLabel.stringValue = state.selectedQuota.fallbackTitle
        totalLabel.stringValue = compact(report.usage.total)
        detailLabel.stringValue = state.selectedWindow.title
        usageLabel.stringValue = "\(compact(report.usage.input)) \(t(.inShort))  |  \(compact(report.usage.output)) \(t(.outShort))"
        refreshLabel.stringValue = state.isLoading ? t(.refreshing) : "\(t(.updated)) \(relative(report.scannedAt))  |  \(t(.next)) \(relative(state.nextRefreshAt))"

        quotaSegment.selectedSegment = QuotaViewOption.allCases.firstIndex(of: state.selectedQuota) ?? 0
        segment.selectedSegment = WindowOption.allCases.firstIndex(of: state.selectedWindow) ?? 1

        let primary = displayLimit?.primary
        let weekly = displayLimit?.secondary
        primaryRing.percent = primary?.remainingPercent ?? 0
        primaryRing.title = t(.fiveHourLeft)
        primaryRing.subtitle = primary.map { "\(t(.reset)) \(relative($0.resetsAt))" } ?? t(.liveLimitUnavailable)
        primaryRing.color = colorForRemaining(percent: primaryRing.percent)

        weeklyRing.percent = weekly?.remainingPercent ?? 0
        weeklyRing.title = t(.weeklyLeft)
        weeklyRing.subtitle = weekly.map { "\(t(.reset)) \(relative($0.resetsAt))" } ?? t(.usageWindow)
        weeklyRing.color = colorForRemaining(percent: weeklyRing.percent)

        cacheRing.percent = report.usage.cachePercent
        cacheRing.title = t(.cacheHit)
        cacheRing.subtitle = "\(compact(report.usage.freshInput)) \(t(.fresh).lowercased())"
        cacheRing.color = NSColor.systemTeal

        dayChart.selectedWindow = state.selectedWindow
        dayChart.days = report.byDay
        dayChart.hours = report.byHour
        dayChart.weeklyQuotaUsedPercent = state.selectedWindow == .day ? nil : weekly?.usedPercent
        dayChart.weeklyQuotaReferenceTotal = state.selectedWindow == .day ? nil : report.byDay.suffix(7).reduce(Int64(0)) { $0 + $1.usage.total }
        sessionsLabel.stringValue = "\(t(.sessions)) \(report.sessions)   \(t(.turns)) \(report.turns)   \(t(.events)) \(report.events)"
        if let estimate = planCostEstimate(report: state.costReferenceReport ?? report, selectedDay: nil, limit: displayLimit) {
            costLabel.stringValue = "\(t(.weeklyUnusedValue)) \(displayMoney(estimate.weeklyUnusedValue))"
        } else {
            costLabel.stringValue = t(.planCostUnavailable)
        }
        needsDisplay = true
    }

    func applyLanguage() {
        for (index, option) in QuotaViewOption.allCases.enumerated() {
            quotaSegment.setLabel(option.shortTitle, forSegment: index)
        }
        for (index, option) in WindowOption.allCases.enumerated() {
            segment.setLabel(option.shortTitle, forSegment: index)
        }
        buttonsByKey[.refresh]?.title = t(.refresh)
        buttonsByKey[.copy]?.title = t(.copy)
        buttonsByKey[.details]?.title = t(.details)
        buttonsByKey[.logs]?.title = t(.logs)
        buttonsByKey[.quit]?.title = t(.quit)
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
        let content = bounds.insetBy(dx: 28, dy: 24)
        logoImageView.frame = NSRect(x: content.minX, y: content.minY + 2, width: 22, height: 22)
        titleLabel.frame = NSRect(x: content.minX + 28, y: content.minY, width: 250, height: 28)
        subtitleLabel.frame = NSRect(x: content.minX + 28, y: content.minY + 30, width: 248, height: 18)
        totalLabel.frame = NSRect(x: content.maxX - 172, y: content.minY, width: 162, height: 36)
        detailLabel.frame = NSRect(x: content.maxX - 172, y: content.minY + 37, width: 162, height: 16)
        quotaSegment.frame = NSRect(x: content.minX, y: content.minY + 52, width: 216, height: 24)
        usageLabel.frame = NSRect(x: content.minX + 228, y: content.minY + 55, width: content.width - 228, height: 16)
        segment.frame = NSRect(x: content.minX, y: content.minY + 82, width: content.width, height: 30)

        let ringY = content.minY + 132
        let ringW = (content.width - 24) / 3
        primaryRing.frame = NSRect(x: content.minX, y: ringY, width: ringW, height: 136)
        weeklyRing.frame = NSRect(x: content.minX + ringW + 12, y: ringY, width: ringW, height: 136)
        cacheRing.frame = NSRect(x: content.minX + (ringW + 12) * 2, y: ringY, width: ringW, height: 136)

        let statsY = ringY + 154
        dayChart.frame = NSRect(x: content.minX, y: statsY, width: content.width, height: 118)
        sessionsLabel.frame = NSRect(x: content.minX, y: statsY + 128, width: content.width, height: 18)
        costLabel.frame = NSRect(x: content.minX, y: statsY + 152, width: content.width, height: 16)
        refreshLabel.frame = NSRect(x: content.minX, y: content.maxY - 58, width: content.width, height: 18)
        buttonsStack.frame = NSRect(x: content.minX, y: content.maxY - 36, width: content.width, height: 28)
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

        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .white
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.46)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        totalLabel.font = .monospacedDigitSystemFont(ofSize: 30, weight: .bold)
        totalLabel.alignment = .right
        totalLabel.textColor = NSColor.systemGreen
        detailLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        detailLabel.alignment = .right
        detailLabel.textColor = NSColor.white.withAlphaComponent(0.45)
        usageLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        usageLabel.alignment = .center
        usageLabel.textColor = NSColor.white.withAlphaComponent(0.34)
        refreshLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        refreshLabel.textColor = NSColor.white.withAlphaComponent(0.36)
        sessionsLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        sessionsLabel.textColor = NSColor.white.withAlphaComponent(0.44)
        costLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        costLabel.textColor = NSColor.white.withAlphaComponent(0.50)

        quotaSegment.target = self
        quotaSegment.action = #selector(quotaSegmentChanged)
        quotaSegment.segmentStyle = .rounded
        addSubview(quotaSegment)

        segment.target = self
        segment.action = #selector(segmentChanged)
        segment.segmentStyle = .rounded
        addSubview(segment)

        [primaryRing, weeklyRing, cacheRing, dayChart].forEach { addSubview($0) }

        buttonsStack.orientation = .horizontal
        buttonsStack.spacing = 8
        buttonsStack.distribution = .fillEqually
        addSubview(buttonsStack)
        addButton(.refresh, action: #selector(refreshTapped))
        addButton(.copy, action: #selector(copyTapped))
        addButton(.details, action: #selector(detailsTapped))
        addButton(.logs, action: #selector(logsTapped))
        addButton(.quit, action: #selector(quitTapped))
        applyLanguage()
    }

    private func addButton(_ titleKey: L10nKey, action: Selector) {
        let button = NSButton(title: t(titleKey), target: self, action: action)
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        buttonsByKey[titleKey] = button
        buttonsStack.addArrangedSubview(button)
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
        limits.first { $0.id == quota.liveLimitID }
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
    @objc private func copyTapped() { onCopy?() }
    @objc private func detailsTapped() { onOpenDetails?() }
    @objc private func logsTapped() { onOpenLogs?() }
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
}

final class DashboardViewController: NSViewController {
    let dashboardView = DashboardView(frame: NSRect(x: 0, y: 0, width: 430, height: 560))

    override func loadView() {
        view = dashboardView
        preferredContentSize = dashboardView.frame.size
    }
}

struct DetailsSnapshot {
    var all: TokenReport
    var spark: TokenReport
    var other: TokenReport
    var liveLimits: [LiveRateLimit]
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
    case about

    var title: String {
        switch self {
        case .overview: return t(.overview)
        case .models: return t(.models)
        case .calendar: return t(.calendar)
        case .costs: return t(.costs)
        case .settings: return t(.settings)
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
        case .about: return t(.aboutSubtitle)
        }
    }
}

final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    private func centeredRect(for bounds: NSRect) -> NSRect {
        let horizontalPadding: CGFloat = 12
        let measuredHeight = ceil(cellSize(forBounds: bounds).height)
        return NSRect(
            x: bounds.minX + horizontalPadding,
            y: bounds.minY + max(0, floor((bounds.height - measuredHeight) / 2)),
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
    var snapshot: DetailsSnapshot? {
        didSet {
            if let report = snapshot?.all {
                selectedDay = preferredSelectedDay(in: report, fallback: selectedDay)
            }
            onPreferredHeightChanged?()
            needsDisplay = true
            needsLayout = true
        }
    }
    var isLoading = false { didSet { onPreferredHeightChanged?(); needsDisplay = true; needsLayout = true } }
    fileprivate var onLanguageChanged: ((AppLanguage) -> Void)?
    fileprivate var onStatusDisplayChanged: ((StatusDisplayOption) -> Void)?
    fileprivate var onPlanCostChanged: ((Double) -> Void)?
    fileprivate var onPaymentStartDayChanged: ((String) -> Void)?
    fileprivate var onPaymentCurrencyChanged: ((CurrencyCode) -> Void)?
    fileprivate var onDisplayCurrencyChanged: ((CurrencyCode) -> Void)?
    fileprivate var onChooseLogFolder: (() -> Void)?
    fileprivate var onResetLogFolder: (() -> Void)?
    fileprivate var onOpenLogFolder: (() -> Void)?
    fileprivate var onShowHistoricalEmptyWeeksChanged: ((Bool) -> Void)?
    fileprivate var onPreferredHeightChanged: (() -> Void)?
    private var selectedSection: DetailsSection = .overview {
        didSet {
            if selectedSection != .costs {
                hoveredCostHistoryIndex = nil
            }
            onPreferredHeightChanged?()
            needsDisplay = true
            needsLayout = true
        }
    }
    private var sidebarItemRects: [DetailsSection: NSRect] = [:]
    private var languageOptionRects: [AppLanguage: NSRect] = [:]
    private var statusOptionRects: [StatusDisplayOption: NSRect] = [:]
    private var costWindowRects: [CostHistoryWindow: NSRect] = [:]
    private var chooseLogFolderRect: NSRect?
    private var resetLogFolderRect: NSRect?
    private var openLogFolderRect: NSRect?
    private var contributionDayRects: [String: NSRect] = [:]
    private var costHistoryBarRects: [Int: NSRect] = [:]
    private var costHistoryRows: [CostPeriodRow] = []
    private var dayValueInfoRect: NSRect?
    private var selectedDay: String?
    private var hoveredCostHistoryIndex: Int?
    private var isHoveringDayValueInfo = false
    private var selectedCostWindow: CostHistoryWindow = .week
    private var selectedCostYear = Calendar.current.component(.year, from: Date())
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
    private let costWindowSegment = NSSegmentedControl(labels: CostHistoryWindow.allCases.map { $0.title }, trackingMode: .selectOne, target: nil, action: nil)
    private let costMonthPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let costYearPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let showHistoricalEmptyWeeksButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private var isUpdatingCostControls = false
    private var detailsTrackingArea: NSTrackingArea?
    private var selectedCostMonth: Int?

    private var visibleCostControlFrames: [NSRect] {
        guard selectedSection == .costs else { return [] }
        var frames: [NSRect] = [costWindowSegment.frame, costYearPopup.frame]
        if !costMonthPopup.isHidden {
            frames.append(costMonthPopup.frame)
        }
        if !showHistoricalEmptyWeeksButton.isHidden {
            frames.append(showHistoricalEmptyWeeksButton.frame)
        }
        return frames.filter { !$0.isEmpty }
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
        costAmountField.drawsBackground = true
        costAmountField.focusRingType = .none
        costAmountField.font = .monospacedDigitSystemFont(ofSize: 18, weight: .bold)
        costAmountField.alignment = .center
        costAmountField.textColor = .white
        costAmountField.backgroundColor = NSColor.black.withAlphaComponent(0.14)
        costAmountField.usesSingleLineMode = true
        costAmountField.lineBreakMode = .byTruncatingTail
        costAmountField.delegate = self
        costAmountField.isHidden = true
        addSubview(costAmountField)

        paymentStartDayField.isBordered = false
        paymentStartDayField.drawsBackground = true
        paymentStartDayField.focusRingType = .none
        paymentStartDayField.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        paymentStartDayField.alignment = .center
        paymentStartDayField.textColor = .white
        paymentStartDayField.backgroundColor = NSColor.black.withAlphaComponent(0.14)
        paymentStartDayField.usesSingleLineMode = true
        paymentStartDayField.lineBreakMode = .byTruncatingTail
        paymentStartDayField.delegate = self
        paymentStartDayField.isHidden = true
        addSubview(paymentStartDayField)

        costWindowSegment.segmentStyle = .rounded
        costWindowSegment.controlSize = .regular
        costWindowSegment.font = .systemFont(ofSize: 12, weight: .semibold)
        costWindowSegment.isHidden = true
        costWindowSegment.target = self
        costWindowSegment.action = #selector(costWindowSegmentChanged)
        addSubview(costWindowSegment)

        showHistoricalEmptyWeeksButton.setButtonType(.switch)
        showHistoricalEmptyWeeksButton.font = .systemFont(ofSize: 12, weight: .semibold)
        showHistoricalEmptyWeeksButton.contentTintColor = .white
        showHistoricalEmptyWeeksButton.isBordered = false
        showHistoricalEmptyWeeksButton.imagePosition = .imageLeading
        showHistoricalEmptyWeeksButton.isHidden = true
        showHistoricalEmptyWeeksButton.target = self
        showHistoricalEmptyWeeksButton.action = #selector(showHistoricalEmptyWeeksChanged)
        addSubview(showHistoricalEmptyWeeksButton)

        for popup in [paymentCurrencyPopup, displayCurrencyPopup, costMonthPopup, costYearPopup] {
            popup.controlSize = .regular
            popup.font = .systemFont(ofSize: 12, weight: .semibold)
            popup.isBordered = false
            popup.isHidden = true
            popup.wantsLayer = true
            popup.layer?.cornerRadius = 8
            popup.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.14).cgColor
            popup.appearance = NSAppearance(named: .darkAqua)
            addSubview(popup)
        }
        paymentCurrencyPopup.removeAllItems()
        paymentCurrencyPopup.addItems(withTitles: CurrencyCode.allCases.map(\.displayTitle))
        displayCurrencyPopup.removeAllItems()
        displayCurrencyPopup.addItems(withTitles: CurrencyCode.allCases.map(\.displayTitle))
        costYearPopup.removeAllItems()
        paymentCurrencyPopup.target = self
        paymentCurrencyPopup.action = #selector(paymentCurrencyPopupChanged)
        displayCurrencyPopup.target = self
        displayCurrencyPopup.action = #selector(displayCurrencyPopupChanged)
        costMonthPopup.target = self
        costMonthPopup.action = #selector(costMonthPopupChanged)
        costYearPopup.target = self
        costYearPopup.action = #selector(costYearPopupChanged)
    }

    private func layoutCostControls() {
        let visible = selectedSection == .costs
        costAmountField.isHidden = !visible
        paymentStartDayField.isHidden = !visible
        paymentCurrencyPopup.isHidden = !visible
        displayCurrencyPopup.isHidden = !visible
        costWindowSegment.isHidden = !visible
        costMonthPopup.isHidden = !visible || selectedCostWindow != .week
        costYearPopup.isHidden = !visible
        showHistoricalEmptyWeeksButton.isHidden = !visible
        guard visible else { return }

        let content = NSRect(x: 220 + 28, y: 28, width: bounds.width - 220 - 56, height: bounds.height - 56)
        let settingsRect = NSRect(x: content.minX, y: content.minY + 78, width: content.width, height: 286)
        let controlWidth = min(300, max(252, settingsRect.width * 0.34))
        let controlX = settingsRect.maxX - controlWidth - 16
        costAmountField.frame = NSRect(x: controlX, y: settingsRect.minY + 34, width: controlWidth, height: 44)
        paymentStartDayField.frame = NSRect(x: controlX, y: settingsRect.minY + 86, width: controlWidth, height: 36)
        paymentCurrencyPopup.frame = NSRect(x: controlX, y: settingsRect.minY + 132, width: controlWidth, height: 36)
        displayCurrencyPopup.frame = NSRect(x: controlX, y: settingsRect.minY + 184, width: controlWidth, height: 36)
        showHistoricalEmptyWeeksButton.frame = NSRect(x: controlX, y: settingsRect.minY + 234, width: controlWidth, height: 24)
        let gap: CGFloat = 12
        let cardWidth = max(150, (content.width - gap * 2) / 3)
        let summaryCardHeight: CGFloat = cardWidth < 190 ? 92 : 82
        let summaryY = settingsRect.maxY + 16
        let summaryHeight = summaryCardHeight * 2 + gap
        let chartY = summaryY + summaryHeight + 16
        let chartRect = NSRect(x: content.minX, y: chartY, width: content.width, height: 332)
        let controlsY = chartRect.minY + 10
        let yearWidth: CGFloat = 152
        let monthWidth: CGFloat = 88
        let segmentWidth: CGFloat = 156
        let controlGap: CGFloat = 8
        costYearPopup.frame = NSRect(x: chartRect.maxX - 16 - yearWidth, y: controlsY, width: yearWidth, height: 28)
        if selectedCostWindow == .week {
            costMonthPopup.frame = NSRect(x: costYearPopup.frame.minX - controlGap - monthWidth, y: controlsY, width: monthWidth, height: 28)
            costWindowSegment.frame = NSRect(x: costMonthPopup.frame.minX - controlGap - segmentWidth, y: controlsY, width: segmentWidth, height: 28)
        } else {
            costWindowSegment.frame = NSRect(x: costYearPopup.frame.minX - controlGap - segmentWidth, y: controlsY, width: segmentWidth, height: 28)
        }
        updateCostControlsFromSettings()
    }

    private func updateCostControlsFromSettings() {
        guard selectedSection == .costs else { return }
        isUpdatingCostControls = true
        defer { isUpdatingCostControls = false }
        costAmountField.stringValue = paymentAmount(AppSettings.monthlyPlanCost)
        paymentStartDayField.stringValue = effectivePaymentStartDay(in: snapshot?.all)
        for (index, option) in CostHistoryWindow.allCases.enumerated() {
            costWindowSegment.setLabel(option.title, forSegment: index)
        }
        costWindowSegment.selectedSegment = CostHistoryWindow.allCases.firstIndex(of: selectedCostWindow) ?? 0
        showHistoricalEmptyWeeksButton.title = ""
        showHistoricalEmptyWeeksButton.state = AppSettings.showHistoricalEmptyWeeks ? .on : .off
        if let paymentIndex = CurrencyCode.allCases.firstIndex(of: AppSettings.paymentCurrency) {
            paymentCurrencyPopup.selectItem(at: paymentIndex)
        }
        if let displayIndex = CurrencyCode.allCases.firstIndex(of: AppSettings.displayCurrency) {
            displayCurrencyPopup.selectItem(at: displayIndex)
        }
        let years = availableCostYears(from: snapshot?.all)
        if !years.contains(selectedCostYear), let last = years.last {
            selectedCostYear = last
        }
        costMonthPopup.removeAllItems()
        costMonthPopup.addItems(withTitles: [t(.all)] + (1...12).map { String(format: "%02d", $0) })
        costMonthPopup.selectItem(at: (selectedCostMonth ?? 0))
        costYearPopup.removeAllItems()
        costYearPopup.addItems(withTitles: years.map(String.init))
        if let yearIndex = years.firstIndex(of: selectedCostYear) {
            costYearPopup.selectItem(at: yearIndex)
        }
    }

    func preferredDocumentHeight(for width: CGFloat) -> CGFloat {
        let minHeight: CGFloat = 660
        let normalizedWidth = max(860, width)
        let contentWidth = normalizedWidth - 220 - 56
        let cardGap: CGFloat = 12
        let cardWidth = max(120, (contentWidth - cardGap * 3) / 4)
        let summaryCardHeight: CGFloat = cardWidth < 170 ? 98 : 82

        let targetHeight: CGFloat
        switch selectedSection {
        case .overview:
            targetHeight = 760
        case .models:
            targetHeight = 660
        case .calendar:
            targetHeight = 760
        case .costs:
            let monthlyRows = min(monthlySpendRows(
                report: snapshot?.all ?? TokenReport(),
                limit: snapshot?.liveLimits.first { $0.id == QuotaViewOption.all.liveLimitID },
                year: selectedCostYear
            ).count, 6)
            let monthlyTableHeight = max(140, 54 + CGFloat(max(monthlyRows, 1)) * 18 + 28)
            let annualChartHeight: CGFloat = 332
            let topOffset: CGFloat = 78
            let settingsHeight: CGFloat = 286
            let sectionGap: CGFloat = 16
            let bottomPadding: CGFloat = 44
            let firstBlock = topOffset + settingsHeight + sectionGap + summaryCardHeight * 2 + cardGap
            let secondBlock = sectionGap + annualChartHeight + sectionGap + monthlyTableHeight
            targetHeight = firstBlock + secondBlock + bottomPadding
        case .settings:
            targetHeight = 470
        case .about:
            targetHeight = 580
        }
        return max(minHeight, targetHeight)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if selectedSection == .costs {
            updateCostHistoryHover(at: point)
        } else {
            if hoveredCostHistoryIndex != nil {
                hoveredCostHistoryIndex = nil
                needsDisplay = true
            }
        }
        updateDayValueInfoHover(at: point)
    }

    override func mouseExited(with event: NSEvent) {
        hoveredCostHistoryIndex = nil
        isHoveringDayValueInfo = false
        needsDisplay = true
    }

    private func updateCostHistoryHover(at point: CGPoint) {
        let match = costHistoryBarRects.first { $0.value.insetBy(dx: -4, dy: -4).contains(point) }
        let newIndex = match?.key
        if hoveredCostHistoryIndex != newIndex {
            hoveredCostHistoryIndex = newIndex
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

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for (section, rect) in sidebarItemRects where rect.contains(point) {
            selectedSection = section
            if section == .calendar, let report = snapshot?.all {
                selectedDay = preferredSelectedDay(in: report, fallback: selectedDay)
            }
            return
        }
        if selectedSection == .costs {
            for (window, rect) in costWindowRects where rect.contains(point) {
                selectedCostWindow = window
                hoveredCostHistoryIndex = nil
                needsDisplay = true
                return
            }
        }
        if selectedSection == .settings {
            for (language, rect) in languageOptionRects where rect.contains(point) {
                onLanguageChanged?(language)
                return
            }
            for (option, rect) in statusOptionRects where rect.contains(point) {
                onStatusDisplayChanged?(option)
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

    @objc private func costWindowSegmentChanged() {
        guard !isUpdatingCostControls,
              costWindowSegment.selectedSegment >= 0,
              costWindowSegment.selectedSegment < CostHistoryWindow.allCases.count else { return }
        selectedCostWindow = CostHistoryWindow.allCases[costWindowSegment.selectedSegment]
        hoveredCostHistoryIndex = nil
        needsDisplay = true
        needsLayout = true
    }

    @objc private func costMonthPopupChanged() {
        guard !isUpdatingCostControls,
              costMonthPopup.indexOfSelectedItem >= 0 else { return }
        selectedCostMonth = costMonthPopup.indexOfSelectedItem == 0 ? nil : costMonthPopup.indexOfSelectedItem
        hoveredCostHistoryIndex = nil
        needsDisplay = true
        needsLayout = true
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

    @objc private func showHistoricalEmptyWeeksChanged() {
        guard !isUpdatingCostControls else { return }
        onShowHistoricalEmptyWeeksChanged?(showHistoricalEmptyWeeksButton.state == .on)
        hoveredCostHistoryIndex = nil
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
        NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
        bounds.fill()

        let sidebarWidth: CGFloat = 220
        NSColor(calibratedWhite: 0.10, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: sidebarWidth, height: bounds.height).fill()
        NSColor.white.withAlphaComponent(0.10).setStroke()
        NSBezierPath(rect: NSRect(x: sidebarWidth, y: 0, width: 1, height: bounds.height)).stroke()

        drawSidebar(width: sidebarWidth)

        let content = NSRect(x: sidebarWidth + 28, y: 28, width: bounds.width - sidebarWidth - 56, height: bounds.height - 56)
        drawText(t(.usageDetails), rect: NSRect(x: content.minX, y: content.minY, width: content.width, height: 34), font: .systemFont(ofSize: 26, weight: .bold), color: .white)
        drawText(selectedSection.subtitle, rect: NSRect(x: content.minX, y: content.minY + 36, width: content.width, height: 20), font: .systemFont(ofSize: 13, weight: .medium), color: NSColor.white.withAlphaComponent(0.50))
        contributionDayRects.removeAll()
        costHistoryBarRects.removeAll()
        costHistoryRows.removeAll()
        dayValueInfoRect = nil
        languageOptionRects.removeAll()
        statusOptionRects.removeAll()
        costWindowRects.removeAll()
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
        case .about:
            drawAboutPage(snapshot: snapshot, content: content)
        }

        if selectedSection == .costs {
            drawCostHistoryTooltip()
        } else if selectedSection == .calendar {
            drawDayValueInfoTooltip()
        }
    }

    private func drawSidebar(width: CGFloat) {
        sidebarItemRects.removeAll()
        drawText("Codex", rect: NSRect(x: 28, y: 28, width: width - 56, height: 28), font: .systemFont(ofSize: 24, weight: .bold), color: .white)
        drawText(t(.tokenMeter), rect: NSRect(x: 28, y: 58, width: width - 56, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: NSColor.white.withAlphaComponent(0.50))
        for (index, section) in DetailsSection.allCases.enumerated() {
            let y = CGFloat(118 + index * 58)
            let rect = NSRect(x: 18, y: y, width: width - 36, height: 42)
            sidebarItemRects[section] = rect
            if section == selectedSection {
                NSColor.systemBlue.withAlphaComponent(0.78).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
            }
            drawText(section.title, rect: NSRect(x: rect.minX + 22, y: rect.minY + 10, width: rect.width - 44, height: 22), font: .systemFont(ofSize: 15, weight: .semibold), color: .white)
        }
    }

    private func drawOverview(snapshot: DetailsSnapshot, content: NSRect) {
        let cardsY = content.minY + 78
        let quotaY = cardsY + 98
        let modelsY = quotaY + 136
        let gridY = modelsY + 146
        drawMetricCards(snapshot: snapshot, content: content)
        drawQuotaRows(snapshot: snapshot, content: content, y: quotaY, height: 120)
        drawModelRows(snapshot: snapshot, content: content, y: modelsY, height: 130, maxRows: 4)
        let gridRect = NSRect(x: content.minX, y: gridY, width: content.width, height: max(168, content.maxY - gridY))
        drawContributionGrid(report: snapshot.all, rect: gridRect, title: t(.pastYear), compact: true)
    }

    private func drawMetricCards(snapshot: DetailsSnapshot, content: NSRect) {
        let gap: CGFloat = 12
        let cardW = (content.width - gap * 3) / 4
        let cards: [(String, String, NSColor)] = [
            (t(.all), compact(snapshot.all.usage.total), .systemGreen),
            (t(.spark), compact(snapshot.spark.usage.total), .systemCyan),
            (t(.other), compact(snapshot.other.usage.total), .systemOrange),
            (t(.cache), String(format: "%.0f%%", snapshot.all.usage.cachePercent), .systemTeal)
        ]
        for (index, card) in cards.enumerated() {
            let rect = NSRect(x: content.minX + CGFloat(index) * (cardW + gap), y: content.minY + 78, width: cardW, height: 82)
            drawPanel(rect)
            drawText(card.0, rect: NSRect(x: rect.minX + 16, y: rect.minY + 12, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(0.52))
            drawText(card.1, rect: NSRect(x: rect.minX + 16, y: rect.minY + 34, width: rect.width - 32, height: 30), font: .monospacedDigitSystemFont(ofSize: 24, weight: .bold), color: card.2)
        }
    }

    private func drawQuotaRows(snapshot: DetailsSnapshot, content: NSRect, y: CGFloat, height: CGFloat) {
        let rect = NSRect(x: content.minX, y: y, width: content.width, height: height)
        drawPanel(rect)
        drawText(t(.quotaViews), rect: NSRect(x: rect.minX + 16, y: rect.minY + 12, width: rect.width - 32, height: 20), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
        let rows = [
            (t(.all), t(.allDescription), snapshot.all),
            (t(.spark), t(.sparkModel), snapshot.spark),
            (t(.other), t(.otherDescription), snapshot.other)
        ]
        for (index, row) in rows.enumerated() {
            let y = rect.minY + 40 + CGFloat(index) * 26
            drawText(row.0, rect: NSRect(x: rect.minX + 16, y: y, width: 90, height: 18), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
            drawText(row.1, rect: NSRect(x: rect.minX + 104, y: y, width: 210, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.45))
            drawRight("\(compact(row.2.usage.total)) \(t(.total))", rect: NSRect(x: rect.maxX - 300, y: y, width: 140, height: 18), color: .white)
            drawRight("\(compact(row.2.usage.input)) \(t(.inShort))", rect: NSRect(x: rect.maxX - 158, y: y, width: 72, height: 18), color: NSColor.white.withAlphaComponent(0.55))
            drawRight("\(compact(row.2.usage.output)) \(t(.outShort))", rect: NSRect(x: rect.maxX - 84, y: y, width: 68, height: 18), color: NSColor.white.withAlphaComponent(0.55))
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
        let rows = monthlySpendRows(report: snapshot.all, limit: snapshot.liveLimits.first { $0.id == QuotaViewOption.all.liveLimitID })
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

    private func drawCalendarPage(snapshot: DetailsSnapshot, content: NSRect) {
        let gridHeight = min(240, max(210, content.height * 0.38))
        let gridRect = NSRect(x: content.minX, y: content.minY + 78, width: content.width, height: gridHeight)
        drawContributionGrid(report: snapshot.all, rect: gridRect, title: t(.pastYear), compact: false)

        let available = max(260, content.maxY - gridRect.maxY - 16)
        let detailRect = NSRect(x: content.minX, y: gridRect.maxY + 16, width: content.width, height: min(360, available))
        drawSelectedDayPanel(snapshot: snapshot, rect: detailRect)
    }

    private func drawCostPage(snapshot: DetailsSnapshot, content: NSRect) {
        let limit = snapshot.liveLimits.first { $0.id == QuotaViewOption.all.liveLimitID }
        let estimate = planCostEstimate(report: snapshot.all, selectedDay: nil, limit: limit)

        let settingsRect = NSRect(x: content.minX, y: content.minY + 78, width: content.width, height: 286)
        let leftColumnWidth = max(240, settingsRect.width - (min(300, max(252, settingsRect.width * 0.34)) + 56))
        drawPanel(settingsRect)
        drawText(t(.planCost), rect: NSRect(x: settingsRect.minX + 16, y: settingsRect.minY + 14, width: 220, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        drawText(t(.paymentMonthly), rect: NSRect(x: settingsRect.minX + 16, y: settingsRect.minY + 52, width: leftColumnWidth, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
        drawMultilineText(t(.planCostHint), rect: NSRect(x: settingsRect.minX + 16, y: settingsRect.minY + 74, width: leftColumnWidth, height: 32), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.52))

        drawText(t(.paymentStartDate), rect: NSRect(x: settingsRect.minX + 16, y: settingsRect.minY + 122, width: leftColumnWidth, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
        drawText(t(.paymentCurrency), rect: NSRect(x: settingsRect.minX + 16, y: settingsRect.minY + 168, width: leftColumnWidth, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
        drawText(t(.displayCurrency), rect: NSRect(x: settingsRect.minX + 16, y: settingsRect.minY + 220, width: leftColumnWidth, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
        drawText(t(.showPastEmptyWeeks), rect: NSRect(x: settingsRect.minX + 16, y: settingsRect.minY + 248, width: leftColumnWidth, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)

        let summaryY = settingsRect.maxY + 16
        let gap: CGFloat = 12
        let columns = 3
        let cardW = (content.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let summaryCardHeight: CGFloat = cardW < 190 ? 92 : 82
        let summaryCards: [(String, String, NSColor)] = [
            (t(.paymentMonthly), paymentMoney(AppSettings.monthlyPlanCost), .white),
            (t(.displayEquivalent), displayMoney(AppSettings.monthlyPlanCost), NSColor.white.withAlphaComponent(0.88)),
            (t(.weeklyUsedValue), estimate.map { displayMoney($0.weeklyUsedValue) } ?? "--", costUsedColor),
            (t(.weeklyUnusedValue), estimate.map { displayMoney($0.weeklyUnusedValue) } ?? "--", costRemainingColor),
            (t(.totalSpendValue), estimate.map { displayMoney($0.totalSpentValue) } ?? "--", .white),
            (t(.totalWasteValue), estimate.map { displayMoney($0.totalWastedValue) } ?? "--", NSColor.white.withAlphaComponent(0.72))
        ]
        for (index, card) in summaryCards.enumerated() {
            let row = index / columns
            let column = index % columns
            let rect = NSRect(
                x: content.minX + CGFloat(column) * (cardW + gap),
                y: summaryY + CGFloat(row) * (summaryCardHeight + gap),
                width: cardW,
                height: summaryCardHeight
            )
            drawPanel(rect)
            drawText(card.0, rect: NSRect(x: rect.minX + 16, y: rect.minY + 12, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(0.52))
            drawText(card.1, rect: NSRect(x: rect.minX + 16, y: rect.minY + 34, width: rect.width - 32, height: 30), font: .monospacedDigitSystemFont(ofSize: 20, weight: .bold), color: card.2)
        }

        let chartY = summaryY + summaryCardHeight * 2 + gap + 16
        let chartRect = NSRect(x: content.minX, y: chartY, width: content.width, height: 332)
        drawPanel(chartRect)
        drawText(t(.costHistory), rect: NSRect(x: chartRect.minX + 16, y: chartRect.minY + 12, width: 220, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        drawText(t(.costHistoryHint), rect: NSRect(x: chartRect.minX + 16, y: chartRect.minY + 36, width: 430, height: 16), font: .systemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.44))

        let costRows: [CostPeriodRow]
        switch selectedCostWindow {
        case .week:
            costRows = weeklySpendRows(report: snapshot.all, limit: limit, year: selectedCostYear, month: selectedCostMonth)
        case .month:
            costRows = monthlyCostRows(report: snapshot.all, limit: limit, year: selectedCostYear)
        }
        drawCostRings(rows: costRows, rect: NSRect(x: chartRect.minX + 16, y: chartRect.minY + 60, width: chartRect.width - 32, height: chartRect.height - 78), year: selectedCostYear, month: selectedCostMonth, mode: selectedCostWindow)

        let tableY = chartRect.maxY + 16
        let tableRect = NSRect(x: content.minX, y: tableY, width: content.width, height: max(120, content.maxY - tableY))
        drawPanel(tableRect)
        drawText(t(.monthlySpendHistory), rect: NSRect(x: tableRect.minX + 16, y: tableRect.minY + 12, width: 220, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        let rows = monthlySpendRows(report: snapshot.all, limit: limit, year: selectedCostYear)
        if rows.isEmpty {
            drawText(t(.planCostUnavailable), rect: NSRect(x: tableRect.minX + 16, y: tableRect.minY + 48, width: tableRect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
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
        drawText("\(compact(day.usage.total)) \(t(.total))", rect: NSRect(x: rect.minX + 18, y: rect.minY + 48, width: 260, height: 34), font: .monospacedDigitSystemFont(ofSize: 28, weight: .bold), color: .systemGreen)
        let limit = snapshot.liveLimits.first { $0.id == QuotaViewOption.all.liveLimitID }
        let cost = planCostEstimate(report: report, selectedDay: day, limit: limit)
        var dayMeta = "\(day.turns) \(t(.turns).lowercased())  |  \(Int(round(intensity * 100)))% \(t(.peakDay))"
        if let cost {
            dayMeta += "  |  \(String(format: "%.1f%%", cost.selectedDayQuotaPercent)) \(t(.weeklyQuotaShare))"
        }
        drawText(dayMeta, rect: NSRect(x: rect.minX + 18, y: rect.minY + 90, width: 420, height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(0.48))

        typealias DayMetric = (title: String, value: String, color: NSColor, infoAnchor: Bool, footer: String?)
        let cachedCostValue: String?
        let freshCostValue: String?
        if let cost, day.usage.total > 0 {
            cachedCostValue = displayMoney(cost.selectedDayValue * Double(day.usage.cachedInput) / Double(day.usage.total))
            freshCostValue = displayMoney(cost.selectedDayValue * Double(day.usage.freshInput) / Double(day.usage.total))
        } else {
            cachedCostValue = nil
            freshCostValue = nil
        }
        var metrics: [DayMetric] = [
            (t(.input), compact(day.usage.input), NSColor.systemGreen, false, nil),
            (t(.output), compact(day.usage.output), NSColor.systemCyan, false, nil),
            (t(.cached), compact(day.usage.cachedInput), NSColor.systemTeal, false, cachedCostValue),
            (t(.fresh), compact(day.usage.freshInput), NSColor.systemOrange, false, freshCostValue)
        ]
        if let cost {
            metrics.append(("\(t(.dayValue)) ?", displayMoney(cost.selectedDayValue), NSColor.systemGreen, true, nil))
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
        let rect = NSRect(x: content.minX, y: content.minY + 78, width: content.width, height: min(360, content.height - 78))
        drawPanel(rect)
        drawText(t(.language), rect: NSRect(x: rect.minX + 16, y: rect.minY + 16, width: rect.width - 32, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        drawText(t(.interfaceLanguage), rect: NSRect(x: rect.minX + 16, y: rect.minY + 56, width: 220, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)

        let optionW: CGFloat = 132
        let optionH: CGFloat = 38
        let gap: CGFloat = 12
        let optionY = rect.minY + 48
        let startX = rect.maxX - 16 - optionW * CGFloat(AppLanguage.allCases.count) - gap * CGFloat(AppLanguage.allCases.count - 1)
        for (index, language) in AppLanguage.allCases.enumerated() {
            let optionRect = NSRect(x: startX + CGFloat(index) * (optionW + gap), y: optionY, width: optionW, height: optionH)
            languageOptionRects[language] = optionRect
            if language == AppLanguage.current {
                NSColor.systemBlue.withAlphaComponent(0.72).setFill()
            } else {
                NSColor.black.withAlphaComponent(0.14).setFill()
            }
            NSBezierPath(roundedRect: optionRect, xRadius: 8, yRadius: 8).fill()
            NSColor.white.withAlphaComponent(language == AppLanguage.current ? 0.18 : 0.08).setStroke()
            NSBezierPath(roundedRect: optionRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
            drawCentered(language.displayName, rect: optionRect.insetBy(dx: 8, dy: 0), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
        }

        drawText(t(.languageHint), rect: NSRect(x: rect.minX + 16, y: rect.minY + 104, width: rect.width - 32, height: 20), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.52))

        drawText(t(.logFolder), rect: NSRect(x: rect.minX + 16, y: rect.minY + 136, width: 220, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
        let pathRect = NSRect(x: rect.minX + 16, y: rect.minY + 164, width: rect.width - 276, height: 34)
        NSColor.black.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: pathRect, xRadius: 7, yRadius: 7).fill()
        drawText(AppSettings.logFolderURL.path, rect: pathRect.insetBy(dx: 12, dy: 9), font: .monospacedSystemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.62))

        let logButtonW: CGFloat = 72
        let logButtonY = rect.minY + 164
        chooseLogFolderRect = NSRect(x: rect.maxX - 244, y: logButtonY, width: 84, height: 34)
        resetLogFolderRect = NSRect(x: rect.maxX - 152, y: logButtonY, width: logButtonW, height: 34)
        openLogFolderRect = NSRect(x: rect.maxX - 72, y: logButtonY, width: 56, height: 34)
        drawSmallButton(t(.logFolderChoose), rect: chooseLogFolderRect!)
        drawSmallButton(t(.logFolderDefault), rect: resetLogFolderRect!)
        drawSmallButton(t(.logFolderOpen), rect: openLogFolderRect!)
        drawText(t(.logFolderHint), rect: NSRect(x: rect.minX + 16, y: rect.minY + 204, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.52))

        drawText(t(.statusBarDisplay), rect: NSRect(x: rect.minX + 16, y: rect.minY + 252, width: 220, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
        let statusY = rect.minY + 248
        let statusGap: CGFloat = 10
        let statusOptionW = max(100, (rect.width - 260 - statusGap * CGFloat(StatusDisplayOption.allCases.count - 1)) / CGFloat(StatusDisplayOption.allCases.count))
        let statusStartX = rect.maxX - 16 - statusOptionW * CGFloat(StatusDisplayOption.allCases.count) - statusGap * CGFloat(StatusDisplayOption.allCases.count - 1)
        for (index, option) in StatusDisplayOption.allCases.enumerated() {
            let optionRect = NSRect(x: statusStartX + CGFloat(index) * (statusOptionW + statusGap), y: statusY, width: statusOptionW, height: 36)
            statusOptionRects[option] = optionRect
            drawSelectablePill(option.title, rect: optionRect, selected: option == StatusDisplayOption.current)
        }
        drawText(t(.statusDisplayHint), rect: NSRect(x: rect.minX + 16, y: rect.minY + 296, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.52))
    }

    private var costUsedColor: NSColor {
        NSColor(calibratedRed: 0.24, green: 0.82, blue: 0.42, alpha: 0.96)
    }

    private var costRemainingColor: NSColor {
        NSColor(calibratedRed: 0.34, green: 0.44, blue: 0.58, alpha: 0.92)
    }

    private var costRemainingMutedColor: NSColor {
        NSColor(calibratedRed: 0.23, green: 0.27, blue: 0.34, alpha: 1.0)
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

    private func drawCostRings(rows: [CostPeriodRow], rect: NSRect, year: Int, month: Int?, mode: CostHistoryWindow) {
        costHistoryRows = rows
        guard !rows.isEmpty else {
            drawText(t(.planCostUnavailable), rect: NSRect(x: rect.minX, y: rect.minY + 32, width: rect.width, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }

        let isMonthly = mode == .month
        let columns: Int
        if isMonthly {
            columns = 6
        } else if month != nil {
            columns = min(max(rows.count, 1), 6)
        } else {
            columns = 13
        }
        let rowCount = Int(ceil(Double(rows.count) / Double(columns)))
        let ringGapX: CGFloat = isMonthly ? 28 : 12
        let ringGapY: CGFloat = isMonthly ? 22 : 18
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

        let scopeTitle = month.map { String(format: "%04d-%02d", year, $0) } ?? String(year)
        drawText(scopeTitle, rect: NSRect(x: rect.minX, y: rect.minY, width: 86, height: 16), font: .monospacedDigitSystemFont(ofSize: 11, weight: .bold), color: NSColor.white.withAlphaComponent(0.52))
        drawCostRingLegend(rect: NSRect(x: rect.minX + 96, y: rect.minY, width: 260, height: 16))

        for (index, row) in rows.enumerated() {
            let gridRow = index / columns
            let gridColumn = index % columns
            let cell = NSRect(
                x: startX + CGFloat(gridColumn) * (ringSize + ringGapX),
                y: startY + CGFloat(gridRow) * (ringSize + ringGapY),
                width: ringSize,
                height: ringSize
            )
            costHistoryBarRects[index] = cell.insetBy(dx: -4, dy: -4)
            drawCostRing(row: row, rect: cell, showLabel: isMonthly, highlighted: hoveredCostHistoryIndex == index)
        }

        let footer = NSRect(x: rect.minX, y: rect.maxY - 18, width: rect.width, height: 14)
        drawRight(t(.costHistoryHint), rect: footer, color: NSColor.white.withAlphaComponent(0.34), font: .systemFont(ofSize: 10, weight: .medium))
    }

    private func drawCostRingLegend(rect: NSRect) {
        let items: [(String, NSColor)] = [
            (t(.used), costUsedColor),
            (t(.remaining), costRemainingColor),
            (t(.noUsage), NSColor.white.withAlphaComponent(0.18)),
            (t(.future), NSColor.white.withAlphaComponent(0.08))
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
        let fullCircleRect = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let baseColor = NSColor.white.withAlphaComponent(row.isFuture ? 0.06 : (row.hasData ? 0.09 : 0.12))

        fillDonut(in: fullCircleRect, thickness: lineWidth, color: baseColor)

        if row.hasData {
            fillDonut(in: fullCircleRect, thickness: lineWidth, color: costRemainingColor)

            let progress = min(1.0, max(0.0, row.usedPercent / 100))
            let ringColor: NSColor = row.usedPercent > 100 ? .systemOrange : costUsedColor
            if progress >= 0.999 {
                fillDonut(in: fullCircleRect, thickness: lineWidth, color: ringColor)
            } else if progress > 0.001 {
                fillDonutSegment(
                    center: center,
                    outerRadius: radius,
                    thickness: lineWidth,
                    startAngle: start,
                    endAngle: start + CGFloat.pi * 2 * CGFloat(progress),
                    color: ringColor
                )
            }
        } else if row.isFuture {
            fillDonut(in: fullCircleRect, thickness: lineWidth, color: NSColor.white.withAlphaComponent(0.08))
        } else {
            fillDonut(in: fullCircleRect, thickness: max(3, lineWidth * 0.72), color: NSColor.white.withAlphaComponent(0.16))
        }

        let ringColor: NSColor = row.usedPercent > 100 ? .systemOrange : costUsedColor

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
        let lines: [(String, String, NSColor)] = [
            (t(.used), displayMoney(row.usedValue), costUsedColor),
            (t(.remaining), displayMoney(row.remainingValue), costRemainingColor),
            (t(.budget), displayMoney(row.budgetValue), .white),
            (t(.usageRate), String(format: "%.1f%%", row.usedPercent), NSColor.white.withAlphaComponent(0.82))
        ]

        let width: CGFloat = 282
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
        let labelWidth: CGFloat = 76
        let valueX = rect.minX + labelWidth + 28
        let valueWidth = rect.maxX - valueX - 14
        for (index, line) in lines.enumerated() {
            let y = startY + CGFloat(index) * rowHeight
            drawText(line.0, rect: NSRect(x: rect.minX + 12, y: y, width: labelWidth, height: 16), font: .systemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.62))
            drawRight(line.1, rect: NSRect(x: valueX, y: y, width: valueWidth, height: 16), color: line.2, font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold))
        }
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

    private func drawAboutPage(snapshot: DetailsSnapshot, content: NSRect) {
        let rect = NSRect(x: content.minX, y: content.minY + 78, width: content.width, height: 276)
        drawPanel(rect)
        drawText(t(.definitions), rect: NSRect(x: rect.minX + 16, y: rect.minY + 16, width: rect.width - 32, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        let rows = [
            (t(.all), "All local Codex token events that include token details."),
            (t(.spark), t(.sparkDescription)),
            (t(.other), t(.otherDefinition)),
            (t(.cacheHit), "Cached input divided by total input for the selected window.")
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
        drawText(title, rect: NSRect(x: rect.minX + 16, y: rect.minY + 12, width: 180, height: 20), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
        let days = report.byDay
        guard !days.isEmpty else {
            drawText(t(.noDailyTokenData), rect: NSRect(x: rect.minX + 16, y: rect.minY + 52, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }

        let maxTotal = max(days.map { $0.usage.total }.max() ?? 1, 1)
        let useCalendarGrid = !compact || days.count > 90
        let columns = useCalendarGrid ? Int(ceil(Double(days.count) / 7.0)) : min(days.count, 15)
        let rows = useCalendarGrid ? 7 : Int(ceil(Double(days.count) / Double(max(columns, 1))))
        let gap: CGFloat = useCalendarGrid ? (compact ? 2 : 3) : 6
        let left: CGFloat = compact ? 18 : 26
        let right: CGFloat = compact ? 18 : 26
        let top: CGFloat = compact ? 48 : 66
        let bottom: CGFloat = compact ? 34 : 72
        let availableW = max(40, rect.width - left - right)
        let availableH = max(40, rect.height - top - bottom)
        let square = floor(min((availableW - gap * CGFloat(max(columns - 1, 0))) / CGFloat(max(columns, 1)), (availableH - gap * CGFloat(max(rows - 1, 0))) / CGFloat(max(rows, 1))))
        let gridW = CGFloat(columns) * square + CGFloat(max(columns - 1, 0)) * gap
        let gridH = CGFloat(rows) * square + CGFloat(max(rows - 1, 0)) * gap
        let startX = rect.minX + left
        let startY = rect.minY + top + (compact ? max(0, (availableH - gridH) / 2) : 0)

        for (index, day) in days.enumerated() {
            let col = useCalendarGrid ? index / 7 : index % columns
            let row = useCalendarGrid ? index % 7 : index / columns
            let intensity = Double(day.usage.total) / Double(maxTotal)
            contributionColor(intensity).setFill()
            let cell = NSRect(x: startX + CGFloat(col) * (square + gap), y: startY + CGFloat(row) * (square + gap), width: square, height: square)
            contributionDayRects[day.day] = cell
            NSBezierPath(roundedRect: cell, xRadius: 3, yRadius: 3).fill()
            if day.day == selectedDay {
                NSColor.white.withAlphaComponent(0.92).setStroke()
                let path = NSBezierPath(roundedRect: cell.insetBy(dx: -2, dy: -2), xRadius: 5, yRadius: 5)
                path.lineWidth = 2
                path.stroke()
            }
            if !compact && row == 6 && (col == 0 || col == columns - 1 || col % 8 == 0) {
                let label = String(day.day.suffix(5))
                drawCentered(label, rect: NSRect(x: cell.midX - 28, y: rect.maxY - 46, width: 56, height: 16), font: .systemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.45))
            }
        }

        if compact {
            let labelY = rect.maxY - 26
            if let first = days.first?.day, let last = days.last?.day {
                drawText(String(first.suffix(5)), rect: NSRect(x: startX, y: labelY, width: 60, height: 16), font: .systemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.40))
                drawRight(String(last.suffix(5)), rect: NSRect(x: startX + gridW - 60, y: labelY, width: 60, height: 16), color: NSColor.white.withAlphaComponent(0.40), font: .systemFont(ofSize: 10, weight: .semibold))
            }
        }
        drawText(t(.usageIntensityHint), rect: NSRect(x: rect.maxX - 280, y: rect.maxY - 26, width: 260, height: 16), font: .systemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.42))
    }

    private func drawPanel(_ rect: NSRect) {
        NSColor(calibratedWhite: 0.18, alpha: 0.96).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        NSColor.white.withAlphaComponent(0.06).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
    }

    private func drawSmallButton(_ title: String, rect: NSRect) {
        NSColor.white.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        NSColor.white.withAlphaComponent(0.10).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7).stroke()
        drawCentered(title, rect: rect.insetBy(dx: 6, dy: 0), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(0.86))
    }

    private func drawSelectablePill(_ title: String, rect: NSRect, selected: Bool) {
        if selected {
            NSColor.systemBlue.withAlphaComponent(0.72).setFill()
        } else {
            NSColor.black.withAlphaComponent(0.14).setFill()
        }
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        NSColor.white.withAlphaComponent(selected ? 0.18 : 0.08).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
        drawCentered(title, rect: rect.insetBy(dx: 8, dy: 0), font: .systemFont(ofSize: 12, weight: .semibold), color: .white)
    }

    private func contributionColor(_ intensity: Double) -> NSColor {
        if intensity <= 0 { return NSColor.white.withAlphaComponent(0.08) }
        if intensity < 0.25 { return NSColor.systemGreen.withAlphaComponent(0.30) }
        if intensity < 0.50 { return NSColor.systemGreen.withAlphaComponent(0.52) }
        if intensity < 0.75 { return NSColor.systemGreen.withAlphaComponent(0.74) }
        return NSColor.systemGreen
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
    private var scanner = CodexTokenScanner(rootURL: AppSettings.logFolderURL)
    private let rateLimitReader = LiveRateLimitReader()
    private let localFormatter = DateFormatter()
    private let scanQueue = DispatchQueue(label: "local.codex-token-meter.scan", qos: .utility)
    private let liveQueue = DispatchQueue(label: "local.codex-token-meter.live", qos: .utility)
    private var selectedWindow: WindowOption = .week
    private var selectedQuota: QuotaViewOption = .all
    private var latestState = DashboardState()
    private var reportCache: [ReportCacheKey: TokenReport] = [:]
    private var liveLimits: [LiveRateLimit] = []
    private var refreshTimer: Timer?
    private var activeScans: Set<ReportCacheKey> = []
    private var liveRefreshInFlight = false
    private var statusSpinnerTimer: Timer?
    private var statusSpinnerFrame = 0
    private var statusIsLoading = false
    private let refreshInterval: TimeInterval = 300
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
        popover.behavior = .transient
        configureStatusButton()

        dashboardController.dashboardView.onWindowChanged = { [weak self] option in self?.selectWindow(option) }
        dashboardController.dashboardView.onQuotaChanged = { [weak self] option in self?.selectQuota(option) }
        dashboardController.dashboardView.onRefresh = { [weak self] in
            self?.refresh(forceLive: false)
            self?.refreshLiveLimits()
        }
        dashboardController.dashboardView.onCopy = { [weak self] in self?.copySummary() }
        dashboardController.dashboardView.onOpenDetails = { [weak self] in self?.openDetailsWindow() }
        dashboardController.dashboardView.onOpenLogs = { [weak self] in self?.openSessionsFolder() }
        dashboardController.dashboardView.onQuit = { NSApp.terminate(nil) }
        detailsController.detailsView.onLanguageChanged = { [weak self] language in
            AppLanguage.current = language
            self?.applyLanguage()
        }
        detailsController.detailsView.onStatusDisplayChanged = { [weak self] option in
            guard let self else { return }
            StatusDisplayOption.current = option
            detailsController.detailsView.needsDisplay = true
            updateStatusTitle(report: latestState.report, limits: liveLimits, quota: selectedQuota)
        }
        detailsController.detailsView.onPlanCostChanged = { [weak self] value in self?.changePlanCost(value) }
        detailsController.detailsView.onPaymentStartDayChanged = { [weak self] value in self?.changePaymentStartDay(value) }
        detailsController.detailsView.onPaymentCurrencyChanged = { [weak self] currency in self?.changePaymentCurrency(currency) }
        detailsController.detailsView.onDisplayCurrencyChanged = { [weak self] currency in self?.changeDisplayCurrency(currency) }
        detailsController.detailsView.onShowHistoricalEmptyWeeksChanged = { [weak self] isOn in self?.changeShowHistoricalEmptyWeeks(isOn) }
        detailsController.detailsView.onChooseLogFolder = { [weak self] in self?.chooseLogFolder() }
        detailsController.detailsView.onResetLogFolder = { [weak self] in self?.resetLogFolder() }
        detailsController.detailsView.onOpenLogFolder = { [weak self] in self?.openSessionsFolder() }
        applyLanguage()

        refresh(forceLive: false)
        refreshLiveLimits()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh(forceLive: false)
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
                costReferenceReport: costReferenceReport(quota: selectedQuota, fallback: cached),
                liveLimits: liveLimits,
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
                costReferenceReport: costReferenceReport(quota: selectedQuota, fallback: nil),
                liveLimits: liveLimits,
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
            costReferenceReport: costReferenceReport(quota: quota, fallback: reportCache[key]),
            liveLimits: liveLimits,
            selectedWindow: window,
            selectedQuota: quota,
            nextRefreshAt: latestState.nextRefreshAt,
            isLoading: true,
            error: nil
        )
        dashboardController.dashboardView.update(latestState)
        updateStatusTitle(report: latestState.report, limits: liveLimits, quota: quota)
        let currentLimits = liveLimits

        scanQueue.async {
            let report = self.scanner.scan(window: window, includedModelName: quota.includedModelName, excludedModelName: quota.excludedModelName)
            let limits = forceLive ? self.rateLimitReader.read() : currentLimits
            let nextRefresh = Date().addingTimeInterval(self.refreshInterval)
            DispatchQueue.main.async {
                self.activeScans.remove(key)
                self.reportCache[key] = report
                if forceLive, !limits.isEmpty {
                    self.liveLimits = limits
                }
                if self.selectedWindow == window && self.selectedQuota == quota {
                    let effectiveLimits = forceLive && !limits.isEmpty ? limits : self.liveLimits
                    self.latestState = DashboardState(
                        report: report,
                        costReferenceReport: self.costReferenceReport(quota: quota, fallback: report),
                        liveLimits: effectiveLimits,
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
            DispatchQueue.main.async {
                self.liveRefreshInFlight = false
                guard !limits.isEmpty else { return }
                self.liveLimits = limits
                self.latestState.liveLimits = limits
                self.latestState.error = nil
                self.updateStatusTitle(report: self.latestState.report, limits: limits, quota: self.latestState.selectedQuota)
                self.dashboardController.dashboardView.update(self.latestState)
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
                        costReferenceReport: self.costReferenceReport(quota: quota, fallback: report),
                        liveLimits: self.liveLimits,
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

    private func costReferenceReport(quota: QuotaViewOption, fallback: TokenReport?) -> TokenReport? {
        reportCache[ReportCacheKey(window: .week, quota: quota)] ?? fallback
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
        if let cached = reportCache[key] {
            return cached
        }
        if latestState.selectedWindow == window && latestState.selectedQuota == quota {
            return latestState.report
        }
        return nil
    }

    private func selectedLimit(from limits: [LiveRateLimit], quota: QuotaViewOption) -> LiveRateLimit? {
        limits.first { $0.id == quota.liveLimitID }
    }

    private func copySummary() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summaryText(state: latestState), forType: .string)
    }

    private func openSessionsFolder() {
        NSWorkspace.shared.open(AppSettings.logFolderURL)
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

    private func changeShowHistoricalEmptyWeeks(_ value: Bool) {
        AppSettings.showHistoricalEmptyWeeks = value
        detailsController.detailsView.needsDisplay = true
        detailsController.detailsView.needsLayout = true
    }

    private func reloadScannerFromSettings() {
        scanner = CodexTokenScanner(rootURL: AppSettings.logFolderURL)
        reportCache.removeAll()
        activeScans.removeAll()
        detailsController.detailsView.needsDisplay = true
        refresh(forceLive: false)
    }

    private func openDetailsWindow() {
        detailsController.showLoading()
        let limits = liveLimits
        scanQueue.async {
            let all = self.scanner.scan(days: 365)
            let spark = self.scanner.scan(days: 365, includedModelName: QuotaViewOption.spark.includedModelName)
            let other = self.scanner.scan(days: 365, excludedModelName: QuotaViewOption.other.excludedModelName)
            let snapshot = DetailsSnapshot(all: all, spark: spark, other: other, liveLimits: limits)
            DispatchQueue.main.async {
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
    if value >= 1_000_000_000 { return String(format: "%.2fB", double / 1_000_000_000) }
    if value >= 1_000_000 { return String(format: "%.1fM", double / 1_000_000) }
    if value >= 1_000 { return String(format: "%.1fK", double / 1_000) }
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

private func effectivePaymentStartDay(in report: TokenReport?) -> String {
    let parser = dayFormatter()
    if let stored = AppSettings.paymentStartDay,
       parser.date(from: stored) != nil {
        return stored
    }
    return report?.byDay.map(\.day).sorted().first ?? todayKey()
}

private func currentWeeklyBudgetPaymentValue() -> Double {
    AppSettings.monthlyPlanCost * 12 / 52
}

private func paymentValueForDayUsage(_ usage: Usage, weeklyQuotaUsedPercent: Double?, weeklyQuotaReferenceTotal: Int64?) -> Double? {
    guard let weeklyQuotaUsedPercent,
          weeklyQuotaUsedPercent > 0,
          let weeklyQuotaReferenceTotal,
          weeklyQuotaReferenceTotal > 0,
          usage.total > 0 else {
        return nil
    }
    let shareOfVisibleWeek = Double(usage.total) / Double(weeklyQuotaReferenceTotal)
    return currentWeeklyBudgetPaymentValue() * shareOfVisibleWeek * weeklyQuotaUsedPercent / 100
}

private func availableCostYears(from report: TokenReport?) -> [Int] {
    guard let report, !report.byDay.isEmpty else {
        return [Calendar.current.component(.year, from: Date())]
    }
    let years = Set(report.byDay.compactMap { Int($0.day.prefix(4)) })
    let sorted = years.sorted()
    return sorted.isEmpty ? [Calendar.current.component(.year, from: Date())] : sorted
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

private func weeklySpendRows(report: TokenReport, limit: LiveRateLimit?, year: Int? = nil, month: Int? = nil) -> [CostPeriodRow] {
    guard let estimate = planCostEstimate(report: report, selectedDay: nil, limit: limit),
          estimate.weeklyBudget > 0 else {
        return []
    }
    let paymentPerToken = estimate.weeklyBudget / max(estimate.weeklyQuotaTotal, 1)
    let calendar = appCalendar()
    let parser = dayFormatter()
    let labelFormatter = shortMonthDayFormatter()
    let titleFormatter = dayFormatter()
    var buckets: [Date: Int64] = [:]
    for day in report.byDay where day.usage.total > 0 {
        guard let date = parser.date(from: day.day),
              let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { continue }
        buckets[start, default: 0] += day.usage.total
    }
    let starts: [Date]
    if let year {
        let allStarts = Array(weekStarts(for: year).prefix(52))
        if let month,
           let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
           let monthInterval = calendar.dateInterval(of: .month, for: monthStart) {
            starts = allStarts.filter { start in
                guard let end = calendar.date(byAdding: .day, value: 6, to: start) else { return false }
                return start < monthInterval.end && end >= monthInterval.start
            }
        } else {
            starts = allStarts
        }
    } else {
        starts = Array(buckets.keys.sorted().reversed().prefix(8).reversed())
    }
    let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? calendar.startOfDay(for: Date())
    let rows = starts.map { start in
        let total = buckets[start] ?? 0
        let usedValue = paymentPerToken * Double(total)
        let remainingValue = max(0, estimate.weeklyBudget - usedValue)
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let weekNumber = calendar.component(.weekOfYear, from: start)
        return CostPeriodRow(
            label: labelFormatter.string(from: start),
            title: "\(titleFormatter.string(from: start)) - \(titleFormatter.string(from: end))",
            subtitle: "\(t(.week)) \(weekNumber)",
            usedValue: usedValue,
            remainingValue: remainingValue,
            budgetValue: estimate.weeklyBudget,
            hasData: total > 0,
            isFuture: start > currentWeekStart
        )
    }
    guard !AppSettings.showHistoricalEmptyWeeks else { return rows }
    return rows.filter { $0.hasData || $0.isFuture }
}

private func monthlyCostRows(report: TokenReport, limit: LiveRateLimit?, year: Int? = nil) -> [CostPeriodRow] {
    guard let estimate = planCostEstimate(report: report, selectedDay: nil, limit: limit),
          estimate.weeklyBudget > 0 else {
        return []
    }
    let paymentPerToken = estimate.weeklyBudget / max(estimate.weeklyQuotaTotal, 1)
    var byMonth: [String: Int64] = [:]
    for day in report.byDay where day.usage.total > 0 {
        let monthKey = String(day.day.prefix(7))
        byMonth[monthKey, default: 0] += day.usage.total
    }
    let months: [String]
    if let year {
        months = (1...12).map { String(format: "%04d-%02d", year, $0) }
    } else {
        months = Array(byMonth.keys.sorted().reversed().prefix(6).reversed())
    }
    let currentMonth = String(dayFormatter().string(from: Date()).prefix(7))
    return months.map { month in
        let total = byMonth[month] ?? 0
        let usedValue = paymentPerToken * Double(total)
        let remainingValue = max(0, AppSettings.monthlyPlanCost - usedValue)
        return CostPeriodRow(
            label: String(month.suffix(2)),
            title: month,
            subtitle: t(.month),
            usedValue: usedValue,
            remainingValue: remainingValue,
            budgetValue: max(AppSettings.monthlyPlanCost, usedValue),
            hasData: total > 0,
            isFuture: month > currentMonth
        )
    }
}

private func monthlySpendRows(report: TokenReport, limit: LiveRateLimit?, year: Int? = nil) -> [MonthlySpendRow] {
    guard let estimate = planCostEstimate(report: report, selectedDay: nil, limit: limit),
          estimate.weeklyBudget > 0 else {
        return []
    }
    let paymentPerToken = estimate.weeklyBudget / max(estimate.weeklyQuotaTotal, 1)
    var byMonth: [String: Int64] = [:]
    for day in report.byDay where day.usage.total > 0 {
        let monthKey = String(day.day.prefix(7))
        byMonth[monthKey, default: 0] += day.usage.total
    }
    let months = byMonth.keys
        .filter { month in
            guard let year else { return true }
            return month.hasPrefix(String(format: "%04d-", year))
        }
        .sorted()
        .reversed()
        .prefix(12)
    return months.map { month in
        let total = byMonth[month] ?? 0
        let usedValue = paymentPerToken * Double(total)
        let planPercent = AppSettings.monthlyPlanCost > 0 ? usedValue / AppSettings.monthlyPlanCost * 100 : 0
        return MonthlySpendRow(month: month, usedValue: usedValue, usedPercentOfPlan: planPercent)
    }
}

private func planCostEstimate(report: TokenReport, selectedDay: DayUsage?, limit: LiveRateLimit?) -> PlanCostEstimate? {
    let monthlyCost = AppSettings.monthlyPlanCost
    guard monthlyCost > 0,
          let weekly = limit?.secondary,
          weekly.usedPercent > 0 else {
        return nil
    }
    let recentDays = Array(report.byDay.suffix(7))
    let recentWeekTotal = recentDays.reduce(Int64(0)) { $0 + $1.usage.total }
    guard recentWeekTotal > 0 else { return nil }

    let weeklyQuotaTotal = Double(recentWeekTotal) / max(weekly.usedPercent / 100, 0.0001)
    guard weeklyQuotaTotal > 0 else { return nil }

    let today = report.byDay.first { $0.day == todayKey() } ?? recentDays.last
    let selected = selectedDay ?? today
    let weeklyBudget = monthlyCost * 12 / 52
    let todayValue = weeklyBudget * Double(today?.usage.total ?? 0) / weeklyQuotaTotal
    let selectedValue = weeklyBudget * Double(selected?.usage.total ?? 0) / weeklyQuotaTotal
    let selectedPercent = Double(selected?.usage.total ?? 0) / weeklyQuotaTotal * 100
    let startDay = effectivePaymentStartDay(in: report)
    let parser = dayFormatter()
    let calendar = appCalendar()
    let startDate = parser.date(from: startDay) ?? calendar.startOfDay(for: Date())
    let todayDate = parser.date(from: todayKey()) ?? calendar.startOfDay(for: Date())
    let totalSpentValue = report.byDay.reduce(0.0) { partial, day in
        guard day.day >= startDay else { return partial }
        return partial + weeklyBudget * Double(day.usage.total) / weeklyQuotaTotal
    }
    let paidDays = max(1, (calendar.dateComponents([.day], from: startDate, to: todayDate).day ?? 0) + 1)
    let accruedBudget = Double(paidDays) * (weeklyBudget / 7)
    let totalWastedValue = max(0, accruedBudget - totalSpentValue)

    return PlanCostEstimate(
        monthlyCost: monthlyCost,
        weeklyBudget: weeklyBudget,
        weeklyQuotaTotal: weeklyQuotaTotal,
        todayValue: todayValue,
        selectedDayValue: selectedValue,
        weeklyUsedValue: weeklyBudget * weekly.usedPercent / 100,
        weeklyUnusedValue: weeklyBudget * weekly.remainingPercent / 100,
        totalSpentValue: totalSpentValue,
        totalWastedValue: totalWastedValue,
        selectedDayQuotaPercent: selectedPercent
    )
}

private func relative(_ date: Date?) -> String {
    guard let date else { return "--" }
    return relative(date)
}

private func relative(_ date: Date) -> String {
    let seconds = Int(date.timeIntervalSinceNow)
    let absSeconds = abs(seconds)
    let suffix = seconds >= 0 ? "" : " ago"
    if absSeconds < 60 { return seconds >= 0 ? "now" : "just now" }
    if absSeconds < 3600 { return "\(absSeconds / 60)m\(suffix)" }
    if absSeconds < 86400 { return "\(absSeconds / 3600)h\((absSeconds % 3600) / 60)m\(suffix)" }
    return "\(absSeconds / 86400)d\(suffix)"
}

if CommandLine.arguments.contains("--print-live") {
    let limits = LiveRateLimitReader().read()
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

if CommandLine.arguments.contains("--print") {
    let scanner = CodexTokenScanner(rootURL: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/sessions"))
    let requestedWindow = CommandLine.arguments
        .compactMap { argument -> WindowOption? in
            guard argument.hasPrefix("--window=") else { return nil }
            switch argument.dropFirst("--window=".count) {
            case "24h": return .day
            case "7d": return .week
            case "30d": return .month
            default: return nil
            }
        }
        .first
    let hours = CommandLine.arguments
        .compactMap { argument -> Int? in
            guard argument.hasPrefix("--hours=") else { return nil }
            return Int(argument.dropFirst("--hours=".count))
        }
        .first ?? WindowOption.week.rawValue
    let quota = CommandLine.arguments
        .compactMap { argument -> QuotaViewOption? in
            guard argument.hasPrefix("--quota=") else { return nil }
            return QuotaViewOption(rawValue: String(argument.dropFirst("--quota=".count)))
        }
        .first
    let report = requestedWindow.map { scanner.scan(window: $0, includedModelName: quota?.includedModelName, excludedModelName: quota?.excludedModelName) }
        ?? scanner.scan(hours: hours, includedModelName: quota?.includedModelName, excludedModelName: quota?.excludedModelName)
    let payload: [String: Any] = [
        "hours": requestedWindow?.rawValue ?? hours,
        "window": requestedWindow?.shortTitle ?? "rolling",
        "quota": quota?.rawValue ?? "all",
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
        "hour_buckets": report.byHour.count,
        "model_breakdown": report.modelBreakdown.map { model in
            [
                "name": model.name,
                "sessions": model.sessions,
                "events": model.events,
                "total": model.usage.total,
                "input": model.usage.input,
                "output": model.usage.output
            ] as [String: Any]
        },
        "by_day": report.byDay.map { day in
            [
                "day": day.day,
                "turns": day.turns,
                "input": day.usage.input,
                "cached_input": day.usage.cachedInput,
                "fresh_input": day.usage.freshInput,
                "output": day.usage.output,
                "reasoning_output": day.usage.reasoningOutput,
                "total": day.usage.total,
                "model_breakdown": day.modelBreakdown.map { model in
                    [
                        "name": model.name,
                        "sessions": model.sessions,
                        "events": model.events,
                        "total": model.usage.total,
                        "input": model.usage.input,
                        "output": model.usage.output
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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
