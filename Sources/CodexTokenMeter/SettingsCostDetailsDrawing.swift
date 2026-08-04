import Cocoa

extension UsageDetailsView {
    func drawSettingsPage(content: NSRect) {
        numberUnitOptionRects.removeAll()
        quotaDisplayStyleRects.removeAll()
        codexHomeRingMetricRects.removeAll()
        claudeHomeRingMetricRects.removeAll()
        claudeThirdRingMetricRects.removeAll()
        settingsSubsectionRects.removeAll()
        chooseLogFolderRect = nil
        resetLogFolderRect = nil
        openLogFolderRect = nil
        chooseCodexAPISourceRect = nil
        resetCodexAPISourceRect = nil
        openCodexAPISourceRect = nil
        machineUsageExportRect = nil

        let rect = settingsPanelRect(in: content)
        drawSettingsSubnavigation(in: rect)

        let page = settingsPageRect(in: rect)
        drawSettingsPageHeader(in: page)
        switch selectedSettingsSubsection {
        case .appearance:
            drawAppearanceSettings(in: page)
        case .data:
            drawDataSettings(in: page)
        case .quota:
            drawQuotaSettings(in: page)
        case .system:
            drawSystemSettings(in: page)
        }
    }

    func drawSettingsSubnavigation(in rect: NSRect) {
        let navRect = NSRect(x: rect.minX, y: rect.minY + 2, width: settingsSubnavWidth, height: rect.height - 4)
        NSColor.white.withAlphaComponent(0.08).setFill()
        NSRect(x: rect.minX + settingsSubnavWidth + 16, y: rect.minY + 2, width: 1, height: rect.height - 4).fill()

        let title = AppLanguage.current == .english ? "Settings" : (AppLanguage.current == .japanese ? "設定分類" : "设置分类")
        drawText(title, rect: NSRect(x: navRect.minX, y: navRect.minY, width: navRect.width - 8, height: 18), font: .systemFont(ofSize: 12, weight: .bold), color: NSColor.white.withAlphaComponent(0.46))

        let itemHeight: CGFloat = 52
        let gap: CGFloat = 10
        var y = navRect.minY + 34
        for subsection in SettingsSubsection.allCases {
            let itemRect = NSRect(x: navRect.minX, y: y, width: navRect.width - 12, height: itemHeight)
            settingsSubsectionRects[subsection] = itemRect
            let selected = subsection == selectedSettingsSubsection
            (selected ? accentBlue.withAlphaComponent(0.70) : NSColor.clear).setFill()
            NSBezierPath(roundedRect: itemRect, xRadius: 8, yRadius: 8).fill()
            let textColor = selected ? NSColor.white : NSColor.white.withAlphaComponent(0.76)
            drawSymbolIcon(subsection.symbolName, in: NSRect(x: itemRect.minX + 12, y: itemRect.minY + 18, width: 18, height: 18), color: textColor.withAlphaComponent(selected ? 0.96 : 0.58), pointSize: 12)
            drawText(subsection.title, rect: NSRect(x: itemRect.minX + 38, y: itemRect.minY + 10, width: itemRect.width - 48, height: 18), font: .systemFont(ofSize: 12, weight: .bold), color: textColor)
            drawText(subsection.subtitle, rect: NSRect(x: itemRect.minX + 38, y: itemRect.minY + 30, width: itemRect.width - 48, height: 16), font: .systemFont(ofSize: 9, weight: .semibold), color: textColor.withAlphaComponent(selected ? 0.64 : 0.42))
            y += itemHeight + gap
        }
    }

    func drawSettingsPageHeader(in page: NSRect) {
        drawText(selectedSettingsSubsection.title, rect: NSRect(x: page.minX, y: page.minY, width: page.width, height: 24), font: .systemFont(ofSize: 18, weight: .bold), color: .white)
        drawText(selectedSettingsSubsection.subtitle, rect: NSRect(x: page.minX, y: page.minY + 28, width: page.width, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.52))
        NSColor.white.withAlphaComponent(0.08).setFill()
        NSRect(x: page.minX, y: page.minY + 56, width: page.width, height: 1).fill()
    }

    func drawAppearanceSettings(in page: NSRect) {
        let labelW = min(220, page.width * 0.35)
        let optionX = page.minX + labelW + 22
        let optionW = page.maxX - optionX

        drawSettingText(title: t(.interfaceLanguage), hint: t(.languageHint), x: page.minX, y: page.minY + 76, width: labelW)

        drawSettingText(title: t(.displayCurrency), hint: t(.displayCurrencyHint), x: page.minX, y: page.minY + 152, width: labelW)

        drawSettingText(title: t(.numberUnits), hint: t(.numberUnitsHint), x: page.minX, y: page.minY + 228, width: labelW)
        let unitStyles = NumberUnitStyle.availableCases
        let unitRects = segmentedRects(count: unitStyles.count, in: NSRect(x: optionX, y: page.minY + 222, width: optionW, height: 36), preferredWidth: 132)
        for (index, style) in unitStyles.enumerated() {
            let optionRect = unitRects[index]
            numberUnitOptionRects[style] = optionRect
            drawSelectablePill(style.title, rect: optionRect, selected: style == NumberUnitStyle.effective)
        }

        let statusTextW = max(labelW, statusPrimaryMetricPopup.frame.minX - page.minX - 12)
        drawSettingText(title: t(.statusBarMetricOne), hint: t(.statusDisplayHint), x: page.minX, y: page.minY + 306, width: statusTextW)
        drawSettingText(title: t(.statusBarMetricTwo), hint: "", x: page.minX, y: page.minY + 376, width: statusTextW)
    }

    func drawDataSettings(in page: NSRect) {
        drawSettingText(title: t(.logFolder), hint: t(.logFolderHint), x: page.minX, y: page.minY + 76, width: page.width)
        let logButtonY = page.minY + 128
        let buttonGap: CGFloat = 12
        let openW: CGFloat = 78
        let resetW: CGFloat = 76
        let chooseW: CGFloat = 108
        let buttonTotalW = openW + resetW + chooseW + buttonGap * 2
        let buttonStartX = page.maxX - buttonTotalW
        openLogFolderRect = NSRect(x: buttonStartX, y: logButtonY, width: openW, height: 34)
        resetLogFolderRect = NSRect(x: openLogFolderRect!.maxX + buttonGap, y: logButtonY, width: resetW, height: 34)
        chooseLogFolderRect = NSRect(x: resetLogFolderRect!.maxX + buttonGap, y: logButtonY, width: chooseW, height: 34)
        let pathRect = NSRect(x: page.minX, y: logButtonY, width: max(120, buttonStartX - page.minX - 16), height: 34)
        NSColor.black.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: pathRect, xRadius: 7, yRadius: 7).fill()
        drawTruncatedText(AppSettings.logFolderDisplayPath, rect: pathRect.insetBy(dx: 12, dy: 9), font: .monospacedSystemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.62))
        drawSmallButton(t(.logs), rect: openLogFolderRect!, emphasized: false)
        drawSmallButton(t(.logFolderDefault), rect: resetLogFolderRect!, emphasized: false)
        drawSmallButton(t(.logFolderChoose), rect: chooseLogFolderRect!, emphasized: true)

        drawSettingText(title: t(.codexAPISources), hint: t(.codexAPISourcesHint), x: page.minX, y: page.minY + 186, width: page.width)
        let apiButtonY = page.minY + 238
        openCodexAPISourceRect = NSRect(x: buttonStartX, y: apiButtonY, width: openW, height: 34)
        resetCodexAPISourceRect = NSRect(x: openCodexAPISourceRect!.maxX + buttonGap, y: apiButtonY, width: resetW, height: 34)
        chooseCodexAPISourceRect = NSRect(x: resetCodexAPISourceRect!.maxX + buttonGap, y: apiButtonY, width: chooseW, height: 34)
        let apiPathRect = NSRect(x: page.minX, y: apiButtonY, width: max(120, buttonStartX - page.minX - 16), height: 34)
        NSColor.black.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: apiPathRect, xRadius: 7, yRadius: 7).fill()
        drawTruncatedText(AppSettings.codexAPISourceDisplayPath, rect: apiPathRect.insetBy(dx: 12, dy: 9), font: .monospacedSystemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.62))
        drawSmallButton(t(.logFolderOpen), rect: openCodexAPISourceRect!, emphasized: false)
        drawSmallButton(t(.logFolderDefault), rect: resetCodexAPISourceRect!, emphasized: false)
        drawSmallButton(t(.codexAPISourcesChoose), rect: chooseCodexAPISourceRect!, emphasized: true)

        drawSwitchSetting(title: t(.profileAPITotals), hint: t(.profileAPITotalsHint), switchFrame: profileAPITotalsSwitch.frame, page: page, y: page.minY + 320)

        let exportCopy = AppLanguage.current.machineUsageReportCopy
        let exportY = page.minY + 400
        let exportW = max(118, measuredTextWidth(exportCopy.exportAction, font: .systemFont(ofSize: 12, weight: .semibold)) + 28)
        machineUsageExportRect = NSRect(x: page.maxX - exportW, y: exportY, width: exportW, height: 34)
        drawSettingText(title: exportCopy.title, hint: exportCopy.hint, x: page.minX, y: exportY, width: max(180, machineUsageExportRect!.minX - page.minX - 16))
        drawSmallButton(exportCopy.exportAction, rect: machineUsageExportRect!, emphasized: true)
    }

    func drawQuotaSettings(in page: NSRect) {
        let labelW = min(220, page.width * 0.34)
        let optionX = page.minX + labelW + 22
        let optionW = page.maxX - optionX

        drawSettingText(title: t(.quotaDisplayStyle), hint: t(.quotaDisplayHint), x: page.minX, y: page.minY + 76, width: labelW)
        let quotaStyleRects = segmentedRects(count: QuotaDisplayStyle.allCases.count, in: NSRect(x: optionX, y: page.minY + 70, width: optionW, height: 36), preferredWidth: 122)
        for (index, style) in QuotaDisplayStyle.allCases.enumerated() {
            let optionRect = quotaStyleRects[index]
            quotaDisplayStyleRects[style] = optionRect
            drawSelectablePill(style.title, rect: optionRect, selected: style == QuotaDisplayStyle.current)
        }

        drawSettingText(title: t(.codexHomeRing), hint: t(.quotaHomeRingHint), x: page.minX, y: page.minY + 150, width: labelW)
        drawSettingText(title: t(.claudeHomeRing), hint: "", x: page.minX, y: page.minY + 220, width: labelW)
        let homeMetricRects = segmentedRects(count: HomeQuotaRingMetric.allCases.count, in: NSRect(x: optionX, y: page.minY + 144, width: optionW, height: 36), preferredWidth: 122)
        let claudeMetricRects = segmentedRects(count: HomeQuotaRingMetric.allCases.count, in: NSRect(x: optionX, y: page.minY + 214, width: optionW, height: 36), preferredWidth: 122)
        for (index, metric) in HomeQuotaRingMetric.allCases.enumerated() {
            let codexRect = homeMetricRects[index]
            codexHomeRingMetricRects[metric] = codexRect
            drawSelectablePill(metric.title, rect: codexRect, selected: metric == AppSettings.codexHomeRingMetric)
            let claudeRect = claudeMetricRects[index]
            claudeHomeRingMetricRects[metric] = claudeRect
            drawSelectablePill(metric.title, rect: claudeRect, selected: metric == AppSettings.claudeHomeRingMetric)
        }

        drawSettingText(title: t(.claudeThirdRing), hint: t(.claudeThirdRingHint), x: page.minX, y: page.minY + 290, width: labelW)
        let thirdRingRects = segmentedRects(count: ClaudeThirdRingMetric.allCases.count, in: NSRect(x: optionX, y: page.minY + 284, width: optionW, height: 36), preferredWidth: 122)
        for (index, metric) in ClaudeThirdRingMetric.allCases.enumerated() {
            let optionRect = thirdRingRects[index]
            claudeThirdRingMetricRects[metric] = optionRect
            drawSelectablePill(metric.title, rect: optionRect, selected: metric == AppSettings.claudeThirdRingMetric)
        }

        drawSwitchSetting(title: t(.showCombinedFable), hint: t(.showCombinedFableHint), switchFrame: showCombinedFableSwitch.frame, page: page, y: page.minY + 356)
        drawSwitchSetting(title: t(.quotaWarnings), hint: t(.quotaWarningsHint), switchFrame: quotaWarningsSwitch.frame, page: page, y: page.minY + 418)
    }

    func drawSystemSettings(in page: NSRect) {
        drawSwitchSetting(title: t(.launchAtLogin), hint: t(.launchAtLoginHint), switchFrame: launchAtLoginSwitch.frame, page: page, y: page.minY + 76)
    }

    func drawSettingText(title: String, hint: String, x: CGFloat, y: CGFloat, width: CGFloat) {
        drawText(title, rect: NSRect(x: x, y: y, width: width, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
        if !hint.isEmpty {
            drawMultilineText(hint, rect: NSRect(x: x, y: y + 23, width: width, height: 34), font: .systemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
        }
    }

    func drawSwitchSetting(title: String, hint: String, switchFrame: NSRect, page: NSRect, y: CGFloat) {
        let textW = max(120, switchFrame.minX - page.minX - 12)
        drawText(title, rect: NSRect(x: page.minX, y: y, width: textW, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
        drawMultilineText(hint, rect: NSRect(x: page.minX, y: y + 23, width: textW, height: 32), font: .systemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
    }

    func segmentedRects(count: Int, in rect: NSRect, preferredWidth: CGFloat) -> [NSRect] {
        guard count > 0 else { return [] }
        let gap: CGFloat = 10
        let availableWidth = rect.width - gap * CGFloat(max(0, count - 1))
        let optionWidth = min(preferredWidth, max(82, availableWidth / CGFloat(count)))
        let totalWidth = optionWidth * CGFloat(count) + gap * CGFloat(max(0, count - 1))
        let startX = rect.maxX - totalWidth
        return (0..<count).map { index in
            NSRect(x: startX + CGFloat(index) * (optionWidth + gap), y: rect.minY, width: optionWidth, height: rect.height)
        }
    }

    var costUsedColor: NSColor {
        accentTeal
    }

    var costRemainingColor: NSColor {
        NSColor(calibratedRed: 0.52, green: 0.58, blue: 0.69, alpha: 1.0)
    }

    var costRemainingMutedColor: NSColor {
        NSColor(calibratedRed: 0.168, green: 0.196, blue: 0.244, alpha: 1.0)
    }

    func costUsedColor(for row: CostPeriodRow) -> NSColor {
        guard row.isShortCycle else { return costUsedColor }
        return accentAmber
    }

    func costRemainingColor(for row: CostPeriodRow) -> NSColor {
        guard row.isShortCycle else { return costRemainingColor }
        return costRemainingColor.withAlphaComponent(0.78)
    }

    func costRemainingMutedColor(for row: CostPeriodRow) -> NSColor {
        guard row.isShortCycle else { return costRemainingMutedColor }
        return costRemainingMutedColor.withAlphaComponent(0.95)
    }

    func drawCurrencyOptions(rect: NSRect, y: CGFloat, selected: CurrencyCode, store: inout [CurrencyCode: NSRect]) {
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

    func drawCostHistoryBars(rows: [CostPeriodRow], rect: NSRect) {
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

    func drawCostRings(rows: [CostPeriodRow], rect: NSRect, year: Int) {
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

    func costRingLayout(rows: [CostPeriodRow], rect: NSRect) -> (cells: [NSRect], legendRect: NSRect, footerRect: NSRect, titleRect: NSRect) {
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

    func renderCostRingsImage(rows: [CostPeriodRow], rect: NSRect, year: Int) -> NSImage {
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

    func costRingCacheKey(rows: [CostPeriodRow], rect: NSRect, year: Int) -> String {
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

    func drawCostRingLegend(rect: NSRect) {
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

    func drawCostRing(row: CostPeriodRow, rect: NSRect, showLabel: Bool, highlighted: Bool) {
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

    func drawCostHistoryTooltip() {
        guard let hoveredCostHistoryIndex,
              costHistoryRows.indices.contains(hoveredCostHistoryIndex),
              let anchorRect = costHistoryBarRects[hoveredCostHistoryIndex] else {
            return
        }
        let row = costHistoryRows[hoveredCostHistoryIndex]
        let costSource = selectedDetailsSource
        var lines = costHistoryTooltipLines(for: row, source: costSource)
        if let apiEquivalentUSD = row.apiEquivalentUSD {
            let apiTitle = row.apiEquivalentCoveragePercent > 0 && row.apiEquivalentCoveragePercent < 99.5
                ? "\(t(.apiEquivalent)) \(String(format: "%.0f%%", row.apiEquivalentCoveragePercent))"
                : t(.apiEquivalent)
            let apiIndex = max(0, lines.count - 1)
            lines.insert((apiTitle, displayAPIMoney(apiEquivalentUSD, source: costSource), accentTeal), at: apiIndex)
        }

        let width: CGFloat = costSource == .all ? 354 : 326
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
        let labelWidth: CGFloat = costSource == .all ? 128 : 108
        let valueX = rect.minX + labelWidth + 30
        let valueWidth = rect.maxX - valueX - 14
        for (index, line) in lines.enumerated() {
            let y = startY + CGFloat(index) * rowHeight
            drawText(line.0, rect: NSRect(x: rect.minX + 12, y: y, width: labelWidth, height: 16), font: .systemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.62))
            drawRight(line.1, rect: NSRect(x: valueX, y: y, width: valueWidth, height: 16), color: line.2, font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold))
        }
    }

    func costHistoryTooltipLines(for row: CostPeriodRow, source: QuotaViewOption) -> [(String, String, NSColor)] {
        guard source == .all, let snapshot else {
            return [
                (t(.used), displayMoney(row.usedValue, source: source), costUsedColor(for: row)),
                (t(.remaining), displayMoney(row.remainingValue, source: source), costRemainingColor(for: row)),
                (t(.budget), displayMoney(row.budgetValue, source: source), .white),
                (t(.usageRate), String(format: "%.1f%%", row.usedPercent), NSColor.white.withAlphaComponent(0.82))
            ]
        }

        let codex = platformCostHistoryValues(matching: row, source: .codex, snapshot: snapshot)
        let claude = platformCostHistoryValues(matching: row, source: .claude, snapshot: snapshot)
        return [
            (platformCostHistoryLabel(source: .codex, remaining: false), displayMoney(codex.usedValue, source: .codex), costUsedColor),
            (platformCostHistoryLabel(source: .codex, remaining: true), displayMoney(codex.remainingValue, source: .codex), costRemainingColor),
            (platformCostHistoryLabel(source: .claude, remaining: false), displayMoney(claude.usedValue, source: .claude), accentAmber),
            (platformCostHistoryLabel(source: .claude, remaining: true), displayMoney(claude.remainingValue, source: .claude), costRemainingColor.withAlphaComponent(0.78)),
            (t(.budget), displayMoney(row.budgetValue, source: source), .white),
            (t(.usageRate), String(format: "%.1f%%", row.usedPercent), NSColor.white.withAlphaComponent(0.82))
        ]
    }

    func platformCostHistoryValues(matching row: CostPeriodRow, source: QuotaViewOption, snapshot: DetailsSnapshot) -> (usedValue: Double, remainingValue: Double) {
        let rows = weeklySpendRows(
            report: sourceReport(for: snapshot, source: source),
            limit: source == .claude ? nil : costEstimateLimit(from: snapshot.liveLimits),
            year: selectedCostYear,
            quotaReferenceReport: source == .claude ? nil : snapshot.costReferenceReport,
            monthlyCost: AppSettings.monthlyPlanCost(for: source),
            paymentStartDay: AppSettings.paymentStartDay(for: source)
        )
        let match = rows.first { $0.label == row.label && $0.cycleIndex == row.cycleIndex && $0.title == row.title }
            ?? rows.first { $0.label == row.label && $0.cycleIndex == row.cycleIndex }
            ?? rows.first { $0.label == row.label && $0.cycleIndex == 0 }
            ?? rows.first { $0.label == row.label }
        if let match {
            return (match.usedValue, match.remainingValue)
        }
        return (0, AppSettings.monthlyPlanCost(for: source) * 12 / 52)
    }

    func platformCostHistoryLabel(source: QuotaViewOption, remaining: Bool) -> String {
        let name = source == .codex ? "Codex" : "Claude"
        switch AppLanguage.current {
        case .chinese, .traditionalChinese:
            return "\(name) \(remaining ? "剩余" : "花费")"
        default:
            return "\(name) \(remaining ? "remaining" : "spent")"
        }
    }

    func drawCostOverviewInfoTooltip() {
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

    func drawDayQuotaShareInfoTooltip() {
        guard isHoveringDayQuotaShareInfo, let anchorRect = dayQuotaShareInfoRect else { return }
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

        drawText(t(.weeklyQuotaShare), rect: NSRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - 24, height: 16), font: .systemFont(ofSize: 11, weight: .bold), color: .white)
        drawMultilineText(t(.selectedDayQuotaShareHint), rect: NSRect(x: rect.minX + 12, y: rect.minY + 30, width: rect.width - 24, height: 34), font: .systemFont(ofSize: 10, weight: .medium), color: NSColor.white.withAlphaComponent(0.58))
    }

    func drawProfileAPIInfoTooltip() {
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

}
