import Cocoa
import Foundation
import ServiceManagement
import UserNotifications

// MARK: - Details Window

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

enum DetailsSection: CaseIterable {
    case overview
    case calendar
    case costs
    case models
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
        let usage: Usage
        let total: Int64
        let activeDays: Int
        let turns: Int
        let days: [DayUsage]
        let hitRect: NSRect
        let cellRects: [NSRect]
    }

    private struct ContributionWeekDetail {
        let usage: Usage
        let turns: Int
        let hasTokenDetail: Bool
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
    var onLanguageChanged: ((AppLanguage) -> Void)?
    var onNumberUnitStyleChanged: ((NumberUnitStyle) -> Void)?
    var onStatusDisplayChanged: ((StatusDisplayOption) -> Void)?
    var onQuotaDisplayStyleChanged: ((QuotaDisplayStyle) -> Void)?
    var onPlanCostChanged: ((Double) -> Void)?
    var onPaymentStartDayChanged: ((String) -> Void)?
    var onPaymentCurrencyChanged: ((CurrencyCode) -> Void)?
    var onDisplayCurrencyChanged: ((CurrencyCode) -> Void)?
    var onChooseLogFolder: (() -> Void)?
    var onResetLogFolder: (() -> Void)?
    var onOpenLogFolder: (() -> Void)?
    var onShowHistoricalEmptyWeeksChanged: ((Bool) -> Void)?
    var onLaunchAtLoginChanged: ((Bool) -> Void)?
    var onShowCodexStatusChanged: ((Bool) -> Void)?
    var onQuotaWarningsChanged: ((Bool) -> Void)?
    var onProfileAPITotalsChanged: ((Bool) -> Void)?
    var onPreferredHeightChanged: (() -> Void)?
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
        let controlWidth = min(300, max(252, settingsRect.width * 0.34))
        let controlX = settingsRect.maxX - controlWidth - 16
        let labelX = settingsRect.minX + 16
        let leftColumnWidth = max(180, controlX - labelX - 24)
        let labelFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let centeredLabelY: (NSRect) -> CGFloat = { frame in
            frame.midY - 10
        }
        drawPanel(settingsRect)
        drawText(t(.planCost), rect: NSRect(x: settingsRect.minX + 16, y: settingsRect.minY + 14, width: 220, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        let monthlyLabelY = max(settingsRect.minY + 38, costAmountField.frame.midY - 12)
        drawText(t(.paymentMonthly), rect: NSRect(x: labelX, y: monthlyLabelY, width: leftColumnWidth, height: 20), font: labelFont, color: .white)
        drawMultilineText(t(.planCostHint), rect: NSRect(x: labelX, y: monthlyLabelY + 22, width: leftColumnWidth, height: 32), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.52))

        drawText(t(.paymentStartDate), rect: NSRect(x: labelX, y: centeredLabelY(paymentStartDayField.frame), width: leftColumnWidth, height: 20), font: labelFont, color: .white)
        drawText(t(.paymentCurrency), rect: NSRect(x: labelX, y: centeredLabelY(paymentCurrencyPopup.frame), width: leftColumnWidth, height: 20), font: labelFont, color: .white)
        drawText(t(.displayCurrency), rect: NSRect(x: labelX, y: centeredLabelY(displayCurrencyPopup.frame), width: leftColumnWidth, height: 20), font: labelFont, color: .white)
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
        let localEstimate = APICostEstimator.estimate(day: localDay)
        if localEstimate.hasPricedUsage {
            return APICostEstimate(
                usdValue: localEstimate.usdValue,
                pricedTokens: localEstimate.pricedTokens,
                totalTokens: max(profileDay.usage.total, localEstimate.totalTokens)
            )
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
        let ringGapY: CGFloat = rowCount > 4 ? 10 : 18
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
        let ringRect = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - labelHeight)
        let availableSide = max(0, min(ringRect.width, ringRect.height))
        let outerPadding = min(4, max(2, availableSide * 0.12))
        let center = CGPoint(x: ringRect.midX, y: ringRect.midY)
        let radius = max(2, availableSide / 2 - outerPadding)
        let preferredLineWidth = max(2.2, availableSide * 0.14)
        let lineWidth: CGFloat = min(8, min(preferredLineWidth, max(2, radius * 0.45)))
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
        var weekUsages: [Int: Usage] = [:]
        var weekTotals: [Int: Int64] = [:]
        var weekActiveDays: [Int: Int] = [:]
        var weekTurns: [Int: Int] = [:]
        var weekDays: [Int: [DayUsage]] = [:]

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
                if weekUsages[col] == nil {
                    weekUsages[col] = Usage()
                }
                weekUsages[col]?.add(day.usage)
                weekTotals[col, default: 0] += day.usage.total
                weekTurns[col, default: 0] += day.turns
                weekDays[col, default: []].append(day)
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
                    usage: weekUsages[column] ?? Usage(total: weekTotals[column] ?? 0),
                    total: weekTotals[column] ?? 0,
                    activeDays: weekActiveDays[column] ?? 0,
                    turns: weekTurns[column] ?? 0,
                    days: weekDays[column] ?? [],
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
        let rows = contributionWeekTooltipRows(summary)
        let labelFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        let titleFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
        let labelWidth = min(86, max(58, (rows.map { measuredTextWidth($0.0, font: labelFont) }.max() ?? 0) + 4))
        let valueWidth = min(170, max(96, (rows.map { measuredTextWidth($0.1, font: valueFont) }.max() ?? 0) + 4))
        let titleWidth = measuredTextWidth(contributionWeekRangeLabel(summary), font: titleFont) + 24
        let width = min(max(max(titleWidth, labelWidth + valueWidth + 42), 244), min(360, container.width - 32))
        let height = CGFloat(40 + rows.count * 16)
        let gap: CGFloat = 14
        var origin: CGPoint
        if summary.hitRect.minX - width - gap >= container.minX + 12 {
            origin = CGPoint(x: summary.hitRect.minX - width - gap, y: summary.hitRect.midY - height / 2)
        } else if summary.hitRect.maxX + width + gap <= container.maxX - 12 {
            origin = CGPoint(x: summary.hitRect.maxX + gap, y: summary.hitRect.midY - height / 2)
        } else {
            origin = CGPoint(x: summary.hitRect.midX - width / 2, y: summary.hitRect.minY - height - gap)
            if origin.y < container.minY + 40 {
                origin.y = summary.hitRect.maxY + gap
            }
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

        drawText(contributionWeekRangeLabel(summary), rect: NSRect(x: tooltipRect.minX + 12, y: tooltipRect.minY + 9, width: tooltipRect.width - 24, height: 16), font: titleFont, color: NSColor.white.withAlphaComponent(0.82))
        for (index, row) in rows.enumerated() {
            let y = tooltipRect.minY + 31 + CGFloat(index) * 16
            drawText(row.0, rect: NSRect(x: tooltipRect.minX + 12, y: y, width: labelWidth, height: 14), font: labelFont, color: NSColor.white.withAlphaComponent(0.52))
            let valueX = tooltipRect.minX + 12 + labelWidth + 18
            drawRight(row.1, rect: NSRect(x: valueX, y: y - 1, width: tooltipRect.maxX - valueX - 12, height: 15), color: NSColor.white.withAlphaComponent(0.88), font: valueFont)
        }
    }

    private func contributionWeekTooltipRows(_ summary: ContributionWeekSummary) -> [(String, String)] {
        let detail = contributionWeekDetail(summary)
        let activeDays = max(summary.activeDays, 1)
        let averagePerActiveDay = summary.total / Int64(activeDays)
        let planValue = contributionWeekPlanValue(summary)
        let apiEstimate = contributionWeekAPIEstimate(summary)
        var rows: [(String, String)] = [
            (contributionWeekLabel(.tokens), compactDashboardTotal(summary.total)),
            (contributionWeekLabel(.activeDays), "\(summary.activeDays)/7"),
            (contributionWeekLabel(.average), compactDashboardTotal(averagePerActiveDay))
        ]
        if detail.hasTokenDetail {
            let inputOutput = "\(compactDashboardTotal(detail.usage.input)) / \(compactDashboardTotal(detail.usage.output))"
            rows.append((contributionWeekLabel(.inputOutput), inputOutput))
            if detail.usage.input > 0 {
                rows.append((contributionWeekLabel(.cache), String(format: "%.0f%%", detail.usage.cachePercent)))
            }
        }
        if detail.turns > 0 {
            rows.append((contributionWeekLabel(.turns), format(Int64(detail.turns))))
        }
        rows.append((contributionPlanAmountLabel(), planValue.map { displayMoney($0) } ?? "--"))
        rows.append((contributionAPIAmountLabel(), apiEstimate.hasPricedUsage ? displayAPIMoney(apiEstimate.usdValue) : "--"))
        return rows
    }

    private func contributionWeekRangeLabel(_ summary: ContributionWeekSummary) -> String {
        "\(localizedContributionDate(summary.startDay)) - \(localizedContributionDate(summary.endDay))"
    }

    private enum ContributionWeekMetric {
        case tokens
        case activeDays
        case average
        case inputOutput
        case cache
        case turns
    }

    private func contributionWeekLabel(_ metric: ContributionWeekMetric) -> String {
        switch (metric, AppLanguage.current) {
        case (.tokens, .chinese), (.tokens, .traditionalChinese): return "Token"
        case (.tokens, .japanese): return "Token"
        case (.tokens, _): return "Tokens"
        case (.activeDays, .chinese), (.activeDays, .traditionalChinese): return "活跃天数"
        case (.activeDays, .japanese): return "利用日数"
        case (.activeDays, _): return "Active days"
        case (.average, .chinese), (.average, .traditionalChinese): return "日均"
        case (.average, .japanese): return "日平均"
        case (.average, _): return "Daily avg"
        case (.inputOutput, .chinese), (.inputOutput, .traditionalChinese): return "输入/输出"
        case (.inputOutput, .japanese): return "入力/出力"
        case (.inputOutput, _): return "Input/output"
        case (.cache, .chinese), (.cache, .traditionalChinese): return "缓存命中"
        case (.cache, .japanese): return "キャッシュ"
        case (.cache, _): return "Cache hit"
        case (.turns, .chinese), (.turns, .traditionalChinese): return "轮次"
        case (.turns, .japanese): return "ターン"
        case (.turns, _): return "Turns"
        }
    }

    private func contributionWeekPlanValue(_ summary: ContributionWeekSummary) -> Double? {
        guard let snapshot,
              let date = dayFormatter().date(from: summary.startDay),
              let weekStart = appCalendar().dateInterval(of: .weekOfYear, for: date)?.start else {
            return nil
        }
        let report = calendarReport(for: snapshot)
        guard let estimator = CostEstimator(
            report: report,
            limit: costEstimateLimit(from: snapshot.liveLimits),
            quotaReferenceReport: snapshot.costReferenceReport
        ) else {
            return nil
        }
        return estimator.weeklyUsedValue(forWeekStart: weekStart, total: summary.total)
    }

    private func contributionWeekAPIEstimate(_ summary: ContributionWeekSummary) -> APICostEstimate {
        var estimate = APICostEstimate()
        if summary.days.isEmpty {
            estimate.add(APICostEstimator.estimate(day: DayUsage(day: summary.startDay, usage: summary.usage, turns: summary.turns)))
            return estimate
        }
        for day in summary.days {
            estimate.add(contributionDayAPIEstimate(day))
        }
        return estimate
    }

    private func contributionWeekDetail(_ summary: ContributionWeekSummary) -> ContributionWeekDetail {
        if summary.usage.input > 0 || summary.usage.output > 0 || summary.usage.cachedInput > 0 || summary.turns > 0 {
            return ContributionWeekDetail(usage: summary.usage, turns: summary.turns, hasTokenDetail: summary.usage.input > 0 || summary.usage.output > 0 || summary.usage.cachedInput > 0)
        }
        guard let snapshot else {
            return ContributionWeekDetail(usage: summary.usage, turns: summary.turns, hasTokenDetail: false)
        }
        var usage = Usage()
        var turns = 0
        var hasTokenDetail = false
        for day in snapshot.all.byDay where day.day >= summary.startDay && day.day <= summary.endDay {
            usage.add(day.usage)
            turns += day.turns
            if day.usage.input > 0 || day.usage.output > 0 || day.usage.cachedInput > 0 {
                hasTokenDetail = true
            }
        }
        return ContributionWeekDetail(usage: usage, turns: turns, hasTokenDetail: hasTokenDetail)
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
