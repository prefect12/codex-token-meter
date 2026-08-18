import Cocoa

extension UsageDetailsView {
    func drawCalendarPage(snapshot: DetailsSnapshot, content: NSRect) {
        let report = calendarReport(for: snapshot)
        let useProfilePanel = usesProfileAPIReport(for: snapshot)
            && !profileSelectedDayUsesLocalFallback(snapshot: snapshot, report: report)
        let title = useProfilePanel
            ? "\(t(.tokenActivity)) · \(t(.profileAPISource))"
            : t(.tokenActivity)
        let preferredGridHeight = contributionGridPreferredHeight(report: report, width: content.width, compact: false)
        let gridHeight = min(preferredGridHeight, max(224, content.height * 0.36))
        let gridRect = NSRect(x: content.minX, y: content.minY + 78, width: content.width, height: gridHeight)
        drawContributionGrid(report: report, rect: gridRect, title: title, compact: false)

        let weekSummary = selectedCalendarRangeSummary()
        let available = max(248, content.maxY - gridRect.maxY - 16)
        let preferredHeight = weekSummary != nil
            ? selectedWeekPanelPreferredHeight(contentWidth: content.width)
            : selectedDayPanelPreferredHeight(contentWidth: content.width)
        let detailRect = NSRect(x: content.minX, y: gridRect.maxY + 16, width: content.width, height: min(preferredHeight, available))
        if let weekSummary {
            drawSelectedWeekPanel(snapshot: snapshot, report: report, summary: weekSummary, rect: detailRect)
        } else if useProfilePanel {
            drawProfileSelectedDayPanel(snapshot: snapshot, report: report, rect: detailRect)
        } else {
            drawSelectedDayPanel(snapshot: snapshot, rect: detailRect)
        }
    }

    func reportCostSignature(_ report: TokenReport?) -> String {
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

    func cachedAvailableCostYears(from report: TokenReport?, source: QuotaViewOption) -> [Int] {
        let key = [
            reportCostSignature(report),
            source.rawValue,
            AppSettings.paymentStartDay(for: source) ?? "",
            todayKey()
        ].joined(separator: "|")
        if costYearOptionsCacheKey == key {
            return costYearOptionsCache
        }
        let years = availableCostYears(from: report, paymentStartDay: AppSettings.paymentStartDay(for: source))
        costYearOptionsCacheKey = key
        costYearOptionsCache = years
        return years
    }

    func costPageDataKey(snapshot: DetailsSnapshot, limit: LiveRateLimit?, year: Int) -> String {
        let weekly = limit?.secondary
        let report = sourceReport(for: snapshot)
        let referenceReport = sourceCostReferenceReport(for: snapshot)
        let costSource = selectedDetailsSource
        return [
            costSource.rawValue,
            reportCostSignature(report),
            "\(year)",
            AppLanguage.current.rawValue,
            String(format: "%.4f", AppSettings.monthlyPlanCost(for: costSource)),
            AppSettings.paymentStartDay(for: costSource) ?? "",
            AppSettings.paymentCurrency(for: costSource).rawValue,
            AppSettings.displayCurrency(for: costSource).rawValue,
            AppSettings.showHistoricalEmptyWeeks ? "1" : "0",
            String(format: "%.4f", weekly?.usedPercent ?? -1),
            String(format: "%.4f", weekly?.remainingPercent ?? -1),
            "\(weekly?.windowMinutes ?? 0)",
            "\(referenceReport?.usage.total ?? -1)",
            String(format: "%.3f", referenceReport?.scannedAt.timeIntervalSince1970 ?? -1),
            todayKey()
        ].joined(separator: "|")
    }

    func costPageData(for snapshot: DetailsSnapshot, limit: LiveRateLimit?, year: Int) -> CostPageData {
        let key = costPageDataKey(snapshot: snapshot, limit: limit, year: year)
        if let cached = costPageDataCache, cached.key == key {
            return cached
        }
        let report = sourceReport(for: snapshot)
        let referenceReport = sourceCostReferenceReport(for: snapshot)
        let costSource = selectedDetailsSource
        let monthlyCost = AppSettings.monthlyPlanCost(for: costSource)
        let paymentStartDay = AppSettings.paymentStartDay(for: costSource)
        let data = CostPageData(
            key: key,
            estimate: planCostEstimate(report: report, selectedDay: nil, limit: limit, quotaReferenceReport: referenceReport, monthlyCost: monthlyCost, paymentStartDay: paymentStartDay),
            apiEstimate: APICostEstimator.estimate(report: report),
            weeklyRows: weeklySpendRows(report: report, limit: limit, year: year, quotaReferenceReport: referenceReport, monthlyCost: monthlyCost, paymentStartDay: paymentStartDay),
            monthlyRows: monthlySpendRows(report: report, limit: limit, year: year, quotaReferenceReport: referenceReport, monthlyCost: monthlyCost, paymentStartDay: paymentStartDay)
        )
        costPageDataCache = data
        return data
    }

    func drawCostOverviewPanel(estimate: PlanCostEstimate?, apiEstimate: APICostEstimate, source: QuotaViewOption, rect: NSRect) {
        drawPanel(rect)
        let externalAPI = ExternalAPICostStore.read()
        guard let estimate else {
            if apiEstimate.hasUsage {
                drawText(t(.apiEquivalent), rect: NSRect(x: rect.minX + 18, y: rect.minY + 20, width: rect.width - 36, height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(0.56))
                drawText(displayAPIMoney(apiEstimate.usdValue, source: source), rect: NSRect(x: rect.minX + 18, y: rect.minY + 48, width: rect.width - 36, height: 34), font: .monospacedDigitSystemFont(ofSize: 26, weight: .bold), color: accentTeal)
                drawText(t(.apiEquivalentHint), rect: NSRect(x: rect.minX + 18, y: rect.minY + 92, width: rect.width - 36, height: 18), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.48))
                let unavailableY: CGFloat = externalAPI?.hasData == true ? 138 : 124
                if let externalAPI, externalAPI.hasData {
                    drawCostOverviewRow(title: t(.externalAPICost), value: displayAPIMoney(externalAPI.usdValue, source: source), color: accentAmber, rect: NSRect(x: rect.minX + 18, y: rect.minY + 116, width: rect.width - 36, height: 20), info: .externalAPI)
                }
                drawText(t(.planCostUnavailable), rect: NSRect(x: rect.minX + 18, y: rect.minY + unavailableY, width: rect.width - 36, height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(0.42))
                return
            }
            if let externalAPI, externalAPI.hasData {
                drawText(t(.externalAPICost), rect: NSRect(x: rect.minX + 18, y: rect.minY + 20, width: rect.width - 36, height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(0.56))
                drawText(displayAPIMoney(externalAPI.usdValue, source: source), rect: NSRect(x: rect.minX + 18, y: rect.minY + 48, width: rect.width - 36, height: 34), font: .monospacedDigitSystemFont(ofSize: 26, weight: .bold), color: accentAmber)
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
        drawText(displayMoney(estimate.weeklyUsedValue, source: source), rect: NSRect(x: leftRect.minX, y: leftRect.minY + 26, width: leftRect.width - 92, height: 34), font: .monospacedDigitSystemFont(ofSize: 26, weight: .bold), color: usedColor)
        drawRight(String(format: "%.0f%%", usageRate * 100), rect: NSRect(x: leftRect.maxX - 86, y: leftRect.minY + 31, width: 86, height: 24), color: NSColor.white.withAlphaComponent(0.82), font: .monospacedDigitSystemFont(ofSize: 17, weight: .bold))

        let progressRect = NSRect(x: leftRect.minX, y: leftRect.minY + 74, width: leftRect.width, height: 10)
        costRemainingMutedColor.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: progressRect, xRadius: 5, yRadius: 5).fill()
        usedColor.setFill()
        let usedProgressWidth = clampedRate > 0 ? max(6, progressRect.width * CGFloat(clampedRate)) : 0
        if usedProgressWidth > 0 {
            NSBezierPath(roundedRect: NSRect(x: progressRect.minX, y: progressRect.minY, width: usedProgressWidth, height: progressRect.height), xRadius: 5, yRadius: 5).fill()
        }

        let budgetLine = "\(t(.weeklyUnusedValue)) \(displayMoney(estimate.weeklyUnusedValue, source: source))  /  \(t(.weeklyBudget)) \(displayMoney(estimate.weeklyBudget, source: source))"
        drawText(budgetLine, rect: NSRect(x: leftRect.minX, y: leftRect.minY + 96, width: leftRect.width, height: 18), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.52))

        let planLine = "\(t(.paymentMonthly)) \(paymentMoney(estimate.monthlyCost, source: source))  ·  \(t(.displayEquivalent)) \(displayMoney(estimate.monthlyCost, source: source))"
        drawText(planLine, rect: NSRect(x: rightRect.minX, y: rightRect.minY, width: rightRect.width, height: 18), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.54))
        var summaryRows: [(String, String, NSColor, CostOverviewInfo)] = [
            (t(.usageRate), String(format: "%.0f%%", usageRate * 100), usedColor, .usageRate),
            (t(.totalSpendValue), displayMoney(estimate.totalSpentValue, source: source), accentAmber, .totalSpend),
            (t(.apiEquivalent), displayAPIMoney(apiEstimate.usdValue, source: source), accentTeal, .apiEquivalent)
        ]
        if let externalAPI, externalAPI.hasData {
            summaryRows.append((t(.externalAPICost), displayAPIMoney(externalAPI.usdValue, source: source), accentAmber, .externalAPI))
        }
        summaryRows.append((t(.totalWasteValue), displayMoney(estimate.totalWastedValue, source: source), accentRose.withAlphaComponent(0.92), .totalWaste))
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

    func drawCostOverviewRow(title: String, value: String, color: NSColor, rect: NSRect, info: CostOverviewInfo? = nil) {
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

    func drawToggle(rect: NSRect, isOn: Bool) {
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

    struct CostHistoryHeaderLayout {
        let hintRect: NSRect
        let emptyWeeksLabelRect: NSRect
        let emptyWeeksSwitchRect: NSRect
        let yearRect: NSRect
        let ringsRect: NSRect
    }

    func costHistoryHeaderLayout(chartRect: NSRect) -> CostHistoryHeaderLayout {
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

    enum QuotaCycleRowKind {
        case current
        case earlyRefresh
        case scheduledReset
    }

    struct QuotaCycleRowModel {
        let shortRange: String
        let fullRange: String
        let kind: QuotaCycleRowKind
        let badgeText: String
        let kindTimeText: String
        let durationText: String
        let percent: Double
        let isCurrent: Bool
        let isPartial: Bool
        var tokenText: String?
        var apiCostText: String?
        var moneyValue: Double?
        var usedMoneyValue: Double?

        var isEarlyRefresh: Bool { kind == .earlyRefresh }
        var isCapped: Bool { percent >= 97 }
        var wastedMoneyValue: Double? {
            guard let moneyValue, let usedMoneyValue, !isCurrent else { return nil }
            return max(0, moneyValue - usedMoneyValue)
        }
    }

    struct QuotaCycleMoneySummary {
        let cycleCount: Int
        let totalValue: Double
        let usedValue: Double
        let wastedValue: Double
        let currentValue: Double?
        let currentUsedValue: Double?
        let currentRemainTokensText: String?
        let monthlyCost: Double
        let weeklyBudget: Double
    }

    struct QuotaCycleBarModel {
        var percent: Double
        var resetAt: Date
        var windowMinutes: Int
        var isCurrent: Bool
        var isEarlyRefresh: Bool
        var tokenText: String?
    }

    struct QuotaCyclePageModel {
        let limit: LiveRateLimit?
        let weeklyRows: [QuotaCycleRowModel]
        let fiveHourBars: [QuotaCycleBarModel]
        let cappedCount: Int
        let hasBackfilledRows: Bool
        let hasEarlyRefreshRows: Bool
        let moneySummary: QuotaCycleMoneySummary?
        let currentDailyUsage: [(day: String, total: Int64)]

        var hasFootnote: Bool { hasBackfilledRows || hasEarlyRefreshRows }
    }

    static let cycleISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let cycleRangeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    static let resetCreditExpiryFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = appTimeZone()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    static let resetCreditFullFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = appTimeZone()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static let cycleDayLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd"
        return formatter
    }()

    static let cycleTimeLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    static let cycleClockLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var quotaCycleSource: QuotaViewOption {
        selectedDetailsSource == .claude ? .claude : .codex
    }

    func quotaCyclePageModel(for snapshot: DetailsSnapshot) -> QuotaCyclePageModel {
        let limitID = quotaCycleSource.liveLimitID
        let limit = snapshot.liveLimits.first { $0.id == limitID }
        let iso = Self.cycleISOFormatter

        struct WeeklyCycleInfo {
            var start: Date?
            var end: Date
            var percent: Double
            var isBackfilled: Bool
            var isCurrent: Bool
            var earlyRefreshAt: Date?
        }

        // Local-log usage attributed to each cycle, for tooltips: day-level
        // sums for weekly cycles, hour-level sums for 5h cycles.
        let usageReport = quotaCycleSource == .claude ? snapshot.claude : snapshot.codex
        let moneySource = quotaCycleSource
        let monthlyCost = AppSettings.monthlyPlanCost(for: moneySource)
        let weeklyBudget = monthlyCost > 0 ? monthlyCost * 12 / 52 : 0
        let dayParser = dayFormatter()
        struct CycleDayStat {
            let midpoint: Date
            let total: Int64
            let usd: Double
            let priced: Bool
        }
        let dayStats: [CycleDayStat] = usageReport.byDay.compactMap { day in
            guard day.usage.total > 0, let date = dayParser.date(from: day.day) else { return nil }
            let estimate = APICostEstimator.estimate(day: day)
            return CycleDayStat(midpoint: date.addingTimeInterval(43_200), total: day.usage.total, usd: estimate.usdValue, priced: estimate.hasPricedUsage)
        }
        func cycleUsageStats(start: Date?, end: Date) -> (tokenText: String?, apiCostText: String?) {
            guard let start else { return (nil, nil) }
            var total: Int64 = 0
            var usd = 0.0
            var hasPriced = false
            for stat in dayStats where stat.midpoint >= start && stat.midpoint < end {
                total += stat.total
                if stat.priced {
                    usd += stat.usd
                    hasPriced = true
                }
            }
            guard total > 0 else { return (nil, nil) }
            return (compact(total), hasPriced ? compactDisplayAPIMoney(usd) : nil)
        }
        func fiveHourTokenText(start: Date, end: Date) -> String? {
            let total = usageReport.byHour.reduce(Int64(0)) { partial, hour in
                hour.hour >= start && hour.hour < end ? partial + hour.usage.total : partial
            }
            return total > 0 ? compact(total) : nil
        }

        let weeklyRecords = QuotaCycleStore.shared.cycles(limitID: limitID, kind: .weekly)
        let weeklyTolerance: TimeInterval = 24 * 3600
        var matchedWeeklyIndex: Int?
        var currentInfo: WeeklyCycleInfo?
        if let liveWeekly = limit?.secondary, let resetsAt = liveWeekly.resetsAt, liveWeekly.windowMinutes > 0 {
            matchedWeeklyIndex = weeklyRecords.firstIndex { record in
                record.resetAtDate(iso).map { abs($0.timeIntervalSince(resetsAt)) <= weeklyTolerance } == true
            }
            let recordedPeak = matchedWeeklyIndex.map { weeklyRecords[$0].maxUsedPercent } ?? 0
            currentInfo = WeeklyCycleInfo(
                start: resetsAt.addingTimeInterval(-Double(liveWeekly.windowMinutes) * 60),
                end: resetsAt,
                percent: max(0, min(100, max(liveWeekly.usedPercent, recordedPeak))),
                isBackfilled: false,
                isCurrent: true
            )
        }

        var infos: [WeeklyCycleInfo] = []
        for (index, record) in weeklyRecords.enumerated() {
            if index == matchedWeeklyIndex { continue }
            guard let end = record.resetAtDate(iso) else { continue }
            if currentInfo != nil && end.timeIntervalSinceNow > 0 { continue }
            infos.append(WeeklyCycleInfo(
                start: record.cycleStartDate(iso),
                end: end,
                percent: max(0, min(100, record.maxUsedPercent)),
                isBackfilled: record.isBackfilled,
                isCurrent: false
            ))
        }
        infos.sort { $0.end < $1.end }
        if let currentInfo {
            infos.append(currentInfo)
        }

        // A cycle whose successor starts well before the scheduled reset was
        // refreshed early (e.g. a provider promotion). Backfilled estimates
        // carry too much calendar-week drift to classify.
        let earlyRefreshTolerance: TimeInterval = 12 * 3600
        for index in 0..<max(0, infos.count - 1) {
            guard !infos[index].isBackfilled, !infos[index + 1].isBackfilled,
                  let nextStart = infos[index + 1].start,
                  nextStart < infos[index].end.addingTimeInterval(-earlyRefreshTolerance) else {
                continue
            }
            infos[index].earlyRefreshAt = nextStart
        }
        // Backfilled cycles carry their real span in start/end; one clearly
        // shorter than a weekly window means the quota was refreshed early.
        // The oldest cycle is exempt: its start is when observation began,
        // not the true cycle start, so a short span proves nothing.
        for index in 1..<max(1, infos.count) {
            guard infos[index].isBackfilled, infos[index].earlyRefreshAt == nil,
                  let start = infos[index].start,
                  infos[index].end.timeIntervalSince(start) < 5.5 * 86_400 else {
                continue
            }
            infos[index].earlyRefreshAt = infos[index].end
        }

        var hasBackfilled = false
        var hasEarlyRefresh = false
        var rows: [QuotaCycleRowModel] = []
        for info in infos {
            if info.isBackfilled { hasBackfilled = true }
            if info.earlyRefreshAt != nil { hasEarlyRefresh = true }
            let effectiveEnd = info.earlyRefreshAt ?? info.end
            let dayText: (Date) -> String = { Self.cycleDayLabelFormatter.string(from: $0) }
            let timeText: (Date) -> String = { Self.cycleTimeLabelFormatter.string(from: $0) }

            let shortRange: String
            let fullRange: String
            if info.isCurrent {
                let startDay = info.start.map(dayText) ?? "--"
                let startFull = info.start.map(timeText) ?? "--"
                shortRange = "\(startDay)→\(t(.cycleNow))"
                fullRange = "\(startFull) → \(t(.cycleNow))"
            } else if let start = info.start {
                shortRange = "\(dayText(start))→\(dayText(effectiveEnd))"
                fullRange = "\(timeText(start)) → \(timeText(effectiveEnd))"
            } else {
                shortRange = dayText(effectiveEnd)
                fullRange = timeText(effectiveEnd)
            }

            // Badges stay short: the range line above already carries the
            // dates, and the hover tooltip has the exact timestamps.
            let kind: QuotaCycleRowKind = info.isCurrent ? .current : (info.earlyRefreshAt != nil ? .earlyRefresh : .scheduledReset)
            let kindTimeText: String
            let badgeText: String
            switch kind {
            case .current:
                kindTimeText = timeText(info.end)
                badgeText = "\(t(.cycleInProgress)) · \(compactResetRelative(info.end))"
            case .earlyRefresh:
                kindTimeText = timeText(effectiveEnd)
                badgeText = t(.cycleEarlyRefresh)
            case .scheduledReset:
                kindTimeText = timeText(info.end)
                badgeText = "\(t(.cycleNormalReset))\(info.isBackfilled ? " *" : "")"
            }

            let durationText: String
            if let start = info.start {
                let referenceEnd = info.isCurrent ? Date() : effectiveEnd
                let days = max(0, referenceEnd.timeIntervalSince(start)) / 86_400
                durationText = String(format: t(info.isCurrent ? .cycleCurrentDayFormat : .cycleDurationDaysFormat), days)
            } else {
                durationText = "--"
            }

            let usageStats = cycleUsageStats(start: info.start, end: info.isCurrent ? Date() : effectiveEnd)
            // Cycle value: the weekly plan budget, pro-rated for cycles that
            // were cut short by an early refresh.
            var moneyValue: Double?
            var usedMoneyValue: Double?
            if weeklyBudget > 0, let start = info.start {
                let span = max(0, effectiveEnd.timeIntervalSince(start))
                let value = weeklyBudget * min(1, span / (7 * 86_400))
                moneyValue = value
                usedMoneyValue = value * max(0, min(100, info.percent)) / 100
            }
            rows.append(QuotaCycleRowModel(
                shortRange: shortRange,
                fullRange: fullRange,
                kind: kind,
                badgeText: badgeText,
                kindTimeText: kindTimeText,
                durationText: durationText,
                percent: info.percent,
                isCurrent: info.isCurrent,
                isPartial: info.isBackfilled,
                tokenText: usageStats.tokenText,
                apiCostText: usageStats.apiCostText,
                moneyValue: moneyValue,
                usedMoneyValue: usedMoneyValue
            ))
        }
        rows.reverse()
        rows = Array(rows.prefix(60))

        // Money summary over the shown cycles, plus a token estimate for the
        // remaining share of the current cycle.
        var moneySummary: QuotaCycleMoneySummary?
        if weeklyBudget > 0, !rows.isEmpty {
            var totalValue = 0.0
            var usedValue = 0.0
            var wastedValue = 0.0
            var currentValue: Double?
            var currentUsedValue: Double?
            for row in rows {
                guard let value = row.moneyValue, let used = row.usedMoneyValue else { continue }
                totalValue += value
                usedValue += used
                if row.isCurrent {
                    currentValue = value
                    currentUsedValue = used
                } else {
                    wastedValue += max(0, value - used)
                }
            }
            var remainTokensText: String?
            if let currentRow = rows.first(where: { $0.isCurrent }),
               let estimator = CostEstimator(
                   report: usageReport,
                   limit: limit,
                   quotaReferenceReport: nil,
                   monthlyCost: monthlyCost,
                   paymentStartDay: AppSettings.paymentStartDay(for: moneySource)
               ) {
                let remainPercent = max(0, 100 - currentRow.percent)
                let tokens = Int64(estimator.weeklyReferenceTotal * remainPercent / 100)
                if tokens > 0 {
                    remainTokensText = String(format: t(.cycleTokensApproxFormat), compact(tokens))
                }
            }
            moneySummary = QuotaCycleMoneySummary(
                cycleCount: rows.count,
                totalValue: totalValue,
                usedValue: usedValue,
                wastedValue: wastedValue,
                currentValue: currentValue,
                currentUsedValue: currentUsedValue,
                currentRemainTokensText: remainTokensText,
                monthlyCost: monthlyCost,
                weeklyBudget: weeklyBudget
            )
        }

        // Daily usage inside the current cycle for the mini distribution.
        var currentDailyUsage: [(day: String, total: Int64)] = []
        if let currentInfo, let currentStart = currentInfo.start {
            for day in usageReport.byDay {
                guard let date = dayParser.date(from: day.day) else { continue }
                let midpoint = date.addingTimeInterval(43_200)
                guard midpoint >= currentStart, midpoint < Date().addingTimeInterval(43_200) else { continue }
                currentDailyUsage.append((day: day.day, total: day.usage.total))
            }
            currentDailyUsage.sort { $0.day < $1.day }
        }

        var bars: [QuotaCycleBarModel] = QuotaCycleStore.shared.cycles(limitID: limitID, kind: .fiveHour).compactMap { record in
            guard let end = record.resetAtDate(iso) else { return nil }
            return QuotaCycleBarModel(
                percent: max(0, min(100, record.maxUsedPercent)),
                resetAt: end,
                windowMinutes: record.windowMinutes,
                isCurrent: false,
                isEarlyRefresh: false
            )
        }
        if let livePrimary = limit?.primary, let resetsAt = livePrimary.resetsAt {
            let tolerance = min(max(Double(livePrimary.windowMinutes) * 60 * 0.1, 20 * 60), 24 * 3600)
            let liveUsed = max(0, min(100, livePrimary.usedPercent))
            if let index = bars.firstIndex(where: { abs($0.resetAt.timeIntervalSince(resetsAt)) <= tolerance }) {
                bars[index].isCurrent = true
                bars[index].percent = max(bars[index].percent, liveUsed)
            } else {
                bars.append(QuotaCycleBarModel(
                    percent: liveUsed,
                    resetAt: resetsAt,
                    windowMinutes: livePrimary.windowMinutes,
                    isCurrent: true,
                    isEarlyRefresh: false
                ))
            }
        }
        bars.sort { $0.resetAt < $1.resetAt }
        if bars.count > 36 {
            bars = Array(bars.suffix(36))
        }
        let fiveHourEarlyTolerance: TimeInterval = 30 * 60
        for index in 0..<max(0, bars.count - 1) {
            let next = bars[index + 1]
            guard next.windowMinutes > 0 else { continue }
            let nextStart = next.resetAt.addingTimeInterval(-Double(next.windowMinutes) * 60)
            if nextStart < bars[index].resetAt.addingTimeInterval(-fiveHourEarlyTolerance) {
                bars[index].isEarlyRefresh = true
                hasEarlyRefresh = true
            }
        }
        for index in 0..<bars.count {
            let bar = bars[index]
            let start = bar.resetAt.addingTimeInterval(-Double(max(bar.windowMinutes, 1)) * 60)
            bars[index].tokenText = fiveHourTokenText(start: start, end: bar.isCurrent ? Date() : bar.resetAt)
        }
        let capped = bars.filter { $0.percent >= 97 }.count

        return QuotaCyclePageModel(
            limit: limit,
            weeklyRows: rows,
            fiveHourBars: bars,
            cappedCount: capped,
            hasBackfilledRows: hasBackfilled,
            hasEarlyRefreshRows: hasEarlyRefresh,
            moneySummary: moneySummary,
            currentDailyUsage: currentDailyUsage
        )
    }

    func cycleSeverityColor(_ percent: Double) -> NSColor {
        if percent >= 97 { return accentRose }
        if percent >= 70 { return accentAmber }
        return accentTeal
    }

    func drawQuotaCyclesPage(snapshot: DetailsSnapshot, content: NSRect) {
        if selectedDetailsSource == .api {
            drawAPICostHistoryPage(report: snapshot.api, content: content)
            return
        }
        let model = quotaCyclePageModel(for: snapshot)
        let panelGap: CGFloat = 16

        guard model.moneySummary != nil else {
            // No plan cost configured: fall back to the percent-only layout.
            let currentHeight: CGFloat = 150
            let panelWidth = (content.width - panelGap) / 2
            let fiveHourRect = NSRect(x: content.minX, y: content.minY + 78, width: panelWidth, height: currentHeight)
            let weeklyCurrentRect = NSRect(x: fiveHourRect.maxX + panelGap, y: fiveHourRect.minY, width: panelWidth, height: currentHeight)
            drawCurrentCyclePanel(window: model.limit?.primary, title: t(.fiveHourWindow), rect: fiveHourRect)
            drawCurrentCyclePanel(window: model.limit?.secondary, title: t(.weeklyWindow), rect: weeklyCurrentRect)
            let historyHeight = weeklyHistoryPanelHeight(rowCount: model.weeklyRows.count, contentWidth: content.width)
            let historyRect = NSRect(x: content.minX, y: fiveHourRect.maxY + panelGap, width: content.width, height: historyHeight)
            drawWeeklyCycleHistory(model: model, rect: historyRect)
            let stripRect = NSRect(x: content.minX, y: historyRect.maxY + panelGap, width: content.width, height: 176)
            drawFiveHourCycleStrip(model: model, rect: stripRect)
            return
        }

        var y = content.minY + 78
        drawMoneySummaryCards(model: model, rect: NSRect(x: content.minX, y: y, width: content.width, height: 96))
        y += 96 + panelGap
        let currentRect = NSRect(x: content.minX, y: y, width: content.width, height: 172)
        drawCurrentCycleMoneyPanel(model: model, rect: currentRect)
        y += 172 + panelGap
        let barsRect = NSRect(x: content.minX, y: y, width: content.width, height: 330)
        drawCycleValueBars(model: model, rect: barsRect)
        y += 330 + panelGap
        drawFiveHourCycleStrip(model: model, rect: NSRect(x: content.minX, y: y, width: content.width, height: 176))
    }

    func drawAPICostHistoryPage(report: TokenReport, content: NSRect) {
        let isChinese = AppLanguage.current == .chinese || AppLanguage.current == .traditionalChinese
        let estimate = APICostEstimator.estimate(report: report)
        let models = report.modelBreakdown
        let gap: CGFloat = 12
        let y = content.minY + 78
        let cardWidth = (content.width - gap * 3) / 4
        let cards: [(String, String, NSColor)] = [
            (isChinese ? "API 估算成本" : "Estimated API cost", estimate.hasPricedUsage ? displayAPIMoney(estimate.usdValue, source: .api) : "--", accentTeal),
            (isChinese ? "总 Token" : "Total tokens", compactDashboardTotal(report.usage.total), .white),
            (isChinese ? "价格覆盖率" : "Price coverage", String(format: "%.1f%%", estimate.coveragePercent), estimate.coveragePercent >= 99.9 ? accentTeal : accentAmber),
            (isChinese ? "模型" : "Models", "\(models.count)", .systemCyan)
        ]
        for (index, card) in cards.enumerated() {
            let rect = NSRect(x: content.minX + CGFloat(index) * (cardWidth + gap), y: y, width: cardWidth, height: 92)
            drawPanel(rect)
            drawTruncatedText(card.0, rect: NSRect(x: rect.minX + 14, y: rect.minY + 13, width: rect.width - 28, height: 16), font: .systemFont(ofSize: 10.5, weight: .semibold), color: NSColor.white.withAlphaComponent(0.5))
            drawTruncatedText(card.1, rect: NSRect(x: rect.minX + 14, y: rect.minY + 39, width: rect.width - 28, height: 28), font: .monospacedDigitSystemFont(ofSize: 18, weight: .bold), color: card.2)
        }

        let modelRect = NSRect(x: content.minX, y: y + 108, width: content.width, height: 238)
        drawPanel(modelRect)
        drawText(isChinese ? "模型成本" : "Model costs", rect: NSRect(x: modelRect.minX + 16, y: modelRect.minY + 14, width: 220, height: 20), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
        drawRight(isChinese ? "输入 / 输出 / 成本" : "Input / Output / Cost", rect: NSRect(x: modelRect.maxX - 300, y: modelRect.minY + 16, width: 284, height: 16), color: NSColor.white.withAlphaComponent(0.44), font: .systemFont(ofSize: 10.5, weight: .semibold))
        if models.isEmpty {
            drawText(isChinese ? "当前范围没有 API 模型用量" : "No API model usage in this range", rect: NSRect(x: modelRect.minX + 16, y: modelRect.minY + 56, width: modelRect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
        } else {
            for (index, model) in models.prefix(8).enumerated() {
                let rowY = modelRect.minY + 48 + CGFloat(index) * 22
                let modelEstimate = APICostEstimator.estimate(usage: model.usage, modelName: model.name)
                drawTruncatedText(model.name, rect: NSRect(x: modelRect.minX + 16, y: rowY, width: modelRect.width * 0.46, height: 17), font: .systemFont(ofSize: 11.5, weight: .semibold), color: .white)
                let detail = "\(compact(model.usage.input)) / \(compact(model.usage.output)) / \(modelEstimate.hasPricedUsage ? displayAPIMoney(modelEstimate.usdValue, source: .api) : "--")"
                drawRight(detail, rect: NSRect(x: modelRect.midX, y: rowY, width: modelRect.width / 2 - 16, height: 17), color: modelEstimate.hasPricedUsage ? accentTeal : accentAmber, font: .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold))
            }
        }

        let dayRect = NSRect(x: content.minX, y: modelRect.maxY + 16, width: content.width, height: 260)
        drawPanel(dayRect)
        drawText(isChinese ? "每日 API 成本" : "Daily API cost", rect: NSRect(x: dayRect.minX + 16, y: dayRect.minY + 14, width: 220, height: 20), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
        let days = Array(report.byDay.filter { $0.usage.total > 0 }.suffix(9))
        if days.isEmpty {
            drawText(isChinese ? "当前范围没有每日用量" : "No daily API usage in this range", rect: NSRect(x: dayRect.minX + 16, y: dayRect.minY + 56, width: dayRect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
        } else {
            let maxCost = max(days.map { APICostEstimator.estimate(day: $0).usdValue }.max() ?? 0, 0.000001)
            for (index, day) in days.enumerated() {
                let rowY = dayRect.minY + 48 + CGFloat(index) * 22
                let dayEstimate = APICostEstimator.estimate(day: day)
                drawText(String(day.day.suffix(5)), rect: NSRect(x: dayRect.minX + 16, y: rowY, width: 56, height: 16), font: .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold), color: NSColor.white.withAlphaComponent(0.62))
                let bar = NSRect(x: dayRect.minX + 82, y: rowY + 4, width: max(2, (dayRect.width - 260) * CGFloat(dayEstimate.usdValue / maxCost)), height: 8)
                accentTeal.withAlphaComponent(0.72).setFill()
                NSBezierPath(roundedRect: bar, xRadius: 4, yRadius: 4).fill()
                drawRight("\(compact(day.usage.total)) · \(dayEstimate.hasPricedUsage ? displayAPIMoney(dayEstimate.usdValue, source: .api) : "--")", rect: NSRect(x: dayRect.maxX - 170, y: rowY, width: 154, height: 16), color: .white, font: .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold))
            }
        }
    }

    func drawMoneySummaryCards(model: QuotaCyclePageModel, rect: NSRect) {
        guard let money = model.moneySummary else { return }
        let source = quotaCycleSource
        let gap: CGFloat = 12
        let cardWidth = (rect.width - gap * 3) / 4
        let usedShare = money.totalValue > 0 ? Int(round(money.usedValue / money.totalValue * 100)) : 0
        let wastedShare = money.totalValue > 0 ? Int(round(money.wastedValue / money.totalValue * 100)) : 0
        let currentRemain = (money.currentValue ?? 0) - (money.currentUsedValue ?? 0)
        let currentRemainShare = (money.currentValue ?? 0) > 0 ? Int(round(currentRemain / (money.currentValue ?? 1) * 100)) : 0
        var remainSub = "\(currentRemainShare)%"
        if let tokens = money.currentRemainTokensText {
            remainSub += " \(tokens)"
        }

        let cards: [(title: String, value: String, valueColor: NSColor, sub: String)] = [
            (
                String(format: t(.cycleMoneySummaryValueFormat), money.cycleCount),
                displayMoney(money.totalValue, source: source),
                .white,
                String(format: t(.cycleMoneyPerCycleFormat), displayMoney(money.monthlyCost, source: source), displayMoney(money.weeklyBudget, source: source))
            ),
            (
                t(.cycleMoneyUsedTitle),
                displayMoney(money.usedValue, source: source),
                accentTeal,
                "\(usedShare)%"
            ),
            (
                t(.cycleMoneyWastedTitle),
                displayMoney(money.wastedValue, source: source),
                money.wastedValue >= money.weeklyBudget * 0.5 ? accentRose : NSColor.white.withAlphaComponent(0.85),
                "\(wastedShare)%"
            ),
            (
                t(.cycleMoneyRemainTitle),
                money.currentValue != nil ? displayMoney(max(0, currentRemain), source: source) : "--",
                accentAmber,
                remainSub
            )
        ]
        for (index, card) in cards.enumerated() {
            let cardRect = NSRect(x: rect.minX + CGFloat(index) * (cardWidth + gap), y: rect.minY, width: cardWidth, height: rect.height)
            drawPanel(cardRect)
            drawText(card.title, rect: NSRect(x: cardRect.minX + 16, y: cardRect.minY + 14, width: cardRect.width - 32, height: 16), font: .systemFont(ofSize: 11.5, weight: .semibold), color: NSColor.white.withAlphaComponent(0.5))
            drawText(card.value, rect: NSRect(x: cardRect.minX + 16, y: cardRect.minY + 34, width: cardRect.width - 32, height: 28), font: .monospacedDigitSystemFont(ofSize: 23, weight: .bold), color: card.valueColor)
            drawTruncatedText(card.sub, rect: NSRect(x: cardRect.minX + 16, y: cardRect.minY + 66, width: cardRect.width - 32, height: 15), font: .monospacedDigitSystemFont(ofSize: 10.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.42))
        }
    }

    func drawCurrentCycleMoneyPanel(model: QuotaCyclePageModel, rect: NSRect) {
        drawPanel(rect)
        let source = quotaCycleSource
        guard let window = model.limit?.secondary,
              window.windowMinutes > 0,
              let currentRow = model.weeklyRows.first(where: { $0.isCurrent }) else {
            drawText(t(.cycleCurrentTitle), rect: NSRect(x: rect.minX + 18, y: rect.minY + 16, width: 300, height: 20), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
            drawText(t(.liveLimitUnavailable), rect: NSRect(x: rect.minX + 18, y: rect.minY + 52, width: rect.width - 36, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }

        let headerText = "\(t(.cycleCurrentTitle)) · \(currentRow.shortRange)"
        drawText(headerText, rect: NSRect(x: rect.minX + 18, y: rect.minY + 16, width: rect.width * 0.5, height: 20), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
        if let resetsAt = window.resetsAt {
            let resetText = "\(t(.reset)) \(compactResetRelative(resetsAt)) · \(Self.cycleRangeFormatter.string(from: resetsAt))"
            drawRight(resetText, rect: NSRect(x: rect.minX + 18, y: rect.minY + 18, width: rect.width - 36, height: 16), color: NSColor.white.withAlphaComponent(0.52), font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold))
        }

        let used = max(0, min(100, window.usedPercent))
        let usedColor = cycleSeverityColor(used)
        let leftWidth = rect.width * 0.56 - 18
        var bigText = "\(t(.used)) \(Int(round(used)))%"
        if let usedMoney = currentRow.usedMoneyValue {
            bigText += " · \(displayMoney(usedMoney, source: source))"
        }
        drawText(bigText, rect: NSRect(x: rect.minX + 18, y: rect.minY + 46, width: leftWidth, height: 30), font: .monospacedDigitSystemFont(ofSize: 24, weight: .bold), color: usedColor)

        let barRect = NSRect(x: rect.minX + 18, y: rect.minY + 96, width: leftWidth, height: 10)
        NSColor.white.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: barRect, xRadius: 5, yRadius: 5).fill()
        let fillWidth = barRect.width * CGFloat(used / 100)
        if fillWidth > 1 {
            usedColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: barRect.minX, y: barRect.minY, width: fillWidth, height: barRect.height), xRadius: 5, yRadius: 5).fill()
        }
        var paceText = ""
        if let pace = paceComparison(for: window) {
            let markerX = barRect.minX + barRect.width * CGFloat(min(100, max(0, pace.progressPercent)) / 100)
            NSColor.white.withAlphaComponent(0.72).setFill()
            NSRect(x: markerX - 1, y: barRect.minY - 4, width: 2, height: barRect.height + 8).fill()
            let delta = Int(round(used - pace.progressPercent))
            paceText = delta > 0 ? String(format: t(.cyclePaceAheadFormat), delta) : String(format: t(.cyclePaceBehindFormat), -delta)
            let progressFraction = pace.progressPercent / 100
            if progressFraction >= 0.03, used >= 1, used < 100 {
                let projectedEnd = used / progressFraction
                if projectedEnd >= 100 {
                    let elapsedSeconds = Double(window.windowMinutes) * 60 * progressFraction
                    let secondsToCap = elapsedSeconds * (100 - used) / used
                    paceText += " · \(String(format: t(.cyclePaceCapEtaFormat), compactResetRelative(Date().addingTimeInterval(secondsToCap))))"
                } else {
                    paceText += " · \(String(format: t(.cyclePaceEndProjectionFormat), Int(round(projectedEnd))))"
                }
            }
        }
        if !paceText.isEmpty {
            drawTruncatedText(paceText, rect: NSRect(x: rect.minX + 18, y: barRect.maxY + 12, width: leftWidth, height: 16), font: .systemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.52))
        }

        // Right column: remaining money/tokens plus the daily distribution.
        let rightX = rect.minX + rect.width * 0.6
        let rightWidth = rect.maxX - 18 - rightX
        if let money = model.moneySummary, let currentValue = money.currentValue, let currentUsed = money.currentUsedValue {
            let remain = max(0, currentValue - currentUsed)
            var remainText = "\(t(.remaining)) \(displayMoney(remain, source: source))"
            if let tokens = money.currentRemainTokensText {
                remainText += " \(tokens)"
            }
            drawText(remainText, rect: NSRect(x: rightX, y: rect.minY + 50, width: rightWidth, height: 18), font: .monospacedDigitSystemFont(ofSize: 13, weight: .semibold), color: NSColor.white.withAlphaComponent(0.82))
        }
        if !model.currentDailyUsage.isEmpty {
            let barsTop = rect.minY + 82
            let barsBottom = rect.minY + 130
            let barsHeight = barsBottom - barsTop
            let count = model.currentDailyUsage.count
            let gap: CGFloat = 6
            let dayBarWidth = min(40, (rightWidth - gap * CGFloat(max(count - 1, 0))) / CGFloat(count))
            let maxTotal = max(model.currentDailyUsage.map(\.total).max() ?? 1, 1)
            for (index, day) in model.currentDailyUsage.enumerated() {
                let height = max(3, barsHeight * CGFloat(Double(day.total) / Double(maxTotal)))
                let dayRect = NSRect(
                    x: rightX + CGFloat(index) * (dayBarWidth + gap),
                    y: barsBottom - height,
                    width: dayBarWidth,
                    height: height
                )
                accentAmber.withAlphaComponent(index == count - 1 ? 1 : 0.5).setFill()
                NSBezierPath(roundedRect: dayRect, xRadius: 2.5, yRadius: 2.5).fill()
            }
            drawText(t(.cycleDailyHint), rect: NSRect(x: rightX, y: barsBottom + 8, width: rightWidth, height: 14), font: .systemFont(ofSize: 10, weight: .medium), color: NSColor.white.withAlphaComponent(0.38))
        }
    }

    func drawCycleValueBars(model: QuotaCyclePageModel, rect: NSRect) {
        drawPanel(rect)
        quotaCycleTooltipRows = model.weeklyRows
        drawText(t(.cycleHistoryTitle), rect: NSRect(x: rect.minX + 16, y: rect.minY + 14, width: 320, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        let completed = model.weeklyRows.filter { !$0.isCurrent }
        var summaryParts: [String] = []
        summaryParts.append(String(format: t(.cycleCappedCountFormat), completed.filter(\.isCapped).count))
        let earlyCount = model.weeklyRows.filter(\.isEarlyRefresh).count
        if earlyCount > 0 {
            summaryParts.append(String(format: t(.cycleEarlyCountFormat), earlyCount))
        }
        drawRight(summaryParts.joined(separator: " · "), rect: NSRect(x: rect.minX + 16, y: rect.minY + 18, width: rect.width - 32, height: 16), color: NSColor.white.withAlphaComponent(0.5), font: .monospacedDigitSystemFont(ofSize: 11, weight: .medium))

        guard !model.weeklyRows.isEmpty else {
            drawText(t(.cycleNoHistory), rect: NSRect(x: rect.minX + 16, y: rect.minY + 52, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }

        let source = quotaCycleSource
        let cells = Array(model.weeklyRows.reversed())
        let count = cells.count
        let showsBadges = count <= 8
        let areaX = rect.minX + 18
        let areaWidth = rect.width - 36
        let gap: CGFloat = count > 16 ? 6 : 14
        let barWidth = min(66, (areaWidth - gap * CGFloat(max(count - 1, 0))) / CGFloat(count))
        let groupWidth = barWidth * CGFloat(count) + gap * CGFloat(max(count - 1, 0))
        let groupX = areaX + max(0, (areaWidth - groupWidth) / 2)
        let barsTop = rect.minY + 56
        let barsBottom = rect.maxY - (showsBadges ? 96 : 72)
        let maxValue = max(model.weeklyRows.compactMap(\.moneyValue).max() ?? 1, 0.01)

        for (displayIndex, row) in cells.enumerated() {
            let modelIndex = count - 1 - displayIndex
            let value = row.moneyValue ?? 0
            let usedMoney = row.usedMoneyValue ?? 0
            let barX = groupX + CGFloat(displayIndex) * (barWidth + gap)
            let totalHeight = max(6, (barsBottom - barsTop) * CGFloat(value / maxValue))
            let usedHeight = max(3, totalHeight * CGFloat(max(0, min(100, row.percent)) / 100))
            let wasteHeight = max(0, totalHeight - usedHeight)

            if wasteHeight > 0.5 {
                accentRose.withAlphaComponent(row.isCurrent ? 0.14 : (row.isPartial ? 0.3 : 0.45)).setFill()
                NSBezierPath(roundedRect: NSRect(x: barX, y: barsBottom - totalHeight, width: barWidth, height: wasteHeight), xRadius: 4, yRadius: 4).fill()
            }
            let usedColor = row.isCurrent ? accentAmber : (row.isPartial ? accentTeal.withAlphaComponent(0.55) : accentTeal)
            let usedPath = NSBezierPath(roundedRect: NSRect(x: barX, y: barsBottom - usedHeight, width: barWidth, height: usedHeight), xRadius: 4, yRadius: 4)
            usedColor.setFill()
            usedPath.fill()
            if row.isCurrent {
                accentAmber.setStroke()
                let focus = NSBezierPath(roundedRect: NSRect(x: barX - 3, y: barsBottom - totalHeight - 3, width: barWidth + 6, height: totalHeight + 6), xRadius: 6, yRadius: 6)
                focus.lineWidth = 1.5
                focus.stroke()
            }

            let topLabel: String
            let topColor: NSColor
            if row.isCurrent {
                topLabel = displayMoney(usedMoney, source: source)
                topColor = accentAmber
            } else if let waste = row.wastedMoneyValue, waste >= 1 {
                topLabel = "-\(displayMoney(waste, source: source))"
                topColor = accentRose.withAlphaComponent(0.92)
            } else {
                topLabel = "≈0"
                topColor = NSColor.white.withAlphaComponent(0.4)
            }
            let topLabelFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
            let topLabelY = barsBottom - totalHeight - 20
            drawCentered(topLabel, rect: NSRect(x: barX - gap / 2, y: topLabelY, width: barWidth + gap, height: 14), font: topLabelFont, color: topColor)
            if row.isCapped {
                let topLabelWidth = measuredTextWidth(topLabel, font: topLabelFont)
                accentRose.setFill()
                NSBezierPath(ovalIn: NSRect(x: barX + barWidth / 2 + topLabelWidth / 2 + 5, y: topLabelY + 5, width: 4.5, height: 4.5)).fill()
            }

            let labelY = barsBottom + 8
            drawCentered(row.shortRange, rect: NSRect(x: barX - gap / 2 - 8, y: labelY, width: barWidth + gap + 16, height: 15), font: .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold), color: NSColor.white.withAlphaComponent(row.isCurrent ? 0.94 : 0.66))
            if showsBadges {
                drawCycleBadge(row: row, centerX: barX + barWidth / 2, y: labelY + 20, maxWidth: barWidth + gap + 8)
            }
            quotaCycleHitAreas.append((
                rect: NSRect(x: barX - gap / 2, y: barsTop, width: barWidth + gap, height: barsBottom - barsTop + 20),
                index: modelIndex
            ))
        }

        let legendY = rect.maxY - 26
        var legendX = rect.minX + 16
        let legendFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        let legendColor = NSColor.white.withAlphaComponent(0.42)
        func legendSwatch(_ color: NSColor, _ text: String) {
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: legendX, y: legendY + 3, width: 9, height: 9), xRadius: 2, yRadius: 2).fill()
            drawText(text, rect: NSRect(x: legendX + 13, y: legendY, width: 120, height: 14), font: legendFont, color: legendColor)
            legendX += 13 + measuredTextWidth(text, font: legendFont) + 18
        }
        legendSwatch(accentTeal, t(.used))
        legendSwatch(accentRose.withAlphaComponent(0.5), t(.cycleWasteLabel))
        var footnotes = [t(.cycleMoneyHint)]
        if model.hasBackfilledRows {
            footnotes.append("* \(t(.cycleBackfilled))")
        }
        drawTruncatedText(footnotes.joined(separator: "   ·   "), rect: NSRect(x: legendX + 8, y: legendY, width: rect.maxX - 16 - legendX - 8, height: 14), font: legendFont, color: NSColor.white.withAlphaComponent(0.36))
    }

    func drawCurrentCyclePanel(window: RateWindow?, title: String, rect: NSRect) {
        drawPanel(rect)
        drawText(title, rect: NSRect(x: rect.minX + 18, y: rect.minY + 16, width: rect.width - 200, height: 20), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
        guard let window, window.windowMinutes > 0 else {
            drawText(t(.liveLimitUnavailable), rect: NSRect(x: rect.minX + 18, y: rect.minY + 52, width: rect.width - 36, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }

        if let resetsAt = window.resetsAt {
            let resetText = "\(t(.reset)) \(compactResetRelative(resetsAt)) · \(Self.cycleRangeFormatter.string(from: resetsAt))"
            drawRight(resetText, rect: NSRect(x: rect.minX + 18, y: rect.minY + 18, width: rect.width - 36, height: 16), color: NSColor.white.withAlphaComponent(0.52), font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold))
        }

        let used = max(0, min(100, window.usedPercent))
        let usedColor = cycleSeverityColor(used)
        drawText("\(t(.used)) \(Int(round(used)))%", rect: NSRect(x: rect.minX + 18, y: rect.minY + 44, width: rect.width - 36, height: 32), font: .monospacedDigitSystemFont(ofSize: 26, weight: .bold), color: usedColor)

        let barRect = NSRect(x: rect.minX + 18, y: rect.minY + 92, width: rect.width - 36, height: 10)
        NSColor.white.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: barRect, xRadius: 5, yRadius: 5).fill()
        let fillWidth = barRect.width * CGFloat(used / 100)
        if fillWidth > 1 {
            usedColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: barRect.minX, y: barRect.minY, width: fillWidth, height: barRect.height), xRadius: 5, yRadius: 5).fill()
        }

        var paceText = ""
        if let pace = paceComparison(for: window) {
            let markerX = barRect.minX + barRect.width * CGFloat(min(100, max(0, pace.progressPercent)) / 100)
            NSColor.white.withAlphaComponent(0.72).setFill()
            NSRect(x: markerX - 1, y: barRect.minY - 4, width: 2, height: barRect.height + 8).fill()
            let delta = Int(round(used - pace.progressPercent))
            if delta > 0 {
                paceText = String(format: t(.cyclePaceAheadFormat), delta)
            } else {
                paceText = String(format: t(.cyclePaceBehindFormat), -delta)
            }
            paceText += " · \(t(.cycleTimeMarkerHint)) \(Int(round(pace.progressPercent)))%"

            // Constant-rate projection: will this cycle hit the cap, and when?
            let progressFraction = pace.progressPercent / 100
            if progressFraction >= 0.03, used >= 1, used < 100 {
                let projectedEnd = used / progressFraction
                if projectedEnd >= 100 {
                    let elapsedSeconds = Double(window.windowMinutes) * 60 * progressFraction
                    let secondsToCap = elapsedSeconds * (100 - used) / used
                    let capText = compactResetRelative(Date().addingTimeInterval(secondsToCap))
                    paceText += " · \(String(format: t(.cyclePaceCapEtaFormat), capText))"
                } else {
                    paceText += " · \(String(format: t(.cyclePaceEndProjectionFormat), Int(round(projectedEnd))))"
                }
            }
        }
        if !paceText.isEmpty {
            drawTruncatedText(paceText, rect: NSRect(x: rect.minX + 18, y: barRect.maxY + 12, width: rect.width - 36, height: 16), font: .systemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.52))
        }
    }

    func weeklyHistoryPanelHeight(rowCount: Int, contentWidth: CGFloat) -> CGFloat {
        guard rowCount > 0 else { return 96 }
        let bandCount = max(0, rowCount - 6)
        let bandHeight: CGFloat
        if bandCount > 0 {
            let perRow = max(1, Int((contentWidth - 32 + 8) / 32))
            let bandRows = Int(ceil(Double(bandCount) / Double(perRow)))
            bandHeight = 32 + CGFloat(bandRows) * 32
        } else {
            bandHeight = 30
        }
        return 50 + 138 + bandHeight + 30
    }

    func drawCycleRing(rect: NSRect, thickness: CGFloat, percent: Double, color: NSColor, highlighted: Bool) {
        fillDonut(in: rect, thickness: thickness, color: NSColor.white.withAlphaComponent(0.09))
        let progress = CGFloat(max(0, min(100, percent)) / 100)
        // Semi-transparent fills would double-darken where the rounded caps
        // overlap the arc, so draw the arc opaque inside a transparency layer
        // and apply the alpha to the composited result.
        let alpha = color.alphaComponent
        let opaqueColor = alpha < 0.999 ? color.withAlphaComponent(1) : color
        let cgContext = alpha < 0.999 ? NSGraphicsContext.current?.cgContext : nil
        if let cgContext {
            cgContext.saveGState()
            cgContext.setAlpha(alpha)
            cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        if progress >= 0.999 {
            fillDonut(in: rect, thickness: thickness, color: opaqueColor)
        } else if progress > 0.001 {
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let outerRadius = rect.width / 2
            let startAngle = -CGFloat.pi / 2
            let endAngle = startAngle + CGFloat.pi * 2 * progress
            fillDonutSegment(center: center, outerRadius: outerRadius, thickness: thickness, startAngle: startAngle, endAngle: endAngle, color: opaqueColor)
            let midRadius = outerRadius - thickness / 2
            opaqueColor.setFill()
            for angle in [startAngle, endAngle] {
                let capCenter = CGPoint(x: center.x + midRadius * cos(angle), y: center.y + midRadius * sin(angle))
                NSBezierPath(ovalIn: NSRect(x: capCenter.x - thickness / 2, y: capCenter.y - thickness / 2, width: thickness, height: thickness)).fill()
            }
        }
        if let cgContext {
            cgContext.endTransparencyLayer()
            cgContext.restoreGState()
        }
        if highlighted {
            color.setStroke()
            let focus = NSBezierPath(ovalIn: rect.insetBy(dx: -4.5, dy: -4.5))
            focus.lineWidth = 1.5
            focus.stroke()
        }
    }

    func drawCycleBadge(row: QuotaCycleRowModel, centerX: CGFloat, y: CGFloat, maxWidth: CGFloat) {
        let font = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
        let iconName: String
        let tint: NSColor
        let background: NSColor
        switch row.kind {
        case .current:
            iconName = "play.fill"
            tint = NSColor.systemGreen
            background = NSColor.systemGreen.withAlphaComponent(0.13)
        case .earlyRefresh:
            iconName = "bolt.fill"
            tint = accentBlue
            background = accentBlue.withAlphaComponent(0.16)
        case .scheduledReset:
            iconName = "arrow.clockwise"
            tint = NSColor.white.withAlphaComponent(0.56)
            background = NSColor.white.withAlphaComponent(0.08)
        }
        let textWidth = min(maxWidth - 32, measuredTextWidth(row.badgeText, font: font))
        let pillWidth = textWidth + 30
        let pill = NSRect(x: centerX - pillWidth / 2, y: y, width: pillWidth, height: 18)
        background.setFill()
        NSBezierPath(roundedRect: pill, xRadius: 9, yRadius: 9).fill()
        drawSymbolIcon(iconName, in: NSRect(x: pill.minX + 7, y: pill.minY + 4.5, width: 9, height: 9), color: tint, pointSize: 8)
        drawTruncatedText(row.badgeText, rect: NSRect(x: pill.minX + 20, y: pill.minY + 2.5, width: pill.width - 26, height: 13), font: font, color: tint)
    }

    func drawWeeklyCycleHistory(model: QuotaCyclePageModel, rect: NSRect) {
        drawPanel(rect)
        quotaCycleTooltipRows = model.weeklyRows
        drawText(t(.cycleHistoryTitle), rect: NSRect(x: rect.minX + 16, y: rect.minY + 14, width: 320, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)

        let completed = model.weeklyRows.filter { !$0.isCurrent }
        let statsBase = completed.isEmpty ? model.weeklyRows : completed
        if !statsBase.isEmpty {
            let averagePeak = Int(round(statsBase.map(\.percent).reduce(0, +) / Double(statsBase.count)))
            var summaryParts = [String(format: t(.cycleAvgPeakFormat), averagePeak)]
            summaryParts.append(String(format: t(.cycleCappedCountFormat), completed.filter(\.isCapped).count))
            let earlyCount = model.weeklyRows.filter(\.isEarlyRefresh).count
            if earlyCount > 0 {
                summaryParts.append(String(format: t(.cycleEarlyCountFormat), earlyCount))
            }
            drawRight(summaryParts.joined(separator: " · "), rect: NSRect(x: rect.minX + 16, y: rect.minY + 18, width: rect.width - 32, height: 16), color: NSColor.white.withAlphaComponent(0.5), font: .monospacedDigitSystemFont(ofSize: 11, weight: .medium))
        }

        guard !model.weeklyRows.isEmpty else {
            drawText(t(.cycleNoHistory), rect: NSRect(x: rect.minX + 16, y: rect.minY + 52, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }

        // Recent cycles as large rings: oldest on the left, current on the right.
        let bigCount = min(model.weeklyRows.count, 6)
        let bigRows = Array(model.weeklyRows.prefix(bigCount).reversed())
        let cellWidth = min(178, (rect.width - 32) / CGFloat(bigCount))
        let startX = rect.minX + 16 + max(0, (rect.width - 32 - cellWidth * CGFloat(bigCount)) / 2)
        let ringSide: CGFloat = 84
        let ringTop = rect.minY + 52
        let rangeFont = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
        for (displayIndex, row) in bigRows.enumerated() {
            let modelIndex = bigCount - 1 - displayIndex
            let cellMidX = startX + CGFloat(displayIndex) * cellWidth + cellWidth / 2
            let ringRect = NSRect(x: cellMidX - ringSide / 2, y: ringTop, width: ringSide, height: ringSide)
            let percent = max(0, min(100, row.percent))
            let color = cycleSeverityColor(percent)
            drawCycleRing(rect: ringRect, thickness: 9, percent: percent, color: row.isPartial ? color.withAlphaComponent(0.5) : color, highlighted: row.isCurrent)
            drawCentered("\(Int(round(percent)))%", rect: NSRect(x: ringRect.minX, y: ringRect.midY - 11, width: ringRect.width, height: 18), font: .monospacedDigitSystemFont(ofSize: 16, weight: .bold), color: row.isCurrent ? .white : NSColor.white.withAlphaComponent(0.9))
            drawCentered(row.isCurrent ? t(.used) : t(.cyclePeak), rect: NSRect(x: ringRect.minX, y: ringRect.midY + 7, width: ringRect.width, height: 12), font: .systemFont(ofSize: 8.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.42))

            let rangeY = ringRect.maxY + 10
            drawCentered(row.shortRange, rect: NSRect(x: cellMidX - cellWidth / 2 - 8, y: rangeY, width: cellWidth + 16, height: 15), font: rangeFont, color: NSColor.white.withAlphaComponent(row.isCurrent ? 0.94 : 0.7))
            if row.isCapped {
                let rangeWidth = measuredTextWidth(row.shortRange, font: rangeFont)
                accentRose.setFill()
                NSBezierPath(ovalIn: NSRect(x: cellMidX + rangeWidth / 2 + 5, y: rangeY + 5, width: 5, height: 5)).fill()
            }
            drawCycleBadge(row: row, centerX: cellMidX, y: rangeY + 20, maxWidth: cellWidth - 8)
            quotaCycleHitAreas.append((rect: ringRect.insetBy(dx: -6, dy: -6), index: modelIndex))
        }

        // Older cycles as a dense mini-ring band, oldest first.
        let bandTop = ringTop + ringSide + 52
        let bandModels = Array(model.weeklyRows.dropFirst(6).reversed())
        if bandModels.isEmpty {
            drawText(t(.cycleBandGrowHint), rect: NSRect(x: rect.minX + 16, y: bandTop + 4, width: rect.width - 32, height: 15), font: .systemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.34))
        } else {
            drawText("\(t(.cycleEarlierBand)) (\(bandModels.count))", rect: NSRect(x: rect.minX + 16, y: bandTop, width: rect.width - 32, height: 15), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.44))
            let miniSide: CGFloat = 24
            let miniGap: CGFloat = 8
            let perRow = max(1, Int((rect.width - 32 + miniGap) / (miniSide + miniGap)))
            for (bandIndex, row) in bandModels.enumerated() {
                let modelIndex = model.weeklyRows.count - 1 - bandIndex
                let column = bandIndex % perRow
                let bandRow = bandIndex / perRow
                let miniRect = NSRect(
                    x: rect.minX + 16 + CGFloat(column) * (miniSide + miniGap),
                    y: bandTop + 22 + CGFloat(bandRow) * (miniSide + 8),
                    width: miniSide,
                    height: miniSide
                )
                let percent = max(0, min(100, row.percent))
                let color = cycleSeverityColor(percent)
                drawCycleRing(rect: miniRect, thickness: 4.5, percent: percent, color: row.isPartial ? color.withAlphaComponent(0.5) : color, highlighted: false)
                if hoveredQuotaCycleIndex == modelIndex {
                    NSColor.white.withAlphaComponent(0.65).setStroke()
                    let focus = NSBezierPath(ovalIn: miniRect.insetBy(dx: -2.5, dy: -2.5))
                    focus.lineWidth = 1
                    focus.stroke()
                }
                quotaCycleHitAreas.append((rect: miniRect.insetBy(dx: -4, dy: -4), index: modelIndex))
            }
        }

        var footnotes = [t(.cycleHistoryHint)]
        if model.hasBackfilledRows {
            footnotes.append("* \(t(.cycleBackfilled))")
        }
        if model.hasEarlyRefreshRows {
            footnotes.append(t(.cycleEarlyRefreshFootnote))
        }
        drawTruncatedText(footnotes.joined(separator: "   ·   "), rect: NSRect(x: rect.minX + 16, y: rect.maxY - 24, width: rect.width - 32, height: 14), font: .systemFont(ofSize: 10, weight: .medium), color: NSColor.white.withAlphaComponent(0.36))
    }

    func updateQuotaCycleHover(at point: CGPoint) {
        let match = quotaCycleHitAreas.first { $0.rect.contains(point) }
        let newIndex = match?.index
        if hoveredQuotaCycleIndex != newIndex {
            hoveredQuotaCycleIndex = newIndex
            needsDisplay = true
        }
    }

    func drawQuotaCycleTooltip(container: NSRect) {
        guard let index = hoveredQuotaCycleIndex,
              index >= 0, index < quotaCycleTooltipRows.count,
              let hit = quotaCycleHitAreas.first(where: { $0.index == index }) else {
            return
        }
        let row = quotaCycleTooltipRows[index]

        var lines: [(String, String, NSColor)] = []
        let percentColor = cycleSeverityColor(row.percent)
        var percentValue = "\(Int(round(row.percent)))%"
        if let usedMoney = row.usedMoneyValue {
            percentValue += " · \(displayMoney(usedMoney, source: quotaCycleSource))"
        }
        lines.append((row.isCurrent ? t(.used) : t(.cyclePeak), percentValue, percentColor))
        if let waste = row.wastedMoneyValue, waste >= 0.5 {
            lines.append((t(.cycleWasteLabel), displayMoney(waste, source: quotaCycleSource), accentRose.withAlphaComponent(0.92)))
        }
        if let value = row.moneyValue {
            lines.append((t(.cycleValueLabel), displayMoney(value, source: quotaCycleSource), NSColor.white.withAlphaComponent(0.88)))
        }
        if let tokenText = row.tokenText {
            lines.append(("Token", tokenText, NSColor.white.withAlphaComponent(0.9)))
        }
        if let apiCostText = row.apiCostText {
            lines.append((t(.apiEquivalent), apiCostText, accentTeal))
        }
        switch row.kind {
        case .current:
            lines.append((t(.reset), row.kindTimeText, NSColor.white.withAlphaComponent(0.88)))
        case .earlyRefresh:
            lines.append((t(.cycleEarlyRefresh), row.kindTimeText, accentBlue))
        case .scheduledReset:
            lines.append((t(.cycleNormalReset), row.kindTimeText, NSColor.white.withAlphaComponent(0.88)))
        }
        lines.append((t(.cycleDurationLabel), row.durationText, NSColor.white.withAlphaComponent(0.88)))
        let footerText: String? = row.isPartial ? "* \(t(.cycleBackfilled))" : nil

        let width: CGFloat = 238
        let height: CGFloat = 30 + CGFloat(lines.count) * 16 + (footerText != nil ? 18 : 8)
        let gap: CGFloat = 12
        var origin = CGPoint(x: hit.rect.midX - width / 2, y: hit.rect.minY - height - gap)
        if origin.y < container.minY + 10 {
            origin.y = hit.rect.maxY + gap
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

        drawText(row.fullRange, rect: NSRect(x: tooltipRect.minX + 10, y: tooltipRect.minY + 8, width: tooltipRect.width - 20, height: 14), font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.85))
        for (lineIndex, line) in lines.enumerated() {
            let y = tooltipRect.minY + 28 + CGFloat(lineIndex) * 16
            drawText(line.0, rect: NSRect(x: tooltipRect.minX + 10, y: y, width: 100, height: 14), font: .systemFont(ofSize: 10, weight: .medium), color: NSColor.white.withAlphaComponent(0.5))
            drawRight(line.1, rect: NSRect(x: tooltipRect.minX + 104, y: y - 1, width: tooltipRect.width - 114, height: 15), color: line.2, font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold))
        }
        if let footerText {
            drawText(footerText, rect: NSRect(x: tooltipRect.minX + 10, y: tooltipRect.maxY - 17, width: tooltipRect.width - 20, height: 12), font: .systemFont(ofSize: 9, weight: .medium), color: NSColor.white.withAlphaComponent(0.4))
        }
    }

    func drawFiveHourCycleStrip(model: QuotaCyclePageModel, rect: NSRect) {
        drawPanel(rect)
        drawText(t(.fiveHourCyclesTitle), rect: NSRect(x: rect.minX + 16, y: rect.minY + 14, width: 260, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        let summary = String(format: t(.cycleCappedFormat), model.cappedCount, model.fiveHourBars.count)
        drawRight(summary, rect: NSRect(x: rect.minX + 16, y: rect.minY + 18, width: rect.width - 32, height: 16), color: NSColor.white.withAlphaComponent(0.52), font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold))
        var hintText = t(.fiveHourCyclesHint)
        if let primary = model.limit?.primary, primary.windowMinutes > 0 {
            hintText += " · \(t(.cycleCurrentTitle)) \(t(.used)) \(Int(round(max(0, min(100, primary.usedPercent)))))%"
            if let resetsAt = primary.resetsAt {
                hintText += " · \(t(.reset)) \(compactResetRelative(resetsAt))"
            }
        }
        drawTruncatedText(hintText, rect: NSRect(x: rect.minX + 16, y: rect.minY + 38, width: rect.width - 32, height: 15), font: .systemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.44))

        guard !model.fiveHourBars.isEmpty else {
            drawText(t(.cycleNoHistory), rect: NSRect(x: rect.minX + 16, y: rect.minY + 76, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }

        let areaTop = rect.minY + 62
        let areaBottom = rect.maxY - 34
        let areaHeight = areaBottom - areaTop
        let areaX = rect.minX + 18
        let areaWidth = rect.width - 36
        let count = model.fiveHourBars.count
        let showsPerBarLabels = count <= 10
        let gap: CGFloat = count > 24 ? 4 : (showsPerBarLabels ? 14 : 6)
        let maxBarWidth: CGFloat = showsPerBarLabels ? 38 : 26
        let barWidth = min(maxBarWidth, (areaWidth - gap * CGFloat(max(count - 1, 0))) / CGFloat(count))
        let groupWidth = barWidth * CGFloat(count) + gap * CGFloat(max(count - 1, 0))
        let groupX = areaX + max(0, (areaWidth - groupWidth) / 2)
        let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        let labelColor = NSColor.white.withAlphaComponent(0.42)
        let tooltipIndexBase = quotaCycleTooltipRows.count

        for (index, bar) in model.fiveHourBars.enumerated() {
            let percent = max(0, min(100, bar.percent))
            let height = max(4, areaHeight * CGFloat(percent / 100))
            let barRect = NSRect(
                x: groupX + CGFloat(index) * (barWidth + gap),
                y: areaBottom - height,
                width: barWidth,
                height: height
            )
            cycleSeverityColor(percent).setFill()
            let path = NSBezierPath(roundedRect: barRect, xRadius: 2.5, yRadius: 2.5)
            path.fill()
            if bar.isCurrent {
                NSColor.white.withAlphaComponent(0.85).setStroke()
                path.lineWidth = 1.5
                path.stroke()
            }
            if bar.isEarlyRefresh {
                accentBlue.setFill()
                NSBezierPath(ovalIn: NSRect(x: barRect.midX - 2.5, y: barRect.minY - 10, width: 5, height: 5)).fill()
            }
            if hoveredQuotaCycleIndex == tooltipIndexBase + index {
                NSColor.white.withAlphaComponent(0.65).setStroke()
                let focus = NSBezierPath(roundedRect: barRect.insetBy(dx: -2.5, dy: -2.5), xRadius: 4, yRadius: 4)
                focus.lineWidth = 1
                focus.stroke()
            }
            if showsPerBarLabels {
                drawCentered(Self.cycleClockLabelFormatter.string(from: bar.resetAt), rect: NSRect(x: barRect.midX - 30, y: areaBottom + 8, width: 60, height: 14), font: labelFont, color: labelColor)
            }

            let start = bar.resetAt.addingTimeInterval(-Double(max(bar.windowMinutes, 1)) * 60)
            let endText = bar.isCurrent ? t(.cycleNow) : Self.cycleTimeLabelFormatter.string(from: bar.resetAt)
            let minutes = max(bar.windowMinutes, 1)
            let durationText = minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h\(minutes % 60)m"
            quotaCycleTooltipRows.append(QuotaCycleRowModel(
                shortRange: "",
                fullRange: "\(Self.cycleTimeLabelFormatter.string(from: start)) → \(endText)",
                kind: bar.isCurrent ? .current : (bar.isEarlyRefresh ? .earlyRefresh : .scheduledReset),
                badgeText: "",
                kindTimeText: Self.cycleTimeLabelFormatter.string(from: bar.resetAt),
                durationText: durationText,
                percent: percent,
                isCurrent: bar.isCurrent,
                isPartial: false,
                tokenText: bar.tokenText,
                apiCostText: nil
            ))
            quotaCycleHitAreas.append((
                rect: NSRect(x: barRect.minX - gap / 2, y: areaTop, width: barWidth + gap, height: areaBottom - areaTop + 6),
                index: tooltipIndexBase + index
            ))
        }

        if !showsPerBarLabels {
            if let first = model.fiveHourBars.first {
                drawText(Self.cycleDayLabelFormatter.string(from: first.resetAt), rect: NSRect(x: areaX, y: areaBottom + 8, width: 90, height: 14), font: labelFont, color: labelColor)
            }
            if let last = model.fiveHourBars.last, model.fiveHourBars.count > 1 {
                drawRight(Self.cycleDayLabelFormatter.string(from: last.resetAt), rect: NSRect(x: rect.maxX - 16 - 90, y: areaBottom + 8, width: 90, height: 14), color: labelColor, font: labelFont)
            }
        }
    }

    func drawCostPage(snapshot: DetailsSnapshot, content: NSRect) {
        let limit = sourceCostLimit(for: snapshot)
        let costSource = selectedDetailsSource
        let costData = costPageData(for: snapshot, limit: limit, year: selectedCostYear)
        let estimate = costData.estimate

        let summaryRect = NSRect(x: content.minX, y: content.minY + 78, width: content.width, height: 168)
        let settingsRect = NSRect(x: content.minX, y: summaryRect.maxY + 16, width: content.width, height: 244)
        let controlWidth = min(300, max(252, settingsRect.width * 0.34))
        let controlX = settingsRect.maxX - controlWidth - 16
        let labelX = settingsRect.minX + 16
        let leftColumnWidth = max(180, controlX - labelX - 24)
        let labelFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let centeredLabelY: (NSRect) -> CGFloat = { frame in
            frame.midY - 10
        }
        drawCostOverviewPanel(estimate: estimate, apiEstimate: costData.apiEstimate, source: costSource, rect: summaryRect)
        drawPanel(settingsRect)
        let planTitle = costSource == .all ? "\(t(.planCost)) · \(t(.all))" : "\(t(.planCost)) · \(costSource.shortTitle)"
        drawText(planTitle, rect: NSRect(x: settingsRect.minX + 16, y: settingsRect.minY + 14, width: 300, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        let monthlyLabelY = max(settingsRect.minY + 38, costAmountField.frame.midY - 12)
        drawText(t(.paymentMonthly), rect: NSRect(x: labelX, y: monthlyLabelY, width: leftColumnWidth, height: 20), font: labelFont, color: .white)
        drawMultilineText(t(.planCostHint), rect: NSRect(x: labelX, y: monthlyLabelY + 22, width: leftColumnWidth, height: 32), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.52))

        drawText(t(.paymentStartDate), rect: NSRect(x: labelX, y: centeredLabelY(paymentStartDayField.frame), width: leftColumnWidth, height: 20), font: labelFont, color: .white)
        drawText(t(.paymentCurrency), rect: NSRect(x: labelX, y: centeredLabelY(paymentCurrencyPopup.frame), width: leftColumnWidth, height: 20), font: labelFont, color: .white)
        drawText(t(.displayCurrency), rect: NSRect(x: labelX, y: centeredLabelY(displayCurrencyPopup.frame), width: leftColumnWidth, height: 20), font: labelFont, color: .white)
        drawInputFieldBackground(costAmountField.frame)
        drawInputFieldBackground(paymentStartDayField.frame)

        let chartY = settingsRect.maxY + 16
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
                visible.map { measuredTextWidth(displayMoney($0.usedValue, source: costSource), font: valueFont) }.max() ?? 0
            ) + 14
            let remainingW = max(
                measuredTextWidth(t(.remaining), font: headerFont),
                visible.map { measuredTextWidth(displayMoney(max(0, (estimate?.monthlyCost ?? AppSettings.monthlyPlanCost(for: costSource)) - $0.usedValue), source: costSource), font: valueFont) }.max() ?? 0
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
                let monthlyCost = estimate?.monthlyCost ?? AppSettings.monthlyPlanCost(for: costSource)
                drawRight(displayMoney(row.usedValue, source: costSource), rect: NSRect(x: usedX, y: rowY, width: usedW, height: 16), color: .white, font: valueFont)
                drawRight(displayMoney(max(0, monthlyCost - row.usedValue), source: costSource), rect: NSRect(x: remainingX, y: rowY, width: remainingW, height: 16), color: NSColor.white.withAlphaComponent(0.60), font: valueFont)
                drawRight(String(format: "%.0f%%", row.usedPercentOfPlan), rect: NSRect(x: percentX, y: rowY, width: percentW, height: 16), color: NSColor.white.withAlphaComponent(0.52), font: valueFont)
            }
        }
    }

    func drawProfileSelectedDayPanel(snapshot: DetailsSnapshot, report: TokenReport, rect: NSRect) {
        drawPanel(rect)
        let day = selectedCalendarDay(in: report)
        guard let day else {
            drawText(t(.noDaySelected), rect: NSRect(x: rect.minX + 18, y: rect.minY + 18, width: 220, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
            return
        }

        let localDay = snapshot.codex.byDay.first { $0.day == day.day }
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
            metrics.append((t(.apiEquivalent), compactDisplayAPIMoney(apiEstimate.usdValue), accentTeal, nil))
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

    func profileAPIDayEstimate(profileDay: DayUsage, localDay: DayUsage?) -> APICostEstimate {
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

    func drawSelectedDayPanel(snapshot: DetailsSnapshot, rect: NSRect) {
        drawPanel(rect)
        let report = calendarReport(for: snapshot)
        let day = selectedCalendarDay(in: report)
        guard let day else {
            drawText(t(.noDaySelected), rect: NSRect(x: rect.minX + 18, y: rect.minY + 18, width: 220, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
            return
        }

        drawText(day.day, rect: NSRect(x: rect.minX + 18, y: rect.minY + 18, width: 180, height: 24), font: .monospacedDigitSystemFont(ofSize: 17, weight: .bold), color: .white)
        drawText(compact(day.usage.total), rect: NSRect(x: rect.minX + 18, y: rect.minY + 48, width: 260, height: 34), font: .monospacedDigitSystemFont(ofSize: 28, weight: .bold), color: .systemGreen)
        let limit = sourceCostLimit(for: snapshot)
        let cost = planCostEstimate(
            report: report,
            selectedDay: day,
            limit: limit,
            quotaReferenceReport: sourceCostReferenceReport(for: snapshot),
            monthlyCost: AppSettings.monthlyPlanCost(for: selectedDetailsSource),
            paymentStartDay: AppSettings.paymentStartDay(for: selectedDetailsSource)
        )
        typealias DayMetric = (title: String, value: String, color: NSColor, infoAnchor: Bool, footer: String?)
        var metrics: [DayMetric] = [
            (t(.input), compact(day.usage.input), NSColor.systemGreen, false, nil),
            (t(.output), compact(day.usage.output), NSColor.systemCyan, false, nil),
            (t(.cached), compact(day.usage.cachedInput), NSColor.systemTeal, false, nil),
            (t(.totalEvents), format(Int64(day.events)), NSColor.systemOrange, false, nil)
        ]
        if let cost {
            metrics.append(("\(t(.weeklyQuotaShare)) ?", String(format: "%.1f%%", cost.selectedDayQuotaPercent), NSColor.systemGreen, true, nil))
        }
        let apiEstimate = APICostEstimator.estimate(day: day)
        if apiEstimate.hasPricedUsage {
            metrics.append((t(.apiEquivalent), compactDisplayAPIMoney(apiEstimate.usdValue), accentTeal, false, nil))
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
                dayQuotaShareInfoRect = card
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
        var leftColumnBottom = rect.minY + 112
        if let split = daySourceSplit(snapshot: snapshot, day: day) {
            drawDaySourceSplit(split, rect: NSRect(x: rect.minX + 18, y: rect.minY + 114, width: 274, height: 90))
            leftColumnBottom = rect.minY + daySourceSplitPanelExtent
        }
        let modelRows = max(1, day.modelBreakdown.count)
        let minimumModelHeight = 22 + CGFloat(modelRows) * 22
        let modelY = max(leftColumnBottom, metricsBottom + 12)
        let modelRect = NSRect(
            x: rect.minX + 18,
            y: modelY,
            width: rect.width - 36,
            height: max(minimumModelHeight, rect.maxY - modelY - 18)
        )
        drawSelectedDayModels(day.modelBreakdown, weeklyQuotaTotal: cost?.weeklyQuotaTotal, rect: modelRect)
    }

    func drawSelectedWeekPanel(snapshot: DetailsSnapshot, report: TokenReport, summary: ContributionWeekSummary, rect: NSRect) {
        drawPanel(rect)
        let weeks = contributionWeekColumns(in: report)
        let maxTotal = max(weeks.map { $0.total }.max() ?? 1, 1)
        let intensity = Double(summary.total) / Double(maxTotal)
        drawText(contributionWeekRangeLabel(summary), rect: NSRect(x: rect.minX + 18, y: rect.minY + 18, width: 274, height: 24), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
        drawText(compact(summary.total), rect: NSRect(x: rect.minX + 18, y: rect.minY + 48, width: 260, height: 34), font: .monospacedDigitSystemFont(ofSize: 28, weight: .bold), color: .systemGreen)
        var weekMeta = "\(summary.turns) \(t(.turns))  |  \(contributionWeekLabel(.activeDays)) \(summary.activeDays)/\(summary.days.count)"
        if isSingleCalendarWeek(summary) {
            weekMeta += "  |  \(Int(round(intensity * 100)))% \(t(.peakWeek))"
        }
        drawText(weekMeta, rect: NSRect(x: rect.minX + 18, y: rect.minY + 90, width: 420, height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(0.48))

        typealias WeekMetric = (title: String, value: String, color: NSColor, footer: String?)
        var metrics: [WeekMetric] = [
            (t(.input), compact(summary.usage.input), NSColor.systemGreen, nil),
            (t(.output), compact(summary.usage.output), NSColor.systemCyan, nil),
            (t(.cached), compact(summary.usage.cachedInput), NSColor.systemTeal, nil),
            (t(.fresh), compact(summary.usage.freshInput), NSColor.systemOrange, nil)
        ]
        if let planValue = contributionWeekPlanValue(summary) {
            metrics.append((contributionPlanAmountLabel(), displayMoney(planValue, source: selectedDetailsSource), NSColor.systemGreen, nil))
        }
        let apiEstimate = contributionWeekAPIEstimate(summary)
        if apiEstimate.hasPricedUsage {
            metrics.append((t(.apiEquivalent), compactDisplayAPIMoney(apiEstimate.usdValue), accentTeal, nil))
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
        var leftColumnBottom = rect.minY + 112
        if let split = weekSourceSplit(snapshot: snapshot, summary: summary) {
            drawDaySourceSplit(split, rect: NSRect(x: rect.minX + 18, y: rect.minY + 114, width: 274, height: 90))
            leftColumnBottom = rect.minY + daySourceSplitPanelExtent
        }
        let models = weekModelBreakdown(summary)
        let modelRows = max(1, models.count)
        let minimumModelHeight = 22 + CGFloat(modelRows) * 22
        let modelY = max(leftColumnBottom, metricsBottom + 12)
        let modelRect = NSRect(
            x: rect.minX + 18,
            y: modelY,
            width: rect.width - 36,
            height: max(minimumModelHeight, rect.maxY - modelY - 18)
        )
        let cost = planCostEstimate(
            report: report,
            selectedDay: nil,
            limit: sourceCostLimit(for: snapshot),
            quotaReferenceReport: sourceCostReferenceReport(for: snapshot),
            monthlyCost: AppSettings.monthlyPlanCost(for: selectedDetailsSource),
            paymentStartDay: AppSettings.paymentStartDay(for: selectedDetailsSource)
        )
        drawSelectedDayModels(models, weeklyQuotaTotal: cost?.weeklyQuotaTotal, rect: modelRect)
    }

    func weekModelBreakdown(_ summary: ContributionWeekSummary) -> [ModelUsage] {
        var byName: [String: ModelUsage] = [:]
        for day in summary.days {
            for model in day.modelBreakdown {
                if var existing = byName[model.name] {
                    existing.usage.add(model.usage)
                    existing.turns += model.turns
                    existing.events += model.events
                    existing.sessions += model.sessions
                    byName[model.name] = existing
                } else {
                    byName[model.name] = model
                }
            }
        }
        return byName.values.sorted { $0.usage.total > $1.usage.total }
    }

    func weekSourceSplit(snapshot: DetailsSnapshot, summary: ContributionWeekSummary) -> (codex: Int64, claude: Int64)? {
        let visible = Set(QuotaViewOption.visiblePlatformCases)
        guard selectedDetailsSource == .all, visible.contains(.codex), visible.contains(.claude) else { return nil }
        let selectedDays = Set(summary.days.map(\.day))
        let codex = snapshot.codex.byDay
            .filter { selectedDays.contains($0.day) }
            .reduce(Int64(0)) { $0 + $1.usage.total }
        let claude = snapshot.claude.byDay
            .filter { selectedDays.contains($0.day) }
            .reduce(Int64(0)) { $0 + $1.usage.total }
        guard codex + claude > 0 else { return nil }
        return (codex, claude)
    }

    var daySourceSplitPanelExtent: CGFloat { 216 }

    func daySourceSplit(snapshot: DetailsSnapshot, day: DayUsage) -> (codex: Int64, claude: Int64)? {
        let visible = Set(QuotaViewOption.visiblePlatformCases)
        guard selectedDetailsSource == .all, visible.contains(.codex), visible.contains(.claude) else { return nil }
        let codex = snapshot.codex.byDay.first { $0.day == day.day }?.usage.total ?? 0
        let claude = snapshot.claude.byDay.first { $0.day == day.day }?.usage.total ?? 0
        guard codex + claude > 0 else { return nil }
        return (codex, claude)
    }

    func drawDaySourceSplit(_ split: (codex: Int64, claude: Int64), rect: NSRect) {
        let codexColor = NSColor(calibratedRed: 0.45, green: 0.50, blue: 1.00, alpha: 1.0)
        let claudeColor = NSColor(calibratedRed: 0.898, green: 0.420, blue: 0.278, alpha: 1.0)
        let total = Double(split.codex + split.claude)
        let codexShare = CGFloat(Double(split.codex) / total)

        drawText(t(.sourceSplit), rect: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 16), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.46))

        let ringSize: CGFloat = 64
        let lineWidth: CGFloat = 12
        let ringRect = NSRect(x: rect.minX, y: rect.minY + 22, width: ringSize, height: ringSize)
        let center = NSPoint(x: ringRect.midX, y: ringRect.midY)
        let radius = ringSize / 2 - lineWidth / 2

        if codexShare >= 1 || codexShare <= 0 {
            let path = NSBezierPath(ovalIn: ringRect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
            path.lineWidth = lineWidth
            (codexShare >= 1 ? codexColor : claudeColor).setStroke()
            path.stroke()
        } else {
            let start: CGFloat = -90
            let boundary = start + 360 * codexShare
            for (from, to, color) in [(start, boundary, codexColor), (boundary, start + 360, claudeColor)] {
                let path = NSBezierPath()
                path.appendArc(withCenter: center, radius: radius, startAngle: from, endAngle: to, clockwise: false)
                path.lineWidth = lineWidth
                color.setStroke()
                path.stroke()
            }
        }

        let legendX = ringRect.maxX + 14
        let legendW = max(0, rect.maxX - legendX)
        let rows: [(name: String, value: Int64, share: CGFloat, color: NSColor)] = [
            ("Codex", split.codex, codexShare, codexColor),
            ("Claude", split.claude, 1 - codexShare, claudeColor)
        ]
        for (index, row) in rows.enumerated() {
            let y = ringRect.minY + 8 + CGFloat(index) * 28
            row.color.setFill()
            NSBezierPath(ovalIn: NSRect(x: legendX, y: y + 4, width: 8, height: 8)).fill()
            drawText(row.name, rect: NSRect(x: legendX + 14, y: y, width: 70, height: 16), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.78))
            let valueText = "\(compact(row.value)) · \(String(format: "%.1f%%", row.share * 100))"
            drawRight(valueText, rect: NSRect(x: legendX + 84, y: y, width: max(0, legendW - 84), height: 16), color: row.color, font: .monospacedDigitSystemFont(ofSize: 11, weight: .bold))
        }
    }

    func drawSelectedDayModels(_ models: [ModelUsage], weeklyQuotaTotal: Double? = nil, rect: NSRect) {
        drawText(t(.models), rect: NSRect(x: rect.minX, y: rect.minY, width: 120, height: 18), font: .systemFont(ofSize: 13, weight: .bold), color: .white)
        guard !models.isEmpty else {
            drawText(t(.noModelLabelForDay), rect: NSRect(x: rect.minX, y: rect.minY + 24, width: rect.width, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.46))
            return
        }

        let maxTotal = max(models.map { $0.usage.total }.max() ?? 1, 1)
        let showsTokenBreakdown = rect.width >= 760
        let showsFullActivity = rect.width >= 900
        let showsQuotaShare = rect.width >= 1_040
        var columnX = rect.maxX
        func allocateColumn(slotWidth: CGFloat) -> CGFloat {
            columnX -= slotWidth
            return columnX
        }

        let costX = allocateColumn(slotWidth: 92)
        let quotaX = showsQuotaShare ? allocateColumn(slotWidth: 82) : nil
        let totalX = allocateColumn(slotWidth: 88)
        let outputX = showsTokenBreakdown ? allocateColumn(slotWidth: 88) : nil
        let inputX = showsTokenBreakdown ? allocateColumn(slotWidth: 90) : nil
        let eventsX = allocateColumn(slotWidth: 78)
        let sessionsX = allocateColumn(slotWidth: 64)
        let turnsX = showsFullActivity ? allocateColumn(slotWidth: 64) : nil
        let availableNameWidth = max(96, columnX - rect.minX - 12)
        let nameW = min(min(220, rect.width * 0.30), availableNameWidth)
        let barX = rect.minX + nameW + 18
        let barW = max(0, columnX - barX - 12)
        if let turnsX {
            drawRight(t(.turns), rect: NSRect(x: turnsX, y: rect.minY, width: 56, height: 18), color: NSColor.white.withAlphaComponent(0.42), font: .systemFont(ofSize: 10, weight: .bold))
        }
        drawRight(t(.sessions), rect: NSRect(x: sessionsX, y: rect.minY, width: 56, height: 18), color: NSColor.white.withAlphaComponent(0.42), font: .systemFont(ofSize: 10, weight: .bold))
        drawRight(t(.totalEvents), rect: NSRect(x: eventsX, y: rect.minY, width: 70, height: 18), color: NSColor.white.withAlphaComponent(0.42), font: .systemFont(ofSize: 10, weight: .bold))
        if let inputX, let outputX {
            drawRight(t(.input), rect: NSRect(x: inputX, y: rect.minY, width: 80, height: 18), color: NSColor.white.withAlphaComponent(0.42), font: .systemFont(ofSize: 10, weight: .bold))
            drawRight(t(.output), rect: NSRect(x: outputX, y: rect.minY, width: 80, height: 18), color: NSColor.white.withAlphaComponent(0.42), font: .systemFont(ofSize: 10, weight: .bold))
        }
        drawRight(t(.total), rect: NSRect(x: totalX, y: rect.minY, width: 82, height: 18), color: NSColor.white.withAlphaComponent(0.42), font: .systemFont(ofSize: 10, weight: .bold))
        if let quotaX {
            drawRight(t(.weeklyQuotaShare), rect: NSRect(x: quotaX, y: rect.minY, width: 74, height: 18), color: NSColor.white.withAlphaComponent(0.42), font: .systemFont(ofSize: 10, weight: .bold))
        }
        drawRight(t(.apiEquivalent), rect: NSRect(x: costX, y: rect.minY, width: 92, height: 18), color: NSColor.white.withAlphaComponent(0.42), font: .systemFont(ofSize: 10, weight: .bold))
        for (index, model) in models.enumerated() {
            let y = rect.minY + 22 + CGFloat(index) * 22
            guard y + 18 <= rect.maxY else { break }
            drawText(model.name, rect: NSRect(x: rect.minX, y: y + 1, width: nameW, height: 16), font: .systemFont(ofSize: 10.5, weight: .semibold), color: .white)

            if barW >= 18 {
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

            if let turnsX {
                drawRight(format(Int64(model.turns)), rect: NSRect(x: turnsX, y: y + 1, width: 56, height: 16), color: NSColor.white.withAlphaComponent(0.70))
            }
            drawRight(format(Int64(model.sessions)), rect: NSRect(x: sessionsX, y: y + 1, width: 56, height: 16), color: NSColor.white.withAlphaComponent(0.70))
            drawRight(format(Int64(model.events)), rect: NSRect(x: eventsX, y: y + 1, width: 70, height: 16), color: NSColor.systemOrange)
            if let inputX, let outputX {
                drawRight(compact(model.usage.input), rect: NSRect(x: inputX, y: y + 1, width: 80, height: 16), color: .systemGreen)
                drawRight(compact(model.usage.output), rect: NSRect(x: outputX, y: y + 1, width: 80, height: 16), color: .systemCyan)
            }
            drawRight(compact(model.usage.total), rect: NSRect(x: totalX, y: y + 1, width: 82, height: 16), color: .white)
            let quotaText: String
            if let weeklyQuotaTotal, weeklyQuotaTotal > 0 {
                quotaText = String(format: "%.2f%%", Double(model.usage.total) / weeklyQuotaTotal * 100)
            } else {
                quotaText = "—"
            }
            let quotaColor = (weeklyQuotaTotal ?? 0) > 0 ? NSColor.systemGreen : NSColor.white.withAlphaComponent(0.38)
            if let quotaX {
                drawRight(quotaText, rect: NSRect(x: quotaX, y: y + 1, width: 74, height: 16), color: quotaColor)
            }
            let modelCost = APICostEstimator.estimate(usage: model.usage, modelName: model.name)
            let costText = modelCost.hasPricedUsage ? compactDisplayAPIMoney(modelCost.usdValue) : "—"
            drawRight(costText, rect: NSRect(x: costX, y: y + 1, width: 92, height: 16), color: modelCost.hasPricedUsage ? accentTeal : NSColor.white.withAlphaComponent(0.38))
        }
    }

}
