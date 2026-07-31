import Cocoa
import Foundation
import ServiceManagement
import UserNotifications

// MARK: - Scanner And Runtime Readers

struct ReportCacheKey: Hashable {
    let window: WindowOption
    let quota: QuotaViewOption
}

final class CodexTokenScanner {
    private struct FileModelAggregate: Codable {
        let name: String
        var usage: Usage
        var events: Int
    }

    private struct FileDayAggregate: Codable {
        let day: String
        var usage: Usage
        var turns: Int
        var models: [FileModelAggregate]
    }

    private struct FileRepoInsightDayAggregate: Codable {
        let day: String
        var turns: Int
        var compressions: Int
        var tokens: Int64
        var abortedTurns: Int
        var completedTurns: Int
    }

    private struct FileRepoInsightHourAggregate: Codable {
        let day: String
        let hour: Int
        var turns: Int
        var tokens: Int64
    }

    private struct FileReasoningRunAggregate: Codable {
        var timestamp: Date
        var day: String
        var model: String
        var effort: String
        var usage: Usage
    }

    private struct FileRepoInsightAggregate: Codable {
        var cwd: String?
        var days: [FileRepoInsightDayAggregate]
        var hours: [FileRepoInsightHourAggregate]
        var reasoningRuns: [FileReasoningRunAggregate]
    }

    private struct FileCache {
        let size: Int64
        let modifiedAt: Date
        let events: [TokenEvent]
        let turns: [Date]
        let days: [FileDayAggregate]
        let repoInsight: FileRepoInsightAggregate
    }

    private struct RepoInsightConversation {
        var cwd: String?
        var turns = 0
        var compressions = 0
        var tokens: Int64 = 0
        var abortedTurns = 0
        var completedTurns = 0
        var activeDays: Set<String> = []
        var days: [FileRepoInsightDayAggregate] = []
        var hours: [FileRepoInsightHourAggregate] = []
        var reasoningRuns: [FileReasoningRunAggregate] = []
        var lastEvent: Date?
    }

    private struct ReasoningEffortAccumulator {
        var runs = 0
        var tasks = 0
        var projects = Set<String>()
        var usage = Usage()
        var runTokenTotals: [Int64] = []
    }

    private struct ReasoningInsightsAccumulator {
        var taskCount = 0
        var runCount = 0
        var usage = Usage()
        var efforts: [String: ReasoningEffortAccumulator] = [:]
        var modelEfforts: [String: ReasoningEffortAccumulator] = [:]
        var dailyModelEfforts: [String: ReasoningEffortAccumulator] = [:]

        mutating func add(_ conversation: RepoInsightConversation, projectKey: String) {
            taskCount += 1
            var taskEfforts = Set<String>()
            var taskModelEfforts = Set<String>()

            for run in conversation.reasoningRuns {
                let effort = CodexTokenScanner.normalizedReasoningEffort(run.effort)
                let model = CodexTokenScanner.normalizedReasoningModel(run.model)
                var bucket = efforts[effort] ?? ReasoningEffortAccumulator()
                bucket.runs += 1
                bucket.usage.add(run.usage)
                bucket.runTokenTotals.append(run.usage.total)
                efforts[effort] = bucket
                taskEfforts.insert(effort)

                let modelEffortKey = Self.key(model, effort)
                var modelBucket = modelEfforts[modelEffortKey] ?? ReasoningEffortAccumulator()
                modelBucket.runs += 1
                modelBucket.usage.add(run.usage)
                modelBucket.runTokenTotals.append(run.usage.total)
                if !projectKey.isEmpty { modelBucket.projects.insert(projectKey) }
                modelEfforts[modelEffortKey] = modelBucket
                taskModelEfforts.insert(modelEffortKey)

                let dailyKey = Self.key(run.day, model, effort)
                var dailyBucket = dailyModelEfforts[dailyKey] ?? ReasoningEffortAccumulator()
                dailyBucket.runs += 1
                dailyBucket.usage.add(run.usage)
                dailyBucket.runTokenTotals.append(run.usage.total)
                dailyModelEfforts[dailyKey] = dailyBucket
                runCount += 1
                usage.add(run.usage)
            }

            let missingRuns = max(0, conversation.turns - conversation.reasoningRuns.count)
            if missingRuns > 0 {
                var unknown = efforts["unknown"] ?? ReasoningEffortAccumulator()
                unknown.runs += missingRuns
                unknown.runTokenTotals.append(contentsOf: repeatElement(0, count: missingRuns))
                efforts["unknown"] = unknown
                taskEfforts.insert("unknown")
                runCount += missingRuns
            }

            for effort in taskEfforts {
                var bucket = efforts[effort] ?? ReasoningEffortAccumulator()
                bucket.tasks += 1
                efforts[effort] = bucket
            }
            for key in taskModelEfforts {
                var bucket = modelEfforts[key] ?? ReasoningEffortAccumulator()
                bucket.tasks += 1
                modelEfforts[key] = bucket
            }
        }

        func report() -> ReasoningInsightsReport {
            let summaries = efforts.map { effort, bucket in
                let sorted = bucket.runTokenTotals.sorted()
                return ReasoningEffortSummary(
                    effort: effort,
                    runs: bucket.runs,
                    tasks: bucket.tasks,
                    usage: bucket.usage,
                    medianTokens: Self.percentile(sorted, percentile: 0.5),
                    p90Tokens: Self.percentile(sorted, percentile: 0.9)
                )
            }
            .sorted {
                let lhsRank = CodexTokenScanner.reasoningEffortRank($0.effort)
                let rhsRank = CodexTokenScanner.reasoningEffortRank($1.effort)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return $0.effort.localizedCaseInsensitiveCompare($1.effort) == .orderedAscending
            }

            let known = summaries.filter { $0.effort != "unknown" }
            let modelSummaries = modelEfforts.compactMap { key, bucket -> ReasoningModelEffortSummary? in
                let parts = Self.parts(key, count: 2)
                guard parts.count == 2 else { return nil }
                let sorted = bucket.runTokenTotals.sorted()
                return ReasoningModelEffortSummary(
                    model: parts[0],
                    effort: parts[1],
                    runs: bucket.runs,
                    tasks: bucket.tasks,
                    projectCount: bucket.projects.count,
                    usage: bucket.usage,
                    medianTokens: Self.percentile(sorted, percentile: 0.5),
                    p90Tokens: Self.percentile(sorted, percentile: 0.9)
                )
            }
            .sorted {
                if $0.model != $1.model { return $0.model.localizedCaseInsensitiveCompare($1.model) == .orderedAscending }
                return CodexTokenScanner.reasoningEffortRank($0.effort) < CodexTokenScanner.reasoningEffortRank($1.effort)
            }
            let dailySummaries = dailyModelEfforts.compactMap { key, bucket -> ReasoningDailyModelEffortSummary? in
                let parts = Self.parts(key, count: 3)
                guard parts.count == 3 else { return nil }
                return ReasoningDailyModelEffortSummary(
                    day: parts[0],
                    model: parts[1],
                    effort: parts[2],
                    runs: bucket.runs,
                    usage: bucket.usage,
                    runTokenTotals: bucket.runTokenTotals
                )
            }
            .sorted {
                if $0.day != $1.day { return $0.day < $1.day }
                if $0.model != $1.model { return $0.model.localizedCaseInsensitiveCompare($1.model) == .orderedAscending }
                return CodexTokenScanner.reasoningEffortRank($0.effort) < CodexTokenScanner.reasoningEffortRank($1.effort)
            }
            return ReasoningInsightsReport(
                taskCount: taskCount,
                runCount: runCount,
                usage: usage,
                knownRunCount: known.reduce(0) { $0 + $1.runs },
                knownTokenCount: known.reduce(Int64(0)) { $0 + $1.usage.total },
                efforts: summaries,
                modelEfforts: modelSummaries,
                dailyModelEfforts: dailySummaries
            )
        }

        private static let keySeparator = "\u{1F}"

        private static func key(_ parts: String...) -> String {
            parts.joined(separator: keySeparator)
        }

        private static func parts(_ key: String, count: Int) -> [String] {
            let values = key.components(separatedBy: keySeparator)
            return values.count == count ? values : []
        }

        private static func percentile(_ sorted: [Int64], percentile: Double) -> Int64 {
            guard !sorted.isEmpty else { return 0 }
            let bounded = min(1, max(0, percentile))
            let index = Int(ceil(Double(sorted.count) * bounded)) - 1
            return sorted[min(sorted.count - 1, max(0, index))]
        }
    }

    private struct RepoInsightAccumulator {
        let key: String
        let displayName: String
        var primaryFolder: String
        var folders: Set<String> = []
        var conversations = 0
        var turns = 0
        var compressions = 0
        var tokens: Int64 = 0
        var conversationsWithCompression = 0
        var longestTurns = 0
        var longestTokens: Int64 = 0
        var maxCompressions = 0
        var abortedTurns = 0
        var completedTurns = 0
        var activeDays: Set<String> = []
        var turnBuckets = RepoInsightTurnBuckets()
        var compressionBuckets = RepoInsightCompressionBuckets()
        var dayBuckets: [String: RepoInsightDay] = [:]
        var hourBuckets: [Int: RepoInsightHour] = [:]

        mutating func add(_ conversation: RepoInsightConversation) {
            conversations += 1
            turns += conversation.turns
            compressions += conversation.compressions
            tokens += conversation.tokens
            abortedTurns += conversation.abortedTurns
            completedTurns += conversation.completedTurns
            longestTurns = max(longestTurns, conversation.turns)
            longestTokens = max(longestTokens, conversation.tokens)
            maxCompressions = max(maxCompressions, conversation.compressions)
            if conversation.compressions > 0 {
                conversationsWithCompression += 1
            }
            if let cwd = conversation.cwd {
                folders.insert(cwd)
                if primaryFolder == "(unknown)" {
                    primaryFolder = cwd
                }
            }
            activeDays.formUnion(conversation.activeDays)

            switch conversation.turns {
            case ..<10:
                turnBuckets.short += 1
            case 10...40:
                turnBuckets.medium += 1
            case 41...100:
                turnBuckets.long += 1
            default:
                turnBuckets.extraLong += 1
            }

            switch conversation.compressions {
            case 0:
                compressionBuckets.zero += 1
            case 1:
                compressionBuckets.one += 1
            case 2:
                compressionBuckets.two += 1
            default:
                compressionBuckets.threePlus += 1
            }

            let dailyRows = conversation.days.isEmpty
                ? conversation.activeDays.map { FileRepoInsightDayAggregate(day: $0, turns: conversation.turns, compressions: conversation.compressions, tokens: conversation.tokens, abortedTurns: conversation.abortedTurns, completedTurns: conversation.completedTurns) }
                : conversation.days
            for day in dailyRows {
                var bucket = dayBuckets[day.day] ?? RepoInsightDay(day: day.day, conversations: 0, turns: 0, compressions: 0)
                bucket.conversations += 1
                bucket.turns += day.turns
                bucket.compressions += day.compressions
                dayBuckets[day.day] = bucket
            }

            for hour in conversation.hours where hour.turns > 0 || hour.tokens > 0 {
                var bucket = hourBuckets[hour.hour] ?? RepoInsightHour(hour: hour.hour, conversations: 0, turns: 0, tokens: 0)
                bucket.conversations += 1
                bucket.turns += hour.turns
                bucket.tokens += hour.tokens
                hourBuckets[hour.hour] = bucket
            }
        }

        func repoInsight() -> RepoInsight {
            RepoInsight(
                key: key,
                displayName: displayName,
                primaryFolder: primaryFolder,
                folders: folders,
                conversations: conversations,
                turns: turns,
                compressions: compressions,
                tokens: tokens,
                conversationsWithCompression: conversationsWithCompression,
                longestTurns: longestTurns,
                longestTokens: longestTokens,
                maxCompressions: maxCompressions,
                abortedTurns: abortedTurns,
                completedTurns: completedTurns,
                activeDays: activeDays,
                turnBuckets: turnBuckets,
                compressionBuckets: compressionBuckets,
                days: dayBuckets.values.sorted { $0.day < $1.day },
                hours: hourBuckets.values.sorted { $0.hour < $1.hour }
            )
        }
    }

    private struct DiskFileCache: Codable {
        let version: Int
        let path: String
        let size: Int64
        let modifiedAt: Double
        let timeZoneIdentifier: String
        let events: [TokenEvent]
        let turns: [Date]
        let days: [FileDayAggregate]
        let repoInsight: FileRepoInsightAggregate
    }

    private struct LegacyV7FileReasoningRunAggregate: Codable {
        var timestamp: Date
        var effort: String
        var usage: Usage
    }

    private struct LegacyV7FileRepoInsightAggregate: Codable {
        var cwd: String?
        var days: [FileRepoInsightDayAggregate]
        var hours: [FileRepoInsightHourAggregate]
        var reasoningRuns: [LegacyV7FileReasoningRunAggregate]
    }

    private struct LegacyV7DiskFileCache: Codable {
        let version: Int
        let path: String
        let size: Int64
        let modifiedAt: Double
        let timeZoneIdentifier: String
        let events: [TokenEvent]
        let turns: [Date]
        let days: [FileDayAggregate]
        let repoInsight: LegacyV7FileRepoInsightAggregate
    }

    private struct LegacyV6FileRepoInsightAggregate: Codable {
        var cwd: String?
        var days: [FileRepoInsightDayAggregate]
        var hours: [FileRepoInsightHourAggregate]
    }

    private struct LegacyV6DiskFileCache: Codable {
        let version: Int
        let path: String
        let size: Int64
        let modifiedAt: Double
        let timeZoneIdentifier: String
        let events: [TokenEvent]
        let turns: [Date]
        let days: [FileDayAggregate]
        let repoInsight: LegacyV6FileRepoInsightAggregate
    }

    private struct LegacyV4FileRepoInsightAggregate: Codable {
        var cwd: String?
        var days: [FileRepoInsightDayAggregate]
    }

    private struct LegacyV4DiskFileCache: Codable {
        let version: Int
        let path: String
        let size: Int64
        let modifiedAt: Double
        let timeZoneIdentifier: String?
        let events: [TokenEvent]
        let turns: [Date]
        let days: [FileDayAggregate]
        let repoInsight: LegacyV4FileRepoInsightAggregate
    }

    private struct LegacyV3DiskFileCache: Codable {
        let version: Int
        let path: String
        let size: Int64
        let modifiedAt: Double
        let events: [TokenEvent]
        let turns: [Date]
        let days: [FileDayAggregate]
    }

    private struct LegacyDiskFileCache: Codable {
        let version: Int
        let path: String
        let size: Int64
        let modifiedAt: Double
        let events: [TokenEvent]
        let turns: [Date]
    }

    private let rootURLs: [URL]
    private let cacheDirectory: URL
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()
    private let isoFormatter: ISO8601DateFormatter
    private let dayFormatter: DateFormatter
    private let calendar: Calendar
    private let eventMsgPattern = Array(#""type":"event_msg""#.utf8)
    private let subagentSourcePattern = Array(#""source":{"subagent":{"thread_spawn""#.utf8)
    private let interAgentMetadataPattern = Array(#""type":"inter_agent_communication_metadata""#.utf8)
    private let turnContextPattern = Array(#""type":"turn_context""#.utf8)
    private let taskStartedPattern = Array(#""type":"task_started""#.utf8)
    private let contextCompactedPattern = Array(#""type":"context_compacted""#.utf8)
    private let turnAbortedPattern = Array(#""type":"turn_aborted""#.utf8)
    private let taskCompletePattern = Array(#""type":"task_complete""#.utf8)
    private let tokenCountPattern = Array(#""type":"token_count""#.utf8)
    private let rateLimitsPattern = Array(#""rate_limits""#.utf8)
    private let timestampKey = Array(#""timestamp":""#.utf8)
    private let cwdKey = Array(#""cwd":""#.utf8)
    private let inputKey = Array(#""input_tokens":"#.utf8)
    private let cachedInputKey = Array(#""cached_input_tokens":"#.utf8)
    private let outputKey = Array(#""output_tokens":"#.utf8)
    private let reasoningOutputKey = Array(#""reasoning_output_tokens":"#.utf8)
    private let totalKey = Array(#""total_tokens":"#.utf8)
    private let limitIDKey = Array(#""limit_id":""#.utf8)
    private let limitNameKey = Array(#""limit_name":""#.utf8)
    private let modelKey = Array(#""model":""#.utf8)
    private let effortKey = Array(#""effort":""#.utf8)
    private let turnIDKey = Array(#""turn_id":""#.utf8)
    private var cache: [String: FileCache] = [:]

    private static func normalizedReasoningEffort(_ value: String?) -> String {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return normalized.isEmpty ? "unknown" : normalized
    }

    private static func normalizedReasoningModel(_ value: String?) -> String {
        canonicalModelName(value)
    }

    private static func canonicalModelName(_ value: String?) -> String {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalized.isEmpty else { return "Unknown model" }
        // Automatic review turns use an internal model label. Present them in
        // the selected Sol bucket so every report uses one consistent model row.
        if normalized.caseInsensitiveCompare("codex-auto-review") == .orderedSame {
            return "gpt-5.6-sol"
        }
        return normalized
    }

    static func reasoningEffortRank(_ effort: String) -> Int {
        switch normalizedReasoningEffort(effort) {
        case "low": return 0
        case "medium": return 1
        case "high": return 2
        case "xhigh": return 3
        case "ultra": return 4
        case "max": return 5
        case "unknown": return 100
        default: return 50
        }
    }

    convenience init(rootURL: URL) {
        self.init(rootURLs: [rootURL])
    }

    init(rootURLs: [URL]) {
        self.rootURLs = Self.uniqueRootURLs(rootURLs)
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        self.cacheDirectory = applicationSupport
            .appendingPathComponent("Codex Token Meter", isDirectory: true)
            .appendingPathComponent("ParsedRollouts", isDirectory: true)
        self.isoFormatter = ISO8601DateFormatter()
        self.isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.dayFormatter = DateFormatter()
        self.dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        self.dayFormatter.timeZone = appTimeZone()
        self.dayFormatter.dateFormat = "yyyy-MM-dd"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = appTimeZone()
        self.calendar = calendar
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    var rootPaths: [String] {
        rootURLs.map(\.path)
    }

    private static func uniqueRootURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var unique: [URL] = []
        for url in urls {
            let standardized = url.standardizedFileURL
            let key = (standardized.path as NSString).standardizingPath
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            unique.append(standardized)
        }
        return unique
    }

    func scan(window: WindowOption, limitID: String? = nil, excludedLimitID: String? = nil, includedModelName: String? = nil, excludedModelName: String? = nil) -> TokenReport {
        let now = Date()
        switch window {
        case .day:
            return scan(start: now.addingTimeInterval(-24 * 3600), now: now, limitID: limitID, excludedLimitID: excludedLimitID, includedModelName: includedModelName, excludedModelName: excludedModelName, fillDayCount: nil)
        case .week:
            let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -6, to: now) ?? now)
            return scan(start: start, now: now, limitID: limitID, excludedLimitID: excludedLimitID, includedModelName: includedModelName, excludedModelName: excludedModelName, fillDayCount: 7)
        case .month:
            let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -29, to: now) ?? now)
            return scan(start: start, now: now, limitID: limitID, excludedLimitID: excludedLimitID, includedModelName: includedModelName, excludedModelName: excludedModelName, fillDayCount: 30)
        }
    }

    func scan(hours: Int, limitID: String? = nil, excludedLimitID: String? = nil, includedModelName: String? = nil, excludedModelName: String? = nil) -> TokenReport {
        let now = Date()
        let start = now.addingTimeInterval(TimeInterval(-hours * 3600))
        return scan(start: start, now: now, limitID: limitID, excludedLimitID: excludedLimitID, includedModelName: includedModelName, excludedModelName: excludedModelName, fillDayCount: nil)
    }

    func scan(days: Int, limitID: String? = nil, excludedLimitID: String? = nil, includedModelName: String? = nil, excludedModelName: String? = nil) -> TokenReport {
        let now = Date()
        let dayCount = max(days, 1)
        let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -(dayCount - 1), to: now) ?? now)
        return scan(start: start, now: now, limitID: limitID, excludedLimitID: excludedLimitID, includedModelName: includedModelName, excludedModelName: excludedModelName, fillDayCount: dayCount)
    }

    func scan(from start: Date, to now: Date = Date(), limitID: String? = nil, excludedLimitID: String? = nil, includedModelName: String? = nil, excludedModelName: String? = nil) -> TokenReport {
        scan(start: start, now: now, limitID: limitID, excludedLimitID: excludedLimitID, includedModelName: includedModelName, excludedModelName: excludedModelName, fillDayCount: nil)
    }

    func scanRepoInsights(days: Int = 90) -> RepoInsightsReport {
        let windowDays = max(days, 1)
        return scanRepoInsights(windows: [windowDays])[windowDays] ?? RepoInsightsReport(rows: [], scannedAt: Date(), windowDays: windowDays)
    }

    func scanRepoInsights(windows: [Int]) -> [Int: RepoInsightsReport] {
        let now = Date()
        let windowDays = Array(Set(windows.map { max($0, 1) })).sorted()
        guard !windowDays.isEmpty else { return [:] }
        let starts = Dictionary(uniqueKeysWithValues: windowDays.map { days in
            (days, calendar.startOfDay(for: calendar.date(byAdding: .day, value: -(days - 1), to: now) ?? now))
        })
        let earliestStart = starts.values.min() ?? now
        var aggregatesByWindow: [Int: [String: RepoInsightAccumulator]] = [:]
        var reasoningByWindow: [Int: ReasoningInsightsAccumulator] = [:]

        for fileURL in rolloutFiles(modifiedSince: earliestStart) {
            let file = cachedFile(fileURL)
            for (days, start) in starts {
                let conversation = repoInsightConversation(from: file.repoInsight, start: start, now: now)
                guard conversation.turns > 0
                        || conversation.compressions > 0
                        || conversation.tokens > 0 else {
                    continue
                }

                let cwd = conversation.cwd ?? "(unknown)"
                let key = repoInsightKey(for: cwd)
                var aggregates = aggregatesByWindow[days] ?? [:]
                var accumulator = aggregates[key] ?? RepoInsightAccumulator(key: key, displayName: repoInsightDisplayName(for: key), primaryFolder: cwd)
                accumulator.add(conversation)
                aggregates[key] = accumulator
                aggregatesByWindow[days] = aggregates
                var reasoning = reasoningByWindow[days] ?? ReasoningInsightsAccumulator()
                reasoning.add(conversation, projectKey: key)
                reasoningByWindow[days] = reasoning
            }
        }

        return Dictionary(uniqueKeysWithValues: windowDays.map { days in
            let rows = repoInsightRows(from: aggregatesByWindow[days] ?? [:])
            let reasoning = reasoningByWindow[days]?.report()
            return (days, RepoInsightsReport(rows: rows, scannedAt: now, windowDays: days, reasoning: reasoning))
        })
    }

    private func repoInsightRows(from aggregates: [String: RepoInsightAccumulator]) -> [RepoInsight] {
        aggregates.values
            .map { $0.repoInsight() }
            .sorted {
                if $0.compressions != $1.compressions {
                    return $0.compressions > $1.compressions
                }
                if $0.conversations != $1.conversations {
                    return $0.conversations > $1.conversations
                }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    private func repoInsightConversation(from aggregate: FileRepoInsightAggregate, start: Date, now: Date) -> RepoInsightConversation {
        let startDay = dayFormatter.string(from: start)
        let endDay = dayFormatter.string(from: now)
        let days = aggregate.days.filter { $0.day >= startDay && $0.day <= endDay }
        let activeDaySet = Set(days.map(\.day))
        var conversation = RepoInsightConversation()
        conversation.cwd = aggregate.cwd
        conversation.days = days
        conversation.activeDays = activeDaySet
        conversation.hours = aggregate.hours.filter { activeDaySet.contains($0.day) && ($0.turns > 0 || $0.tokens > 0) }
        conversation.reasoningRuns = aggregate.reasoningRuns.filter { $0.timestamp >= start && $0.timestamp <= now }
        for day in days {
            conversation.turns += day.turns
            conversation.compressions += day.compressions
            conversation.tokens += day.tokens
            conversation.abortedTurns += day.abortedTurns
            conversation.completedTurns += day.completedTurns
        }
        return conversation
    }

    private func scan(start: Date, now: Date, limitID: String?, excludedLimitID: String?, includedModelName: String?, excludedModelName: String?, fillDayCount: Int?) -> TokenReport {
        if limitID == nil, excludedLimitID == nil, fillDayCount != nil {
            return scanDayAggregates(start: start, now: now, includedModelName: includedModelName, excludedModelName: excludedModelName, fillDayCount: fillDayCount)
        }

        var report = TokenReport(scannedAt: now)
        var dayBuckets: [String: Usage] = [:]
        var dayTurns: [String: Int] = [:]
        var dayModelBuckets: [String: [String: Usage]] = [:]
        var dayModelEvents: [String: [String: Int]] = [:]
        var dayModelSessions: [String: [String: Int]] = [:]
        var hourBuckets: [Date: Usage] = [:]
        var hourTurns: [Date: Int] = [:]
        var modelBuckets: [String: Usage] = [:]
        var modelEvents: [String: Int] = [:]
        var modelSessions: [String: Int] = [:]
        var sessions: [SessionUsage] = []

        for fileURL in rolloutFiles(modifiedSince: start) {
            let file = cachedFile(fileURL)
            let isUnfilteredScan = limitID == nil && excludedLimitID == nil && includedModelName == nil && excludedModelName == nil
            let events = file.events.filter {
                $0.timestamp >= start
                    && $0.timestamp <= now
                    && matchesLimit($0, limitID: limitID)
                    && !matchesExcludedLimit($0, excludedLimitID: excludedLimitID)
                    && matchesModel($0, modelName: includedModelName)
                    && !matchesExcludedModel($0, modelName: excludedModelName)
            }
            let rawTurns = file.turns.filter { $0 >= start && $0 <= now }
            let turns = isUnfilteredScan ? rawTurns : events.map { $0.timestamp }
            guard !events.isEmpty || !turns.isEmpty else { continue }

            var sessionUsage = Usage()
            var lastEvent = file.events.last?.timestamp ?? now
            var sessionModels = Set<String>()
            var sessionDayModels: [String: Set<String>] = [:]
            for event in events {
                sessionUsage.add(event.usage)
                lastEvent = event.timestamp
                if let limitName = event.limitName {
                    report.limitNames.insert(limitName)
                }
                let modelName = modelDisplayName(for: event)
                var modelUsage = modelBuckets[modelName] ?? Usage()
                modelUsage.add(event.usage)
                modelBuckets[modelName] = modelUsage
                modelEvents[modelName, default: 0] += 1
                sessionModels.insert(modelName)

                let day = dayFormatter.string(from: event.timestamp)
                sessionDayModels[day, default: []].insert(modelName)
                var usage = dayBuckets[day] ?? Usage()
                usage.add(event.usage)
                dayBuckets[day] = usage
                var dayModels = dayModelBuckets[day] ?? [:]
                var dayModelUsage = dayModels[modelName] ?? Usage()
                dayModelUsage.add(event.usage)
                dayModels[modelName] = dayModelUsage
                dayModelBuckets[day] = dayModels
                var dayEvents = dayModelEvents[day] ?? [:]
                dayEvents[modelName, default: 0] += 1
                dayModelEvents[day] = dayEvents

                let hour = calendar.dateInterval(of: .hour, for: event.timestamp)?.start ?? event.timestamp
                var hourUsage = hourBuckets[hour] ?? Usage()
                hourUsage.add(event.usage)
                hourBuckets[hour] = hourUsage
            }

            for turn in turns {
                dayTurns[dayFormatter.string(from: turn), default: 0] += 1
                let hour = calendar.dateInterval(of: .hour, for: turn)?.start ?? turn
                hourTurns[hour, default: 0] += 1
            }

            if isUnfilteredScan || !events.isEmpty {
                report.sessions += 1
                report.events += events.count
                report.turns += turns.count
                report.usage.add(sessionUsage)
                sessions.append(SessionUsage(path: fileURL.path, lastEvent: lastEvent, turns: turns.count, usage: sessionUsage))
                for model in sessionModels {
                    modelSessions[model, default: 0] += 1
                }
                for (day, models) in sessionDayModels {
                    var sessionsForDay = dayModelSessions[day] ?? [:]
                    for model in models {
                        sessionsForDay[model, default: 0] += 1
                    }
                    dayModelSessions[day] = sessionsForDay
                }
            }
        }

        let days: Set<String>
        if let fillDayCount {
            days = Set((0..<fillDayCount).compactMap { offset in
                calendar.date(byAdding: .day, value: offset, to: start).map { dayFormatter.string(from: $0) }
            })
        } else {
            days = Set(dayBuckets.keys).union(dayTurns.keys)
        }
        report.byDay = days
            .map { day in
                let models = (dayModelBuckets[day] ?? [:]).map { name, usage in
                    ModelUsage(
                        name: name,
                        usage: usage,
                        events: dayModelEvents[day]?[name] ?? 0,
                        sessions: dayModelSessions[day]?[name] ?? 0
                    )
                }
                .sorted { $0.usage.total > $1.usage.total }
                return DayUsage(day: day, usage: dayBuckets[day] ?? Usage(), turns: dayTurns[day] ?? 0, modelBreakdown: models)
            }
            .sorted { $0.day < $1.day }
        let hours = Set(hourBuckets.keys).union(hourTurns.keys)
        report.byHour = hours
            .map { HourUsage(hour: $0, usage: hourBuckets[$0] ?? Usage(), turns: hourTurns[$0] ?? 0) }
            .sorted { $0.hour < $1.hour }
        report.topSessions = sessions.sorted { $0.usage.total > $1.usage.total }.prefix(8).map { $0 }
        report.modelBreakdown = modelBuckets.map { name, usage in
            ModelUsage(name: name, usage: usage, events: modelEvents[name] ?? 0, sessions: modelSessions[name] ?? 0)
        }
        .sorted { $0.usage.total > $1.usage.total }
        return report
    }

    private func scanDayAggregates(start: Date, now: Date, includedModelName: String?, excludedModelName: String?, fillDayCount: Int?) -> TokenReport {
        var report = TokenReport(scannedAt: now)
        let startDay = dayFormatter.string(from: start)
        let endDay = dayFormatter.string(from: now)
        let isUnfilteredScan = includedModelName == nil && excludedModelName == nil
        var dayBuckets: [String: Usage] = [:]
        var dayTurns: [String: Int] = [:]
        var dayModelBuckets: [String: [String: Usage]] = [:]
        var dayModelEvents: [String: [String: Int]] = [:]
        var dayModelSessions: [String: [String: Int]] = [:]
        var modelBuckets: [String: Usage] = [:]
        var modelEvents: [String: Int] = [:]
        var modelSessions: [String: Int] = [:]
        var sessions: [SessionUsage] = []

        for fileURL in rolloutFiles(modifiedSince: start) {
            let file = cachedFile(fileURL)
            var sessionUsage = Usage()
            var sessionTurns = 0
            var lastEvent = now
            var hasLastEvent = false
            var sessionModels = Set<String>()
            var sessionDayModels: [String: Set<String>] = [:]

            for day in file.days where day.day >= startDay && day.day <= endDay {
                let matchingModels = day.models.filter {
                    matchesAggregateModel($0.name, includedModelName: includedModelName, excludedModelName: excludedModelName)
                }
                let dayUsage: Usage
                let selectedTurns: Int
                if isUnfilteredScan {
                    dayUsage = day.usage
                    selectedTurns = day.turns
                } else {
                    dayUsage = matchingModels.reduce(Usage()) { partial, model in
                        var next = partial
                        next.add(model.usage)
                        return next
                    }
                    selectedTurns = matchingModels.reduce(0) { $0 + $1.events }
                }
                guard dayUsage.total > 0 || dayUsage.input > 0 || dayUsage.output > 0 || selectedTurns > 0 else {
                    continue
                }

                sessionUsage.add(dayUsage)
                sessionTurns += selectedTurns
                dayTurns[day.day, default: 0] += selectedTurns
                var usage = dayBuckets[day.day] ?? Usage()
                usage.add(dayUsage)
                dayBuckets[day.day] = usage
                if let date = dayFormatter.date(from: day.day) {
                    lastEvent = date
                    hasLastEvent = true
                }

                for model in matchingModels {
                    let modelName = Self.canonicalModelName(model.name)
                    sessionModels.insert(modelName)
                    sessionDayModels[day.day, default: []].insert(modelName)
                    var totalModelUsage = modelBuckets[modelName] ?? Usage()
                    totalModelUsage.add(model.usage)
                    modelBuckets[modelName] = totalModelUsage
                    modelEvents[modelName, default: 0] += model.events

                    var dayModels = dayModelBuckets[day.day] ?? [:]
                    var dayModelUsage = dayModels[modelName] ?? Usage()
                    dayModelUsage.add(model.usage)
                    dayModels[modelName] = dayModelUsage
                    dayModelBuckets[day.day] = dayModels

                    var dayEvents = dayModelEvents[day.day] ?? [:]
                    dayEvents[modelName, default: 0] += model.events
                    dayModelEvents[day.day] = dayEvents
                }
            }

            guard sessionUsage.total > 0 || sessionUsage.input > 0 || sessionUsage.output > 0 || sessionTurns > 0 else {
                continue
            }
            report.sessions += 1
            report.events += isUnfilteredScan ? file.days
                .filter { $0.day >= startDay && $0.day <= endDay }
                .reduce(0) { $0 + $1.models.reduce(0) { $0 + $1.events } } : sessionTurns
            report.turns += sessionTurns
            report.usage.add(sessionUsage)
            sessions.append(SessionUsage(path: fileURL.path, lastEvent: hasLastEvent ? lastEvent : now, turns: sessionTurns, usage: sessionUsage))
            for model in sessionModels {
                modelSessions[model, default: 0] += 1
            }
            for (day, models) in sessionDayModels {
                var sessionsForDay = dayModelSessions[day] ?? [:]
                for model in models {
                    sessionsForDay[model, default: 0] += 1
                }
                dayModelSessions[day] = sessionsForDay
            }
        }

        let days: Set<String>
        if let fillDayCount {
            days = Set((0..<fillDayCount).compactMap { offset in
                calendar.date(byAdding: .day, value: offset, to: start).map { dayFormatter.string(from: $0) }
            })
        } else {
            days = Set(dayBuckets.keys).union(dayTurns.keys)
        }
        report.byDay = days
            .map { day in
                let models = (dayModelBuckets[day] ?? [:]).map { name, usage in
                    ModelUsage(
                        name: name,
                        usage: usage,
                        events: dayModelEvents[day]?[name] ?? 0,
                        sessions: dayModelSessions[day]?[name] ?? 0
                    )
                }
                .sorted { $0.usage.total > $1.usage.total }
                return DayUsage(day: day, usage: dayBuckets[day] ?? Usage(), turns: dayTurns[day] ?? 0, modelBreakdown: models)
            }
            .sorted { $0.day < $1.day }
        report.topSessions = sessions.sorted { $0.usage.total > $1.usage.total }.prefix(8).map { $0 }
        report.modelBreakdown = modelBuckets.map { name, usage in
            ModelUsage(name: name, usage: usage, events: modelEvents[name] ?? 0, sessions: modelSessions[name] ?? 0)
        }
        .sorted { $0.usage.total > $1.usage.total }
        return report
    }

    private func matchesAggregateModel(_ value: String, includedModelName: String?, excludedModelName: String?) -> Bool {
        let canonicalValue = Self.canonicalModelName(value).lowercased()
        if let includedModelName,
           !modelNameMatches(canonicalValue, target: Self.canonicalModelName(includedModelName)) {
            return false
        }
        if let excludedModelName,
           modelNameMatches(canonicalValue, target: Self.canonicalModelName(excludedModelName)) {
            return false
        }
        return true
    }

    private func modelDisplayName(for event: TokenEvent) -> String {
        if let model = event.model, !model.isEmpty {
            return Self.canonicalModelName(model)
        }
        if event.limitID == AppSettings.modelLimitID {
            return Self.canonicalModelName(AppSettings.modelLimitName)
        }
        if let limitName = event.limitName,
           limitName.localizedCaseInsensitiveContains(AppSettings.modelLimitName) {
            return Self.canonicalModelName(AppSettings.modelLimitName)
        }
        return "Unknown model"
    }

    private func matchesLimit(_ event: TokenEvent, limitID: String?) -> Bool {
        guard let limitID else { return true }
        if event.limitID == limitID {
            return true
        }
        guard let limitName = event.limitName else {
            return false
        }
        return limitName == limitID || limitName.hasPrefix("\(limitID) ")
    }

    private func matchesExcludedLimit(_ event: TokenEvent, excludedLimitID: String?) -> Bool {
        guard let excludedLimitID else { return false }
        return matchesLimit(event, limitID: excludedLimitID)
    }

    private func matchesModel(_ event: TokenEvent, modelName: String?) -> Bool {
        guard let modelName else { return true }
        return modelNameMatches(normalizedModelName(for: event), target: modelName)
    }

    private func matchesExcludedModel(_ event: TokenEvent, modelName: String?) -> Bool {
        guard let modelName else { return false }
        return modelNameMatches(normalizedModelName(for: event), target: modelName)
    }

    private func normalizedModelName(for event: TokenEvent) -> String {
        modelDisplayName(for: event).lowercased()
    }

    private func modelNameMatches(_ value: String, target: String) -> Bool {
        let normalizedTarget = target.lowercased()
        return value == normalizedTarget
            || value.contains(normalizedTarget)
            || normalizedTarget.contains(value)
    }

    private func rolloutFiles(modifiedSince start: Date) -> [URL] {
        var files: [URL] = []
        var seen = Set<String>()

        for rootURL in rootURLs {
            for url in rolloutFiles(in: rootURL, modifiedSince: start) {
                let key = (url.path as NSString).standardizingPath
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                files.append(url)
            }
        }

        return files.sorted { $0.path < $1.path }
    }

    private func rolloutFiles(in rootURL: URL, modifiedSince start: Date) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL else { return nil }
            guard url.lastPathComponent.hasPrefix("rollout-"), url.pathExtension == "jsonl" else { return nil }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if let modifiedAt = values?.contentModificationDate, modifiedAt < start {
                return nil
            }
            return url
        }
    }

    private func cachedFile(_ fileURL: URL) -> FileCache {
        let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modifiedAt = values?.contentModificationDate ?? .distantPast
        let size = Int64(values?.fileSize ?? 0)
        let key = fileURL.path

        if let cached = cache[key], cached.modifiedAt == modifiedAt, cached.size == size {
            return cached
        }

        if let cached = readDiskCache(fileURL: fileURL, size: size, modifiedAt: modifiedAt) {
            cache[key] = cached
            return cached
        }

        let parsed = parse(fileURL: fileURL)
        let file = FileCache(
            size: size,
            modifiedAt: modifiedAt,
            events: parsed.events,
            turns: parsed.turns,
            days: dayAggregates(events: parsed.events, turns: parsed.turns),
            repoInsight: repoInsightAggregate(fileURL: fileURL)
        )
        cache[key] = file
        writeDiskCache(file, fileURL: fileURL)
        return file
    }

    private func readDiskCache(fileURL: URL, size: Int64, modifiedAt: Date) -> FileCache? {
        let url = diskCacheURL(for: fileURL)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        let timeZoneIdentifier = appTimeZone().identifier
        if let disk = try? jsonDecoder.decode(DiskFileCache.self, from: data),
              disk.version == 10,
              disk.path == fileURL.path,
              disk.size == size,
              disk.timeZoneIdentifier == timeZoneIdentifier,
              abs(disk.modifiedAt - modifiedAt.timeIntervalSinceReferenceDate) < 0.001 {
            return FileCache(size: disk.size, modifiedAt: modifiedAt, events: disk.events, turns: disk.turns, days: disk.days, repoInsight: disk.repoInsight)
        }

        if let legacy = try? jsonDecoder.decode(LegacyV7DiskFileCache.self, from: data),
           legacy.version == 7,
           legacy.path == fileURL.path,
           legacy.size == size,
           legacy.timeZoneIdentifier == timeZoneIdentifier,
           abs(legacy.modifiedAt - modifiedAt.timeIntervalSinceReferenceDate) < 0.001 {
            let file = FileCache(
                size: legacy.size,
                modifiedAt: modifiedAt,
                events: legacy.events,
                turns: legacy.turns,
                days: legacy.days,
                repoInsight: repoInsightAggregate(fileURL: fileURL)
            )
            writeDiskCache(file, fileURL: fileURL)
            return file
        }

        if let legacy = try? jsonDecoder.decode(LegacyV6DiskFileCache.self, from: data),
           legacy.version == 6,
           legacy.path == fileURL.path,
           legacy.size == size,
           legacy.timeZoneIdentifier == timeZoneIdentifier,
           abs(legacy.modifiedAt - modifiedAt.timeIntervalSinceReferenceDate) < 0.001 {
            let file = FileCache(
                size: legacy.size,
                modifiedAt: modifiedAt,
                events: legacy.events,
                turns: legacy.turns,
                days: legacy.days,
                repoInsight: repoInsightAggregate(fileURL: fileURL)
            )
            writeDiskCache(file, fileURL: fileURL)
            return file
        }

        if let legacy = try? jsonDecoder.decode(LegacyV4DiskFileCache.self, from: data),
           legacy.version == 5,
           legacy.path == fileURL.path,
           legacy.size == size,
           legacy.timeZoneIdentifier == timeZoneIdentifier,
           abs(legacy.modifiedAt - modifiedAt.timeIntervalSinceReferenceDate) < 0.001 {
            let file = FileCache(
                size: legacy.size,
                modifiedAt: modifiedAt,
                events: legacy.events,
                turns: legacy.turns,
                days: legacy.days,
                repoInsight: repoInsightAggregate(fileURL: fileURL)
            )
            writeDiskCache(file, fileURL: fileURL)
            return file
        }

        if let legacy = try? jsonDecoder.decode(LegacyV4DiskFileCache.self, from: data),
           legacy.version == 4,
           legacy.path == fileURL.path,
           legacy.size == size,
           abs(legacy.modifiedAt - modifiedAt.timeIntervalSinceReferenceDate) < 0.001 {
            let file = FileCache(
                size: legacy.size,
                modifiedAt: modifiedAt,
                events: legacy.events,
                turns: legacy.turns,
                days: legacy.days,
                repoInsight: repoInsightAggregate(fileURL: fileURL)
            )
            writeDiskCache(file, fileURL: fileURL)
            return file
        }

        if let legacy = try? jsonDecoder.decode(LegacyV3DiskFileCache.self, from: data),
           legacy.version == 3,
           legacy.path == fileURL.path,
           legacy.size == size,
           abs(legacy.modifiedAt - modifiedAt.timeIntervalSinceReferenceDate) < 0.001 {
            let file = FileCache(
                size: legacy.size,
                modifiedAt: modifiedAt,
                events: legacy.events,
                turns: legacy.turns,
                days: legacy.days,
                repoInsight: repoInsightAggregate(fileURL: fileURL)
            )
            writeDiskCache(file, fileURL: fileURL)
            return file
        }

        if let legacy = try? jsonDecoder.decode(LegacyDiskFileCache.self, from: data),
           legacy.version == 2,
           legacy.path == fileURL.path,
           legacy.size == size,
           abs(legacy.modifiedAt - modifiedAt.timeIntervalSinceReferenceDate) < 0.001 {
            let file = FileCache(
                size: legacy.size,
                modifiedAt: modifiedAt,
                events: legacy.events,
                turns: legacy.turns,
                days: dayAggregates(events: legacy.events, turns: legacy.turns),
                repoInsight: repoInsightAggregate(fileURL: fileURL)
            )
            writeDiskCache(file, fileURL: fileURL)
            return file
        }

        return nil
    }

    private func writeDiskCache(_ file: FileCache, fileURL: URL) {
        let disk = DiskFileCache(
            version: 10,
            path: fileURL.path,
            size: file.size,
            modifiedAt: file.modifiedAt.timeIntervalSinceReferenceDate,
            timeZoneIdentifier: appTimeZone().identifier,
            events: file.events,
            turns: file.turns,
            days: file.days,
            repoInsight: file.repoInsight
        )
        guard let data = try? jsonEncoder.encode(disk) else { return }
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: diskCacheURL(for: fileURL), options: [.atomic])
    }

    private func repoInsightAggregate(fileURL: URL) -> FileRepoInsightAggregate {
        guard let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]) else {
            return FileRepoInsightAggregate(cwd: nil, days: [], hours: [], reasoningRuns: [])
        }

        var previousTotal = Usage()
        var dayBuckets: [String: FileRepoInsightDayAggregate] = [:]
        var hourBuckets: [String: FileRepoInsightHourAggregate] = [:]
        var cwdCounts: [String: Int] = [:]
        var reasoningRuns: [FileReasoningRunAggregate] = []
        var runIndexByTurnID: [String: Int] = [:]
        var currentRunIndex: Int?
        var pendingTaskStartedIndex: Int?
        var currentModel = "Unknown model"
        var awaitingSubagentBoundary = false
        var pendingSubagentModel: String?

        func appendReasoningRun(timestamp: Date, model: String = "Unknown model", effort: String = "unknown") -> Int {
            reasoningRuns.append(FileReasoningRunAggregate(
                timestamp: timestamp,
                day: self.dayFormatter.string(from: timestamp),
                model: Self.normalizedReasoningModel(model),
                effort: effort,
                usage: Usage()
            ))
            return reasoningRuns.count - 1
        }

        func updateDay(_ day: String, apply: (inout FileRepoInsightDayAggregate) -> Void) {
            var bucket = dayBuckets[day] ?? FileRepoInsightDayAggregate(day: day, turns: 0, compressions: 0, tokens: 0, abortedTurns: 0, completedTurns: 0)
            apply(&bucket)
            dayBuckets[day] = bucket
        }

        func updateHour(_ timestamp: Date, day: String, apply: (inout FileRepoInsightHourAggregate) -> Void) {
            let hour = self.calendar.component(.hour, from: timestamp)
            let key = "\(day)|\(hour)"
            var bucket = hourBuckets[key] ?? FileRepoInsightHourAggregate(day: day, hour: hour, turns: 0, tokens: 0)
            apply(&bucket)
            hourBuckets[key] = bucket
        }

        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            let count = rawBuffer.count
            var lineStart = 0

            func handleLine(_ lineEnd: Int) {
                guard lineEnd > lineStart else { return }
                let range = lineStart..<lineEnd

                if self.contains(base, range: range, pattern: self.subagentSourcePattern) {
                    // Desktop forks serialize the parent's event history into each
                    // child rollout before this marker. Keep advancing cumulative
                    // counters below, but do not attribute that inherited prefix.
                    awaitingSubagentBoundary = true
                    pendingSubagentModel = nil
                    return
                }
                if awaitingSubagentBoundary,
                   self.contains(base, range: range, pattern: self.turnContextPattern),
                   let model = self.extractString(base, range: range, key: self.modelKey),
                   !model.isEmpty {
                    // The child's turn context is serialized immediately before
                    // the boundary marker. Preserve its model while continuing to
                    // ignore the inherited parent event prefix.
                    pendingSubagentModel = Self.normalizedReasoningModel(model)
                    return
                }
                if awaitingSubagentBoundary,
                   self.contains(base, range: range, pattern: self.interAgentMetadataPattern) {
                    awaitingSubagentBoundary = false
                    currentRunIndex = nil
                    pendingTaskStartedIndex = nil
                    currentModel = pendingSubagentModel ?? "Unknown model"
                    pendingSubagentModel = nil
                    return
                }

                if !awaitingSubagentBoundary,
                   self.contains(base, range: range, pattern: self.turnContextPattern),
                   let cwd = self.extractString(base, range: range, key: self.cwdKey),
                   !cwd.isEmpty {
                    cwdCounts[cwd, default: 0] += 1
                }

                guard let timestampString = self.extractString(base, range: range, key: self.timestampKey),
                      let timestamp = self.parseDate(timestampString) else {
                    return
                }
                let day = self.dayFormatter.string(from: timestamp)

                if self.contains(base, range: range, pattern: self.turnContextPattern) {
                    let effort = Self.normalizedReasoningEffort(self.extractString(base, range: range, key: self.effortKey))
                    let model = Self.normalizedReasoningModel(self.extractString(base, range: range, key: self.modelKey))
                    let turnID = self.extractString(base, range: range, key: self.turnIDKey)
                    currentModel = model

                    if let turnID, let existing = runIndexByTurnID[turnID] {
                        currentRunIndex = existing
                        reasoningRuns[existing].effort = effort
                        reasoningRuns[existing].model = model
                    } else if let pending = pendingTaskStartedIndex,
                              reasoningRuns.indices.contains(pending),
                              reasoningRuns[pending].usage.total == 0 {
                        currentRunIndex = pending
                        reasoningRuns[pending].effort = effort
                        reasoningRuns[pending].model = model
                        if let turnID, !turnID.isEmpty {
                            runIndexByTurnID[turnID] = pending
                        }
                    } else if turnID == nil, let currentRunIndex,
                              reasoningRuns.indices.contains(currentRunIndex) {
                        reasoningRuns[currentRunIndex].effort = effort
                        reasoningRuns[currentRunIndex].model = model
                    } else {
                        let index = appendReasoningRun(timestamp: timestamp, model: model, effort: effort)
                        currentRunIndex = index
                        if let turnID, !turnID.isEmpty {
                            runIndexByTurnID[turnID] = index
                        }
                    }
                    pendingTaskStartedIndex = nil
                }

                if self.contains(base, range: range, pattern: self.tokenCountPattern) {
                    let currentTotal = Usage(
                        input: self.extractInt64(base, range: range, key: self.inputKey),
                        cachedInput: self.extractInt64(base, range: range, key: self.cachedInputKey),
                        output: self.extractInt64(base, range: range, key: self.outputKey),
                        reasoningOutput: self.extractInt64(base, range: range, key: self.reasoningOutputKey),
                        total: self.extractInt64(base, range: range, key: self.totalKey)
                    )
                    let delta = Usage.delta(from: previousTotal, to: currentTotal)
                    previousTotal = currentTotal
                    guard !awaitingSubagentBoundary else { return }
                    updateDay(day) { $0.tokens += delta.total }
                    updateHour(timestamp, day: day) { $0.tokens += delta.total }
                    if currentRunIndex == nil {
                        currentRunIndex = appendReasoningRun(timestamp: timestamp, model: currentModel)
                    }
                    if let currentRunIndex, reasoningRuns.indices.contains(currentRunIndex) {
                        reasoningRuns[currentRunIndex].usage.add(delta)
                    }
                }

                guard !awaitingSubagentBoundary else { return }

                guard self.contains(base, range: range, pattern: self.eventMsgPattern) else {
                    return
                }

                if self.contains(base, range: range, pattern: self.taskStartedPattern) {
                    updateDay(day) { $0.turns += 1 }
                    updateHour(timestamp, day: day) { $0.turns += 1 }
                    currentModel = "Unknown model"
                    let index = appendReasoningRun(timestamp: timestamp)
                    currentRunIndex = index
                    pendingTaskStartedIndex = index
                } else if self.contains(base, range: range, pattern: self.contextCompactedPattern) {
                    updateDay(day) { $0.compressions += 1 }
                } else if self.contains(base, range: range, pattern: self.turnAbortedPattern) {
                    updateDay(day) { $0.abortedTurns += 1 }
                } else if self.contains(base, range: range, pattern: self.taskCompletePattern) {
                    updateDay(day) { $0.completedTurns += 1 }
                }
            }

            for index in 0..<count {
                if base[index] == 10 {
                    handleLine(index)
                    lineStart = index + 1
                }
            }
            if lineStart < count {
                handleLine(count)
            }
        }

        let cwd = cwdCounts.max {
            if $0.value != $1.value { return $0.value < $1.value }
            return $0.key > $1.key
        }?.key
        return FileRepoInsightAggregate(
            cwd: cwd,
            days: dayBuckets.values.sorted { $0.day < $1.day },
            hours: hourBuckets.values.sorted {
                if $0.day != $1.day { return $0.day < $1.day }
                return $0.hour < $1.hour
            },
            reasoningRuns: reasoningRuns
        )
    }

    private func dayAggregates(events: [TokenEvent], turns: [Date]) -> [FileDayAggregate] {
        var dayBuckets: [String: Usage] = [:]
        var dayTurns: [String: Int] = [:]
        var dayModelBuckets: [String: [String: Usage]] = [:]
        var dayModelEvents: [String: [String: Int]] = [:]

        for turn in turns {
            dayTurns[dayFormatter.string(from: turn), default: 0] += 1
        }

        for event in events {
            let day = dayFormatter.string(from: event.timestamp)
            var usage = dayBuckets[day] ?? Usage()
            usage.add(event.usage)
            dayBuckets[day] = usage

            let modelName = modelDisplayName(for: event)
            var dayModels = dayModelBuckets[day] ?? [:]
            var modelUsage = dayModels[modelName] ?? Usage()
            modelUsage.add(event.usage)
            dayModels[modelName] = modelUsage
            dayModelBuckets[day] = dayModels

            var modelEvents = dayModelEvents[day] ?? [:]
            modelEvents[modelName, default: 0] += 1
            dayModelEvents[day] = modelEvents
        }

        return Set(dayBuckets.keys).union(dayTurns.keys)
            .map { day in
                let models = (dayModelBuckets[day] ?? [:])
                    .map { name, usage in
                        FileModelAggregate(name: name, usage: usage, events: dayModelEvents[day]?[name] ?? 0)
                    }
                    .sorted { $0.usage.total > $1.usage.total }
                return FileDayAggregate(day: day, usage: dayBuckets[day] ?? Usage(), turns: dayTurns[day] ?? 0, models: models)
            }
            .sorted { $0.day < $1.day }
    }

    private func diskCacheURL(for fileURL: URL) -> URL {
        cacheDirectory.appendingPathComponent("\(fnv1a64(fileURL.path)).json")
    }

    private func fnv1a64(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    private func repoInsightKey(for cwd: String) -> String {
        let standardized = (cwd as NSString).standardizingPath
        let components = standardized.split(separator: "/").map(String.init)

        if components.count >= 6,
           components[0] == "Users",
           components[1] == "kadewu",
           components[2] == ".codex",
           components[3] == "worktrees" {
            let repoName = components[5]
            let canonical = "/Users/kadewu/Documents/github/\(repoName)"
            if FileManager.default.fileExists(atPath: canonical) {
                return canonical
            }
            return "/Users/kadewu/.codex/worktrees/*/\(repoName)"
        }

        if let githubIndex = components.firstIndex(of: "github"),
           components.count > githubIndex + 1 {
            return "/" + components.prefix(githubIndex + 2).joined(separator: "/")
        }

        if standardized == "/Users/kadewu/Documents/Codex"
            || standardized.hasPrefix("/Users/kadewu/Documents/Codex/") {
            return "/Users/kadewu/Documents/Codex"
        }

        return standardized
    }

    private func repoInsightDisplayName(for key: String) -> String {
        let home = NSHomeDirectory()
        if key.hasPrefix("/Users/kadewu/Documents/github/") {
            return "github/" + key.dropFirst("/Users/kadewu/Documents/github/".count)
        }
        if key == "/Users/kadewu/Documents/Codex" {
            return "Codex"
        }
        if key.hasPrefix("/Users/kadewu/Documents/Codex/") {
            return "Codex/" + key.dropFirst("/Users/kadewu/Documents/Codex/".count)
        }
        if key.hasPrefix("/Users/kadewu/.codex/worktrees/*/") {
            return "worktrees/" + key.dropFirst("/Users/kadewu/.codex/worktrees/*/".count)
        }
        if key.hasPrefix(home) {
            return "~" + key.dropFirst(home.count)
        }
        return key
    }

    private func parse(fileURL: URL) -> (events: [TokenEvent], turns: [Date]) {
        guard let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]) else {
            return ([], [])
        }

        var previousTotal = Usage()
        var events: [TokenEvent] = []
        var turns: [Date] = []
        var currentModel: String?
        var awaitingSubagentBoundary = false
        var pendingSubagentModel: String?

        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            let count = rawBuffer.count
            var lineStart = 0

            func handleLine(_ lineEnd: Int) {
                guard lineEnd > lineStart else { return }
                let range = lineStart..<lineEnd

                if self.contains(base, range: range, pattern: self.subagentSourcePattern) {
                    // A forked rollout starts with a replay of its parent's events.
                    // The child turn context and following inter-agent metadata
                    // mark the child's own event stream.
                    awaitingSubagentBoundary = true
                    pendingSubagentModel = nil
                    return
                }
                if awaitingSubagentBoundary,
                   self.contains(base, range: range, pattern: self.turnContextPattern),
                   let model = self.extractString(base, range: range, key: self.modelKey),
                   !model.isEmpty {
                    pendingSubagentModel = model
                    return
                }
                if awaitingSubagentBoundary,
                   self.contains(base, range: range, pattern: self.interAgentMetadataPattern) {
                    awaitingSubagentBoundary = false
                    currentModel = pendingSubagentModel
                    pendingSubagentModel = nil
                    return
                }
                guard let timestampString = self.extractString(base, range: range, key: self.timestampKey),
                      let timestamp = self.parseDate(timestampString) else {
                    return
                }

                if !awaitingSubagentBoundary,
                   self.contains(base, range: range, pattern: self.turnContextPattern),
                   let model = self.extractString(base, range: range, key: self.modelKey),
                   !model.isEmpty {
                    currentModel = model
                    return
                }

                guard self.contains(base, range: range, pattern: self.eventMsgPattern) else {
                    return
                }

                if self.contains(base, range: range, pattern: self.taskStartedPattern) {
                    turns.append(timestamp)
                    return
                }

                guard self.contains(base, range: range, pattern: self.tokenCountPattern) else {
                    return
                }

                let currentTotal = Usage(
                    input: self.extractInt64(base, range: range, key: self.inputKey),
                    cachedInput: self.extractInt64(base, range: range, key: self.cachedInputKey),
                    output: self.extractInt64(base, range: range, key: self.outputKey),
                    reasoningOutput: self.extractInt64(base, range: range, key: self.reasoningOutputKey),
                    total: self.extractInt64(base, range: range, key: self.totalKey)
                )
                let delta = Usage.delta(from: previousTotal, to: currentTotal)
                previousTotal = currentTotal
                guard !awaitingSubagentBoundary else { return }
                guard delta.total > 0 || delta.input > 0 || delta.output > 0 else {
                    return
                }

                var limitID: String?
                var limitName: String?
                if self.contains(base, range: range, pattern: self.rateLimitsPattern) {
                    limitID = self.extractString(base, range: range, key: self.limitIDKey) ?? "unknown"
                    if let name = self.extractString(base, range: range, key: self.limitNameKey), !name.isEmpty {
                        limitName = "\(limitID ?? "unknown") (\(name))"
                    } else {
                        limitName = limitID
                    }
                }

                events.append(TokenEvent(timestamp: timestamp, usage: delta, limitID: limitID, limitName: limitName, model: currentModel))
            }

            for index in 0..<count {
                if base[index] == 10 {
                    handleLine(index)
                    lineStart = index + 1
                }
            }
            if lineStart < count {
                handleLine(count)
            }
        }

        return (events, turns)
    }

    private func contains(_ base: UnsafePointer<UInt8>, range: Range<Int>, pattern: [UInt8]) -> Bool {
        find(base, range: range, pattern: pattern) != nil
    }

    private func find(_ base: UnsafePointer<UInt8>, range: Range<Int>, pattern: [UInt8]) -> Int? {
        guard !pattern.isEmpty, range.count >= pattern.count else { return nil }
        let lastStart = range.upperBound - pattern.count
        var index = range.lowerBound
        while index <= lastStart {
            if base[index] == pattern[0] {
                var matched = true
                for offset in 1..<pattern.count where base[index + offset] != pattern[offset] {
                    matched = false
                    break
                }
                if matched { return index }
            }
            index += 1
        }
        return nil
    }

    private func extractString(_ base: UnsafePointer<UInt8>, range: Range<Int>, key: [UInt8]) -> String? {
        guard let keyIndex = find(base, range: range, pattern: key) else { return nil }
        let start = keyIndex + key.count
        var end = start
        while end < range.upperBound, base[end] != 34 {
            end += 1
        }
        guard end > start, end < range.upperBound else { return nil }
        return String(decoding: UnsafeBufferPointer(start: base + start, count: end - start), as: UTF8.self)
    }

    private func extractInt64(_ base: UnsafePointer<UInt8>, range: Range<Int>, key: [UInt8]) -> Int64 {
        guard let keyIndex = find(base, range: range, pattern: key) else { return 0 }
        var index = keyIndex + key.count
        var value: Int64 = 0
        var found = false
        while index < range.upperBound {
            let byte = base[index]
            guard byte >= 48, byte <= 57 else { break }
            value = value * 10 + Int64(byte - 48)
            found = true
            index += 1
        }
        return found ? value : 0
    }

    private func extractString(_ line: String, key: String) -> String? {
        guard let keyRange = line.range(of: key) else { return nil }
        let start = keyRange.upperBound
        guard let end = line[start...].firstIndex(of: "\"") else { return nil }
        return String(line[start..<end])
    }

    private func extractInt64(_ line: String, key: String) -> Int64 {
        guard let keyRange = line.range(of: key) else { return 0 }
        var index = keyRange.upperBound
        var value = ""
        while index < line.endIndex {
            let char = line[index]
            if char < "0" || char > "9" {
                break
            }
            value.append(char)
            index = line.index(after: index)
        }
        return Int64(value) ?? 0
    }

    private func jsonObject(from line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private func parseDate(_ value: String) -> Date? {
        if let date = isoFormatter.date(from: value) {
            return date
        }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: value)
    }

    private func usage(from dict: [String: Any]) -> Usage {
        Usage(
            input: int64(dict["input_tokens"]),
            cachedInput: int64(dict["cached_input_tokens"]),
            output: int64(dict["output_tokens"]),
            reasoningOutput: int64(dict["reasoning_output_tokens"]),
            total: int64(dict["total_tokens"])
        )
    }

    private func int64(_ value: Any?) -> Int64 {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? Double { return Int64(value) }
        if let value = value as? String { return Int64(value) ?? 0 }
        return 0
    }
}

private struct CodexBackendCredentials {
    let accessToken: String
    let accountID: String
}

private final class CodexBackendHTTPClient {
    static let shared = CodexBackendHTTPClient()

    private struct EndpointState {
        var data: Data?
        var fetchedAt: Date?
        var failureCount = 0
        var retryNotBefore: Date?
    }

    private let baseURL = URL(string: "https://chatgpt.com/backend-api")!
    private let lock = NSLock()
    private var states: [String: EndpointState] = [:]
    private let failureBackoff: [TimeInterval] = [60, 300, 900]

    func get(path: String, timeout: TimeInterval, cacheTTL: TimeInterval) -> Data? {
        let now = Date()
        lock.lock()
        let state = states[path]
        if let data = state?.data,
           let fetchedAt = state?.fetchedAt,
           now.timeIntervalSince(fetchedAt) < cacheTTL {
            lock.unlock()
            return data
        }
        if let retryAt = state?.retryNotBefore, retryAt > now {
            lock.unlock()
            return nil
        }
        lock.unlock()

        guard let credentials = credentials() else {
            recordFailure(path: path)
            return nil
        }
        let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codex-cli", forHTTPHeaderField: "User-Agent")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration)
        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var statusCode = 0
        let task = session.dataTask(with: request) { data, response, _ in
            responseData = data
            statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            semaphore.signal()
        }
        task.resume()
        if semaphore.wait(timeout: .now() + timeout + 1) == .timedOut {
            task.cancel()
        }
        session.invalidateAndCancel()

        guard statusCode == 200, let responseData else {
            recordFailure(path: path)
            return nil
        }
        lock.lock()
        states[path] = EndpointState(data: responseData, fetchedAt: Date())
        lock.unlock()
        return responseData
    }

    private func credentials() -> CodexBackendCredentials? {
        for homeURL in AppSettings.codexAPISourceHomeURLs {
            let authURL = homeURL.appendingPathComponent("auth.json")
            guard let data = try? Data(contentsOf: authURL),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            let mode = (object["auth_mode"] as? String ?? object["authMode"] as? String)?.lowercased()
            guard mode == nil || mode == "chatgpt" else { continue }
            let tokens = object["tokens"] as? [String: Any]
            let accessToken = tokens?["access_token"] as? String ?? object["access_token"] as? String
            let accountID = tokens?["account_id"] as? String ?? object["account_id"] as? String
            if let accessToken, !accessToken.isEmpty, let accountID, !accountID.isEmpty {
                return CodexBackendCredentials(accessToken: accessToken, accountID: accountID)
            }
        }
        return nil
    }

    private func recordFailure(path: String) {
        lock.lock()
        var state = states[path] ?? EndpointState()
        state.failureCount += 1
        let index = min(state.failureCount - 1, failureBackoff.count - 1)
        state.retryNotBefore = Date().addingTimeInterval(failureBackoff[index])
        states[path] = state
        lock.unlock()
    }
}

private enum AccountUsageCacheStore {
    private static let version = 1
    private struct Payload: Codable { let version: Int; let snapshot: AccountUsageSnapshot }
    private static var url: URL { AppSettings.appSupportDirectoryURL.appendingPathComponent("account-usage-cache.json") }

    static func read() -> AccountUsageSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.version == version else { return nil }
        return payload.snapshot
    }

    static func write(_ snapshot: AccountUsageSnapshot) {
        guard let data = try? JSONEncoder().encode(Payload(version: version, snapshot: snapshot)) else { return }
        try? FileManager.default.createDirectory(at: AppSettings.appSupportDirectoryURL, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

private enum ResetCreditsCacheStore {
    private static let version = 1
    private struct Payload: Codable { let version: Int; let snapshot: RateLimitResetCreditsSnapshot }
    private static var url: URL { AppSettings.appSupportDirectoryURL.appendingPathComponent("reset-credits-cache.json") }

    static func read() -> RateLimitResetCreditsSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.version == version else { return nil }
        return payload.snapshot
    }

    static func write(_ snapshot: RateLimitResetCreditsSnapshot) {
        guard let data = try? JSONEncoder().encode(Payload(version: version, snapshot: snapshot)) else { return }
        try? FileManager.default.createDirectory(at: AppSettings.appSupportDirectoryURL, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

final class LiveRateLimitReader {
    func read(timeout: TimeInterval = 12) -> [LiveRateLimit] {
        guard let data = CodexBackendHTTPClient.shared.get(path: "/wham/usage", timeout: timeout, cacheTTL: 10),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var results: [LiveRateLimit] = []
        if let rateLimit = object["rate_limit"] as? [String: Any],
           let limit = liveLimit(id: "codex", name: "Codex", rateLimit: rateLimit, planType: object["plan_type"] as? String) {
            results.append(limit)
        }
        for item in object["additional_rate_limits"] as? [[String: Any]] ?? [] {
            guard let rateLimit = item["rate_limit"] as? [String: Any] else { continue }
            let id = item["metered_feature"] as? String ?? item["limit_name"] as? String ?? "codex-additional"
            let name = item["limit_name"] as? String ?? id
            if let limit = liveLimit(id: id, name: name, rateLimit: rateLimit, planType: object["plan_type"] as? String) {
                results.append(limit)
            }
        }
        return results.sorted { $0.id < $1.id }
    }

    private func liveLimit(id: String, name: String, rateLimit: [String: Any], planType: String?) -> LiveRateLimit? {
        let rawPrimary = (rateLimit["primary_window"] as? [String: Any]).flatMap(window(from:))
        let rawSecondary = (rateLimit["secondary_window"] as? [String: Any]).flatMap(window(from:))
        let windows = normalizedWindows(primary: rawPrimary, secondary: rawSecondary)
        guard windows.primary != nil || windows.secondary != nil else {
            return nil
        }
        return LiveRateLimit(
            id: id,
            name: name,
            primary: windows.primary,
            secondary: windows.secondary,
            planType: planType,
            capturedAt: Date()
        )
    }

    private func normalizedWindows(
        primary: RateWindow?,
        secondary: RateWindow?
    ) -> (primary: RateWindow?, secondary: RateWindow?) {
        let windows = [primary, secondary].compactMap { $0 }
        let fiveHour = windows.first { abs($0.windowMinutes - 5 * 60) <= 60 }
        let weekly = windows.first { abs($0.windowMinutes - 7 * 24 * 60) <= 24 * 60 }

        // Preserve the provider's traditional slot for unknown durations while
        // allowing promotional plans to omit either the 5h or weekly window.
        return (
            fiveHour ?? primary.flatMap { weekly?.windowMinutes == $0.windowMinutes ? nil : $0 },
            weekly ?? secondary.flatMap { fiveHour?.windowMinutes == $0.windowMinutes ? nil : $0 }
        )
    }

    private func window(from dict: [String: Any]) -> RateWindow? {
        guard let used = optionalDouble(dict["used_percent"]),
              used.isFinite else {
            return nil
        }
        let minutes = Int((optionalDouble(dict["limit_window_seconds"]) ?? 0) / 60)
        guard minutes > 0 else { return nil }
        let resetSeconds = optionalDouble(dict["reset_at"]) ?? 0
        let resetDate = resetSeconds > 0 ? Date(timeIntervalSince1970: resetSeconds) : nil
        return RateWindow(usedPercent: used, windowMinutes: minutes, resetsAt: resetDate)
    }

    private func optionalDouble(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? Int64 { return Double(value) }
        if let value = value as? String { return Double(value) }
        return nil
    }
}

final class AccountUsageReader {
    func read(timeout: TimeInterval = 12) -> AccountUsageSnapshot? {
        guard let data = CodexBackendHTTPClient.shared.get(path: "/wham/profiles/me", timeout: timeout, cacheTTL: 300),
              let snapshot = parse(data) else { return AccountUsageCacheStore.read() }
        AccountUsageCacheStore.write(snapshot)
        return snapshot
    }

    private func parse(_ data: Data) -> AccountUsageSnapshot? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stats = object["stats"] as? [String: Any] else { return nil }
        let buckets = (stats["daily_usage_buckets"] as? [[String: Any]] ?? []).compactMap { dict -> AccountUsageDailyBucket? in
            guard let startDate = dict["start_date"] as? String,
                  let tokens = int64(dict["tokens"]) else { return nil }
            return AccountUsageDailyBucket(startDate: startDate, tokens: tokens)
        }
        let summary = AccountUsageSummary(
            lifetimeTokens: int64(stats["lifetime_tokens"]),
            peakDailyTokens: int64(stats["peak_daily_tokens"]),
            longestRunningTurnSec: int64(stats["longest_running_turn_sec"]),
            currentStreakDays: int64(stats["current_streak_days"]),
            longestStreakDays: int64(stats["longest_streak_days"])
        )
        return AccountUsageSnapshot(summary: summary, dailyUsageBuckets: buckets.sorted { $0.startDate < $1.startDate }, readAt: Date())
    }

    private func int64(_ value: Any?) -> Int64? {
        if value == nil || value is NSNull { return nil }
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? Double { return Int64(value) }
        if let value = value as? String { return Int64(value) }
        return nil
    }
}

final class RateLimitResetCreditsReader {
    private let isoWithFractional = ISO8601DateFormatter()
    private let isoBasic = ISO8601DateFormatter()

    init() {
        isoWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        isoBasic.formatOptions = [.withInternetDateTime]
    }

    func read(timeout: TimeInterval = 12) -> RateLimitResetCreditsSnapshot? {
        if let data = CodexBackendHTTPClient.shared.get(path: "/wham/rate-limit-reset-credits", timeout: timeout, cacheTTL: 300),
           let snapshot = parsePrivateResponse(data) {
            ResetCreditsCacheStore.write(snapshot)
            return snapshot
        }
        if let data = CodexBackendHTTPClient.shared.get(path: "/wham/usage", timeout: timeout, cacheTTL: 10),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let summary = object["rate_limit_reset_credits"] as? [String: Any],
           let availableCount = int(summary["available_count"]) {
            let snapshot = RateLimitResetCreditsSnapshot(
                availableCount: max(0, availableCount),
                totalEarnedCount: int(summary["total_earned_count"]),
                credits: [],
                readAt: Date(),
                source: "chatgpt-wham-usage"
            )
            ResetCreditsCacheStore.write(snapshot)
            return snapshot
        }
        return ResetCreditsCacheStore.read()
    }

    private func parsePrivateResponse(_ data: Data) -> RateLimitResetCreditsSnapshot? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let creditsRaw = object["credits"] as? [[String: Any]]
            ?? object["data"] as? [[String: Any]]
            ?? []
        let credits = creditsRaw.compactMap(parseCredit)
        let availableCount = int(object["available_count"] ?? object["availableCount"])
            ?? credits.filter(\.isAvailable).count
        let totalEarnedCount = int(object["total_earned_count"] ?? object["totalEarnedCount"])
        return RateLimitResetCreditsSnapshot(
            availableCount: max(0, availableCount),
            totalEarnedCount: totalEarnedCount,
            credits: credits.sorted {
                ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture)
            },
            readAt: Date(),
            source: "chatgpt-wham"
        )
    }

    private func parseCredit(_ dict: [String: Any]) -> RateLimitResetCredit? {
        let status = dict["status"] as? String ?? "available"
        let grantedAt = parseDate(dict["granted_at"] ?? dict["grantedAt"])
        let explicitExpiresAt = parseDate(dict["expires_at"] ?? dict["expiresAt"])
        let expiresAt = explicitExpiresAt ?? grantedAt?.addingTimeInterval(30 * 24 * 60 * 60)
        guard grantedAt != nil || expiresAt != nil else {
            return nil
        }
        return RateLimitResetCredit(
            status: status,
            grantedAt: grantedAt,
            expiresAt: expiresAt,
            expirationIsEstimated: explicitExpiresAt == nil && grantedAt != nil
        )
    }

    private func parseDate(_ raw: Any?) -> Date? {
        if let value = raw as? Date {
            return value
        }
        if let value = raw as? Double, value > 0 {
            return Date(timeIntervalSince1970: value > 1_000_000_000_000 ? value / 1000 : value)
        }
        if let value = raw as? Int, value > 0 {
            let seconds = Double(value)
            return Date(timeIntervalSince1970: seconds > 1_000_000_000_000 ? seconds / 1000 : seconds)
        }
        guard let string = raw as? String, !string.isEmpty else {
            return nil
        }
        if let date = isoWithFractional.date(from: string) {
            return date
        }
        if let date = isoBasic.date(from: string) {
            return date
        }
        if let seconds = Double(string), seconds > 0 {
            return Date(timeIntervalSince1970: seconds > 1_000_000_000_000 ? seconds / 1000 : seconds)
        }
        return nil
    }

    private func int(_ value: Any?) -> Int? {
        if value == nil || value is NSNull { return nil }
        if let value = value as? Int { return value }
        if let value = value as? Int64 { return Int(value) }
        if let value = value as? Double { return Int(value) }
        if let value = value as? String { return Int(value) }
        return nil
    }
}
