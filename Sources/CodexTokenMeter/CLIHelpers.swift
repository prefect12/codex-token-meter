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

func cliReport(window: WindowOption, quota: QuotaViewOption, scanner: CodexTokenScanner, claudeScanner: ClaudeTokenScanner) -> TokenReport {
    switch quota {
    case .claude:
        return claudeScanner.scan(window: window)
    case .all:
        return mergedTokenReports([scanner.scan(window: window), claudeScanner.scan(window: window)], scannedAt: Date())
    case .codex:
        return scanner.scan(window: window)
    default:
        return scanner.scan(window: window, includedModelName: quota.includedModelName, excludedModelName: quota.excludedModelName)
    }
}

func cliReport(hours: Int, quota: QuotaViewOption?, scanner: CodexTokenScanner, claudeScanner: ClaudeTokenScanner) -> TokenReport {
    guard let quota else {
        return mergedTokenReports([scanner.scan(hours: hours), claudeScanner.scan(hours: hours)], scannedAt: Date())
    }
    switch quota {
    case .claude:
        return claudeScanner.scan(hours: hours)
    case .all:
        return mergedTokenReports([scanner.scan(hours: hours), claudeScanner.scan(hours: hours)], scannedAt: Date())
    case .codex:
        return scanner.scan(hours: hours)
    default:
        return scanner.scan(hours: hours, includedModelName: quota.includedModelName, excludedModelName: quota.excludedModelName)
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
    let codexReport = quota == .all ? scanner.scan(window: window) : (quota == .codex ? scanner.scan(window: window) : nil)
    let claudeReport = quota == .all ? claudeScanner.scan(window: window) : (quota == .claude ? claudeScanner.scan(window: window) : nil)
    let report: TokenReport
    if quota == .all, let codexReport, let claudeReport {
        report = mergedTokenReports([codexReport, claudeReport], scannedAt: Date())
    } else if let codexReport {
        report = codexReport
    } else if let claudeReport {
        report = claudeReport
    } else {
        report = cliReport(window: window, quota: quota, scanner: scanner, claudeScanner: claudeScanner)
    }
    let liveLimits = LiveRateLimitReader().read()
    let serviceStatus = CodexServiceStatusReader().read()
    let accountUsage = AppSettings.profileAPITotalsEnabled ? AccountUsageReader().read() : nil
    let profileReport: TokenReport?
    if quota == .all, let accountUsage, accountUsage.hasData {
        profileReport = profileReportWithLocalFallback(accountUsage.report(window: window), localReport: report)
    } else {
        profileReport = nil
    }

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

    let view = DashboardView(frame: NSRect(origin: .zero, size: DashboardView.preferredSize(for: quota)))
    view.update(state)
    view.layoutSubtreeIfNeeded()
    try writePNG(of: view, to: outputURL)
    return outputURL
}

func renderDetailsSnapshot(arguments: [String]) throws -> URL {
    let scanner = CodexTokenScanner(rootURLs: AppSettings.logFolderURLs)
    let section = requestedDetailsSection(from: arguments)
    let isInsightsSection = section == .insights
    let accountUsage = !isInsightsSection && AppSettings.profileAPITotalsEnabled ? AccountUsageReader().read() : nil
    let allLocal = isInsightsSection ? TokenReport(scannedAt: Date()) : scanner.scan(window: .week)
    let all: TokenReport
    if let accountUsage, accountUsage.hasData {
        all = profileReportWithLocalFallback(accountUsage.report(window: .week), localReport: allLocal)
    } else {
        all = allLocal
    }
    let repoInsightReports = scanner.scanRepoInsights(windows: [7, 30, 90])
    let repoInsights = repoInsightReports[90] ?? scanner.scanRepoInsights(days: 90)
    let snapshot = DetailsSnapshot(
        all: all,
        spark: isInsightsSection ? TokenReport(scannedAt: Date()) : scanner.scan(window: .week, includedModelName: "codex-spark"),
        other: isInsightsSection ? TokenReport(scannedAt: Date()) : scanner.scan(window: .week, excludedModelName: "codex-spark"),
        repoInsights: repoInsights,
        repoInsightReports: repoInsightReports,
        liveLimits: isInsightsSection ? [] : LiveRateLimitReader().read(),
        serviceStatus: isInsightsSection ? nil : CodexServiceStatusReader().read(),
        costReferenceReport: allLocal,
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
    view.showSection(section, insightWindowDays: windowDays)
    view.snapshot = snapshot
    view.isLoading = false
    view.layoutSubtreeIfNeeded()
    try writePNG(of: view, to: outputURL)
    return outputURL
}
