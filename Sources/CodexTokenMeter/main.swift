import Cocoa
import Foundation
import ServiceManagement
import UserNotifications

// MARK: - Command Line Entrypoints

if CommandLine.arguments.contains("--print-profile") {
    let snapshot = AccountUsageReader().read()
    let payload: [String: Any] = [
        "profile_api_totals_enabled": AppSettings.profileAPITotalsEnabled,
        "present": snapshot != nil,
        "has_data": snapshot?.hasData ?? false,
        "lifetime_tokens": snapshot?.summary.lifetimeTokens ?? 0,
        "peak_daily_tokens": snapshot?.summary.peakDailyTokens ?? 0,
        "longest_running_turn_sec": snapshot?.summary.longestRunningTurnSec ?? 0,
        "current_streak_days": snapshot?.summary.currentStreakDays ?? 0,
        "longest_streak_days": snapshot?.summary.longestStreakDays ?? 0,
        "daily_bucket_count": snapshot?.dailyUsageBuckets.count ?? 0,
        "profile_day_total": snapshot?.report(window: .day).usage.total ?? 0,
        "profile_week_total": snapshot?.report(window: .week).usage.total ?? 0,
        "profile_month_total": snapshot?.report(window: .month).usage.total ?? 0,
        "last_daily_bucket": snapshot?.dailyUsageBuckets.last.map { ["start_date": $0.startDate, "tokens": $0.tokens] } ?? [:]
    ]
    if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
       let text = String(data: data, encoding: .utf8) {
        print(text)
    }
    exit(0)
}

if CommandLine.arguments.contains("--print-live") {
    let limits = LiveRateLimitReader().read()
    AppSettings.learnModelLimit(from: limits)
    CostHistoryStore.shared.record(limits: limits)
    let payload = limits.map { limit in
        [
            "id": limit.id,
            "name": limit.name,
            "primary_percent": limit.primary.usedPercent,
            "primary_remaining_percent": limit.primary.remainingPercent,
            "weekly_percent": limit.secondary.usedPercent,
            "weekly_remaining_percent": limit.secondary.remainingPercent,
            "primary_resets_at": limit.primary.resetsAt?.description ?? "",
            "weekly_resets_at": limit.secondary.resetsAt?.description ?? ""
        ] as [String: Any]
    }
    if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
       let text = String(data: data, encoding: .utf8) {
        print(text)
    }
    exit(0)
}

if CommandLine.arguments.contains("--print-service-status") {
    let snapshot = CodexServiceStatusReader().read()
    let payload: [String: Any] = [
        "present": snapshot != nil,
        "updated_at": snapshot?.statusPageUpdatedAt?.description ?? "",
        "read_at": snapshot?.readAt.description ?? "",
        "overall_status": snapshot?.overallStatus ?? "",
        "degraded_component_count": snapshot?.degradedComponents.count ?? 0,
        "component_count": snapshot?.components.count ?? 0,
        "components": snapshot?.components.map { ["name": $0.name, "status": $0.status] } ?? [],
        "active_incident": snapshot?.activeIncident.map { incident in
            [
                "name": incident.name,
                "status": incident.status,
                "message": incident.message,
                "created_at": incident.createdAt?.description ?? "",
                "updated_at": incident.updatedAt?.description ?? ""
            ] as [String: Any]
        } ?? [:]
    ]
    if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
       let text = String(data: data, encoding: .utf8) {
        print(text)
    }
    exit(0)
}

if CommandLine.arguments.contains("--print") {
    let scanner = CodexTokenScanner(rootURLs: AppSettings.logFolderURLs)
    let requestedWindow = requestedWindow(from: CommandLine.arguments)
    let hours = requestedHours(from: CommandLine.arguments)
    let quota = requestedQuota(from: CommandLine.arguments)
    let report = requestedWindow.map { scanner.scan(window: $0, includedModelName: quota?.includedModelName, excludedModelName: quota?.excludedModelName) }
        ?? scanner.scan(hours: hours, includedModelName: quota?.includedModelName, excludedModelName: quota?.excludedModelName)
    let apiEstimate = APICostEstimator.estimate(report: report)
    let externalAPI = ExternalAPICostStore.read()
    let externalAPIPayload: [String: Any] = [
        "configured_path": AppSettings.externalAPICostURL.path,
        "present": externalAPI != nil,
        "has_data": externalAPI?.hasData ?? false,
        "usd_value": externalAPI?.usdValue ?? 0,
        "total_tokens": externalAPI?.totalTokens ?? 0,
        "updated_at": externalAPI?.updatedAt ?? ""
    ]
    let payload: [String: Any] = [
        "hours": requestedWindow?.rawValue ?? hours,
        "window": requestedWindow?.shortTitle ?? "rolling",
        "quota": quota?.rawValue ?? "all",
        "model_limit_id": AppSettings.modelLimitID,
        "model_limit_name": AppSettings.modelLimitName,
        "log_roots": scanner.rootPaths,
        "sessions": report.sessions,
        "events": report.events,
        "turns": report.turns,
        "input": report.usage.input,
        "cached_input": report.usage.cachedInput,
        "fresh_input": report.usage.freshInput,
        "output": report.usage.output,
        "reasoning_output": report.usage.reasoningOutput,
        "total": report.usage.total,
        "cache_percent": report.usage.cachePercent,
        "api_equivalent_usd": apiEstimate.usdValue,
        "api_equivalent_priced_tokens": apiEstimate.pricedTokens,
        "api_equivalent_total_tokens": apiEstimate.totalTokens,
        "api_equivalent_coverage_percent": apiEstimate.coveragePercent,
        "external_api_cost": externalAPIPayload,
        "hour_buckets": report.byHour.count,
        "model_breakdown": report.modelBreakdown.map { model in
            let modelAPIEstimate = APICostEstimator.estimate(usage: model.usage, modelName: model.name)
            return [
                "name": model.name,
                "sessions": model.sessions,
                "events": model.events,
                "total": model.usage.total,
                "input": model.usage.input,
                "output": model.usage.output,
                "api_equivalent_usd": modelAPIEstimate.usdValue,
                "api_equivalent_priced_tokens": modelAPIEstimate.pricedTokens
            ] as [String: Any]
        },
        "by_day": report.byDay.map { day in
            let dayAPIEstimate = APICostEstimator.estimate(day: day)
            return [
                "day": day.day,
                "turns": day.turns,
                "input": day.usage.input,
                "cached_input": day.usage.cachedInput,
                "fresh_input": day.usage.freshInput,
                "output": day.usage.output,
                "reasoning_output": day.usage.reasoningOutput,
                "total": day.usage.total,
                "api_equivalent_usd": dayAPIEstimate.usdValue,
                "api_equivalent_coverage_percent": dayAPIEstimate.coveragePercent,
                "model_breakdown": day.modelBreakdown.map { model in
                    let modelAPIEstimate = APICostEstimator.estimate(usage: model.usage, modelName: model.name)
                    return [
                        "name": model.name,
                        "sessions": model.sessions,
                        "events": model.events,
                        "total": model.usage.total,
                        "input": model.usage.input,
                        "output": model.usage.output,
                        "api_equivalent_usd": modelAPIEstimate.usdValue
                    ] as [String: Any]
                }
            ] as [String: Any]
        }
    ]
    if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
       let text = String(data: data, encoding: .utf8) {
        print(text)
    }
    exit(0)
}

if CommandLine.arguments.contains("--render-dashboard") || CommandLine.arguments.contains(where: { $0.hasPrefix("--render-dashboard=") }) {
    do {
        let url = try renderDashboardSnapshot(arguments: CommandLine.arguments)
        print(url.path)
    } catch {
        fputs("Failed to render dashboard: \(error)\n", stderr)
        exit(1)
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
