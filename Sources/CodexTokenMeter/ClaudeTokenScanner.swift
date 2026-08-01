import Cocoa
import Foundation
import ServiceManagement
import UserNotifications

// MARK: - Claude Code Scanner

final class ClaudeTokenScanner {
    private struct ClaudeTurn {
        let timestamp: Date
        let key: String
    }

    private struct ClaudeEvent {
        let timestamp: Date
        let usage: Usage
        let model: String
        let sessionID: String
        let messageID: String
        let requestID: String?
        let isSidechain: Bool

        var key: String { "\(sessionID)|\(messageID)" }
        var exactKey: String { "\(sessionID)|\(messageID)|\(requestID ?? "")" }
    }

    private struct ParsedClaudeFile {
        let sessionID: String
        let cwd: String?
        let events: [ClaudeEvent]
        let turns: [ClaudeTurn]
    }

    private struct RepoConversation {
        var cwd: String?
        var conversations = 1
        var turns = 0
        var tokens: Int64 = 0
        var completedTurns = 0
        var activeDays: Set<String> = []
        var days: [String: RepoInsightDay] = [:]
        var hours: [Int: RepoInsightHour] = [:]
    }

    private struct RepoAccumulator {
        let key: String
        let displayName: String
        var primaryFolder: String
        var folders: Set<String> = []
        var conversations = 0
        var turns = 0
        var tokens: Int64 = 0
        var completedTurns = 0
        var activeDays: Set<String> = []
        var turnBuckets = RepoInsightTurnBuckets()
        var compressionBuckets = RepoInsightCompressionBuckets()
        var days: [String: RepoInsightDay] = [:]
        var hours: [Int: RepoInsightHour] = [:]

        mutating func add(_ conversation: RepoConversation) {
            conversations += conversation.conversations
            turns += conversation.turns
            tokens += conversation.tokens
            completedTurns += conversation.completedTurns
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
            compressionBuckets.zero += 1

            for day in conversation.days.values {
                var existing = days[day.day] ?? RepoInsightDay(day: day.day, conversations: 0, turns: 0, compressions: 0)
                existing.conversations += day.conversations
                existing.turns += day.turns
                existing.compressions += day.compressions
                days[day.day] = existing
            }

            for hour in conversation.hours.values {
                var existing = hours[hour.hour] ?? RepoInsightHour(hour: hour.hour, conversations: 0, turns: 0, tokens: 0)
                existing.conversations += hour.conversations
                existing.turns += hour.turns
                existing.tokens += hour.tokens
                hours[hour.hour] = existing
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
                compressions: 0,
                tokens: tokens,
                conversationsWithCompression: 0,
                longestTurns: turns,
                longestTokens: tokens,
                maxCompressions: 0,
                abortedTurns: 0,
                completedTurns: completedTurns,
                activeDays: activeDays,
                turnBuckets: turnBuckets,
                compressionBuckets: compressionBuckets,
                days: days.values.sorted { $0.day < $1.day },
                hours: hours.values.sorted { $0.hour < $1.hour }
            )
        }
    }

    private let rootURLs: [URL]
    private let isoFormatter: ISO8601DateFormatter
    private let dayFormatter: DateFormatter
    private let calendar: Calendar
    init(rootURLs: [URL] = AppSettings.claudeLogFolderURLs) {
        self.rootURLs = Self.uniqueRootURLs(rootURLs)
        self.isoFormatter = ISO8601DateFormatter()
        self.isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.dayFormatter = DateFormatter()
        self.dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        self.dayFormatter.timeZone = appTimeZone()
        self.dayFormatter.dateFormat = "yyyy-MM-dd"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = appTimeZone()
        self.calendar = calendar
    }

    var rootPaths: [String] {
        rootURLs.map(\.path)
    }

    func scan(window: WindowOption) -> TokenReport {
        let now = Date()
        switch window {
        case .day:
            return scan(start: now.addingTimeInterval(-24 * 3600), now: now, fillDayCount: nil)
        case .week:
            let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -6, to: now) ?? now)
            return scan(start: start, now: now, fillDayCount: 7)
        case .month:
            let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -29, to: now) ?? now)
            return scan(start: start, now: now, fillDayCount: 30)
        }
    }

    func scan(hours: Int) -> TokenReport {
        let now = Date()
        return scan(start: now.addingTimeInterval(TimeInterval(-hours * 3600)), now: now, fillDayCount: nil)
    }

    func scan(days: Int) -> TokenReport {
        let now = Date()
        let dayCount = max(days, 1)
        let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -(dayCount - 1), to: now) ?? now)
        return scan(start: start, now: now, fillDayCount: dayCount)
    }

    func scanWithRepoInsights(days: Int, insightWindows: [Int]) -> (report: TokenReport, repoInsights: [Int: RepoInsightsReport]) {
        let now = Date()
        let dayCount = max(days, 1)
        let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -(dayCount - 1), to: now) ?? now)
        let windowDays = Array(Set(insightWindows.map { max($0, 1) })).sorted()
        let starts = Dictionary(uniqueKeysWithValues: windowDays.map { days in
            (days, calendar.startOfDay(for: calendar.date(byAdding: .day, value: -(days - 1), to: now) ?? now))
        })
        let fileStart = min(start, starts.values.min() ?? start)
        var aggregateByWindow: [Int: [String: RepoAccumulator]] = [:]
        let report = scan(start: start, now: now, fillDayCount: dayCount, fileStart: fileStart) { parsed in
            self.accumulateRepoInsights(
                parsed: parsed,
                starts: starts,
                now: now,
                aggregateByWindow: &aggregateByWindow
            )
        }
        return (
            report,
            repoInsightsReports(aggregateByWindow: aggregateByWindow, windowDays: windowDays, now: now)
        )
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
        var aggregateByWindow: [Int: [String: RepoAccumulator]] = [:]

        for fileURL in logFiles(modifiedSince: earliestStart) {
            accumulateRepoInsights(
                parsed: parse(fileURL: fileURL),
                starts: starts,
                now: now,
                aggregateByWindow: &aggregateByWindow
            )
        }

        return repoInsightsReports(aggregateByWindow: aggregateByWindow, windowDays: windowDays, now: now)
    }

    private func accumulateRepoInsights(
        parsed: ParsedClaudeFile,
        starts: [Int: Date],
        now: Date,
        aggregateByWindow: inout [Int: [String: RepoAccumulator]]
    ) {
        for (days, start) in starts {
            let conversation = repoConversation(from: parsed, start: start, now: now)
            guard conversation.turns > 0 || conversation.tokens > 0 else { continue }
            let cwd = conversation.cwd ?? "(unknown)"
            let key = repoInsightKey(for: cwd)
            var rows = aggregateByWindow[days] ?? [:]
            var accumulator = rows[key] ?? RepoAccumulator(key: key, displayName: repoInsightDisplayName(for: key), primaryFolder: cwd)
            accumulator.add(conversation)
            rows[key] = accumulator
            aggregateByWindow[days] = rows
        }
    }

    private func repoInsightsReports(
        aggregateByWindow: [Int: [String: RepoAccumulator]],
        windowDays: [Int],
        now: Date
    ) -> [Int: RepoInsightsReport] {
        Dictionary(uniqueKeysWithValues: windowDays.map { days in
            let rows = (aggregateByWindow[days] ?? [:]).values
                .map { $0.repoInsight() }
                .sorted {
                    if $0.conversations != $1.conversations {
                        return $0.conversations > $1.conversations
                    }
                    if $0.tokens != $1.tokens {
                        return $0.tokens > $1.tokens
                    }
                    return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
            return (days, RepoInsightsReport(rows: rows, scannedAt: now, windowDays: days))
        })
    }

    private func scan(
        start: Date,
        now: Date,
        fillDayCount: Int?,
        fileStart: Date? = nil,
        parsedFileHandler: ((ParsedClaudeFile) -> Void)? = nil
    ) -> TokenReport {
        var report = TokenReport(scannedAt: now)
        var seenEvents = Set<String>()
        var seenTurns = Set<String>()
        var sessionIDs = Set<String>()
        var dayBuckets: [String: Usage] = [:]
        var dayTurns: [String: Int] = [:]
        var daySessionIDs: [String: Set<String>] = [:]
        var dayEvents: [String: Int] = [:]
        var dayModelBuckets: [String: [String: Usage]] = [:]
        var dayModelTurns: [String: [String: Int]] = [:]
        var dayModelEvents: [String: [String: Int]] = [:]
        var dayModelSessions: [String: [String: Int]] = [:]
        var hourBuckets: [Date: Usage] = [:]
        var hourTurns: [Date: Int] = [:]
        var modelBuckets: [String: Usage] = [:]
        var modelTurns: [String: Int] = [:]
        var modelEvents: [String: Int] = [:]
        var modelSessions: [String: Int] = [:]
        var sessions: [SessionUsage] = []

        for fileURL in logFiles(modifiedSince: fileStart ?? start) {
            let parsed = parse(fileURL: fileURL)
            parsedFileHandler?(parsed)
            var sessionUsage = Usage()
            var sessionTurns = 0
            var sessionModels = Set<String>()
            var sessionDayModels: [String: Set<String>] = [:]
            var sessionDays = Set<String>()
            var lastEvent = now
            var hasActivity = false
            let attributedTurns = attributedModelTurns(turns: parsed.turns, events: parsed.events)

            for turn in parsed.turns where turn.timestamp >= start && turn.timestamp <= now {
                guard seenTurns.insert(turn.key).inserted else { continue }
                hasActivity = true
                sessionTurns += 1
                let day = dayFormatter.string(from: turn.timestamp)
                sessionDays.insert(day)
                dayTurns[day, default: 0] += 1
                if let modelName = attributedTurns[turn.key] {
                    modelTurns[modelName, default: 0] += 1
                    var turnsForDay = dayModelTurns[day] ?? [:]
                    turnsForDay[modelName, default: 0] += 1
                    dayModelTurns[day] = turnsForDay
                }
                let hour = calendar.dateInterval(of: .hour, for: turn.timestamp)?.start ?? turn.timestamp
                hourTurns[hour, default: 0] += 1
            }

            for event in parsed.events where event.timestamp >= start && event.timestamp <= now {
                guard seenEvents.insert(event.key).inserted else { continue }
                hasActivity = true
                lastEvent = event.timestamp
                sessionUsage.add(event.usage)
                sessionModels.insert(event.model)

                var modelUsage = modelBuckets[event.model] ?? Usage()
                modelUsage.add(event.usage)
                modelBuckets[event.model] = modelUsage
                modelEvents[event.model, default: 0] += 1

                let day = dayFormatter.string(from: event.timestamp)
                sessionDays.insert(day)
                dayEvents[day, default: 0] += 1
                sessionDayModels[day, default: []].insert(event.model)
                var dayUsage = dayBuckets[day] ?? Usage()
                dayUsage.add(event.usage)
                dayBuckets[day] = dayUsage

                var dayModels = dayModelBuckets[day] ?? [:]
                var dayModelUsage = dayModels[event.model] ?? Usage()
                dayModelUsage.add(event.usage)
                dayModels[event.model] = dayModelUsage
                dayModelBuckets[day] = dayModels

                var dayEvents = dayModelEvents[day] ?? [:]
                dayEvents[event.model, default: 0] += 1
                dayModelEvents[day] = dayEvents

                let hour = calendar.dateInterval(of: .hour, for: event.timestamp)?.start ?? event.timestamp
                var hourUsage = hourBuckets[hour] ?? Usage()
                hourUsage.add(event.usage)
                hourBuckets[hour] = hourUsage
            }

            guard hasActivity else { continue }
            sessionIDs.insert(parsed.sessionID)
            for day in sessionDays {
                daySessionIDs[day, default: []].insert(parsed.sessionID)
            }
            report.turns += sessionTurns
            report.usage.add(sessionUsage)
            sessions.append(SessionUsage(path: fileURL.path, lastEvent: lastEvent, turns: sessionTurns, usage: sessionUsage))
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

        report.sessions = sessionIDs.count
        report.events = seenEvents.count
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
                        turns: dayModelTurns[day]?[name] ?? 0,
                        events: dayModelEvents[day]?[name] ?? 0,
                        sessions: dayModelSessions[day]?[name] ?? 0
                    )
                }
                .sorted { $0.usage.total > $1.usage.total }
                return DayUsage(
                    day: day,
                    usage: dayBuckets[day] ?? Usage(),
                    turns: dayTurns[day] ?? 0,
                    sessions: daySessionIDs[day]?.count ?? 0,
                    events: dayEvents[day] ?? 0,
                    modelBreakdown: models
                )
            }
            .sorted { $0.day < $1.day }
        let hours = Set(hourBuckets.keys).union(hourTurns.keys)
        report.byHour = hours
            .map { HourUsage(hour: $0, usage: hourBuckets[$0] ?? Usage(), turns: hourTurns[$0] ?? 0) }
            .sorted { $0.hour < $1.hour }
        report.modelBreakdown = modelBuckets.map { name, usage in
            ModelUsage(name: name, usage: usage, turns: modelTurns[name] ?? 0, events: modelEvents[name] ?? 0, sessions: modelSessions[name] ?? 0)
        }
        .sorted { $0.usage.total > $1.usage.total }
        report.topSessions = sessions.sorted { $0.usage.total > $1.usage.total }.prefix(8).map { $0 }
        return report
    }

    private func repoConversation(from parsed: ParsedClaudeFile, start: Date, now: Date) -> RepoConversation {
        var conversation = RepoConversation(cwd: parsed.cwd)
        var seenEventKeys = Set<String>()
        var seenTurnKeys = Set<String>()
        for turn in parsed.turns where turn.timestamp >= start && turn.timestamp <= now {
            guard seenTurnKeys.insert(turn.key).inserted else { continue }
            conversation.turns += 1
            let day = dayFormatter.string(from: turn.timestamp)
            conversation.activeDays.insert(day)
            var row = conversation.days[day] ?? RepoInsightDay(day: day, conversations: 0, turns: 0, compressions: 0)
            row.turns += 1
            conversation.days[day] = row
            let hour = calendar.component(.hour, from: turn.timestamp)
            var hourRow = conversation.hours[hour] ?? RepoInsightHour(hour: hour, conversations: 1, turns: 0, tokens: 0)
            hourRow.turns += 1
            conversation.hours[hour] = hourRow
        }
        for event in parsed.events where event.timestamp >= start && event.timestamp <= now {
            guard seenEventKeys.insert(event.key).inserted else { continue }
            conversation.tokens += event.usage.total
            conversation.completedTurns += 1
            let day = dayFormatter.string(from: event.timestamp)
            conversation.activeDays.insert(day)
            let hour = calendar.component(.hour, from: event.timestamp)
            var hourRow = conversation.hours[hour] ?? RepoInsightHour(hour: hour, conversations: 1, turns: 0, tokens: 0)
            hourRow.tokens += event.usage.total
            conversation.hours[hour] = hourRow
        }
        for day in conversation.activeDays {
            var row = conversation.days[day] ?? RepoInsightDay(day: day, conversations: 0, turns: 0, compressions: 0)
            row.conversations = 1
            conversation.days[day] = row
        }
        return conversation
    }

    private func parse(fileURL: URL) -> ParsedClaudeFile {
        guard let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]),
              let text = String(data: data, encoding: .utf8) else {
            return ParsedClaudeFile(sessionID: fileURL.deletingPathExtension().lastPathComponent, cwd: nil, events: [], turns: [])
        }

        var eventBuckets: [String: ClaudeEvent] = [:]
        var turns: [ClaudeTurn] = []
        var sessionID = fileURL.deletingPathExtension().lastPathComponent
        var cwdCounts: [String: Int] = [:]

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }
            if let value = object["sessionId"] as? String, !value.isEmpty {
                sessionID = value
            }
            if let cwd = object["cwd"] as? String, !cwd.isEmpty {
                cwdCounts[cwd, default: 0] += 1
            }
            guard let timestampString = object["timestamp"] as? String,
                  let timestamp = parseDate(timestampString),
                  let type = object["type"] as? String else {
                continue
            }
            if type == "user" {
                let uuid = object["uuid"] as? String ?? "\(sessionID)-\(timestampString)"
                turns.append(ClaudeTurn(timestamp: timestamp, key: "\(sessionID)|\(uuid)"))
                continue
            }
            guard type == "assistant",
                  let message = object["message"] as? [String: Any],
                  let usageDict = message["usage"] as? [String: Any] else {
                continue
            }
            let messageID = message["id"] as? String
                ?? object["requestId"] as? String
                ?? object["uuid"] as? String
                ?? "\(sessionID)-\(timestampString)"
            let requestID = object["requestId"] as? String
            let isSidechain = object["isSidechain"] as? Bool ?? false
            let model = (message["model"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Claude"
            let usage = usage(from: usageDict)
            guard usage.total > 0 || usage.input > 0 || usage.output > 0 else { continue }
            let event = ClaudeEvent(timestamp: timestamp, usage: usage, model: model, sessionID: sessionID, messageID: messageID, requestID: requestID, isSidechain: isSidechain)
            let exactKey = event.exactKey
            if let existing = eventBuckets[exactKey] {
                if shouldReplace(existing: existing, with: event) {
                    eventBuckets[exactKey] = event
                }
            } else {
                eventBuckets[exactKey] = event
            }
        }

        let events = dedupedEvents(Array(eventBuckets.values))
        let cwd = cwdCounts.max {
            if $0.value != $1.value { return $0.value < $1.value }
            return $0.key > $1.key
        }?.key
        return ParsedClaudeFile(sessionID: sessionID, cwd: cwd, events: events, turns: turns)
    }

    private func dedupedEvents(_ events: [ClaudeEvent]) -> [ClaudeEvent] {
        var buckets: [String: ClaudeEvent] = [:]
        for event in events {
            if let existing = buckets[event.key] {
                if shouldReplace(existing: existing, with: event) {
                    buckets[event.key] = event
                }
            } else {
                buckets[event.key] = event
            }
        }
        return buckets.values.sorted { $0.timestamp < $1.timestamp }
    }

    private func attributedModelTurns(turns: [ClaudeTurn], events: [ClaudeEvent]) -> [String: String] {
        let sortedTurns = turns.sorted { $0.timestamp < $1.timestamp }
        let sortedEvents = events.sorted { $0.timestamp < $1.timestamp }
        guard !sortedTurns.isEmpty, !sortedEvents.isEmpty else { return [:] }

        var result: [String: String] = [:]
        var eventIndex = 0
        for (turnIndex, turn) in sortedTurns.enumerated() {
            let nextTurn = turnIndex + 1 < sortedTurns.count ? sortedTurns[turnIndex + 1].timestamp : .distantFuture
            while eventIndex < sortedEvents.count && sortedEvents[eventIndex].timestamp < turn.timestamp {
                eventIndex += 1
            }

            var usageByModel: [String: Int64] = [:]
            var scanIndex = eventIndex
            while scanIndex < sortedEvents.count && sortedEvents[scanIndex].timestamp < nextTurn {
                let event = sortedEvents[scanIndex]
                usageByModel[event.model, default: 0] += max(event.usage.total, 1)
                scanIndex += 1
            }
            if let modelName = usageByModel.max(by: { $0.value < $1.value })?.key {
                result[turn.key] = modelName
            }
            eventIndex = scanIndex
        }
        return result
    }

    private func shouldReplace(existing: ClaudeEvent, with candidate: ClaudeEvent) -> Bool {
        if existing.isSidechain != candidate.isSidechain {
            return existing.isSidechain
        }
        if existing.usage.total != candidate.usage.total {
            return candidate.usage.total > existing.usage.total
        }
        if candidate.usage.input != existing.usage.input {
            return candidate.usage.input > existing.usage.input
        }
        return candidate.timestamp > existing.timestamp
    }

    private func usage(from dict: [String: Any]) -> Usage {
        let freshInput = int64(dict["input_tokens"])
        let cacheCreation = int64(dict["cache_creation_input_tokens"]) + int64((dict["cache_creation"] as? [String: Any])?["ephemeral_5m_input_tokens"])
        let cacheCreation1h = int64((dict["cache_creation"] as? [String: Any])?["ephemeral_1h_input_tokens"])
        let cacheRead = int64(dict["cache_read_input_tokens"])
        let output = int64(dict["output_tokens"])
        let inputTotal = freshInput + cacheCreation + cacheCreation1h + cacheRead
        return Usage(
            input: inputTotal,
            cachedInput: cacheRead,
            cacheCreationInput: cacheCreation,
            cacheCreationInput1h: cacheCreation1h,
            output: output,
            reasoningOutput: 0,
            total: inputTotal + output
        )
    }

    private func logFiles(modifiedSince start: Date) -> [URL] {
        var files: [URL] = []
        var seen = Set<String>()
        for rootURL in rootURLs {
            for url in logFiles(in: rootURL, modifiedSince: start) {
                let key = (url.path as NSString).standardizingPath
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                files.append(url)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private func logFiles(in rootURL: URL, modifiedSince start: Date) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL, url.pathExtension == "jsonl" else { return nil }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if let modifiedAt = values?.contentModificationDate, modifiedAt < start {
                return nil
            }
            return url
        }
    }

    private func parseDate(_ value: String) -> Date? {
        if let date = isoFormatter.date(from: value) {
            return date
        }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: value)
    }

    private func int64(_ value: Any?) -> Int64 {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? Double { return Int64(value) }
        if let value = value as? String { return Int64(value) ?? 0 }
        return 0
    }

    private func repoInsightKey(for cwd: String) -> String {
        let standardized = (cwd as NSString).standardizingPath
        let components = standardized.split(separator: "/").map(String.init)

        if let githubIndex = components.firstIndex(of: "GitHub"),
           components.count > githubIndex + 1 {
            return "/" + components.prefix(githubIndex + 2).joined(separator: "/")
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
        if key == "/Users/kadewu/Documents/Codex" {
            return "Codex"
        }
        if key.hasPrefix("/Users/kadewu/Documents/Codex/") {
            return "Codex/" + key.dropFirst("/Users/kadewu/Documents/Codex/".count)
        }
        if key.hasPrefix(home) {
            return "~" + key.dropFirst(home.count)
        }
        return key
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
}
