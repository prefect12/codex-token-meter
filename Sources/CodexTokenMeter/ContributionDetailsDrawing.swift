import Cocoa

extension UsageDetailsView {
    func drawAboutPage(content: NSRect) {
        let rect = NSRect(x: content.minX, y: content.minY + 78, width: content.width, height: 208)
        drawPanel(rect)
        drawText(t(.definitions), rect: NSRect(x: rect.minX + 16, y: rect.minY + 16, width: rect.width - 32, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        let rows = [
            (t(.all), t(.allDescription)),
            (t(.codex), t(.codexDescription)),
            (t(.claude), t(.claudeDescription)),
            (t(.cacheHit), t(.cacheHitDescription))
        ]
        for (index, row) in rows.enumerated() {
            let y = rect.minY + 52 + CGFloat(index) * 38
            drawText(row.0, rect: NSRect(x: rect.minX + 16, y: y, width: 92, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
            drawText(row.1, rect: NSRect(x: rect.minX + 116, y: y, width: rect.width - 132, height: 20), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.56))
        }

        let sourceRect = NSRect(x: content.minX, y: rect.maxY + 16, width: content.width, height: 196)
        drawPanel(sourceRect)
        drawText(t(.dataSource), rect: NSRect(x: sourceRect.minX + 16, y: sourceRect.minY + 16, width: sourceRect.width - 32, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        drawText(t(.dataSourceLine1), rect: NSRect(x: sourceRect.minX + 16, y: sourceRect.minY + 52, width: sourceRect.width - 32, height: 20), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.58))
        drawMultilineText(t(.dataSourceLine2), rect: NSRect(x: sourceRect.minX + 16, y: sourceRect.minY + 80, width: sourceRect.width - 32, height: 104), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.6))
    }

    /// Pads sparse "past year" day data to a full 53-week range ending at the
    /// current calendar week's last slot, so the grid keeps fixed weekday rows
    /// while future dates stay blank.
    func paddedContributionDays(_ days: [DayUsage]) -> [DayUsage] {
        let totalDays = 53 * 7
        let formatter = dayFormatter()
        let calendar = appCalendar()
        let today = calendar.startOfDay(for: Date())
        let windowEnd = contributionWeekEnd(for: today, calendar: calendar)
        guard let windowStart = calendar.date(byAdding: .day, value: -(totalDays - 1), to: windowEnd) else {
            return days
        }
        var byKey: [String: DayUsage] = [:]
        for day in days {
            guard let date = formatter.date(from: day.day),
                  date >= windowStart,
                  date <= windowEnd else { continue }
            byKey[day.day] = day
        }
        var padded: [DayUsage] = []
        padded.reserveCapacity(totalDays)
        for offset in stride(from: totalDays - 1, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: windowEnd) else { continue }
            let key = formatter.string(from: date)
            padded.append(byKey[key] ?? DayUsage(day: key, usage: Usage(), turns: 0))
        }
        return padded
    }

    func contributionWeekEnd(for date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: day)?.start,
              let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
            return day
        }
        return weekEnd
    }

    func isFutureContributionDay(_ day: String, formatter: DateFormatter, calendar: Calendar, today: Date) -> Bool {
        guard let date = formatter.date(from: day) else { return false }
        return calendar.compare(date, to: today, toGranularity: .day) == .orderedDescending
    }

    /// Aggregates the padded contribution days into the same 7-day columns the
    /// grid renders, so week selection maps 1:1 to what the user clicked.
    func contributionWeekColumns(in report: TokenReport) -> [ContributionWeekSummary] {
        let days = paddedContributionDays(report.byDay)
        guard !days.isEmpty else { return [] }
        let formatter = dayFormatter()
        let calendar = appCalendar()
        let today = calendar.startOfDay(for: Date())
        var result: [ContributionWeekSummary] = []
        var index = 0
        while index < days.count {
            let slice = Array(days[index..<min(index + 7, days.count)])
            let visibleDays = slice.filter { !isFutureContributionDay($0.day, formatter: formatter, calendar: calendar, today: today) }
            guard !visibleDays.isEmpty else {
                index += 7
                continue
            }
            var usage = Usage()
            var turns = 0
            var activeDays = 0
            var total: Int64 = 0
            for day in visibleDays {
                usage.add(day.usage)
                turns += day.turns
                total += day.usage.total
                if day.usage.total > 0 {
                    activeDays += 1
                }
            }
            result.append(ContributionWeekSummary(
                key: visibleDays.first?.day ?? "",
                startDay: visibleDays.first?.day ?? "",
                endDay: visibleDays.last?.day ?? "",
                usage: usage,
                total: total,
                activeDays: activeDays,
                turns: turns,
                days: visibleDays,
                hitRect: .zero,
                cellRects: []
            ))
            index += 7
        }
        return result
    }

    func selectedCalendarRangeSummary() -> ContributionWeekSummary? {
        guard let snapshot, selectedContributionDays.count > 1 else { return nil }
        let report = calendarReport(for: snapshot)
        let selected = paddedContributionDays(report.byDay)
            .filter { selectedContributionDays.contains($0.day) }
            .sorted { $0.day < $1.day }
        guard let first = selected.first, let last = selected.last else { return nil }

        var usage = Usage()
        var turns = 0
        var activeDays = 0
        for day in selected {
            usage.add(day.usage)
            turns += day.turns
            if day.usage.total > 0 {
                activeDays += 1
            }
        }
        return ContributionWeekSummary(
            key: first.day,
            startDay: first.day,
            endDay: last.day,
            usage: usage,
            total: usage.total,
            activeDays: activeDays,
            turns: turns,
            days: selected,
            hitRect: .zero,
            cellRects: []
        )
    }

    func isContributionWeekFullySelected(_ summary: ContributionWeekSummary) -> Bool {
        guard selectedContributionDays.count > 1, !summary.days.isEmpty else { return false }
        return summary.days.allSatisfy { selectedContributionDays.contains($0.day) }
    }

    func drawContributionGrid(report: TokenReport, rect: NSRect, title: String, compact: Bool) {
        drawPanel(rect)
        drawText(title, rect: NSRect(x: rect.minX + 16, y: rect.minY + 12, width: rect.width - 32, height: 20), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
        guard !report.byDay.isEmpty else {
            drawText(t(.noDailyTokenData), rect: NSRect(x: rect.minX + 16, y: rect.minY + 52, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }
        let days = paddedContributionDays(report.byDay)

        let maxTotal = max(days.map { $0.usage.total }.max() ?? 1, 1)
        let formatter = dayFormatter()
        let calendar = appCalendar()
        let today = calendar.startOfDay(for: Date())
        let useCalendarGrid = !compact || days.count > 90
        let enableDayHover = selectedSection == .overview && compact
        let enableWeekSelection = selectedSection == .calendar && !compact && useCalendarGrid
        let columns = useCalendarGrid ? Int(ceil(Double(days.count) / 7.0)) : min(days.count, 15)
        let rows = useCalendarGrid ? 7 : Int(ceil(Double(days.count) / Double(max(columns, 1))))
        let gap: CGFloat = useCalendarGrid ? (compact ? 2 : 3) : 6
        let left: CGFloat = compact ? 18 : 26
        let right: CGFloat = compact ? 18 : 26
        let top: CGFloat = compact ? 42 : 58
        let bottom: CGFloat = compact ? 44 : 50
        let availableW = max(40, rect.width - left - right)
        let availableH = max(40, rect.height - top - bottom)
        let square = min(
            compact ? 16 : 18,
            floor(min((availableW - gap * CGFloat(max(columns - 1, 0))) / CGFloat(max(columns, 1)), (availableH - gap * CGFloat(max(rows - 1, 0))) / CGFloat(max(rows, 1))))
        )
        let gridH = CGFloat(rows) * square + CGFloat(max(rows - 1, 0)) * gap
        let startX = rect.minX + left
        let startY = rect.minY + top
        if enableWeekSelection {
            contributionGridSelectionRect = NSRect(
                x: startX - gap / 2,
                y: startY - 24,
                width: CGFloat(columns) * square + CGFloat(max(columns - 1, 0)) * gap + gap,
                height: gridH + 24 + gap / 2
            )
        }
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
            let isFuture = isFutureContributionDay(day.day, formatter: formatter, calendar: calendar, today: today)
            guard !isFuture else { continue }
            let cell = NSRect(x: startX + CGFloat(col) * (square + gap), y: startY + CGFloat(row) * (square + gap), width: square, height: square)
            cells.append((day: day, rect: cell, column: col))
            if enableWeekSelection || day.usage.total > 0 || day.turns > 0 {
                contributionDayRects[day.day] = cell
                if enableDayHover {
                    contributionDaySummaries[day.day] = ContributionDaySummary(day: day, hitRect: cell)
                }
            }
            if enableWeekSelection {
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

        if enableWeekSelection {
            var summaries: [String: ContributionWeekSummary] = [:]
            for column in 0..<columns {
                guard let rects = weekCells[column], !rects.isEmpty,
                      (weekTotals[column] ?? 0) > 0 else { continue }
                let key = weekStartDays[column] ?? ""
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
            for summary in summaries.values where isContributionWeekFullySelected(summary) {
                drawContributionWeekHighlight(summary, emphasized: true)
            }
            for (key, summary) in summaries {
                let center = CGPoint(x: summary.hitRect.midX, y: startY - 11)
                let isSelected = isContributionWeekFullySelected(summary)
                let isPartiallySelected = summary.days.contains { selectedContributionDays.contains($0.day) }
                let radius: CGFloat = isSelected ? 3.5 : 3
                let dotRect = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                if isSelected {
                    accentTeal.setFill()
                } else if isPartiallySelected {
                    accentTeal.withAlphaComponent(0.58).setFill()
                } else {
                    NSColor.white.withAlphaComponent(0.32).setFill()
                }
                NSBezierPath(ovalIn: dotRect).fill()
                if isSelected {
                    accentTeal.withAlphaComponent(0.40).setStroke()
                    let ring = NSBezierPath(ovalIn: dotRect.insetBy(dx: -2.5, dy: -2.5))
                    ring.lineWidth = 1.5
                    ring.stroke()
                }
                contributionWeekDotRects[key] = NSRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)
            }
            updateContributionWeekHoverOverlay()
        }

        for cellData in cells {
            let day = cellData.day
            let cell = cellData.rect
            let intensity = Double(day.usage.total) / Double(maxTotal)
            contributionColor(intensity).setFill()
            NSBezierPath(roundedRect: cell, xRadius: 3, yRadius: 3).fill()
            if selectedContributionDays.count > 1 && selectedContributionDays.contains(day.day) {
                accentTeal.withAlphaComponent(0.24).setFill()
                NSBezierPath(roundedRect: cell.insetBy(dx: 1, dy: 1), xRadius: 2.5, yRadius: 2.5).fill()
            } else if selectedContributionDays.count <= 1 && day.day == selectedDay {
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

        if enableWeekSelection, let marquee = contributionMarqueeRect {
            accentTeal.withAlphaComponent(0.10).setFill()
            NSBezierPath(roundedRect: marquee, xRadius: 5, yRadius: 5).fill()
            accentTeal.withAlphaComponent(0.86).setStroke()
            let path = NSBezierPath(roundedRect: marquee.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
            path.lineWidth = 1
            path.stroke()
        }

        let labelY = min(startY + gridH + 10, rect.maxY - 38)
        let hintY = min(labelY + 18, rect.maxY - 20)
        drawContributionMonthLabels(days: days, useCalendarGrid: useCalendarGrid, columns: columns, square: square, gap: gap, startX: startX, y: labelY, compact: compact)
        drawText(t(.usageIntensityHint), rect: NSRect(x: startX, y: hintY, width: max(0, rect.maxX - startX - right), height: 16), font: .systemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.42))
        if enableDayHover,
           let hoveredContributionDay,
           let summary = contributionDaySummaries[hoveredContributionDay] {
            drawContributionDayTooltip(summary, container: rect)
        }
    }

    func drawContributionDayTooltip(_ summary: ContributionDaySummary, container: NSRect) {
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
            (contributionPlanAmountLabel(), planValue.map { displayMoney($0, source: selectedDetailsSource) } ?? "--"),
            (contributionAPIAmountLabel(), apiEstimate.hasPricedUsage ? displayAPIMoney(apiEstimate.usdValue, source: selectedDetailsSource) : "--")
        ]
        drawText(localizedContributionDate(day.day), rect: NSRect(x: tooltipRect.minX + 10, y: tooltipRect.minY + 8, width: tooltipRect.width - 20, height: 14), font: .systemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.82))
        for (index, row) in rows.enumerated() {
            let y = tooltipRect.minY + 27 + CGFloat(index) * 16
            drawText(row.0, rect: NSRect(x: tooltipRect.minX + 10, y: y, width: 84, height: 14), font: .systemFont(ofSize: 10, weight: .medium), color: NSColor.white.withAlphaComponent(0.52))
            drawRight(row.1, rect: NSRect(x: tooltipRect.minX + 92, y: y - 1, width: tooltipRect.width - 102, height: 15), color: NSColor.white.withAlphaComponent(0.86), font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold))
        }
        drawText(t(.clickForDetails), rect: NSRect(x: tooltipRect.minX + 10, y: tooltipRect.maxY - 18, width: tooltipRect.width - 20, height: 13), font: .systemFont(ofSize: 9, weight: .medium), color: accentTeal.withAlphaComponent(0.74))
    }

    func contributionDayPlanValue(_ day: DayUsage) -> Double? {
        guard let snapshot else { return nil }
        let report = calendarReport(for: snapshot)
        let reportDay = report.byDay.first { $0.day == day.day } ?? day
        return planCostEstimate(
            report: report,
            selectedDay: reportDay,
            limit: sourceCostLimit(for: snapshot),
            quotaReferenceReport: sourceCostReferenceReport(for: snapshot),
            monthlyCost: AppSettings.monthlyPlanCost(for: selectedDetailsSource),
            paymentStartDay: AppSettings.paymentStartDay(for: selectedDetailsSource)
        )?.selectedDayValue
    }

    func contributionDayAPIEstimate(_ day: DayUsage) -> APICostEstimate {
        guard let snapshot, usesProfileAPIReport(for: snapshot) else {
            return APICostEstimator.estimate(day: day)
        }
        let localDay = snapshot.codex.byDay.first { $0.day == day.day }
        return profileAPIDayEstimate(profileDay: day, localDay: localDay)
    }

    func contributionPlanAmountLabel() -> String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese:
            return "对应金额"
        case .japanese:
            return "対応金額"
        default:
            return "Plan value"
        }
    }

    func contributionAPIAmountLabel() -> String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese:
            return "API 金额"
        case .japanese:
            return "API 金額"
        default:
            return "API cost"
        }
    }

    func drawContributionWeekHighlight(_ summary: ContributionWeekSummary, emphasized: Bool) {
        let rect = summary.hitRect.insetBy(dx: -4, dy: -4)
        accentTeal.withAlphaComponent(emphasized ? 0.14 : 0.08).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        accentTeal.withAlphaComponent(emphasized ? 0.70 : 0.40).setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        border.lineWidth = emphasized ? 1.5 : 1
        border.stroke()
    }

    func contributionWeekRangeLabel(_ summary: ContributionWeekSummary) -> String {
        let range: String
        if let start = dayFormatter().date(from: summary.startDay),
           let end = dayFormatter().date(from: summary.endDay) {
            let calendar = appCalendar()
            let sameYear = calendar.component(.year, from: start) == calendar.component(.year, from: end)
            switch AppLanguage.current {
            case .chinese, .traditionalChinese:
                let year = calendar.component(.year, from: start)
                let startMonth = calendar.component(.month, from: start)
                let startDay = calendar.component(.day, from: start)
                let endMonth = calendar.component(.month, from: end)
                let endDay = calendar.component(.day, from: end)
                range = sameYear
                    ? "\(year)年\(startMonth)月\(startDay)日 - \(endMonth)月\(endDay)日"
                    : "\(localizedContributionDate(summary.startDay)) - \(localizedContributionDate(summary.endDay))"
            case .japanese:
                let year = calendar.component(.year, from: start)
                let startMonth = calendar.component(.month, from: start)
                let startDay = calendar.component(.day, from: start)
                let endMonth = calendar.component(.month, from: end)
                let endDay = calendar.component(.day, from: end)
                range = sameYear
                    ? "\(year)年\(startMonth)月\(startDay)日 - \(endMonth)月\(endDay)日"
                    : "\(localizedContributionDate(summary.startDay)) - \(localizedContributionDate(summary.endDay))"
            default:
                let formatter = DateFormatter()
                formatter.timeZone = appTimeZone()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "MMM d"
                range = sameYear
                    ? "\(formatter.string(from: start)) - \(formatter.string(from: end)), \(calendar.component(.year, from: start))"
                    : "\(localizedContributionDate(summary.startDay)) - \(localizedContributionDate(summary.endDay))"
            }
        } else {
            range = "\(summary.startDay) - \(summary.endDay)"
        }
        guard !isSingleCalendarWeek(summary) else { return range }
        let suffix: String
        switch AppLanguage.current {
        case .chinese, .traditionalChinese:
            suffix = "\(summary.days.count) 天"
        case .japanese:
            suffix = "\(summary.days.count)日"
        default:
            suffix = "\(summary.days.count) days"
        }
        return "\(range) · \(suffix)"
    }

    func isSingleCalendarWeek(_ summary: ContributionWeekSummary) -> Bool {
        guard summary.days.count == 7,
              let start = dayFormatter().date(from: summary.startDay),
              let end = dayFormatter().date(from: summary.endDay),
              let interval = appCalendar().dateInterval(of: .weekOfYear, for: start) else {
            return false
        }
        return appCalendar().isDate(start, inSameDayAs: interval.start)
            && appCalendar().dateComponents([.day], from: start, to: end).day == 6
    }

    enum ContributionWeekMetric {
        case tokens
        case activeDays
        case average
        case inputOutput
        case cache
        case turns
    }

    func contributionWeekLabel(_ metric: ContributionWeekMetric) -> String {
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

    func contributionWeekPlanValue(_ summary: ContributionWeekSummary) -> Double? {
        guard let snapshot,
              !summary.days.isEmpty else {
            return nil
        }
        let report = calendarReport(for: snapshot)
        guard let estimator = CostEstimator(
            report: report,
            limit: sourceCostLimit(for: snapshot),
            quotaReferenceReport: sourceCostReferenceReport(for: snapshot),
            monthlyCost: AppSettings.monthlyPlanCost(for: selectedDetailsSource),
            paymentStartDay: AppSettings.paymentStartDay(for: selectedDetailsSource)
        ) else {
            return nil
        }
        var totalsByWeek: [Date: Int64] = [:]
        for day in summary.days {
            guard let date = dayFormatter().date(from: day.day),
                  let weekStart = appCalendar().dateInterval(of: .weekOfYear, for: date)?.start else {
                continue
            }
            totalsByWeek[weekStart, default: 0] += day.usage.total
        }
        guard !totalsByWeek.isEmpty else { return nil }
        return totalsByWeek.reduce(0) { partial, entry in
            partial + estimator.weeklyUsedValue(forWeekStart: entry.key, total: entry.value)
        }
    }

    func contributionWeekAPIEstimate(_ summary: ContributionWeekSummary) -> APICostEstimate {
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

    func localizedContributionDate(_ day: String) -> String {
        guard let date = dayFormatter().date(from: day) else { return day }
        let formatter = DateFormatter()
        formatter.timeZone = appTimeZone()
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

    func contributionGridPreferredHeight(report: TokenReport, width: CGFloat, compact: Bool) -> CGFloat {
        guard !report.byDay.isEmpty else {
            return compact ? 112 : 128
        }
        let days = paddedContributionDays(report.byDay)
        let useCalendarGrid = !compact || days.count > 90
        let columns = useCalendarGrid ? Int(ceil(Double(days.count) / 7.0)) : min(days.count, 15)
        let rows = useCalendarGrid ? 7 : Int(ceil(Double(days.count) / Double(max(columns, 1))))
        let gap: CGFloat = useCalendarGrid ? (compact ? 2 : 3) : 6
        let left: CGFloat = compact ? 18 : 26
        let right: CGFloat = compact ? 18 : 26
        let top: CGFloat = compact ? 42 : 58
        let availableW = max(40, width - left - right)
        let square = min(
            compact ? 16 : 18,
            floor((availableW - gap * CGFloat(max(columns - 1, 0))) / CGFloat(max(columns, 1)))
        )
        let gridH = CGFloat(rows) * max(6, square) + CGFloat(max(rows - 1, 0)) * gap
        let labelAndHintHeight: CGFloat = compact ? 48 : 54
        return ceil(top + gridH + labelAndHintHeight)
    }

    func drawContributionMonthLabels(days: [DayUsage], useCalendarGrid: Bool, columns: Int, square: CGFloat, gap: CGFloat, startX: CGFloat, y: CGFloat, compact: Bool) {
        var lastMonth: String?
        var lastLabelX = -CGFloat.greatestFiniteMagnitude
        let minimumGap: CGFloat = compact ? 42 : 50
        let formatter = dayFormatter()
        let calendar = appCalendar()
        let today = calendar.startOfDay(for: Date())
        for (index, day) in days.enumerated() {
            guard !isFutureContributionDay(day.day, formatter: formatter, calendar: calendar, today: today) else { continue }
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

    func contributionMonthLabel(for day: String) -> String {
        guard let date = dayFormatter().date(from: day) else {
            return String(day.dropFirst(5).prefix(2))
        }
        let formatter = DateFormatter()
        formatter.timeZone = appTimeZone()
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

    // MARK: - Storage page

}
