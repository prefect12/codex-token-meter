import Cocoa
import Foundation
import ServiceManagement
import UserNotifications

// MARK: - CLI And Snapshot Rendering

func requestedWindow(from arguments: [String]) -> WindowOption? {
    arguments.compactMap { argument -> WindowOption? in
        guard argument.hasPrefix("--window=") else { return nil }
        switch argument.dropFirst("--window=".count) {
        case "24h", "day": return .day
        case "7d", "week": return .week
        case "30d", "month": return .month
        default: return nil
        }
    }.first
}

func requestedQuota(from arguments: [String]) -> QuotaViewOption? {
    arguments.compactMap { argument -> QuotaViewOption? in
        guard argument.hasPrefix("--quota=") else { return nil }
        return QuotaViewOption.option(from: String(argument.dropFirst("--quota=".count)))
    }.first
}

func scanReport(window: WindowOption, source: QuotaViewOption, codexScanner: CodexTokenScanner, claudeScanner: ClaudeTokenScanner) -> TokenReport {
    switch source {
    case .all:
        return mergedTokenReport([
            codexScanner.scan(window: window),
            claudeScanner.scan(window: window)
        ])
    case .codex:
        return codexScanner.scan(window: window)
    case .claude:
        return claudeScanner.scan(window: window)
    }
}

func scanReport(hours: Int, source: QuotaViewOption, codexScanner: CodexTokenScanner, claudeScanner: ClaudeTokenScanner) -> TokenReport {
    switch source {
    case .all:
        return mergedTokenReport([
            codexScanner.scan(hours: hours),
            claudeScanner.scan(hours: hours)
        ])
    case .codex:
        return codexScanner.scan(hours: hours)
    case .claude:
        return claudeScanner.scan(hours: hours)
    }
}

func requestedHours(from arguments: [String], defaultValue: Int = WindowOption.week.rawValue) -> Int {
    arguments.compactMap { argument -> Int? in
        guard argument.hasPrefix("--hours=") else { return nil }
        return Int(argument.dropFirst("--hours=".count))
    }.first ?? defaultValue
}

func requestedDetailsSection(from arguments: [String]) -> DetailsSection {
    let rawSection = arguments
        .compactMap { argument -> String? in
            guard argument.hasPrefix("--section=") else { return nil }
            return String(argument.dropFirst("--section=".count))
        }
        .first ?? "overview"

    switch rawSection {
    case "overview": return .overview
    case "calendar": return .calendar
    case "insights": return .insights
    case "costs": return .costs
    case "models": return .models
    case "settings": return .settings
    case "diagnostics": return .diagnostics
    case "about": return .about
    default: return .overview
    }
}

func requestedDetailsSource(from arguments: [String]) -> QuotaViewOption? {
    arguments.compactMap { argument -> QuotaViewOption? in
        if argument.hasPrefix("--details-source=") {
            return QuotaViewOption.option(from: String(argument.dropFirst("--details-source=".count)))
        }
        if argument.hasPrefix("--source=") {
            return QuotaViewOption.option(from: String(argument.dropFirst("--source=".count)))
        }
        return nil
    }.first
}

func writePNG(of view: NSView, to url: URL) throws {
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        throw NSError(domain: "CodexTokenMeter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create bitmap"])
    }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "CodexTokenMeter", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
    }
    try data.write(to: url, options: [.atomic])
}

func renderDashboardSnapshot(arguments: [String]) throws -> URL {
    let scanner = CodexTokenScanner(rootURLs: AppSettings.logFolderURLs)
    let claudeScanner = ClaudeTokenScanner(rootURLs: AppSettings.claudeLogFolderURLs)
    let window = requestedWindow(from: arguments) ?? .week
    let quota = requestedQuota(from: arguments) ?? .all
    let codexReport = quota == .all ? scanner.scan(window: window) : nil
    let claudeReport = quota == .all ? claudeScanner.scan(window: window) : nil
    let report: TokenReport
    if let codexReport, let claudeReport {
        report = mergedTokenReport([codexReport, claudeReport])
    } else {
        report = scanReport(window: window, source: quota, codexScanner: scanner, claudeScanner: claudeScanner)
    }
    let liveLimits = combinedLiveLimits()
    let serviceStatus = CodexServiceStatusReader().read()
    let accountUsage = AppSettings.profileAPITotalsEnabled ? AccountUsageReader().read() : nil
    let profileReport = AppSettings.profileAPITotalsEnabled
        ? profileBackedReport(
            window: window,
            quota: quota,
            accountUsage: accountUsage,
            localReport: report,
            localCodexReport: codexReport,
            localClaudeReport: claudeReport
        )
        : nil

    let outputURL = arguments
        .compactMap { argument -> URL? in
            guard argument.hasPrefix("--render-dashboard=") else { return nil }
            return URL(fileURLWithPath: String(argument.dropFirst("--render-dashboard=".count)))
        }
        .first ?? URL(fileURLWithPath: "/tmp/codex-token-meter-dashboard.png")

    let state = DashboardState(
        report: report,
        codexReport: codexReport,
        claudeReport: claudeReport,
        profileReport: profileReport,
        accountUsage: accountUsage,
        costReferenceReport: nil,
        liveLimits: liveLimits,
        serviceStatus: serviceStatus,
        selectedWindow: window,
        selectedQuota: quota,
        nextRefreshAt: Date().addingTimeInterval(300),
        isLoading: false,
        error: nil
    )

    let view = DashboardView(frame: NSRect(origin: .zero, size: DashboardView.idealSize))
    view.update(state)
    let preferredSize = view.preferredPopoverSize
    view.frame = NSRect(origin: .zero, size: preferredSize)
    view.layoutSubtreeIfNeeded()
    try writePNG(of: view, to: outputURL)
    return outputURL
}

func renderDetailsSnapshot(arguments: [String]) throws -> URL {
    let scanner = CodexTokenScanner(rootURLs: AppSettings.logFolderURLs)
    let claudeScanner = ClaudeTokenScanner(rootURLs: AppSettings.claudeLogFolderURLs)
    let section = requestedDetailsSection(from: arguments)
    let source = requestedDetailsSource(from: arguments) ?? .all
    let isInsightsSection = section == .insights
    let accountUsage = !isInsightsSection && AppSettings.profileAPITotalsEnabled ? AccountUsageReader().read() : nil
    let codex = isInsightsSection ? TokenReport(scannedAt: Date()) : scanner.scan(window: .week)
    let claude = isInsightsSection ? TokenReport(scannedAt: Date()) : claudeScanner.scan(window: .week)
    let all = mergedTokenReport([codex, claude])
    let codexRepoInsightReports = scanner.scanRepoInsights(windows: [7, 30, 90])
    let claudeRepoInsightReports = claudeScanner.scanRepoInsights(windows: [7, 30, 90])
    let repoInsightReports = Dictionary(uniqueKeysWithValues: [7, 30, 90].map { days in
        let report = mergedRepoInsightsReport(
            [
                codexRepoInsightReports[days] ?? RepoInsightsReport(rows: [], scannedAt: Date(), windowDays: days),
                claudeRepoInsightReports[days] ?? RepoInsightsReport(rows: [], scannedAt: Date(), windowDays: days)
            ],
            windowDays: days
        )
        return (days, report)
    })
    let repoInsights = repoInsightReports[90] ?? RepoInsightsReport(rows: [], scannedAt: Date(), windowDays: 90)
    let codexRepoInsights = codexRepoInsightReports[90] ?? RepoInsightsReport(rows: [], scannedAt: Date(), windowDays: 90)
    let claudeRepoInsights = claudeRepoInsightReports[90] ?? RepoInsightsReport(rows: [], scannedAt: Date(), windowDays: 90)
    let snapshot = DetailsSnapshot(
        all: all,
        codex: codex,
        claude: claude,
        repoInsights: repoInsights,
        repoInsightReports: repoInsightReports,
        codexRepoInsights: codexRepoInsights,
        codexRepoInsightReports: codexRepoInsightReports,
        claudeRepoInsights: claudeRepoInsights,
        claudeRepoInsightReports: claudeRepoInsightReports,
        liveLimits: isInsightsSection ? [] : combinedLiveLimits(),
        serviceStatus: isInsightsSection ? nil : CodexServiceStatusReader().read(),
        costReferenceReport: source == .codex ? codex : all,
        accountUsage: accountUsage
    )

    let outputURL = arguments
        .compactMap { argument -> URL? in
            guard argument.hasPrefix("--render-details=") else { return nil }
            return URL(fileURLWithPath: String(argument.dropFirst("--render-details=".count)))
        }
        .first ?? URL(fileURLWithPath: "/tmp/codex-token-meter-details.png")

    let view = UsageDetailsView(frame: NSRect(x: 0, y: 0, width: 1280, height: 760))
    let windowDays = arguments
        .compactMap { argument -> Int? in
            guard argument.hasPrefix("--insight-window=") else { return nil }
            return Int(argument.dropFirst("--insight-window=".count))
        }
        .first ?? 90
    let insightMode = arguments
        .compactMap { argument -> String? in
            guard argument.hasPrefix("--insight-mode=") else { return nil }
            return String(argument.dropFirst("--insight-mode=".count))
        }
        .first
    view.showSection(section, insightWindowDays: windowDays, source: source, insightMode: insightMode)
    view.snapshot = snapshot
    view.isLoading = false
    view.layoutSubtreeIfNeeded()
    try writePNG(of: view, to: outputURL)
    return outputURL
}
