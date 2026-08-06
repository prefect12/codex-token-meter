import Cocoa

extension UsageDetailsView {
    func drawInsightsPage(snapshot: DetailsSnapshot, content: NSRect) {
        let report = insightReport(for: snapshot)
        let rows = sortedInsightRows(report.rows)
        drawInsightControls(content: content)
        let topY = content.minY + 112

        if selectedInsightDetailMode == .reasoningDepth {
            drawReasoningDepthPage(report: report.reasoning, content: content, topY: topY)
            return
        }

        if selectedInsightDetailMode == .usageTime {
            let timeRect = NSRect(x: content.minX, y: topY, width: content.width, height: min(520, max(360, content.maxY - topY)))
            drawInsightUsageTimePage(report: report, rect: timeRect)
            return
        }

        if rows.isEmpty {
            let emptyRect = NSRect(x: content.minX, y: topY, width: content.width, height: 180)
            drawPanel(emptyRect)
            drawText(insightEmptyTitle, rect: NSRect(x: emptyRect.minX + 18, y: emptyRect.minY + 22, width: emptyRect.width - 36, height: 24), font: .systemFont(ofSize: 17, weight: .bold), color: .white)
            drawText(insightEmptyDescription, rect: NSRect(x: emptyRect.minX + 18, y: emptyRect.minY + 56, width: emptyRect.width - 36, height: 20), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.54))
            return
        }

        drawInsightStatusChips(rows: rows, content: content, y: topY)
        let filtered = rows.filter { selectedInsightStatusFilter.matches($0.risk) }
        let panelTop = topY + 40
        let grouped = selectedInsightStatusFilter == .all

        if filtered.isEmpty {
            let listRect = NSRect(x: content.minX, y: panelTop, width: content.width, height: 140)
            drawPanel(listRect)
            drawCentered(AppLanguage.current.insightCopy.projectCount(0), rect: NSRect(x: listRect.minX, y: listRect.midY - 9, width: listRect.width, height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(0.42))
            return
        }

        let panelHeight: CGFloat = 384
        if content.width >= 940 {
            let gap: CGFloat = 16
            let listWidth = min(CGFloat(370), content.width * 0.40)
            let listRect = NSRect(x: content.minX, y: panelTop, width: listWidth, height: panelHeight)
            let detailRect = NSRect(x: listRect.maxX + gap, y: panelTop, width: content.width - listWidth - gap, height: panelHeight)
            let heatmapRect = NSRect(x: content.minX, y: panelTop + panelHeight + 16, width: content.width, height: 148)
            drawInsightProjectList(rows: filtered, grouped: grouped, rect: listRect)
            let selected = selectedInsight(in: filtered)
            drawInsightDetail(selected, rect: detailRect)
            drawInsightHeatmap(row: selected, rect: heatmapRect)
        } else {
            let selected = selectedInsight(in: filtered)
            let listRect = NSRect(x: content.minX, y: panelTop, width: content.width, height: 384)
            let detailRect = NSRect(x: content.minX, y: listRect.maxY + 16, width: content.width, height: panelHeight)
            let heatmapRect = NSRect(x: content.minX, y: detailRect.maxY + 16, width: content.width, height: 148)
            drawInsightProjectList(rows: filtered, grouped: grouped, rect: listRect)
            drawInsightDetail(selected, rect: detailRect)
            drawInsightHeatmap(row: selected, rect: heatmapRect)
        }
    }

    func drawInsightStatusChips(rows: [RepoInsight], content: NSRect, y: CGFloat) {
        let copy = AppLanguage.current.insightCopy
        let chipH: CGFloat = 28
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let chips: [(InsightStatusFilter, String, NSColor?)] = [
            (.all, localizedInsightFilterAll, nil),
            (.frequentCompression, copy.riskLabel(.frequentCompression), accentRose),
            (.longRunning, copy.riskLabel(.longRunning), accentAmber),
            (.good, localizedInsightGoodStatus, accentTeal)
        ]
        var x = content.minX
        for (filter, label, dotColor) in chips {
            let count = rows.reduce(0) { $0 + (filter.matches($1.risk) ? 1 : 0) }
            let text = "\(label) \(count)"
            let textW = measuredTextWidth(text, font: font)
            let dotW: CGFloat = dotColor == nil ? 0 : 13
            let chipRect = NSRect(x: x, y: y, width: textW + dotW + 24, height: chipH)
            insightStatusFilterRects[filter] = chipRect
            let selected = selectedInsightStatusFilter == filter
            (selected ? accentBlue.withAlphaComponent(0.74) : inputSurfaceColor.withAlphaComponent(0.30)).setFill()
            NSBezierPath(roundedRect: chipRect, xRadius: chipH / 2, yRadius: chipH / 2).fill()
            (selected ? accentTeal.withAlphaComponent(0.45) : borderColor.withAlphaComponent(0.8)).setStroke()
            let outline = NSBezierPath(roundedRect: chipRect.insetBy(dx: 0.5, dy: 0.5), xRadius: chipH / 2, yRadius: chipH / 2)
            outline.lineWidth = 1
            outline.stroke()
            var textX = chipRect.minX + 12
            if let dotColor {
                dotColor.setFill()
                NSBezierPath(ovalIn: NSRect(x: textX, y: chipRect.midY - 4, width: 8, height: 8)).fill()
                textX += 13
            }
            drawText(text, rect: NSRect(x: textX, y: chipRect.minY + 7, width: textW + 4, height: 15), font: font, color: selected ? .white : NSColor.white.withAlphaComponent(0.75))
            x += chipRect.width + 8
        }
        let totalConversations = rows.reduce(0) { $0 + $1.conversations }
        let summary = "\(copy.windowLabel(days: selectedInsightWindowDays)) · \(totalConversations) \(copy.chatsMetric)"
        if content.maxX - x > 200 {
            drawRight(summary, rect: NSRect(x: content.maxX - 260, y: y + 7, width: 244, height: 15), color: NSColor.white.withAlphaComponent(0.42), font: font)
        }
    }

    func selectedInsight(in rows: [RepoInsight]) -> RepoInsight {
        if let selectedInsightKey,
           let row = rows.first(where: { $0.key == selectedInsightKey }) {
            return row
        }
        selectedInsightKey = rows.first?.key
        return rows[0]
    }

    func insightReport(for snapshot: DetailsSnapshot) -> RepoInsightsReport {
        switch selectedDetailsSource {
        case .all:
            let reports = QuotaViewOption.visiblePlatformCases.map { source -> RepoInsightsReport in
                switch source {
                case .codex:
                    return snapshot.codexRepoInsightReports[selectedInsightWindowDays] ?? snapshot.codexRepoInsights
                case .claude:
                    return snapshot.claudeRepoInsightReports[selectedInsightWindowDays] ?? snapshot.claudeRepoInsights
                case .api:
                    return snapshot.apiRepoInsightReports[selectedInsightWindowDays] ?? snapshot.apiRepoInsights
                case .all:
                    return RepoInsightsReport(rows: [], scannedAt: Date(), windowDays: selectedInsightWindowDays)
                }
            }
            return mergedRepoInsightsReport(reports, windowDays: selectedInsightWindowDays)
        case .codex:
            return snapshot.codexRepoInsightReports[selectedInsightWindowDays] ?? snapshot.codexRepoInsights
        case .claude:
            return snapshot.claudeRepoInsightReports[selectedInsightWindowDays] ?? snapshot.claudeRepoInsights
        case .api:
            return snapshot.apiRepoInsightReports[selectedInsightWindowDays] ?? snapshot.apiRepoInsights
        }
    }

    func normalizeSelectedInsight(for report: RepoInsightsReport) {
        if let selectedInsightKey,
           report.rows.contains(where: { $0.key == selectedInsightKey }) {
            return
        }
        selectedInsightKey = sortedInsightRows(report.rows).first?.key
    }

    func sortedInsightRows(_ rows: [RepoInsight]) -> [RepoInsight] {
        rows.sorted { lhs, rhs in
            let ascending = isInsightSortAscending
            switch selectedInsightSort {
            case .project:
                let order = insightListDisplayName(for: lhs).localizedCaseInsensitiveCompare(insightListDisplayName(for: rhs))
                if order != .orderedSame {
                    return ascending ? order == .orderedAscending : order == .orderedDescending
                }
                if lhs.conversations != rhs.conversations {
                    return lhs.conversations > rhs.conversations
                }
            case .conversations:
                if lhs.conversations != rhs.conversations {
                    return ascending ? lhs.conversations < rhs.conversations : lhs.conversations > rhs.conversations
                }
                if lhs.compressions != rhs.compressions {
                    return lhs.compressions > rhs.compressions
                }
            case .compressions:
                if lhs.compressions != rhs.compressions {
                    return ascending ? lhs.compressions < rhs.compressions : lhs.compressions > rhs.compressions
                }
                if lhs.conversations != rhs.conversations {
                    return lhs.conversations > rhs.conversations
                }
            case .average:
                if lhs.averageCompressionsPerConversation != rhs.averageCompressionsPerConversation {
                    return ascending ? lhs.averageCompressionsPerConversation < rhs.averageCompressionsPerConversation : lhs.averageCompressionsPerConversation > rhs.averageCompressionsPerConversation
                }
                if lhs.compressions != rhs.compressions {
                    return lhs.compressions > rhs.compressions
                }
            case .status:
                let lhsRank = insightRiskSortRank(lhs.risk)
                let rhsRank = insightRiskSortRank(rhs.risk)
                if lhsRank != rhsRank {
                    return ascending ? lhsRank < rhsRank : lhsRank > rhsRank
                }
                if lhs.compressions != rhs.compressions {
                    return lhs.compressions > rhs.compressions
                }
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    func insightRiskSortRank(_ risk: RepoInsightRisk) -> Int {
        switch risk {
        case .healthy: return 0
        case .wellSplit: return 1
        case .longRunning: return 2
        case .frequentCompression: return 3
        }
    }

    var insightEmptyTitle: String {
        AppLanguage.current.insightCopy.emptyTitle
    }

    var insightEmptyDescription: String {
        AppLanguage.current.insightCopy.emptyDescription
    }

    func drawInsightControls(content: NSRect) {
        let y = content.minY + 64
        let rowH: CGFloat = 28
        let modePillW: CGFloat = 104
        let modeGap: CGFloat = 8
        let modes: [(InsightDetailMode, String)] = [
            (.usageHabits, localizedInsightDetailMode(.usageHabits)),
            (.usageTime, localizedInsightDetailMode(.usageTime))
        ]
        var x = content.minX
        for mode in modes {
            let rect = NSRect(x: x, y: y, width: modePillW, height: rowH)
            insightDetailModeRects[mode.0] = rect
            drawSelectablePill(mode.1, rect: rect, selected: selectedInsightDetailMode == mode.0)
            x += modePillW + modeGap
        }

        x += 8
        drawInsightControlSeparator(x: x, y: y, height: rowH)
        x += 17

        let compactH: CGFloat = 24
        let compactY = y + (rowH - compactH) / 2
        let compactGap: CGFloat = 5
        let sourceW: CGFloat = 54
        let sourceOptions = QuotaViewOption.visibleSelectorOptions
        for option in sourceOptions {
            let rect = NSRect(x: x, y: compactY, width: sourceW, height: compactH)
            let enabled = selectedInsightDetailMode != .reasoningDepth || option == preferredReasoningSource
            if enabled {
                sourceOptionRects[option] = rect
            }
            drawCompactInsightPill(detailsSourceTitle(option), rect: rect, selected: selectedDetailsSource == option, enabled: enabled)
            x += sourceW + compactGap
        }

        x += 12 - compactGap
        drawInsightControlSeparator(x: x, y: y, height: rowH)
        x += 17

        let copy = AppLanguage.current.insightCopy
        let windowW: CGFloat = 46
        for days in insightWindowOptions {
            let rect = NSRect(x: x, y: compactY, width: windowW, height: compactH)
            insightWindowRects[days] = rect
            drawCompactInsightPill(copy.windowLabel(days: days), rect: rect, selected: days == selectedInsightWindowDays)
            x += windowW + compactGap
        }
    }

    func drawInsightControlSeparator(x: CGFloat, y: CGFloat, height: CGFloat) {
        NSColor.white.withAlphaComponent(0.12).setFill()
        NSBezierPath(rect: NSRect(x: x, y: y + 6, width: 1, height: height - 12)).fill()
    }

    func drawCompactInsightPill(_ text: String, rect: NSRect, selected: Bool, enabled: Bool = true) {
        let isSelected = selected && enabled
        let fill = isSelected ? accentBlue.withAlphaComponent(0.74) : inputSurfaceColor.withAlphaComponent(enabled ? 0.30 : 0.16)
        let stroke = isSelected ? accentTeal.withAlphaComponent(0.50) : borderColor.withAlphaComponent(enabled ? 0.80 : 0.36)
        fill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        stroke.setStroke()
        let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        outline.lineWidth = 1
        outline.stroke()
        let color = isSelected ? NSColor.white : NSColor.white.withAlphaComponent(enabled ? 0.72 : 0.28)
        drawCentered(text, rect: rect.insetBy(dx: 4, dy: 0), font: .systemFont(ofSize: 10, weight: .bold), color: color)
    }

    func drawInsightProjectList(rows: [RepoInsight], grouped: Bool, rect: NSRect) {
        let copy = AppLanguage.current.insightCopy
        drawPanel(rect)

        let headerY = rect.minY + 18
        let avgW: CGFloat = 56
        let conversationsW: CGFloat = 56
        let avgX = rect.maxX - 16 - avgW
        let conversationsX = avgX - 10 - conversationsW
        let nameW = max(110, conversationsX - rect.minX - 34)
        let headerColor = NSColor.white.withAlphaComponent(0.42)
        let projectHeader = NSRect(x: rect.minX + 16, y: headerY, width: nameW, height: 16)
        let conversationsHeader = NSRect(x: conversationsX, y: headerY, width: conversationsW, height: 16)
        let avgHeader = NSRect(x: avgX, y: headerY, width: avgW, height: 16)
        insightSortRects[.project] = projectHeader
        insightSortRects[.conversations] = conversationsHeader
        insightSortRects[.average] = avgHeader
        drawInsightHeader(.project, rect: projectHeader, alignment: .left, color: headerColor)
        drawInsightHeader(.conversations, rect: conversationsHeader, alignment: .right, color: headerColor)
        drawInsightHeader(.average, rect: avgHeader, alignment: .right, color: headerColor)

        enum ListItem {
            case group(String, Int)
            case row(RepoInsight)
        }
        var items: [ListItem] = []
        if grouped {
            let attention = rows.filter { $0.risk == .frequentCompression || $0.risk == .longRunning }
            let good = rows.filter { $0.risk == .wellSplit || $0.risk == .healthy }
            if !attention.isEmpty {
                items.append(.group(localizedInsightAttentionGroup, attention.count))
                items.append(contentsOf: attention.map(ListItem.row))
            }
            if !good.isEmpty {
                items.append(.group(localizedInsightGoodStatus, good.count))
                items.append(contentsOf: good.map(ListItem.row))
            }
        } else {
            items = rows.map(ListItem.row)
        }

        let rowHeight: CGFloat = 40
        let groupHeight: CGFloat = 30
        func itemHeight(_ item: ListItem) -> CGFloat {
            if case .group = item { return groupHeight }
            return rowHeight
        }
        let contentHeight = items.reduce(CGFloat(0)) { $0 + itemHeight($1) }
        insightListContentHeight = contentHeight
        let viewport = NSRect(x: rect.minX, y: rect.minY + 42, width: rect.width, height: max(0, rect.height - 84))
        insightListViewportRect = viewport
        let maxOffset = max(0, contentHeight - viewport.height)
        insightListScrollOffset = min(max(0, insightListScrollOffset), maxOffset)

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: viewport).addClip()
        var y = viewport.minY - insightListScrollOffset
        for item in items {
            let itemH = itemHeight(item)
            defer { y += itemH }
            guard y + itemH > viewport.minY, y < viewport.maxY else { continue }
            switch item {
            case .group(let title, let count):
                drawText("\(title) · \(count)", rect: NSRect(x: rect.minX + 16, y: y + 11, width: rect.width - 32, height: 14), font: .systemFont(ofSize: 10, weight: .bold), color: NSColor.white.withAlphaComponent(0.38))
            case .row(let row):
                let rowRect = NSRect(x: rect.minX, y: y, width: rect.width, height: itemH)
                insightRowRects[row.key] = rowRect
                let riskColor = insightRiskColor(row.risk)
                let isSelected = row.key == selectedInsightKey
                if isSelected {
                    accentBlue.withAlphaComponent(0.76).setFill()
                    NSBezierPath(roundedRect: rowRect.insetBy(dx: 6, dy: 2), xRadius: 7, yRadius: 7).fill()
                }
                riskColor.withAlphaComponent(0.9).setFill()
                NSBezierPath(roundedRect: NSRect(x: rect.minX + 10, y: y + 9, width: 3, height: itemH - 18), xRadius: 1.5, yRadius: 1.5).fill()
                let textColor = isSelected ? NSColor.white : NSColor.white.withAlphaComponent(0.78)
                drawTruncatedText(insightListDisplayName(for: row), rect: NSRect(x: rect.minX + 22, y: y + 11, width: nameW - 6, height: 18), font: .systemFont(ofSize: 11, weight: .semibold), color: textColor)
                drawRight("\(row.conversations)", rect: NSRect(x: conversationsX, y: y + 11, width: conversationsW, height: 18), color: isSelected ? .white : NSColor.white.withAlphaComponent(0.62))
                drawRight(String(format: "%.2f", row.averageCompressionsPerConversation), rect: NSRect(x: avgX, y: y + 11, width: avgW, height: 18), color: isSelected ? .white : riskColor.withAlphaComponent(0.95))
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        drawInsightListScrollbar(viewport: viewport, contentHeight: contentHeight)

        drawText(copy.projectCount(rows.count), rect: NSRect(x: rect.minX + 16, y: rect.maxY - 30, width: 200, height: 16), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.46))
    }

    enum InsightHeaderAlignment {
        case left
        case center
        case right
    }

    func drawInsightHeader(_ column: InsightSortColumn, rect: NSRect, alignment: InsightHeaderAlignment, color: NSColor) {
        let font = NSFont.systemFont(ofSize: 11, weight: .bold)
        let arrowFont = NSFont.systemFont(ofSize: 10, weight: .bold)
        let arrow = selectedInsightSort == column ? (isInsightSortAscending ? "↑" : "↓") : nil
        let arrowWidth: CGFloat = 10

        switch alignment {
        case .left:
            drawText(column.title, rect: rect, font: font, color: color)
            if let arrow {
                let x = rect.minX + measuredTextWidth(column.title, font: font) + 4
                drawText(arrow, rect: NSRect(x: x, y: rect.minY, width: arrowWidth, height: rect.height), font: arrowFont, color: color)
            }
        case .center:
            drawCentered(column.title, rect: rect, font: font, color: color)
            if let arrow {
                let titleWidth = measuredTextWidth(column.title, font: font)
                let x = rect.midX + titleWidth / 2 + 4
                drawText(arrow, rect: NSRect(x: x, y: rect.minY, width: arrowWidth, height: rect.height), font: arrowFont, color: color)
            }
        case .right:
            let titleRect = NSRect(x: rect.minX, y: rect.minY, width: max(0, rect.width - arrowWidth - 4), height: rect.height)
            drawRight(column.title, rect: titleRect, color: color, font: font)
            if let arrow {
                drawText(arrow, rect: NSRect(x: rect.maxX - arrowWidth, y: rect.minY, width: arrowWidth, height: rect.height), font: arrowFont, color: color)
            }
        }
    }

    func drawInsightListScrollbar(viewport: NSRect, contentHeight: CGFloat) {
        guard contentHeight > viewport.height else { return }
        let track = NSRect(x: viewport.maxX - 7, y: viewport.minY + 4, width: 3, height: viewport.height - 8)
        NSColor.white.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()
        let thumbHeight = max(CGFloat(28), track.height * viewport.height / contentHeight)
        let maxOffset = max(1, contentHeight - viewport.height)
        let travel = max(0, track.height - thumbHeight)
        let thumbY = track.minY + travel * (insightListScrollOffset / maxOffset)
        accentBlue.withAlphaComponent(0.52).setFill()
        NSBezierPath(roundedRect: NSRect(x: track.minX, y: thumbY, width: track.width, height: thumbHeight), xRadius: 1.5, yRadius: 1.5).fill()
    }

    func insightListDisplayName(for row: RepoInsight) -> String {
        if row.displayName.hasPrefix("github/") {
            let rawName = String(row.displayName.dropFirst("github/".count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if let name = rawName.split(separator: "/").last {
                return String(name)
            }
            return githubRepoName(from: row.primaryFolder)
                ?? githubRepoName(from: row.key)
                ?? "github"
        }
        if row.displayName.hasPrefix("worktrees/") {
            let rawName = String(row.displayName.dropFirst("worktrees/".count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if let name = rawName.split(separator: "/").last {
                return String(name)
            }
            return "worktrees"
        }
        if row.displayName.hasPrefix("~/Documents/") {
            let parts = row.displayName.split(separator: "/")
            return parts.last.map(String.init) ?? row.displayName
        }
        return row.displayName
    }

    func githubRepoName(from path: String) -> String? {
        let components = (path as NSString)
            .standardizingPath
            .split(separator: "/")
            .map(String.init)
        guard let githubIndex = components.firstIndex(of: "github"),
              components.count > githubIndex + 1 else {
            return nil
        }
        let repoName = components[githubIndex + 1]
        return repoName.isEmpty ? nil : repoName
    }

    func drawInsightDetail(_ row: RepoInsight, rect: NSRect) {
        let copy = AppLanguage.current.insightCopy
        drawPanel(rect)
        drawText(row.displayName, rect: NSRect(x: rect.minX + 16, y: rect.minY + 16, width: rect.width - 140, height: 24), font: .systemFont(ofSize: 17, weight: .bold), color: .white)
        drawInsightRiskPill(row.risk, rect: NSRect(x: rect.maxX - 112, y: rect.minY + 16, width: 88, height: 24))

        drawText(insightDiagnosisText(for: row), rect: NSRect(x: rect.minX + 16, y: rect.minY + 46, width: rect.width - 32, height: 34), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.66))

        let riskColor = insightRiskColor(row.risk)
        let attention = row.risk == .frequentCompression || row.risk == .longRunning
        let plain = NSColor.white.withAlphaComponent(0.94)
        let metricY = rect.minY + 90
        let metricW = (rect.width - 32) / 5
        let metrics: [(String, String, NSColor)] = [
            (copy.chatsMetric, "\(row.conversations)", plain),
            (copy.turnsMetric, "\(row.turns)", plain),
            (copy.compactionsMetric, "\(row.compressions)", attention ? riskColor : plain),
            (copy.avgCompactionsMetric, String(format: "%.2f", row.averageCompressionsPerConversation), attention ? riskColor : plain),
            (copy.maxTurnsMetric, "\(row.longestTurns)", plain)
        ]
        for (index, metric) in metrics.enumerated() {
            let x = rect.minX + 16 + CGFloat(index) * metricW
            drawTruncatedText(metric.0, rect: NSRect(x: x, y: metricY, width: metricW - 10, height: 14), font: .systemFont(ofSize: 10, weight: .bold), color: NSColor.white.withAlphaComponent(0.48))
            drawText(metric.1, rect: NSRect(x: x, y: metricY + 16, width: metricW - 10, height: 24), font: .monospacedDigitSystemFont(ofSize: 19, weight: .bold), color: metric.2)
        }

        let sectionY = metricY + 52
        let sectionH: CGFloat = 124
        let sectionGap: CGFloat = 10
        let sectionW = (rect.width - 32 - sectionGap) / 2
        let lengthRect = NSRect(x: rect.minX + 16, y: sectionY, width: sectionW, height: sectionH)
        drawInsightDonutSection(
            title: copy.lengthDistributionTitle,
            rightText: nil,
            buckets: [
                (copy.shortBucket, row.turnBuckets.short, accentTeal),
                (copy.mediumBucket, row.turnBuckets.medium, accentBlue),
                (copy.longBucket, row.turnBuckets.long, accentAmber),
                (copy.extraLongBucket, row.turnBuckets.extraLong, accentRose)
            ],
            rect: lengthRect
        )

        let conversationTotal = max(1, row.conversations)
        let compressedCount = max(0, conversationTotal - row.compressionBuckets.zero)
        let compressedPercent = Int(round(Double(compressedCount) / Double(conversationTotal) * 100))
        let compressionRect = NSRect(x: lengthRect.maxX + sectionGap, y: sectionY, width: sectionW, height: sectionH)
        drawInsightDonutSection(
            title: copy.compactionDistributionTitle,
            rightText: copy.compactedPercent(compressedPercent),
            buckets: [
                (copy.zeroCompactions, row.compressionBuckets.zero, accentTeal),
                (copy.oneCompaction, row.compressionBuckets.one, accentBlue),
                (copy.twoCompactions, row.compressionBuckets.two, accentAmber),
                (copy.threePlusCompactions, row.compressionBuckets.threePlus, accentRose)
            ],
            rect: compressionRect
        )

        let recommendationRect = NSRect(x: rect.minX + 16, y: compressionRect.maxY + 12, width: rect.width - 32, height: max(70, rect.maxY - compressionRect.maxY - 26))
        drawInsightRecommendations(row, rect: recommendationRect)
    }

    func drawInsightDonutSection(title: String, rightText: String?, buckets: [(String, Int, NSColor)], rect: NSRect) {
        inputSurfaceColor.withAlphaComponent(0.42).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        let rightW: CGFloat = rightText == nil ? 0 : 96
        drawTruncatedText(title, rect: NSRect(x: rect.minX + 12, y: rect.minY + 9, width: rect.width - 24 - rightW, height: 16), font: .systemFont(ofSize: 12, weight: .bold), color: NSColor.white.withAlphaComponent(0.76))
        if let rightText {
            drawRight(rightText, rect: NSRect(x: rect.maxX - 12 - rightW, y: rect.minY + 10, width: rightW, height: 15), color: NSColor.white.withAlphaComponent(0.48), font: .systemFont(ofSize: 10, weight: .semibold))
        }

        let total = max(1, buckets.reduce(0) { $0 + $1.1 })
        let bodyTop = rect.minY + 30
        let bodyHeight = rect.height - 38
        let radius: CGFloat = min(30, bodyHeight / 2 - 4)
        let thickness: CGFloat = 11
        let center = NSPoint(x: rect.minX + 14 + radius, y: bodyTop + bodyHeight / 2)

        let track = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        track.lineWidth = thickness
        NSColor.white.withAlphaComponent(0.06).setStroke()
        track.stroke()

        var angle: CGFloat = 90
        for bucket in buckets where bucket.1 > 0 {
            let sweep = 360 * CGFloat(bucket.1) / CGFloat(total)
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius, startAngle: angle, endAngle: angle + sweep, clockwise: false)
            arc.lineWidth = thickness
            arc.lineCapStyle = .butt
            bucket.2.withAlphaComponent(0.9).setStroke()
            arc.stroke()
            angle += sweep
        }

        if let dominant = buckets.max(by: { $0.1 < $1.1 }), dominant.1 > 0 {
            let percent = Int(round(Double(dominant.1) / Double(total) * 100))
            drawCentered("\(percent)%", rect: NSRect(x: center.x - radius + 4, y: center.y - 7, width: (radius - 4) * 2, height: 14), font: .monospacedDigitSystemFont(ofSize: 11, weight: .bold), color: dominant.2.withAlphaComponent(0.95))
        }

        let legendX = center.x + radius + 18
        let rowH = bodyHeight / CGFloat(max(1, buckets.count))
        for (index, bucket) in buckets.enumerated() {
            let y = bodyTop + CGFloat(index) * rowH
            bucket.2.setFill()
            NSBezierPath(ovalIn: NSRect(x: legendX, y: y + rowH / 2 - 3.5, width: 7, height: 7)).fill()
            let percent = Int(round(Double(bucket.1) / Double(total) * 100))
            let valueW: CGFloat = 82
            drawTruncatedText(bucket.0, rect: NSRect(x: legendX + 12, y: y + rowH / 2 - 7, width: max(30, rect.maxX - 12 - valueW - legendX - 18), height: 14), font: .systemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.58))
            drawRight("\(bucket.1) · \(percent)%", rect: NSRect(x: rect.maxX - 12 - valueW, y: y + rowH / 2 - 7, width: valueW, height: 14), color: NSColor.white.withAlphaComponent(0.72), font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold))
        }
    }

    func drawInsightUsageTimePage(report: RepoInsightsReport, rect: NSRect) {
        drawPanel(rect)
        let hours = aggregateInsightHours(report)
        let windowLabel = AppLanguage.current.insightCopy.windowLabel(days: selectedInsightWindowDays)
        let title = "\(localizedInsightUsageTimeTitle) · \(detailsSourceTitle(selectedDetailsSource)) · \(windowLabel)"
        drawText(title, rect: NSRect(x: rect.minX + 18, y: rect.minY + 16, width: rect.width - 36, height: 24), font: .systemFont(ofSize: 17, weight: .bold), color: .white)
        drawText(insightUsageTimeSummary(hours), rect: NSRect(x: rect.minX + 18, y: rect.minY + 44, width: rect.width - 36, height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(0.56))

        let summaryRect = NSRect(x: rect.minX + 18, y: rect.minY + 78, width: rect.width - 36, height: 74)
        drawInsightTimePeriodCards(hours: hours, rect: summaryRect)

        let chartPanel = NSRect(x: rect.minX + 18, y: summaryRect.maxY + 16, width: rect.width - 36, height: max(210, rect.maxY - summaryRect.maxY - 40))
        inputSurfaceColor.withAlphaComponent(0.42).setFill()
        NSBezierPath(roundedRect: chartPanel, xRadius: 7, yRadius: 7).fill()
        drawText(localizedInsightHourlyCallsTitle, rect: NSRect(x: chartPanel.minX + 14, y: chartPanel.minY + 12, width: chartPanel.width - 28, height: 18), font: .systemFont(ofSize: 13, weight: .bold), color: NSColor.white.withAlphaComponent(0.76))

        let hoursByHour = Dictionary(uniqueKeysWithValues: hours.map { ($0.hour, $0) })
        let maxTurns = max(1, hours.map(\.turns).max() ?? 0)
        let axisWidth: CGFloat = 44
        let chart = NSRect(x: chartPanel.minX + 18 + axisWidth, y: chartPanel.minY + 48, width: chartPanel.width - 36 - axisWidth, height: chartPanel.height - 94)
        let tickValues = insightAxisTickValues(maxValue: maxTurns)
        let axisMax = max(1, tickValues.last ?? maxTurns)
        for tick in tickValues {
            let ratio = CGFloat(tick) / CGFloat(axisMax)
            let y = chart.maxY - chart.height * ratio
            let tickColor = NSColor.white.withAlphaComponent(tick == 0 ? 0.30 : 0.12)
            tickColor.setStroke()
            let grid = NSBezierPath()
            grid.move(to: NSPoint(x: chart.minX - 5, y: y))
            grid.line(to: NSPoint(x: chart.maxX, y: y))
            grid.lineWidth = tick == 0 ? 1.1 : 0.8
            grid.stroke()
            drawRight(compact(Int64(tick)), rect: NSRect(x: chartPanel.minX + 12, y: y - 7, width: axisWidth - 12, height: 14), color: NSColor.white.withAlphaComponent(0.46), font: .monospacedDigitSystemFont(ofSize: 9, weight: .semibold))
        }
        NSColor.white.withAlphaComponent(0.20).setStroke()
        let axis = NSBezierPath()
        axis.move(to: NSPoint(x: chart.minX - 5, y: chart.minY))
        axis.line(to: NSPoint(x: chart.minX - 5, y: chart.maxY))
        axis.lineWidth = 1
        axis.stroke()
        drawRight(t(.turns), rect: NSRect(x: chartPanel.minX + 12, y: chart.minY - 18, width: axisWidth - 12, height: 12), color: NSColor.white.withAlphaComponent(0.36), font: .systemFont(ofSize: 8, weight: .bold))
        let gap: CGFloat = 4
        let barWidth = max(CGFloat(6), (chart.width - CGFloat(23) * gap) / 24)
        for hour in 0..<24 {
            let turns = hoursByHour[hour]?.turns ?? 0
            let ratio = CGFloat(turns) / CGFloat(axisMax)
            let height = turns > 0 ? max(CGFloat(5), chart.height * ratio) : 2
            let x = chart.minX + CGFloat(hour) * (barWidth + gap)
            let bar = NSRect(x: x, y: chart.maxY - height, width: barWidth, height: height)
            insightHourRects[hour] = NSRect(x: x - max(2, gap / 2), y: chart.minY, width: barWidth + max(4, gap), height: chart.height)
            insightHourBarRects[hour] = bar
            insightHourColor(hour).withAlphaComponent(turns > 0 ? 0.86 : 0.16).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 3, yRadius: 3).fill()
            if hoveredInsightHour == hour {
                NSColor.white.withAlphaComponent(0.34).setStroke()
                let focus = NSBezierPath(roundedRect: bar.insetBy(dx: -3, dy: -3), xRadius: 5, yRadius: 5)
                focus.lineWidth = 1.4
                focus.stroke()
            }
            if [0, 6, 12, 18, 23].contains(hour) {
                drawCentered(String(format: "%02d", hour), rect: NSRect(x: x - 6, y: chart.maxY + 6, width: barWidth + 12, height: 14), font: .monospacedDigitSystemFont(ofSize: 9, weight: .semibold), color: NSColor.white.withAlphaComponent(0.42))
            }
        }

        let legendY = chartPanel.maxY - 30
        let legend: [(String, NSColor)] = [
            (localizedInsightMorning, accentTeal),
            (localizedInsightAfternoon, accentBlue),
            (localizedInsightEvening, accentAmber),
            (localizedInsightLateNight, accentRose)
        ]
        var legendX = chartPanel.minX + 14
        for item in legend {
            item.1.setFill()
            NSBezierPath(ovalIn: NSRect(x: legendX, y: legendY + 4, width: 7, height: 7)).fill()
            drawText(item.0, rect: NSRect(x: legendX + 11, y: legendY, width: 78, height: 15), font: .systemFont(ofSize: 9, weight: .semibold), color: NSColor.white.withAlphaComponent(0.52))
            legendX += min(92, chartPanel.width / 4)
        }
    }

    func aggregateInsightHours(_ report: RepoInsightsReport) -> [RepoInsightHour] {
        var buckets: [Int: RepoInsightHour] = [:]
        for row in report.rows {
            for hour in row.hours {
                var bucket = buckets[hour.hour] ?? RepoInsightHour(hour: hour.hour, conversations: 0, turns: 0, tokens: 0)
                bucket.conversations += hour.conversations
                bucket.turns += hour.turns
                bucket.tokens += hour.tokens
                buckets[hour.hour] = bucket
            }
        }
        return buckets.values.sorted { $0.hour < $1.hour }
    }

    func insightAxisTickValues(maxValue: Int) -> [Int] {
        guard maxValue > 0 else { return [0, 1] }
        if maxValue <= 4 {
            return Array(0...maxValue)
        }
        let roughStep = Double(maxValue) / 4.0
        let magnitude = pow(10.0, floor(log10(roughStep)))
        let normalized = roughStep / magnitude
        let multiplier: Double
        if normalized <= 1 {
            multiplier = 1
        } else if normalized <= 2 {
            multiplier = 2
        } else if normalized <= 5 {
            multiplier = 5
        } else {
            multiplier = 10
        }
        let step = max(1, Int(multiplier * magnitude))
        let top = Int(ceil(Double(maxValue) / Double(step))) * step
        return stride(from: 0, through: top, by: step).map { $0 }
    }

    func drawInsightTimePeriodCards(hours: [RepoInsightHour], rect: NSRect) {
        let groups = insightPeriodDefinitions()
        let totals = groups.map { item in
            (item.0, hours.filter { item.1.contains($0.hour) }.reduce(0) { $0 + $1.turns }, item.2)
        }
        let totalTurns = max(1, totals.reduce(0) { $0 + $1.1 })
        let gap: CGFloat = 10
        let cardW = (rect.width - gap * CGFloat(max(0, totals.count - 1))) / CGFloat(max(1, totals.count))
        for (index, item) in totals.enumerated() {
            let card = NSRect(x: rect.minX + CGFloat(index) * (cardW + gap), y: rect.minY, width: cardW, height: rect.height)
            insightPeriodRects[item.0] = card
            inputSurfaceColor.withAlphaComponent(0.62).setFill()
            NSBezierPath(roundedRect: card, xRadius: 7, yRadius: 7).fill()
            item.2.withAlphaComponent(0.80).setFill()
            NSBezierPath(roundedRect: NSRect(x: card.minX, y: card.minY, width: 4, height: card.height), xRadius: 2, yRadius: 2).fill()
            if hoveredInsightPeriod == item.0 {
                NSColor.white.withAlphaComponent(0.22).setStroke()
                let focus = NSBezierPath(roundedRect: card.insetBy(dx: -2, dy: -2), xRadius: 8, yRadius: 8)
                focus.lineWidth = 1.3
                focus.stroke()
            }
            drawText(item.0, rect: NSRect(x: card.minX + 14, y: card.minY + 10, width: card.width - 28, height: 16), font: .systemFont(ofSize: 11, weight: .bold), color: NSColor.white.withAlphaComponent(0.58))
            drawText("\(item.1)", rect: NSRect(x: card.minX + 14, y: card.minY + 30, width: card.width * 0.55, height: 24), font: .monospacedDigitSystemFont(ofSize: 18, weight: .bold), color: item.2.withAlphaComponent(0.96))
            let percent = Int(round(Double(item.1) / Double(totalTurns) * 100))
            drawRight("\(percent)%", rect: NSRect(x: card.midX, y: card.minY + 34, width: card.width / 2 - 14, height: 18), color: NSColor.white.withAlphaComponent(0.44), font: .monospacedDigitSystemFont(ofSize: 12, weight: .semibold))
        }
    }

    func drawInsightUsageTimeTooltip() {
        guard selectedSection == .insights,
              selectedInsightDetailMode == .usageTime,
              let snapshot else {
            return
        }
        let report = insightReport(for: snapshot)
        let hours = aggregateInsightHours(report)
        let totalTurns = max(1, hours.reduce(0) { $0 + $1.turns })

        let title: String
        let color: NSColor
        let anchorRect: NSRect
        let lines: [(String, String)]

        if let hoveredInsightHour,
           let rect = insightHourBarRects[hoveredInsightHour] ?? insightHourRects[hoveredInsightHour] {
            let turns = hours.first(where: { $0.hour == hoveredInsightHour })?.turns ?? 0
            title = String(format: "%02d:00-%02d:00", hoveredInsightHour, (hoveredInsightHour + 1) % 24)
            color = insightHourColor(hoveredInsightHour)
            anchorRect = rect
            lines = [
                (localizedInsightTooltipTurns, "\(turns) \(t(.turns).lowercased())"),
                (localizedInsightTooltipShare, "\(Int(round(Double(turns) / Double(totalTurns) * 100)))%"),
                (localizedInsightTooltipDailyAverage, String(format: "%.1f %@", Double(turns) / Double(max(1, selectedInsightWindowDays)), t(.turns).lowercased())),
                (localizedInsightTooltipPeriod, localizedInsightDayPart(for: hoveredInsightHour))
            ]
        } else if let hoveredInsightPeriod,
                  let rect = insightPeriodRects[hoveredInsightPeriod],
                  let period = insightPeriodDefinitions().first(where: { $0.0 == hoveredInsightPeriod }) {
            let periodHours = hours.filter { period.1.contains($0.hour) }
            let turns = periodHours.reduce(0) { $0 + $1.turns }
            let peak = periodHours.max { $0.turns < $1.turns }
            title = hoveredInsightPeriod
            color = period.2
            anchorRect = rect
            lines = [
                (localizedInsightTooltipTurns, "\(turns) \(t(.turns).lowercased())"),
                (localizedInsightTooltipShare, "\(Int(round(Double(turns) / Double(totalTurns) * 100)))%"),
                (localizedInsightTooltipDailyAverage, String(format: "%.1f %@", Double(turns) / Double(max(1, selectedInsightWindowDays)), t(.turns).lowercased())),
                (localizedInsightTooltipHourlyAverage, String(format: "%.1f %@", Double(turns) / 6.0, t(.turns).lowercased())),
                (localizedInsightTooltipPeakHour, peak.map { String(format: "%02d:00 · %d", $0.hour, $0.turns) } ?? "--")
            ]
        } else {
            return
        }

        let width: CGFloat = 236
        let rowHeight: CGFloat = 20
        let height: CGFloat = 42 + CGFloat(lines.count) * rowHeight
        var origin = CGPoint(x: anchorRect.midX - width / 2, y: anchorRect.minY - height - 10)
        if origin.y < bounds.minY + 12 {
            origin.y = anchorRect.maxY + 10
        }
        origin.x = max(bounds.minX + 12, min(origin.x, bounds.maxX - width - 12))
        origin.y = max(bounds.minY + 12, min(origin.y, bounds.maxY - height - 12))
        let rect = NSRect(origin: origin, size: CGSize(width: width, height: height))

        NSColor(calibratedWhite: 0.055, alpha: 0.97).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()
        color.withAlphaComponent(0.55).setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        border.lineWidth = 1
        border.stroke()
        drawText(title, rect: NSRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - 24, height: 18), font: .systemFont(ofSize: 12, weight: .bold), color: .white)

        for (index, line) in lines.enumerated() {
            let y = rect.minY + 34 + CGFloat(index) * rowHeight
            drawText(line.0, rect: NSRect(x: rect.minX + 12, y: y, width: 104, height: 16), font: .systemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.58))
            drawRight(line.1, rect: NSRect(x: rect.minX + 118, y: y, width: rect.width - 130, height: 16), color: color.withAlphaComponent(0.96), font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold))
        }
    }

    func insightPeriodDefinitions() -> [(String, Range<Int>, NSColor)] {
        [
            (localizedInsightMorning, 6..<12, accentTeal),
            (localizedInsightAfternoon, 12..<18, accentBlue),
            (localizedInsightEvening, 18..<24, accentAmber),
            (localizedInsightLateNight, 0..<6, accentRose)
        ]
    }

    func insightUsageTimeSummary(_ hours: [RepoInsightHour]) -> String {
        guard let peak = hours.max(by: { $0.turns < $1.turns }), peak.turns > 0 else {
            return localizedInsightNoUsageTime
        }
        return localizedInsightPeakSummary(range: localizedInsightDayPart(for: peak.hour), hour: peak.hour, turns: peak.turns)
    }

    func insightHourColor(_ hour: Int) -> NSColor {
        switch hour {
        case 6..<12: return accentTeal
        case 12..<18: return accentBlue
        case 18..<24: return accentAmber
        default: return accentRose
        }
    }

    func localizedInsightDetailMode(_ mode: InsightDetailMode) -> String {
        switch (mode, AppLanguage.current) {
        case (.usageHabits, .chinese), (.usageHabits, .traditionalChinese): return "使用习惯"
        case (.usageHabits, .japanese): return "使い方"
        case (.usageHabits, .polish): return "Nawyki"
        case (.usageHabits, .english): return "Habits"
        case (.usageHabits, _): return "Habits"
        case (.usageTime, .chinese), (.usageTime, .traditionalChinese): return "使用时间"
        case (.usageTime, .japanese): return "時間帯"
        case (.usageTime, .polish): return "Godziny"
        case (.usageTime, .english): return "Time"
        case (.usageTime, _): return "Time"
        case (.reasoningDepth, .chinese), (.reasoningDepth, .traditionalChinese): return "思考深度"
        case (.reasoningDepth, .japanese): return "思考深度"
        case (.reasoningDepth, .polish): return "Rozumowanie"
        case (.reasoningDepth, .english): return "Reasoning"
        case (.reasoningDepth, _): return "Reasoning"
        }
    }

    var localizedReasoningDepthPageTitle: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "思考深度"
        case .japanese: return "思考深度"
        case .polish: return "Glebokosc rozumowania"
        case .english: return "Reasoning Depth"
        default: return "Reasoning Depth"
        }
    }

    var localizedReasoningDepthPageSubtitle: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "查看思考等级、会话数量与 Token 消耗之间的关系"
        case .japanese: return "思考レベル、タスク数、Token 消費の関係を確認"
        case .polish: return "Relacja poziomu rozumowania, zadan i zuzycia tokenow"
        case .english: return "Compare reasoning effort, session volume, and token consumption"
        default: return "Compare reasoning effort, session volume, and token consumption"
        }
    }

    var localizedInsightUsageTimeTitle: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "调用时间分布（按小时）"
        case .japanese: return "利用時間の分布（時間別）"
        case .polish: return "Rozkład użycia według godzin"
        case .english: return "Usage time distribution by hour"
        default: return "Usage time distribution by hour"
        }
    }

    var localizedInsightUsageTimePageTitle: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "使用时间"
        case .japanese: return "利用時間"
        case .polish: return "Godziny uzycia"
        case .english: return "Usage Time"
        default: return "Usage Time"
        }
    }

    var localizedInsightUsageTimePageSubtitle: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "按来源和时间窗口查看高峰调用时段"
        case .japanese: return "ソースと期間ごとの利用ピークを確認"
        case .polish: return "Pory szczytu wedlug zrodla i zakresu"
        case .english: return "Find peak usage periods by source and window"
        default: return "Find peak usage periods by source and window"
        }
    }

    var localizedInsightTooltipTurns: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "数量"
        case .japanese: return "回数"
        case .polish: return "Liczba"
        case .english: return "Count"
        default: return "Count"
        }
    }

    var localizedInsightTooltipShare: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "占比"
        case .japanese: return "割合"
        case .polish: return "Udzial"
        case .english: return "Share"
        default: return "Share"
        }
    }

    var localizedInsightTooltipDailyAverage: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "日均"
        case .japanese: return "日平均"
        case .polish: return "Dziennie"
        case .english: return "Daily avg"
        default: return "Daily avg"
        }
    }

    var localizedInsightTooltipHourlyAverage: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "小时均值"
        case .japanese: return "時間平均"
        case .polish: return "Na godz."
        case .english: return "Hourly avg"
        default: return "Hourly avg"
        }
    }

    var localizedInsightTooltipPeriod: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "时段"
        case .japanese: return "時間帯"
        case .polish: return "Pora"
        case .english: return "Period"
        default: return "Period"
        }
    }

    var localizedInsightTooltipPeakHour: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "峰值小时"
        case .japanese: return "ピーク時間"
        case .polish: return "Szczyt"
        case .english: return "Peak hour"
        default: return "Peak hour"
        }
    }

    var localizedInsightHourlyCallsTitle: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "24 小时调用柱状图"
        case .japanese: return "24時間の利用バー"
        case .polish: return "Godzinowy wykres uzycia"
        case .english: return "24-hour usage bars"
        default: return "24-hour usage bars"
        }
    }

    var localizedInsightNoUsageTime: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "这个窗口内还没有可展示的调用时间。"
        case .japanese: return "この期間には表示できる利用時間がありません。"
        case .polish: return "Brak godzin użycia w tym zakresie."
        case .english: return "No usage time is available for this window."
        default: return "No usage time is available for this window."
        }
    }

    var localizedInsightMorning: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "早上"
        case .japanese: return "朝"
        case .polish: return "Rano"
        case .english: return "Morning"
        default: return "Morning"
        }
    }

    var localizedInsightAfternoon: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "下午"
        case .japanese: return "午後"
        case .polish: return "Popoludnie"
        case .english: return "Afternoon"
        default: return "Afternoon"
        }
    }

    var localizedInsightEvening: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "晚上"
        case .japanese: return "夜"
        case .polish: return "Wieczor"
        case .english: return "Evening"
        default: return "Evening"
        }
    }

    var localizedInsightLateNight: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "深夜"
        case .japanese: return "深夜"
        case .polish: return "Noc"
        case .english: return "Late night"
        default: return "Late night"
        }
    }

    func localizedInsightDayPart(for hour: Int) -> String {
        switch hour {
        case 6..<12: return localizedInsightMorning
        case 12..<18: return localizedInsightAfternoon
        case 18..<24: return localizedInsightEvening
        default: return localizedInsightLateNight
        }
    }

    func localizedInsightPeakSummary(range: String, hour: Int, turns: Int) -> String {
        let turnValue = "\(turns) \(t(.turns).lowercased())"
        switch AppLanguage.current {
        case .chinese, .traditionalChinese:
            return "高峰在\(range)，\(String(format: "%02d:00", hour)) 附近最多（\(turnValue)）。"
        case .japanese:
            return "ピークは\(range)、\(String(format: "%02d:00", hour)) 頃が最多（\(turnValue)）。"
        case .polish:
            return "Szczyt: \(range), okolo \(String(format: "%02d:00", hour)) (\(turnValue))."
        case .english:
            return "Peak usage is in the \(range.lowercased()), highest around \(String(format: "%02d:00", hour)) (\(turnValue))."
        default:
            return "Peak usage is in the \(range.lowercased()), highest around \(String(format: "%02d:00", hour)) (\(turnValue))."
        }
    }

    func drawInsightRecommendations(_ row: RepoInsight, rect: NSRect) {
        let copy = AppLanguage.current.insightCopy
        let recommendations = insightRecommendations(for: row)
        guard let primary = recommendations.first else { return }
        drawText(copy.recommendationsTitle, rect: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 16), font: .systemFont(ofSize: 12, weight: .bold), color: .white)
        let card = NSRect(x: rect.minX, y: rect.minY + 22, width: rect.width, height: 38)
        primary.2.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: card, xRadius: 7, yRadius: 7).fill()
        primary.2.withAlphaComponent(0.34).setStroke()
        let outline = NSBezierPath(roundedRect: card.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        outline.lineWidth = 1
        outline.stroke()
        drawTruncatedText(primary.0, rect: NSRect(x: card.minX + 12, y: card.minY + 4, width: card.width - 24, height: 14), font: .systemFont(ofSize: 11, weight: .bold), color: primary.2)
        drawTruncatedText(primary.1, rect: NSRect(x: card.minX + 12, y: card.minY + 20, width: card.width - 24, height: 14), font: .systemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.60))
        let secondary = recommendations.dropFirst().map(\.0).joined(separator: "  ·  ")
        if !secondary.isEmpty {
            drawTruncatedText(secondary, rect: NSRect(x: rect.minX + 2, y: card.maxY + 7, width: rect.width - 4, height: 14), font: .systemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.42))
        }
    }

    func drawInsightHeatmap(row: RepoInsight, rect: NSRect) {
        let copy = AppLanguage.current.insightCopy
        drawPanel(rect)
        drawText(copy.heatmapTitle, rect: NSRect(x: rect.minX + 16, y: rect.minY + 14, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 13, weight: .bold), color: .white)
        let days = recentInsightDays(count: 90)
        let dayMap = Dictionary(uniqueKeysWithValues: row.days.map { ($0.day, $0) })
        let cols = 30
        let rows = 3
        let gap: CGFloat = 4
        let legendW: CGFloat = min(170, rect.width * 0.22)
        let gridW = rect.width - 32 - legendW - 18
        let cell = min(CGFloat(16), (gridW - CGFloat(cols - 1) * gap) / CGFloat(cols))
        let startX = rect.minX + 16
        let startY = rect.minY + 48
        for (index, day) in days.enumerated() {
            let col = index / rows
            let rowIndex = index % rows
            let cellRect = NSRect(x: startX + CGFloat(col) * (cell + gap), y: startY + CGFloat(rowIndex) * (cell + gap), width: cell, height: cell)
            insightDayColor(dayMap[day]).setFill()
            NSBezierPath(roundedRect: cellRect, xRadius: 3, yRadius: 3).fill()
        }
        let legendX = startX + CGFloat(cols) * (cell + gap) + 18
        let legends: [(String, NSColor)] = [
            (copy.normalLegend, accentTeal),
            (copy.highLegend, accentAmber),
            (copy.veryHighLegend, accentRose),
            (copy.noActivityLegend, NSColor.white.withAlphaComponent(0.10))
        ]
        for (index, legend) in legends.enumerated() {
            let y = rect.minY + 44 + CGFloat(index) * 22
            legend.1.setFill()
            NSBezierPath(ovalIn: NSRect(x: legendX, y: y + 4, width: 8, height: 8)).fill()
            drawText(legend.0, rect: NSRect(x: legendX + 14, y: y, width: rect.maxX - legendX - 24, height: 16), font: .systemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.58))
        }
    }

    func insightDayColor(_ day: RepoInsightDay?) -> NSColor {
        guard let day, day.conversations > 0 else {
            return NSColor.white.withAlphaComponent(0.08)
        }
        let rate = Double(day.compressions) / Double(max(1, day.conversations))
        if rate > 1 {
            return accentRose.withAlphaComponent(0.82)
        }
        if rate > 0.3 {
            return accentAmber.withAlphaComponent(0.82)
        }
        return accentTeal.withAlphaComponent(0.72)
    }

    func insightRecommendations(for row: RepoInsight) -> [(String, String, NSColor)] {
        let colors: [NSColor]
        switch row.risk {
        case .frequentCompression:
            colors = [accentRose, accentAmber, accentBlue]
        case .longRunning:
            colors = [accentAmber, accentBlue, accentTeal]
        case .wellSplit, .healthy:
            colors = [accentTeal, accentBlue, accentAmber]
        }
        return AppLanguage.current.insightCopy.recommendations(row.risk).enumerated().map { index, item in
            (item.title, item.body, colors[min(index, colors.count - 1)])
        }
    }

    func drawInsightRiskPill(_ risk: RepoInsightRisk, rect: NSRect) {
        let label = AppLanguage.current.insightCopy.riskLabel(risk)
        let color = insightRiskColor(risk)
        color.withAlphaComponent(0.42).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        drawCentered(label, rect: rect.insetBy(dx: 4, dy: 0), font: .systemFont(ofSize: 10, weight: .bold), color: color.withAlphaComponent(0.95))
    }

    func insightRiskColor(_ risk: RepoInsightRisk) -> NSColor {
        switch risk {
        case .frequentCompression: return accentRose
        case .longRunning: return accentAmber
        case .wellSplit: return accentTeal
        case .healthy: return NSColor.systemGreen
        }
    }

    var localizedInsightFilterAll: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "全部"
        case .japanese: return "すべて"
        case .polish: return "Wszystkie"
        default: return "All"
        }
    }

    var localizedInsightGoodStatus: String {
        switch AppLanguage.current {
        case .chinese: return "状态良好"
        case .traditionalChinese: return "狀態良好"
        case .japanese: return "良好"
        case .polish: return "W normie"
        default: return "Doing fine"
        }
    }

    var localizedInsightAttentionGroup: String {
        switch AppLanguage.current {
        case .chinese: return "需要关注"
        case .traditionalChinese: return "需要關注"
        case .japanese: return "要注意"
        case .polish: return "Wymaga uwagi"
        default: return "Needs attention"
        }
    }

    func insightDiagnosisText(for row: RepoInsight) -> String {
        let days = selectedInsightWindowDays
        let avg = String(format: "%.2f", row.averageCompressionsPerConversation)
        let percent = Int(round(row.compressionConversationRate * 100))
        switch AppLanguage.current {
        case .chinese:
            switch row.risk {
            case .frequentCompression:
                return "\(days) 天内 \(row.conversations) 个会话共压缩 \(row.compressions) 次，平均 \(avg) 次/会话，明显偏高；\(percent)% 的会话发生过压缩，最长 \(row.longestTurns) 轮次。"
            case .longRunning:
                return "会话偏长：最长 \(row.longestTurns) 轮次，平均压缩 \(avg) 次/会话；建议阶段完成后开新窗口，避免触发压缩。"
            case .wellSplit:
                return "切分习惯良好：会话普遍较短，平均压缩 \(avg) 次/会话，上下文保持干净。"
            case .healthy:
                return "\(days) 天内 \(row.conversations) 个会话，平均压缩 \(avg) 次/会话，处于健康区间，保持当前节奏即可。"
            }
        case .traditionalChinese:
            switch row.risk {
            case .frequentCompression:
                return "\(days) 天內 \(row.conversations) 個會話共壓縮 \(row.compressions) 次，平均 \(avg) 次/會話，明顯偏高；\(percent)% 的會話發生過壓縮，最長 \(row.longestTurns) 輪次。"
            case .longRunning:
                return "會話偏長：最長 \(row.longestTurns) 輪次，平均壓縮 \(avg) 次/會話；建議階段完成後開新視窗，避免觸發壓縮。"
            case .wellSplit:
                return "切分習慣良好：會話普遍較短，平均壓縮 \(avg) 次/會話，上下文保持乾淨。"
            case .healthy:
                return "\(days) 天內 \(row.conversations) 個會話，平均壓縮 \(avg) 次/會話，處於健康區間，保持目前節奏即可。"
            }
        case .japanese:
            switch row.risk {
            case .frequentCompression:
                return "直近\(days)日で\(row.conversations)会話・圧縮\(row.compressions)回（平均\(avg)回/会話）と高水準。\(percent)%の会話で圧縮が発生、最長\(row.longestTurns) turns。"
            case .longRunning:
                return "会話が長め：最長\(row.longestTurns) turns、平均圧縮\(avg)回/会話。区切りごとに新しいウィンドウを開くのがおすすめ。"
            case .wellSplit:
                return "分割が良好：会話は短めで平均圧縮\(avg)回/会話。コンテキストはきれいに保たれています。"
            case .healthy:
                return "直近\(days)日で\(row.conversations)会話、平均圧縮\(avg)回/会話。健全な範囲です。"
            }
        default:
            switch row.risk {
            case .frequentCompression:
                return "\(row.conversations) sessions compacted \(row.compressions) times in \(days) days — \(avg) per session, well above healthy; \(percent)% of sessions hit compaction, longest \(row.longestTurns) Turns."
            case .longRunning:
                return "Sessions run long: up to \(row.longestTurns) Turns, \(avg) compactions per session. Start a fresh window after each milestone."
            case .wellSplit:
                return "Well split: sessions stay short with \(avg) compactions per session, keeping context clean."
            case .healthy:
                return "\(row.conversations) sessions in \(days) days with \(avg) compactions per session — comfortably in the healthy range."
            }
        }
    }

    func recentInsightDays(count: Int) -> [String] {
        let formatter = dayFormatter()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<count).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { formatter.string(from: $0) }
        }
    }

}
