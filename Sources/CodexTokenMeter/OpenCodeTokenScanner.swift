import Foundation
import SQLite3

// MARK: - OpenCode Scanner

/// Read-only scanner for the local OpenCode / OpenChamber session database at
/// `~/.local/share/opencode/opencode.db`. Every assistant message row stores
/// that message's own token totals plus the model, provider, and timestamps;
/// tokens are per-message counts (like Claude Code), not cumulative rollout
/// counters, so they are summed directly. Subagent sessions live as separate
/// sessions in the same tables and represent real token usage, so they are
/// included. The database is opened read-only and this scanner never writes.
final class OpenCodeTokenScanner {
    static let shared = OpenCodeTokenScanner()

    struct Event {
        let timestamp: Date
        let usage: Usage
        let model: String
        let sessionKey: String
        let directory: String?
    }

    private struct Turn {
        let timestamp: Date
        let sessionKey: String
    }

    private struct ParsedData {
        let events: [Event]
        let turns: [Turn]

        var isEmpty: Bool { events.isEmpty && turns.isEmpty }
    }

    private struct ParsedCacheEntry {
        let fingerprint: String
        let parsed: ParsedData
    }

    static var defaultDatabaseURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("share", isDirectory: true)
            .appendingPathComponent("opencode", isDirectory: true)
            .appendingPathComponent("opencode.db")
    }

    /// Database path when present, so callers can surface availability.
    var databasePath: String? {
        FileManager.default.fileExists(atPath: databaseURL.path) ? databaseURL.path : nil
    }

    private let databaseURL: URL
    private let calendar = appCalendar()
    private let lock = NSLock()
    private var cacheEntry: ParsedCacheEntry?

    init(databaseURL: URL = OpenCodeTokenScanner.defaultDatabaseURL) {
        self.databaseURL = databaseURL
    }

    // MARK: Scans

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
        return scan(start: now.addingTimeInterval(TimeInterval(-max(hours, 1) * 3600)), now: now, fillDayCount: nil)
    }

    func scan(days: Int) -> TokenReport {
        let now = Date()
        let dayCount = max(days, 1)
        let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -(dayCount - 1), to: now) ?? now)
        return scan(start: start, now: now, fillDayCount: dayCount)
    }

    func scan(from start: Date, to end: Date = Date()) -> TokenReport {
        scan(start: min(start, end), now: max(start, end), fillDayCount: nil)
    }

    /// OpenCode stores reasoning-token counts but not a user-selected reasoning
    /// effort. Surface those runs explicitly as `unavailable`, never as an
    /// inferred low/medium/high setting.
    func scanReasoningInsights(days: Int) -> ReasoningInsightsReport? {
        let now = Date()
        let dayCount = max(days, 1)
        let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -(dayCount - 1), to: now) ?? now)
        return scanReasoningInsights(from: start, to: now)
    }

    func scanReasoningInsights(from start: Date, to end: Date = Date()) -> ReasoningInsightsReport? {
        let rangeStart = min(start, end)
        let rangeEnd = max(start, end)
        guard let parsed = readParsedData(), !parsed.events.isEmpty else { return nil }
        let formatter = dayFormatter()
        struct Run {
            let model: String
            let sessionKey: String
            let day: String
            let directory: String?
            var usage: Usage
        }
        var runs: [String: Run] = [:]
        for event in parsed.events where event.timestamp >= rangeStart && event.timestamp <= rangeEnd {
            let day = formatter.string(from: event.timestamp)
            let key = "\(event.sessionKey)\u{1F}\(event.model)\u{1F}\(day)"
            if var existing = runs[key] {
                existing.usage.add(event.usage)
                runs[key] = existing
            } else {
                runs[key] = Run(model: event.model, sessionKey: event.sessionKey, day: day, directory: event.directory, usage: event.usage)
            }
        }
        guard !runs.isEmpty else { return nil }

        var totalUsage = Usage()
        var modelRuns: [String: [Run]] = [:]
        var dailyRuns: [String: [Run]] = [:]
        var sessions = Set<String>()
        for run in runs.values {
            totalUsage.add(run.usage)
            modelRuns[run.model, default: []].append(run)
            dailyRuns["\(run.day)\u{1F}\(run.model)", default: []].append(run)
            sessions.insert(run.sessionKey)
        }

        func percentile(_ totals: [Int64], _ value: Double) -> Int64 {
            let sorted = totals.sorted()
            guard !sorted.isEmpty else { return 0 }
            let index = max(0, min(sorted.count - 1, Int(ceil(Double(sorted.count) * value)) - 1))
            return sorted[index]
        }
        func summary(model: String, values: [Run]) -> ReasoningModelEffortSummary {
            let totals = values.map { $0.usage.total }
            return ReasoningModelEffortSummary(
                model: model,
                effort: "unavailable",
                runs: values.count,
                tasks: Set(values.map(\.sessionKey)).count,
                projectCount: Set(values.compactMap(\.directory)).count,
                usage: values.reduce(Usage()) { partial, run in var result = partial; result.add(run.usage); return result },
                medianTokens: percentile(totals, 0.5),
                p90Tokens: percentile(totals, 0.9)
            )
        }

        let modelEfforts = modelRuns.map { summary(model: $0.key, values: $0.value) }
            .sorted { $0.model.localizedCaseInsensitiveCompare($1.model) == .orderedAscending }
        let dailyModelEfforts = dailyRuns.compactMap { key, values -> ReasoningDailyModelEffortSummary? in
            let parts = key.components(separatedBy: "\u{1F}")
            guard parts.count == 2 else { return nil }
            return ReasoningDailyModelEffortSummary(day: parts[0], model: parts[1], effort: "unavailable", runs: values.count, usage: values.reduce(Usage()) { partial, run in var result = partial; result.add(run.usage); return result }, runTokenTotals: values.map { $0.usage.total })
        }
        .sorted { $0.day == $1.day ? $0.model.localizedCaseInsensitiveCompare($1.model) == .orderedAscending : $0.day < $1.day }
        let allTotals = runs.values.map { $0.usage.total }
        let unavailable = ReasoningEffortSummary(effort: "unavailable", runs: runs.count, tasks: sessions.count, usage: totalUsage, medianTokens: percentile(allTotals, 0.5), p90Tokens: percentile(allTotals, 0.9))
        return ReasoningInsightsReport(taskCount: sessions.count, runCount: runs.count, usage: totalUsage, knownRunCount: 0, knownTokenCount: 0, efforts: [unavailable], modelEfforts: modelEfforts, dailyModelEfforts: dailyModelEfforts)
    }

    // MARK: Aggregation

    private func scan(start: Date, now: Date, fillDayCount: Int?) -> TokenReport {
        var report = TokenReport(scannedAt: now)
        guard let parsed = readParsedData(), !parsed.isEmpty else { return report }
        let formatter = dayFormatter()

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
        var sessionIDs = Set<String>()
        var sessionUsages: [String: Usage] = [:]
        var sessionLastEvents: [String: Date] = [:]
        var sessionDirectories: [String: String] = [:]
        var sessionTurns: [String: Int] = [:]
        var daySessionTurns: [String: [String: Int]] = [:]
        var sessionModels: [String: Set<String>] = [:]
        var seenDayModelSessionKeys = Set<String>()
        var eventCount = 0

        for turn in parsed.turns where turn.timestamp >= start && turn.timestamp <= now {
            let day = formatter.string(from: turn.timestamp)
            dayTurns[day, default: 0] += 1
            sessionTurns[turn.sessionKey, default: 0] += 1
            daySessionTurns[day, default: [:]][turn.sessionKey, default: 0] += 1
            let hour = calendar.dateInterval(of: .hour, for: turn.timestamp)?.start ?? turn.timestamp
            hourTurns[hour, default: 0] += 1
            report.turns += 1
        }

        for event in parsed.events where event.timestamp >= start && event.timestamp <= now {
            eventCount += 1
            let day = formatter.string(from: event.timestamp)

            sessionIDs.insert(event.sessionKey)
            sessionUsages[event.sessionKey, default: Usage()].add(event.usage)
            if let directory = event.directory, sessionDirectories[event.sessionKey] == nil {
                sessionDirectories[event.sessionKey] = directory
            }
            sessionLastEvents[event.sessionKey] = max(sessionLastEvents[event.sessionKey] ?? event.timestamp, event.timestamp)
            sessionModels[event.sessionKey, default: []].insert(event.model)
            daySessionIDs[day, default: []].insert(event.sessionKey)

            var modelsByDay = dayModelSessions[day] ?? [:]
            let dayModelSessionKey = "\(day)|\(event.model)|\(event.sessionKey)"
            if !seenDayModelSessionKeys.contains(dayModelSessionKey) {
                seenDayModelSessionKeys.insert(dayModelSessionKey)
                modelsByDay[event.model, default: 0] += 1
            }
            dayModelSessions[day] = modelsByDay

            var modelUsage = modelBuckets[event.model] ?? Usage()
            modelUsage.add(event.usage)
            modelBuckets[event.model] = modelUsage
            modelEvents[event.model, default: 0] += 1

            var dayUsage = dayBuckets[day] ?? Usage()
            dayUsage.add(event.usage)
            dayBuckets[day] = dayUsage
            dayEvents[day, default: 0] += 1

            var dayModels = dayModelBuckets[day] ?? [:]
            var dayModelUsage = dayModels[event.model] ?? Usage()
            dayModelUsage.add(event.usage)
            dayModels[event.model] = dayModelUsage
            dayModelBuckets[day] = dayModels

            var dayEventModels = dayModelEvents[day] ?? [:]
            dayEventModels[event.model, default: 0] += 1
            dayModelEvents[day] = dayEventModels

            let hour = calendar.dateInterval(of: .hour, for: event.timestamp)?.start ?? event.timestamp
            var hourUsage = hourBuckets[hour] ?? Usage()
            hourUsage.add(event.usage)
            hourBuckets[hour] = hourUsage
        }

        // Attribute session prompts to the model when a session clearly ran on
        // a single model; multi-model sessions stay unattributed like Claude.
        for sessionKey in sessionIDs {
            let models = sessionModels[sessionKey] ?? []
            guard models.count == 1, let model = models.first else { continue }
            let turnsForSession = sessionTurns[sessionKey] ?? 0
            if turnsForSession > 0 {
                modelTurns[model, default: 0] += turnsForSession
            }
            for (day, turnsBySession) in daySessionTurns {
                let dayTurnCount = turnsBySession[sessionKey] ?? 0
                if dayTurnCount > 0 {
                    dayModelTurns[day, default: [:]][model, default: 0] += dayTurnCount
                }
            }
            modelSessions[model, default: 0] += 1
        }

        report.sessions = sessionIDs.count
        report.events = eventCount
        for sessionKey in sessionIDs {
            guard let usage = sessionUsages[sessionKey], usage.total > 0 || (sessionTurns[sessionKey] ?? 0) > 0 else {
                continue
            }
            report.usage.add(usage)
            report.topSessions.append(SessionUsage(
                path: sessionDirectories[sessionKey] ?? sessionKey,
                lastEvent: sessionLastEvents[sessionKey] ?? now,
                turns: sessionTurns[sessionKey] ?? 0,
                usage: usage
            ))
        }
        report.topSessions.sort { $0.usage.total > $1.usage.total }
        report.topSessions = Array(report.topSessions.prefix(8))
        let days: Set<String>
        if let fillDayCount {
            days = Set((0..<fillDayCount).compactMap { offset in
                calendar.date(byAdding: .day, value: offset, to: start).map { formatter.string(from: $0) }
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
        report.scannedAt = now
        return report
    }

    // MARK: Parsing

    private func readParsedData() -> ParsedData? {
        let fingerprint = Self.fingerprint(for: databaseURL)
        lock.lock()
        defer { lock.unlock() }
        if let entry = cacheEntry, entry.fingerprint == fingerprint {
            return entry.parsed
        }
        let parsed = parseDatabase()
        cacheEntry = ParsedCacheEntry(fingerprint: fingerprint, parsed: parsed)
        return parsed
    }

    private static func fingerprint(for url: URL) -> String {
        func describe(_ path: String) -> String {
            let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = values?.fileSize ?? 0
            let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            return size == 0 && modified == 0 ? "missing" : "\(size)|\(modified)"
        }
        return [url.path, url.path + "-wal", url.path + "-shm"].map(describe).joined(separator: "|")
    }

    private func parseDatabase() -> ParsedData {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return ParsedData(events: [], turns: [])
        }
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let database else {
            sqlite3_close(database)
            return ParsedData(events: [], turns: [])
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 250)

        let sql = """
        SELECT m.time_created,
               json_extract(m.data, '$.role'),
               m.session_id,
               s.directory,
               json_extract(m.data, '$.modelID'),
               json_extract(m.data, '$.tokens.input'),
               json_extract(m.data, '$.tokens.output'),
               json_extract(m.data, '$.tokens.reasoning'),
               json_extract(m.data, '$.tokens.cache.read'),
               json_extract(m.data, '$.tokens.cache.write'),
               json_extract(m.data, '$.tokens.total')
        FROM message m
        JOIN session s ON s.id = m.session_id
        WHERE json_extract(m.data, '$.role') IN ('assistant', 'user')
        ORDER BY m.time_created ASC
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return ParsedData(events: [], turns: [])
        }
        defer { sqlite3_finalize(statement) }

        var events: [Event] = []
        var turns: [Turn] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let timeMilliseconds = sqlite3_column_int64(statement, 0)
            guard timeMilliseconds > 0 else { continue }
            let timestamp = Date(timeIntervalSince1970: Double(timeMilliseconds) / 1000)
            let role = text(statement, 1)
            let sessionKey = text(statement, 2) ?? "unknown"
            if role == "user" {
                turns.append(Turn(timestamp: timestamp, sessionKey: sessionKey))
                continue
            }
            guard role == "assistant" else { continue }
            let freshInput = integer(statement, 5)
            let output = integer(statement, 6)
            let reasoning = integer(statement, 7)
            let cacheRead = integer(statement, 8)
            let cacheWrite = integer(statement, 9)
            let reportedTotal = integer(statement, 10)
            let inputTotal = freshInput + cacheRead + cacheWrite
            let computedTotal = inputTotal + output + reasoning
            guard computedTotal > 0 || reportedTotal > 0 else { continue }
            let usage = Usage(
                input: inputTotal,
                cachedInput: cacheRead,
                cacheCreationInput: cacheWrite,
                output: output,
                reasoningOutput: reasoning,
                total: reportedTotal > 0 ? min(reportedTotal, computedTotal) : computedTotal
            )
            events.append(Event(
                timestamp: timestamp,
                usage: usage,
                model: Self.displayModelName(text(statement, 4)),
                sessionKey: sessionKey,
                directory: text(statement, 3)
            ))
        }
        return ParsedData(events: events, turns: turns)
    }

    /// OpenCode persists provider model IDs, which are useful for routing but
    /// are not a readable name for a usage table. Keep the mapping local to
    /// this scanner so other providers retain their own canonicalization and
    /// an unknown OpenCode ID remains visible rather than guessed.
    private static func displayModelName(_ rawModelID: String?) -> String {
        switch rawModelID?.lowercased() {
        case "x-preview-f-free":
            return "Ox Alpha Free"
        case .none, .some(""):
            return "unknown"
        default:
            return rawModelID ?? "unknown"
        }
    }

    private func text(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }

    private func integer(_ statement: OpaquePointer?, _ index: Int32) -> Int64 {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? 0 : sqlite3_column_int64(statement, index)
    }
}
