import Cocoa

private struct ReasoningTrendPoint {
    let day: String
    let runsByEffort: [String: Int]
    let totalRuns: Int
    let medianTokens: Int64
}

extension UsageDetailsView {
    private var reasoningEfforts: [String] { ["low", "medium", "high", "xhigh", "ultra", "max"] }

    func normalizeReasoningSelection(_ report: ReasoningInsightsReport?) {
        guard let report else {
            selectedReasoningModels.removeAll()
            selectedReasoningCell = nil
            return
        }
        let models = reasoningAvailableModels(report)
        let valid = Set(models)
        selectedReasoningModels = selectedReasoningModels.intersection(valid)
        if selectedReasoningModels.isEmpty {
            selectedReasoningModels = Set(models.prefix(3))
        }
        if selectedReasoningModels.count > 3 {
            selectedReasoningModels = Set(models.filter(selectedReasoningModels.contains).prefix(3))
        }
        if hoveredReasoningDay == nil {
            let days = Set(report.dailyModelEfforts.map(\.day)).sorted()
            hoveredReasoningDay = days.count > 14 ? days[days.count - 15] : days.last
        }
        let visible = reasoningVisibleModels(report)
        if let selected = selectedReasoningCell,
           visible.contains(selected.model),
           reasoningCell(report, model: selected.model, effort: selected.effort) != nil {
            return
        }
        guard let model = visible.first else {
            selectedReasoningCell = nil
            return
        }
        let effort = reasoningCell(report, model: model, effort: "xhigh") != nil
            ? "xhigh"
            : reasoningEfforts.first(where: { reasoningCell(report, model: model, effort: $0) != nil }) ?? "high"
        selectedReasoningCell = ReasoningCellKey(model: model, effort: effort)
    }

    func drawReasoningDepthPage(report: ReasoningInsightsReport?, content: NSRect, topY: CGFloat) {
        guard let report, report.runCount > 0 else {
            let emptyRect = NSRect(x: content.minX, y: content.minY + 74, width: content.width, height: 180)
            drawReasoningPanel(emptyRect)
            drawText(reasoningLocalized("还没有可用的思考深度数据", english: "No reasoning-depth data yet"), rect: NSRect(x: emptyRect.minX + 18, y: emptyRect.minY + 22, width: emptyRect.width - 36, height: 24), font: .systemFont(ofSize: 17, weight: .bold), color: .white)
            drawText(reasoningLocalized("完成包含思考等级的 Codex 执行后，这里会显示实际分布。", english: "This view appears after Codex records reasoning effort for completed runs."), rect: NSRect(x: emptyRect.minX + 18, y: emptyRect.minY + 56, width: emptyRect.width - 36, height: 36), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.54))
            return
        }

        normalizeReasoningSelection(report)
        drawReasoningFilters(report: report, content: content)

        let upperY = content.minY + 148
        let availableHeight = max(680, content.maxY - upperY)
        let upperHeight = min(CGFloat(450), max(CGFloat(390), availableHeight * 0.55))
        let gap: CGFloat = 12
        let leftWidth = floor((content.width - gap) * 0.56)
        let heatmapRect = NSRect(x: content.minX, y: upperY, width: leftWidth, height: upperHeight)
        let detailRect = NSRect(x: heatmapRect.maxX + gap, y: upperY, width: content.maxX - heatmapRect.maxX - gap, height: upperHeight)
        drawReasoningHeatmap(report: report, rect: heatmapRect)
        drawReasoningCombinationDetail(report: report, rect: detailRect)

        let trendY = upperY + upperHeight + gap
        let trendHeight = max(CGFloat(290), content.maxY - trendY)
        drawReasoningTrend(report: report, rect: NSRect(x: content.minX, y: trendY, width: content.width, height: trendHeight))
    }

    func drawReasoningFilters(report: ReasoningInsightsReport, content: NSRect) {
        let y = content.minY + 90
        let labelY = y - 22
        let controlH: CGFloat = 36
        var x = content.minX

        let timeW = min(CGFloat(304), content.width * 0.24)
        drawText(reasoningLocalized("时间", english: "Time"), rect: NSRect(x: x, y: labelY, width: timeW, height: 16), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.58))
        let options = [(7, "7 天"), (30, "30 天"), (90, "90 天"), (0, reasoningLocalized("自定义", english: "Custom"))]
        let segmentW = timeW / CGFloat(options.count)
        inputSurfaceColor.withAlphaComponent(0.72).setFill()
        let timeRect = NSRect(x: x, y: y, width: timeW, height: controlH)
        NSBezierPath(roundedRect: timeRect, xRadius: 7, yRadius: 7).fill()
        borderColor.withAlphaComponent(0.65).setStroke()
        NSBezierPath(roundedRect: timeRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7).stroke()
        for (index, option) in options.enumerated() {
            let segment = NSRect(x: x + CGFloat(index) * segmentW, y: y, width: segmentW, height: controlH)
            if option.0 > 0 { insightWindowRects[option.0] = segment }
            let selected = option.0 == selectedInsightWindowDays
            if selected {
                accentBlue.withAlphaComponent(0.88).setFill()
                NSBezierPath(roundedRect: segment.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6).fill()
            }
            if index > 0 {
                NSColor.white.withAlphaComponent(0.08).setFill()
                NSRect(x: segment.minX, y: segment.minY + 5, width: 1, height: segment.height - 10).fill()
            }
            drawCentered(option.1, rect: segment, font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(selected ? 0.98 : 0.82))
        }
        x += timeW + 26

        let platformW: CGFloat = 126
        drawText(reasoningLocalized("平台", english: "Platform"), rect: NSRect(x: x, y: labelY, width: platformW, height: 16), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.58))
        drawReasoningField(title: "Codex", rect: NSRect(x: x, y: y, width: platformW, height: controlH), showsChevron: true)
        x += platformW + 14

        let projectW: CGFloat = 132
        let metricW: CGFloat = 178
        let remaining = max(CGFloat(292), content.maxX - x - projectW - metricW - 28)
        let modelW = remaining
        drawText(reasoningLocalized("模型", english: "Models"), rect: NSRect(x: x, y: labelY, width: modelW, height: 16), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.58))
        drawReasoningModelField(report: report, rect: NSRect(x: x, y: y, width: modelW, height: controlH))
        x += modelW + 14

        drawText(reasoningLocalized("项目", english: "Project"), rect: NSRect(x: x, y: labelY, width: projectW, height: 16), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.58))
        drawReasoningField(title: reasoningLocalized("全部项目", english: "All Projects"), rect: NSRect(x: x, y: y, width: projectW, height: controlH), showsChevron: true)
        x += projectW + 14

        drawText(reasoningLocalized("指标", english: "Metric"), rect: NSRect(x: x, y: labelY, width: metricW, height: 16), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.58))
        drawReasoningField(title: reasoningLocalized("单轮 Token 中位数", english: "Median Token / Run"), rect: NSRect(x: x, y: y, width: max(0, content.maxX - x), height: controlH), showsChevron: true)
    }

    func drawReasoningField(title: String, rect: NSRect, showsChevron: Bool) {
        inputSurfaceColor.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        borderColor.setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7).stroke()
        drawTruncatedText(title, rect: NSRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - (showsChevron ? 38 : 22), height: 17), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.92))
        if showsChevron {
            drawSymbolIcon("chevron.down", in: NSRect(x: rect.maxX - 24, y: rect.minY + 11, width: 12, height: 12), color: NSColor.white.withAlphaComponent(0.64), pointSize: 9)
        }
    }

    func drawReasoningPanel(_ rect: NSRect) {
        NSColor(calibratedRed: 0.052, green: 0.075, blue: 0.104, alpha: 0.88).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()
        NSColor(calibratedWhite: 1, alpha: 0.11).setStroke()
        let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        outline.lineWidth = 1
        outline.stroke()
    }

    func drawReasoningModelField(report: ReasoningInsightsReport, rect: NSRect) {
        inputSurfaceColor.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        borderColor.setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7).stroke()

        var x = rect.minX + 8
        for model in reasoningVisibleModels(report) {
            let font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
            let width = min(CGFloat(142), measuredTextWidth(model, font: font) + 34)
            guard x + width < rect.maxX - 28 else { break }
            let chip = NSRect(x: x, y: rect.minY + 6, width: width, height: 24)
            reasoningModelChipRects[model] = chip
            NSColor.white.withAlphaComponent(0.055).setFill()
            NSBezierPath(roundedRect: chip, xRadius: 5, yRadius: 5).fill()
            borderColor.withAlphaComponent(0.85).setStroke()
            NSBezierPath(roundedRect: chip.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5).stroke()
            drawTruncatedText(model, rect: NSRect(x: chip.minX + 9, y: chip.minY + 5, width: chip.width - 25, height: 15), font: font, color: NSColor.white.withAlphaComponent(0.78))
            drawCentered("×", rect: NSRect(x: chip.maxX - 20, y: chip.minY, width: 16, height: chip.height), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.52))
            x += width + 6
        }
        drawSymbolIcon("chevron.down", in: NSRect(x: rect.maxX - 23, y: rect.minY + 11, width: 12, height: 12), color: NSColor.white.withAlphaComponent(0.64), pointSize: 9)
    }

    func drawReasoningHeatmap(report: ReasoningInsightsReport, rect: NSRect) {
        drawReasoningPanel(rect)
        drawText(reasoningLocalized("模型 × 思考深度", english: "Model × Reasoning Effort"), rect: NSRect(x: rect.minX + 16, y: rect.minY + 16, width: rect.width - 32, height: 22), font: .systemFont(ofSize: 15, weight: .bold), color: NSColor.white.withAlphaComponent(0.94))
        drawText(reasoningLocalized("（单轮 Token 中位数）", english: "(Median Token / Run)"), rect: NSRect(x: rect.minX + 150, y: rect.minY + 18, width: rect.width - 166, height: 18), font: .systemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.52))

        let models = reasoningVisibleModels(report)
        guard !models.isEmpty else { return }
        let labelW = min(CGFloat(112), rect.width * 0.17)
        let grid = NSRect(x: rect.minX + 10, y: rect.minY + 114, width: rect.width - 20, height: rect.height - 128)
        let cellW = (grid.width - labelW) / CGFloat(reasoningEfforts.count)
        let rowH = grid.height / CGFloat(models.count)

        let legendY = rect.minY + 54
        drawText(reasoningLocalized("较低", english: "Lower"), rect: NSRect(x: rect.minX + 16, y: legendY, width: 42, height: 16), font: .systemFont(ofSize: 10.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.54))
        let gradientRect = NSRect(x: rect.minX + 58, y: legendY + 3, width: min(200, rect.width * 0.30), height: 10)
        NSGradient(colors: [reasoningEffortColor("low"), reasoningEffortColor("xhigh"), reasoningEffortColor("max")])?.draw(in: NSBezierPath(roundedRect: gradientRect, xRadius: 3, yRadius: 3), angle: 0)
        drawText(reasoningLocalized("较高", english: "Higher"), rect: NSRect(x: gradientRect.maxX + 10, y: legendY, width: 44, height: 16), font: .systemFont(ofSize: 10.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.54))

        for (column, effort) in reasoningEfforts.enumerated() {
            drawCentered(effort, rect: NSRect(x: grid.minX + labelW + CGFloat(column) * cellW, y: grid.minY - 29, width: cellW, height: 20), font: .systemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.70))
        }

        for (row, model) in models.enumerated() {
            let y = grid.minY + CGFloat(row) * rowH
            inputSurfaceColor.withAlphaComponent(0.38).setFill()
            NSRect(x: grid.minX, y: y, width: labelW, height: rowH).fill()
            drawTruncatedText(model, rect: NSRect(x: grid.minX + 10, y: y + rowH / 2 - 8, width: labelW - 16, height: 17), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.88))

            for (column, effort) in reasoningEfforts.enumerated() {
                let cellRect = NSRect(x: grid.minX + labelW + CGFloat(column) * cellW, y: y, width: cellW, height: rowH)
                let key = ReasoningCellKey(model: model, effort: effort)
                reasoningCellRects[key] = cellRect
                let color = reasoningEffortColor(effort)
                color.withAlphaComponent(0.72 + CGFloat(column) * 0.025).setFill()
                cellRect.fill()
                NSColor.white.withAlphaComponent(0.11).setStroke()
                NSBezierPath(rect: cellRect.insetBy(dx: 0.5, dy: 0.5)).stroke()
                let text = reasoningCell(report, model: model, effort: effort).map { reasoningCompactTokens($0.medianTokens) } ?? "—"
                drawCentered(text, rect: cellRect, font: .monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold), color: NSColor.white.withAlphaComponent(text == "—" ? 0.36 : 0.96))
                if selectedReasoningCell == key {
                    accentTeal.setStroke()
                    let outline = NSBezierPath(roundedRect: cellRect.insetBy(dx: 1.5, dy: 1.5), xRadius: 5, yRadius: 5)
                    outline.lineWidth = 2
                    outline.stroke()
                }
            }
        }
    }

    func drawReasoningCombinationDetail(report: ReasoningInsightsReport, rect: NSRect) {
        drawReasoningPanel(rect)
        drawText(reasoningLocalized("组合详情", english: "Combination Details"), rect: NSRect(x: rect.minX + 16, y: rect.minY + 16, width: rect.width - 32, height: 22), font: .systemFont(ofSize: 15, weight: .bold), color: NSColor.white.withAlphaComponent(0.94))
        guard let selected = selectedReasoningCell,
              let cell = reasoningCell(report, model: selected.model, effort: selected.effort) else { return }

        let modelFont = NSFont.systemFont(ofSize: 18, weight: .bold)
        let modelW = min(rect.width - 110, measuredTextWidth(selected.model, font: modelFont) + 2)
        drawTruncatedText(selected.model, rect: NSRect(x: rect.minX + 16, y: rect.minY + 52, width: modelW, height: 26), font: modelFont, color: accentBlue)
        drawText("×", rect: NSRect(x: rect.minX + 22 + modelW, y: rect.minY + 54, width: 18, height: 22), font: .systemFont(ofSize: 15, weight: .semibold), color: NSColor.white.withAlphaComponent(0.52))
        drawTruncatedText(selected.effort, rect: NSRect(x: rect.minX + 43 + modelW, y: rect.minY + 52, width: rect.width - modelW - 59, height: 26), font: modelFont, color: reasoningEffortColor(selected.effort))

        let knownRuns = max(1, report.knownRunCount)
        let taskTotal = max(1, report.taskCount)
        let rows: [(String, String)] = [
            (reasoningLocalized("会话", english: "Sessions"), "\(format(Int64(cell.tasks))) \(reasoningLocalized("个", english: ""))"),
            (reasoningLocalized("轮次", english: "Turns"), format(Int64(cell.runs))),
            (reasoningLocalized("总 Token", english: "Total Token"), reasoningCompactTokens(cell.usage.total)),
            (reasoningLocalized("单轮中位数", english: "Median / Run"), reasoningCompactTokens(cell.medianTokens)),
            ("P90", reasoningCompactTokens(cell.p90Tokens))
        ]
        let rowStart = rect.minY + 90
        let rowH: CGFloat = 32
        for (index, row) in rows.enumerated() {
            let y = rowStart + CGFloat(index) * rowH
            drawText(row.0, rect: NSRect(x: rect.minX + 16, y: y + 7, width: rect.width * 0.45, height: 18), font: .systemFont(ofSize: 11.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.68))
            drawRight(row.1, rect: NSRect(x: rect.minX + rect.width * 0.45, y: y + 7, width: rect.width * 0.55 - 16, height: 18), color: NSColor.white.withAlphaComponent(0.92), font: .monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold))
            NSColor.white.withAlphaComponent(0.075).setFill()
            NSRect(x: rect.minX + 16, y: y + rowH - 1, width: rect.width - 32, height: 1).fill()
        }

        let compositionY = rowStart + CGFloat(rows.count) * rowH + 8
        drawText(reasoningLocalized("Token 组成（占比）", english: "Token Composition"), rect: NSRect(x: rect.minX + 16, y: compositionY, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 11.5, weight: .semibold), color: NSColor.white.withAlphaComponent(0.80))
        let freshInput = max(Int64(0), cell.usage.input - cell.usage.cachedInput)
        let visibleOutput = max(Int64(0), cell.usage.output - cell.usage.reasoningOutput)
        let segments: [(String, Int64, NSColor)] = [
            (reasoningLocalized("输入", english: "Input"), freshInput, accentBlue),
            (reasoningLocalized("缓存输入", english: "Cached"), cell.usage.cachedInput, reasoningEffortColor("xhigh")),
            (reasoningLocalized("输出", english: "Output"), visibleOutput, accentTeal),
            (reasoningLocalized("推理输出", english: "Reasoning"), cell.usage.reasoningOutput, reasoningEffortColor("max"))
        ]
        let segmentTotal = max(Int64(1), segments.reduce(Int64(0)) { $0 + $1.1 })
        let bar = NSRect(x: rect.minX + 16, y: compositionY + 30, width: rect.width - 32, height: 12)
        var barX = bar.minX
        for segment in segments {
            let width = bar.width * CGFloat(Double(segment.1) / Double(segmentTotal))
            segment.2.setFill()
            NSRect(x: barX, y: bar.minY, width: max(segment.1 > 0 ? 2 : 0, width), height: bar.height).fill()
            barX += width
        }
        var legendX = rect.minX + 16
        for segment in segments {
            let percent = Double(segment.1) / Double(segmentTotal) * 100
            segment.2.setFill()
            NSRect(x: legendX, y: bar.maxY + 15, width: 8, height: 8).fill()
            let text = "\(segment.0)  \(String(format: "%.1f%%", percent))"
            let width = min(CGFloat(118), measuredTextWidth(text, font: .systemFont(ofSize: 9.5, weight: .medium)) + 18)
            drawText(text, rect: NSRect(x: legendX + 13, y: bar.maxY + 11, width: width - 13, height: 16), font: .systemFont(ofSize: 9.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.68))
            legendX += width
        }

        let sharesY = bar.maxY + 44
        drawReasoningShareRow(title: reasoningLocalized("会话占比", english: "Session Share"), value: Double(cell.tasks) / Double(taskTotal), rect: NSRect(x: rect.minX + 16, y: sharesY, width: rect.width - 32, height: 28), color: accentBlue)
        drawReasoningShareRow(title: reasoningLocalized("轮次占比", english: "Turn Share"), value: Double(cell.runs) / Double(knownRuns), rect: NSRect(x: rect.minX + 16, y: sharesY + 38, width: rect.width - 32, height: 28), color: reasoningEffortColor(selected.effort))
    }

    func drawReasoningShareRow(title: String, value: Double, rect: NSRect, color: NSColor) {
        drawText(title, rect: NSRect(x: rect.minX, y: rect.minY + 5, width: 110, height: 17), font: .systemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.68))
        drawRight(String(format: "%.1f%%", value * 100), rect: NSRect(x: rect.minX + 108, y: rect.minY + 5, width: 56, height: 17), color: NSColor.white.withAlphaComponent(0.84), font: .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold))
        let rail = NSRect(x: rect.minX + 176, y: rect.minY + 10, width: max(20, rect.width - 176), height: 7)
        NSColor.white.withAlphaComponent(0.07).setFill()
        NSBezierPath(roundedRect: rail, xRadius: 3.5, yRadius: 3.5).fill()
        color.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: NSRect(x: rail.minX, y: rail.minY, width: max(2, rail.width * CGFloat(min(1, max(0, value)))), height: rail.height), xRadius: 3.5, yRadius: 3.5).fill()
    }

    func drawReasoningTrend(report: ReasoningInsightsReport, rect: NSRect) {
        drawReasoningPanel(rect)
        drawText(reasoningLocalized("思考深度趋势", english: "Reasoning Effort Trend"), rect: NSRect(x: rect.minX + 16, y: rect.minY + 14, width: 180, height: 22), font: .systemFont(ofSize: 15, weight: .bold), color: NSColor.white.withAlphaComponent(0.94))
        drawText(reasoningLocalized("每日轮次占比（堆叠面积）与单轮 Token 中位数", english: "Daily turn share and median Token per turn"), rect: NSRect(x: rect.minX + 16, y: rect.minY + 39, width: 360, height: 17), font: .systemFont(ofSize: 10.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))

        let points = reasoningTrendPoints(report)
        guard points.count >= 2 else { return }
        drawReasoningLegend(rect: NSRect(x: rect.maxX - 560, y: rect.minY + 14, width: 544, height: 26))

        let plot = NSRect(x: rect.minX + 58, y: rect.minY + 92, width: rect.width - 116, height: max(120, rect.height - 136))
        let gridColor = NSColor.white.withAlphaComponent(0.075)
        for step in 0...4 {
            let fraction = CGFloat(step) / 4
            let y = plot.maxY - fraction * plot.height
            gridColor.setStroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: plot.minX, y: y))
            line.line(to: NSPoint(x: plot.maxX, y: y))
            line.lineWidth = 1
            line.stroke()
            drawRight("\(step * 25)%", rect: NSRect(x: rect.minX + 8, y: y - 8, width: 42, height: 16), color: NSColor.white.withAlphaComponent(0.52), font: .monospacedDigitSystemFont(ofSize: 9.5, weight: .medium))
        }
        drawText(reasoningLocalized("轮次占比", english: "Turn Share"), rect: NSRect(x: rect.minX + 16, y: rect.minY + 67, width: 80, height: 16), font: .systemFont(ofSize: 10, weight: .medium), color: NSColor.white.withAlphaComponent(0.52))

        let xForIndex: (Int) -> CGFloat = { index in
            plot.minX + CGFloat(index) / CGFloat(max(1, points.count - 1)) * plot.width
        }
        var lower = Array(repeating: CGFloat(0), count: points.count)
        for effort in reasoningEfforts {
            let upper = points.enumerated().map { index, point in
                lower[index] + CGFloat(point.runsByEffort[effort] ?? 0) / CGFloat(max(1, point.totalRuns))
            }
            let path = NSBezierPath()
            for index in points.indices {
                let point = NSPoint(x: xForIndex(index), y: plot.maxY - upper[index] * plot.height)
                index == points.startIndex ? path.move(to: point) : path.line(to: point)
            }
            for index in points.indices.reversed() {
                path.line(to: NSPoint(x: xForIndex(index), y: plot.maxY - lower[index] * plot.height))
            }
            path.close()
            reasoningEffortColor(effort).withAlphaComponent(0.92).setFill()
            path.fill()
            lower = upper
        }

        let rawMax = max(Int64(1), points.map(\.medianTokens).max() ?? 1)
        let axisMax = reasoningRoundedAxisMaximum(rawMax)
        drawText(reasoningLocalized("单轮 Token 中位数", english: "Median Token / Run"), rect: NSRect(x: rect.maxX - 142, y: rect.minY + 67, width: 126, height: 16), font: .systemFont(ofSize: 10, weight: .medium), color: NSColor.white.withAlphaComponent(0.52))
        for step in 0...4 {
            let value = axisMax * Int64(step) / 4
            let y = plot.maxY - CGFloat(step) / 4 * plot.height
            drawText(reasoningCompactTokens(value), rect: NSRect(x: plot.maxX + 8, y: y - 8, width: 48, height: 16), font: .monospacedDigitSystemFont(ofSize: 9.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.52))
        }

        let medianPath = NSBezierPath()
        for (index, point) in points.enumerated() {
            let y = plot.maxY - CGFloat(Double(point.medianTokens) / Double(axisMax)) * plot.height
            let position = NSPoint(x: xForIndex(index), y: y)
            index == 0 ? medianPath.move(to: position) : medianPath.line(to: position)
        }
        accentTeal.setStroke()
        medianPath.lineWidth = 2.5
        medianPath.lineJoinStyle = .round
        medianPath.stroke()

        let labelIndexes = Set([0, max(0, points.count / 4), max(0, points.count / 2), max(0, points.count * 3 / 4), points.count - 1])
        for index in points.indices {
            let x = xForIndex(index)
            let zoneWidth = plot.width / CGFloat(points.count)
            reasoningTrendDayRects[points[index].day] = NSRect(x: x - zoneWidth / 2, y: plot.minY, width: zoneWidth, height: plot.height)
            if labelIndexes.contains(index) {
                drawCentered(points[index].day, rect: NSRect(x: x - 48, y: plot.maxY + 10, width: 96, height: 16), font: .monospacedDigitSystemFont(ofSize: 9.2, weight: .medium), color: NSColor.white.withAlphaComponent(0.54))
            }
        }

        if let hovered = hoveredReasoningDay,
           let index = points.firstIndex(where: { $0.day == hovered }) {
            let point = points[index]
            let x = xForIndex(index)
            NSColor.white.withAlphaComponent(0.42).setStroke()
            let guide = NSBezierPath()
            guide.move(to: NSPoint(x: x, y: plot.minY))
            guide.line(to: NSPoint(x: x, y: plot.maxY))
            guide.lineWidth = 1
            guide.setLineDash([4, 3], count: 2, phase: 0)
            guide.stroke()
            let dominant = reasoningEfforts.max { (point.runsByEffort[$0] ?? 0) < (point.runsByEffort[$1] ?? 0) } ?? "high"
            let share = Double(point.runsByEffort[dominant] ?? 0) / Double(max(1, point.totalRuns)) * 100
            let title = "\(reasoningDateLabel(point.day))  \(dominant) \(String(format: "%.1f%%", share)) · \(reasoningLocalized("单轮中位数", english: "Median")) \(reasoningCompactTokens(point.medianTokens))"
            let tooltipW = min(CGFloat(330), measuredTextWidth(title, font: .systemFont(ofSize: 10.5, weight: .semibold)) + 22)
            let tooltipX = min(max(rect.minX + 12, x - tooltipW / 2), rect.maxX - tooltipW - 12)
            let tooltip = NSRect(x: tooltipX, y: plot.minY - 48, width: tooltipW, height: 38)
            NSColor(calibratedRed: 0.045, green: 0.057, blue: 0.077, alpha: 0.98).setFill()
            NSBezierPath(roundedRect: tooltip, xRadius: 7, yRadius: 7).fill()
            borderColor.setStroke()
            NSBezierPath(roundedRect: tooltip.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7).stroke()
            drawCentered(title, rect: tooltip.insetBy(dx: 8, dy: 0), font: .systemFont(ofSize: 10.5, weight: .semibold), color: NSColor.white.withAlphaComponent(0.92))
        }
    }

    func drawReasoningLegend(rect: NSRect) {
        let font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        var x = rect.minX
        for effort in reasoningEfforts {
            reasoningEffortColor(effort).setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: rect.minY + 8, width: 8, height: 8)).fill()
            drawText(effort, rect: NSRect(x: x + 12, y: rect.minY + 4, width: 48, height: 18), font: font, color: NSColor.white.withAlphaComponent(0.68))
            x += 58
        }
        accentTeal.setStroke()
        let line = NSBezierPath()
        line.move(to: NSPoint(x: x + 2, y: rect.minY + 12))
        line.line(to: NSPoint(x: x + 26, y: rect.minY + 12))
        line.lineWidth = 2
        line.stroke()
        drawText(reasoningLocalized("单轮 Token 中位数", english: "Median Token / Run"), rect: NSRect(x: x + 34, y: rect.minY + 4, width: rect.maxX - x - 34, height: 18), font: font, color: accentTeal)
    }

    private func reasoningTrendPoints(_ report: ReasoningInsightsReport) -> [ReasoningTrendPoint] {
        let selected = selectedReasoningModels
        let filtered = report.dailyModelEfforts.filter {
            selected.contains($0.model) && reasoningEfforts.contains($0.effort)
        }
        let grouped = Dictionary(grouping: filtered, by: \.day)
        let visibleDays = Array(grouped.keys.sorted().suffix(31))
        return visibleDays.map { day in
            let rows = grouped[day] ?? []
            var runs: [String: Int] = [:]
            var totals: [Int64] = []
            for row in rows {
                runs[row.effort, default: 0] += row.runs
                totals.append(contentsOf: row.runTokenTotals)
            }
            totals.sort()
            let median = totals.isEmpty ? 0 : totals[(totals.count - 1) / 2]
            return ReasoningTrendPoint(day: day, runsByEffort: runs, totalRuns: rows.reduce(0) { $0 + $1.runs }, medianTokens: median)
        }
    }

    func reasoningAvailableModels(_ report: ReasoningInsightsReport) -> [String] {
        let grouped = Dictionary(grouping: report.modelEfforts.filter { $0.model != "Unknown model" && $0.effort != "unknown" }, by: \.model)
        return grouped.keys.sorted {
            let lhs = grouped[$0]?.reduce(0) { $0 + $1.runs } ?? 0
            let rhs = grouped[$1]?.reduce(0) { $0 + $1.runs } ?? 0
            if lhs != rhs { return lhs > rhs }
            return $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    func reasoningVisibleModels(_ report: ReasoningInsightsReport) -> [String] {
        Array(reasoningAvailableModels(report).filter(selectedReasoningModels.contains).prefix(3))
    }

    func reasoningCell(_ report: ReasoningInsightsReport, model: String, effort: String) -> ReasoningModelEffortSummary? {
        report.modelEfforts.first { $0.model == model && $0.effort == effort && $0.runs > 0 }
    }

    func reasoningEffortColor(_ effort: String) -> NSColor {
        switch effort.lowercased() {
        case "low": return NSColor(calibratedRed: 0.20, green: 0.58, blue: 0.91, alpha: 1)
        case "medium": return NSColor(calibratedRed: 0.22, green: 0.43, blue: 0.91, alpha: 1)
        case "high": return NSColor(calibratedRed: 0.29, green: 0.37, blue: 0.83, alpha: 1)
        case "xhigh": return NSColor(calibratedRed: 0.45, green: 0.30, blue: 0.78, alpha: 1)
        case "ultra": return NSColor(calibratedRed: 0.64, green: 0.31, blue: 0.75, alpha: 1)
        case "max": return NSColor(calibratedRed: 0.91, green: 0.43, blue: 0.64, alpha: 1)
        default: return NSColor.white.withAlphaComponent(0.28)
        }
    }

    func reasoningRoundedAxisMaximum(_ raw: Int64) -> Int64 {
        guard raw > 0 else { return 1 }
        let magnitude = pow(10.0, floor(log10(Double(raw))))
        let normalized = Double(raw) / magnitude
        let rounded: Double = normalized <= 1.2 ? 1.2 : normalized <= 2 ? 2 : normalized <= 3 ? 3 : normalized <= 6 ? 6 : 12
        return max(1, Int64(ceil(rounded * magnitude)))
    }

    func reasoningCompactTokens(_ value: Int64) -> String {
        guard value > 0 else { return "0" }
        switch AppLanguage.current {
        case .chinese, .traditionalChinese, .japanese:
            if value >= 100_000_000 { return String(format: "%.2f亿", Double(value) / 100_000_000) }
            if value >= 10_000 { return String(format: "%.1f万", Double(value) / 10_000) }
            return format(value)
        default:
            if value >= 1_000_000_000 { return String(format: "%.2fB", Double(value) / 1_000_000_000) }
            if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
            if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
            return format(value)
        }
    }

    func reasoningDateLabel(_ day: String) -> String {
        let parts = day.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let date = Int(parts[2]) else { return day }
        return AppLanguage.current == .chinese || AppLanguage.current == .traditionalChinese ? "\(month)月\(date)日" : "\(month)/\(date)"
    }

    func reasoningLocalized(_ chinese: String, english: String) -> String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return chinese
        default: return english
        }
    }

    func drawReasoningTrendTooltip(container: NSRect) {
        // The tooltip is drawn last inside the trend panel so it remains above the chart.
    }
}
