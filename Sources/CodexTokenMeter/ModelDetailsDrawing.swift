import Cocoa

struct ModelUsageHoverRow {
    let rect: NSRect
    let title: String
    let subtitle: String?
    let usage: Usage
    let shareText: String?
    let sessions: Int?
    let events: Int?
    let apiCostText: String?
    let apiCostColor: NSColor
}

extension UsageDetailsView {
    func drawModelsPage(snapshot: DetailsSnapshot, content: NSRect) {
        modelUsageHoverRows.removeAll(keepingCapacity: true)
        drawQuotaRows(snapshot: snapshot, content: content, y: content.minY + 78, height: 128)
        let presentation = modelListPresentation(for: snapshot)
        let tableHeight = presentation.tableHeight
        let tableY = content.minY + 222
        drawModelsTable(presentation: presentation, content: content, y: tableY, height: tableHeight)
        let noteY = tableY + tableHeight + 16
        let noteRect = NSRect(x: content.minX, y: noteY, width: content.width, height: min(116, content.maxY - noteY))
        drawPanel(noteRect)
        let report = sourceReport(for: snapshot)
        let scannedAt = DateFormatter.localizedString(from: report.scannedAt, dateStyle: .short, timeStyle: .short)
        let sourceText = String(format: t(.modelTrustSourceFormat), selectedDetailsSource.fallbackTitle, scannedAt)
        let identificationText = String(
            format: t(.modelTrustIdentificationFormat),
            presentation.identificationCoveragePercent,
            presentation.hiddenUnknownCount
        )
        let pricingText = String(
            format: t(.modelTrustPricingFormat),
            presentation.pricingCoveragePercent,
            presentation.unpricedModelCount
        )
        let trustRows = [sourceText, identificationText, pricingText, t(.modelGroupingNote)]
        for (index, text) in trustRows.enumerated() {
            drawText(
                text,
                rect: NSRect(x: noteRect.minX + 16, y: noteRect.minY + 14 + CGFloat(index) * 24, width: noteRect.width - 32, height: 18),
                font: .systemFont(ofSize: 12, weight: index == 0 ? .semibold : .medium),
                color: NSColor.white.withAlphaComponent(index < 3 ? 0.66 : 0.44)
            )
        }
    }

    func drawModelUsageRowTooltip(container: NSRect) {
        guard let hoveredModelUsageRowIndex,
              modelUsageHoverRows.indices.contains(hoveredModelUsageRowIndex) else {
            return
        }
        let row = modelUsageHoverRows[hoveredModelUsageRowIndex]
        var lines: [(String, String, NSColor)] = [
            (t(.total), format(row.usage.total), NSColor.white.withAlphaComponent(0.9)),
            (t(.input), format(row.usage.input), NSColor.white.withAlphaComponent(0.78)),
            (t(.output), format(row.usage.output), NSColor.white.withAlphaComponent(0.78))
        ]
        if let shareText = row.shareText {
            lines.append(("%", shareText, NSColor.white.withAlphaComponent(0.74)))
        }
        if let sessions = row.sessions {
            lines.append((t(.sessions), "\(sessions)", NSColor.white.withAlphaComponent(0.72)))
        }
        if let events = row.events {
            lines.append((t(.events), "\(events)", NSColor.white.withAlphaComponent(0.72)))
        }
        if let apiCostText = row.apiCostText {
            lines.append((t(.apiEquivalent), apiCostText, row.apiCostColor))
        }

        let width: CGFloat = 274
        let headerHeight: CGFloat = row.subtitle == nil ? 31 : 49
        let height = headerHeight + CGFloat(lines.count) * 16 + 10
        let gap: CGFloat = 10
        var origin = CGPoint(x: row.rect.midX - width / 2, y: row.rect.maxY + gap)
        if origin.y + height > container.maxY - 10 {
            origin.y = row.rect.minY - height - gap
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

        drawTruncatedText(row.title, rect: NSRect(x: tooltipRect.minX + 10, y: tooltipRect.minY + 8, width: tooltipRect.width - 20, height: 16), font: .systemFont(ofSize: 11, weight: .bold), color: .white)
        if let subtitle = row.subtitle {
            drawTruncatedText(subtitle, rect: NSRect(x: tooltipRect.minX + 10, y: tooltipRect.minY + 27, width: tooltipRect.width - 20, height: 14), font: .systemFont(ofSize: 10, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
        }
        let firstLineY = tooltipRect.minY + headerHeight
        for (index, line) in lines.enumerated() {
            let y = firstLineY + CGFloat(index) * 16
            drawText(line.0, rect: NSRect(x: tooltipRect.minX + 10, y: y, width: 92, height: 14), font: .systemFont(ofSize: 10, weight: .medium), color: NSColor.white.withAlphaComponent(0.5))
            drawRight(line.1, rect: NSRect(x: tooltipRect.minX + 104, y: y - 1, width: tooltipRect.width - 114, height: 15), color: line.2, font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold))
        }
    }

    func drawQuotaRows(snapshot: DetailsSnapshot, content: NSRect, y: CGFloat, height: CGFloat) {
        let rect = NSRect(x: content.minX, y: y, width: content.width, height: height)
        drawPanel(rect)
        drawText(t(.quotaViews), rect: NSRect(x: rect.minX + 16, y: rect.minY + 12, width: rect.width - 32, height: 20), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
        let rows: [(String, String, TokenReport)]
        switch selectedDetailsSource {
        case .all:
            rows = [
                (t(.all), t(.allDescription), snapshot.all),
                (t(.codex), t(.codexDescription), snapshot.codex),
                (t(.claude), t(.claudeDescription), snapshot.claude)
            ]
        case .codex:
            rows = [(t(.codex), t(.codexDescription), snapshot.codex)]
        case .claude:
            rows = [(t(.claude), t(.claudeDescription), snapshot.claude)]
        }
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
            let rowY = rect.minY + 52 + CGFloat(index) * 22
            let rowRect = NSRect(x: rect.minX + 10, y: rowY - 2, width: rect.width - 20, height: 21)
            let rowIndex = modelUsageHoverRows.count
            modelUsageHoverRows.append(ModelUsageHoverRow(
                rect: rowRect,
                title: row.0,
                subtitle: row.1,
                usage: row.2.usage,
                shareText: nil,
                sessions: row.2.sessions,
                events: row.2.events,
                apiCostText: nil,
                apiCostColor: accentTeal
            ))
            if hoveredModelUsageRowIndex == rowIndex {
                NSColor.white.withAlphaComponent(0.055).setFill()
                NSBezierPath(roundedRect: rowRect, xRadius: 5, yRadius: 5).fill()
            }
            drawText(row.0, rect: NSRect(x: rect.minX + 16, y: rowY, width: 90, height: 18), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
            drawText(row.1, rect: NSRect(x: descriptionX, y: rowY, width: descriptionW, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.45))
            drawRight(compactDashboardMetric(row.2.usage.total), rect: NSRect(x: totalX, y: rowY, width: totalW, height: 18), color: .white)
            drawRight(compactDashboardMetric(row.2.usage.input), rect: NSRect(x: inputX, y: rowY, width: inputW, height: 18), color: NSColor.white.withAlphaComponent(0.58))
            drawRight(compactDashboardMetric(row.2.usage.output), rect: NSRect(x: outputX, y: rowY, width: outputW, height: 18), color: NSColor.white.withAlphaComponent(0.58))
        }
    }

    private func drawModelsTable(presentation: ModelListPresentation, content: NSRect, y: CGFloat, height: CGFloat) {
        let rect = NSRect(x: content.minX, y: y, width: content.width, height: height)
        drawPanel(rect)
        drawText(t(.models), rect: NSRect(x: rect.minX + 16, y: rect.minY + 12, width: 90, height: 20), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
        drawText(
            String(format: t(.modelVisibleCountFormat), presentation.models.count, presentation.knownModelCount),
            rect: NSRect(x: rect.minX + 104, y: rect.minY + 14, width: 170, height: 18),
            font: .systemFont(ofSize: 11, weight: .medium),
            color: NSColor.white.withAlphaComponent(0.45)
        )
        let models = presentation.models
        if models.isEmpty {
            let emptyText = presentation.knownModelCount > 0 ? t(.modelNoSearchResults) : t(.noModelLabelsFound)
            drawText(emptyText, rect: NSRect(x: rect.minX + 16, y: rect.minY + 64, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }
        let totalTokens = presentation.knownTokens
        drawModelShareBar(models: models, totalTokens: totalTokens, rect: NSRect(x: rect.minX + 16, y: rect.minY + 54, width: rect.width - 32, height: 8))

        let showsActivity = rect.width >= 920
        let gap: CGFloat = 10
        let moneyW: CGFloat = 104
        let eventsW: CGFloat = 76
        let sessionsW: CGFloat = 68
        let outputW: CGFloat = 84
        let inputW: CGFloat = 88
        let totalW: CGFloat = 88
        let shareW: CGFloat = 48
        let moneyX = rect.maxX - 16 - moneyW
        let eventsX = moneyX - gap - eventsW
        let sessionsX = eventsX - gap - sessionsW
        let outputX = (showsActivity ? sessionsX : moneyX) - gap - outputW
        let inputX = outputX - gap - inputW
        let totalX = inputX - gap - totalW
        let shareX = totalX - gap - shareW
        let nameX = rect.minX + 32
        let nameW = max(96, shareX - nameX - 12)

        let headerY = rect.minY + 72
        let headerColor = NSColor.white.withAlphaComponent(0.38)
        let headerFont = NSFont.systemFont(ofSize: 10, weight: .bold)
        drawRight("%", rect: NSRect(x: shareX, y: headerY, width: shareW, height: 14), color: headerColor, font: headerFont)
        drawRight(t(.total), rect: NSRect(x: totalX, y: headerY, width: totalW, height: 14), color: headerColor, font: headerFont)
        drawRight(t(.input), rect: NSRect(x: inputX, y: headerY, width: inputW, height: 14), color: headerColor, font: headerFont)
        drawRight(t(.output), rect: NSRect(x: outputX, y: headerY, width: outputW, height: 14), color: headerColor, font: headerFont)
        if showsActivity {
            drawRight(t(.sessions), rect: NSRect(x: sessionsX, y: headerY, width: sessionsW, height: 14), color: headerColor, font: headerFont)
            drawRight(t(.events), rect: NSRect(x: eventsX, y: headerY, width: eventsW, height: 14), color: headerColor, font: headerFont)
        }
        drawRight(t(.apiEquivalent), rect: NSRect(x: moneyX, y: headerY, width: moneyW, height: 14), color: headerColor, font: headerFont)

        let displayCurrency = AppSettings.displayCurrency(for: selectedDetailsSource)
        for (index, model) in models.enumerated() {
            let rowY = rect.minY + 90 + CGFloat(index) * 20
            let color = modelShareColor(index)
            let share = totalTokens > 0 ? Double(model.usage.total) / Double(totalTokens) * 100 : 0
            let shareText = share > 0 && share < 0.1 ? "<0.1%" : String(format: "%.1f%%", share)
            let estimate = APICostEstimator.estimate(usage: model.usage, modelName: model.name)
            let moneyText = estimate.hasPricedUsage
                ? compactMoney(convertCurrency(estimate.usdValue, from: .usd, to: displayCurrency), currency: displayCurrency)
                : "—"
            let rowRect = NSRect(x: rect.minX + 10, y: rowY - 2, width: rect.width - 20, height: 19)
            let rowIndex = modelUsageHoverRows.count
            modelUsageHoverRows.append(ModelUsageHoverRow(
                rect: rowRect,
                title: model.name,
                subtitle: nil,
                usage: model.usage,
                shareText: shareText,
                sessions: model.sessions,
                events: model.events,
                apiCostText: estimate.hasPricedUsage ? displayAPIMoney(estimate.usdValue, source: selectedDetailsSource) : nil,
                apiCostColor: estimate.hasPricedUsage ? accentTeal : NSColor.white.withAlphaComponent(0.38)
            ))
            if hoveredModelUsageRowIndex == rowIndex {
                NSColor.white.withAlphaComponent(0.055).setFill()
                NSBezierPath(roundedRect: rowRect, xRadius: 5, yRadius: 5).fill()
            }
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.minX + 16, y: rowY + 5, width: 8, height: 8)).fill()
            drawText(model.name, rect: NSRect(x: nameX, y: rowY, width: nameW, height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: .white)
            drawRight(shareText, rect: NSRect(x: shareX, y: rowY, width: shareW, height: 18), color: NSColor.white.withAlphaComponent(0.62), font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold))
            drawRight(compact(model.usage.total), rect: NSRect(x: totalX, y: rowY, width: totalW, height: 18), color: .white)
            drawRight(compact(model.usage.input), rect: NSRect(x: inputX, y: rowY, width: inputW, height: 18), color: NSColor.white.withAlphaComponent(0.58))
            drawRight(compact(model.usage.output), rect: NSRect(x: outputX, y: rowY, width: outputW, height: 18), color: NSColor.white.withAlphaComponent(0.58))
            if showsActivity {
                drawRight("\(model.sessions)", rect: NSRect(x: sessionsX, y: rowY, width: sessionsW, height: 18), color: NSColor.white.withAlphaComponent(0.52))
                drawRight("\(model.events)", rect: NSRect(x: eventsX, y: rowY, width: eventsW, height: 18), color: NSColor.white.withAlphaComponent(0.52))
            }
            drawRight(moneyText, rect: NSRect(x: moneyX, y: rowY, width: moneyW, height: 18), color: estimate.hasPricedUsage ? accentTeal.withAlphaComponent(0.92) : NSColor.white.withAlphaComponent(0.34), font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold))
        }
    }

    private var modelShareColors: [NSColor] {
        [
            accentBlue,
            accentTeal,
            accentAmber,
            accentRose,
            NSColor(calibratedRed: 0.702, green: 0.533, blue: 1.0, alpha: 1.0),
            NSColor(calibratedRed: 0.478, green: 0.867, blue: 0.443, alpha: 1.0),
            NSColor(calibratedRed: 1.0, green: 0.537, blue: 0.396, alpha: 1.0),
            NSColor(calibratedRed: 0.408, green: 0.780, blue: 0.949, alpha: 1.0),
            NSColor(calibratedRed: 0.910, green: 0.796, blue: 0.478, alpha: 1.0),
            NSColor(calibratedRed: 0.769, green: 0.545, blue: 0.729, alpha: 1.0)
        ]
    }

    private func modelShareColor(_ index: Int) -> NSColor {
        modelShareColors[index % modelShareColors.count]
    }

    private func drawModelShareBar(models: [ModelUsage], totalTokens: Int64, rect: NSRect) {
        guard totalTokens > 0 else { return }
        inputSurfaceColor.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).addClip()
        var x = rect.minX
        for (index, model) in models.enumerated() {
            let width = rect.width * CGFloat(Double(model.usage.total) / Double(totalTokens))
            modelShareColor(index).withAlphaComponent(0.92).setFill()
            NSRect(x: x, y: rect.minY, width: width, height: rect.height).fill()
            x += width
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
