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
        return QuotaViewOption(rawValue: String(argument.dropFirst("--quota=".count)))
    }.first
}

func requestedLanguage(from arguments: [String]) -> AppLanguage? {
    arguments.compactMap { argument -> AppLanguage? in
        guard argument.hasPrefix("--language=") else { return nil }
        let raw = String(argument.dropFirst("--language=".count))
        switch raw {
        case "en", "english": return .english
        case "zh", "zh-CN", "zh-Hans", "chinese": return .chinese
        default: return AppLanguage(rawValue: raw)
        }
    }.first
}

func requestedDetailsSection(from arguments: [String]) -> DetailsSection {
    arguments.compactMap { argument -> DetailsSection? in
        guard argument.hasPrefix("--details-section=") else { return nil }
        switch argument.dropFirst("--details-section=".count) {
        case "overview": return .overview
        case "calendar": return .calendar
        case "costs", "cost": return .costs
        case "models", "model": return .models
        case "settings": return .settings
        case "diagnostics", "diagnostic": return .diagnostics
        case "about": return .about
        default: return nil
        }
    }.first ?? .overview
}

func requestedHours(from arguments: [String], defaultValue: Int = WindowOption.week.rawValue) -> Int {
    arguments.compactMap { argument -> Int? in
        guard argument.hasPrefix("--hours=") else { return nil }
        return Int(argument.dropFirst("--hours=".count))
    }.first ?? defaultValue
}

func requestedRenderScale(from arguments: [String], defaultValue: CGFloat = 2) -> CGFloat {
    let value = arguments.compactMap { argument -> Double? in
        guard argument.hasPrefix("--render-scale=") else { return nil }
        return Double(argument.dropFirst("--render-scale=".count))
    }.first ?? Double(defaultValue)
    return CGFloat(min(4, max(1, value)))
}

func withTemporaryRenderLanguage<T>(arguments: [String], _ work: () throws -> T) rethrows -> T {
    let previous = AppLanguage.runtimeOverride
    if let language = requestedLanguage(from: arguments) {
        AppLanguage.runtimeOverride = language
    }
    defer {
        AppLanguage.runtimeOverride = previous
    }
    return try work()
}

func writePNG(of view: NSView, to url: URL, scale: CGFloat = 2) throws {
    let pixelWidth = max(1, Int(ceil(view.bounds.width * scale)))
    let pixelHeight = max(1, Int(ceil(view.bounds.height * scale)))
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelWidth,
        pixelsHigh: pixelHeight,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "CodexTokenMeter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create bitmap"])
    }
    bitmap.size = view.bounds.size
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "CodexTokenMeter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create graphics context"])
    }
    view.displayIgnoringOpacity(view.bounds, in: context)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "CodexTokenMeter", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
    }
    try data.write(to: url, options: [.atomic])
}

func renderDashboardSnapshot(arguments: [String]) throws -> URL {
    try withTemporaryRenderLanguage(arguments: arguments) {
        try renderDashboardSnapshotWithCurrentLanguage(arguments: arguments)
    }
}

private func renderDashboardSnapshotWithCurrentLanguage(arguments: [String]) throws -> URL {
    let scanner = CodexTokenScanner(rootURLs: AppSettings.logFolderURLs)
    let window = requestedWindow(from: arguments) ?? .week
    let quota = requestedQuota(from: arguments) ?? .other
    let report = scanner.scan(window: window, includedModelName: quota.includedModelName, excludedModelName: quota.excludedModelName)
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
    view.layoutSubtreeIfNeeded()
    try writePNG(of: view, to: outputURL, scale: requestedRenderScale(from: arguments))
    return outputURL
}

func renderDetailsSnapshot(arguments: [String]) throws -> URL {
    try withTemporaryRenderLanguage(arguments: arguments) {
        try renderDetailsSnapshotWithCurrentLanguage(arguments: arguments)
    }
}

private func renderDetailsSnapshotWithCurrentLanguage(arguments: [String]) throws -> URL {
    let outputURL = arguments
        .compactMap { argument -> URL? in
            guard argument.hasPrefix("--render-details=") else { return nil }
            return URL(fileURLWithPath: String(argument.dropFirst("--render-details=".count)))
        }
        .first ?? URL(fileURLWithPath: "/tmp/codex-token-meter-details.png")
    let section = requestedDetailsSection(from: arguments)
    let width: CGFloat = 1012
    let height: CGFloat = 800

    let liveLimits = LiveRateLimitReader().read()
    AppSettings.learnModelLimit(from: liveLimits)
    let scanner = CodexTokenScanner(rootURLs: AppSettings.logFolderURLs)
    let all = scanner.scan(days: 365)
    let spark = scanner.scan(days: 365, includedModelName: QuotaViewOption.spark.includedModelName)
    let other = scanner.scan(days: 365, excludedModelName: QuotaViewOption.other.excludedModelName)
    let accountUsage = AppSettings.profileAPITotalsEnabled ? AccountUsageReader().read() : nil
    let costReferenceReport: TokenReport?
    if AppSettings.profileAPITotalsEnabled, let accountUsage, accountUsage.hasData {
        costReferenceReport = profileReportWithLocalFallback(accountUsage.report(days: 365), localReport: all)
    } else {
        costReferenceReport = all
    }
    let snapshot = DetailsSnapshot(
        all: all,
        spark: spark,
        other: other,
        liveLimits: liveLimits,
        serviceStatus: CodexServiceStatusReader().read(),
        costReferenceReport: costReferenceReport,
        accountUsage: accountUsage
    )

    let view = UsageDetailsView(frame: NSRect(x: 0, y: 0, width: width, height: height))
    view.showSection(section)
    view.snapshot = snapshot
    view.isLoading = false
    view.layoutSubtreeIfNeeded()
    try writePNG(of: view, to: outputURL, scale: requestedRenderScale(from: arguments))
    return outputURL
}
