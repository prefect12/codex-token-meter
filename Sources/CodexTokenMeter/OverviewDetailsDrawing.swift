import Cocoa

final class WeeklyQuotaHoverOverlayView: NSView {
    struct Row {
        let label: String
        let value: String
        let color: NSColor
    }

    private var title = ""
    private var rows: [Row] = []
    private var contentID = ""

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(title: String, rows: [Row], contentID: String, origin: CGPoint) {
        let contentChanged = self.contentID != contentID
        self.title = title
        self.rows = rows
        self.contentID = contentID

        let size = NSSize(width: 286, height: CGFloat(34 + rows.count * 17 + 8))
        if frame.size != size { setFrameSize(size) }
        if frame.origin != origin { setFrameOrigin(origin) }
        isHidden = false
        if contentChanged { needsDisplay = true }
    }

    func hide() {
        guard !isHidden else { return }
        isHidden = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.055, alpha: 0.97).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        border.lineWidth = 1
        border.stroke()

        drawText(title, rect: NSRect(x: 10, y: 8, width: bounds.width - 20, height: 16), font: .systemFont(ofSize: 11, weight: .bold), color: .white)
        for (index, row) in rows.enumerated() {
            let y = CGFloat(31 + index * 17)
            drawText(row.label, rect: NSRect(x: 10, y: y, width: 70, height: 14), font: .systemFont(ofSize: 10, weight: .medium), color: NSColor.white.withAlphaComponent(0.5))
            drawText(row.value, rect: NSRect(x: 84, y: y - 1, width: bounds.width - 94, height: 15), font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold), color: row.color, alignment: .right)
        }
    }

    private func drawText(_ text: String, rect: NSRect, font: NSFont, color: NSColor, alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: rect, withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
    }
}

extension UsageDetailsView {
    func drawOverview(snapshot: DetailsSnapshot, content: NSRect) {
        // Reset credits are a Codex-only concept, so hide the row in the Claude view
        // and pull the panels below it up to fill the gap.
        let showResetCredits = selectedDetailsSource == .all || selectedDetailsSource == .codex
        let cardsY = content.minY + 78
        let cardsHeight: CGFloat = 176
        let resetY = cardsY + cardsHeight + 16
        let resetHeight = resetCreditPanelHeight(for: snapshot)
        let quotaY = showResetCredits ? resetY + resetHeight + 16 : resetY
        let modelsY = quotaY + 136
        let gridY = modelsY + 146
        let gridReport = calendarReport(for: snapshot)
        let gridTitle = usesProfileAPIReport(for: snapshot)
            ? "\(t(.pastYear)) · \(t(.profileAPISource))"
            : t(.pastYear)
        drawMetricCards(snapshot: snapshot, content: content)
        if showResetCredits {
            drawResetCreditCountdownRow(snapshot: snapshot, content: content, y: resetY, height: resetHeight)
        }
        drawQuotaRows(snapshot: snapshot, content: content, y: quotaY, height: 120)
        drawModelRows(snapshot: snapshot, content: content, y: modelsY, height: 130, maxRows: 4)
        let gridHeight = contributionGridPreferredHeight(report: gridReport, width: content.width, compact: true)
        let gridRect = NSRect(x: content.minX, y: gridY, width: content.width, height: min(gridHeight, max(168, content.maxY - gridY)))
        drawContributionGrid(report: gridReport, rect: gridRect, title: gridTitle, compact: true)
    }

    func overviewResetCreditRect(snapshot: DetailsSnapshot, content: NSRect) -> NSRect? {
        guard selectedSection == .overview,
              selectedDetailsSource == .all || selectedDetailsSource == .codex else {
            return nil
        }
        let cardsY = content.minY + 78
        let cardsHeight: CGFloat = 176
        let resetY = cardsY + cardsHeight + 16
        return NSRect(
            x: content.minX,
            y: resetY,
            width: content.width,
            height: resetCreditPanelHeight(for: snapshot)
        )
    }

    func resetCreditPanelHeight(for snapshot: DetailsSnapshot) -> CGFloat {
        let columns = 3
        let availableCount = max(0, snapshot.resetCredits?.availableCount ?? 0)
        let rowCount = max(1, (availableCount + columns - 1) / columns)
        return 88 + CGFloat(rowCount - 1) * 52
    }

    func drawMetricCards(snapshot: DetailsSnapshot, content: NSRect) {
        let gap: CGFloat = 12
        let cardsY = content.minY + 78
        let cardsHeight: CGFloat = 176
        let quotaCardWidth = min(440, max(320, content.width * 0.40))
        let quotaRect = NSRect(x: content.minX, y: cardsY, width: quotaCardWidth, height: cardsHeight)
        drawWeeklyQuotaSummary(snapshot: snapshot, rect: quotaRect)

        let report = sourceReport(for: snapshot)
        let apiEstimate = APICostEstimator.estimate(report: report)
        let displayCurrency = AppSettings.displayCurrency(for: selectedDetailsSource)
        let apiMoney = compactMoney(convertCurrency(apiEstimate.usdValue, from: .usd, to: displayCurrency), currency: displayCurrency)
        let cards: [(title: String, value: String, subtitle: String?, color: NSColor)]
        switch selectedDetailsSource {
        case .all:
            let platformCards: [(String, String, String?, NSColor)] = QuotaViewOption.visiblePlatformCases.map { source in
                let sourceReport = sourceReport(for: snapshot, source: source)
                switch source {
                case .codex: return (t(.codex), compactDashboardTotal(sourceReport.usage.total), nil, .systemCyan)
                case .claude: return (t(.claude), compactDashboardTotal(sourceReport.usage.total), nil, .systemOrange)
                case .api: return ("API", compactDashboardTotal(sourceReport.usage.total), nil, accentTeal)
                case .all: return (detailsSourceTitle(.all), compactDashboardTotal(report.usage.total), nil, .systemGreen)
                }
            }
            cards = [
                (detailsSourceTitle(.all), compactDashboardTotal(report.usage.total), nil, .systemGreen)
            ] + platformCards + [
                (t(.cache), String(format: "%.0f%%", report.usage.cachePercent), nil, .systemTeal),
                (t(.apiEquivalent), apiMoney, nil, accentTeal)
            ]
        case .codex:
            cards = [
                (t(.codex), compactDashboardTotal(report.usage.total), nil, .systemCyan),
                (t(.input), compactDashboardMetric(report.usage.input), nil, .systemGreen),
                (t(.output), compactDashboardMetric(report.usage.output), nil, .systemOrange),
                (t(.cache), String(format: "%.0f%%", report.usage.cachePercent), nil, .systemTeal),
                (t(.apiEquivalent), apiMoney, nil, accentTeal)
            ]
        case .claude:
            cards = [
                (t(.claude), compactDashboardTotal(report.usage.total), nil, .systemOrange),
                (t(.input), compactDashboardMetric(report.usage.input), nil, .systemGreen),
                (t(.output), compactDashboardMetric(report.usage.output), nil, .systemCyan),
                (t(.cache), String(format: "%.0f%%", report.usage.cachePercent), nil, .systemTeal),
                (t(.apiEquivalent), apiMoney, nil, accentTeal)
            ]
        case .api:
            cards = [
                ("API", compactDashboardTotal(report.usage.total), nil, .systemCyan),
                (t(.input), compactDashboardMetric(report.usage.input), nil, .systemGreen),
                (t(.output), compactDashboardMetric(report.usage.output), nil, .systemOrange),
                (t(.cache), String(format: "%.0f%%", report.usage.cachePercent), nil, .systemTeal),
                (t(.externalAPICost), apiMoney, nil, accentAmber)
            ]
        }
        let metricsX = quotaRect.maxX + gap
        let metricsWidth = content.maxX - metricsX
        let rowHeight = (cardsHeight - gap) / 2
        for (index, card) in cards.enumerated() {
            let row = index < 3 ? 0 : 1
            let indexInRow = row == 0 ? index : index - 3
            let columnCount = row == 0 ? 3 : max(1, cards.count - 3)
            let cardW = (metricsWidth - gap * CGFloat(columnCount - 1)) / CGFloat(columnCount)
            let rect = NSRect(
                x: metricsX + CGFloat(indexInRow) * (cardW + gap),
                y: cardsY + CGFloat(row) * (rowHeight + gap),
                width: cardW,
                height: rowHeight
            )
            drawPanel(rect)
            let valueFontSize: CGFloat = cardW < 136 ? 17 : (cardW < 176 ? 20 : 22)
            let titleFontSize: CGFloat = cardW < 136 ? 10.5 : 11.5
            drawText(card.title, rect: NSRect(x: rect.minX + 14, y: rect.minY + 12, width: rect.width - 28, height: 18), font: .systemFont(ofSize: titleFontSize, weight: .semibold), color: NSColor.white.withAlphaComponent(0.52))
            let valueY = card.subtitle == nil ? rect.minY + 34 : rect.minY + 31
            let valueRect = NSRect(x: rect.minX + 14, y: valueY, width: rect.width - 28, height: 28)
            let valueFont = metricCardValueFont(text: card.value, maxWidth: valueRect.width, preferredSize: valueFontSize)
            drawText(card.value, rect: valueRect, font: valueFont, color: card.color)
            if let subtitle = card.subtitle {
                drawText(subtitle, rect: NSRect(x: rect.minX + 14, y: rect.minY + 60, width: rect.width - 28, height: 15), font: .systemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.46))
            }
        }
    }

    func drawWeeklyQuotaSummary(snapshot: DetailsSnapshot, rect: NSRect) {
        drawPanel(rect)
        if selectedDetailsSource == .api {
            let report = sourceReport(for: snapshot, source: .api)
            let estimate = APICostEstimator.estimate(report: report)
            drawText("API", rect: NSRect(x: rect.minX + 14, y: rect.minY + 18, width: rect.width - 28, height: 20), font: .systemFont(ofSize: 14, weight: .bold), color: accentTeal)
            drawText("\(t(.total))  \(compactDashboardTotal(report.usage.total))", rect: NSRect(x: rect.minX + 14, y: rect.minY + 58, width: rect.width - 28, height: 28), font: .monospacedDigitSystemFont(ofSize: 24, weight: .bold), color: .white)
            let cost = estimate.hasPricedUsage ? displayAPIMoney(estimate.usdValue, source: .api) : "--"
            drawText("\(t(.externalAPICost))  \(cost)", rect: NSRect(x: rect.minX + 14, y: rect.minY + 108, width: rect.width - 28, height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(0.58))
            return
        }
        let quotaSources: [QuotaViewOption]
        if selectedDetailsSource == .all {
            quotaSources = QuotaViewOption.visiblePlatformCases.filter { $0 == .codex || $0 == .claude }
        } else {
            quotaSources = [selectedDetailsSource].filter { $0 == .codex || $0 == .claude }
        }
        let rowHeight = rect.height / CGFloat(max(1, quotaSources.count))
        for (index, source) in quotaSources.enumerated() {
            if index > 0 {
                NSColor.white.withAlphaComponent(0.08).setFill()
                NSRect(x: rect.minX + 14, y: rect.minY + CGFloat(index) * rowHeight, width: rect.width - 28, height: 1).fill()
            }
            let window = snapshot.liveLimits.first(where: { $0.id == source.liveLimitID })?.secondary
            drawWeeklyQuotaRow(
                source: source,
                title: weeklyQuotaTitle(source: source),
                window: window,
                color: source == .codex ? accentBlue : accentAmber,
                rect: NSRect(x: rect.minX, y: rect.minY + CGFloat(index) * rowHeight, width: rect.width, height: rowHeight)
            )
        }
    }

    func drawWeeklyQuotaRow(
        source: QuotaViewOption,
        title: String,
        window: RateWindow?,
        color: NSColor,
        rect: NSRect
    ) {
        weeklyQuotaHitAreas.append((rect: rect, source: source))
        let horizontalPadding: CGFloat = 14
        drawText(
            title,
            rect: NSRect(x: rect.minX + horizontalPadding, y: rect.minY + 10, width: rect.width - horizontalPadding * 2, height: 17),
            font: .systemFont(ofSize: 12, weight: .semibold),
            color: NSColor.white.withAlphaComponent(0.78)
        )

        let normalizedPercent = window.map { min(100, max(0, $0.remainingPercent)) }
        let value = normalizedPercent.map { String(format: "%.0f%%", $0) } ?? "--%"
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 26, weight: .bold)
        let valueRect = NSRect(x: rect.minX + horizontalPadding, y: rect.minY + 29, width: rect.width - horizontalPadding * 2, height: 31)
        drawText(value, rect: valueRect, font: valueFont, color: normalizedPercent == nil ? NSColor.white.withAlphaComponent(0.36) : color)
        let suffixX = valueRect.minX + measuredTextWidth(value, font: valueFont) + 10
        drawText(
            t(.remaining),
            rect: NSRect(x: suffixX, y: valueRect.minY + 6, width: max(0, valueRect.maxX - suffixX), height: 20),
            font: .systemFont(ofSize: 12, weight: .semibold),
            color: NSColor.white.withAlphaComponent(0.64)
        )

        let trackRect = NSRect(x: rect.minX + horizontalPadding, y: rect.minY + 61, width: rect.width - horizontalPadding * 2, height: 7)
        NSColor.black.withAlphaComponent(0.28).setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: trackRect.height / 2, yRadius: trackRect.height / 2).fill()
        if let normalizedPercent, normalizedPercent > 0 {
            let fillRect = NSRect(x: trackRect.minX, y: trackRect.minY, width: max(trackRect.height, trackRect.width * normalizedPercent / 100), height: trackRect.height)
            color.setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: fillRect.height / 2, yRadius: fillRect.height / 2).fill()
        }
        if let window, let comparison = paceComparison(for: window) {
            let expectedRemaining = min(100, max(0, 100 - comparison.progressPercent))
            let markerCenterX = min(
                trackRect.maxX - 1.5,
                max(trackRect.minX + 1.5, trackRect.minX + trackRect.width * expectedRemaining / 100)
            )
            let actualRemaining = min(100, max(0, window.remainingPercent))
            let markerColor = actualRemaining >= expectedRemaining
                ? NSColor(calibratedRed: 0.56, green: 1.0, blue: 0.16, alpha: 0.98)
                : NSColor.systemYellow.withAlphaComponent(0.98)
            let markerRect = NSRect(
                x: markerCenterX - 1.5,
                y: trackRect.minY - 4,
                width: 3,
                height: trackRect.height + 8
            )
            markerColor.setFill()
            NSBezierPath(roundedRect: markerRect, xRadius: 1.5, yRadius: 1.5).fill()
        }

        let resetText = window?.resetsAt.map {
            "\(shortMonthDayTimeFormatter().string(from: $0)) \(t(.reset))"
        } ?? t(.liveLimitUnavailable)
        drawText(
            resetText,
            rect: NSRect(x: rect.minX + horizontalPadding, y: rect.minY + 71, width: rect.width - horizontalPadding * 2, height: 15),
            font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
            color: NSColor.white.withAlphaComponent(0.43)
        )
    }

    func weeklyQuotaTitle(source: QuotaViewOption) -> String {
        switch AppLanguage.current {
        case .chinese:
            return source == .codex ? "Codex 一周剩余" : "Claude 一周剩余"
        case .traditionalChinese:
            return source == .codex ? "Codex 一週剩餘" : "Claude 一週剩餘"
        case .japanese:
            return source == .codex ? "Codex 週間残量" : "Claude 週間残量"
        default:
            return source == .codex ? "Codex Weekly Remaining" : "Claude Weekly Remaining"
        }
    }

    func updateWeeklyQuotaHover(at point: CGPoint) {
        guard selectedSection == .overview else {
            if hoveredWeeklyQuotaSource != nil || weeklyQuotaHoverPoint != nil {
                hoveredWeeklyQuotaSource = nil
                weeklyQuotaHoverPoint = nil
            }
            weeklyQuotaHoverOverlay.hide()
            return
        }
        let source = weeklyQuotaHitAreas.first { $0.rect.contains(point) }?.source
        let hoverPoint = source == nil ? nil : point
        hoveredWeeklyQuotaSource = source
        weeklyQuotaHoverPoint = hoverPoint
        guard source != nil else {
            weeklyQuotaHoverOverlay.hide()
            return
        }
        updateWeeklyQuotaHoverOverlay()
    }

    func updateWeeklyQuotaHoverOverlay() {
        guard let source = hoveredWeeklyQuotaSource,
              let anchor = weeklyQuotaHoverPoint,
              let snapshot else {
            weeklyQuotaHoverOverlay.hide()
            return
        }
        let limit = snapshot.liveLimits.first { $0.id == source.liveLimitID }
        let window = limit?.secondary
        let actualRemaining = window.map { min(100, max(0, $0.remainingPercent)) }
        let comparison = window.flatMap { paceComparison(for: $0) }

        var rows: [WeeklyQuotaHoverOverlayView.Row] = []
        rows.append(.init(label: "实际剩余", value: actualRemaining.map { "\(Int(round($0)))%" } ?? "--", color: source == .codex ? accentBlue : accentAmber))
        if let comparison {
            let expectedRemaining = min(100, max(0, 100 - comparison.progressPercent))
            rows.append(.init(label: "预计剩余", value: "\(Int(round(expectedRemaining)))%", color: NSColor.white.withAlphaComponent(0.88)))
            rows.append(.init(label: "使用节奏", value: comparison.status == .ahead ? "用得偏快" : "用得较少", color: comparison.status == .ahead ? NSColor.systemYellow : NSColor.systemGreen))
        }
        rows.append(.init(label: "重置", value: window?.resetsAt.map { relative($0) } ?? "--", color: NSColor.white.withAlphaComponent(0.88)))
        let updatedText: String
        if let capturedAt = limit?.capturedAt {
            let seconds = -capturedAt.timeIntervalSinceNow
            updatedText = seconds < 60
                ? "刚刚"
                : "\(relative(capturedAt).replacingOccurrences(of: " ago", with: ""))前"
        } else {
            updatedText = "--"
        }
        rows.append(.init(label: "数据更新", value: updatedText, color: NSColor.white.withAlphaComponent(0.72)))

        let width: CGFloat = 286
        let height = CGFloat(34 + rows.count * 17 + 8)
        let container = sectionContent(for: .overview, in: bounds, sidebarWidth: detailsSidebarWidth)
        let cursorGap: CGFloat = 14
        var origin = CGPoint(x: anchor.x + cursorGap, y: anchor.y - height - cursorGap)
        if origin.x + width > container.maxX - 10 {
            origin.x = anchor.x - width - cursorGap
        }
        if origin.y < container.minY + 10 {
            origin.y = anchor.y + cursorGap
        }
        origin.x = max(container.minX + 10, min(origin.x, container.maxX - width - 10))
        origin.y = max(container.minY + 10, min(origin.y, container.maxY - height - 10))

        let title = weeklyQuotaTitle(source: source)
        let contentID = ([title] + rows.flatMap { [$0.label, $0.value] }).joined(separator: "\u{1f}")
        weeklyQuotaHoverOverlay.show(title: title, rows: rows, contentID: contentID, origin: origin)
    }

    func metricCardValueFont(text: String, maxWidth: CGFloat, preferredSize: CGFloat) -> NSFont {
        var size = preferredSize
        while size > 14 {
            let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .bold)
            if measuredTextWidth(text, font: font) <= maxWidth {
                return font
            }
            size -= 1
        }
        return .monospacedDigitSystemFont(ofSize: size, weight: .bold)
    }

    func drawResetCreditCountdownRow(snapshot: DetailsSnapshot, content: NSRect, y: CGFloat, height: CGFloat) {
        let rect = NSRect(x: content.minX, y: y, width: content.width, height: height)
        drawPanel(rect)

        let title = "\(t(.codex)) \(t(.resetCredits))"
        guard let resetCredits = snapshot.resetCredits else {
            drawText(title, rect: NSRect(x: rect.minX + 16, y: rect.minY + 12, width: 240, height: 20), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
            drawText(t(.resetCreditExpiryUnavailable), rect: NSRect(x: rect.minX + 16, y: rect.minY + 42, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }

        let count = max(0, resetCredits.availableCount)
        let countText = String(format: t(.resetCreditCountFormat), count)
        let titleText = "\(title) · \(countText)"
        let titleRect = NSRect(x: rect.minX + 16, y: rect.minY + 12, width: 280, height: 20)
        drawText(titleText, rect: titleRect, font: .systemFont(ofSize: 15, weight: .bold), color: .white)

        guard count > 0 else {
            drawText(t(.resetCreditNoCredits), rect: NSRect(x: rect.minX + 16, y: rect.minY + 42, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }

        let credits = resetCredits.availableCredits
            .sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
        guard !credits.isEmpty else {
            drawText(t(.resetCreditExpiryUnavailable), rect: NSRect(x: rect.minX + 16, y: rect.minY + 42, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }

        let columnCount = 3
        let horizontalGap: CGFloat = 18
        let verticalGap: CGFloat = 10
        let columnH: CGFloat = 42
        let columnW = (rect.width - 32 - horizontalGap * CGFloat(columnCount - 1)) / CGFloat(columnCount)
        let displaySlotCount = ((count + columnCount - 1) / columnCount) * columnCount
        for index in 0..<displaySlotCount {
            let row = index / columnCount
            let columnIndex = index % columnCount
            let column = NSRect(
                x: rect.minX + 16 + CGFloat(columnIndex) * (columnW + horizontalGap),
                y: rect.minY + 36 + CGFloat(row) * (columnH + verticalGap),
                width: columnW,
                height: columnH
            )
            if columnIndex > 0 {
                NSColor.white.withAlphaComponent(0.08).setStroke()
                let path = NSBezierPath()
                path.move(to: NSPoint(x: column.minX - horizontalGap / 2, y: column.minY + 2))
                path.line(to: NSPoint(x: column.minX - horizontalGap / 2, y: column.maxY - 2))
                path.stroke()
            }

            guard index < credits.count, let expiresAt = credits[index].expiresAt else {
                drawText("--", rect: NSRect(x: column.minX, y: column.minY + 10, width: column.width, height: 22), font: .monospacedDigitSystemFont(ofSize: 17, weight: .bold), color: NSColor.white.withAlphaComponent(0.35))
                continue
            }

            resetCreditTooltipRows.append(credits[index])
            resetCreditHitAreas.append((rect: column, index: resetCreditTooltipRows.count - 1))
            if hoveredResetCreditIndex == resetCreditTooltipRows.count - 1 {
                NSColor.white.withAlphaComponent(0.28).setStroke()
                let focus = NSBezierPath(roundedRect: column.insetBy(dx: -8, dy: -5), xRadius: 7, yRadius: 7)
                focus.lineWidth = 1
                focus.stroke()
            }

            var meta = "#\(index + 1) · \(t(.resetCreditExpiresAt)) \(Self.resetCreditExpiryFormatter.string(from: expiresAt))"
            if credits[index].expirationIsEstimated {
                meta += " · \(t(.resetCreditEstimated))"
            }
            let countdown = resetCreditCountdown(to: expiresAt)
            let countdownFont = metricCardValueFont(text: countdown, maxWidth: column.width, preferredSize: 20)
            drawText(meta, rect: NSRect(x: column.minX, y: column.minY, width: column.width, height: 15), font: .systemFont(ofSize: 10.5, weight: .semibold), color: NSColor.white.withAlphaComponent(0.48))
            drawText(countdown, rect: NSRect(x: column.minX, y: column.minY + 18, width: column.width, height: 24), font: countdownFont, color: resetCreditUrgencyColor(to: expiresAt))
        }
    }

    func resetCreditCountdown(to date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60

        switch AppLanguage.current {
        case .chinese, .traditionalChinese:
            return String(format: "%d天 %02d:%02d:%02d", days, hours, minutes, remainingSeconds)
        case .japanese:
            return String(format: "%d日 %02d:%02d:%02d", days, hours, minutes, remainingSeconds)
        default:
            return String(format: "%dd %02d:%02d:%02d", days, hours, minutes, remainingSeconds)
        }
    }

    func resetCreditUrgencyColor(to date: Date, now: Date = Date()) -> NSColor {
        let seconds = date.timeIntervalSince(now)
        if seconds <= 3 * 86_400 {
            return accentRose
        }
        if seconds <= 14 * 86_400 {
            return accentAmber
        }
        return accentBlue
    }

    func drawResetCreditTooltip(container: NSRect) {
        guard let index = hoveredResetCreditIndex,
              index >= 0, index < resetCreditTooltipRows.count,
              let hit = resetCreditHitAreas.first(where: { $0.index == index }) else {
            return
        }
        let credit = resetCreditTooltipRows[index]
        let grantedText = credit.grantedAt.map { Self.resetCreditFullFormatter.string(from: $0) } ?? "--"
        let expiresText = credit.expiresAt.map { Self.resetCreditFullFormatter.string(from: $0) } ?? "--"
        let remainingText = credit.expiresAt.map { resetCreditCountdown(to: $0) } ?? "--"
        let rows: [(String, String, NSColor)] = [
            (t(.resetCreditGrantedAt), grantedText, NSColor.white.withAlphaComponent(0.88)),
            (t(.resetCreditExpiresAt), expiresText, credit.expiresAt.map { resetCreditUrgencyColor(to: $0) } ?? accentAmber),
            (t(.remaining), remainingText, credit.expiresAt.map { resetCreditUrgencyColor(to: $0) } ?? accentAmber)
        ]

        let width: CGFloat = 278
        let height: CGFloat = 84
        var origin = CGPoint(x: hit.rect.midX - width / 2, y: hit.rect.minY - height - 10)
        if origin.y < container.minY + 10 {
            origin.y = hit.rect.maxY + 10
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

        drawText("\(t(.resetCredits)) #\(index + 1)", rect: NSRect(x: tooltipRect.minX + 10, y: tooltipRect.minY + 8, width: tooltipRect.width - 20, height: 16), font: .systemFont(ofSize: 11, weight: .bold), color: .white)
        for (rowIndex, row) in rows.enumerated() {
            let y = tooltipRect.minY + 30 + CGFloat(rowIndex) * 16
            drawText(row.0, rect: NSRect(x: tooltipRect.minX + 10, y: y, width: 56, height: 14), font: .systemFont(ofSize: 10, weight: .medium), color: NSColor.white.withAlphaComponent(0.5))
            drawRight(row.1, rect: NSRect(x: tooltipRect.minX + 70, y: y - 1, width: tooltipRect.width - 80, height: 15), color: row.2, font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold))
        }
    }

    func drawModelRows(snapshot: DetailsSnapshot, content: NSRect, y: CGFloat, height: CGFloat, maxRows: Int) {
        let rect = NSRect(x: content.minX, y: y, width: content.width, height: height)
        drawPanel(rect)
        drawText(t(.models), rect: NSRect(x: rect.minX + 16, y: rect.minY + 12, width: rect.width - 32, height: 20), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
        let models = Array(sourceReport(for: snapshot).modelBreakdown.prefix(maxRows))
        if models.isEmpty {
            drawText(t(.noModelLabelsFound), rect: NSRect(x: rect.minX + 16, y: rect.minY + 48, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }
        let metadataFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let totalWidth: CGFloat = 90
        let sessionsWidth = max(
            90,
            models.map { measuredTextWidth("\($0.sessions) \(t(.sessions))", font: metadataFont) + 4 }.max() ?? 90
        )
        let eventsWidth = max(
            92,
            models.map { measuredTextWidth("\($0.events) \(t(.events))", font: metadataFont) + 4 }.max() ?? 92
        )
        let rightPadding: CGFloat = 16
        let columnGap: CGFloat = 8
        let eventsX = rect.maxX - rightPadding - eventsWidth
        let sessionsX = eventsX - columnGap - sessionsWidth
        let totalX = sessionsX - columnGap - totalWidth
        let nameWidth = max(80, totalX - columnGap - (rect.minX + 16))
        for (index, model) in models.enumerated() {
            let y = rect.minY + 40 + CGFloat(index) * 20
            drawText(model.name, rect: NSRect(x: rect.minX + 16, y: y, width: nameWidth, height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: .white)
            drawRight(compact(model.usage.total), rect: NSRect(x: totalX, y: y, width: totalWidth, height: 18), color: .white, font: metadataFont)
            drawRight("\(model.sessions) \(t(.sessions))", rect: NSRect(x: sessionsX, y: y, width: sessionsWidth, height: 18), color: NSColor.white.withAlphaComponent(0.52), font: metadataFont)
            drawRight("\(model.events) \(t(.events))", rect: NSRect(x: eventsX, y: y, width: eventsWidth, height: 18), color: NSColor.white.withAlphaComponent(0.52), font: metadataFont)
        }
    }

    func drawMonthlySpendPanel(snapshot: DetailsSnapshot, content: NSRect, y: CGFloat, height: CGFloat) {
        let rect = NSRect(x: content.minX, y: y, width: content.width, height: height)
        drawPanel(rect)
        drawText(t(.monthlySpendHistory), rect: NSRect(x: rect.minX + 16, y: rect.minY + 12, width: 220, height: 20), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
        let costSource = selectedDetailsSource
        let rows = monthlySpendRows(
            report: sourceReport(for: snapshot),
            limit: sourceCostLimit(for: snapshot),
            quotaReferenceReport: sourceCostReferenceReport(for: snapshot),
            monthlyCost: AppSettings.monthlyPlanCost(for: costSource),
            paymentStartDay: AppSettings.paymentStartDay(for: costSource)
        )
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
            drawRight(displayMoney(row.usedValue, source: costSource), rect: NSRect(x: rect.maxX - 210, y: rowY, width: 110, height: 14), color: .white, font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold))
            drawRight(String(format: "%.0f%%", row.usedPercentOfPlan), rect: NSRect(x: rect.maxX - 84, y: rowY, width: 68, height: 14), color: NSColor.white.withAlphaComponent(0.52), font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold))
        }
    }

}
