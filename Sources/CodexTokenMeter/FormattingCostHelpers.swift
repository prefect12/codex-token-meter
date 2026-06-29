import Cocoa
import Foundation
import ServiceManagement
import UserNotifications

// MARK: - Formatting And Cost Helpers

func format(_ value: Int64) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
}

func compact(_ value: Int64) -> String {
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

func compactDashboardTotal(_ value: Int64) -> String {
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

func compactDashboardMetric(_ value: Int64) -> String {
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

func money(_ value: Double, currency: CurrencyCode) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = value >= 100 ? 0 : min(currency.fractionDigits, 2)
    formatter.maximumFractionDigits = value >= 100 ? 0 : currency.fractionDigits
    let formatted = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    return "\(currency.rawValue) \(formatted)"
}

func compactMoney(_ value: Double, currency: CurrencyCode) -> String {
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

func paymentMoney(_ value: Double) -> String {
    money(value, currency: AppSettings.paymentCurrency)
}

func paymentMoney(_ value: Double, source: QuotaViewOption) -> String {
    money(value, currency: AppSettings.paymentCurrency(for: source))
}

func paymentAmount(_ value: Double, currency: CurrencyCode = AppSettings.paymentCurrency) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.groupingSeparator = ","
    formatter.usesGroupingSeparator = true
    formatter.minimumFractionDigits = value >= 100 ? 0 : min(currency.fractionDigits, 2)
    formatter.maximumFractionDigits = value >= 100 ? 0 : currency.fractionDigits
    return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
}

func paymentAmount(_ value: Double, source: QuotaViewOption) -> String {
    paymentAmount(value, currency: AppSettings.paymentCurrency(for: source))
}

func displayMoney(_ paymentValue: Double) -> String {
    let converted = convertCurrency(paymentValue, from: AppSettings.paymentCurrency, to: AppSettings.displayCurrency)
    return money(converted, currency: AppSettings.displayCurrency)
}

func displayMoney(_ paymentValue: Double, source: QuotaViewOption) -> String {
    let converted = convertCurrency(paymentValue, from: AppSettings.paymentCurrency(for: source), to: AppSettings.displayCurrency(for: source))
    return money(converted, currency: AppSettings.displayCurrency(for: source))
}

func displayAPIMoney(_ usdValue: Double) -> String {
    let converted = convertCurrency(usdValue, from: .usd, to: AppSettings.displayCurrency)
    return money(converted, currency: AppSettings.displayCurrency)
}

func displayAPIMoney(_ usdValue: Double, source: QuotaViewOption) -> String {
    let converted = convertCurrency(usdValue, from: .usd, to: AppSettings.displayCurrency(for: source))
    return money(converted, currency: AppSettings.displayCurrency(for: source))
}

func compactDisplayAPIMoney(_ usdValue: Double) -> String {
    let converted = convertCurrency(usdValue, from: .usd, to: AppSettings.displayCurrency)
    return compactMoney(converted, currency: AppSettings.displayCurrency)
}

func todayKey() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date())
}

func appCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.firstWeekday = 2
    return calendar
}

func dayFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}

func shortMonthDayFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    formatter.dateFormat = "MM-dd"
    return formatter
}

func shortMonthDayTimeFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    formatter.dateFormat = "MM-dd HH:mm"
    return formatter
}

func cycleRangeTitle(start: Date?, end: Date?, fallback: String, formatter: DateFormatter) -> String {
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

func isShortCostCycle(start: Date, end: Date) -> Bool {
    let duration = end.timeIntervalSince(start)
    let fullWeek: TimeInterval = 7 * 24 * 60 * 60
    return duration > 0 && duration < fullWeek - 60
}

func effectivePaymentStartDay(in report: TokenReport?, paymentStartDay: String? = AppSettings.paymentStartDay) -> String {
    let parser = dayFormatter()
    if let stored = paymentStartDay,
       parser.date(from: stored) != nil {
        return stored
    }
    return report?.byDay.map(\.day).sorted().first ?? todayKey()
}

func availableCostYears(from report: TokenReport?, paymentStartDay: String? = AppSettings.paymentStartDay) -> [Int] {
    let currentYear = Calendar.current.component(.year, from: Date())
    let startDay = effectivePaymentStartDay(in: report, paymentStartDay: paymentStartDay)
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

func weekStarts(for year: Int) -> [Date] {
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

func weeklyAPICostBuckets(days: [DayUsage], startDay: String) -> [Date: APICostEstimate] {
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

func proportionalAPICostUSD(estimate: APICostEstimate, usedValue: Double, totalUsedValue: Double) -> Double? {
    guard estimate.hasPricedUsage else { return nil }
    guard totalUsedValue > 0 else { return estimate.usdValue }
    return estimate.usdValue * max(0, usedValue) / totalUsedValue
}

func weeklySpendRows(report: TokenReport, limit: LiveRateLimit?, year: Int? = nil, quotaReferenceReport: TokenReport? = nil, monthlyCost: Double = AppSettings.monthlyPlanCost, paymentStartDay: String? = AppSettings.paymentStartDay) -> [CostPeriodRow] {
    guard let estimator = CostEstimator(report: report, limit: limit, quotaReferenceReport: quotaReferenceReport, monthlyCost: monthlyCost, paymentStartDay: paymentStartDay),
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

func monthlyCostRows(report: TokenReport, limit: LiveRateLimit?, year: Int? = nil, quotaReferenceReport: TokenReport? = nil, monthlyCost: Double = AppSettings.monthlyPlanCost, paymentStartDay: String? = AppSettings.paymentStartDay) -> [CostPeriodRow] {
    guard let estimator = CostEstimator(report: report, limit: limit, quotaReferenceReport: quotaReferenceReport, monthlyCost: monthlyCost, paymentStartDay: paymentStartDay),
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

func monthlySpendRows(report: TokenReport, limit: LiveRateLimit?, year: Int? = nil, quotaReferenceReport: TokenReport? = nil, monthlyCost: Double = AppSettings.monthlyPlanCost, paymentStartDay: String? = AppSettings.paymentStartDay) -> [MonthlySpendRow] {
    guard let estimator = CostEstimator(report: report, limit: limit, quotaReferenceReport: quotaReferenceReport, monthlyCost: monthlyCost, paymentStartDay: paymentStartDay),
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

func planCostEstimate(report: TokenReport, selectedDay: DayUsage?, limit: LiveRateLimit?, quotaReferenceReport: TokenReport? = nil, monthlyCost: Double = AppSettings.monthlyPlanCost, paymentStartDay: String? = AppSettings.paymentStartDay) -> PlanCostEstimate? {
    guard let estimator = CostEstimator(report: report, limit: limit, quotaReferenceReport: quotaReferenceReport, monthlyCost: monthlyCost, paymentStartDay: paymentStartDay) else { return nil }

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

func relative(_ date: Date?) -> String {
    guard let date else { return "--" }
    return relative(date)
}

func compactResetRelative(_ date: Date?) -> String {
    guard let date else { return "--" }
    return compactResetRelative(date)
}

func compactResetRelative(_ date: Date) -> String {
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

func relative(_ date: Date) -> String {
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
