import Cocoa

extension UsageDetailsView {
    struct StoragePageLayout {
        var toolbar: NSRect
        var cards: NSRect
        var source: NSRect
        var projects: NSRect
        var growth: NSRect
        var risk: NSRect
        var footer: NSRect
        var totalHeight: CGFloat
    }

    func storagePageLayout(content: NSRect) -> StoragePageLayout {
        let wide = content.width >= 900
        var y = content.minY + 78
        let toolbar = NSRect(x: content.minX, y: y, width: content.width, height: 28)
        y = toolbar.maxY + 12
        let cards = NSRect(x: content.minX, y: y, width: content.width, height: 84)
        y = cards.maxY + 14

        let sourceRows = CGFloat(max(1, storageVisibleCategories().count))
        let sourceHeight = 46 + sourceRows * 52 + 14
        let source: NSRect
        let projects: NSRect
        if wide {
            let sourceW = floor((content.width - 16) * 0.52)
            let middleH = max(sourceHeight, 420)
            source = NSRect(x: content.minX, y: y, width: sourceW, height: middleH)
            projects = NSRect(x: source.maxX + 16, y: y, width: content.width - sourceW - 16, height: middleH)
            y = source.maxY + 16
        } else {
            source = NSRect(x: content.minX, y: y, width: content.width, height: sourceHeight)
            projects = NSRect(x: content.minX, y: source.maxY + 16, width: content.width, height: 420)
            y = projects.maxY + 16
        }

        let growth: NSRect
        let risk: NSRect
        if wide {
            let growthW = floor((content.width - 16) * 0.62)
            growth = NSRect(x: content.minX, y: y, width: growthW, height: 244)
            risk = NSRect(x: growth.maxX + 16, y: y, width: content.width - growthW - 16, height: 244)
            y = growth.maxY + 16
        } else {
            growth = NSRect(x: content.minX, y: y, width: content.width, height: 244)
            risk = NSRect(x: content.minX, y: growth.maxY + 16, width: content.width, height: 230)
            y = risk.maxY + 16
        }
        let footer = NSRect(x: content.minX, y: y, width: content.width, height: 36)
        return StoragePageLayout(
            toolbar: toolbar,
            cards: cards,
            source: source,
            projects: projects,
            growth: growth,
            risk: risk,
            footer: footer,
            totalHeight: footer.maxY + 44
        )
    }

    func storagePlatformCategories() -> [StorageCategoryUsage] {
        guard let snap = storageSnapshot else { return [] }
        return snap.categories
            .filter { category in
                (selectedDetailsSource == .all || category.id.platform == selectedDetailsSource)
                    && (category.bytes > 0 || category.fileCount > 0)
            }
            .sorted { $0.bytes > $1.bytes }
    }

    func storageVisibleCategories() -> [StorageCategoryUsage] {
        let base = storagePlatformCategories()
        guard let filter = storageFilterCategory, base.contains(where: { $0.id == filter }) else { return base }
        return base.filter { $0.id == filter }
    }

    func selectedStorageUsage() -> StorageCategoryUsage? {
        let visible = storagePlatformCategories()
        if let id = selectedStorageCategoryID, let match = visible.first(where: { $0.id == id }) {
            return match
        }
        return visible.first
    }

    func storageDayTotal(_ day: String, snap: StorageSnapshot) -> Int64 {
        let ids = Set(storageVisibleCategories().map { $0.id.rawValue })
        guard let perCategory = snap.dailyGrowth[day] else { return 0 }
        return perCategory.reduce(Int64(0)) { partial, entry in
            ids.contains(entry.key) ? partial + entry.value : partial
        }
    }

    func storageGrowthBreakdown(days: [String], snap: StorageSnapshot) -> [(StorageCategoryID, Int64)] {
        let ids = Set(storageVisibleCategories().map { $0.id })
        var totals: [StorageCategoryID: Int64] = [:]
        for day in days {
            guard let perCategory = snap.dailyGrowth[day] else { continue }
            for (raw, bytes) in perCategory {
                guard let id = StorageCategoryID(rawValue: raw), ids.contains(id) else { continue }
                totals[id, default: 0] += bytes
            }
        }
        return totals.sorted { $0.value > $1.value }
    }

    func storageFilteredProjects() -> [StorageProjectUsage] {
        guard let snap = storageSnapshot else { return [] }
        var rows = snap.projects.filter { project in
            selectedDetailsSource == .all || project.platform == selectedDetailsSource
        }
        let query = storageSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            rows = rows.filter {
                $0.name.localizedCaseInsensitiveContains(query) || $0.path.localizedCaseInsensitiveContains(query)
            }
        }
        switch storageSortOption {
        case .size:
            rows.sort { $0.bytes > $1.bytes }
        case .recent:
            rows.sort { ($0.newestModified ?? .distantPast) > ($1.newestModified ?? .distantPast) }
        case .name:
            rows.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return rows
    }

    func storageInsight(for project: StorageProjectUsage) -> RepoInsight? {
        guard let snapshot else { return nil }
        let report: RepoInsightsReport
        switch project.platform {
        case .claude:
            report = snapshot.claudeRepoInsights
        case .codex:
            report = snapshot.codexRepoInsights
        case .all:
            report = snapshot.repoInsights
        }
        return report.rows.first { $0.folders.contains(project.path) }
            ?? report.rows.first { $0.primaryFolder == project.path }
            ?? report.rows.first { $0.displayName.caseInsensitiveCompare(project.name) == .orderedSame }
    }

    func storageProjectNeedsReview(_ project: StorageProjectUsage) -> Bool {
        guard project.bytes > 300 * 1_048_576 else { return false }
        guard let newest = project.newestModified else { return true }
        return newest < Date().addingTimeInterval(-30 * 86_400)
    }

    func storageCategoryColor(_ id: StorageCategoryID) -> NSColor {
        switch id {
        case .codexSessions: return .systemGreen
        case .codexWorktrees: return accentBlue
        case .codexBackups: return accentAmber
        case .codexDatabase: return .systemPurple
        case .codexImages: return .systemPink
        case .codexPlugins: return .systemTeal
        case .codexOther: return .systemGray
        case .claudeProjects: return .systemOrange
        case .claudeOther: return .systemBrown
        }
    }

    func storageRiskColor(_ risk: StorageRisk) -> NSColor {
        switch risk {
        case .safeToClear: return accentTeal
        case .reviewFirst: return accentAmber
        case .doNotClean: return accentRose
        }
    }

    func storageSymbolName(_ id: StorageCategoryID) -> String {
        switch id {
        case .codexSessions: return "doc.text"
        case .codexWorktrees: return "folder"
        case .codexBackups: return "archivebox"
        case .codexDatabase: return "externaldrive"
        case .codexImages: return "photo"
        case .codexPlugins: return "puzzlepiece"
        case .codexOther: return "shippingbox"
        case .claudeProjects: return "cube"
        case .claudeOther: return "tray.full"
        }
    }

    func drawStorageIcon(_ id: StorageCategoryID, in rect: NSRect) {
        let color = storageCategoryColor(id)
        color.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        if let base = NSImage(systemSymbolName: storageSymbolName(id), accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)) {
            let tinted = NSImage(size: base.size)
            tinted.lockFocus()
            base.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)
            color.set()
            NSRect(origin: .zero, size: base.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            let target = NSRect(
                x: rect.midX - base.size.width / 2,
                y: rect.midY - base.size.height / 2,
                width: base.size.width,
                height: base.size.height
            )
            tinted.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
        } else {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.midX - 4, y: rect.midY - 4, width: 8, height: 8)).fill()
        }
    }

    func handleStorageMouseDown(at point: CGPoint) -> Bool {
        if let rect = storageRefreshRect, rect.contains(point) {
            if !isStorageScanning {
                isStorageScanning = true
                onStorageScanRequested?()
            }
            return true
        }
        if let rect = storageExportRect, rect.contains(point) {
            exportStorageReport()
            return true
        }
        if let rect = storageOpenFinderRect, rect.contains(point) {
            if let path = selectedStorageUsage()?.roots.first {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
            return true
        }
        for (id, rect) in storageSourceMenuRects where rect.insetBy(dx: -4, dy: -4).contains(point) {
            showStorageCategoryMenu(id, at: point)
            return true
        }
        for (id, rect) in storageSourceRowRects where rect.contains(point) {
            selectedStorageCategoryID = id
            needsDisplay = true
            return true
        }
        return false
    }

    func showStorageCategoryMenu(_ id: StorageCategoryID, at point: CGPoint) {
        let copy = AppLanguage.current.storageCopy
        let menu = NSMenu()
        let reveal = NSMenuItem(title: copy.revealInFinder, action: #selector(storageMenuReveal(_:)), keyEquivalent: "")
        reveal.target = self
        reveal.representedObject = id.rawValue
        menu.addItem(reveal)
        let copyItem = NSMenuItem(title: copy.copyPath, action: #selector(storageMenuCopyPath(_:)), keyEquivalent: "")
        copyItem.target = self
        copyItem.representedObject = id.rawValue
        menu.addItem(copyItem)
        menu.popUp(positioning: nil, at: point, in: self)
    }

    func storageMenuCategory(_ sender: NSMenuItem) -> StorageCategoryUsage? {
        guard let raw = sender.representedObject as? String,
              let id = StorageCategoryID(rawValue: raw) else { return nil }
        return storageSnapshot?.category(id)
    }

    @objc private func storageMenuReveal(_ sender: NSMenuItem) {
        guard let path = storageMenuCategory(sender)?.roots.first else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    @objc private func storageMenuCopyPath(_ sender: NSMenuItem) {
        guard let usage = storageMenuCategory(sender), !usage.roots.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(usage.roots.joined(separator: "\n"), forType: .string)
    }

    @objc func storageFilterPopupChanged() {
        let index = storageFilterPopup.indexOfSelectedItem
        let cats = storagePlatformCategories()
        if index <= 0 || index > cats.count {
            storageFilterCategory = nil
        } else {
            storageFilterCategory = cats[index - 1].id
        }
        onPreferredHeightChanged?()
        needsDisplay = true
        needsLayout = true
    }

    @objc func storageSortPopupChanged() {
        let options: [StorageSortOption] = [.size, .recent, .name]
        let index = storageSortPopup.indexOfSelectedItem
        if index >= 0 && index < options.count {
            storageSortOption = options[index]
        }
        needsDisplay = true
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else { return }
        if field === storageSearchField {
            storageSearchText = field.stringValue
            needsDisplay = true
        }
    }

    func layoutModelControls() {
        let visible = selectedSection == .models && snapshot != nil
        let content = sectionContent(for: .models, in: bounds, sidebarWidth: detailsSidebarWidth)
        modelDateRangeControls.layout(content: content, visible: visible)
        modelControls.layout(content: content, tableY: content.minY + 264, visible: visible)
    }

    func layoutStorageControls() {
        let visible = selectedSection == .storage && storageSnapshot != nil
        storageFilterPopup.isHidden = !visible
        storageSortPopup.isHidden = !visible
        storageSearchField.isHidden = !visible
        guard visible else { return }
        let content = NSRect(x: detailsSidebarWidth + 28, y: 28, width: bounds.width - detailsSidebarWidth - 56, height: bounds.height - 56)
        let bar = storagePageLayout(content: content).toolbar
        let searchW = min(240, max(160, bar.width * 0.26))
        storageSearchField.frame = NSRect(x: bar.maxX - searchW, y: bar.minY + 1, width: searchW, height: 26)
        let sortW: CGFloat = 148
        storageSortPopup.frame = NSRect(x: storageSearchField.frame.minX - 10 - sortW, y: bar.minY, width: sortW, height: 28)
        let filterW: CGFloat = 148
        storageFilterPopup.frame = NSRect(x: storageSortPopup.frame.minX - 10 - filterW, y: bar.minY, width: filterW, height: 28)
        updateStoragePopupItems()
    }

    func updateStoragePopupItems() {
        let copy = AppLanguage.current.storageCopy
        let cats = storagePlatformCategories()
        let filterTitles = [copy.filterAll] + cats.map { copy.categories($0.id).name }
        if storageFilterPopup.itemArray.map(\.title) != filterTitles {
            storageFilterPopup.removeAllItems()
            storageFilterPopup.addItems(withTitles: filterTitles)
        }
        let filterIndex = storageFilterCategory.flatMap { id in cats.firstIndex { $0.id == id }.map { $0 + 1 } } ?? 0
        if storageFilterPopup.indexOfSelectedItem != filterIndex, filterIndex < storageFilterPopup.numberOfItems {
            storageFilterPopup.selectItem(at: filterIndex)
        }
        let sortTitles = [copy.sortBySize, copy.sortByRecent, copy.sortByName]
        if storageSortPopup.itemArray.map(\.title) != sortTitles {
            storageSortPopup.removeAllItems()
            storageSortPopup.addItems(withTitles: sortTitles)
        }
        let sortIndex = [StorageSortOption.size, .recent, .name].firstIndex(of: storageSortOption) ?? 0
        if storageSortPopup.indexOfSelectedItem != sortIndex {
            storageSortPopup.selectItem(at: sortIndex)
        }
        if storageSearchField.placeholderString != copy.searchPlaceholder {
            storageSearchField.placeholderString = copy.searchPlaceholder
        }
    }

    func exportStorageReport() {
        guard let snap = storageSnapshot, let window else { return }
        let copy = AppLanguage.current.storageCopy
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ai-token-meter-storage-report.md"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            var lines: [String] = []
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            lines.append("# AI Token Meter · \(copy.headerTitle)")
            lines.append("")
            lines.append(String(format: copy.scannedAtFormat, formatter.string(from: snap.scannedAt)))
            lines.append("")
            lines.append("| \(copy.sourceTitle) | \(copy.colSize) | \(copy.colAdvice) |")
            lines.append("| --- | ---: | --- |")
            for usage in snap.categories.sorted(by: { $0.bytes > $1.bytes }) where usage.bytes > 0 {
                let name = copy.categories(usage.id).name
                lines.append("| \(name) (\(usage.roots.joined(separator: ", "))) | \(storageByteText(usage.bytes)) | \(copy.riskLabel(usage.id.risk)) |")
            }
            lines.append("")
            lines.append("| \(copy.colProject) | \(copy.colApp) | \(copy.colSize) |")
            lines.append("| --- | --- | ---: |")
            for project in snap.projects.prefix(20) {
                lines.append("| \(project.path) | \(project.platform == .claude ? "Claude" : "Codex") | \(storageByteText(project.bytes)) |")
            }
            lines.append("")
            lines.append("> \(copy.caveat)")
            do {
                try lines.joined(separator: "\n").data(using: .utf8)?.write(to: url, options: [.atomic])
                NSWorkspace.shared.open(url)
            } catch {
                NSSound.beep()
            }
        }
    }

    func drawStoragePage(content: NSRect) {
        let copy = AppLanguage.current.storageCopy
        guard let snap = storageSnapshot else {
            drawText(copy.scanningLabel, rect: NSRect(x: content.minX, y: content.minY + 92, width: content.width, height: 24), font: .systemFont(ofSize: 15, weight: .semibold), color: NSColor.white.withAlphaComponent(0.56))
            return
        }
        let layout = storagePageLayout(content: content)
        drawStorageStatCards(snap: snap, copy: copy, rect: layout.cards)
        drawStorageSourcePanel(snap: snap, copy: copy, rect: layout.source)
        drawStorageProjectsPanel(snap: snap, copy: copy, rect: layout.projects)
        drawStorageGrowthChart(snap: snap, copy: copy, rect: layout.growth)
        drawStorageRiskPanel(snap: snap, copy: copy, rect: layout.risk)
        drawStorageFooter(snap: snap, copy: copy, rect: layout.footer)
    }

    func drawStorageStatCards(snap: StorageSnapshot, copy: StorageCopy, rect: NSRect) {
        let totalBytes = snap.totalBytes(platform: .all)
        let codexBytes = snap.totalBytes(platform: .codex)
        let claudeBytes = snap.totalBytes(platform: .claude)
        let fileCount = snap.totalFileCount(platform: selectedDetailsSource)
        let recentBytes = snap.recentGrowthBytes(platform: selectedDetailsSource)
        func share(_ value: Int64) -> String {
            guard totalBytes > 0 else { return "--" }
            return String(format: copy.shareFormat, String(format: "%.1f%%", Double(value) / Double(totalBytes) * 100))
        }
        let cards: [(String, String, String, NSColor)] = [
            (copy.totalCard, storageByteText(totalBytes), "\(format(totalBytes)) \(copy.bytesSuffix)", .systemGreen),
            ("Codex", storageByteText(codexBytes), share(codexBytes), .systemCyan),
            ("Claude", storageByteText(claudeBytes), share(claudeBytes), .systemOrange),
            (copy.fileCountCard, format(Int64(fileCount)), copy.fileCountHint, NSColor.white.withAlphaComponent(0.92)),
            (copy.recentCard, storageGrowthText(recentBytes), String(format: copy.filesFormat, format(Int64(snap.recentGrowthFiles(platform: selectedDetailsSource)))), accentTeal)
        ]
        let gap: CGFloat = 12
        let cardW = (rect.width - gap * CGFloat(cards.count - 1)) / CGFloat(cards.count)
        let valueFontSize: CGFloat = cardW < 158 ? 15 : (cardW < 200 ? 17 : 19)
        for (index, card) in cards.enumerated() {
            let cardRect = NSRect(x: rect.minX + CGFloat(index) * (cardW + gap), y: rect.minY, width: cardW, height: rect.height)
            drawPanel(cardRect)
            drawTruncatedText(card.0, rect: NSRect(x: cardRect.minX + 14, y: cardRect.minY + 11, width: cardRect.width - 28, height: 15), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.5))
            drawTruncatedText(card.1, rect: NSRect(x: cardRect.minX + 14, y: cardRect.minY + 29, width: cardRect.width - 28, height: 24), font: .monospacedDigitSystemFont(ofSize: valueFontSize, weight: .bold), color: card.3)
            drawTruncatedText(card.2, rect: NSRect(x: cardRect.minX + 14, y: cardRect.minY + 58, width: cardRect.width - 28, height: 14), font: .systemFont(ofSize: 9.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.4))
        }
    }

    func drawStorageSourcePanel(snap: StorageSnapshot, copy: StorageCopy, rect: NSRect) {
        drawPanel(rect)
        drawText(copy.sourceTitle, rect: NSRect(x: rect.minX + 16, y: rect.minY + 14, width: rect.width - 170, height: 18), font: .systemFont(ofSize: 13.5, weight: .bold), color: .white)
        let visible = storageVisibleCategories()
        let visibleTotal = visible.reduce(Int64(0)) { $0 + $1.bytes }
        drawRight(String(format: copy.totalFormat, storageByteText(visibleTotal)), rect: NSRect(x: rect.maxX - 166, y: rect.minY + 16, width: 150, height: 15), color: NSColor.white.withAlphaComponent(0.44), font: .systemFont(ofSize: 10.5, weight: .semibold))

        guard !visible.isEmpty else {
            drawText(copy.emptyCategoriesHint, rect: NSRect(x: rect.minX + 16, y: rect.minY + 52, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }

        let maxBytes = max(visible.map { $0.bytes }.max() ?? 1, 1)
        let selectedUsage = selectedStorageUsage()
        let rowH: CGFloat = 52
        let maxRows = max(1, Int((rect.height - 46 - 12) / rowH))
        for (index, usage) in visible.prefix(maxRows).enumerated() {
            let row = NSRect(x: rect.minX + 10, y: rect.minY + 46 + CGFloat(index) * rowH, width: rect.width - 20, height: rowH - 4)
            storageSourceRowRects[usage.id] = row
            if usage.id == selectedUsage?.id {
                accentBlue.withAlphaComponent(0.14).setFill()
                NSBezierPath(roundedRect: row, xRadius: 7, yRadius: 7).fill()
            } else if usage.id == hoveredStorageSourceID {
                NSColor.white.withAlphaComponent(0.05).setFill()
                NSBezierPath(roundedRect: row, xRadius: 7, yRadius: 7).fill()
            }
            drawStorageIcon(usage.id, in: NSRect(x: row.minX + 8, y: row.minY + 8, width: 32, height: 32))

            let nameX = row.minX + 52
            let sizeX = row.maxX - 128
            let name = copy.categories(usage.id).name
            let nameFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
            let nameW = min(measuredTextWidth(name, font: nameFont), sizeX - nameX - 92)
            drawTruncatedText(name, rect: NSRect(x: nameX, y: row.minY + 6, width: nameW + 4, height: 17), font: nameFont, color: .white)
            let chipText = copy.riskLabel(usage.id.risk)
            let chipW = measuredTextWidth(chipText, font: .systemFont(ofSize: 8.5, weight: .semibold)) + 14
            drawStorageRiskChip(chipText, color: storageRiskColor(usage.id.risk), rect: NSRect(x: nameX + nameW + 10, y: row.minY + 8, width: chipW, height: 15), fontSize: 8.5)

            let home = NSHomeDirectory()
            let pathText = usage.roots
                .map { $0.hasPrefix(home) ? "~" + $0.dropFirst(home.count) : $0 }
                .joined(separator: ", ")
            drawTruncatedText(pathText, rect: NSRect(x: nameX, y: row.minY + 26, width: max(40, sizeX - nameX - 10), height: 13), font: .systemFont(ofSize: 9.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.4))

            drawRight(storageByteText(usage.bytes), rect: NSRect(x: sizeX, y: row.minY + 7, width: 86, height: 16), color: .white, font: .monospacedDigitSystemFont(ofSize: 12.5, weight: .bold))
            let pct = visibleTotal > 0 ? Double(usage.bytes) / Double(visibleTotal) * 100 : 0
            drawRight(String(format: "%.1f%%", pct), rect: NSRect(x: sizeX, y: row.minY + 26, width: 86, height: 13), color: NSColor.white.withAlphaComponent(0.45), font: .monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold))

            let menuRect = NSRect(x: row.maxX - 30, y: row.minY + 14, width: 22, height: 20)
            storageSourceMenuRects[usage.id] = menuRect
            NSColor.white.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: menuRect, xRadius: 5, yRadius: 5).fill()
            drawCentered("⋯", rect: menuRect, font: .systemFont(ofSize: 12, weight: .bold), color: NSColor.white.withAlphaComponent(0.6))

            let barTrack = NSRect(x: nameX, y: row.minY + 42, width: max(30, sizeX - nameX - 10), height: 3)
            NSColor.white.withAlphaComponent(0.07).setFill()
            NSBezierPath(roundedRect: barTrack, xRadius: 1.5, yRadius: 1.5).fill()
            let fraction = CGFloat(Double(usage.bytes) / Double(maxBytes))
            let fill = NSRect(x: barTrack.minX, y: barTrack.minY, width: max(2, barTrack.width * fraction), height: barTrack.height)
            storageCategoryColor(usage.id).withAlphaComponent(0.8).setFill()
            NSBezierPath(roundedRect: fill, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }

    func drawStorageProjectsPanel(snap: StorageSnapshot, copy: StorageCopy, rect: NSRect) {
        drawPanel(rect)
        drawText(copy.projectsTitle, rect: NSRect(x: rect.minX + 16, y: rect.minY + 14, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 13.5, weight: .bold), color: .white)

        let rows = storageFilteredProjects()
        guard !rows.isEmpty else {
            drawText(copy.noProjectsHint, rect: NSRect(x: rect.minX + 16, y: rect.minY + 52, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }

        let compactColumns = rect.width < 470
        let adviceW: CGFloat = 58
        let turnsW: CGFloat = compactColumns ? 0 : 46
        let tokensW: CGFloat = compactColumns ? 0 : 62
        let sizeW: CGFloat = 74
        let appW: CGFloat = compactColumns ? 0 : 52
        let gap: CGFloat = 10
        let adviceX = rect.maxX - 14 - adviceW
        let turnsX = adviceX - (turnsW > 0 ? gap + turnsW : 0)
        let tokensX = turnsX - (tokensW > 0 ? gap + tokensW : 0)
        let sizeX = tokensX - gap - sizeW
        let appX = sizeX - (appW > 0 ? gap + appW : 0)
        let nameMaxX = (appW > 0 ? appX : sizeX) - 12

        let headerFont = NSFont.systemFont(ofSize: 9.5, weight: .bold)
        let headerColor = NSColor.white.withAlphaComponent(0.38)
        let headerY = rect.minY + 42
        drawText(copy.colProject, rect: NSRect(x: rect.minX + 16, y: headerY, width: nameMaxX - rect.minX - 16, height: 13), font: headerFont, color: headerColor)
        if appW > 0 {
            drawRight(copy.colApp, rect: NSRect(x: appX, y: headerY, width: appW, height: 13), color: headerColor, font: headerFont)
        }
        drawRight(copy.colSize, rect: NSRect(x: sizeX, y: headerY, width: sizeW, height: 13), color: headerColor, font: headerFont)
        if tokensW > 0 {
            drawRight(copy.colTokens, rect: NSRect(x: tokensX, y: headerY, width: tokensW, height: 13), color: headerColor, font: headerFont)
        }
        if turnsW > 0 {
            drawRight(copy.colTurns, rect: NSRect(x: turnsX, y: headerY, width: turnsW, height: 13), color: headerColor, font: headerFont)
        }
        drawRight(copy.colAdvice, rect: NSRect(x: adviceX, y: headerY, width: adviceW, height: 13), color: headerColor, font: headerFont)

        let rowH: CGFloat = 44
        let maxRows = max(1, Int((rect.height - 62 - 8) / rowH))
        let home = NSHomeDirectory()
        for (index, project) in rows.prefix(maxRows).enumerated() {
            let y = rect.minY + 60 + CGFloat(index) * rowH
            if index > 0 {
                NSColor.white.withAlphaComponent(0.045).setFill()
                NSRect(x: rect.minX + 16, y: y - 2, width: rect.width - 32, height: 1).fill()
            }
            drawTruncatedText(project.name, rect: NSRect(x: rect.minX + 16, y: y + 4, width: max(40, nameMaxX - rect.minX - 16), height: 16), font: .systemFont(ofSize: 12, weight: .bold), color: .white)
            let displayPath = project.path.hasPrefix(home) ? "~" + project.path.dropFirst(home.count) : project.path
            drawTruncatedText(displayPath, rect: NSRect(x: rect.minX + 16, y: y + 22, width: max(40, nameMaxX - rect.minX - 16), height: 13), font: .systemFont(ofSize: 9, weight: .medium), color: NSColor.white.withAlphaComponent(0.38))
            if appW > 0 {
                drawRight(project.platform == .claude ? "Claude" : "Codex", rect: NSRect(x: appX, y: y + 6, width: appW, height: 15), color: NSColor.white.withAlphaComponent(0.6), font: .systemFont(ofSize: 10.5, weight: .semibold))
            }
            drawRight(storageByteText(project.bytes), rect: NSRect(x: sizeX, y: y + 6, width: sizeW, height: 15), color: .white, font: .monospacedDigitSystemFont(ofSize: 11.5, weight: .bold))
            let insight = storageInsight(for: project)
            if tokensW > 0 {
                drawRight(insight.map { compact($0.tokens) } ?? "—", rect: NSRect(x: tokensX, y: y + 6, width: tokensW, height: 15), color: NSColor.white.withAlphaComponent(0.62), font: .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold))
            }
            if turnsW > 0 {
                drawRight(insight.map { format(Int64($0.turns)) } ?? "—", rect: NSRect(x: turnsX, y: y + 6, width: turnsW, height: 15), color: NSColor.white.withAlphaComponent(0.62), font: .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold))
            }
            let needsReview = storageProjectNeedsReview(project)
            drawRight(needsReview ? copy.adviceReview : copy.adviceKeep, rect: NSRect(x: adviceX, y: y + 6, width: adviceW, height: 15), color: needsReview ? accentAmber : accentTeal, font: .systemFont(ofSize: 10.5, weight: .bold))
        }
    }

    func drawStorageGrowthChart(snap: StorageSnapshot, copy: StorageCopy, rect: NSRect) {
        drawPanel(rect)
        drawText(copy.growthTitle, rect: NSRect(x: rect.minX + 16, y: rect.minY + 14, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 13.5, weight: .bold), color: .white)

        let days = snap.recentDays
        guard !days.isEmpty else { return }
        let visible = storageVisibleCategories()
        let recentTotals = storageGrowthBreakdown(days: days, snap: snap)
        let topIDs = Array(recentTotals.prefix(3).map { $0.0 })
        var series: [(String, NSColor, StorageCategoryID?)] = topIDs.map {
            (copy.categories($0).name, storageCategoryColor($0), $0)
        }
        let hasOther = visible.count > topIDs.count
        if hasOther {
            series.append((copy.otherSeries, NSColor.systemGray, nil))
        }

        var legendX = rect.maxX - 16
        let legendFont = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
        for entry in series.reversed() {
            let labelW = measuredTextWidth(entry.0, font: legendFont)
            legendX -= labelW
            drawText(entry.0, rect: NSRect(x: legendX, y: rect.minY + 17, width: labelW + 4, height: 13), font: legendFont, color: NSColor.white.withAlphaComponent(0.55))
            legendX -= 12
            entry.1.withAlphaComponent(0.9).setFill()
            NSBezierPath(ovalIn: NSRect(x: legendX, y: rect.minY + 20, width: 7, height: 7)).fill()
            legendX -= 14
        }

        let plot = NSRect(x: rect.minX + 58, y: rect.minY + 46, width: rect.width - 58 - 18, height: rect.height - 46 - 34)
        let dayTotals = days.map { storageDayTotal($0, snap: snap) }
        let maxTotal = max(dayTotals.max() ?? 1, 1)

        let axisFont = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .medium)
        let axisColor = NSColor.white.withAlphaComponent(0.35)
        for step in 0...2 {
            let value = Int64(Double(maxTotal) * Double(step) / 2.0)
            let y = plot.maxY - plot.height * CGFloat(step) / 2
            NSColor.white.withAlphaComponent(step == 0 ? 0.12 : 0.05).setFill()
            NSRect(x: plot.minX, y: y - 0.5, width: plot.width, height: 1).fill()
            drawRight(storageByteText(value), rect: NSRect(x: rect.minX + 8, y: y - 6, width: 46, height: 12), color: axisColor, font: axisFont)
        }

        let slotW = plot.width / CGFloat(days.count)
        let barW = max(6, slotW * 0.52)
        let enabledIDs = Set(visible.map { $0.id })
        for (index, day) in days.enumerated() {
            let total = dayTotals[index]
            let slotX = plot.minX + CGFloat(index) * slotW
            let barX = slotX + (slotW - barW) / 2
            var stackY = plot.maxY
            if total > 0 {
                let perCategory = snap.dailyGrowth[day] ?? [:]
                var seriesValues: [(NSColor, Int64)] = []
                var accounted: Int64 = 0
                for id in topIDs {
                    let value = perCategory[id.rawValue] ?? 0
                    accounted += value
                    if value > 0 {
                        seriesValues.append((storageCategoryColor(id), value))
                    }
                }
                if hasOther {
                    let otherValue = perCategory.reduce(Int64(0)) { partial, entry in
                        guard let id = StorageCategoryID(rawValue: entry.key), enabledIDs.contains(id), !topIDs.contains(id) else { return partial }
                        return partial + entry.value
                    }
                    if otherValue > 0 {
                        seriesValues.append((NSColor.systemGray, otherValue))
                    }
                }
                let totalHeight = max(3, plot.height * CGFloat(Double(total) / Double(maxTotal)))
                for (color, value) in seriesValues {
                    let segment = max(1.5, totalHeight * CGFloat(Double(value) / Double(total)))
                    let segmentRect = NSRect(x: barX, y: stackY - segment, width: barW, height: segment)
                    let hovered = hoveredStorageCellKey == "day-\(day)"
                    color.withAlphaComponent(hovered ? 1.0 : 0.82).setFill()
                    NSBezierPath(roundedRect: segmentRect, xRadius: 1.5, yRadius: 1.5).fill()
                    stackY -= segment
                }
                storageGrowthCells.append(StorageGrowthCell(
                    key: "day-\(day)",
                    rect: NSRect(x: slotX, y: plot.minY, width: slotW, height: plot.height),
                    title: localizedContributionDate(day),
                    rows: storageGrowthBreakdown(days: [day], snap: snap),
                    total: total
                ))
            } else {
                NSColor.white.withAlphaComponent(0.06).setFill()
                NSBezierPath(roundedRect: NSRect(x: barX, y: plot.maxY - 2, width: barW, height: 2), xRadius: 1, yRadius: 1).fill()
            }
            if index % 2 == days.count % 2 {
                let parts = day.split(separator: "-")
                let label = parts.count == 3 ? "\(Int(parts[1]) ?? 0)/\(Int(parts[2]) ?? 0)" : String(day.suffix(5))
                drawCentered(label, rect: NSRect(x: slotX - 6, y: plot.maxY + 6, width: slotW + 12, height: 12), font: .monospacedDigitSystemFont(ofSize: 8.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.4))
            }
        }
    }

    func drawStorageRiskPanel(snap: StorageSnapshot, copy: StorageCopy, rect: NSRect) {
        drawPanel(rect)
        drawText(copy.riskTitle, rect: NSRect(x: rect.minX + 16, y: rect.minY + 14, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 13.5, weight: .bold), color: .white)
        let categories = storagePlatformCategories()
        let totalBytes = categories.reduce(Int64(0)) { $0 + $1.bytes }
        let riskOrder: [StorageRisk] = [.safeToClear, .reviewFirst, .doNotClean]
        let riskTotals = riskOrder.map { risk in
            (risk, categories.filter { $0.id.risk == risk }.reduce(Int64(0)) { $0 + $1.bytes })
        }

        let diameter = min(rect.height - 76, 136)
        let thickness = max(13, diameter * 0.13)
        let center = CGPoint(x: rect.minX + 26 + diameter / 2, y: rect.minY + 42 + (rect.height - 58) / 2)
        let outerRect = NSRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        if totalBytes <= 0 {
            fillDonut(in: outerRect, thickness: thickness, color: NSColor.white.withAlphaComponent(0.1))
        } else {
            var angle = -CGFloat.pi / 2
            for (risk, bytes) in riskTotals where bytes > 0 {
                let sweep = CGFloat(Double(bytes) / Double(totalBytes)) * .pi * 2
                fillDonutSegment(center: center, outerRadius: diameter / 2, thickness: thickness, startAngle: angle, endAngle: angle + sweep, color: storageRiskColor(risk).withAlphaComponent(0.92))
                angle += sweep
            }
        }
        drawCentered(storageByteText(totalBytes), rect: NSRect(x: outerRect.minX + 6, y: center.y - 14, width: outerRect.width - 12, height: 17), font: .monospacedDigitSystemFont(ofSize: 13.5, weight: .bold), color: .white)
        drawCentered(detailsSourceTitle(selectedDetailsSource), rect: NSRect(x: outerRect.minX + 6, y: center.y + 4, width: outerRect.width - 12, height: 13), font: .systemFont(ofSize: 9.5, weight: .semibold), color: NSColor.white.withAlphaComponent(0.48))

        let legendX = outerRect.maxX + 20
        for (index, entry) in riskTotals.enumerated() {
            let y = center.y - 44 + CGFloat(index) * 30
            let dimmed = entry.1 <= 0
            let dot = NSRect(x: legendX, y: y + 4, width: 9, height: 9)
            storageRiskColor(entry.0).withAlphaComponent(dimmed ? 0.32 : 1.0).setFill()
            NSBezierPath(ovalIn: dot).fill()
            drawText(copy.riskLabel(entry.0), rect: NSRect(x: legendX + 16, y: y, width: max(40, rect.maxX - legendX - 110), height: 16), font: .systemFont(ofSize: 11.5, weight: .semibold), color: NSColor.white.withAlphaComponent(dimmed ? 0.3 : 0.85))
            let pct = totalBytes > 0 ? Double(entry.1) / Double(totalBytes) * 100 : 0
            let valueText = dimmed ? storageByteText(entry.1) : "\(storageByteText(entry.1)) (\(String(format: "%.1f%%", pct)))"
            drawRight(valueText, rect: NSRect(x: rect.maxX - 16 - 132, y: y, width: 132, height: 16), color: NSColor.white.withAlphaComponent(dimmed ? 0.3 : 0.92), font: .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold))
        }
    }

    func drawStorageFooter(snap: StorageSnapshot, copy: StorageCopy, rect: NSRect) {
        let buttonFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        var x = rect.maxX
        func placeButton(_ title: String, emphasized: Bool = false) -> NSRect {
            let width = max(72, measuredTextWidth(title, font: buttonFont) + 26)
            x -= width
            let buttonRect = NSRect(x: x, y: rect.minY + 4, width: width, height: 28)
            drawSmallButton(title, rect: buttonRect, emphasized: emphasized)
            x -= 10
            return buttonRect
        }
        storageRefreshRect = placeButton(copy.refreshButton)
        storageExportRect = placeButton(copy.exportReport)
        storageOpenFinderRect = placeButton(copy.openInFinder, emphasized: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        let status = String(format: copy.scannedAtFormat, formatter.string(from: snap.scannedAt))
        let caveatText = "⚠︎ \(copy.caveat)  ·  \(status)"
        drawTruncatedText(caveatText, rect: NSRect(x: rect.minX, y: rect.minY + 10, width: max(60, x - rect.minX - 12), height: 16), font: .systemFont(ofSize: 10.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.42))
    }

    func drawStorageRiskChip(_ title: String, color: NSColor, rect: NSRect, fontSize: CGFloat = 10, dimmed: Bool = false) {
        let alpha: CGFloat = dimmed ? 0.4 : 1.0
        color.withAlphaComponent(0.14 * alpha).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        color.withAlphaComponent(0.55 * alpha).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4).stroke()
        drawCentered(title, rect: rect.insetBy(dx: 2, dy: 0), font: .systemFont(ofSize: fontSize, weight: .semibold), color: color.withAlphaComponent(alpha))
    }

    func measuredTextHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        let bounding = (text as NSString).boundingRect(
            with: NSSize(width: width, height: 600),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: font]
        )
        return ceil(bounding.height)
    }

    func drawStorageSourceTooltip(container: NSRect) {
        guard let hoveredStorageSourceID,
              let row = storageSourceRowRects[hoveredStorageSourceID] else {
            return
        }
        let copy = AppLanguage.current.storageCopy
        let categoryCopy = copy.categories(hoveredStorageSourceID)
        let width: CGFloat = 270
        let bodyFont = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        let body = categoryCopy.purpose
        let impact = categoryCopy.impact
        let bodyH = measuredTextHeight(body, font: bodyFont, width: width - 24)
        let impactH = measuredTextHeight(impact, font: bodyFont, width: width - 24)
        let height = 12 + 18 + 6 + bodyH + 8 + impactH + 12
        var origin = CGPoint(x: row.maxX - width - 40, y: row.maxY + 8)
        if origin.y + height > container.maxY - 8 {
            origin.y = row.minY - height - 8
        }
        origin.x = max(container.minX + 12, min(origin.x, container.maxX - width - 12))
        origin.y = max(container.minY + 10, origin.y)
        let tooltipRect = NSRect(origin: origin, size: NSSize(width: width, height: height))

        NSColor(calibratedWhite: 0.055, alpha: 0.97).setFill()
        NSBezierPath(roundedRect: tooltipRect, xRadius: 8, yRadius: 8).fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        NSBezierPath(roundedRect: tooltipRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()

        drawText(categoryCopy.name, rect: NSRect(x: tooltipRect.minX + 12, y: tooltipRect.minY + 10, width: width - 24, height: 15), font: .systemFont(ofSize: 11, weight: .bold), color: NSColor.white.withAlphaComponent(0.92))
        drawMultilineText(body, rect: NSRect(x: tooltipRect.minX + 12, y: tooltipRect.minY + 34, width: width - 24, height: bodyH + 2), font: bodyFont, color: NSColor.white.withAlphaComponent(0.78))
        drawMultilineText(impact, rect: NSRect(x: tooltipRect.minX + 12, y: tooltipRect.minY + 34 + bodyH + 8, width: width - 24, height: impactH + 2), font: bodyFont, color: NSColor.white.withAlphaComponent(0.5))
    }

    func drawStorageGrowthTooltip(container: NSRect) {
        guard let hoveredStorageCellKey,
              let cell = storageGrowthCells.first(where: { $0.key == hoveredStorageCellKey }) else {
            return
        }
        let copy = AppLanguage.current.storageCopy
        let labelFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        let titleFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
        let rows: [(NSColor, String, Int64)] = cell.rows.prefix(5).map {
            (storageCategoryColor($0.0), copy.categories($0.0).name, $0.1)
        }
        let labelWidth = min(130, max(60, (rows.map { measuredTextWidth($0.1, font: labelFont) }.max() ?? 0) + 16))
        let valueWidth = max(70, (rows.map { measuredTextWidth(storageGrowthText($0.2), font: valueFont) }.max() ?? 0) + 4)
        let titleWidth = measuredTextWidth(cell.title, font: titleFont) + 24
        let width = min(max(max(titleWidth, labelWidth + valueWidth + 56), 200), 320)
        let height = CGFloat(34 + rows.count * 16 + 24)
        let anchor = cell.rect
        let gap: CGFloat = 12
        var origin = CGPoint(x: anchor.maxX + gap, y: anchor.midY - height / 2)
        if origin.x + width > container.maxX - 12 {
            origin.x = anchor.minX - gap - width
        }
        if origin.x < container.minX + 12 {
            origin.x = anchor.midX - width / 2
            origin.y = anchor.minY - height - gap
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

        drawText(cell.title, rect: NSRect(x: tooltipRect.minX + 12, y: tooltipRect.minY + 8, width: tooltipRect.width - 24, height: 14), font: titleFont, color: NSColor.white.withAlphaComponent(0.82))
        for (index, row) in rows.enumerated() {
            let y = tooltipRect.minY + 28 + CGFloat(index) * 16
            let dot = NSRect(x: tooltipRect.minX + 12, y: y + 3, width: 7, height: 7)
            row.0.setFill()
            NSBezierPath(ovalIn: dot).fill()
            drawText(row.1, rect: NSRect(x: tooltipRect.minX + 25, y: y, width: labelWidth + 20, height: 14), font: labelFont, color: NSColor.white.withAlphaComponent(0.62))
            drawRight(storageGrowthText(row.2), rect: NSRect(x: tooltipRect.maxX - 12 - valueWidth - 20, y: y - 1, width: valueWidth + 20, height: 15), color: NSColor.white.withAlphaComponent(0.88), font: valueFont)
        }
        let separatorY = tooltipRect.minY + 28 + CGFloat(rows.count) * 16 + 3
        NSColor.white.withAlphaComponent(0.10).setFill()
        NSRect(x: tooltipRect.minX + 12, y: separatorY, width: tooltipRect.width - 24, height: 1).fill()
        drawText(copy.totalLabel, rect: NSRect(x: tooltipRect.minX + 12, y: separatorY + 6, width: labelWidth + 20, height: 14), font: .systemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.78))
        drawRight(storageGrowthText(cell.total), rect: NSRect(x: tooltipRect.maxX - 12 - valueWidth - 20, y: separatorY + 5, width: valueWidth + 20, height: 15), color: .white, font: .monospacedDigitSystemFont(ofSize: 10, weight: .bold))
    }

    func drawPanel(_ rect: NSRect) {
        panelSurfaceColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        NSColor.white.withAlphaComponent(0.035).setFill()
        NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: min(1.5, rect.height)), xRadius: 0, yRadius: 0).fill()
        borderColor.setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
    }

}
