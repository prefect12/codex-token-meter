import Foundation

/// Public, synthetic data used only by CLI screenshot rendering. None of these
/// values are derived from local logs, account APIs, preferences, or folders.
enum DemoSnapshotFactory {
    private struct DemoModel {
        let name: String
        let weight: Int64
    }

    private static let calendar = appCalendar()

    private static var anchor: Date {
        calendar.startOfDay(for: Date())
    }

    private static let codexModels = [
        DemoModel(name: "gpt-5.6-luna", weight: 34),
        DemoModel(name: "gpt-6-astra", weight: 28),
        DemoModel(name: "gpt-5.6-sol", weight: 22),
    ]

    private static let claudeModels = [
        DemoModel(name: "claude-sonnet-4-5", weight: 18),
        DemoModel(name: "claude-opus-4-1", weight: 12),
    ]

    private static let apiModels = [
        DemoModel(name: "gpt-5.6-terra", weight: 9),
        DemoModel(name: "gemini-2.5-pro", weight: 7),
    ]

    static func dashboardState(window: WindowOption, quota: QuotaViewOption) -> DashboardState {
        let days: Int
        switch window {
        case .day: days = 1
        case .week: days = 7
        case .month: days = 30
        }
        let codex = report(models: codexModels, days: days, hours: window == .day ? 24 : 0, scale: 1_000)
        let claude = report(models: claudeModels, days: days, hours: window == .day ? 24 : 0, scale: 820)
        let api = report(models: apiModels, days: days, hours: window == .day ? 24 : 0, scale: 430)
        let all = mergedTokenReport([codex, claude, api])
        let selected: TokenReport
        switch quota {
        case .all: selected = all
        case .codex: selected = codex
        case .claude: selected = claude
        case .api: selected = api
        }
        return DashboardState(
            report: selected,
            codexReport: codex,
            claudeReport: claude,
            apiReport: api,
            profileReport: nil,
            accountUsage: accountUsage(),
            costReferenceReport: all,
            liveLimits: liveLimits(),
            resetCredits: resetCredits(),
            serviceStatus: serviceStatus(),
            claudeServiceStatus: serviceStatus(),
            selectedWindow: window,
            selectedQuota: quota,
            nextRefreshAt: Date().addingTimeInterval(300),
            isLoading: false,
            error: nil
        )
    }

    static func detailsSnapshot(source: QuotaViewOption) -> DetailsSnapshot {
        let codex = report(models: codexModels, days: 90, hours: 0, scale: 1_000)
        let claude = report(models: claudeModels, days: 90, hours: 0, scale: 820)
        let api = report(models: apiModels, days: 90, hours: 0, scale: 430)
        let all = mergedTokenReport([codex, claude, api])
        let recentCodex = report(models: codexModels, days: 2, hours: 48, scale: 1_000)
        let recentClaude = report(models: claudeModels, days: 2, hours: 48, scale: 820)
        let recentAPI = report(models: apiModels, days: 2, hours: 48, scale: 430)
        let recentAll = mergedTokenReport([recentCodex, recentClaude, recentAPI])
        let reasoning = reasoningReport()
        let repoReports = Dictionary(uniqueKeysWithValues: [7, 30, 90].map { days in
            (days, RepoInsightsReport(rows: [], scannedAt: Date(), windowDays: days, reasoning: reasoning))
        })
        let emptyRepoReports = Dictionary(uniqueKeysWithValues: [7, 30, 90].map { days in
            (days, RepoInsightsReport(rows: [], scannedAt: Date(), windowDays: days))
        })
        let repo = repoReports[90]!
        let emptyRepo = emptyRepoReports[90]!
        let costReference: TokenReport
        switch source {
        case .codex: costReference = codex
        case .claude: costReference = claude
        case .api: costReference = api
        case .all: costReference = all
        }
        return DetailsSnapshot(
            all: all,
            codex: codex,
            claude: claude,
            api: api,
            recentAll: recentAll,
            recentCodex: recentCodex,
            recentClaude: recentClaude,
            recentAPI: recentAPI,
            modelAll: all,
            modelCodex: codex,
            modelClaude: claude,
            modelAPI: api,
            repoInsights: repo,
            repoInsightReports: repoReports,
            codexRepoInsights: repo,
            codexRepoInsightReports: repoReports,
            claudeRepoInsights: emptyRepo,
            claudeRepoInsightReports: emptyRepoReports,
            apiRepoInsights: emptyRepo,
            apiRepoInsightReports: emptyRepoReports,
            liveLimits: liveLimits(),
            serviceStatus: serviceStatus(),
            costReferenceReport: costReference,
            accountUsage: accountUsage(),
            resetCredits: resetCredits()
        )
    }

    static func storageSnapshot() -> StorageSnapshot {
        let categories: [StorageCategoryUsage] = [
            StorageCategoryUsage(id: .codexSessions, bytes: 1_280_000_000, fileCount: 1_248, newestModified: Date(), roots: ["~/demo/.codex/sessions"]),
            StorageCategoryUsage(id: .codexWorktrees, bytes: 2_460_000_000, fileCount: 8_420, newestModified: Date(), roots: ["~/demo/.codex/worktrees"]),
            StorageCategoryUsage(id: .codexImages, bytes: 684_000_000, fileCount: 312, newestModified: Date(), roots: ["~/demo/.codex/images"]),
            StorageCategoryUsage(id: .claudeProjects, bytes: 936_000_000, fileCount: 2_104, newestModified: Date(), roots: ["~/demo/.claude/projects"]),
            StorageCategoryUsage(id: .claudeOther, bytes: 188_000_000, fileCount: 486, newestModified: Date(), roots: ["~/demo/.claude"]),
        ]
        let formatter = dayFormatter()
        var growth: [String: [String: Int64]] = [:]
        var growthFiles: [String: [String: Int]] = [:]
        var days: [String] = []
        for offset in stride(from: 13, through: 0, by: -1) {
            let date = calendar.date(byAdding: .day, value: -offset, to: anchor) ?? anchor
            let day = formatter.string(from: date)
            days.append(day)
            growth[day] = [
                StorageCategoryID.codexSessions.rawValue: Int64(22 + offset % 5) * 1_000_000,
                StorageCategoryID.claudeProjects.rawValue: Int64(10 + offset % 4) * 1_000_000,
            ]
            growthFiles[day] = [
                StorageCategoryID.codexSessions.rawValue: 14 + offset % 7,
                StorageCategoryID.claudeProjects.rawValue: 8 + offset % 5,
            ]
        }
        return StorageSnapshot(
            scannedAt: Date(),
            categories: categories,
            dailyGrowth: growth,
            dailyGrowthFiles: growthFiles,
            growthDays: days,
            projects: [
                StorageProjectUsage(name: "orion-app", path: "~/demo/orion-app", platform: .codex, bytes: 890_000_000, fileCount: 1_240, newestModified: Date()),
                StorageProjectUsage(name: "atlas-api", path: "~/demo/atlas-api", platform: .codex, bytes: 610_000_000, fileCount: 864, newestModified: Date()),
                StorageProjectUsage(name: "nova-web", path: "~/demo/nova-web", platform: .claude, bytes: 420_000_000, fileCount: 536, newestModified: Date()),
            ]
        )
    }

    static func modelRoutingSnapshot() -> CodexModelRoutingSnapshot {
        let models = [
            CodexModelOption(slug: "gpt-6-astra", displayName: "GPT-6 Astra", description: "Complex, demanding work", defaultReasoningEffort: "high", supportedReasoningEfforts: ["low", "medium", "high", "xhigh"]),
            CodexModelOption(slug: "gpt-6-sol", displayName: "GPT-6 Sol", description: "Strong reasoning for demanding tasks", defaultReasoningEffort: "medium", supportedReasoningEfforts: ["low", "medium", "high", "xhigh", "max", "ultra"]),
            CodexModelOption(slug: "gpt-6-luna", displayName: "GPT-6 Luna", description: "Efficient everyday work", defaultReasoningEffort: "medium", supportedReasoningEfforts: ["low", "medium", "high", "xhigh", "max"]),
            CodexModelOption(slug: "gpt-5.6-sol", displayName: "GPT-5.6 Sol", description: "Reliable everyday work", defaultReasoningEffort: "medium", supportedReasoningEfforts: ["low", "medium", "high", "xhigh"]),
            CodexModelOption(slug: "gpt-5.6-luna", displayName: "GPT-5.6 Luna", description: "Fast agentic coding", defaultReasoningEffort: "medium", supportedReasoningEfforts: ["low", "medium", "high"]),
        ]
        let global = CodexConfigSelection(model: "gpt-5.6-sol", reasoningEffort: "high", contextWindow: 258_400, autoCompactTokenLimit: 219_640, planModeReasoningEffort: "high")
        let projects = [
            CodexProjectRoutingSnapshot(
                project: CodexSavedProject(id: "demo-orion", name: "orion-app", rootPaths: ["~/demo/orion-app"]),
                model: .value("gpt-6-astra"), reasoningEffort: .value("xhigh"), contextWindow: .inherited,
                autoCompactTokenLimit: .inherited, planModeReasoningEffort: .value("high")
            ),
            CodexProjectRoutingSnapshot(
                project: CodexSavedProject(id: "demo-atlas", name: "atlas-api", rootPaths: ["~/demo/atlas-api"]),
                model: .inherited, reasoningEffort: .inherited, contextWindow: .inherited,
                autoCompactTokenLimit: .inherited, planModeReasoningEffort: .inherited
            ),
        ]
        return CodexModelRoutingSnapshot(global: global, models: models, projects: projects)
    }

    private static func report(models: [DemoModel], days: Int, hours: Int, scale: Int64) -> TokenReport {
        let formatter = dayFormatter()
        var report = TokenReport(scannedAt: Date())
        var modelTotals: [String: ModelUsage] = [:]
        for offset in stride(from: max(days - 1, 0), through: 0, by: -1) {
            let date = calendar.date(byAdding: .day, value: -offset, to: anchor) ?? anchor
            let activity = Int64(3 + ((offset * 7 + 5) % 9))
            let dayModels = models.enumerated().map { index, model in
                modelUsage(model: model, activity: activity + Int64(index), scale: scale)
            }
            let usage = summedUsage(dayModels.map(\.usage))
            report.byDay.append(DayUsage(day: formatter.string(from: date), usage: usage, turns: Int(activity) + 4, sessions: 1 + Int(activity % 4), events: Int(activity) + 7, modelBreakdown: dayModels))
            report.usage.add(usage)
            report.turns += Int(activity) + 4
            report.sessions += 1 + Int(activity % 4)
            report.events += Int(activity) + 7
            merge(dayModels, into: &modelTotals)
        }
        if hours > 0 {
            let end = calendar.date(byAdding: .hour, value: 12, to: anchor) ?? anchor
            for offset in stride(from: hours - 1, through: 0, by: -1) {
                let hour = calendar.date(byAdding: .hour, value: -offset, to: end) ?? end
                let activity = Int64((offset * 5 + 3) % 10)
                let hourModels = activity == 0 ? [] : models.enumerated().map { index, model in
                    modelUsage(model: model, activity: activity + Int64(index), scale: max(80, scale / 10))
                }
                report.byHour.append(HourUsage(hour: hour, usage: summedUsage(hourModels.map(\.usage)), turns: Int(activity), modelBreakdown: hourModels))
            }
        }
        report.modelBreakdown = modelTotals.values.sorted { $0.usage.total > $1.usage.total }
        report.topSessions = [
            SessionUsage(path: "~/demo/orion-app/session-a.jsonl", lastEvent: Date(), turns: 18, usage: Usage(total: 8_400_000)),
            SessionUsage(path: "~/demo/atlas-api/session-b.jsonl", lastEvent: Date().addingTimeInterval(-3600), turns: 12, usage: Usage(total: 5_900_000)),
        ]
        return report
    }

    private static func modelUsage(model: DemoModel, activity: Int64, scale: Int64) -> ModelUsage {
        let total = max(1, model.weight * activity * scale)
        let input = total * 82 / 100
        let cached = input * 58 / 100
        let output = total - input
        return ModelUsage(
            name: model.name,
            usage: Usage(input: input, cachedInput: cached, output: output, reasoningOutput: output / 3, total: total),
            turns: Int(activity), events: Int(activity) + 2, sessions: 1 + Int(activity % 3)
        )
    }

    private static func summedUsage(_ usages: [Usage]) -> Usage {
        usages.reduce(into: Usage()) { $0.add($1) }
    }

    private static func merge(_ models: [ModelUsage], into totals: inout [String: ModelUsage]) {
        for model in models {
            var value = totals[model.name] ?? ModelUsage(name: model.name, usage: Usage(), events: 0, sessions: 0)
            value.usage.add(model.usage)
            value.turns += model.turns
            value.events += model.events
            value.sessions += model.sessions
            totals[model.name] = value
        }
    }

    private static func reasoningReport() -> ReasoningInsightsReport {
        let efforts = [
            ("low", 18, 2_800_000 as Int64),
            ("medium", 42, 8_600_000 as Int64),
            ("high", 31, 12_400_000 as Int64),
            ("xhigh", 14, 9_100_000 as Int64),
        ]
        let summaries = efforts.map { effort, runs, total in
            ReasoningEffortSummary(effort: effort, runs: runs, tasks: max(1, runs - 5), usage: Usage(input: total * 8 / 10, cachedInput: total * 4 / 10, output: total * 2 / 10, reasoningOutput: total / 12, total: total), medianTokens: total / Int64(runs), p90Tokens: total / Int64(max(1, runs / 2)))
        }
        let modelEfforts = [
            ReasoningModelEffortSummary(model: "gpt-6-astra", effort: "high", runs: 24, tasks: 19, projectCount: 3, usage: Usage(total: 9_800_000), medianTokens: 408_000, p90Tokens: 760_000),
            ReasoningModelEffortSummary(model: "gpt-5.6-sol", effort: "medium", runs: 36, tasks: 28, projectCount: 4, usage: Usage(total: 8_200_000), medianTokens: 228_000, p90Tokens: 510_000),
            ReasoningModelEffortSummary(model: "gpt-5.6-luna", effort: "low", runs: 18, tasks: 15, projectCount: 2, usage: Usage(total: 3_600_000), medianTokens: 200_000, p90Tokens: 340_000),
        ]
        var daily: [ReasoningDailyModelEffortSummary] = []
        let formatter = dayFormatter()
        for offset in stride(from: 13, through: 0, by: -1) {
            let date = calendar.date(byAdding: .day, value: -offset, to: anchor) ?? anchor
            let day = formatter.string(from: date)
            daily.append(ReasoningDailyModelEffortSummary(day: day, model: "gpt-6-astra", effort: "high", runs: 2 + offset % 3, usage: Usage(total: Int64(720_000 + offset * 42_000)), runTokenTotals: [320_000, 440_000]))
            daily.append(ReasoningDailyModelEffortSummary(day: day, model: "gpt-5.6-sol", effort: "medium", runs: 3 + offset % 4, usage: Usage(total: Int64(560_000 + offset * 31_000)), runTokenTotals: [180_000, 240_000, 310_000]))
        }
        let total = summedUsage(summaries.map(\.usage))
        return ReasoningInsightsReport(taskCount: 78, runCount: 105, usage: total, knownRunCount: 101, knownTokenCount: total.total * 96 / 100, efforts: summaries, modelEfforts: modelEfforts, dailyModelEfforts: daily)
    }

    private static func liveLimits() -> [LiveRateLimit] {
        let now = Date()
        return [
            LiveRateLimit(id: "codex", name: "Codex", primary: RateWindow(usedPercent: 37, windowMinutes: 300, resetsAt: now.addingTimeInterval(2.2 * 3600)), secondary: RateWindow(usedPercent: 54, windowMinutes: 10_080, resetsAt: now.addingTimeInterval(4.5 * 86_400)), planType: "Plus", capturedAt: now),
            LiveRateLimit(id: "claude", name: "Claude", primary: RateWindow(usedPercent: 24, windowMinutes: 300, resetsAt: now.addingTimeInterval(3.1 * 3600)), secondary: RateWindow(usedPercent: 43, windowMinutes: 10_080, resetsAt: now.addingTimeInterval(5.2 * 86_400)), planType: "Pro", capturedAt: now),
        ]
    }

    private static func accountUsage() -> AccountUsageSnapshot {
        let formatter = dayFormatter()
        let buckets = (0..<30).map { offset -> AccountUsageDailyBucket in
            let date = calendar.date(byAdding: .day, value: -(29 - offset), to: anchor) ?? anchor
            return AccountUsageDailyBucket(startDate: formatter.string(from: date), tokens: Int64(8_000_000 + ((offset * 13) % 17) * 620_000))
        }
        return AccountUsageSnapshot(summary: AccountUsageSummary(lifetimeTokens: 486_000_000, peakDailyTokens: 22_800_000, longestRunningTurnSec: 740, currentStreakDays: 9, longestStreakDays: 21), dailyUsageBuckets: buckets, readAt: Date())
    }

    private static func resetCredits() -> RateLimitResetCreditsSnapshot {
        let credit = RateLimitResetCredit(status: "available", grantedAt: Date().addingTimeInterval(-3 * 86_400), expiresAt: Date().addingTimeInterval(18 * 86_400), expirationIsEstimated: false)
        return RateLimitResetCreditsSnapshot(availableCount: 1, totalEarnedCount: 2, credits: [credit], readAt: Date(), source: "demo")
    }

    private static func serviceStatus() -> CodexServiceStatusSnapshot {
        CodexServiceStatusSnapshot(statusPageUpdatedAt: Date(), readAt: Date(), components: [CodexServiceComponentStatus(name: "Codex", status: "operational")], incidents: [])
    }

    private static func dayFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = appTimeZone()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
