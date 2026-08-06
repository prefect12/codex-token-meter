import Cocoa

enum ModelListSortOption: String, CaseIterable, Hashable {
    case name
    case share
    case total
    case input
    case output
    case sessions
    case events
    case apiCost
}

enum ModelListSortDirection: String, Hashable {
    case ascending
    case descending
}

struct ModelListPresentation {
    let models: [ModelUsage]
    let knownModelCount: Int
    let hiddenUnknownCount: Int
    let knownTokens: Int64
    let allModelTokens: Int64
    let pricedTokens: Int64
    let unpricedModelCount: Int

    var identificationCoveragePercent: Double {
        guard allModelTokens > 0 else { return 0 }
        return Double(knownTokens) / Double(allModelTokens) * 100
    }

    var pricingCoveragePercent: Double {
        guard knownTokens > 0 else { return 0 }
        return Double(pricedTokens) / Double(knownTokens) * 100
    }

    var tableHeight: CGFloat {
        max(CGFloat(132), CGFloat(112 + models.count * 20))
    }

    static func make(
        report: TokenReport,
        query: String,
        sort: ModelListSortOption,
        direction: ModelListSortDirection
    ) -> ModelListPresentation {
        let allModels = report.modelBreakdown
        let knownModels = allModels.filter { !isUnknownModelName($0.name) }
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var visibleModels = normalizedQuery.isEmpty
            ? knownModels
            : knownModels.filter { $0.name.localizedCaseInsensitiveContains(normalizedQuery) }

        visibleModels.sort { lhs, rhs in
            let comparison: ComparisonResult
            switch sort {
            case .name:
                comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            case .share, .total:
                comparison = compare(lhs.usage.total, rhs.usage.total)
            case .input:
                comparison = compare(lhs.usage.input, rhs.usage.input)
            case .output:
                comparison = compare(lhs.usage.output, rhs.usage.output)
            case .sessions:
                comparison = compare(lhs.sessions, rhs.sessions)
            case .events:
                comparison = compare(lhs.events, rhs.events)
            case .apiCost:
                let left = APICostEstimator.estimate(usage: lhs.usage, modelName: lhs.name).usdValue
                let right = APICostEstimator.estimate(usage: rhs.usage, modelName: rhs.name).usdValue
                comparison = compare(left, right)
            }
            if comparison != .orderedSame {
                return direction == .ascending
                    ? comparison == .orderedAscending
                    : comparison == .orderedDescending
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        let knownTokens = knownModels.reduce(Int64(0)) { $0 + $1.usage.total }
        let allModelTokens = allModels.reduce(Int64(0)) { $0 + $1.usage.total }
        var pricedTokens: Int64 = 0
        var unpricedModelCount = 0
        for model in knownModels {
            let estimate = APICostEstimator.estimate(usage: model.usage, modelName: model.name)
            pricedTokens += estimate.pricedTokens
            if model.usage.total > 0 && !estimate.hasPricedUsage {
                unpricedModelCount += 1
            }
        }

        return ModelListPresentation(
            models: visibleModels,
            knownModelCount: knownModels.count,
            hiddenUnknownCount: allModels.count - knownModels.count,
            knownTokens: knownTokens,
            allModelTokens: allModelTokens,
            pricedTokens: pricedTokens,
            unpricedModelCount: unpricedModelCount
        )
    }
}

private func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
    if lhs < rhs { return .orderedAscending }
    if lhs > rhs { return .orderedDescending }
    return .orderedSame
}

private func isUnknownModelName(_ rawName: String) -> Bool {
    let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return name == "unknown" || name == "unknown model" || name == "(unknown)"
}

final class ModelDetailsControls: NSObject, NSSearchFieldDelegate {
    let searchField = NSSearchField()
    private(set) var query = ""
    private(set) var sort: ModelListSortOption = .total
    private(set) var direction: ModelListSortDirection = .descending
    var onChange: (() -> Void)?

    func install(in view: NSView, inputSurfaceColor: NSColor) {
        searchField.controlSize = .small
        searchField.font = .systemFont(ofSize: 11)
        searchField.isHidden = true
        searchField.appearance = NSAppearance(named: .darkAqua)
        searchField.delegate = self
        searchField.sendsWholeSearchString = false
        searchField.sendsSearchStringImmediately = true
        view.addSubview(searchField)
    }

    func layout(content: NSRect, tableY: CGFloat, visible: Bool) {
        searchField.isHidden = !visible
        guard visible else { return }

        let searchWidth = min(CGFloat(210), max(CGFloat(150), content.width * 0.18))
        searchField.frame = NSRect(x: content.maxX - searchWidth - 16, y: tableY + 8, width: searchWidth, height: 26)
        searchField.placeholderString = t(.modelSearchPlaceholder)
        searchField.setAccessibilityLabel(t(.modelSearchPlaceholder))
    }

    func configure(query: String?, sort rawSort: String?) {
        if let query {
            self.query = query
            searchField.stringValue = query
        }
        if let rawSort {
            let parts = rawSort.split(separator: "-", maxSplits: 1).map(String.init)
            let legacyOption = rawSort == "tokens" ? ModelListSortOption.total : nil
            if let option = legacyOption ?? ModelListSortOption(rawValue: parts[0]) {
                sort = option
                if parts.count == 2 {
                    direction = parts[1] == "asc" ? .ascending : .descending
                } else {
                    direction = option == .name ? .ascending : .descending
                }
            }
        }
        onChange?()
    }

    func toggleSort(_ option: ModelListSortOption) {
        if sort == option {
            direction = direction == .ascending ? .descending : .ascending
        } else {
            sort = option
            direction = .ascending
        }
        onChange?()
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField, field === searchField else { return }
        query = field.stringValue
        onChange?()
    }
}

private enum ModelDateRangePreset: Int, CaseIterable {
    case last7Days
    case last30Days
    case last90Days
    case custom

    var dayCount: Int? {
        switch self {
        case .last7Days: return 7
        case .last30Days: return 30
        case .last90Days: return 90
        case .custom: return nil
        }
    }

    var title: String {
        let isSimplifiedChinese = AppLanguage.current == .chinese
        let isTraditionalChinese = AppLanguage.current == .traditionalChinese
        switch self {
        case .last7Days:
            return isSimplifiedChinese ? "7 天" : (isTraditionalChinese ? "7 天" : "7 days")
        case .last30Days:
            return isSimplifiedChinese ? "30 天" : (isTraditionalChinese ? "30 天" : "30 days")
        case .last90Days:
            return isSimplifiedChinese ? "90 天" : (isTraditionalChinese ? "90 天" : "90 days")
        case .custom:
            return isSimplifiedChinese ? "自定义" : (isTraditionalChinese ? "自訂" : "Custom")
        }
    }
}

private final class ModelDateRangePanelView: NSView {
    override var isFlipped: Bool { true }
}

private final class ModelCalendarMonthView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private var dayButtons: [NSButton] = []
    private var rangeBackgroundViews: [NSView] = []
    private var buttonDates: [ObjectIdentifier: Date] = [:]
    private var month = Date()
    private var selectionStart = Date()
    private var selectionEnd = Date()
    var onSelectDate: ((Date) -> Void)?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        configureStaticViews()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(month: Date, start: Date, end: Date) {
        self.month = month
        selectionStart = start
        selectionEnd = end
        rebuildDays()
    }

    private func configureStaticViews() {
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.92)
        titleLabel.alignment = .center
        titleLabel.frame = NSRect(x: 0, y: 0, width: 252, height: 20)
        addSubview(titleLabel)

        let symbols = localizedWeekdaySymbols()
        for (index, symbol) in symbols.enumerated() {
            let label = NSTextField(labelWithString: symbol)
            label.font = .systemFont(ofSize: 10, weight: .medium)
            label.textColor = NSColor.white.withAlphaComponent(0.42)
            label.alignment = .center
            label.frame = NSRect(x: CGFloat(index) * 36, y: 30, width: 36, height: 16)
            addSubview(label)
        }
    }

    private func localizedWeekdaySymbols() -> [String] {
        switch AppLanguage.current {
        case .chinese:
            return ["日", "一", "二", "三", "四", "五", "六"]
        case .traditionalChinese:
            return ["日", "一", "二", "三", "四", "五", "六"]
        default:
            return ["S", "M", "T", "W", "T", "F", "S"]
        }
    }

    private func rebuildDays() {
        dayButtons.forEach { $0.removeFromSuperview() }
        dayButtons.removeAll()
        rangeBackgroundViews.forEach { $0.removeFromSuperview() }
        rangeBackgroundViews.removeAll()
        buttonDates.removeAll()

        let calendar = appCalendar()
        let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: month)
        ) ?? month
        let titleFormatter = DateFormatter()
        titleFormatter.timeZone = appTimeZone()
        switch AppLanguage.current {
        case .chinese:
            titleFormatter.locale = Locale(identifier: "zh_Hans_CN")
            titleFormatter.dateFormat = "yyyy 年 M 月"
        case .traditionalChinese:
            titleFormatter.locale = Locale(identifier: "zh_Hant_TW")
            titleFormatter.dateFormat = "yyyy 年 M 月"
        default:
            titleFormatter.locale = Locale(identifier: "en_US")
            titleFormatter.dateFormat = "MMMM yyyy"
        }
        titleLabel.stringValue = titleFormatter.string(from: monthStart)

        let weekday = calendar.component(.weekday, from: monthStart)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let days = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let today = calendar.startOfDay(for: Date())
        let minimumDate = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? .distantPast
        let rangeStart = calendar.startOfDay(for: min(selectionStart, selectionEnd))
        let rangeEnd = calendar.startOfDay(for: max(selectionStart, selectionEnd))
        let accessibilityFormatter = DateFormatter()
        accessibilityFormatter.locale = Locale.current
        accessibilityFormatter.timeZone = appTimeZone()
        accessibilityFormatter.dateStyle = .full

        for day in 1...days {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else { continue }
            let index = offset + day - 1
            let column = index % 7
            let row = index / 7
            let button = NSButton(title: "\(day)", target: self, action: #selector(dayPressed(_:)))
            button.isBordered = false
            button.font = .systemFont(ofSize: 11, weight: .medium)
            button.wantsLayer = true
            button.layer?.cornerRadius = 13
            button.frame = NSRect(
                x: CGFloat(column) * 36 + 5,
                y: 52 + CGFloat(row) * 31,
                width: 26,
                height: 26
            )
            let normalized = calendar.startOfDay(for: date)
            let enabled = normalized >= minimumDate && normalized <= today
            let isEndpoint = normalized == rangeStart || normalized == rangeEnd
            let isInRange = normalized > rangeStart && normalized < rangeEnd
            let isToday = normalized == today
            if rangeStart != rangeEnd && (isEndpoint || isInRange) {
                let background = NSView()
                background.wantsLayer = true
                background.layer?.backgroundColor = NSColor(
                    calibratedRed: 0.35,
                    green: 0.55,
                    blue: 0.86,
                    alpha: 0.18
                ).cgColor
                let cellX = CGFloat(column) * 36
                let backgroundX: CGFloat
                let backgroundWidth: CGFloat
                if normalized == rangeStart {
                    backgroundX = cellX + 18
                    backgroundWidth = 18
                } else if normalized == rangeEnd {
                    backgroundX = cellX
                    backgroundWidth = 18
                } else {
                    backgroundX = cellX
                    backgroundWidth = 36
                }
                background.frame = NSRect(
                    x: backgroundX,
                    y: 52 + CGFloat(row) * 31,
                    width: backgroundWidth,
                    height: 26
                )
                addSubview(background)
                rangeBackgroundViews.append(background)
            }
            button.isEnabled = enabled
            button.alphaValue = enabled ? 1 : 0.28
            button.contentTintColor = NSColor.white.withAlphaComponent(isEndpoint ? 1 : 0.82)
            if isEndpoint {
                button.font = .systemFont(ofSize: 11, weight: .bold)
                button.layer?.backgroundColor = NSColor(
                    calibratedRed: 0.35,
                    green: 0.55,
                    blue: 0.86,
                    alpha: 1
                ).cgColor
            } else if isInRange {
                button.layer?.backgroundColor = NSColor.clear.cgColor
            } else {
                button.layer?.backgroundColor = NSColor.clear.cgColor
            }
            if isToday && !isEndpoint {
                button.layer?.borderWidth = 1
                button.layer?.borderColor = NSColor(
                    calibratedRed: 0.42,
                    green: 0.63,
                    blue: 0.94,
                    alpha: 0.9
                ).cgColor
            } else {
                button.layer?.borderWidth = 0
            }
            button.toolTip = accessibilityFormatter.string(from: date)
            button.setAccessibilityLabel(accessibilityFormatter.string(from: date))
            if isEndpoint {
                button.setAccessibilityValue(
                    normalized == rangeStart
                        ? localized("开始日期", traditional: "開始日期", english: "Start date")
                        : localized("结束日期", traditional: "結束日期", english: "End date")
                )
            } else if isInRange {
                button.setAccessibilityValue(
                    localized("已选范围内", traditional: "已選範圍內", english: "In selected range")
                )
            }
            addSubview(button)
            dayButtons.append(button)
            buttonDates[ObjectIdentifier(button)] = date
        }
    }

    private func localized(_ simplified: String, traditional: String, english: String) -> String {
        switch AppLanguage.current {
        case .chinese: return simplified
        case .traditionalChinese: return traditional
        default: return english
        }
    }

    @objc private func dayPressed(_ sender: NSButton) {
        guard let date = buttonDates[ObjectIdentifier(sender)] else { return }
        onSelectDate?(date)
    }
}

private final class ModelDateRangePopoverController: NSViewController {
    private let titleLabel = NSTextField(labelWithString: "")
    private let rangeLabel = NSTextField(labelWithString: "")
    private let startCaptionLabel = NSTextField(labelWithString: "")
    private let endCaptionLabel = NSTextField(labelWithString: "")
    private let helperLabel = NSTextField(labelWithString: "")
    private let leftPreviousButton = NSButton()
    private let leftNextButton = NSButton()
    private let rightPreviousButton = NSButton()
    private let rightNextButton = NSButton()
    private let leftMonthView = ModelCalendarMonthView()
    private let rightMonthView = ModelCalendarMonthView()
    private let cancelButton = NSButton()
    private let applyButton = NSButton()
    private var startDate = Date()
    private var endDate = Date()
    private var leftVisibleMonth = Date()
    private var rightVisibleMonth = Date()
    var onApply: ((Date, Date) -> Void)?
    var onCancel: (() -> Void)?

    override func loadView() {
        let panel = ModelDateRangePanelView(frame: NSRect(x: 0, y: 0, width: 620, height: 410))
        panel.wantsLayer = true
        panel.layer?.backgroundColor = NSColor(
            calibratedRed: 0.075,
            green: 0.09,
            blue: 0.12,
            alpha: 1
        ).cgColor
        view = panel
        configureControls()
    }

    func configure(start: Date, end: Date) {
        loadViewIfNeeded()
        let calendar = appCalendar()
        startDate = calendar.startOfDay(for: min(start, end))
        endDate = calendar.startOfDay(for: max(start, end))
        leftVisibleMonth = monthStart(for: startDate)
        rightVisibleMonth = monthStart(for: endDate)
        updateLocalizedCopy()
        updateCalendar()
    }

    private func configureControls() {
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.94)
        titleLabel.frame = NSRect(x: 20, y: 16, width: 260, height: 20)
        view.addSubview(titleLabel)

        rangeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        rangeLabel.textColor = NSColor.white.withAlphaComponent(0.58)
        rangeLabel.frame = NSRect(x: 20, y: 42, width: 580, height: 18)
        view.addSubview(rangeLabel)

        for (label, x) in [(startCaptionLabel, CGFloat(54)), (endCaptionLabel, CGFloat(314))] {
            label.font = .systemFont(ofSize: 10, weight: .semibold)
            label.textColor = NSColor.white.withAlphaComponent(0.42)
            label.alignment = .center
            label.frame = NSRect(x: x, y: 68, width: 252, height: 16)
            view.addSubview(label)
        }

        for (button, symbol, action) in [
            (leftPreviousButton, "chevron.left", #selector(leftPreviousMonth)),
            (leftNextButton, "chevron.right", #selector(leftNextMonth)),
            (rightPreviousButton, "chevron.left", #selector(rightPreviousMonth)),
            (rightNextButton, "chevron.right", #selector(rightNextMonth))
        ] {
            button.isBordered = false
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            button.contentTintColor = NSColor.white.withAlphaComponent(0.7)
            button.wantsLayer = true
            button.layer?.cornerRadius = 8
            button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.055).cgColor
            button.target = self
            button.action = action
            view.addSubview(button)
        }
        leftPreviousButton.frame = NSRect(x: 54, y: 91, width: 28, height: 28)
        leftNextButton.frame = NSRect(x: 278, y: 91, width: 28, height: 28)
        rightPreviousButton.frame = NSRect(x: 314, y: 91, width: 28, height: 28)
        rightNextButton.frame = NSRect(x: 538, y: 91, width: 28, height: 28)

        leftMonthView.frame = NSRect(x: 54, y: 94, width: 252, height: 246)
        rightMonthView.frame = NSRect(x: 314, y: 94, width: 252, height: 246)
        leftMonthView.onSelectDate = { [weak self] date in self?.selectStart(date) }
        rightMonthView.onSelectDate = { [weak self] date in self?.selectEnd(date) }
        view.addSubview(leftMonthView)
        view.addSubview(rightMonthView)

        let divider = NSBox(frame: NSRect(x: 20, y: 344, width: 580, height: 1))
        divider.boxType = .separator
        view.addSubview(divider)

        helperLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        helperLabel.textColor = NSColor.white.withAlphaComponent(0.46)
        helperLabel.frame = NSRect(x: 20, y: 368, width: 360, height: 18)
        view.addSubview(helperLabel)

        cancelButton.isBordered = false
        cancelButton.font = .systemFont(ofSize: 12, weight: .semibold)
        cancelButton.wantsLayer = true
        cancelButton.layer?.cornerRadius = 7
        cancelButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
        cancelButton.frame = NSRect(x: 424, y: 360, width: 80, height: 34)
        cancelButton.target = self
        cancelButton.action = #selector(cancelPressed)
        view.addSubview(cancelButton)

        applyButton.isBordered = false
        applyButton.font = .systemFont(ofSize: 12, weight: .bold)
        applyButton.contentTintColor = .white
        applyButton.wantsLayer = true
        applyButton.layer?.cornerRadius = 7
        applyButton.layer?.backgroundColor = NSColor(calibratedRed: 0.35, green: 0.55, blue: 0.86, alpha: 1).cgColor
        applyButton.frame = NSRect(x: 514, y: 360, width: 86, height: 34)
        applyButton.target = self
        applyButton.action = #selector(applyPressed)
        view.addSubview(applyButton)
        updateLocalizedCopy()
    }

    private func updateLocalizedCopy() {
        switch AppLanguage.current {
        case .chinese:
            titleLabel.stringValue = "选择时间范围"
            startCaptionLabel.stringValue = "开始日期"
            endCaptionLabel.stringValue = "结束日期"
            helperLabel.stringValue = "左侧选择开始日期，右侧选择结束日期"
            cancelButton.title = "取消"
            applyButton.title = "应用"
            leftPreviousButton.setAccessibilityLabel("开始日期上一个月")
            leftNextButton.setAccessibilityLabel("开始日期下一个月")
            rightPreviousButton.setAccessibilityLabel("结束日期上一个月")
            rightNextButton.setAccessibilityLabel("结束日期下一个月")
        case .traditionalChinese:
            titleLabel.stringValue = "選擇時間範圍"
            startCaptionLabel.stringValue = "開始日期"
            endCaptionLabel.stringValue = "結束日期"
            helperLabel.stringValue = "左側選擇開始日期，右側選擇結束日期"
            cancelButton.title = "取消"
            applyButton.title = "套用"
            leftPreviousButton.setAccessibilityLabel("開始日期上一個月")
            leftNextButton.setAccessibilityLabel("開始日期下一個月")
            rightPreviousButton.setAccessibilityLabel("結束日期上一個月")
            rightNextButton.setAccessibilityLabel("結束日期下一個月")
        default:
            titleLabel.stringValue = "Choose a date range"
            startCaptionLabel.stringValue = "START DATE"
            endCaptionLabel.stringValue = "END DATE"
            helperLabel.stringValue = "Choose the start date on the left and the end date on the right"
            cancelButton.title = "Cancel"
            applyButton.title = "Apply"
            leftPreviousButton.setAccessibilityLabel("Previous start month")
            leftNextButton.setAccessibilityLabel("Next start month")
            rightPreviousButton.setAccessibilityLabel("Previous end month")
            rightNextButton.setAccessibilityLabel("Next end month")
        }
        cancelButton.setAccessibilityLabel(cancelButton.title)
        applyButton.setAccessibilityLabel(applyButton.title)
        updateRangeLabel()
    }

    private func updateRangeLabel() {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = appTimeZone()
        formatter.dateFormat = "yyyy/MM/dd"
        let calendar = appCalendar()
        let dayCount = max(
            1,
            (calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0) + 1
        )
        let daySuffix: String
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: daySuffix = "天"
        default: daySuffix = dayCount == 1 ? "day" : "days"
        }
        rangeLabel.stringValue = "\(formatter.string(from: startDate))  →  \(formatter.string(from: endDate))  ·  \(dayCount) \(daySuffix)"
    }

    private func updateCalendar() {
        let calendar = appCalendar()
        leftMonthView.configure(month: leftVisibleMonth, start: startDate, end: endDate)
        rightMonthView.configure(month: rightVisibleMonth, start: startDate, end: endDate)
        let minimumMonth = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? .distantPast
        let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        updateNavigationButton(
            leftPreviousButton,
            enabled: (calendar.date(byAdding: .month, value: -1, to: leftVisibleMonth) ?? leftVisibleMonth) >= minimumMonth
        )
        updateNavigationButton(
            leftNextButton,
            enabled: (calendar.date(byAdding: .month, value: 1, to: leftVisibleMonth) ?? leftVisibleMonth) <= currentMonth
        )
        updateNavigationButton(
            rightPreviousButton,
            enabled: (calendar.date(byAdding: .month, value: -1, to: rightVisibleMonth) ?? rightVisibleMonth) >= minimumMonth
        )
        updateNavigationButton(
            rightNextButton,
            enabled: (calendar.date(byAdding: .month, value: 1, to: rightVisibleMonth) ?? rightVisibleMonth) <= currentMonth
        )
        updateLocalizedCopy()
        applyButton.isEnabled = true
        applyButton.alphaValue = 1
    }

    private func selectStart(_ date: Date) {
        let normalized = appCalendar().startOfDay(for: date)
        startDate = normalized
        if startDate > endDate {
            endDate = normalized
            rightVisibleMonth = monthStart(for: endDate)
        }
        updateCalendar()
    }

    private func selectEnd(_ date: Date) {
        let normalized = appCalendar().startOfDay(for: date)
        endDate = normalized
        if endDate < startDate {
            startDate = normalized
            leftVisibleMonth = monthStart(for: startDate)
        }
        updateCalendar()
    }

    private func monthStart(for date: Date) -> Date {
        let calendar = appCalendar()
        return calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func updateNavigationButton(_ button: NSButton, enabled: Bool) {
        button.isEnabled = enabled
        button.alphaValue = enabled ? 1 : 0.35
    }

    @objc private func leftPreviousMonth() {
        leftVisibleMonth = appCalendar().date(byAdding: .month, value: -1, to: leftVisibleMonth) ?? leftVisibleMonth
        updateCalendar()
    }

    @objc private func leftNextMonth() {
        leftVisibleMonth = appCalendar().date(byAdding: .month, value: 1, to: leftVisibleMonth) ?? leftVisibleMonth
        updateCalendar()
    }

    @objc private func rightPreviousMonth() {
        rightVisibleMonth = appCalendar().date(byAdding: .month, value: -1, to: rightVisibleMonth) ?? rightVisibleMonth
        updateCalendar()
    }

    @objc private func rightNextMonth() {
        rightVisibleMonth = appCalendar().date(byAdding: .month, value: 1, to: rightVisibleMonth) ?? rightVisibleMonth
        updateCalendar()
    }

    @objc private func cancelPressed() {
        onCancel?()
    }

    @objc private func applyPressed() {
        onApply?(startDate, endDate)
    }
}

enum DateRangeControlContext {
    case models
    case reasoning
}

final class ModelDateRangeControls: NSObject {
    private var quickButtons: [ModelDateRangePreset: NSButton] = [:]
    private let rangeButton = NSButton()
    private let popover = NSPopover()
    private let popoverController = ModelDateRangePopoverController()
    private var selectedPreset: ModelDateRangePreset = .last90Days
    private var startDate: Date
    private var endDate: Date
    private var isLoading = false
    private var inputSurfaceColor = NSColor.clear
    private let context: DateRangeControlContext
    var onChange: ((Date, Date) -> Void)?

    init(context: DateRangeControlContext = .models) {
        self.context = context
        let calendar = appCalendar()
        let today = calendar.startOfDay(for: Date())
        startDate = calendar.date(byAdding: .day, value: -89, to: today) ?? today
        endDate = today
        super.init()
    }

    func install(in view: NSView, inputSurfaceColor: NSColor) {
        self.inputSurfaceColor = inputSurfaceColor
        for preset in [ModelDateRangePreset.last7Days, .last30Days, .last90Days] {
            let button = NSButton(title: preset.title, target: self, action: #selector(quickRangePressed(_:)))
            button.tag = preset.rawValue
            button.isBordered = false
            button.font = .systemFont(ofSize: 11, weight: .semibold)
            button.wantsLayer = true
            button.layer?.cornerRadius = 8
            button.layer?.borderWidth = 1
            button.setAccessibilityLabel(preset.title)
            view.addSubview(button)
            quickButtons[preset] = button
        }

        rangeButton.isBordered = false
        rangeButton.alignment = .center
        rangeButton.font = .systemFont(ofSize: 11, weight: .semibold)
        let calendarSymbol = NSImage(systemSymbolName: "calendar", accessibilityDescription: nil)
        rangeButton.image = calendarSymbol?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        )
        rangeButton.imagePosition = .imageLeading
        rangeButton.imageHugsTitle = true
        rangeButton.contentTintColor = NSColor.white.withAlphaComponent(0.86)
        rangeButton.wantsLayer = true
        rangeButton.layer?.cornerRadius = 8
        rangeButton.layer?.borderWidth = 1
        rangeButton.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        rangeButton.layer?.backgroundColor = inputSurfaceColor.cgColor
        rangeButton.target = self
        rangeButton.action = #selector(showDateRangePopover)
        view.addSubview(rangeButton)

        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentSize = NSSize(width: 620, height: 410)
        popover.contentViewController = popoverController
        popoverController.onCancel = { [weak self] in self?.popover.performClose(nil) }
        popoverController.onApply = { [weak self] start, end in
            self?.applyCustom(start: start, end: end)
        }
        updateButtonTitle()
        updateAccessibilityLabel()
        updateSelectionAppearance(inputSurfaceColor: inputSurfaceColor)
    }

    func layout(content: NSRect, visible: Bool) {
        let x = content.minX + 92
        let y = content.minY + 66
        layout(
            in: NSRect(x: x, y: y, width: min(332, content.maxX - x), height: 34),
            visible: visible
        )
    }

    func layout(in rect: NSRect, visible: Bool) {
        for button in quickButtons.values {
            button.isHidden = !visible
        }
        rangeButton.isHidden = !visible
        guard visible else {
            popover.performClose(nil)
            return
        }
        updateButtonTitle()
        updateAccessibilityLabel()
        let gap: CGFloat = 8
        let customWidth = min(CGFloat(116), max(CGFloat(88), rect.width * 0.36))
        let buttonWidth = max(CGFloat(42), (rect.width - customWidth - gap * 3) / 3)
        for (index, preset) in [ModelDateRangePreset.last7Days, .last30Days, .last90Days].enumerated() {
            quickButtons[preset]?.frame = NSRect(
                x: rect.minX + CGFloat(index) * (buttonWidth + gap),
                y: rect.minY,
                width: buttonWidth,
                height: rect.height
            )
        }
        let customX = rect.minX + 3 * (buttonWidth + gap)
        rangeButton.frame = NSRect(x: customX, y: rect.minY, width: rect.maxX - customX, height: rect.height)
    }

    func setLoading(_ isLoading: Bool) {
        self.isLoading = isLoading
        for button in quickButtons.values {
            button.isEnabled = !isLoading
            button.alphaValue = isLoading ? 0.58 : 1
        }
        rangeButton.isEnabled = !isLoading
        rangeButton.alphaValue = isLoading ? 0.58 : 1
        updateButtonTitle()
    }

    private func updateButtonTitle() {
        guard selectedPreset == .custom else {
            rangeButton.title = ModelDateRangePreset.custom.title
            rangeButton.toolTip = nil
            return
        }
        rangeButton.title = isLoading
            ? localizedUpdatingTitle()
            : formattedRange(dateFormat: "MM/dd", separator: "–")
        rangeButton.toolTip = formattedRange(dateFormat: "yyyy/MM/dd", separator: " → ")
    }

    private func updateAccessibilityLabel() {
        let currentSelection = selectedPreset == .custom
            ? formattedRange(dateFormat: "yyyy/MM/dd", separator: " → ")
            : selectedPreset.title
        switch AppLanguage.current {
        case .chinese:
            let subject = context == .models ? "模型统计" : "思考分析"
            rangeButton.setAccessibilityLabel("自定义\(subject)时间范围，当前选择 \(currentSelection)")
        case .traditionalChinese:
            let subject = context == .models ? "模型統計" : "思考分析"
            rangeButton.setAccessibilityLabel("自訂\(subject)時間範圍，目前選擇 \(currentSelection)")
        default:
            let subject = context == .models ? "model statistics" : "reasoning analysis"
            rangeButton.setAccessibilityLabel("Choose a custom \(subject) date range. Current selection: \(currentSelection)")
        }
    }

    private func formattedRange(dateFormat: String, separator: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = appTimeZone()
        formatter.dateFormat = dateFormat
        return "\(formatter.string(from: startDate))\(separator)\(formatter.string(from: endDate))"
    }

    private func localizedUpdatingTitle() -> String {
        switch AppLanguage.current {
        case .chinese: return "更新中…"
        case .traditionalChinese: return "更新中…"
        default: return "Updating…"
        }
    }

    @objc private func showDateRangePopover() {
        popoverController.configure(start: startDate, end: endDate)
        popover.show(relativeTo: rangeButton.bounds, of: rangeButton, preferredEdge: .minY)
    }

    @objc private func quickRangePressed(_ sender: NSButton) {
        guard let preset = ModelDateRangePreset(rawValue: sender.tag),
              let dayCount = preset.dayCount else { return }
        let calendar = appCalendar()
        let today = calendar.startOfDay(for: Date())
        selectedPreset = preset
        startDate = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today) ?? today
        endDate = today
        popover.performClose(nil)
        updateButtonTitle()
        updateAccessibilityLabel()
        updateSelectionAppearance(inputSurfaceColor: inputSurfaceColor)
        notifyChange()
    }

    private func applyCustom(start: Date, end: Date) {
        let calendar = appCalendar()
        startDate = calendar.startOfDay(for: min(start, end))
        endDate = calendar.startOfDay(for: max(start, end))
        selectedPreset = .custom
        updateButtonTitle()
        updateAccessibilityLabel()
        updateSelectionAppearance(inputSurfaceColor: inputSurfaceColor)
        popover.performClose(nil)
        notifyChange()
    }

    private func notifyChange() {
        let calendar = appCalendar()
        let nextDay = calendar.date(byAdding: .day, value: 1, to: endDate) ?? endDate
        onChange?(startDate, min(Date(), nextDay.addingTimeInterval(-0.001)))
    }

    private func updateSelectionAppearance(inputSurfaceColor: NSColor) {
        let accent = NSColor(calibratedRed: 0.35, green: 0.55, blue: 0.86, alpha: 1)
        for (preset, button) in quickButtons {
            let selected = preset == selectedPreset
            button.layer?.backgroundColor = selected ? accent.cgColor : inputSurfaceColor.cgColor
            button.layer?.borderColor = selected
                ? accent.withAlphaComponent(0.94).cgColor
                : NSColor.white.withAlphaComponent(0.12).cgColor
            button.contentTintColor = NSColor.white.withAlphaComponent(selected ? 1 : 0.78)
            button.state = selected ? .on : .off
            button.setAccessibilityValue(selected ? "selected" : nil)
        }
        let customSelected = selectedPreset == .custom
        rangeButton.layer?.backgroundColor = customSelected ? accent.cgColor : inputSurfaceColor.cgColor
        rangeButton.layer?.borderColor = customSelected
            ? accent.withAlphaComponent(0.94).cgColor
            : NSColor.white.withAlphaComponent(0.12).cgColor
        rangeButton.contentTintColor = NSColor.white.withAlphaComponent(customSelected ? 1 : 0.82)
        rangeButton.state = customSelected ? .on : .off
        rangeButton.setAccessibilityValue(customSelected ? "selected" : nil)
    }
}
