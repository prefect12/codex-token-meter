import Cocoa

private struct CombinationRankingRow {
    let model: String
    let platform: String
    let effort: String
    let projects: Int?
    let tasks: Int
    let runs: Int
    let usage: Usage
    let medianTokens: Int64
    let p90Tokens: Int64

    var key: UsageDetailsView.ReasoningCellKey { .init(model: model, effort: effort, platform: platform) }
    var averageTokensPerTask: Int64 { tasks > 0 ? usage.total / Int64(tasks) : 0 }
    var freshInput: Int64 { max(0, usage.input - usage.cachedInput) }
    var visibleOutput: Int64 { max(0, usage.output - usage.reasoningOutput) }
    var apiEstimate: APICostEstimate { APICostEstimator.estimate(usage: usage, modelName: model) }
    var costPerTask: Double { tasks > 0 ? apiEstimate.usdValue / Double(tasks) : 0 }
}

private struct ReasoningTableColumn {
    let sort: UsageDetailsView.CombinationRankingSortColumn
    let title: String
    let width: CGFloat
    let alignment: NSTextAlignment
    let value: (CombinationRankingRow) -> String
}

extension UsageDetailsView {
    func normalizeCombinationRankingSelection(snapshot: DetailsSnapshot?) {
        guard let snapshot else {
            selectedCombinationRankingModels.removeAll()
            selectedCombinationRankingEffortsByModel.removeAll()
            activeCombinationRankingModel = nil
            selectedCombinationRankingCell = nil
            return
        }
        let rows = combinationRankingRows(snapshot: snapshot)
        let models = combinationRankingAvailableModels(rows)
        selectedCombinationRankingModels.formIntersection(Set(models))
        if selectedCombinationRankingModels.isEmpty {
            let preferredModels = ["gpt-5.6-sol", "gpt-5.6-terra"].compactMap { preferred in
                models.first { $0.caseInsensitiveCompare(preferred) == .orderedSame }
            }
            let unavailableModels = rows
                .filter { $0.effort == "unavailable" }
                .sorted { $0.usage.total > $1.usage.total }
                .map(\.model)
            var defaults: [String] = []
            for model in unavailableModels where !defaults.contains(where: { $0.caseInsensitiveCompare(model) == .orderedSame }) {
                defaults.append(model)
            }
            if let highestUsageModel = combinationRankingHighestUsageModel(rows),
               !defaults.contains(where: { $0.caseInsensitiveCompare(highestUsageModel) == .orderedSame }) {
                defaults.append(highestUsageModel)
            }
            defaults.append(contentsOf: preferredModels.filter { candidate in
                !defaults.contains { $0.caseInsensitiveCompare(candidate) == .orderedSame }
            })
            selectedCombinationRankingModels = Set(defaults.prefix(3))
        }
        if activeCombinationRankingModel == nil || !models.contains(activeCombinationRankingModel ?? "") {
            activeCombinationRankingModel = selectedCombinationRankingModels.sorted().first ?? models.first
        }
        selectedCombinationRankingEffortsByModel = selectedCombinationRankingEffortsByModel.filter {
            models.contains($0.key)
        }
        for model in selectedCombinationRankingModels {
            let available = Set(combinationRankingAvailableEfforts(rows, model: model))
            var selected = selectedCombinationRankingEffortsByModel[model] ?? available
            selected.formIntersection(available)
            if selected.isEmpty {
                selected = available
            }
            selectedCombinationRankingEffortsByModel[model] = selected
        }
        let visible = combinationRankingVisibleRows(rows)
        if let selectedCombinationRankingCell, visible.contains(where: { $0.key == selectedCombinationRankingCell }) { return }
        selectedCombinationRankingCell = visible.first(where: { $0.effort == "xhigh" })?.key ?? visible.first?.key
    }

    func drawCombinationRankingPage(snapshot: DetailsSnapshot, content: NSRect) {
        normalizeCombinationRankingSelection(snapshot: snapshot)
        let allRows = combinationRankingRows(snapshot: snapshot)
        drawCombinationRankingFilters(rows: allRows, content: content)

        let rows = combinationRankingSortedRows(combinationRankingVisibleRows(allRows))
        let gap: CGFloat = 12
        let narrow = content.width < 1040
        let bodyY: CGFloat
        if narrow {
            let hintRect = NSRect(x: content.minX, y: content.minY + 126, width: content.width, height: 36)
            drawCombinationRankingExpandHint(rect: hintRect)
            bodyY = hintRect.maxY + gap
            let tableHeight = min(CGFloat(520), max(CGFloat(350), content.height * 0.52))
            let tableRect = NSRect(x: content.minX, y: bodyY, width: content.width, height: tableHeight)
            drawReasoningTable(rows: rows, rect: tableRect, compact: true)
            let detailRect = NSRect(x: content.minX, y: tableRect.maxY + gap, width: content.width, height: max(410, content.maxY - tableRect.maxY - gap))
            drawCombinationRankingDetail(rows: rows, snapshot: snapshot, rect: detailRect, compact: true)
        } else {
            bodyY = content.minY + 138
            let detailWidth = min(CGFloat(286), max(CGFloat(244), content.width * 0.22))
            let tableRect = NSRect(x: content.minX, y: bodyY, width: content.width - detailWidth - gap, height: content.maxY - bodyY)
            let detailRect = NSRect(x: tableRect.maxX + gap, y: bodyY, width: detailWidth, height: tableRect.height)
            drawReasoningTable(rows: rows, rect: tableRect, compact: false)
            drawCombinationRankingDetail(rows: rows, snapshot: snapshot, rect: detailRect, compact: false)
        }

        if isCombinationRankingModelMenuOpen { drawCombinationRankingModelMenu(rows: allRows, content: content) }
    }

    private func drawCombinationRankingExpandHint(rect: NSRect) {
        combinationRankingExpandHintRect = rect
        accentBlue.withAlphaComponent(0.075).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        accentBlue.withAlphaComponent(0.28).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7).stroke()
        drawSymbolIcon("arrow.up.left.and.arrow.down.right", in: NSRect(x: rect.minX + 12, y: rect.minY + 11, width: 14, height: 14), color: accentBlue.withAlphaComponent(0.9), pointSize: 10)
        drawText(reasoningLocalized("展开窗口，查看全部指标与右侧明细", english: "Expand the window to see all metrics and details"), rect: NSRect(x: rect.minX + 36, y: rect.minY + 9, width: max(120, rect.width - 142), height: 18), font: .systemFont(ofSize: 10.5, weight: .semibold), color: NSColor.white.withAlphaComponent(0.68))
        let button = NSRect(x: rect.maxX - 96, y: rect.minY + 6, width: 84, height: 24)
        accentBlue.withAlphaComponent(0.84).setFill()
        NSBezierPath(roundedRect: button, xRadius: 5, yRadius: 5).fill()
        drawCentered(reasoningLocalized("展开窗口", english: "Expand"), rect: button, font: .systemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.96))
    }

    private func drawCombinationRankingFilters(rows: [CombinationRankingRow], content: NSRect) {
        let y = content.minY + 72
        let h: CGFloat = 36
        var x = content.minX
        let timeW = min(CGFloat(280), content.width * 0.31)
        drawFilterLabel(reasoningLocalized("时间", english: "Time"), x: x, y: y - 20, width: timeW)
        x += timeW + 16

        let projectW: CGFloat = content.width < 820 ? 0 : 132
        let modelW = max(CGFloat(220), content.maxX - x - projectW - (projectW > 0 ? 16 : 0))
        drawFilterLabel(reasoningLocalized("模型与思考强度", english: "Models & Reasoning Effort"), x: x, y: y - 20, width: modelW)
        let modelRect = NSRect(x: x, y: y, width: modelW, height: h)
        combinationRankingModelFieldRect = modelRect
        drawCombinationRankingFieldBackground(modelRect)
        drawCombinationRankingSelectedFilterChips(rows: rows, rect: modelRect)
        drawSymbolIcon(isCombinationRankingModelMenuOpen ? "chevron.up" : "chevron.down", in: NSRect(x: modelRect.maxX - 23, y: modelRect.minY + 11, width: 11, height: 11), color: NSColor.white.withAlphaComponent(0.62), pointSize: 9)
        if projectW > 0 {
            x = modelRect.maxX + 16
            drawFilterLabel(reasoningLocalized("项目", english: "Project"), x: x, y: y - 20, width: projectW)
            drawReasoningField(title: reasoningLocalized("全部项目", english: "All Projects"), rect: NSRect(x: x, y: y, width: projectW, height: h), showsChevron: true)
        }
    }

    private func drawFilterLabel(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat) {
        drawText(text, rect: NSRect(x: x, y: y, width: width, height: 16), font: .systemFont(ofSize: 10.5, weight: .semibold), color: NSColor.white.withAlphaComponent(0.54))
    }

    private func drawReasoningTable(rows: [CombinationRankingRow], rect: NSRect, compact: Bool) {
        drawReasoningPanel(rect)
        let toolbarH: CGFloat = 45
        let searchRect = NSRect(x: rect.minX + 10, y: rect.minY + 9, width: min(CGFloat(220), rect.width * 0.34), height: 28)
        drawCombinationRankingFieldBackground(searchRect)
        drawSymbolIcon("magnifyingglass", in: NSRect(x: searchRect.minX + 8, y: searchRect.minY + 8, width: 12, height: 12), color: NSColor.white.withAlphaComponent(0.5), pointSize: 10)
        drawText(reasoningLocalized("搜索指标…", english: "Search metrics…"), rect: NSRect(x: searchRect.minX + 28, y: searchRect.minY + 6, width: searchRect.width - 36, height: 17), font: .systemFont(ofSize: 10.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.36))
        drawRight("\(rows.count) \(reasoningLocalized("种组合", english: "combinations"))", rect: NSRect(x: rect.maxX - 130, y: rect.minY + 15, width: 114, height: 17), color: NSColor.white.withAlphaComponent(0.42), font: .monospacedDigitSystemFont(ofSize: 10, weight: .medium))

        let columns = reasoningTableColumns(compact: compact)
        let totalWidth = columns.reduce(CGFloat(0)) { $0 + $1.width }
        let available = rect.width - 20
        let scale = min(CGFloat(1), available / totalWidth)
        let headerY = rect.minY + toolbarH
        let headerH: CGFloat = 42
        NSColor.white.withAlphaComponent(0.025).setFill()
        NSRect(x: rect.minX + 1, y: headerY, width: rect.width - 2, height: headerH).fill()
        var x = rect.minX + 10
        for column in columns {
            let width = column.width * scale
            let headerRect = NSRect(x: x, y: headerY, width: width, height: headerH)
            combinationRankingSortRects[column.sort] = headerRect
            let isSelectedSort = selectedCombinationRankingSort == column.sort
            let titleTrailingInset: CGFloat = isSelectedSort ? 21 : 10
            drawTableText(column.title, rect: NSRect(x: x + 5, y: headerY + 12, width: width - titleTrailingInset, height: 18), font: .systemFont(ofSize: 9.3, weight: .semibold), color: NSColor.white.withAlphaComponent(isSelectedSort ? 0.76 : 0.48), alignment: column.alignment)
            if isSelectedSort {
                drawSymbolIcon(isCombinationRankingSortAscending ? "chevron.up" : "chevron.down", in: NSRect(x: headerRect.maxX - 13, y: headerRect.minY + 13, width: 7, height: 8), color: accentBlue.withAlphaComponent(0.9), pointSize: 7)
            }
            x += width
        }

        let footerH: CGFloat = 42
        let rowArea = max(CGFloat(1), rect.height - toolbarH - headerH - footerH)
        let rowH: CGFloat = compact ? 38 : 36
        let limit = max(1, min(rows.count, Int(rowArea / rowH)))
        for (index, row) in rows.prefix(limit).enumerated() {
            let y = headerY + headerH + CGFloat(index) * rowH
            let rowRect = NSRect(x: rect.minX + 4, y: y, width: rect.width - 8, height: rowH)
            combinationRankingRowRects[row.key] = rowRect
            if selectedCombinationRankingCell == row.key {
                accentBlue.withAlphaComponent(0.20).setFill()
                NSBezierPath(roundedRect: rowRect, xRadius: 4, yRadius: 4).fill()
                accentBlue.withAlphaComponent(0.8).setFill()
                NSRect(x: rowRect.minX, y: rowRect.minY + 2, width: 2, height: rowRect.height - 4).fill()
            }
            x = rect.minX + 10
            for (columnIndex, column) in columns.enumerated() {
                let width = column.width * scale
                if columnIndex == 1 {
                    drawCombinationRankingEffortChip(row.effort, rect: NSRect(x: x + 5, y: y + 8, width: min(width - 10, 62), height: 21))
                } else {
                    drawTableText(column.value(row), rect: NSRect(x: x + 5, y: y + 10, width: width - 10, height: 18), font: columnIndex == 0 ? .systemFont(ofSize: 10, weight: .semibold) : .monospacedDigitSystemFont(ofSize: 9.6, weight: .medium), color: NSColor.white.withAlphaComponent(columnIndex == 0 ? 0.88 : 0.72), alignment: column.alignment)
                }
                x += width
            }
            NSColor.white.withAlphaComponent(0.05).setFill()
            NSRect(x: rect.minX + 10, y: rowRect.maxY - 1, width: rect.width - 20, height: 1).fill()
        }

        let footerY = rect.maxY - footerH
        NSColor.white.withAlphaComponent(0.07).setFill()
        NSRect(x: rect.minX + 10, y: footerY, width: rect.width - 20, height: 1).fill()
        let totalTasks = rows.reduce(0) { $0 + $1.tasks }
        let totalUsage = rows.reduce(into: Usage()) { $0.add($1.usage) }
        let totalCost = rows.reduce(0.0) { $0 + $1.apiEstimate.usdValue }
        drawText(reasoningLocalized("总计", english: "Total"), rect: NSRect(x: rect.minX + 16, y: footerY + 13, width: 52, height: 18), font: .systemFont(ofSize: 10.5, weight: .bold), color: NSColor.white.withAlphaComponent(0.8))
        drawText("\(format(Int64(totalTasks))) \(reasoningLocalized("会话", english: "sessions"))  ·  \(reasoningCompactTokens(totalUsage.total))  ·  \(combinationRankingMoney(totalCost))", rect: NSRect(x: rect.minX + 72, y: footerY + 13, width: rect.width - 88, height: 18), font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold), color: accentBlue.withAlphaComponent(0.82))
    }

    private func reasoningTableColumns(compact: Bool) -> [ReasoningTableColumn] {
        let model = ReasoningTableColumn(sort: .model, title: reasoningLocalized("模型", english: "Model"), width: compact ? 142 : 138, alignment: .left, value: { $0.model })
        let effort = ReasoningTableColumn(sort: .effort, title: reasoningLocalized("思考强度", english: "Effort"), width: 76, alignment: .left, value: { $0.effort })
        let projects = ReasoningTableColumn(sort: .projects, title: reasoningLocalized("项目数", english: "Projects"), width: 62, alignment: .right, value: { $0.projects.map(String.init) ?? "—" })
        let tasks = ReasoningTableColumn(sort: .tasks, title: reasoningLocalized("会话数", english: "Sessions"), width: 64, alignment: .right, value: { row in format(Int64(row.tasks)) })
        let total = ReasoningTableColumn(sort: .totalTokens, title: reasoningLocalized("总 Token", english: "Total Token"), width: 78, alignment: .right, value: { self.reasoningCompactTokens($0.usage.total) })
        let average = ReasoningTableColumn(sort: .averageTokens, title: reasoningLocalized("平均 Token/会话", english: "Avg Token/Session"), width: 104, alignment: .right, value: { self.reasoningCompactTokens($0.averageTokensPerTask) })
        if compact { return [model, effort, tasks, total, average] }
        return [
            model, effort, projects, tasks, total, average,
            .init(sort: .freshInput, title: reasoningLocalized("新鲜输入", english: "Fresh Input"), width: 78, alignment: .right, value: { self.reasoningCompactTokens($0.freshInput) }),
            .init(sort: .cachedInput, title: reasoningLocalized("缓存输入", english: "Cached Input"), width: 78, alignment: .right, value: { self.reasoningCompactTokens($0.usage.cachedInput) }),
            .init(sort: .output, title: reasoningLocalized("输出", english: "Output"), width: 70, alignment: .right, value: { self.reasoningCompactTokens($0.visibleOutput) }),
            .init(sort: .reasoningOutput, title: reasoningLocalized("推理输出", english: "Reasoning"), width: 76, alignment: .right, value: { self.reasoningCompactTokens($0.usage.reasoningOutput) }),
            .init(sort: .totalCost, title: reasoningLocalized("API 等价成本", english: "API Cost"), width: 96, alignment: .right, value: { self.combinationRankingMoney($0.apiEstimate.usdValue) }),
            .init(sort: .costPerTask, title: reasoningLocalized("成本/会话", english: "Cost/Session"), width: 90, alignment: .right, value: { self.combinationRankingMoney($0.costPerTask) })
        ]
    }

    private func drawTableText(_ text: String, rect: NSRect, font: NSFont, color: NSColor, alignment: NSTextAlignment) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    }

    private func drawCombinationRankingDetail(rows: [CombinationRankingRow], snapshot: DetailsSnapshot, rect: NSRect, compact: Bool) {
        drawReasoningPanel(rect)
        drawText(reasoningLocalized("明细", english: "Details"), rect: NSRect(x: rect.minX + 14, y: rect.minY + 13, width: rect.width - 28, height: 22), font: .systemFont(ofSize: 14, weight: .bold), color: NSColor.white.withAlphaComponent(0.9))
        guard let key = selectedCombinationRankingCell, let row = rows.first(where: { $0.key == key }) else { return }
        let titleY = rect.minY + 48
        drawTruncatedText(row.model, rect: NSRect(x: rect.minX + 14, y: titleY, width: rect.width - 92, height: 24), font: .systemFont(ofSize: 16, weight: .bold), color: accentBlue)
        drawRight("× \(combinationRankingEffortTitle(row.effort))", rect: NSRect(x: rect.maxX - 92, y: titleY + 2, width: 78, height: 20), color: combinationRankingEffortColor(row.effort), font: .systemFont(ofSize: 12, weight: .bold))
        let daily = combinationDailyRows(for: row, snapshot: snapshot)
        let dateText: String
        if !daily.isEmpty {
            dateText = "\(daily.first!.day) — \(daily.last!.day)"
        } else if selectedInsightWindowDays == 0,
                  let start = snapshot.reasoningRangeStart,
                  let end = snapshot.reasoningRangeEnd {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = appTimeZone()
            formatter.dateFormat = "yyyy-MM-dd"
            dateText = "\(formatter.string(from: start)) — \(formatter.string(from: end))"
        } else {
            dateText = reasoningLocalized("最近 \(selectedInsightWindowDays) 天", english: "Last \(selectedInsightWindowDays) days")
        }
        drawText(dateText, rect: NSRect(x: rect.minX + 14, y: titleY + 27, width: rect.width - 28, height: 16), font: .monospacedDigitSystemFont(ofSize: 9.2, weight: .medium), color: NSColor.white.withAlphaComponent(0.42))

        let overviewY = titleY + 58
        drawDetailSectionTitle(reasoningLocalized("会话概览", english: "Session Overview"), rect: rect, y: overviewY)
        let overview: [(String, String)] = [
            (reasoningLocalized("项目数", english: "Projects"), row.projects.map { format(Int64($0)) } ?? "—"),
            (reasoningLocalized("会话数", english: "Sessions"), format(Int64(row.tasks))),
            (reasoningLocalized("轮次", english: "Turns"), format(Int64(row.runs))),
            (reasoningLocalized("总 Token", english: "Total Token"), format(row.usage.total)),
            (reasoningLocalized("平均 Token/会话", english: "Avg Token/Session"), format(row.averageTokensPerTask)),
            (reasoningLocalized("API 等价成本", english: "API Cost"), combinationRankingMoney(row.apiEstimate.usdValue)),
            (reasoningLocalized("成本/会话", english: "Cost/Session"), combinationRankingMoney(row.costPerTask))
        ]
        var y = overviewY + 24
        for item in overview { drawDetailValue(label: item.0, value: item.1, rect: rect, y: y); y += 20 }

        y += 9
        drawDetailSectionTitle(reasoningLocalized("Token 明细（具体数值）", english: "Token Details"), rect: rect, y: y)
        y += 24
        drawCombinationTokenComposition(usage: row.usage, rect: NSRect(x: rect.minX + 14, y: y, width: rect.width - 28, height: 10))
        y += 20
        let composition: [(String, Int64, NSColor)] = [
            (reasoningLocalized("新鲜输入", english: "Fresh input"), row.freshInput, accentBlue),
            (reasoningLocalized("缓存输入", english: "Cached input"), row.usage.cachedInput, combinationRankingEffortColor("xhigh")),
            (reasoningLocalized("输出", english: "Output"), row.visibleOutput, accentTeal),
            (reasoningLocalized("推理输出", english: "Reasoning output"), row.usage.reasoningOutput, combinationRankingEffortColor("max"))
        ]
        for item in composition {
            item.2.setFill(); NSRect(x: rect.minX + 15, y: y + 5, width: 7, height: 7).fill()
            let percent = row.usage.total > 0 ? Double(item.1) / Double(row.usage.total) * 100 : 0
            drawText(item.0, rect: NSRect(x: rect.minX + 28, y: y, width: rect.width * 0.43, height: 17), font: .systemFont(ofSize: 9.3, weight: .medium), color: NSColor.white.withAlphaComponent(0.58))
            drawRight("\(format(item.1))  \(String(format: "%.1f%%", percent))", rect: NSRect(x: rect.minX + rect.width * 0.43, y: y, width: rect.width * 0.57 - 14, height: 17), color: NSColor.white.withAlphaComponent(0.82), font: .monospacedDigitSystemFont(ofSize: 9.2, weight: .semibold))
            y += 19
        }

        let samples = daily.flatMap(\.runTokenTotals).sorted()
        if !samples.isEmpty, y + 132 < rect.maxY {
            y += 8
            drawDetailSectionTitle(reasoningLocalized("统计分布（每轮 Token）", english: "Distribution"), rect: rect, y: y)
            y += 24
            let stats: [(String, Int64)] = [
                ("P50", percentile(samples, 0.50)), ("P90", percentile(samples, 0.90)),
                ("P95", percentile(samples, 0.95)), (reasoningLocalized("最大值", english: "Max"), samples.last ?? 0),
                (reasoningLocalized("最小值", english: "Min"), samples.first ?? 0)
            ]
            for item in stats { drawDetailValue(label: item.0, value: format(item.1), rect: rect, y: y); y += 19 }
        }

        if !daily.isEmpty, y + 112 < rect.maxY {
            y += 8
            drawDetailSectionTitle(reasoningLocalized("每日趋势（总 Token）", english: "Daily Trend"), rect: rect, y: y)
            y += 24
            drawCombinationDailyTrend(daily, rect: NSRect(x: rect.minX + 14, y: y, width: rect.width - 28, height: min(110, rect.maxY - y - 12)))
        }
    }

    private func drawDetailSectionTitle(_ text: String, rect: NSRect, y: CGFloat) {
        NSColor.white.withAlphaComponent(0.07).setFill(); NSRect(x: rect.minX + 14, y: y - 8, width: rect.width - 28, height: 1).fill()
        drawText(text, rect: NSRect(x: rect.minX + 14, y: y, width: rect.width - 28, height: 18), font: .systemFont(ofSize: 10, weight: .bold), color: NSColor.white.withAlphaComponent(0.72))
    }

    private func drawDetailValue(label: String, value: String, rect: NSRect, y: CGFloat) {
        drawText(label, rect: NSRect(x: rect.minX + 14, y: y, width: rect.width * 0.53, height: 17), font: .systemFont(ofSize: 9.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.52))
        drawRight(value, rect: NSRect(x: rect.minX + rect.width * 0.50, y: y, width: rect.width * 0.50 - 14, height: 17), color: NSColor.white.withAlphaComponent(0.88), font: .monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold))
    }

    private func drawCombinationDailyTrend(_ rows: [ReasoningDailyModelEffortSummary], rect: NSRect) {
        let values = rows.map { $0.usage.total }
        let maxValue = max(Int64(1), values.max() ?? 1)
        let step = rect.width / CGFloat(max(1, rows.count - 1))
        let path = NSBezierPath()
        var points: [NSPoint] = []
        for (index, value) in values.enumerated() {
            let point = NSPoint(x: rect.minX + CGFloat(index) * step, y: rect.maxY - CGFloat(Double(value) / Double(maxValue)) * (rect.height - 14))
            points.append(point)
            let zoneWidth = max(CGFloat(12), rows.count > 1 ? step : rect.width)
            reasoningTrendDayRects[rows[index].day] = NSRect(x: point.x - zoneWidth / 2, y: rect.minY, width: zoneWidth, height: rect.height)
            index == 0 ? path.move(to: point) : path.line(to: point)
        }
        accentTeal.setStroke(); path.lineWidth = 1.8; path.stroke()
        drawText(reasoningCompactTokens(values.first ?? 0), rect: NSRect(x: rect.minX, y: rect.maxY - 13, width: rect.width / 2, height: 13), font: .monospacedDigitSystemFont(ofSize: 8, weight: .medium), color: NSColor.white.withAlphaComponent(0.35))
        drawRight(reasoningCompactTokens(values.last ?? 0), rect: NSRect(x: rect.midX, y: rect.maxY - 13, width: rect.width / 2, height: 13), color: NSColor.white.withAlphaComponent(0.35), font: .monospacedDigitSystemFont(ofSize: 8, weight: .medium))

        guard let hoveredReasoningDay,
              let index = rows.firstIndex(where: { $0.day == hoveredReasoningDay }),
              points.indices.contains(index) else { return }
        let point = points[index]
        NSColor.white.withAlphaComponent(0.28).setStroke()
        let guide = NSBezierPath()
        guide.move(to: NSPoint(x: point.x, y: rect.minY))
        guide.line(to: NSPoint(x: point.x, y: rect.maxY))
        guide.lineWidth = 1
        guide.setLineDash([3, 3], count: 2, phase: 0)
        guide.stroke()
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7)).fill()
        accentTeal.setStroke()
        let dot = NSBezierPath(ovalIn: NSRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
        dot.lineWidth = 1.5
        dot.stroke()

        let tooltipWidth = min(CGFloat(176), rect.width)
        let tooltipHeight: CGFloat = 44
        let tooltipX = min(max(rect.minX, point.x - tooltipWidth / 2), rect.maxX - tooltipWidth)
        let tooltipY = max(rect.minY, min(rect.maxY - tooltipHeight, point.y - tooltipHeight - 8))
        let tooltip = NSRect(x: tooltipX, y: tooltipY, width: tooltipWidth, height: tooltipHeight)
        NSColor(calibratedRed: 0.035, green: 0.050, blue: 0.072, alpha: 0.98).setFill()
        NSBezierPath(roundedRect: tooltip, xRadius: 7, yRadius: 7).fill()
        borderColor.setStroke()
        NSBezierPath(roundedRect: tooltip.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7).stroke()
        drawText(rows[index].day, rect: NSRect(x: tooltip.minX + 10, y: tooltip.minY + 7, width: tooltip.width - 20, height: 14), font: .monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold), color: NSColor.white.withAlphaComponent(0.72))
        drawText(reasoningLocalized("总 Token", english: "Total Token"), rect: NSRect(x: tooltip.minX + 10, y: tooltip.minY + 24, width: 62, height: 14), font: .systemFont(ofSize: 9.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
        drawRight(format(rows[index].usage.total), rect: NSRect(x: tooltip.minX + 66, y: tooltip.minY + 23, width: tooltip.width - 76, height: 15), color: accentTeal, font: .monospacedDigitSystemFont(ofSize: 9.5, weight: .bold))
    }

    private func percentile(_ sorted: [Int64], _ percentile: Double) -> Int64 {
        guard !sorted.isEmpty else { return 0 }
        let index = Int((Double(sorted.count - 1) * percentile).rounded())
        return sorted[min(sorted.count - 1, max(0, index))]
    }

    private func combinationDailyRows(for row: CombinationRankingRow, snapshot: DetailsSnapshot) -> [ReasoningDailyModelEffortSummary] {
        let report: ReasoningInsightsReport?
        switch row.platform {
        case "Codex":
            report = snapshot.codexRepoInsightReports[selectedInsightWindowDays]?.reasoning ?? snapshot.codexRepoInsights.reasoning
        case "API":
            report = snapshot.apiRepoInsightReports[selectedInsightWindowDays]?.reasoning ?? snapshot.apiRepoInsights.reasoning
        default:
            return []
        }
        return report?.dailyModelEfforts.filter { $0.model == row.model && $0.effort == row.effort }.sorted { $0.day < $1.day } ?? []
    }

    private func drawCombinationRankingSelectedFilterChips(rows: [CombinationRankingRow], rect: NSRect) {
        let models = combinationRankingAvailableModels(rows).filter(selectedCombinationRankingModels.contains)
        var x = rect.minX + 8
        var shown = 0
        for model in models {
            let font = NSFont.systemFont(ofSize: 10, weight: .medium)
            let selectedEfforts = combinationRankingAvailableEfforts(rows, model: model)
                .filter { selectedCombinationRankingEffortsByModel[model]?.contains($0) == true }
            let effortSummary: String
            if selectedEfforts.count == 1, let effort = selectedEfforts.first {
                effortSummary = combinationRankingEffortTitle(effort)
            } else {
                effortSummary = reasoningLocalized("\(selectedEfforts.count) 档", english: "\(selectedEfforts.count) levels")
            }
            let title = "\(model) · \(effortSummary)"
            let width = min(CGFloat(190), measuredTextWidth(title, font: font) + 22)
            guard x + width < rect.maxX - 42 else { break }
            let chip = NSRect(x: x, y: rect.minY + 6, width: width, height: 24)
            NSColor.white.withAlphaComponent(0.055).setFill(); NSBezierPath(roundedRect: chip, xRadius: 5, yRadius: 5).fill()
            borderColor.setStroke(); NSBezierPath(roundedRect: chip.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5).stroke()
            drawTruncatedText(title, rect: NSRect(x: chip.minX + 7, y: chip.minY + 5, width: chip.width - 14, height: 15), font: font, color: NSColor.white.withAlphaComponent(0.82))
            x += width + 6; shown += 1
        }
        if shown < models.count { drawText("+\(models.count - shown)", rect: NSRect(x: x, y: rect.minY + 10, width: 30, height: 17), font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold), color: accentBlue) }
    }

    private func drawCombinationRankingModelMenu(rows: [CombinationRankingRow], content: NSRect) {
        guard let field = combinationRankingModelFieldRect else { return }
        let models = combinationRankingAvailableModels(rows)
        let activeModel = activeCombinationRankingModel ?? selectedCombinationRankingModels.sorted().first ?? models.first
        let efforts = activeModel.map { combinationRankingAvailableEfforts(rows, model: $0) } ?? []
        let desiredMenuHeight = CGFloat(max(models.count, efforts.count)) * 30 + 42
        let availableMenuHeight = max(CGFloat(72), content.maxY - field.maxY - 6)
        let menuHeight = min(desiredMenuHeight, availableMenuHeight)
        let menu = NSRect(x: field.minX, y: field.maxY + 6, width: field.width, height: menuHeight)
        combinationRankingModelMenuRect = menu
        NSColor(calibratedRed: 0.045, green: 0.065, blue: 0.091, alpha: 0.99).setFill(); NSBezierPath(roundedRect: menu, xRadius: 8, yRadius: 8).fill()
        borderColor.setStroke(); NSBezierPath(roundedRect: menu.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
        let dividerX = menu.minX + floor(menu.width * 0.58)
        drawText(reasoningLocalized("选择模型", english: "Select Models"), rect: NSRect(x: menu.minX + 14, y: menu.minY + 10, width: dividerX - menu.minX - 22, height: 18), font: .systemFont(ofSize: 10.5, weight: .semibold), color: NSColor.white.withAlphaComponent(0.52))
        drawText(activeModel.map { "\($0) · \(reasoningLocalized("思考强度", english: "Effort"))" } ?? reasoningLocalized("思考强度", english: "Reasoning Effort"), rect: NSRect(x: dividerX + 12, y: menu.minY + 10, width: menu.maxX - dividerX - 24, height: 18), font: .systemFont(ofSize: 10.5, weight: .semibold), color: NSColor.white.withAlphaComponent(0.52))
        NSColor.white.withAlphaComponent(0.07).setFill()
        NSRect(x: dividerX, y: menu.minY + 8, width: 1, height: menu.height - 16).fill()
        for (index, model) in models.prefix(Int((menuHeight - 36) / 30)).enumerated() {
            let row = NSRect(x: menu.minX + 8, y: menu.minY + 34 + CGFloat(index) * 30, width: dividerX - menu.minX - 16, height: 28)
            combinationRankingModelOptionRects[model] = row
            let checked = selectedCombinationRankingModels.contains(model)
            if activeModel == model {
                NSColor.white.withAlphaComponent(0.055).setFill()
                NSBezierPath(roundedRect: row, xRadius: 5, yRadius: 5).fill()
            }
            let checkbox = NSRect(x: row.minX + 7, y: row.minY + 7, width: 14, height: 14)
            combinationRankingModelCheckboxRects[model] = checkbox.insetBy(dx: -4, dy: -4)
            (checked ? accentBlue : NSColor.white.withAlphaComponent(0.08)).setFill(); NSBezierPath(roundedRect: checkbox, xRadius: 3, yRadius: 3).fill()
            if checked { drawSymbolIcon("checkmark", in: NSRect(x: row.minX + 9, y: row.minY + 9, width: 10, height: 10), color: .white, pointSize: 8) }
            drawText(model, rect: NSRect(x: row.minX + 30, y: row.minY + 6, width: row.width - 54, height: 17), font: .systemFont(ofSize: 10.5, weight: .semibold), color: NSColor.white.withAlphaComponent(0.82))
            drawSymbolIcon("chevron.right", in: NSRect(x: row.maxX - 16, y: row.minY + 10, width: 7, height: 9), color: NSColor.white.withAlphaComponent(activeModel == model ? 0.72 : 0.3), pointSize: 7)
        }
        for (index, effort) in efforts.prefix(Int((menuHeight - 36) / 30)).enumerated() {
            let row = NSRect(x: dividerX + 5, y: menu.minY + 34 + CGFloat(index) * 30, width: menu.maxX - dividerX - 13, height: 28)
            combinationRankingEffortOptionRects[effort] = row
            let checked = activeModel.flatMap { selectedCombinationRankingEffortsByModel[$0] }?.contains(effort) == true
            (checked ? combinationRankingEffortColor(effort).withAlphaComponent(0.88) : NSColor.white.withAlphaComponent(0.08)).setFill()
            NSBezierPath(roundedRect: NSRect(x: row.minX + 7, y: row.minY + 7, width: 14, height: 14), xRadius: 3, yRadius: 3).fill()
            if checked { drawSymbolIcon("checkmark", in: NSRect(x: row.minX + 9, y: row.minY + 9, width: 10, height: 10), color: .white, pointSize: 8) }
            drawText(combinationRankingEffortTitle(effort), rect: NSRect(x: row.minX + 30, y: row.minY + 6, width: row.width - 38, height: 17), font: .systemFont(ofSize: 10.5, weight: .semibold), color: NSColor.white.withAlphaComponent(0.82))
        }
    }

    private func drawCombinationRankingFieldBackground(_ rect: NSRect) {
        inputSurfaceColor.withAlphaComponent(0.82).setFill(); NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        borderColor.setStroke(); NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7).stroke()
    }

    private func drawCombinationRankingEffortChip(_ effort: String, rect: NSRect) {
        combinationRankingEffortColor(effort).withAlphaComponent(effort == "none" ? 0.24 : 0.82).setFill(); NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        drawCentered(combinationRankingEffortTitle(effort), rect: rect, font: .systemFont(ofSize: 9, weight: .semibold), color: NSColor.white.withAlphaComponent(0.94))
    }

    private func drawCombinationTokenComposition(usage: Usage, rect: NSRect) {
        let values: [(Int64, NSColor)] = [(max(0, usage.input - usage.cachedInput), accentBlue), (usage.cachedInput, combinationRankingEffortColor("xhigh")), (max(0, usage.output - usage.reasoningOutput), accentTeal), (usage.reasoningOutput, combinationRankingEffortColor("max"))]
        let total = max(Int64(1), values.reduce(0) { $0 + $1.0 })
        var x = rect.minX
        for item in values where item.0 > 0 { let width = rect.width * CGFloat(Double(item.0) / Double(total)); item.1.setFill(); NSRect(x: x, y: rect.minY, width: width, height: rect.height).fill(); x += width }
    }

    private func combinationRankingRows(snapshot: DetailsSnapshot) -> [CombinationRankingRow] {
        func localRows(_ report: ReasoningInsightsReport?, platform: String) -> [CombinationRankingRow] {
            report?.modelEfforts.filter {
                $0.runs > 0 && $0.effort != "unknown" && $0.model != "Unknown model"
            }.map { entry in
                CombinationRankingRow(model: entry.model, platform: platform, effort: entry.effort, projects: entry.projectCount, tasks: entry.tasks, runs: entry.runs, usage: entry.usage, medianTokens: entry.medianTokens, p90Tokens: entry.p90Tokens)
            } ?? []
        }
        let codexReasoning = snapshot.codexRepoInsightReports[selectedInsightWindowDays]?.reasoning ?? snapshot.codexRepoInsights.reasoning
        let apiReasoning = snapshot.apiRepoInsightReports[selectedInsightWindowDays]?.reasoning ?? snapshot.apiRepoInsights.reasoning
        var rows = localRows(codexReasoning, platform: "Codex")
        rows.append(contentsOf: localRows(apiReasoning, platform: "API"))
        let claudeReport = selectedInsightWindowDays == 0 ? (snapshot.reasoningClaude ?? snapshot.claude) : snapshot.claude
        rows.append(contentsOf: combinationRankingClaudeRows(report: claudeReport, days: selectedInsightWindowDays))
        switch selectedDetailsSource {
        case .all:
            let enabledPlatforms = Set(QuotaViewOption.visiblePlatformCases.map { source in
                switch source {
                case .codex: return "Codex"
                case .claude: return "Claude"
                case .api: return "API"
                case .all: return ""
                }
            })
            return rows.filter { enabledPlatforms.contains($0.platform) }
        case .codex: return rows.filter { $0.platform == "Codex" }
        case .claude: return rows.filter { $0.platform == "Claude" }
        case .api: return rows.filter { $0.platform == "API" }
        }
    }

    private func combinationRankingClaudeRows(report: TokenReport, days: Int) -> [CombinationRankingRow] {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = appTimeZone(); formatter.dateFormat = "yyyy-MM-dd"
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = appTimeZone()
        let start = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: calendar.startOfDay(for: report.scannedAt)) ?? report.scannedAt
        let cutoff = formatter.string(from: start)
        var buckets: [String: ModelUsage] = [:]
        if days == 0 {
            buckets = Dictionary(uniqueKeysWithValues: report.modelBreakdown.map { ($0.name, $0) })
        } else {
            for day in report.byDay where day.day >= cutoff { for model in day.modelBreakdown { var value = buckets[model.name] ?? ModelUsage(name: model.name, usage: Usage(), events: 0, sessions: 0); value.usage.add(model.usage); value.turns += model.turns; value.events += model.events; value.sessions += model.sessions; buckets[model.name] = value } }
        }
        if days >= 90, buckets.isEmpty { buckets = Dictionary(uniqueKeysWithValues: report.modelBreakdown.map { ($0.name, $0) }) }
        return buckets.values.filter { $0.usage.total > 0 }.map { model in
            let tasks = max(1, model.sessions), average = model.usage.total / Int64(tasks)
            return CombinationRankingRow(model: model.name, platform: "Claude", effort: "none", projects: nil, tasks: tasks, runs: max(tasks, model.events), usage: model.usage, medianTokens: average, p90Tokens: average)
        }
    }

    private func combinationRankingAvailableModels(_ rows: [CombinationRankingRow]) -> [String] {
        Set(rows.map(\.model)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    private func combinationRankingAvailableEfforts(_ rows: [CombinationRankingRow], model: String) -> [String] {
        let available = Set(rows.filter { $0.model == model }.map(\.effort))
        let order = ["low", "medium", "high", "xhigh", "ultra", "max", "none", "unavailable"]
        return order.filter(available.contains) + available.filter { !order.contains($0) }.sorted()
    }
    private func combinationRankingHighestUsageModel(_ rows: [CombinationRankingRow]) -> String? {
        Dictionary(grouping: rows, by: \.model).max { lhs, rhs in
            let lhsTotal = lhs.value.reduce(Int64(0)) { $0 + $1.usage.total }
            let rhsTotal = rhs.value.reduce(Int64(0)) { $0 + $1.usage.total }
            if lhsTotal != rhsTotal { return lhsTotal < rhsTotal }
            return lhs.key.localizedStandardCompare(rhs.key) == .orderedDescending
        }?.key
    }
    private func combinationRankingVisibleRows(_ rows: [CombinationRankingRow]) -> [CombinationRankingRow] {
        rows.filter {
            selectedCombinationRankingModels.contains($0.model)
                && selectedCombinationRankingEffortsByModel[$0.model]?.contains($0.effort) == true
        }
    }
    private func combinationRankingSortedRows(_ rows: [CombinationRankingRow]) -> [CombinationRankingRow] {
        rows.sorted { lhs, rhs in
            if selectedCombinationRankingSort == .model {
                let modelComparison = lhs.model.localizedStandardCompare(rhs.model)
                if modelComparison != .orderedSame {
                    return isCombinationRankingSortAscending
                        ? modelComparison == .orderedAscending
                        : modelComparison == .orderedDescending
                }

                let effortComparison = compareNumbers(
                    combinationRankingEffortRank(lhs.effort),
                    combinationRankingEffortRank(rhs.effort)
                )
                if effortComparison != .orderedSame {
                    return effortComparison == .orderedAscending
                }
            }
            if selectedCombinationRankingSort == .projects {
                if lhs.projects == nil, rhs.projects != nil { return false }
                if lhs.projects != nil, rhs.projects == nil { return true }
            }
            let comparison = combinationRankingComparison(lhs, rhs, column: selectedCombinationRankingSort)
            if comparison == .orderedSame {
                let leftKey = "\(lhs.model)\u{1F}\(lhs.effort)"
                let rightKey = "\(rhs.model)\u{1F}\(rhs.effort)"
                return leftKey.localizedStandardCompare(rightKey) == .orderedAscending
            }
            return isCombinationRankingSortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }

    private func combinationRankingComparison(_ lhs: CombinationRankingRow, _ rhs: CombinationRankingRow, column: CombinationRankingSortColumn) -> ComparisonResult {
        switch column {
        case .model:
            return lhs.model.localizedStandardCompare(rhs.model)
        case .effort:
            return compareNumbers(combinationRankingEffortRank(lhs.effort), combinationRankingEffortRank(rhs.effort))
        case .projects:
            return compareNumbers(lhs.projects ?? 0, rhs.projects ?? 0)
        case .tasks:
            return compareNumbers(lhs.tasks, rhs.tasks)
        case .totalTokens:
            return compareNumbers(lhs.usage.total, rhs.usage.total)
        case .averageTokens:
            return compareNumbers(lhs.averageTokensPerTask, rhs.averageTokensPerTask)
        case .freshInput:
            return compareNumbers(lhs.freshInput, rhs.freshInput)
        case .cachedInput:
            return compareNumbers(lhs.usage.cachedInput, rhs.usage.cachedInput)
        case .output:
            return compareNumbers(lhs.visibleOutput, rhs.visibleOutput)
        case .reasoningOutput:
            return compareNumbers(lhs.usage.reasoningOutput, rhs.usage.reasoningOutput)
        case .totalCost:
            return compareNumbers(lhs.apiEstimate.usdValue, rhs.apiEstimate.usdValue)
        case .costPerTask:
            return compareNumbers(lhs.costPerTask, rhs.costPerTask)
        }
    }

    private func compareNumbers<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        lhs == rhs ? .orderedSame : (lhs < rhs ? .orderedAscending : .orderedDescending)
    }

    private func combinationRankingEffortRank(_ effort: String) -> Int {
        ["low", "medium", "high", "xhigh", "ultra", "max", "none", "unavailable"].firstIndex(of: effort) ?? Int.max
    }
    private func combinationRankingEffortTitle(_ effort: String) -> String {
        switch effort {
        case "none": return reasoningLocalized("无等级", english: "No Level")
        case "unavailable": return reasoningLocalized("未提供", english: "Unavailable")
        default: return effort
        }
    }
    private func combinationRankingEffortColor(_ effort: String) -> NSColor {
        switch effort {
        case "none": return NSColor(calibratedRed: 0.20, green: 0.67, blue: 0.65, alpha: 1)
        case "unavailable": return NSColor(calibratedWhite: 0.72, alpha: 1)
        default: return reasoningEffortColor(effort)
        }
    }
    private func combinationRankingMoney(_ usdValue: Double) -> String { displayAPIMoney(usdValue, source: selectedDetailsSource) }
}
