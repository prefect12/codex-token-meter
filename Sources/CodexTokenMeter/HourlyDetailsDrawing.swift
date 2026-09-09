import Cocoa

final class HourlyCalendarView: NSView {
    private var calendar: Calendar { appCalendar() }
    private let monthTitle = NSTextField(labelWithString: "")
    private let previousMonthButton = NSButton(frame: .zero)
    private let nextMonthButton = NSButton(frame: .zero)
    private var weekdayLabels: [NSTextField] = []
    private var dayButtons: [NSButton] = []
    private var visibleDates: [Date] = []
    private var displayedMonth = Date()
    private var selectedDate = Date()
    private var minimumDate: Date?
    private var maximumDate = Date()
    var onSelectDate: ((Date) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(
            calibratedRed: 0.075,
            green: 0.09,
            blue: 0.12,
            alpha: 1
        ).cgColor
        buildSubviews()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func buildSubviews() {
        monthTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        monthTitle.textColor = NSColor.white.withAlphaComponent(0.92)
        monthTitle.alignment = .left
        addSubview(monthTitle)

        for (button, symbol, action) in [
            (previousMonthButton, "chevron.left", #selector(previousMonth)),
            (nextMonthButton, "chevron.right", #selector(nextMonth))
        ] {
            button.isBordered = false
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            button.imagePosition = .imageOnly
            button.contentTintColor = NSColor.white.withAlphaComponent(0.76)
            button.wantsLayer = true
            button.layer?.cornerRadius = 7
            button.layer?.borderWidth = 1
            button.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
            button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.035).cgColor
            button.target = self
            button.action = action
            addSubview(button)
        }

        weekdayLabels = weekdayTitles().map { title in
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 10.5, weight: .semibold)
            label.textColor = NSColor.white.withAlphaComponent(0.52)
            label.alignment = .center
            addSubview(label)
            return label
        }

        dayButtons = (0..<42).map { index in
            let button = NSButton(frame: .zero)
            button.tag = index
            button.isBordered = false
            button.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
            button.alignment = .center
            button.wantsLayer = true
            button.layer?.cornerRadius = 7
            button.target = self
            button.action = #selector(daySelected(_:))
            addSubview(button)
            return button
        }

        previousMonthButton.setAccessibilityLabel(monthNavigationLabel(previous: true))
        nextMonthButton.setAccessibilityLabel(monthNavigationLabel(previous: false))
    }

    override func layout() {
        super.layout()
        let horizontalInset: CGFloat = 16
        let contentWidth = bounds.width - horizontalInset * 2
        let columnWidth = contentWidth / 7

        monthTitle.frame = NSRect(x: horizontalInset, y: bounds.height - 48, width: contentWidth - 76, height: 24)
        previousMonthButton.frame = NSRect(x: bounds.width - 76, y: bounds.height - 50, width: 28, height: 28)
        nextMonthButton.frame = NSRect(x: bounds.width - 40, y: bounds.height - 50, width: 28, height: 28)

        for (column, label) in weekdayLabels.enumerated() {
            label.frame = NSRect(
                x: horizontalInset + CGFloat(column) * columnWidth,
                y: bounds.height - 83,
                width: columnWidth,
                height: 18
            )
        }

        let firstRowY = bounds.height - 116
        let rowStep: CGFloat = 31
        for (index, button) in dayButtons.enumerated() {
            let row = index / 7
            let column = index % 7
            button.frame = NSRect(
                x: horizontalInset + CGFloat(column) * columnWidth + (columnWidth - 30) / 2,
                y: firstRowY - CGFloat(row) * rowStep - 1,
                width: 30,
                height: 28
            )
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let dividerY = bounds.height - 92.5
        NSColor.white.withAlphaComponent(0.07).setFill()
        NSRect(x: 16, y: dividerY, width: bounds.width - 32, height: 1).fill()
    }

    func configure(date: Date, minimumDate: Date?, maximumDate: Date) {
        for (label, title) in zip(weekdayLabels, weekdayTitles()) {
            label.stringValue = title
        }
        previousMonthButton.setAccessibilityLabel(monthNavigationLabel(previous: true))
        nextMonthButton.setAccessibilityLabel(monthNavigationLabel(previous: false))
        selectedDate = calendar.startOfDay(for: date)
        self.minimumDate = minimumDate.map(calendar.startOfDay(for:))
        self.maximumDate = calendar.startOfDay(for: maximumDate)
        displayedMonth = monthStart(for: selectedDate)
        reloadMonth()
    }

    private func reloadMonth() {
        monthTitle.stringValue = monthTitleText(displayedMonth)
        guard let firstWeekday = calendar.dateComponents([.weekday], from: displayedMonth).weekday,
              let gridStart = calendar.date(byAdding: .day, value: -(firstWeekday - 1), to: displayedMonth) else {
            return
        }

        visibleDates = (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
        let displayedMonthNumber = calendar.component(.month, from: displayedMonth)
        let accessibilityFormatter = DateFormatter()
        accessibilityFormatter.calendar = calendar
        accessibilityFormatter.locale = localeForCurrentLanguage()
        accessibilityFormatter.timeZone = appTimeZone()
        accessibilityFormatter.dateStyle = .full

        for (index, button) in dayButtons.enumerated() {
            guard visibleDates.indices.contains(index) else {
                button.isHidden = true
                continue
            }
            let date = visibleDates[index]
            let isInDisplayedMonth = calendar.component(.month, from: date) == displayedMonthNumber
                && calendar.component(.year, from: date) == calendar.component(.year, from: displayedMonth)
            let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
            let isToday = calendar.isDateInToday(date)
            let isAvailable = isSelectable(date)

            button.isHidden = false
            button.title = String(calendar.component(.day, from: date))
            button.isEnabled = isAvailable
            button.alphaValue = 1
            button.layer?.backgroundColor = isSelected
                ? NSColor.systemBlue.withAlphaComponent(0.92).cgColor
                : NSColor.clear.cgColor
            button.layer?.borderWidth = isToday && !isSelected ? 1.5 : 0
            button.layer?.borderColor = NSColor.systemCyan.withAlphaComponent(0.95).cgColor
            button.layer?.cornerRadius = isToday && !isSelected ? 14 : 7

            if isSelected {
                button.contentTintColor = .white
                button.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
            } else if !isAvailable {
                button.contentTintColor = NSColor.white.withAlphaComponent(0.27)
                button.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
            } else if isInDisplayedMonth {
                button.contentTintColor = NSColor.white.withAlphaComponent(0.84)
                button.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
            } else {
                button.contentTintColor = NSColor.white.withAlphaComponent(0.34)
                button.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
            }

            button.setAccessibilityLabel(accessibilityFormatter.string(from: date))
        }

        let previousStart = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
        let nextStart = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
        previousMonthButton.isEnabled = monthContainsSelectableDate(previousStart)
        nextMonthButton.isEnabled = monthContainsSelectableDate(nextStart)
        previousMonthButton.alphaValue = previousMonthButton.isEnabled ? 1 : 0.34
        nextMonthButton.alphaValue = nextMonthButton.isEnabled ? 1 : 0.34
        needsLayout = true
        needsDisplay = true
    }

    private func isSelectable(_ date: Date) -> Bool {
        let day = calendar.startOfDay(for: date)
        if let minimumDate, day < minimumDate { return false }
        return day <= maximumDate
    }

    private func monthContainsSelectableDate(_ month: Date) -> Bool {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return false }
        let lastDay = interval.end.addingTimeInterval(-1)
        if let minimumDate, lastDay < minimumDate { return false }
        return interval.start <= maximumDate
    }

    private func monthStart(for date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    private func weekdayTitles() -> [String] {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese:
            return ["日", "一", "二", "三", "四", "五", "六"]
        case .japanese:
            return ["日", "月", "火", "水", "木", "金", "土"]
        default:
            return ["S", "M", "T", "W", "T", "F", "S"]
        }
    }

    private func monthTitleText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = localeForCurrentLanguage()
        formatter.timeZone = appTimeZone()
        switch AppLanguage.current {
        case .chinese, .traditionalChinese, .japanese:
            formatter.dateFormat = "yyyy年M月"
        default:
            formatter.dateFormat = "MMMM yyyy"
        }
        return formatter.string(from: date)
    }

    private func localeForCurrentLanguage() -> Locale {
        switch AppLanguage.current {
        case .chinese: return Locale(identifier: "zh_Hans_CN")
        case .traditionalChinese: return Locale(identifier: "zh_Hant_TW")
        case .japanese: return Locale(identifier: "ja_JP")
        default: return Locale(identifier: "en_US")
        }
    }

    private func monthNavigationLabel(previous: Bool) -> String {
        switch AppLanguage.current {
        case .chinese: return previous ? "上个月" : "下个月"
        case .traditionalChinese: return previous ? "上個月" : "下個月"
        case .japanese: return previous ? "前の月" : "次の月"
        default: return previous ? "Previous month" : "Next month"
        }
    }

    @objc private func previousMonth() {
        guard let month = calendar.date(byAdding: .month, value: -1, to: displayedMonth),
              monthContainsSelectableDate(month) else { return }
        displayedMonth = monthStart(for: month)
        reloadMonth()
    }

    @objc private func nextMonth() {
        guard let month = calendar.date(byAdding: .month, value: 1, to: displayedMonth),
              monthContainsSelectableDate(month) else { return }
        displayedMonth = monthStart(for: month)
        reloadMonth()
    }

    @objc private func daySelected(_ sender: NSButton) {
        guard visibleDates.indices.contains(sender.tag) else { return }
        let date = visibleDates[sender.tag]
        guard isSelectable(date) else { return }
        selectedDate = calendar.startOfDay(for: date)
        onSelectDate?(selectedDate)
    }
}

final class HourlyDatePopoverController: NSViewController {
    private let calendarView = HourlyCalendarView(frame: NSRect(x: 0, y: 0, width: 304, height: 270))
    var onSelectDate: ((Date) -> Void)? {
        didSet { calendarView.onSelectDate = onSelectDate }
    }

    override func loadView() {
        view = calendarView
    }

    func configure(date: Date, minimumDate: Date?, maximumDate: Date) {
        loadViewIfNeeded()
        calendarView.configure(date: date, minimumDate: minimumDate, maximumDate: maximumDate)
    }
}

extension UsageDetailsView {
    func recentCalendarReport(for snapshot: DetailsSnapshot) -> TokenReport {
        switch selectedDetailsSource {
        case .all:
            return mergedTokenReport(QuotaViewOption.visiblePlatformCases.map { source in
                switch source {
                case .codex: return snapshot.recentCodex
                case .claude: return snapshot.recentClaude
                case .api: return snapshot.recentAPI
                case .all: return TokenReport(scannedAt: snapshot.recentAll.scannedAt)
                }
            })
        case .codex: return snapshot.recentCodex
        case .claude: return snapshot.recentClaude
        case .api: return snapshot.recentAPI
        }
    }

    func continuousCalendarHours(snapshot: DetailsSnapshot) -> [HourUsage] {
        let calendar = appCalendar()
        let hourCount = selectedHourlyRangeHours
        let last: Date
        let reports: [TokenReport]
        if let selectedHourlyDate {
            let dayStart = calendar.startOfDay(for: selectedHourlyDate)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)?.addingTimeInterval(-0.001) ?? dayStart
            last = calendar.dateInterval(of: .hour, for: dayEnd)?.start ?? dayStart
            reports = historicalHourlyReports(for: snapshot)
        } else {
            let report = recentCalendarReport(for: snapshot)
            guard let scannedHour = calendar.dateInterval(of: .hour, for: report.scannedAt)?.start else {
                return report.byHour
            }
            last = scannedHour
            reports = [report]
        }
        let start = calendar.date(byAdding: .hour, value: -(hourCount - 1), to: last) ?? last
        let end = calendar.date(byAdding: .hour, value: hourCount, to: start)?.addingTimeInterval(-0.001) ?? last
        var buckets: [Date: [HourUsage]] = [:]
        for report in reports {
            for hour in hourlySlice(report.byHour, from: start, through: end) {
                buckets[hour.hour, default: []].append(hour)
            }
        }
        let byHour = buckets.mapValues(aggregateCalendarHours)
        return (0..<hourCount).map { offset in
            let hour = calendar.date(byAdding: .hour, value: offset, to: start) ?? start
            return byHour[hour] ?? HourUsage(hour: hour, usage: Usage(), turns: 0)
        }
    }

    func historicalHourlyReports(for snapshot: DetailsSnapshot) -> [TokenReport] {
        guard let hourlyRangeReports else { return [] }
        return [hourlyRangeReports.report(for: selectedDetailsSource)]
    }

    func hourlySlice(_ hours: [HourUsage], from start: Date, through end: Date) -> ArraySlice<HourUsage> {
        var lower = 0
        var upper = hours.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if hours[middle].hour < start {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        let startIndex = lower
        upper = hours.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if hours[middle].hour <= end {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return hours[startIndex..<lower]
    }

    func earliestHourlyDate(in snapshot: DetailsSnapshot) -> Date? {
        let report: TokenReport
        switch selectedDetailsSource {
        case .all: report = snapshot.all
        case .codex: report = snapshot.codex
        case .claude: report = snapshot.claude
        case .api: report = snapshot.api
        }
        return report.byDay.first.flatMap { dayFormatter().date(from: $0.day) }
    }

    func displayedCalendarHours(snapshot: DetailsSnapshot) -> [HourUsage] {
        let hours = continuousCalendarHours(snapshot: snapshot)
        return hidesEmptyCalendarHours ? hours.filter { $0.usage.total > 0 } : hours
    }

    func aggregateCalendarHours(_ hours: [HourUsage]) -> HourUsage {
        var usage = Usage()
        var turns = 0
        var models: [String: ModelUsage] = [:]
        for hour in hours {
            usage.add(hour.usage)
            turns += hour.turns
            for model in hour.modelBreakdown {
                var value = models[model.name] ?? ModelUsage(name: model.name, usage: Usage(), events: 0, sessions: 0)
                value.usage.add(model.usage)
                value.turns += model.turns
                value.events += model.events
                value.sessions += model.sessions
                models[model.name] = value
            }
        }
        return HourUsage(
            hour: hours.first?.hour ?? Date(),
            usage: usage,
            turns: turns,
            modelBreakdown: models.values.sorted { $0.usage.total > $1.usage.total }
        )
    }

    func selectedCalendarHourSummary(snapshot: DetailsSnapshot) -> HourUsage? {
        guard !selectedCalendarHours.isEmpty else { return nil }
        let selected = continuousCalendarHours(snapshot: snapshot).filter { selectedCalendarHours.contains($0.hour) }
        return selected.isEmpty ? nil : aggregateCalendarHours(selected)
    }

    func hourlyDisplayedSummary(snapshot: DetailsSnapshot) -> HourUsage {
        if let selected = selectedCalendarHourSummary(snapshot: snapshot) {
            return selected
        }
        return aggregateCalendarHours(continuousCalendarHours(snapshot: snapshot))
    }

    func hourlyLocalized(_ chinese: String, traditionalChinese: String? = nil, japanese: String? = nil, english: String) -> String {
        switch AppLanguage.current {
        case .chinese: return chinese
        case .traditionalChinese: return traditionalChinese ?? chinese
        case .japanese: return japanese ?? english
        default: return english
        }
    }

    func hourlySelectedDateText(_ date: Date, format: String = "yyyy-MM-dd") -> String {
        let formatter = DateFormatter()
        formatter.calendar = appCalendar()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = appTimeZone()
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    func hourlyWindowSummaryTitle() -> String {
        guard let selectedHourlyDate else {
            return hourlyLocalized(
                "过去 \(selectedHourlyRangeHours) 小时汇总",
                traditionalChinese: "過去 \(selectedHourlyRangeHours) 小時彙總",
                japanese: "過去\(selectedHourlyRangeHours)時間の集計",
                english: "Last \(selectedHourlyRangeHours) hours summary"
            )
        }
        let end = hourlySelectedDateText(selectedHourlyDate)
        if selectedHourlyRangeHours == 24 {
            return hourlyLocalized(
                "\(end) · 24 小时汇总",
                traditionalChinese: "\(end) · 24 小時彙總",
                japanese: "\(end) · 24時間の集計",
                english: "\(end) · 24-hour summary"
            )
        }
        let calendar = appCalendar()
        let startDate = calendar.date(byAdding: .day, value: -1, to: selectedHourlyDate) ?? selectedHourlyDate
        let start = hourlySelectedDateText(startDate)
        return hourlyLocalized(
            "\(start) – \(end) · 48 小时汇总",
            traditionalChinese: "\(start) – \(end) · 48 小時彙總",
            japanese: "\(start) – \(end) · 48時間の集計",
            english: "\(start) – \(end) · 48-hour summary"
        )
    }

    func hourlyWindowSubtitle() -> String {
        guard let selectedHourlyDate else {
            return hourlyLocalized(
                "过去 \(selectedHourlyRangeHours) 小时每小时 Token 用量与模型构成",
                traditionalChinese: "過去 \(selectedHourlyRangeHours) 小時每小時 Token 用量與模型構成",
                japanese: "過去\(selectedHourlyRangeHours)時間の時間別Token使用量とモデル構成",
                english: "Hourly Token usage and model mix over the last \(selectedHourlyRangeHours) hours"
            )
        }
        return hourlyLocalized(
            "\(hourlySelectedDateText(selectedHourlyDate)) 结束的 \(selectedHourlyRangeHours) 小时 Token 用量与模型构成",
            traditionalChinese: "\(hourlySelectedDateText(selectedHourlyDate)) 結束的 \(selectedHourlyRangeHours) 小時 Token 用量與模型構成",
            japanese: "\(hourlySelectedDateText(selectedHourlyDate)) までの\(selectedHourlyRangeHours)時間のToken使用量とモデル構成",
            english: "Hourly Token usage and model mix for the \(selectedHourlyRangeHours) hours ending \(hourlySelectedDateText(selectedHourlyDate))"
        )
    }

    func calendarHourHint() -> String {
        hourlyLocalized(
            "点击柱子选择，按住 Command 多选，或拖拽框选",
            traditionalChinese: "點擊柱狀選擇，按住 Command 多選，或拖曳框選",
            japanese: "クリックで選択、Commandで複数選択、ドラッグで範囲選択",
            english: "Click a bar to select, hold Command to multi-select, or drag across bars"
        )
    }

    func calendarHourModelTitle(hourCount: Int, total: Int64) -> String {
        let count = max(hourCount, 1)
        return hourlyLocalized(
            "模型 · 已选 \(count) 小时 · \(compact(total))",
            traditionalChinese: "模型 · 已選 \(count) 小時 · \(compact(total))",
            japanese: "モデル · \(count)時間選択 · \(compact(total))",
            english: "Models · \(count)h selected · \(compact(total))"
        )
    }

    var hourlyModelColors: [NSColor] {
        [
            accentRose,
            accentBlue,
            accentTeal,
            accentAmber,
            NSColor(calibratedRed: 0.57, green: 0.82, blue: 0.20, alpha: 1),
            NSColor(calibratedRed: 0.72, green: 0.48, blue: 1.00, alpha: 1),
            NSColor(calibratedRed: 1.00, green: 0.43, blue: 0.25, alpha: 1),
            NSColor(calibratedRed: 0.20, green: 0.72, blue: 0.95, alpha: 1),
            NSColor(calibratedRed: 0.90, green: 0.76, blue: 0.26, alpha: 1),
            NSColor(calibratedRed: 0.69, green: 0.68, blue: 0.72, alpha: 1)
        ]
    }

    func drawHourlyPage(snapshot: DetailsSnapshot, content: NSRect) {
        let allHours = continuousCalendarHours(snapshot: snapshot)
        let hours = displayedCalendarHours(snapshot: snapshot)
        let rangeSummary = aggregateCalendarHours(allHours)
        let chartRect = NSRect(x: content.minX, y: content.minY + 78, width: content.width, height: 350)
        drawPanel(chartRect)
        let dateControlsMinX = chartRect.maxX - 522
        let hideEmptyRect = NSRect(x: chartRect.maxX - 282, y: chartRect.minY + 15, width: 100, height: 24)
        drawText(
            hourlyLocalized("每小时 Token 活动", traditionalChinese: "每小時 Token 活動", japanese: "時間別Tokenアクティビティ", english: "Hourly Token activity"),
            rect: NSRect(x: chartRect.minX + 18, y: chartRect.minY + 16, width: max(110, dateControlsMinX - chartRect.minX - 30), height: 22),
            font: .systemFont(ofSize: 16, weight: .bold),
            color: .white
        )
        drawHideEmptyCalendarHoursButton(rect: hideEmptyRect)
        drawHourlyRangeSelector(rect: NSRect(x: chartRect.maxX - 134, y: chartRect.minY + 13, width: 116, height: 28))

        let modelOrder = rangeSummary.modelBreakdown.map(\.name)
        let colorByModel = Dictionary(uniqueKeysWithValues: modelOrder.enumerated().map { index, name in
            (name, hourlyModelColors[index % hourlyModelColors.count])
        })
        drawHourlyLegend(models: Array(modelOrder.prefix(8)), colors: colorByModel, rect: NSRect(x: chartRect.minX + 18, y: chartRect.minY + 56, width: chartRect.width - 36, height: 22))

        let plot = NSRect(x: chartRect.minX + 72, y: chartRect.minY + 90, width: chartRect.width - 96, height: 202)
        let maxTotal = max(hours.map { $0.usage.total }.max() ?? 1, 1)
        let baseline = plot.maxY
        for step in 0...4 {
            let ratio = CGFloat(step) / 4
            let y = baseline - plot.height * ratio
            NSColor.white.withAlphaComponent(step == 0 ? 0.13 : 0.055).setStroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: plot.minX, y: y))
            line.line(to: NSPoint(x: plot.maxX, y: y))
            line.lineWidth = 1
            line.stroke()
            let value = Int64(Double(maxTotal) * Double(ratio))
            drawRight(compact(value), rect: NSRect(x: chartRect.minX + 8, y: y - 7, width: 56, height: 14), color: NSColor.white.withAlphaComponent(0.34), font: .monospacedDigitSystemFont(ofSize: 9.5, weight: .medium))
        }

        let hourCount = max(hours.count, 1)
        let gap: CGFloat = hourCount > 24
            ? max(2, min(5, plot.width / 240))
            : max(4, min(9, plot.width / 120))
        let barWidth = max(4, (plot.width - gap * CGFloat(hourCount - 1)) / CGFloat(hourCount))
        calendarHourSelectionRect = plot
        for (index, hour) in hours.enumerated() {
            let x = plot.minX + CGFloat(index) * (barWidth + gap)
            let selected = selectedCalendarHours.contains(hour.hour)
            let alpha: CGFloat = selectedCalendarHours.isEmpty || selected ? 0.94 : 0.28
            var cursorY = baseline
            let modelsByName = Dictionary(uniqueKeysWithValues: hour.modelBreakdown.map { ($0.name, $0) })
            for modelName in modelOrder {
                guard let model = modelsByName[modelName], model.usage.total > 0 else { continue }
                let segmentHeight = plot.height * CGFloat(Double(model.usage.total) / Double(maxTotal))
                cursorY -= segmentHeight
                (colorByModel[modelName] ?? NSColor.systemGray).withAlphaComponent(alpha).setFill()
                NSRect(x: x, y: cursorY, width: barWidth, height: max(1, segmentHeight)).fill()
            }
            if hour.usage.total == 0 {
                NSColor.white.withAlphaComponent(0.09).setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: baseline - 2, width: barWidth, height: 2), xRadius: 1, yRadius: 1).fill()
            }
            let totalHeight = hour.usage.total > 0 ? max(2, plot.height * CGFloat(Double(hour.usage.total) / Double(maxTotal))) : 2
            let totalBar = NSRect(x: x, y: baseline - totalHeight, width: barWidth, height: totalHeight)
            if selected {
                NSColor.white.withAlphaComponent(0.90).setStroke()
                let outline = NSBezierPath(roundedRect: totalBar.insetBy(dx: -1.5, dy: -1.5), xRadius: 3, yRadius: 3)
                outline.lineWidth = 1.5
                outline.stroke()
            }
            calendarHourRects[hour.hour] = NSRect(x: x - gap / 2, y: plot.minY, width: barWidth + gap, height: plot.height)
            calendarHourBarRects[hour.hour] = totalBar
        }

        drawHourlyAxisLabels(hours: hours, plot: plot, barWidth: barWidth, gap: gap)
        drawText(calendarHourHint(), rect: NSRect(x: plot.minX, y: chartRect.maxY - 28, width: plot.width, height: 16), font: .systemFont(ofSize: 10.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.40))
        drawHourlyMarquee()
        if isHourlyDateLoading {
            NSColor.black.withAlphaComponent(0.24).setFill()
            NSBezierPath(roundedRect: plot, xRadius: 8, yRadius: 8).fill()
            drawCentered(
                hourlyLocalized("正在加载小时数据…", traditionalChinese: "正在載入小時數據…", japanese: "時間別データを読み込み中…", english: "Loading hourly data…"),
                rect: NSRect(x: plot.minX, y: plot.midY - 10, width: plot.width, height: 20),
                font: .systemFont(ofSize: 13, weight: .semibold),
                color: NSColor.white.withAlphaComponent(0.82)
            )
        }

        let summaryRect = NSRect(x: content.minX, y: chartRect.maxY + 16, width: content.width, height: max(190, content.maxY - chartRect.maxY - 16))
        drawHourlySelectionDetails(snapshot: snapshot, rect: summaryRect)
    }

    func drawHideEmptyCalendarHoursButton(rect: NSRect) {
        hideEmptyCalendarHoursRect = rect
        let title = hourlyLocalized(
            "隐藏空白小时",
            traditionalChinese: "隱藏空白小時",
            japanese: "空白時間を隠す",
            english: "Hide empty"
        )
        drawRight(
            title,
            rect: rect,
            color: NSColor.white.withAlphaComponent(0.72),
            font: .systemFont(ofSize: 11, weight: .semibold)
        )
    }

    func drawHourlyRangeSelector(rect: NSRect) {
        let options = [24, 48]
        let gap: CGFloat = 6
        let width = (rect.width - gap) / 2
        for (index, hours) in options.enumerated() {
            let optionRect = NSRect(x: rect.minX + CGFloat(index) * (width + gap), y: rect.minY, width: width, height: rect.height)
            hourlyRangeRects[hours] = optionRect
            drawSelectablePill("\(hours)h", rect: optionRect, selected: selectedHourlyRangeHours == hours)
        }
    }

    func drawHourlyLegend(models: [String], colors: [String: NSColor], rect: NSRect) {
        var x = rect.minX
        for model in models {
            let font = NSFont.systemFont(ofSize: 10, weight: .semibold)
            let width = min(150, measuredTextWidth(model, font: font) + 24)
            guard x + width <= rect.maxX else { break }
            (colors[model] ?? .systemGray).setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: rect.minY + 6, width: 8, height: 8)).fill()
            drawText(model, rect: NSRect(x: x + 13, y: rect.minY + 2, width: width - 13, height: 16), font: font, color: NSColor.white.withAlphaComponent(0.66))
            x += width + 10
        }
    }

    func drawHourlyAxisLabels(hours: [HourUsage], plot: NSRect, barWidth: CGFloat, gap: CGFloat) {
        let formatter = DateFormatter()
        formatter.calendar = appCalendar()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let isExtended = selectedHourlyRangeHours > 24
        formatter.dateFormat = isExtended ? "M/d HH:00" : "HH:00"
        let strideSize = max(1, Int(ceil(Double(hours.count) / 8.0)))
        var indexes = Set(Swift.stride(from: 0, to: hours.count, by: strideSize))
        if !hours.isEmpty { indexes.insert(hours.count - 1) }
        for index in indexes.sorted() where hours.indices.contains(index) {
            let centerX = plot.minX + CGFloat(index) * (barWidth + gap) + barWidth / 2
            let labelWidth: CGFloat = isExtended ? 76 : 50
            drawCentered(formatter.string(from: hours[index].hour), rect: NSRect(x: centerX - labelWidth / 2, y: plot.maxY + 8, width: labelWidth, height: 14), font: .monospacedDigitSystemFont(ofSize: 9, weight: .semibold), color: NSColor.white.withAlphaComponent(0.38))
        }
    }

    func drawHourlyMarquee() {
        guard let marquee = calendarHourMarqueeRect else { return }
        accentTeal.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: marquee, xRadius: 4, yRadius: 4).fill()
        accentTeal.withAlphaComponent(0.76).setStroke()
        let outline = NSBezierPath(roundedRect: marquee.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        outline.lineWidth = 1
        outline.stroke()
    }

    func drawHourlySelectionDetails(snapshot: DetailsSnapshot, rect: NSRect) {
        drawPanel(rect)
        let summary = hourlyDisplayedSummary(snapshot: snapshot)
        let selectionCount = selectedCalendarHours.count
        let title = selectionCount > 0
            ? calendarHourModelTitle(hourCount: selectionCount, total: summary.usage.total)
            : hourlyWindowSummaryTitle()
        drawText(title, rect: NSRect(x: rect.minX + 18, y: rect.minY + 16, width: rect.width - 36, height: 22), font: .systemFont(ofSize: 15, weight: .bold), color: .white)

        var costReport = TokenReport()
        costReport.usage = summary.usage
        costReport.modelBreakdown = summary.modelBreakdown
        let apiEstimate = APICostEstimator.estimate(report: costReport)
        let cards: [(String, String, NSColor)] = [
            (t(.total), compact(summary.usage.total), .white),
            (t(.input), compact(summary.usage.input), .systemGreen),
            (t(.output), compact(summary.usage.output), .systemCyan),
            (t(.cached), compact(summary.usage.cachedInput), .systemTeal),
            (t(.apiEquivalent), apiEstimate.hasPricedUsage ? compactDisplayAPIMoney(apiEstimate.usdValue) : "—", accentTeal)
        ]
        let gap: CGFloat = 10
        let cardWidth = (rect.width - 36 - gap * CGFloat(cards.count - 1)) / CGFloat(cards.count)
        for (index, card) in cards.enumerated() {
            let cardRect = NSRect(x: rect.minX + 18 + CGFloat(index) * (cardWidth + gap), y: rect.minY + 48, width: cardWidth, height: 58)
            NSColor.black.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: cardRect, xRadius: 7, yRadius: 7).fill()
            drawText(card.0, rect: NSRect(x: cardRect.minX + 11, y: cardRect.minY + 9, width: cardRect.width - 22, height: 14), font: .systemFont(ofSize: 10.5, weight: .semibold), color: NSColor.white.withAlphaComponent(0.44))
            drawText(card.1, rect: NSRect(x: cardRect.minX + 11, y: cardRect.minY + 28, width: cardRect.width - 22, height: 20), font: .monospacedDigitSystemFont(ofSize: 14, weight: .bold), color: card.2)
        }

        let modelRect = NSRect(x: rect.minX + 18, y: rect.minY + 124, width: rect.width - 36, height: max(58, rect.height - 142))
        drawSelectedDayModels(
            summary.modelBreakdown,
            showsSessions: selectionCount == 1,
            title: t(.models),
            rect: modelRect
        )
    }
}
