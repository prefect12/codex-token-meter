import Cocoa
import Foundation
import ServiceManagement
import UserNotifications

// MARK: - Details Window

struct DetailsSnapshot: Codable {
    var all: TokenReport
    var codex: TokenReport
    var claude: TokenReport
    var repoInsights: RepoInsightsReport
    var repoInsightReports: [Int: RepoInsightsReport] = [:]
    var codexRepoInsights: RepoInsightsReport = RepoInsightsReport(rows: [], scannedAt: Date(), windowDays: 90)
    var codexRepoInsightReports: [Int: RepoInsightsReport] = [:]
    var claudeRepoInsights: RepoInsightsReport = RepoInsightsReport(rows: [], scannedAt: Date(), windowDays: 90)
    var claudeRepoInsightReports: [Int: RepoInsightsReport] = [:]
    var liveLimits: [LiveRateLimit]
    var serviceStatus: CodexServiceStatusSnapshot?
    var costReferenceReport: TokenReport?
    var accountUsage: AccountUsageSnapshot? = nil
    var resetCredits: RateLimitResetCreditsSnapshot? = nil
}

struct DetailsLoadingProgress {
    var fraction: Double
    var messageKey: L10nKey

    static let starting = DetailsLoadingProgress(fraction: 0.08, messageKey: .loadingUsageDetails)

    var clampedFraction: Double {
        min(max(fraction, 0), 1)
    }
}

final class UsageDetailsWindowController: NSWindowController, NSWindowDelegate {
    let detailsView = UsageDetailsView(frame: NSRect(x: 0, y: 0, width: 900, height: 660))
    private let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 660))
    private var hasPresentedWindow = false

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = t(.detailsWindowTitle)
        window.isRestorable = false
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
        detailsView.onExpandReasoningWindow = { [weak self] in
            self?.expandReasoningWindow()
        }
        updateDocumentLayout()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func showLoading() {
        detailsView.isLoading = true
        detailsView.loadingProgress = .starting
        presentWindow()
        updateDocumentLayout()
    }

    func showCached(snapshot: DetailsSnapshot) {
        detailsView.snapshot = snapshot
        detailsView.isLoading = false
        presentWindow()
        updateDocumentLayout()
    }

    func showContent() {
        detailsView.isLoading = false
        presentWindow()
        updateDocumentLayout()
    }

    private func presentWindow() {
        showWindow(nil)
        if !hasPresentedWindow {
            window?.setContentSize(NSSize(width: 900, height: 660))
            hasPresentedWindow = true
        }
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    func updateLoadingProgress(_ progress: DetailsLoadingProgress) {
        guard detailsView.isLoading else { return }
        detailsView.loadingProgress = progress
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

    func updateResetCredits(_ resetCredits: RateLimitResetCreditsSnapshot?) {
        guard var snapshot = detailsView.snapshot else { return }
        snapshot.resetCredits = resetCredits
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

    private func expandReasoningWindow() {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let targetContentWidth = min(CGFloat(1400), visible.width - 64)
        guard targetContentWidth > window.contentLayoutRect.width + 20 else { return }
        let contentRect = NSRect(x: 0, y: 0, width: targetContentWidth, height: window.contentLayoutRect.height)
        var targetFrame = window.frameRect(forContentRect: contentRect)
        targetFrame.origin.x = min(max(visible.minX, window.frame.midX - targetFrame.width / 2), visible.maxX - targetFrame.width)
        targetFrame.origin.y = min(visible.maxY - targetFrame.height, window.frame.maxY - targetFrame.height)
        window.animator().setFrame(targetFrame, display: true)
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

enum DetailsSection: CaseIterable {
    case overview
    case calendar
    case models
    case reasoning
    case combinationRanking
    case insights
    case costs
    case storage
    case settings
    case diagnostics
    case about

    static var visibleSections: [DetailsSection] {
        allCases.filter(\.isVisibleInDetailsNavigation)
    }

    var isVisibleInDetailsNavigation: Bool {
        // Quota cycles page is hidden until its design is finalized.
        self != .costs && self != .combinationRanking
    }

    var visibleFallback: DetailsSection {
        if self == .combinationRanking {
            return .reasoning
        }
        return isVisibleInDetailsNavigation ? self : .overview
    }

    var title: String {
        switch self {
        case .overview: return t(.overview)
        case .insights: return AppLanguage.current.insightCopy.sidebarTitle
        case .reasoning: return AppLanguage.current == .chinese || AppLanguage.current == .traditionalChinese ? "思考分析" : "Reasoning"
        case .combinationRanking: return AppLanguage.current == .chinese || AppLanguage.current == .traditionalChinese ? "思考分析" : "Reasoning"
        case .models: return t(.models)
        case .calendar: return t(.calendar)
        case .costs: return t(.quotaCycles)
        case .storage: return AppLanguage.current.storageCopy.sidebarTitle
        case .settings: return t(.settings)
        case .diagnostics: return t(.diagnostics)
        case .about: return t(.about)
        }
    }

    var subtitle: String {
        switch self {
        case .overview: return t(.overviewSubtitle)
        case .insights: return AppLanguage.current.insightCopy.sidebarSubtitle
        case .reasoning: return AppLanguage.current == .chinese || AppLanguage.current == .traditionalChinese ? "比较模型在不同思考强度下的 Token 与成本" : "Compare Token usage and cost across reasoning efforts"
        case .combinationRanking: return AppLanguage.current == .chinese || AppLanguage.current == .traditionalChinese ? "实际使用的模型 × 思考强度组合表现" : "Actual model × reasoning-effort performance"
        case .models: return t(.modelsSubtitle)
        case .calendar: return t(.calendarSubtitle)
        case .costs: return t(.quotaCyclesSubtitle)
        case .storage: return AppLanguage.current.storageCopy.headerSubtitle
        case .settings: return t(.settingsSubtitle)
        case .diagnostics: return t(.diagnosticsSubtitle)
        case .about: return t(.aboutSubtitle)
        }
    }

    var headerTitle: String {
        switch self {
        case .insights:
            return AppLanguage.current.insightCopy.headerTitle
        case .reasoning:
            return AppLanguage.current == .chinese || AppLanguage.current == .traditionalChinese ? "思考分析" : "Reasoning"
        case .combinationRanking:
            return AppLanguage.current == .chinese || AppLanguage.current == .traditionalChinese ? "思考分析" : "Reasoning"
        case .storage:
            return AppLanguage.current.storageCopy.headerTitle
        case .overview:
            return t(.usageDetails)
        default:
            return title
        }
    }

    var canRenderWithoutSnapshot: Bool {
        switch self {
        case .settings, .about, .storage:
            return true
        default:
            return false
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

final class ContributionWeekHoverOverlayView: NSView {
    private var highlightRect: NSRect?
    private var dotHitRect: NSRect?
    private var accentColor = NSColor(calibratedRed: 0.279, green: 0.839, blue: 0.702, alpha: 1.0)

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func show(highlightRect: NSRect, dotHitRect: NSRect, accentColor: NSColor) {
        self.highlightRect = highlightRect
        self.dotHitRect = dotHitRect
        self.accentColor = accentColor
        isHidden = false
        needsDisplay = true
    }

    func hide() {
        guard !isHidden || highlightRect != nil || dotHitRect != nil else { return }
        highlightRect = nil
        dotHitRect = nil
        isHidden = true
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let highlightRect, let dotHitRect else { return }

        accentColor.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: highlightRect, xRadius: 7, yRadius: 7).fill()
        accentColor.withAlphaComponent(0.40).setStroke()
        let border = NSBezierPath(roundedRect: highlightRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        border.lineWidth = 1
        border.stroke()

        let radius: CGFloat = 3
        let dotRect = NSRect(
            x: dotHitRect.midX - radius,
            y: dotHitRect.midY - radius,
            width: radius * 2,
            height: radius * 2
        )
        NSColor.white.withAlphaComponent(0.85).setFill()
        NSBezierPath(ovalIn: dotRect).fill()
    }
}

final class UsageDetailsView: NSView, NSTextFieldDelegate, NSSearchFieldDelegate {
    struct CostRingCache {
        let key: String
        let image: NSImage
    }

    struct CostPageData {
        let key: String
        let estimate: PlanCostEstimate?
        let apiEstimate: APICostEstimate
        let weeklyRows: [CostPeriodRow]
        let monthlyRows: [MonthlySpendRow]
    }

    struct ContributionWeekSummary {
        let key: String
        let startDay: String
        let endDay: String
        let usage: Usage
        let total: Int64
        let activeDays: Int
        let turns: Int
        let days: [DayUsage]
        let hitRect: NSRect
        let cellRects: [NSRect]
    }

    struct ContributionDaySummary {
        let day: DayUsage
        let hitRect: NSRect
    }

    enum ContributionDragMode {
        case days
        case weeks
    }

    enum CostOverviewInfo: Hashable {
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

    enum InsightSortColumn: CaseIterable {
        case project
        case conversations
        case compressions
        case average
        case status

        var title: String {
            let copy = AppLanguage.current.insightCopy
            switch self {
            case .project: return copy.project
            case .conversations: return copy.conversations
            case .compressions: return copy.compressions
            case .average: return copy.average
            case .status: return copy.status
            }
        }

        var defaultAscending: Bool {
            switch self {
            case .project, .status:
                return true
            case .conversations, .compressions, .average:
                return false
            }
        }
    }

    enum InsightDetailMode: CaseIterable {
        case usageHabits
        case usageTime
        case reasoningDepth
    }

    struct ReasoningCellKey: Hashable {
        let model: String
        let effort: String
    }

    enum CombinationRankingMetric: CaseIterable {
        case totalTokens
        case averageTokens
        case totalCost
    }

    enum CombinationRankingSortColumn: CaseIterable {
        case model
        case effort
        case projects
        case tasks
        case totalTokens
        case averageTokens
        case freshInput
        case cachedInput
        case output
        case reasoningOutput
        case totalCost
        case costPerTask

        var defaultAscending: Bool {
            self == .model || self == .effort
        }
    }

    enum SettingsSubsection: CaseIterable {
        case appearance
        case data
        case quota
        case system

        var title: String {
            switch AppLanguage.current {
            case .chinese, .traditionalChinese:
                switch self {
                case .appearance: return "外观显示"
                case .data: return "数据来源"
                case .quota: return "额度提醒"
                case .system: return "系统"
                }
            case .japanese:
                switch self {
                case .appearance: return "表示"
                case .data: return "データソース"
                case .quota: return "制限と通知"
                case .system: return "システム"
                }
            default:
                switch self {
                case .appearance: return "Appearance"
                case .data: return "Data Sources"
                case .quota: return "Quota & Alerts"
                case .system: return "System"
                }
            }
        }

        var subtitle: String {
            switch AppLanguage.current {
            case .chinese, .traditionalChinese:
                switch self {
                case .appearance: return "语言、单位和状态栏"
                case .data: return "日志目录和 API 总量"
                case .quota: return "额度显示和提醒"
                case .system: return "启动行为"
                }
            case .japanese:
                switch self {
                case .appearance: return "言語、単位、メニューバー"
                case .data: return "ログルートと API 合計"
                case .quota: return "制限表示と通知"
                case .system: return "起動動作"
                }
            default:
                switch self {
                case .appearance: return "Language, units, and menu bar"
                case .data: return "Log roots and API totals"
                case .quota: return "Quota visuals and warnings"
                case .system: return "Startup behavior"
                }
            }
        }

        var symbolName: String {
            switch self {
            case .appearance: return "slider.horizontal.3"
            case .data: return "externaldrive"
            case .quota: return "bell.badge"
            case .system: return "power"
            }
        }
    }

    enum InsightStatusFilter: CaseIterable, Hashable {
        case all
        case frequentCompression
        case longRunning
        case good

        func matches(_ risk: RepoInsightRisk) -> Bool {
            switch self {
            case .all: return true
            case .frequentCompression: return risk == .frequentCompression
            case .longRunning: return risk == .longRunning
            case .good: return risk == .wellSplit || risk == .healthy
            }
        }
    }

    var snapshot: DetailsSnapshot? {
        didSet {
            if let snapshot {
                let report = calendarReport(for: snapshot)
                normalizeCalendarSelection(in: report, fallback: selectedDay)
                normalizeSelectedInsight(for: insightReport(for: snapshot))
                normalizeReasoningSelection(snapshot.codexRepoInsightReports[selectedInsightWindowDays]?.reasoning ?? snapshot.codexRepoInsights.reasoning)
                normalizeCombinationRankingSelection(snapshot: snapshot)
            }
            updateResetCreditCountdownTimer()
            onPreferredHeightChanged?()
            needsDisplay = true
            needsLayout = true
        }
    }
    var isLoading = false { didSet { updateResetCreditCountdownTimer(); onPreferredHeightChanged?(); needsDisplay = true; needsLayout = true } }
    var loadingProgress = DetailsLoadingProgress.starting { didSet { needsDisplay = true } }
    var onLanguageChanged: ((AppLanguage) -> Void)?
    var onNumberUnitStyleChanged: ((NumberUnitStyle) -> Void)?
    var onStatusBarMetricChanged: ((StatusBarMetricSlot, StatusBarMetric?) -> Void)?
    var onQuotaDisplayStyleChanged: ((QuotaDisplayStyle) -> Void)?
    var onCodexHomeRingMetricChanged: ((HomeQuotaRingMetric) -> Void)?
    var onClaudeHomeRingMetricChanged: ((HomeQuotaRingMetric) -> Void)?
    var onPlanCostChanged: ((Double, QuotaViewOption) -> Void)?
    var onPaymentStartDayChanged: ((String, QuotaViewOption) -> Void)?
    var onPaymentCurrencyChanged: ((CurrencyCode, QuotaViewOption) -> Void)?
    var onDisplayCurrencyChanged: ((CurrencyCode, QuotaViewOption) -> Void)?
    var onChooseLogFolder: (() -> Void)?
    var onResetLogFolder: (() -> Void)?
    var onOpenLogFolder: (() -> Void)?
    var onChooseCodexAPISource: (() -> Void)?
    var onResetCodexAPISources: (() -> Void)?
    var onOpenCodexAPISource: (() -> Void)?
    var onShowHistoricalEmptyWeeksChanged: ((Bool) -> Void)?
    var onLaunchAtLoginChanged: ((Bool) -> Void)?
    var onShowCodexStatusChanged: ((Bool) -> Void)?
    var onQuotaWarningsChanged: ((Bool) -> Void)?
    var onProfileAPITotalsChanged: ((Bool) -> Void)?
    var onExportMachineUsageReport: (() -> Void)?
    var onPreferredHeightChanged: (() -> Void)?
    var selectedSection: DetailsSection = .overview {
        didSet {
            if selectedSection.canRenderWithoutSnapshot {
                isLoading = false
            }
            if selectedSection != .costs {
                hoveredCostHistoryIndex = nil
                hoveredCostOverviewInfo = nil
                hoveredQuotaCycleIndex = nil
            }
            if selectedSection != .calendar {
                isHoveringDayValueInfo = false
                isHoveringProfileAPIInfo = false
            }
            if selectedSection != .calendar {
                hoveredContributionWeekKey = nil
                contributionWeekHoverOverlay.hide()
            }
            if selectedSection != .overview {
                hoveredContributionDay = nil
            }
            if selectedSection != .models {
                hoveredModelUsageRowIndex = nil
                modelUsageHoverRows.removeAll(keepingCapacity: true)
            }
            if selectedSection != .storage {
                hoveredStorageCellKey = nil
                hoveredStorageSourceID = nil
            }
            if selectedSection == .storage {
                requestStorageScanIfNeeded()
            }
            updateResetCreditCountdownTimer()
            onPreferredHeightChanged?()
            needsDisplay = true
            needsLayout = true
        }
    }
    var resetCreditCountdownTimer: Timer?
    var hoveredResetCreditIndex: Int?
    var resetCreditHitAreas: [(rect: NSRect, index: Int)] = []
    var resetCreditTooltipRows: [RateLimitResetCredit] = []
    var sidebarItemRects: [DetailsSection: NSRect] = [:]
    var insightRowRects: [String: NSRect] = [:]
    var insightWindowRects: [Int: NSRect] = [:]
    var insightDetailModeRects: [InsightDetailMode: NSRect] = [:]
    var insightSortRects: [InsightSortColumn: NSRect] = [:]
    var sourceOptionRects: [QuotaViewOption: NSRect] = [:]
    var insightListViewportRect: NSRect?
    let insightWindowOptions = [7, 30, 90]
    var selectedInsightWindowDays = 90
    var selectedDetailsSource: QuotaViewOption = .all {
        didSet {
            guard selectedDetailsSource != oldValue else { return }
            costPageDataCache = nil
            costRingCache = nil
            costYearOptionsCacheKey = nil
            if let snapshot {
                let report = calendarReport(for: snapshot)
                normalizeCalendarSelection(in: report, fallback: selectedDay)
                normalizeSelectedInsight(for: insightReport(for: snapshot))
            }
            onPreferredHeightChanged?()
            updateResetCreditCountdownTimer()
            needsDisplay = true
            needsLayout = true
        }
    }
    var selectedInsightKey: String?
    var selectedInsightSort: InsightSortColumn = .average
    var selectedInsightStatusFilter: InsightStatusFilter = .all
    var insightStatusFilterRects: [InsightStatusFilter: NSRect] = [:]
    var insightListContentHeight: CGFloat = 0
    var isInsightSortAscending = false
    var selectedInsightDetailMode: InsightDetailMode = .usageHabits
    var selectedReasoningModels = Set<String>()
    var selectedReasoningCell: ReasoningCellKey?
    var reasoningModelChipRects: [String: NSRect] = [:]
    var reasoningCellRects: [ReasoningCellKey: NSRect] = [:]
    var reasoningTrendDayRects: [String: NSRect] = [:]
    var hoveredReasoningDay: String?
    var selectedCombinationRankingMetric: CombinationRankingMetric = .averageTokens
    var selectedCombinationRankingModels = Set<String>()
    var selectedCombinationRankingCell: ReasoningCellKey?
    var combinationRankingMetricRects: [CombinationRankingMetric: NSRect] = [:]
    var combinationRankingModelFieldRect: NSRect?
    var combinationRankingModelOptionRects: [String: NSRect] = [:]
    var combinationRankingSortRects: [CombinationRankingSortColumn: NSRect] = [:]
    var combinationRankingRowRects: [ReasoningCellKey: NSRect] = [:]
    var combinationRankingBubbleRects: [ReasoningCellKey: NSRect] = [:]
    var isCombinationRankingModelMenuOpen = false
    var combinationRankingExpandHintRect: NSRect?
    var onExpandReasoningWindow: (() -> Void)?
    var selectedCombinationRankingSort: CombinationRankingSortColumn = .averageTokens
    var isCombinationRankingSortAscending = false
    var selectedSettingsSubsection: SettingsSubsection = .appearance {
        didSet {
            guard selectedSettingsSubsection != oldValue else { return }
            window?.makeFirstResponder(nil)
            layoutSettingsControls()
            needsDisplay = true
            needsLayout = true
        }
    }
    var insightHourRects: [Int: NSRect] = [:]
    var insightHourBarRects: [Int: NSRect] = [:]
    var insightPeriodRects: [String: NSRect] = [:]
    var hoveredInsightHour: Int?
    var hoveredInsightPeriod: String?
    var insightListScrollOffset: CGFloat = 0
    var numberUnitOptionRects: [NumberUnitStyle: NSRect] = [:]
    var quotaDisplayStyleRects: [QuotaDisplayStyle: NSRect] = [:]
    var codexHomeRingMetricRects: [HomeQuotaRingMetric: NSRect] = [:]
    var claudeHomeRingMetricRects: [HomeQuotaRingMetric: NSRect] = [:]
    var settingsSubsectionRects: [SettingsSubsection: NSRect] = [:]
    var chooseLogFolderRect: NSRect?
    var resetLogFolderRect: NSRect?
    var openLogFolderRect: NSRect?
    var chooseCodexAPISourceRect: NSRect?
    var resetCodexAPISourceRect: NSRect?
    var openCodexAPISourceRect: NSRect?
    var machineUsageExportRect: NSRect?
    var contributionDayRects: [String: NSRect] = [:]
    var contributionDaySummaries: [String: ContributionDaySummary] = [:]
    var hoveredContributionDay: String?
    var contributionWeekSummaries: [String: ContributionWeekSummary] = [:]
    var contributionWeekDotRects: [String: NSRect] = [:]
    var hoveredContributionWeekKey: String?
    let contributionWeekHoverOverlay = ContributionWeekHoverOverlayView(frame: .zero)
    var selectedContributionDays: Set<String> = []
    var contributionSelectionAnchor: (startDay: String, endDay: String)?
    var contributionGridSelectionRect: NSRect?
    var contributionDragMode: ContributionDragMode?
    var contributionDragStartPoint: CGPoint?
    var contributionDragBaseDays: Set<String> = []
    var contributionMarqueeRect: NSRect?
    var costHistoryBarRects: [Int: NSRect] = [:]
    var costHistoryRows: [CostPeriodRow] = []
    var costOverviewInfoRects: [CostOverviewInfo: NSRect] = [:]
    var dayValueInfoRect: NSRect?
    var profileAPIInfoRect: NSRect?
    var showHistoricalEmptyWeeksToggleRect: NSRect?
    var selectedDay: String?
    var hoveredCostHistoryIndex: Int?
    var quotaCycleHitAreas: [(rect: NSRect, index: Int)] = []
    var quotaCycleTooltipRows: [QuotaCycleRowModel] = []
    var hoveredQuotaCycleIndex: Int?
    var modelUsageHoverRows: [ModelUsageHoverRow] = []
    var hoveredModelUsageRowIndex: Int?
    var modelSortColumnRects: [ModelListSortOption: NSRect] = [:]
    let modelControls = ModelDetailsControls()
    var hoveredCostOverviewInfo: CostOverviewInfo?
    var isHoveringDayValueInfo = false
    var isHoveringProfileAPIInfo = false
    var selectedCostYear = Calendar.current.component(.year, from: Date())
    var costRingCache: CostRingCache?
    var costPageDataCache: CostPageData?
    var costYearOptionsCacheKey: String?
    var costYearOptionsCache: [Int] = []
    var costAmountEditingSource: QuotaViewOption?
    var paymentStartDayEditingSource: QuotaViewOption?
    let costAmountField: NSTextField = {
        let field = NSTextField()
        field.cell = VerticallyCenteredTextFieldCell(textCell: "")
        return field
    }()
    let paymentStartDayField: NSTextField = {
        let field = NSTextField()
        field.cell = VerticallyCenteredTextFieldCell(textCell: "")
        return field
    }()
    let paymentCurrencyPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let displayCurrencyPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let costYearPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let statusPrimaryMetricPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let statusSecondaryMetricPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let storageFilterPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let storageSortPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let storageSearchField = NSSearchField()
    let showHistoricalEmptyWeeksSwitch = NSSwitch(frame: .zero)
    let launchAtLoginSwitch = NSSwitch(frame: .zero)
    let showCodexStatusSwitch = NSSwitch(frame: .zero)
    let quotaWarningsSwitch = NSSwitch(frame: .zero)
    let profileAPITotalsSwitch = NSSwitch(frame: .zero)
    var isUpdatingCostControls = false
    var isUpdatingStatusMetricPopups = false
    var detailsTrackingArea: NSTrackingArea?

    var storageSnapshot: StorageSnapshot? {
        didSet {
            if selectedStorageCategoryID == nil, let storageSnapshot {
                selectedStorageCategoryID = storageSnapshot.categories
                    .filter { $0.bytes > 0 }
                    .max { $0.bytes < $1.bytes }?
                    .id
            }
            onPreferredHeightChanged?()
            needsDisplay = true
            needsLayout = true
        }
    }
    var isStorageScanning = false {
        didSet {
            onPreferredHeightChanged?()
            needsDisplay = true
            needsLayout = true
        }
    }
    var onStorageScanRequested: (() -> Void)?

    enum StorageSortOption: CaseIterable {
        case size
        case recent
        case name
    }

    struct StorageGrowthCell {
        let key: String
        let rect: NSRect
        let title: String
        let rows: [(StorageCategoryID, Int64)]
        let total: Int64
    }

    var storageSortOption: StorageSortOption = .size
    var storageFilterCategory: StorageCategoryID?
    var storageSearchText = ""
    var selectedStorageCategoryID: StorageCategoryID?
    var hoveredStorageCellKey: String?
    var hoveredStorageSourceID: StorageCategoryID?
    var storageGrowthCells: [StorageGrowthCell] = []
    var storageSourceRowRects: [StorageCategoryID: NSRect] = [:]
    var storageSourceMenuRects: [StorageCategoryID: NSRect] = [:]
    var storageOpenFinderRect: NSRect?
    var storageExportRect: NSRect?
    var storageRefreshRect: NSRect?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateResetCreditCountdownTimer()
    }

    deinit {
        resetCreditCountdownTimer?.invalidate()
    }

    var shouldAnimateResetCreditCountdown: Bool {
        guard window != nil,
              !isLoading,
              selectedSection == .overview,
              selectedDetailsSource != .claude,
              let resetCredits = snapshot?.resetCredits,
              resetCredits.availableCount > 0,
              resetCredits.nextExpiringAvailableCredit?.expiresAt != nil else {
            return false
        }
        return true
    }

    func updateResetCreditCountdownTimer() {
        if shouldAnimateResetCreditCountdown {
            guard resetCreditCountdownTimer == nil else { return }
            let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                guard self.shouldAnimateResetCreditCountdown else {
                    self.resetCreditCountdownTimer?.invalidate()
                    self.resetCreditCountdownTimer = nil
                    return
                }
                self.needsDisplay = true
            }
            resetCreditCountdownTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else {
            resetCreditCountdownTimer?.invalidate()
            resetCreditCountdownTimer = nil
        }
    }

    func requestStorageScanIfNeeded() {
        guard storageSnapshot == nil, !isStorageScanning else { return }
        isStorageScanning = true
        onStorageScanRequested?()
    }

    func showUsagePage() {
        selectedSection = .overview
    }

    func showInsightsPage(windowDays: Int = 90, insightMode: String? = nil) {
        if insightWindowOptions.contains(windowDays) {
            selectedInsightWindowDays = windowDays
        }
        if let insightMode {
            switch insightMode.lowercased() {
            case "time", "usage-time", "usage_time":
                selectedInsightDetailMode = .usageTime
            case "habits", "usage-habits", "usage_habits":
                selectedInsightDetailMode = .usageHabits
            case "reasoning", "reasoning-depth", "reasoning_depth", "effort":
                selectedInsightDetailMode = .reasoningDepth
                selectedDetailsSource = .codex
            default:
                break
            }
        }
        selectedSection = .insights
    }

    func showSection(_ section: DetailsSection, insightWindowDays: Int = 90, source: QuotaViewOption? = nil, insightMode: String? = nil) {
        if let source {
            selectedDetailsSource = source
        }
        let visibleSection = section.visibleFallback
        if visibleSection == .insights {
            showInsightsPage(windowDays: insightWindowDays, insightMode: insightMode)
        } else if visibleSection == .reasoning {
            selectedInsightWindowDays = insightWindowOptions.contains(insightWindowDays) ? insightWindowDays : 90
            selectedDetailsSource = .codex
            selectedSection = .reasoning
        } else if visibleSection == .combinationRanking {
            selectedInsightWindowDays = insightWindowOptions.contains(insightWindowDays) ? insightWindowDays : 90
            selectedSection = .combinationRanking
        } else {
            selectedSection = visibleSection
        }
    }

    func showSettingsPage() {
        selectedSection = .settings
    }

    let detailsSidebarWidth: CGFloat = 200
    let settingsContentTopOffset: CGFloat = 78
    let settingsPanelHeight: CGFloat = 548
    let settingsBottomPadding: CGFloat = 56
    let settingsSubnavWidth: CGFloat = 172

    var showsDetailsSourceSelector: Bool {
        switch selectedSection {
        case .overview, .models, .calendar, .costs, .diagnostics, .storage:
            return true
        case .insights, .reasoning, .combinationRanking, .settings, .about:
            return false
        }
    }

    func settingsPanelRect(in content: NSRect) -> NSRect {
        NSRect(
            x: content.minX,
            y: content.minY + settingsContentTopOffset,
            width: content.width,
            height: settingsPanelHeight
        )
    }

    func settingsPageRect(in panel: NSRect) -> NSRect {
        NSRect(
            x: panel.minX + settingsSubnavWidth + 34,
            y: panel.minY + 4,
            width: max(0, panel.width - settingsSubnavWidth - 34),
            height: panel.height - 8
        )
    }

    func sectionContent(for section: DetailsSection, in bounds: NSRect, sidebarWidth: CGFloat) -> NSRect {
        let full = NSRect(x: sidebarWidth + 28, y: 28, width: bounds.width - sidebarWidth - 56, height: bounds.height - 56)
        switch section {
        case .settings:
            return NSRect(x: full.minX, y: full.minY, width: min(full.width, 920), height: full.height)
        default:
            return full
        }
    }

    var visibleCostControlFrames: [NSRect] {
        []
    }

    var appBackgroundTop: NSColor {
        NSColor(calibratedRed: 0.055, green: 0.066, blue: 0.086, alpha: 1.0)
    }

    var appBackgroundBottom: NSColor {
        NSColor(calibratedRed: 0.075, green: 0.090, blue: 0.118, alpha: 1.0)
    }

    var sidebarBackgroundColor: NSColor {
        NSColor(calibratedRed: 0.046, green: 0.055, blue: 0.073, alpha: 1.0)
    }

    var panelSurfaceColor: NSColor {
        NSColor(calibratedRed: 0.126, green: 0.148, blue: 0.186, alpha: 0.98)
    }

    var panelElevatedColor: NSColor {
        NSColor(calibratedRed: 0.154, green: 0.178, blue: 0.222, alpha: 0.98)
    }

    var inputSurfaceColor: NSColor {
        NSColor(calibratedRed: 0.088, green: 0.105, blue: 0.138, alpha: 1.0)
    }

    var borderColor: NSColor {
        NSColor.white.withAlphaComponent(0.075)
    }

    var accentBlue: NSColor {
        NSColor(calibratedRed: 0.365, green: 0.548, blue: 1.0, alpha: 1.0)
    }

    var accentTeal: NSColor {
        NSColor(calibratedRed: 0.279, green: 0.839, blue: 0.702, alpha: 1.0)
    }

    var accentAmber: NSColor {
        NSColor(calibratedRed: 0.965, green: 0.724, blue: 0.357, alpha: 1.0)
    }

    var accentRose: NSColor {
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
        contributionWeekHoverOverlay.frame = bounds
        layoutCostControls()
        layoutSettingsControls()
        layoutStorageControls()
        layoutModelControls()
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

    func setupControls() {
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

        for popup in [paymentCurrencyPopup, displayCurrencyPopup, costYearPopup, languagePopup, statusPrimaryMetricPopup, statusSecondaryMetricPopup] {
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
        updateStatusMetricPopupsFromSettings()
        costAmountField.setAccessibilityLabel(t(.paymentMonthly))
        paymentStartDayField.setAccessibilityLabel(t(.paymentStartDate))
        paymentCurrencyPopup.setAccessibilityLabel(t(.paymentCurrency))
        displayCurrencyPopup.setAccessibilityLabel(t(.displayCurrency))
        costYearPopup.setAccessibilityLabel(t(.costHistory))
        languagePopup.setAccessibilityLabel(t(.interfaceLanguage))
        statusPrimaryMetricPopup.setAccessibilityLabel(t(.statusBarMetricOne))
        statusSecondaryMetricPopup.setAccessibilityLabel(t(.statusBarMetricTwo))
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
        statusPrimaryMetricPopup.target = self
        statusPrimaryMetricPopup.action = #selector(statusPrimaryMetricPopupChanged)
        statusSecondaryMetricPopup.target = self
        statusSecondaryMetricPopup.action = #selector(statusSecondaryMetricPopupChanged)

        for popup in [storageFilterPopup, storageSortPopup] {
            popup.controlSize = .small
            popup.font = .systemFont(ofSize: 11, weight: .semibold)
            popup.isBordered = false
            popup.isHidden = true
            popup.wantsLayer = true
            popup.layer?.cornerRadius = 7
            popup.layer?.backgroundColor = inputSurfaceColor.cgColor
            popup.appearance = NSAppearance(named: .darkAqua)
            addSubview(popup)
        }
        storageFilterPopup.target = self
        storageFilterPopup.action = #selector(storageFilterPopupChanged)
        storageSortPopup.target = self
        storageSortPopup.action = #selector(storageSortPopupChanged)
        storageSearchField.controlSize = .small
        storageSearchField.font = .systemFont(ofSize: 11)
        storageSearchField.isHidden = true
        storageSearchField.appearance = NSAppearance(named: .darkAqua)
        storageSearchField.delegate = self
        storageSearchField.sendsWholeSearchString = false
        storageSearchField.sendsSearchStringImmediately = true
        addSubview(storageSearchField)

        modelControls.install(in: self, inputSurfaceColor: inputSurfaceColor)
        modelControls.onChange = { [weak self] in
            guard let self else { return }
            self.hoveredModelUsageRowIndex = nil
            self.onPreferredHeightChanged?()
            self.needsDisplay = true
            self.needsLayout = true
        }

        contributionWeekHoverOverlay.frame = bounds
        contributionWeekHoverOverlay.autoresizingMask = [.width, .height]
        contributionWeekHoverOverlay.wantsLayer = true
        contributionWeekHoverOverlay.layer?.backgroundColor = NSColor.clear.cgColor
        contributionWeekHoverOverlay.isHidden = true
        addSubview(contributionWeekHoverOverlay, positioned: .above, relativeTo: nil)
    }

    func layoutCostControls() {
        // The quota-cycle page replaced the legacy money page; its plan-cost
        // input controls stay hidden everywhere.
        costAmountField.isHidden = true
        paymentStartDayField.isHidden = true
        paymentCurrencyPopup.isHidden = true
        displayCurrencyPopup.isHidden = true
        costYearPopup.isHidden = true
        showHistoricalEmptyWeeksSwitch.isHidden = true
        showHistoricalEmptyWeeksToggleRect = nil
    }

    func layoutSettingsControls() {
        let visible = selectedSection == .settings
        languagePopup.isHidden = !(visible && selectedSettingsSubsection == .appearance)
        displayCurrencyPopup.isHidden = !(visible && selectedSettingsSubsection == .appearance)
        statusPrimaryMetricPopup.isHidden = !(visible && selectedSettingsSubsection == .appearance)
        statusSecondaryMetricPopup.isHidden = !(visible && selectedSettingsSubsection == .appearance)
        launchAtLoginSwitch.isHidden = !(visible && selectedSettingsSubsection == .system)
        showCodexStatusSwitch.isHidden = !(visible && selectedSettingsSubsection == .quota)
        quotaWarningsSwitch.isHidden = !(visible && selectedSettingsSubsection == .quota)
        profileAPITotalsSwitch.isHidden = !(visible && selectedSettingsSubsection == .data)
        guard visible else { return }

        let content = sectionContent(for: .settings, in: bounds, sidebarWidth: detailsSidebarWidth)
        let rect = settingsPanelRect(in: content)
        let pageRect = settingsPageRect(in: rect)
        let controlWidth = min(300, max(224, pageRect.width * 0.40))
        let controlX = pageRect.maxX - controlWidth
        let switchX = pageRect.maxX - 50
        languagePopup.frame = NSRect(x: controlX, y: pageRect.minY + 70, width: controlWidth, height: 36)
        displayCurrencyPopup.frame = NSRect(x: controlX, y: pageRect.minY + 146, width: controlWidth, height: 36)
        statusPrimaryMetricPopup.frame = NSRect(x: controlX, y: pageRect.minY + 300, width: controlWidth, height: 36)
        statusSecondaryMetricPopup.frame = NSRect(x: controlX, y: pageRect.minY + 370, width: controlWidth, height: 36)
        profileAPITotalsSwitch.frame = NSRect(x: switchX, y: pageRect.minY + 320, width: 48, height: 24)
        showCodexStatusSwitch.frame = NSRect(x: switchX, y: pageRect.minY + 306, width: 48, height: 24)
        quotaWarningsSwitch.frame = NSRect(x: switchX, y: pageRect.minY + 390, width: 48, height: 24)
        launchAtLoginSwitch.frame = NSRect(x: switchX, y: pageRect.minY + 76, width: 48, height: 24)
        updateLanguagePopupFromSettings()
        updateDisplayCurrencyPopupFromSettings()
        updateStatusMetricPopupsFromSettings()
        updateSettingsControlsFromSystem()
    }

    func updateLanguagePopupFromSettings() {
        if languagePopup.itemArray.map(\.title) != AppLanguage.allCases.map(\.displayName) {
            languagePopup.removeAllItems()
            languagePopup.addItems(withTitles: AppLanguage.allCases.map(\.displayName))
        }
        if let index = AppLanguage.allCases.firstIndex(of: AppLanguage.current) {
            languagePopup.selectItem(at: index)
        }
    }

    func updateDisplayCurrencyPopupFromSettings() {
        let titles = CurrencyCode.allCases.map(\.displayTitle)
        if displayCurrencyPopup.itemArray.map(\.title) != titles {
            displayCurrencyPopup.removeAllItems()
            displayCurrencyPopup.addItems(withTitles: titles)
        }
        if let index = CurrencyCode.allCases.firstIndex(of: AppSettings.displayCurrency(for: .all)) {
            displayCurrencyPopup.selectItem(at: index)
        }
    }

    func updateSettingsControlsFromSystem() {
        guard selectedSection == .settings else { return }
        launchAtLoginSwitch.state = LoginItemManager.isEnabled ? .on : .off
        showCodexStatusSwitch.state = AppSettings.showCodexStatusEnabled ? .on : .off
        quotaWarningsSwitch.state = AppSettings.quotaWarningsEnabled ? .on : .off
        profileAPITotalsSwitch.state = AppSettings.profileAPITotalsEnabled ? .on : .off
    }

    func updateStatusMetricPopupsFromSettings() {
        isUpdatingStatusMetricPopups = true
        defer { isUpdatingStatusMetricPopups = false }

        let metricTitles = StatusBarMetric.allCases.map(\.title)
        if statusPrimaryMetricPopup.itemArray.map(\.title) != metricTitles {
            statusPrimaryMetricPopup.removeAllItems()
            statusPrimaryMetricPopup.addItems(withTitles: metricTitles)
        }
        if let primaryIndex = StatusBarMetric.allCases.firstIndex(of: AppSettings.statusBarPrimaryMetric) {
            statusPrimaryMetricPopup.selectItem(at: primaryIndex)
        }

        let secondaryTitles = [t(.statusMetricOff)] + metricTitles
        if statusSecondaryMetricPopup.itemArray.map(\.title) != secondaryTitles {
            statusSecondaryMetricPopup.removeAllItems()
            statusSecondaryMetricPopup.addItems(withTitles: secondaryTitles)
        }
        if let secondaryMetric = AppSettings.statusBarSecondaryMetric,
           let secondaryIndex = StatusBarMetric.allCases.firstIndex(of: secondaryMetric) {
            statusSecondaryMetricPopup.selectItem(at: secondaryIndex + 1)
        } else {
            statusSecondaryMetricPopup.selectItem(at: 0)
        }
    }

    func updateCostControlsFromSettings() {
        guard selectedSection == .costs else { return }
        isUpdatingCostControls = true
        defer { isUpdatingCostControls = false }
        let costSource = selectedDetailsSource
        let isEditableSource = costSource != .all
        costAmountField.isEnabled = isEditableSource
        paymentStartDayField.isEnabled = isEditableSource
        paymentCurrencyPopup.isEnabled = isEditableSource
        displayCurrencyPopup.isEnabled = isEditableSource
        costAmountField.textColor = isEditableSource ? .white : NSColor.white.withAlphaComponent(0.58)
        paymentStartDayField.textColor = isEditableSource ? .white : NSColor.white.withAlphaComponent(0.58)
        if costAmountField.currentEditor() == nil {
            costAmountField.stringValue = paymentAmount(AppSettings.monthlyPlanCost(for: costSource), source: costSource)
        }
        let costReport = snapshot.map { sourceReport(for: $0) }
        if paymentStartDayField.currentEditor() == nil {
            paymentStartDayField.stringValue = isEditableSource
                ? effectivePaymentStartDay(in: costReport, paymentStartDay: AppSettings.paymentStartDay(for: costSource))
                : "--"
        }
        showHistoricalEmptyWeeksSwitch.state = AppSettings.showHistoricalEmptyWeeks ? .on : .off
        if let paymentIndex = CurrencyCode.allCases.firstIndex(of: AppSettings.paymentCurrency(for: costSource)) {
            paymentCurrencyPopup.selectItem(at: paymentIndex)
        }
        if let displayIndex = CurrencyCode.allCases.firstIndex(of: AppSettings.displayCurrency(for: costSource)) {
            displayCurrencyPopup.selectItem(at: displayIndex)
        }
        let years = cachedAvailableCostYears(from: costReport, source: costSource)
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
        let contentWidth = normalizedWidth - detailsSidebarWidth - 56

        let targetHeight: CGFloat
        switch selectedSection {
        case .overview:
            // The Claude view hides the Codex reset-credits row (see drawOverview),
            // while Codex/all expands it when reset credits wrap to another row.
            if selectedDetailsSource == .claude {
                targetHeight = 746
            } else if let snapshot {
                targetHeight = 762 + resetCreditPanelHeight(for: snapshot)
            } else {
                targetHeight = 850
            }
        case .insights:
            let heatmapHeight: CGFloat = 148
            let topOffset: CGFloat = 78
            let bottomPadding: CGFloat = 44
            if selectedInsightDetailMode == .reasoningDepth {
                targetHeight = topOffset + 74 + 12 + 282 + 12 + 240 + bottomPadding
            } else if contentWidth >= 940 {
                targetHeight = topOffset + 444 + 16 + heatmapHeight + bottomPadding
            } else {
                let listHeight: CGFloat = 444
                let detailHeight: CGFloat = 430
                targetHeight = topOffset + listHeight + 16 + detailHeight + 16 + heatmapHeight + bottomPadding
            }
        case .reasoning:
            targetHeight = contentWidth < 900 ? 1_390 : 968
        case .combinationRanking:
            targetHeight = contentWidth < 900 ? 1_390 : 968
        case .models:
            let tableHeight = snapshot.map { modelListPresentation(for: $0).tableHeight } ?? 132
            targetHeight = 410 + tableHeight
        case .calendar:
            let gridHeight: CGFloat = normalizedWidth >= 1200 ? 246 : 232
            let detailHeight = selectedCalendarRangeSummary() != nil
                ? selectedWeekPanelPreferredHeight(contentWidth: contentWidth)
                : selectedDayPanelPreferredHeight(contentWidth: contentWidth)
            targetHeight = 174 + gridHeight + detailHeight
        case .costs:
            let topOffset: CGFloat = 78
            let sectionGap: CGFloat = 16
            let fiveHourPanelHeight: CGFloat = 176
            let bottomPadding: CGFloat = 44
            if let snapshot {
                let model = quotaCyclePageModel(for: snapshot)
                if model.moneySummary != nil {
                    targetHeight = topOffset + 96 + sectionGap + 172 + sectionGap + 330 + sectionGap + fiveHourPanelHeight + bottomPadding
                } else {
                    let weeklyPanelHeight = weeklyHistoryPanelHeight(rowCount: model.weeklyRows.count, contentWidth: contentWidth)
                    targetHeight = topOffset + 150 + sectionGap + weeklyPanelHeight + sectionGap + fiveHourPanelHeight + bottomPadding
                }
            } else {
                targetHeight = topOffset + 150 + sectionGap + 96 + sectionGap + fiveHourPanelHeight + bottomPadding
            }
        case .diagnostics:
            targetHeight = 714
        case .storage:
            if storageSnapshot != nil {
                let content = NSRect(x: 0, y: 28, width: contentWidth, height: 0)
                targetHeight = storagePageLayout(content: content).totalHeight
            } else {
                targetHeight = 660
            }
        case .settings:
            targetHeight = settingsContentTopOffset + settingsPanelHeight + settingsBottomPadding
        case .about:
            targetHeight = 580
        }
        return max(minHeight, targetHeight)
    }

    func selectedDayPanelPreferredHeight(contentWidth: CGFloat) -> CGFloat {
        guard let snapshot else { return 248 }
        let report = calendarReport(for: snapshot)
        let day = selectedCalendarDay(in: report)
        if usesProfileAPIReport(for: snapshot), !profileSelectedDayUsesLocalFallback(snapshot: snapshot, report: report) {
            let localDay = day.flatMap { profileDay in snapshot.codex.byDay.first { $0.day == profileDay.day } }
            let apiEstimate = day.map { profileAPIDayEstimate(profileDay: $0, localDay: localDay) }
            let metricsCount = 3 + (apiEstimate?.hasPricedUsage == true ? 1 : 0)
            let startX = min(CGFloat(420), max(CGFloat(292), contentWidth * 0.50))
            let gap: CGFloat = 12
            let availableMetricWidth = max(0, contentWidth - startX - 18)
            let columns = metricsCount > 3 && availableMetricWidth >= 500 ? 4 : min(3, metricsCount)
            let metricRows = Int(ceil(Double(metricsCount) / Double(max(columns, 1))))
            let metricH: CGFloat = 74
            let metricsBottom = CGFloat(42) + CGFloat(metricRows) * metricH + CGFloat(max(0, metricRows - 1)) * gap
            let modelRows = max(1, localDay?.modelBreakdown.count ?? 0)
            let minimumModelHeight = 22 + CGFloat(modelRows) * 22
            let modelY = max(CGFloat(134), metricsBottom + 18)
            return max(284, modelY + minimumModelHeight + 18)
        }
        guard let day else { return 160 }

        let limit = sourceCostLimit(for: snapshot)
        let cost = planCostEstimate(
            report: report,
            selectedDay: day,
            limit: limit,
            quotaReferenceReport: sourceCostReferenceReport(for: snapshot),
            monthlyCost: AppSettings.monthlyPlanCost(for: selectedDetailsSource),
            paymentStartDay: AppSettings.paymentStartDay(for: selectedDetailsSource)
        )
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
        let modelRows = max(1, day.modelBreakdown.count)
        let minimumModelHeight = 22 + CGFloat(modelRows) * 22
        let leftColumnBottom: CGFloat = daySourceSplit(snapshot: snapshot, day: day) != nil ? daySourceSplitPanelExtent : 112
        let modelY = max(leftColumnBottom, metricsBottom + 12)
        let contentHeight = modelY + minimumModelHeight + 18
        return max(248, contentHeight)
    }

    func selectedWeekPanelPreferredHeight(contentWidth: CGFloat) -> CGFloat {
        guard let snapshot, let summary = selectedCalendarRangeSummary() else { return 248 }
        let planValue = contributionWeekPlanValue(summary)
        let apiEstimate = contributionWeekAPIEstimate(summary)
        let metricsCount = 4 + (planValue == nil ? 0 : 1) + (apiEstimate.hasPricedUsage ? 1 : 0)
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
        let modelRows = max(1, weekModelBreakdown(summary).count)
        let minimumModelHeight = 22 + CGFloat(modelRows) * 22
        let leftColumnBottom: CGFloat = weekSourceSplit(snapshot: snapshot, summary: summary) != nil ? daySourceSplitPanelExtent : 112
        let modelY = max(leftColumnBottom, metricsBottom + 12)
        return max(248, modelY + minimumModelHeight + 18)
    }

    func sourceReport(for snapshot: DetailsSnapshot, source: QuotaViewOption? = nil) -> TokenReport {
        switch source ?? selectedDetailsSource {
        case .all:
            return snapshot.all
        case .codex:
            return snapshot.codex
        case .claude:
            return snapshot.claude
        }
    }

    func modelListPresentation(for snapshot: DetailsSnapshot) -> ModelListPresentation {
        ModelListPresentation.make(
            report: sourceReport(for: snapshot),
            query: modelControls.query,
            sort: modelControls.sort,
            direction: modelControls.direction
        )
    }

    func sourceCostLimit(for snapshot: DetailsSnapshot) -> LiveRateLimit? {
        guard selectedDetailsSource != .claude else { return nil }
        return costEstimateLimit(from: snapshot.liveLimits)
    }

    func sourceCostReferenceReport(for snapshot: DetailsSnapshot) -> TokenReport? {
        guard selectedDetailsSource != .claude else { return nil }
        return snapshot.costReferenceReport
    }

    func usesProfileAPIReport(for snapshot: DetailsSnapshot) -> Bool {
        selectedDetailsSource == .codex
            && selectedSection != .calendar
            && AppSettings.profileAPITotalsEnabled
            && snapshot.accountUsage?.hasData == true
    }

    func calendarReport(for snapshot: DetailsSnapshot) -> TokenReport {
        guard let report = rawProfileCalendarReport(for: snapshot) else {
            return sourceReport(for: snapshot)
        }
        return profileReportWithLocalFallback(report, localReport: snapshot.codex)
    }

    func rawProfileCalendarReport(for snapshot: DetailsSnapshot) -> TokenReport? {
        guard usesProfileAPIReport(for: snapshot),
              let accountUsage = snapshot.accountUsage else {
            return nil
        }
        return accountUsage.report(days: 365)
    }

    func selectedCalendarDay(in report: TokenReport) -> DayUsage? {
        selectedDay.flatMap { selected in report.byDay.first { $0.day == selected } }
            ?? report.byDay.last(where: { $0.usage.total > 0 })
            ?? report.byDay.last
    }

    func profileSelectedDayUsesLocalFallback(snapshot: DetailsSnapshot, report: TokenReport) -> Bool {
        guard usesProfileAPIReport(for: snapshot),
              let day = selectedCalendarDay(in: report),
              let localDay = snapshot.codex.byDay.first(where: { $0.day == day.day }),
              localDay.usage.total > 0 else {
            return false
        }
        let rawProfileTotal = rawProfileCalendarReport(for: snapshot)?
            .byDay
            .first { $0.day == day.day }?
            .usage
            .total ?? 0
        return rawProfileTotal == 0 && day.usage.total == localDay.usage.total
    }

    func profileLifetimeTotal(for snapshot: DetailsSnapshot) -> Int64? {
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
            updateQuotaCycleHover(at: point)
        } else {
            if hoveredCostHistoryIndex != nil {
                hoveredCostHistoryIndex = nil
                needsDisplay = true
            }
            if hoveredQuotaCycleIndex != nil {
                hoveredQuotaCycleIndex = nil
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
        updateResetCreditHover(at: point)
        updateInsightUsageTimeHover(at: point)
        updateReasoningTrendHover(at: point)
        updateModelUsageRowHover(at: point)
        updateStorageGrowthHover(at: point)
    }

    func updateStorageGrowthHover(at point: CGPoint) {
        guard selectedSection == .storage else {
            if hoveredStorageCellKey != nil || hoveredStorageSourceID != nil {
                hoveredStorageCellKey = nil
                hoveredStorageSourceID = nil
                needsDisplay = true
            }
            return
        }
        let match = storageGrowthCells.first { $0.rect.insetBy(dx: -2, dy: -2).contains(point) }
        if hoveredStorageCellKey != match?.key {
            hoveredStorageCellKey = match?.key
            needsDisplay = true
        }
        let sourceMatch = storageSourceRowRects.first { entry in
            var zone = entry.value
            zone.size.width = max(0, zone.width - 130)
            return zone.contains(point)
        }?.key
        if hoveredStorageSourceID != sourceMatch {
            hoveredStorageSourceID = sourceMatch
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredCostHistoryIndex = nil
        hoveredCostOverviewInfo = nil
        hoveredContributionDay = nil
        hoveredContributionWeekKey = nil
        contributionWeekHoverOverlay.hide()
        hoveredInsightHour = nil
        hoveredInsightPeriod = nil
        hoveredReasoningDay = nil
        hoveredResetCreditIndex = nil
        hoveredModelUsageRowIndex = nil
        hoveredStorageCellKey = nil
        hoveredStorageSourceID = nil
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
            contributionWeekHoverOverlay.hide()
        }
        if hoveredInsightHour != nil {
            hoveredInsightHour = nil
            shouldRedraw = true
        }
        if hoveredInsightPeriod != nil {
            hoveredInsightPeriod = nil
            shouldRedraw = true
        }
        if hoveredResetCreditIndex != nil {
            hoveredResetCreditIndex = nil
            shouldRedraw = true
        }
        if hoveredModelUsageRowIndex != nil {
            hoveredModelUsageRowIndex = nil
            shouldRedraw = true
        }
        if hoveredStorageCellKey != nil {
            hoveredStorageCellKey = nil
            shouldRedraw = true
        }
        if hoveredStorageSourceID != nil {
            hoveredStorageSourceID = nil
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
        if scrollInsightListIfNeeded(with: event) {
            return
        }
        super.scrollWheel(with: event)
    }

    func scrollInsightListIfNeeded(with event: NSEvent) -> Bool {
        guard selectedSection == .insights,
              let viewport = insightListViewportRect,
              viewport.contains(convert(event.locationInWindow, from: nil)) else {
            return false
        }

        let maxOffset = max(0, insightListContentHeight - viewport.height)
        guard maxOffset > 0 else { return false }

        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
        insightListScrollOffset = min(max(0, insightListScrollOffset - delta), maxOffset)
        needsDisplay = true
        return true
    }

    func updateContributionDayHover(at point: CGPoint) {
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

    func updateContributionWeekHover(at point: CGPoint) {
        guard selectedSection == .calendar else {
            if hoveredContributionWeekKey != nil {
                hoveredContributionWeekKey = nil
                contributionWeekHoverOverlay.hide()
            }
            return
        }
        let match = contributionWeekDotRects.first {
            $0.value.insetBy(dx: -3, dy: -3).contains(point)
        }
        let newKey = match?.key
        if hoveredContributionWeekKey != newKey {
            hoveredContributionWeekKey = newKey
            updateContributionWeekHoverOverlay()
        }
    }

    func updateContributionWeekHoverOverlay() {
        guard selectedSection == .calendar,
              let key = hoveredContributionWeekKey,
              let summary = contributionWeekSummaries[key],
              !isContributionWeekFullySelected(summary),
              let dotRect = contributionWeekDotRects[key] else {
            contributionWeekHoverOverlay.hide()
            return
        }
        contributionWeekHoverOverlay.show(
            highlightRect: summary.hitRect.insetBy(dx: -4, dy: -4),
            dotHitRect: dotRect,
            accentColor: accentTeal
        )
    }

    func updateResetCreditHover(at point: CGPoint) {
        guard selectedSection == .overview else {
            if hoveredResetCreditIndex != nil {
                hoveredResetCreditIndex = nil
                needsDisplay = true
            }
            return
        }
        let match = resetCreditHitAreas.first { $0.rect.insetBy(dx: -4, dy: -4).contains(point) }
        let newIndex = match?.index
        if hoveredResetCreditIndex != newIndex {
            hoveredResetCreditIndex = newIndex
            needsDisplay = true
        }
    }

    func updateModelUsageRowHover(at point: CGPoint) {
        guard selectedSection == .models else {
            if hoveredModelUsageRowIndex != nil {
                hoveredModelUsageRowIndex = nil
                needsDisplay = true
            }
            return
        }
        let newIndex = modelUsageHoverRows.firstIndex { $0.rect.insetBy(dx: -3, dy: -2).contains(point) }
        if hoveredModelUsageRowIndex != newIndex {
            hoveredModelUsageRowIndex = newIndex
            needsDisplay = true
        }
    }

    func updateCostHistoryHover(at point: CGPoint) {
        let match = costHistoryBarRects.first { $0.value.insetBy(dx: -4, dy: -4).contains(point) }
        let newIndex = match?.key
        if hoveredCostHistoryIndex != newIndex {
            hoveredCostHistoryIndex = newIndex
            needsDisplay = true
        }
    }

    func updateCostOverviewInfoHover(at point: CGPoint) {
        let match = costOverviewInfoRects.first { $0.value.insetBy(dx: -4, dy: -4).contains(point) }
        let newInfo = match?.key
        if hoveredCostOverviewInfo != newInfo {
            hoveredCostOverviewInfo = newInfo
            needsDisplay = true
        }
    }

    func updateInsightUsageTimeHover(at point: CGPoint) {
        guard selectedSection == .insights, selectedInsightDetailMode == .usageTime else {
            if hoveredInsightHour != nil || hoveredInsightPeriod != nil {
                hoveredInsightHour = nil
                hoveredInsightPeriod = nil
                needsDisplay = true
            }
            return
        }
        let newHour = insightHourRects.first { $0.value.insetBy(dx: -3, dy: -3).contains(point) }?.key
        let newPeriod = newHour == nil ? insightPeriodRects.first { $0.value.insetBy(dx: -3, dy: -3).contains(point) }?.key : nil
        if hoveredInsightHour != newHour || hoveredInsightPeriod != newPeriod {
            hoveredInsightHour = newHour
            hoveredInsightPeriod = newPeriod
            needsDisplay = true
        }
    }

    func updateReasoningTrendHover(at point: CGPoint) {
        guard selectedSection == .reasoning else {
            if hoveredReasoningDay != nil {
                hoveredReasoningDay = nil
                needsDisplay = true
            }
            return
        }
        let newDay = reasoningTrendDayRects.first { $0.value.insetBy(dx: -3, dy: -6).contains(point) }?.key
        if hoveredReasoningDay != newDay {
            hoveredReasoningDay = newDay
            needsDisplay = true
        }
    }

    func updateDayValueInfoHover(at point: CGPoint) {
        let hovering = selectedSection == .calendar && (dayValueInfoRect?.contains(point) == true)
        if hovering != isHoveringDayValueInfo {
            isHoveringDayValueInfo = hovering
            needsDisplay = true
        }
    }

    func updateProfileAPIInfoHover(at point: CGPoint) {
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
            if section == .calendar, let snapshot {
                let report = calendarReport(for: snapshot)
                normalizeCalendarSelection(in: report, fallback: selectedDay)
            }
            if section == .insights, let snapshot {
                normalizeSelectedInsight(for: insightReport(for: snapshot))
            }
            if section == .reasoning, let snapshot {
                normalizeCombinationRankingSelection(snapshot: snapshot)
            }
            return
        }
        for (source, rect) in sourceOptionRects where rect.contains(point) {
            window?.makeFirstResponder(nil)
            selectedDetailsSource = source
            return
        }
        if selectedSection == .models {
            for (option, rect) in modelSortColumnRects where rect.contains(point) {
                modelControls.toggleSort(option)
                return
            }
        }
        if selectedSection == .insights {
            for (filter, rect) in insightStatusFilterRects where rect.contains(point) {
                selectedInsightStatusFilter = filter
                insightListScrollOffset = 0
                needsDisplay = true
                return
            }
            for (days, rect) in insightWindowRects where rect.contains(point) {
                selectedInsightWindowDays = days
                if let snapshot {
                    normalizeSelectedInsight(for: insightReport(for: snapshot))
                }
                needsDisplay = true
                return
            }
            for (mode, rect) in insightDetailModeRects where rect.contains(point) {
                selectedInsightDetailMode = mode
                if mode == .reasoningDepth {
                    selectedDetailsSource = .codex
                }
                needsDisplay = true
                return
            }
            for (column, rect) in insightSortRects where rect.insetBy(dx: -4, dy: -4).contains(point) {
                if selectedInsightSort == column {
                    isInsightSortAscending.toggle()
                } else {
                    selectedInsightSort = column
                    isInsightSortAscending = column.defaultAscending
                }
                insightListScrollOffset = 0
                if let snapshot {
                    normalizeSelectedInsight(for: insightReport(for: snapshot))
                }
                needsDisplay = true
                return
            }
            for (key, rect) in insightRowRects where rect.contains(point) {
                selectedInsightKey = key
                needsDisplay = true
                return
            }
        }
        if selectedSection == .reasoning || selectedSection == .combinationRanking {
            if combinationRankingExpandHintRect?.contains(point) == true {
                onExpandReasoningWindow?()
                return
            }
            if isCombinationRankingModelMenuOpen {
                for (model, rect) in combinationRankingModelOptionRects where rect.contains(point) {
                    if selectedCombinationRankingModels.contains(model), selectedCombinationRankingModels.count > 1 {
                        selectedCombinationRankingModels.remove(model)
                    } else {
                        selectedCombinationRankingModels.insert(model)
                    }
                    normalizeCombinationRankingSelection(snapshot: snapshot)
                    needsDisplay = true
                    return
                }
            }
            if combinationRankingModelFieldRect?.contains(point) == true {
                isCombinationRankingModelMenuOpen.toggle()
                needsDisplay = true
                return
            }
            if isCombinationRankingModelMenuOpen {
                isCombinationRankingModelMenuOpen = false
                needsDisplay = true
                return
            }
            for (days, rect) in insightWindowRects where rect.contains(point) {
                selectedInsightWindowDays = days
                normalizeCombinationRankingSelection(snapshot: snapshot)
                needsDisplay = true
                return
            }
            for (metric, rect) in combinationRankingMetricRects where rect.contains(point) {
                selectedCombinationRankingMetric = metric
                needsDisplay = true
                return
            }
            for (column, rect) in combinationRankingSortRects where rect.contains(point) {
                if selectedCombinationRankingSort == column {
                    isCombinationRankingSortAscending.toggle()
                } else {
                    selectedCombinationRankingSort = column
                    isCombinationRankingSortAscending = column.defaultAscending
                }
                needsDisplay = true
                return
            }
            for (cell, rect) in combinationRankingRowRects where rect.contains(point) {
                selectedCombinationRankingCell = cell
                needsDisplay = true
                return
            }
            for (cell, rect) in combinationRankingBubbleRects where rect.contains(point) {
                selectedCombinationRankingCell = cell
                needsDisplay = true
                return
            }
        }
        if selectedSection == .storage {
            if handleStorageMouseDown(at: point) {
                return
            }
        }
        if selectedSection == .settings {
            for (subsection, rect) in settingsSubsectionRects where rect.contains(point) {
                selectedSettingsSubsection = subsection
                return
            }
            for (style, rect) in numberUnitOptionRects where rect.contains(point) {
                onNumberUnitStyleChanged?(style)
                return
            }
            for (style, rect) in quotaDisplayStyleRects where rect.contains(point) {
                onQuotaDisplayStyleChanged?(style)
                return
            }
            for (metric, rect) in codexHomeRingMetricRects where rect.contains(point) {
                onCodexHomeRingMetricChanged?(metric)
                return
            }
            for (metric, rect) in claudeHomeRingMetricRects where rect.contains(point) {
                onClaudeHomeRingMetricChanged?(metric)
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
            if chooseCodexAPISourceRect?.contains(point) == true {
                onChooseCodexAPISource?()
                return
            }
            if resetCodexAPISourceRect?.contains(point) == true {
                onResetCodexAPISources?()
                return
            }
            if openCodexAPISourceRect?.contains(point) == true {
                onOpenCodexAPISource?()
                return
            }
            if machineUsageExportRect?.contains(point) == true {
                onExportMachineUsageReport?()
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
        for (weekStart, rect) in contributionWeekDotRects where rect.insetBy(dx: -3, dy: -3).contains(point) {
            guard let summary = contributionWeekSummaries[weekStart] else { continue }
            let extendsSelection = event.modifierFlags.contains(.command)
            beginContributionDrag(mode: .weeks, at: point, extending: extendsSelection)
            let weekDays = Set(summary.days.map(\.day))
            if extendsSelection {
                toggleContributionSelection(weekDays)
                contributionSelectionAnchor = (summary.startDay, summary.endDay)
            } else if contributionSelectionDays() == weekDays {
                selectedContributionDays.removeAll()
                contributionSelectionAnchor = selectedDay.map { ($0, $0) }
                calendarSelectionDidChange()
            } else {
                applyContributionSelection(weekDays)
                contributionSelectionAnchor = (summary.startDay, summary.endDay)
            }
            return
        }
        for (day, rect) in contributionDayRects where rect.insetBy(dx: -2, dy: -2).contains(point) {
            if selectedSection == .calendar {
                let extendsSelection = event.modifierFlags.contains(.command)
                beginContributionDrag(mode: .days, at: point, extending: extendsSelection)
                if extendsSelection {
                    toggleContributionSelection([day])
                    contributionSelectionAnchor = (day, day)
                } else {
                    applyContributionSelection([day])
                    contributionSelectionAnchor = (day, day)
                    AppSettings.selectedCalendarDay = day
                }
            } else {
                selectedContributionDays.removeAll()
                selectedDay = day
                contributionSelectionAnchor = (day, day)
                AppSettings.selectedCalendarDay = day
                selectedSection = .calendar
            }
            return
        }
        if selectedSection == .calendar, contributionGridSelectionRect?.contains(point) == true {
            beginContributionDrag(mode: .days, at: point, extending: event.modifierFlags.contains(.command))
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mode = contributionDragMode,
              let start = contributionDragStartPoint else {
            super.mouseDragged(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) >= 3 else { return }
        let marquee = NSRect(
            x: min(start.x, point.x),
            y: min(start.y, point.y),
            width: max(1, abs(point.x - start.x)),
            height: max(1, abs(point.y - start.y))
        )
        contributionMarqueeRect = marquee

        var selected = contributionDragBaseDays
        switch mode {
        case .days:
            selected.formUnion(contributionDayRects.compactMap { day, rect in
                marquee.intersects(rect.insetBy(dx: -1, dy: -1)) ? day : nil
            })
        case .weeks:
            let weekKeys = contributionWeekDotRects.compactMap { key, rect in
                marquee.intersects(rect.insetBy(dx: -2, dy: -2)) ? key : nil
            }
            for key in weekKeys {
                selected.formUnion(contributionWeekSummaries[key]?.days.map(\.day) ?? [])
            }
        }
        if !selected.isEmpty {
            applyContributionSelection(selected, updateLayout: false)
        } else {
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        if contributionDragMode != nil {
            let completedMarqueeSelection = contributionMarqueeRect != nil
            if completedMarqueeSelection {
                let days = contributionSelectionDays().sorted()
                if let first = days.first, let last = days.last {
                    contributionSelectionAnchor = (first, last)
                }
            }
            contributionDragMode = nil
            contributionDragStartPoint = nil
            contributionDragBaseDays.removeAll()
            contributionMarqueeRect = nil
            if completedMarqueeSelection {
                calendarSelectionDidChange()
            } else {
                needsDisplay = true
            }
            return
        }
        super.mouseUp(with: event)
    }

    func beginContributionDrag(mode: ContributionDragMode, at point: CGPoint, extending: Bool) {
        contributionDragMode = mode
        contributionDragStartPoint = point
        contributionDragBaseDays = extending ? contributionSelectionDays() : []
        contributionMarqueeRect = nil
        hoveredContributionWeekKey = nil
        contributionWeekHoverOverlay.hide()
    }

    func contributionSelectionDays() -> Set<String> {
        if selectedContributionDays.count > 1 {
            return selectedContributionDays
        }
        return selectedDay.map { [$0] } ?? []
    }

    func applyContributionSelection(_ days: Set<String>, updateLayout: Bool = true) {
        let normalized = Set(days)
        guard normalized != contributionSelectionDays() else {
            needsDisplay = true
            return
        }
        if normalized.count <= 1 {
            selectedContributionDays.removeAll()
            if let day = normalized.first {
                selectedDay = day
            } else {
                selectedDay = nil
            }
        } else {
            selectedContributionDays = normalized
        }
        calendarSelectionDidChange(updateLayout: updateLayout)
    }

    func toggleContributionSelection(_ days: Set<String>) {
        var selection = contributionSelectionDays()
        if days.isSubset(of: selection) {
            selection.subtract(days)
        } else {
            selection.formUnion(days)
        }
        applyContributionSelection(selection)
    }

    func selectContributionRange(
        from anchor: (startDay: String, endDay: String),
        through target: (startDay: String, endDay: String),
        report: TokenReport
    ) {
        let startDay = min(anchor.startDay, target.startDay)
        let endDay = max(anchor.endDay, target.endDay)
        let days = Set(paddedContributionDays(report.byDay).compactMap { day in
            day.day >= startDay && day.day <= endDay ? day.day : nil
        })
        applyContributionSelection(days)
    }

    func normalizeCalendarSelection(in report: TokenReport, fallback: String?) {
        let available = Set(paddedContributionDays(report.byDay).map(\.day))
        let retained = selectedContributionDays.intersection(available)
        if retained.count > 1 {
            selectedContributionDays = retained
            return
        }
        selectedContributionDays.removeAll()
        selectedDay = preferredSelectedDay(in: report, fallback: retained.first ?? fallback)
        contributionSelectionAnchor = selectedDay.map { ($0, $0) }
    }

    func calendarSelectionDidChange(updateLayout: Bool = true) {
        if contributionDragMode == nil {
            updateContributionWeekHoverOverlay()
        }
        if updateLayout {
            onPreferredHeightChanged?()
            needsLayout = true
        }
        needsDisplay = true
    }

    /// Debug hook for --render-details=--select-week snapshots.
    func selectCalendarWeek(startDay: String) {
        guard let snapshot else { return }
        let report = calendarReport(for: snapshot)
        guard let summary = contributionWeekColumns(in: report).first(where: { $0.startDay == startDay }) else { return }
        applyContributionSelection(Set(summary.days.map(\.day)))
        contributionSelectionAnchor = (summary.startDay, summary.endDay)
    }

    /// Debug hook for deterministic model-list search and sort screenshots.
    func configureModelList(query: String?, sort: String?) {
        modelControls.configure(query: query, sort: sort)
    }

    /// Debug hook for rendering a multi-day selection.
    func selectCalendarRange(startDay: String, endDay: String) {
        guard let snapshot else { return }
        selectContributionRange(
            from: (startDay, startDay),
            through: (endDay, endDay),
            report: calendarReport(for: snapshot)
        )
        contributionSelectionAnchor = (startDay, startDay)
    }

    func preferredSelectedDay(in report: TokenReport, fallback: String?) -> String? {
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
              selectedDetailsSource != .all,
              paymentCurrencyPopup.indexOfSelectedItem >= 0 else { return }
        let currency = CurrencyCode.allCases[paymentCurrencyPopup.indexOfSelectedItem]
        onPaymentCurrencyChanged?(currency, selectedDetailsSource)
        needsDisplay = true
        needsLayout = true
    }

    @objc private func displayCurrencyPopupChanged() {
        guard displayCurrencyPopup.indexOfSelectedItem >= 0 else { return }
        let currency = CurrencyCode.allCases[displayCurrencyPopup.indexOfSelectedItem]
        if selectedSection == .settings && selectedSettingsSubsection == .appearance {
            onDisplayCurrencyChanged?(currency, .all)
            needsDisplay = true
            return
        }
        guard !isUpdatingCostControls,
              selectedDetailsSource != .all else { return }
        onDisplayCurrencyChanged?(currency, selectedDetailsSource)
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

    @objc private func statusPrimaryMetricPopupChanged() {
        guard !isUpdatingStatusMetricPopups,
              statusPrimaryMetricPopup.indexOfSelectedItem >= 0,
              StatusBarMetric.allCases.indices.contains(statusPrimaryMetricPopup.indexOfSelectedItem) else { return }
        let metric = StatusBarMetric.allCases[statusPrimaryMetricPopup.indexOfSelectedItem]
        onStatusBarMetricChanged?(.first, metric)
        needsDisplay = true
    }

    @objc private func statusSecondaryMetricPopupChanged() {
        guard !isUpdatingStatusMetricPopups,
              statusSecondaryMetricPopup.indexOfSelectedItem >= 0 else { return }
        let index = statusSecondaryMetricPopup.indexOfSelectedItem
        guard index > 0 else {
            onStatusBarMetricChanged?(.second, nil)
            needsDisplay = true
            return
        }
        let metricIndex = index - 1
        guard StatusBarMetric.allCases.indices.contains(metricIndex) else { return }
        onStatusBarMetricChanged?(.second, StatusBarMetric.allCases[metricIndex])
        needsDisplay = true
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
            let editSource = costAmountEditingSource ?? selectedDetailsSource
            costAmountEditingSource = nil
            guard editSource != .all else {
                updateCostControlsFromSettings()
                return
            }
            let sanitized = String(costAmountField.stringValue.filter { "0123456789.".contains($0) })
            guard let value = Double(sanitized), value >= 0 else {
                updateCostControlsFromSettings()
                return
            }
            onPlanCostChanged?(value, editSource)
            costAmountField.stringValue = paymentAmount(AppSettings.monthlyPlanCost(for: selectedDetailsSource), source: selectedDetailsSource)
            needsDisplay = true
            needsLayout = true
            return
        }
        if field === paymentStartDayField {
            let editSource = paymentStartDayEditingSource ?? selectedDetailsSource
            paymentStartDayEditingSource = nil
            guard editSource != .all else {
                updateCostControlsFromSettings()
                return
            }
            let value = paymentStartDayField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard dayFormatter().date(from: value) != nil else {
                updateCostControlsFromSettings()
                return
            }
            onPaymentStartDayChanged?(value, editSource)
            if editSource != selectedDetailsSource {
                updateCostControlsFromSettings()
            }
            needsDisplay = true
            needsLayout = true
        }
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === costAmountField {
            costAmountEditingSource = selectedDetailsSource
        } else if field === paymentStartDayField {
            paymentStartDayEditingSource = selectedDetailsSource
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGradient(starting: appBackgroundTop, ending: appBackgroundBottom)?.draw(in: bounds, angle: -90)

        let sidebarWidth = detailsSidebarWidth
        sidebarBackgroundColor.setFill()
        NSRect(x: 0, y: 0, width: sidebarWidth, height: bounds.height).fill()
        borderColor.setStroke()
        NSBezierPath(rect: NSRect(x: sidebarWidth, y: 0, width: 1, height: bounds.height)).stroke()

        drawSidebar(width: sidebarWidth)

        let content = sectionContent(for: selectedSection, in: bounds, sidebarWidth: sidebarWidth)
        contributionDayRects.removeAll()
        contributionDaySummaries.removeAll()
        contributionWeekSummaries.removeAll()
        contributionWeekDotRects.removeAll()
        contributionGridSelectionRect = nil
        resetCreditHitAreas.removeAll()
        resetCreditTooltipRows.removeAll()
        costHistoryBarRects.removeAll()
        costHistoryRows.removeAll()
        quotaCycleHitAreas.removeAll()
        costOverviewInfoRects.removeAll()
        dayValueInfoRect = nil
        profileAPIInfoRect = nil
        insightRowRects.removeAll()
        insightWindowRects.removeAll()
        insightDetailModeRects.removeAll()
        insightHourRects.removeAll()
        insightHourBarRects.removeAll()
        insightPeriodRects.removeAll()
        reasoningModelChipRects.removeAll()
        reasoningCellRects.removeAll()
        reasoningTrendDayRects.removeAll()
        combinationRankingMetricRects.removeAll()
        combinationRankingModelFieldRect = nil
        combinationRankingModelOptionRects.removeAll()
        combinationRankingSortRects.removeAll()
        combinationRankingRowRects.removeAll()
        combinationRankingBubbleRects.removeAll()
        combinationRankingExpandHintRect = nil
        insightSortRects.removeAll()
        modelSortColumnRects.removeAll()
        insightStatusFilterRects.removeAll()
        insightListViewportRect = nil
        numberUnitOptionRects.removeAll()
        quotaDisplayStyleRects.removeAll()
        settingsSubsectionRects.removeAll()
        sourceOptionRects.removeAll()
        chooseLogFolderRect = nil
        resetLogFolderRect = nil
        openLogFolderRect = nil
        chooseCodexAPISourceRect = nil
        resetCodexAPISourceRect = nil
        openCodexAPISourceRect = nil
        machineUsageExportRect = nil
        storageGrowthCells.removeAll()
        storageSourceRowRects.removeAll()
        storageSourceMenuRects.removeAll()
        storageOpenFinderRect = nil
        storageExportRect = nil
        storageRefreshRect = nil

        let sourceSelectorWidth: CGFloat = showsDetailsSourceSelector ? min(286, max(246, content.width * 0.31)) : 0
        let headerTextWidth = showsDetailsSourceSelector ? max(260, content.width - sourceSelectorWidth - 18) : content.width
        drawText(currentDetailsHeaderTitle, rect: NSRect(x: content.minX, y: content.minY, width: headerTextWidth, height: 34), font: .systemFont(ofSize: 26, weight: .bold), color: .white)
        drawText(currentDetailsHeaderSubtitle, rect: NSRect(x: content.minX, y: content.minY + 36, width: headerTextWidth, height: 20), font: .systemFont(ofSize: 13, weight: .medium), color: NSColor.white.withAlphaComponent(0.56))
        if showsDetailsSourceSelector {
            drawDetailsSourceSelector(content: content, width: sourceSelectorWidth)
        }

        if selectedSection == .storage {
            drawStoragePage(content: content)
            drawStorageGrowthTooltip(container: content)
            drawStorageSourceTooltip(container: content)
            return
        }

        guard let snapshot else {
            if selectedSection == .settings {
                drawSettingsPage(content: content)
            } else if selectedSection == .about {
                drawAboutPage(content: content)
            } else if isLoading {
                drawLoadingState(content: content)
            } else {
                drawText(t(.noDataLoaded), rect: NSRect(x: content.minX, y: content.minY + 92, width: content.width, height: 24), font: .systemFont(ofSize: 15, weight: .semibold), color: NSColor.white.withAlphaComponent(0.56))
            }
            return
        }

        switch selectedSection {
        case .overview:
            drawOverview(snapshot: snapshot, content: content)
        case .insights:
            drawInsightsPage(snapshot: snapshot, content: content)
        case .reasoning:
            drawCombinationRankingPage(snapshot: snapshot, content: content)
        case .combinationRanking:
            drawCombinationRankingPage(snapshot: snapshot, content: content)
        case .models:
            drawModelsPage(snapshot: snapshot, content: content)
        case .calendar:
            drawCalendarPage(snapshot: snapshot, content: content)
        case .costs:
            drawQuotaCyclesPage(snapshot: snapshot, content: content)
        case .settings:
            drawSettingsPage(content: content)
        case .diagnostics:
            drawDiagnosticsPage(snapshot: snapshot, content: content)
        case .storage:
            break
        case .about:
            drawAboutPage(content: content)
        }

        if selectedSection == .calendar {
            drawDayValueInfoTooltip()
            drawProfileAPIInfoTooltip()
        } else if selectedSection == .overview {
            drawResetCreditTooltip(container: content)
        } else if selectedSection == .insights {
            drawInsightUsageTimeTooltip()
        } else if selectedSection == .reasoning {
            drawReasoningTrendTooltip(container: content)
        } else if selectedSection == .costs {
            drawQuotaCycleTooltip(container: content)
        } else if selectedSection == .models {
            drawModelUsageRowTooltip(container: content)
        }
    }

    func drawDetailsSourceSelector(content: NSRect, width: CGFloat) {
        let usesPlatformOnlySources = selectedSection == .diagnostics || selectedSection == .costs
        let options: [QuotaViewOption] = usesPlatformOnlySources ? [.codex, .claude] : [.all, .codex, .claude]
        let height: CGFloat = 30
        let gap: CGFloat = 8
        let rect = NSRect(x: content.maxX - width, y: content.minY + 6, width: width, height: height)
        let optionWidth = (rect.width - gap * CGFloat(options.count - 1)) / CGFloat(options.count)
        let selectedOption = usesPlatformOnlySources && selectedDetailsSource == .all ? QuotaViewOption.codex : selectedDetailsSource
        for (index, option) in options.enumerated() {
            let optionRect = NSRect(
                x: rect.minX + CGFloat(index) * (optionWidth + gap),
                y: rect.minY,
                width: optionWidth,
                height: height
            )
            sourceOptionRects[option] = optionRect
            drawSelectablePill(detailsSourceTitle(option), rect: optionRect, selected: option == selectedOption)
        }
    }

    var currentDetailsHeaderTitle: String {
        if selectedSection == .insights, selectedInsightDetailMode == .usageTime {
            return localizedInsightUsageTimePageTitle
        }
        if selectedSection == .insights, selectedInsightDetailMode == .reasoningDepth {
            return localizedReasoningDepthPageTitle
        }
        return selectedSection.headerTitle
    }

    var currentDetailsHeaderSubtitle: String {
        if selectedSection == .insights, selectedInsightDetailMode == .usageTime {
            return localizedInsightUsageTimePageSubtitle
        }
        if selectedSection == .insights, selectedInsightDetailMode == .reasoningDepth {
            return localizedReasoningDepthPageSubtitle
        }
        return selectedSection.subtitle
    }

    func detailsSourceTitle(_ option: QuotaViewOption) -> String {
        switch option {
        case .all:
            switch AppLanguage.current {
            case .chinese:
                return "总和"
            case .traditionalChinese:
                return "總和"
            case .japanese:
                return "合計"
            default:
                return "Total"
            }
        case .codex:
            return "Codex"
        case .claude:
            return "Claude"
        }
    }

    func drawLoadingState(content: NSRect) {
        let progress = loadingProgress.clampedFraction
        let message = t(loadingProgress.messageKey)
        let percentText = "\(Int((progress * 100).rounded()))%"
        let y = content.minY + 92
        let progressWidth = min(content.width, 420)
        let labelRect = NSRect(x: content.minX, y: y, width: progressWidth - 56, height: 24)
        let percentRect = NSRect(x: content.minX + progressWidth - 50, y: y, width: 50, height: 24)
        drawText(message, rect: labelRect, font: .systemFont(ofSize: 15, weight: .semibold), color: NSColor.white.withAlphaComponent(0.68))
        drawText(percentText, rect: percentRect, font: .monospacedDigitSystemFont(ofSize: 13, weight: .bold), color: accentTeal.withAlphaComponent(0.86))

        let track = NSRect(x: content.minX, y: y + 34, width: progressWidth, height: 10)
        NSColor.white.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: track, xRadius: 5, yRadius: 5).fill()

        let fillWidth = max(progress > 0 ? 8 : 0, track.width * CGFloat(progress))
        let fillRect = NSRect(x: track.minX, y: track.minY, width: min(track.width, fillWidth), height: track.height)
        accentBlue.withAlphaComponent(0.86).setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: 5, yRadius: 5).fill()

        drawText(t(.loadingUsageDetailsHint), rect: NSRect(x: content.minX, y: y + 58, width: content.width, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.42))
    }

    func drawSidebar(width: CGFloat) {
        sidebarItemRects.removeAll()
        drawText("AI Token Meter", rect: NSRect(x: 28, y: 28, width: width - 56, height: 28), font: .systemFont(ofSize: 20, weight: .bold), color: .white)
        drawText(t(.combinedUsage), rect: NSRect(x: 28, y: 58, width: width - 56, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: NSColor.white.withAlphaComponent(0.52))
        for (index, section) in DetailsSection.visibleSections.enumerated() {
            let y = CGFloat(118 + index * 58)
            let rect = NSRect(x: 18, y: y, width: width - 36, height: 42)
            sidebarItemRects[section] = rect
            if section == selectedSection {
                accentBlue.withAlphaComponent(0.82).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
            }
            let textColor = section == selectedSection ? NSColor.white : NSColor.white.withAlphaComponent(0.82)
            let iconRect = NSRect(x: rect.minX + 14, y: rect.minY + 12, width: 18, height: 18)
            drawSymbolIcon(sidebarSymbolName(section), in: iconRect, color: textColor.withAlphaComponent(section == selectedSection ? 1.0 : 0.72))
            drawText(section.title, rect: NSRect(x: rect.minX + 42, y: rect.minY + 10, width: rect.width - 56, height: 22), font: .systemFont(ofSize: 15, weight: .semibold), color: textColor)
        }
        if (selectedSection == .reasoning || selectedSection == .combinationRanking),
           let report = snapshot?.codexRepoInsightReports[selectedInsightWindowDays] ?? snapshot?.codexRepoInsights {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = appTimeZone()
            formatter.dateFormat = "yyyy-MM-dd"
            drawText("\(reasoningLocalized("数据更新", english: "Updated")):  \(formatter.string(from: report.scannedAt))", rect: NSRect(x: 28, y: bounds.maxY - 66, width: width - 48, height: 17), font: .systemFont(ofSize: 10.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.46))
            let seconds = appTimeZone().secondsFromGMT()
            let sign = seconds >= 0 ? "+" : "-"
            drawText("\(reasoningLocalized("时区", english: "Time zone")):  UTC\(sign)\(abs(seconds) / 3600)", rect: NSRect(x: 28, y: bounds.maxY - 42, width: width - 48, height: 17), font: .systemFont(ofSize: 10.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.46))
        }
    }

    func sidebarSymbolName(_ section: DetailsSection) -> String {
        switch section {
        case .overview: return "square.grid.2x2"
        case .calendar: return "calendar"
        case .insights: return "waveform.path.ecg"
        case .reasoning: return "chart.line.uptrend.xyaxis"
        case .combinationRanking: return "chart.bar.xaxis.ascending"
        case .costs: return "clock.arrow.circlepath"
        case .models: return "cpu"
        case .storage: return "internaldrive"
        case .settings: return "gearshape"
        case .diagnostics: return "stethoscope"
        case .about: return "info.circle"
        }
    }

    func drawSymbolIcon(_ name: String, in rect: NSRect, color: NSColor, pointSize: CGFloat = 13) {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)) else { return }
        let tinted = NSImage(size: base.size)
        tinted.lockFocus()
        base.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)
        color.set()
        NSRect(origin: .zero, size: base.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        let target = NSRect(
            x: rect.midX - base.size.width / 2,
            y: rect.midY - base.size.height / 2,
            width: base.size.width,
            height: base.size.height
        )
        tinted.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
    }

}
