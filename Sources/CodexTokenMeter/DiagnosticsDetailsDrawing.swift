import Cocoa

extension UsageDetailsView {
    func drawDiagnosticsPage(snapshot: DetailsSnapshot, content: NSRect) {
        let sourceRect = NSRect(x: content.minX, y: content.minY + 78, width: content.width, height: 268)
        drawPanel(sourceRect)
        drawText(t(.sourceHealth), rect: NSRect(x: sourceRect.minX + 16, y: sourceRect.minY + 14, width: 220, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        drawDiagnosticRows(sourceDiagnostics(snapshot: snapshot), rect: NSRect(x: sourceRect.minX + 16, y: sourceRect.minY + 48, width: sourceRect.width - 32, height: sourceRect.height - 64))

        let apiRect = NSRect(x: content.minX, y: sourceRect.maxY + 16, width: content.width, height: 124)
        drawPanel(apiRect)
        drawText(t(.externalAPICost), rect: NSRect(x: apiRect.minX + 16, y: apiRect.minY + 14, width: 220, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        drawText(t(.externalAPICostHint), rect: NSRect(x: apiRect.minX + 16, y: apiRect.minY + 40, width: apiRect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.52))
        drawDiagnosticRows(apiDiagnostics(), rect: NSRect(x: apiRect.minX + 16, y: apiRect.minY + 66, width: apiRect.width - 32, height: 44))

        let toolsRect = NSRect(x: content.minX, y: apiRect.maxY + 16, width: content.width, height: 168)
        drawPanel(toolsRect)
        drawText(t(.otherTools), rect: NSRect(x: toolsRect.minX + 16, y: toolsRect.minY + 14, width: 220, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        drawDiagnosticRows(otherToolDiagnostics(), rect: NSRect(x: toolsRect.minX + 16, y: toolsRect.minY + 48, width: toolsRect.width - 32, height: toolsRect.height - 64))
    }

    private func drawDiagnosticRows(_ rows: [(String, String, NSColor)], rect: NSRect) {
        let rowHeight = min(CGFloat(28), rect.height / CGFloat(max(rows.count, 1)))
        for (index, row) in rows.enumerated() {
            let y = rect.minY + CGFloat(index) * rowHeight
            guard y + min(22, rowHeight) <= rect.maxY + 0.5 else { break }
            drawText(row.0, rect: NSRect(x: rect.minX, y: y + 2, width: min(220, rect.width * 0.34), height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(0.58))
            let dot = NSRect(x: rect.maxX - 10, y: y + max(5, (rowHeight - 8) / 2), width: 8, height: 8)
            row.2.setFill()
            NSBezierPath(ovalIn: dot).fill()
            drawRight(row.1, rect: NSRect(x: rect.minX + rect.width * 0.34, y: y + 1, width: rect.width * 0.64 - 18, height: 18), color: .white, font: .systemFont(ofSize: 12, weight: .semibold))
        }
    }

    private func sourceDiagnostics(snapshot: DetailsSnapshot) -> [(String, String, NSColor)] {
        selectedDetailsSource == .claude ? claudeSourceDiagnostics(snapshot: snapshot) : codexSourceDiagnostics(snapshot: snapshot)
    }

    private func codexSourceDiagnostics(snapshot: DetailsSnapshot) -> [(String, String, NSColor)] {
        let cliPath = LiveRateLimitReader.codexExecutablePath()
        let authURL = AppSettings.defaultCodexHomeURL.appendingPathComponent("auth.json")
        let liveText = snapshot.liveLimits.isEmpty
            ? t(.liveLimitUnavailable)
            : "\(snapshot.liveLimits.count) windows"
        let serviceText = snapshot.serviceStatus.map { localizedCodexStatus($0.overallStatus) } ?? t(.codexStatusUnavailable)
        let serviceColor = snapshot.serviceStatus.map { codexStatusColor($0.overallStatus) } ?? accentAmber
        let incidentText = snapshot.serviceStatus?.activeIncident?.name ?? t(.codexNoActiveIncident)
        let incidentColor = snapshot.serviceStatus?.activeIncident.map { codexStatusColor($0.status) } ?? NSColor.white.withAlphaComponent(0.58)
        let profileText: String
        let profileColor: NSColor
        if !AppSettings.profileAPITotalsEnabled {
            profileText = t(.disabled)
            profileColor = accentAmber
        } else if let accountUsage = snapshot.accountUsage, accountUsage.hasData {
            profileText = accountUsage.summary.lifetimeTokens.map { compact($0) } ?? "\(accountUsage.dailyUsageBuckets.count) days"
            profileColor = accentTeal
        } else {
            profileText = t(.liveLimitUnavailable)
            profileColor = accentRose
        }
        let rollouts = AppSettings.logFolderURLs.reduce(0) { $0 + rolloutCount(in: $1, modifiedWithinDays: 14) }
        return [
            ("Codex CLI", cliPath.map(shortenedPath) ?? t(.fileMissing), cliPath == nil ? accentRose : accentTeal),
            ("auth.json", FileManager.default.fileExists(atPath: authURL.path) ? t(.filePresent) : t(.fileMissing), FileManager.default.fileExists(atPath: authURL.path) ? accentTeal : accentAmber),
            (t(.liveQuota), liveText, snapshot.liveLimits.isEmpty ? accentRose : accentTeal),
            (t(.codexStatus), serviceText, serviceColor),
            (t(.codexIncident), incidentText, incidentColor),
            (t(.profileAPITotals), profileText, profileColor),
            (t(.modelLimit), "\(AppSettings.modelLimitName) / \(AppSettings.modelLimitID)", accentTeal),
            (t(.logFolder), "\(AppSettings.logFolderURLs.count) roots", AppSettings.logFolderURLs.isEmpty ? accentRose : accentTeal),
            (t(.recentRollouts), "\(rollouts) files / 14d", rollouts > 0 ? accentTeal : accentAmber),
            (t(.quotaWarnings), AppSettings.quotaWarningsEnabled ? t(.enabled) : t(.disabled), AppSettings.quotaWarningsEnabled ? accentTeal : accentAmber)
        ]
    }

    private func claudeSourceDiagnostics(snapshot: DetailsSnapshot) -> [(String, String, NSColor)] {
        let claudeLogs = AppSettings.claudeLogFolderURLs.reduce(0) { $0 + jsonlCount(in: $1, modifiedWithinDays: 14) }
        let claudeRootExists = AppSettings.claudeLogFolderURLs.contains { FileManager.default.fileExists(atPath: $0.path) }
        let claudeStatuslineStore = ClaudeStatuslineStore()
        let claudeStatusline = claudeStatuslineStore.read()
        let claudeStatuslineText: String
        let claudeStatuslineColor: NSColor
        if let claudeStatusline, claudeStatusline.liveRateLimit != nil {
            let fiveHour = claudeStatusline.fiveHour.map { "\(Int(round($0.usedPercent)))% 5h" } ?? "5h --"
            let sevenDay = claudeStatusline.sevenDay.map { "\(Int(round($0.usedPercent)))% 7d" } ?? "7d --"
            claudeStatuslineText = "\(fiveHour) / \(sevenDay)"
            claudeStatuslineColor = accentTeal
        } else {
            claudeStatuslineText = "not captured: \(shortenedPath(claudeStatuslineStore.path))"
            claudeStatuslineColor = accentAmber
        }
        return [
            (t(.claudeLogs), AppSettings.claudeLogFolderDisplayPath, claudeRootExists ? accentTeal : accentAmber),
            (t(.recentRollouts), "\(claudeLogs) files / 14d", claudeLogs > 0 ? accentTeal : accentAmber),
            ("Claude statusline", claudeStatuslineText, claudeStatuslineColor),
            (t(.claudeActiveRefresh), AppSettings.claudeActiveQuotaRefreshEnabled ? t(.enabled) : t(.disabled), AppSettings.claudeActiveQuotaRefreshEnabled ? accentTeal : accentAmber),
            (t(.cacheHit), String(format: "%.0f%%", snapshot.all.usage.cachePercent), accentTeal),
            (t(.models), "\(snapshot.all.modelBreakdown.count)", accentTeal),
            (t(.sessions), "\(snapshot.all.sessions)", accentTeal),
            (t(.turns), "\(snapshot.all.turns)", accentTeal)
        ]
    }

    private func apiDiagnostics() -> [(String, String, NSColor)] {
        let url = AppSettings.externalAPICostURL
        if let snapshot = ExternalAPICostStore.read(url: url), snapshot.hasData {
            let tokenPart = snapshot.totalTokens > 0 ? " · \(compact(snapshot.totalTokens)) tokens" : ""
            return [
                ("api-usage.json", "\(displayAPIMoney(snapshot.usdValue))\(tokenPart)", accentTeal),
                ("Path", shortenedPath(url.path), NSColor.white.withAlphaComponent(0.62))
            ]
        }
        return [
            ("api-usage.json", t(.fileMissing), accentAmber),
            ("Path", shortenedPath(url.path), NSColor.white.withAlphaComponent(0.62))
        ]
    }

    private func otherToolDiagnostics() -> [(String, String, NSColor)] {
        let home = NSHomeDirectory()
        let probes: [(String, String, Bool)] = [
            ("Codex", AppSettings.logFolderDisplayPath, true),
            ("Claude Code", "\(home)/.claude/projects", true),
            ("Cursor", "\(home)/Library/Application Support/Cursor", false),
            ("OpenCode", "\(home)/.local/share/opencode", false),
            ("Gemini CLI", "\(home)/.gemini", false)
        ]
        return probes.map { name, path, tracked in
            let exists = FileManager.default.fileExists(atPath: path)
            let value: String
            if tracked {
                value = t(.tracked)
            } else if exists {
                value = t(.detectedNotTracked)
            } else {
                value = t(.fileMissing)
            }
            let color: NSColor = tracked ? accentTeal : (exists ? accentAmber : NSColor.white.withAlphaComponent(0.36))
            return (name, value, color)
        }
    }

    private func rolloutCount(in root: URL, modifiedWithinDays days: Int) -> Int {
        let start = Date().addingTimeInterval(-TimeInterval(days) * 24 * 3600)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var count = 0
        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasPrefix("rollout-"), url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if (values?.contentModificationDate ?? .distantPast) >= start {
                count += 1
            }
        }
        return count
    }

    private func jsonlCount(in root: URL, modifiedWithinDays days: Int) -> Int {
        let start = Date().addingTimeInterval(-TimeInterval(days) * 24 * 3600)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var count = 0
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if (values?.contentModificationDate ?? .distantPast) >= start {
                count += 1
            }
        }
        return count
    }

    private func shortenedPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path.count > 72 ? "..." + path.suffix(69) : path
    }

}
