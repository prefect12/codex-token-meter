import Cocoa
import Foundation

/// A running Codex/Claude turn writes to its transcript every few seconds. Once a
/// session has been silent longer than this it has stopped — the window was closed
/// or the turn died mid-flight — so it must no longer be reported as "running".
/// Kept generous so a long, quiet tool call (e.g. a multi-minute build) is not
/// mistaken for a dead session.
private let runningActivityTimeout: TimeInterval = 10 * 60

private struct ReadStateFile: Codable {
    var schemaVersion: Int?
    var didBaselineExistingWaiting: Bool
    var openedAt: [String: TimeInterval]
    var runningSeenAt: [String: TimeInterval]?
    var userReadAt: [String: TimeInterval]?
    var codexUpdatedAtSeen: [String: TimeInterval]?
}

private struct LoggedThread {
    let id: String
    let lastActivity: Date
}

private struct ThreadStateMetadata {
    let tokensUsed: Int?
    let tokenBreakdown: TokenBreakdown
    let model: String?
    let updatedAt: Date?
}

private struct AppServerThreadSnapshot {
    var items: [CodexThreadItem] = []
    var externalReadAtByID: [String: Date] = [:]
}

private struct RolloutSummary {
    var title: String?
    var preview: String?
    var cwd: String?
    var isRunning = false
    var isWaitingForInput = false
    var turns = 0
    var lastTaskEventAt: Date?
    var lastWaitingAt: Date?
    var lastCompletionAt: Date?
    var currentTurnStartedAt: Date?
    var tokenBreakdown = TokenBreakdown()
    var compressionCount = 0
}

/// Byte-offset bookmark into a JSONL file that is only ever appended to.
/// `size` detects rewrites: whenever the file shrinks the scan restarts at zero.
private struct FileScanPosition {
    var offset: UInt64 = 0
    var size: UInt64 = 0
}

/// The bytes appended to a file since the previous scan. `body` holds complete
/// lines (up to the last newline); `tail` holds a possibly half-written final
/// line that must not advance the bookmark, so it is re-read next scan.
private struct AppendedContent {
    let body: String
    let tail: String
    let position: FileScanPosition
    let restarted: Bool
}

/// Accumulated fold state for one Codex rollout file, kept across scans so each
/// scan only parses newly appended lines.
private struct RolloutScanState {
    var position = FileScanPosition()
    var summary = RolloutSummary()
    var previousTokenCounters = TokenBreakdown()
    var pendingInteractiveCallIDs = Set<String>()
    var pendingInteractiveCallWithoutID = false
}

/// Accumulated fold state for one Claude Code transcript, kept across scans so
/// each scan only parses newly appended lines.
private struct ClaudeScanState {
    var position = FileScanPosition()
    var sessionID: String
    var cwd: String?
    var firstUserText: String?
    var latestUserText: String?
    var latestAssistantText: String?
    var lastPrompt: String?
    var aiTitle: String?
    var latestUserAt: Date?
    var latestUserIsToolResult = false
    var latestUserIsInteractiveToolResult = false
    var latestAssistantAt: Date?
    var latestAssistantIsRunning = false
    var latestAssistantNeedsInput = false
    var latestAssistantInteractiveToolIDs = Set<String>()
    var lastActivity: Date?
    var lastQueueOperation: String?
    var lastQueueAt: Date?
    var turns = 0
    var model: String?
    var tokens = TokenBreakdown()
}

final class CodexActivityReader {
    private let fileManager = FileManager.default
    private let home = NSHomeDirectory()
    private var rolloutScanCache: [String: RolloutScanState] = [:]
    private var claudeScanCache: [String: ClaudeScanState] = [:]

    func read(limit: Int = 12, lookbackHours: Int = 12) -> [CodexThreadItem] {
        // Safety valve only: entries are tiny, but an unbounded map over months of
        // uptime should not grow forever. Dropping everything just re-parses once.
        if rolloutScanCache.count > 2048 { rolloutScanCache.removeAll() }
        if claudeScanCache.count > 2048 { claudeScanCache.removeAll() }
        var byID: [String: CodexThreadItem] = [:]
        let unreadThreadIDs = globalUnreadThreadIDs()
        let stateMetadata = stateThreadMetadata()
        let appServerSnapshot = readFromAppServer(limit: limit, unreadThreadIDs: unreadThreadIDs)
        for item in appServerSnapshot.items {
            byID[item.id] = item
        }

        for logged in recentLoggedThreads(limit: max(limit * 3, 18), lookbackHours: lookbackHours) {
            let rollout = rolloutURL(threadID: logged.id, lastActivity: logged.lastActivity, lookbackHours: lookbackHours)
            let summary = rollout.flatMap(rolloutSummary)
            guard let summary, summary.turns > 0 else { continue }
            let activityDate: Date
            if summary.isWaitingForInput {
                activityDate = summary.lastWaitingAt ?? summary.lastTaskEventAt ?? logged.lastActivity
            } else if summary.isRunning {
                activityDate = maxDate(logged.lastActivity, summary.lastTaskEventAt)
            } else {
                activityDate = summary.lastCompletionAt ?? summary.lastTaskEventAt ?? logged.lastActivity
            }
            // A running turn keeps emitting events; once it has been silent past the
            // timeout the turn has stopped, so it is reported as finished, not running.
            let isRunning = !summary.isWaitingForInput
                && summary.isRunning
                && Date().timeIntervalSince(activityDate) <= runningActivityTimeout
            let status: ThreadRunStatus = summary.isWaitingForInput ? .waiting : (isRunning ? .running : .unread)
            let externalReadAt = appServerSnapshot.externalReadAtByID[logged.id]
            let explicitUnread = unreadThreadIDs.contains(logged.id)
                && !isAppServerReadThrough(externalReadAt: externalReadAt, lastActivity: activityDate)
            if let existing = byID[logged.id] {
                let preferLoggedStatus = status == .waiting || statusRank(status) < statusRank(existing.status)
                let tokenBreakdown = summary.tokenBreakdown.resolved(with: existing.tokenBreakdown)
                let mergedTitle = cleanTitle(summary.title)
                    ?? cleanTitle(existing.title)
                    ?? summary.cwd.map(shortFolderName)
                    ?? existing.title
                let startedAt = status == .waiting
                    ? (summary.lastWaitingAt ?? summary.currentTurnStartedAt)
                    : summary.currentTurnStartedAt
                byID[logged.id] = CodexThreadItem(
                    id: existing.id,
                    title: mergedTitle,
                    preview: summary.preview ?? existing.preview,
                    cwd: existing.cwd ?? summary.cwd,
                    lastActivity: maxDate(existing.lastActivity, activityDate),
                    startedAt: preferLoggedStatus ? startedAt : existing.startedAt,
                    externalReadAt: maxOptionalDate(existing.externalReadAt, externalReadAt),
                    status: preferLoggedStatus ? status : existing.status,
                    turns: max(existing.turns, summary.turns),
                    compressionCount: mergedCompressionCount(existing.compressionCount, summary.compressionCount),
                    source: preferLoggedStatus ? "\(existing.source)+logs" : existing.source,
                    isExplicitUnread: existing.isExplicitUnread || explicitUnread,
                    codexUpdatedAt: existing.codexUpdatedAt,
                    tokensUsed: existing.tokensUsed ?? tokenBreakdown.displayTotal,
                    tokenBreakdown: tokenBreakdown,
                    model: existing.model
                )
                continue
            }
            let title = cleanTitle(summary.title)
                ?? summary.cwd.map(shortFolderName)
                ?? String(logged.id.prefix(8))
            let startedAt = status == .waiting
                ? (summary.lastWaitingAt ?? summary.currentTurnStartedAt)
                : (summary.isRunning ? summary.currentTurnStartedAt : nil)
            byID[logged.id] = CodexThreadItem(
                id: logged.id,
                title: title,
                preview: summary.preview,
                cwd: summary.cwd,
                lastActivity: activityDate,
                startedAt: startedAt,
                externalReadAt: externalReadAt,
                status: status,
                turns: summary.turns,
                compressionCount: summary.compressionCount,
                source: "logs",
                isExplicitUnread: explicitUnread,
                codexUpdatedAt: nil,
                tokensUsed: summary.tokenBreakdown.displayTotal,
                tokenBreakdown: summary.tokenBreakdown,
                model: nil
            )
        }

        let missingUnreadIDs = unreadThreadIDs.filter { byID[$0] == nil }
        for item in unreadStateThreads(threadIDs: missingUnreadIDs, externalReadAtByID: appServerSnapshot.externalReadAtByID) {
            byID[item.id] = item
        }

        for item in readClaudeThreads(limit: max(limit, 8), lookbackHours: lookbackHours) {
            byID[item.id] = item
        }

        return Array(byID.values)
            .map { enrich($0, with: stateMetadata[$0.id]) }
            .map { enrichWithRolloutSummary($0, lookbackHours: max(lookbackHours, 72)) }
            .sorted(by: stableThreadOrder)
            .limitedForTaskBar(limit: limit)
    }

    private func enrich(_ item: CodexThreadItem, with metadata: ThreadStateMetadata?) -> CodexThreadItem {
        guard let metadata else { return item }
        return CodexThreadItem(
            id: item.id,
            title: item.title,
            preview: item.preview,
            cwd: item.cwd,
            lastActivity: item.lastActivity,
            startedAt: item.startedAt,
            externalReadAt: item.externalReadAt,
            status: item.status,
            turns: item.turns,
            compressionCount: item.compressionCount,
            source: item.source,
            isExplicitUnread: item.isExplicitUnread,
            codexUpdatedAt: metadata.updatedAt ?? item.codexUpdatedAt,
            tokensUsed: item.tokensUsed ?? metadata.tokensUsed,
            tokenBreakdown: item.tokenBreakdown.resolved(with: metadata.tokenBreakdown),
            model: item.model ?? metadata.model
        )
    }

    private func enrichWithRolloutSummary(_ item: CodexThreadItem, lookbackHours: Int) -> CodexThreadItem {
        guard let rollout = rolloutURL(threadID: item.id, lastActivity: item.lastActivity, lookbackHours: lookbackHours),
              let summary = rolloutSummary(fileURL: rollout) else {
            return item
        }
        let shouldUseSummaryTokens = !item.tokenBreakdown.hasDetailedCounters && summary.tokenBreakdown.hasDetailedCounters
        let compressionCount = mergedCompressionCount(item.compressionCount, summary.compressionCount)
        let mergedTitle = cleanTitle(summary.title)
            ?? cleanTitle(item.title)
            ?? summary.cwd.map(shortFolderName)
            ?? item.title
        guard shouldUseSummaryTokens
                || compressionCount != item.compressionCount
                || summary.turns > item.turns
                || mergedTitle != item.title else {
            return item
        }
        let tokenBreakdown = shouldUseSummaryTokens
            ? summary.tokenBreakdown.resolved(with: item.tokenBreakdown)
            : item.tokenBreakdown
        return CodexThreadItem(
            id: item.id,
            title: mergedTitle,
            preview: item.preview ?? summary.preview,
            cwd: item.cwd ?? summary.cwd,
            lastActivity: item.lastActivity,
            startedAt: item.startedAt,
            externalReadAt: item.externalReadAt,
            status: item.status,
            turns: max(item.turns, summary.turns),
            compressionCount: compressionCount,
            source: item.source,
            isExplicitUnread: item.isExplicitUnread,
            codexUpdatedAt: item.codexUpdatedAt,
            tokensUsed: item.tokensUsed ?? tokenBreakdown.displayTotal,
            tokenBreakdown: tokenBreakdown,
            model: item.model
        )
    }

    private func readFromAppServer(limit: Int, unreadThreadIDs: Set<String>) -> AppServerThreadSnapshot {
        guard let codexPath = codexExecutablePath() else { return AppServerThreadSnapshot() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server"]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return AppServerThreadSnapshot()
        }

        let outputLock = NSLock()
        var outputData = Data()
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            outputLock.lock()
            outputData.append(chunk)
            outputLock.unlock()
        }

        let messages = [
            #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"task-bar","version":"0.1.0"},"capabilities":{}}}"#,
            #"{"method":"initialized"}"#,
            #"{"id":2,"method":"thread/loaded/list"}"#,
            #"{"id":3,"method":"thread/list","params":{"limit":20}}"#
        ]
        if let data = (messages.joined(separator: "\n") + "\n").data(using: .utf8) {
            input.fileHandleForWriting.write(data)
        }

        let deadline = Date().addingTimeInterval(2.0)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.1)
        }
        output.fileHandleForReading.readabilityHandler = nil
        outputLock.lock()
        let data = outputData
        outputLock.unlock()
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return AppServerThreadSnapshot() }
        return parseAppServerThreads(text: text, limit: limit, unreadThreadIDs: unreadThreadIDs)
    }

    private func parseAppServerThreads(text: String, limit: Int, unreadThreadIDs: Set<String>) -> AppServerThreadSnapshot {
        var items: [CodexThreadItem] = []
        var externalReadAtByID: [String: Date] = [:]
        var threadDictionaries: [[String: Any]] = []
        for line in text.split(separator: "\n") {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = object["result"] as? [String: Any] else {
                continue
            }
            let candidates = firstArray(in: result, keys: ["data", "threads", "items", "tasks", "loadedThreads"])
            for value in candidates {
                guard let dict = value as? [String: Any],
                      let id = string(dict["id"] ?? dict["threadId"] ?? dict["conversationId"]) else {
                    continue
                }
                guard !isArchivedThread(dict) else { continue }
                threadDictionaries.append(dict)
                if let externalReadAt = appServerExternalReadAt(from: dict) {
                    externalReadAtByID[id] = maxOptionalDate(externalReadAtByID[id], externalReadAt) ?? externalReadAt
                }
            }
        }

        for dict in threadDictionaries {
            guard let id = string(dict["id"] ?? dict["threadId"] ?? dict["conversationId"]) else {
                continue
            }
                let title = cleanTitleCandidate(
                    string(dict["title"]),
                    string(dict["name"]),
                    string(dict["preview"])
                ) ?? String(id.prefix(8))
                let cwd = string(dict["cwd"] ?? dict["workingDirectory"] ?? dict["path"])
                let updatedSeconds = double(dict["updatedAt"] ?? dict["updated_at"] ?? dict["lastActivityAt"]) ?? Date().timeIntervalSince1970
                let lastActivity = unixDate(seconds: updatedSeconds)
                let externalReadAt = maxOptionalDate(appServerExternalReadAt(from: dict), externalReadAtByID[id])
                let explicitUnread = (unreadThreadIDs.contains(id) || isUnreadThread(dict))
                    && !isAppServerReadThrough(externalReadAt: externalReadAt, lastActivity: lastActivity)
                guard let status = appServerThreadStatus(dict, explicitUnread: explicitUnread) else { continue }
                let tokenBreakdown = tokenBreakdown(from: dict)
                let codexUpdatedAt = (double(dict["updatedAt"] ?? dict["updated_at"] ?? dict["lastActivityAt"]) ?? double(dict["recencyAt"] ?? dict["recency_at"]))
                    .map(unixDate(seconds:))
                items.append(CodexThreadItem(
                    id: id,
                    title: title,
                    preview: cleanPreview(string(dict["lastAgentMessage"] ?? dict["lastMessage"] ?? dict["subtitle"] ?? dict["summary"])),
                    cwd: cwd,
                    lastActivity: lastActivity,
                    startedAt: nil,
                    externalReadAt: externalReadAt,
                    status: status,
                    turns: turnCount(from: dict["turns"] ?? dict["turnCount"]),
                    compressionCount: nil,
                    source: "app-server",
                    isExplicitUnread: explicitUnread,
                    codexUpdatedAt: codexUpdatedAt,
                    tokensUsed: tokenBreakdown.displayTotal,
                    tokenBreakdown: tokenBreakdown,
                    model: string(dict["model"] ?? dict["modelName"])
                ))
        }
        return AppServerThreadSnapshot(items: items.limitedForTaskBar(limit: limit), externalReadAtByID: externalReadAtByID)
    }

    private func appServerExternalReadAt(from dict: [String: Any]) -> Date? {
        let keys = [
            "readAt",
            "read_at",
            "lastReadAt",
            "last_read_at",
            "lastViewedAt",
            "last_viewed_at",
            "viewedAt",
            "viewed_at"
        ]
        for key in keys {
            if let seconds = double(dict[key]) {
                return unixDate(seconds: seconds)
            }
        }
        return nil
    }

    private func isAppServerReadThrough(externalReadAt: Date?, lastActivity: Date) -> Bool {
        guard let externalReadAt else { return false }
        return externalReadAt.timeIntervalSince1970 + 60 >= lastActivity.timeIntervalSince1970
    }

    private func isArchivedThread(_ dict: [String: Any]) -> Bool {
        for key in ["archived", "isArchived", "is_archived"] {
            if bool(dict[key]) == true {
                return true
            }
        }

        for key in ["status", "state", "lifecycleStatus", "lifecycle_status", "visibility"] {
            if textContainsArchived(dict[key]) {
                return true
            }
        }
        return false
    }

    private func textContainsArchived(_ raw: Any?) -> Bool {
        if let dict = raw as? [String: Any] {
            return dict.values.contains(where: textContainsArchived)
        }
        if let array = raw as? [Any] {
            return array.contains(where: textContainsArchived)
        }
        guard let value = string(raw)?.lowercased() else { return false }
        let tokens = Set(value.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        return tokens.contains("archived") || tokens.contains("archive")
    }

    private func isUnreadThread(_ dict: [String: Any]) -> Bool {
        for key in ["unread", "isUnread", "is_unread", "hasUnread", "has_unread", "hasUnreadMessages", "has_unread_messages", "hasUnreadActivity", "has_unread_activity"] {
            if bool(dict[key]) == true {
                return true
            }
        }

        for key in ["read", "isRead", "is_read"] {
            if bool(dict[key]) == false {
                return true
            }
        }

        for key in ["status", "state", "activeFlags", "flags"] {
            if textContainsUnread(dict[key]) {
                return true
            }
        }
        return false
    }

    private func textContainsUnread(_ raw: Any?) -> Bool {
        if let dict = raw as? [String: Any] {
            return dict.values.contains(where: textContainsUnread)
        }
        if let array = raw as? [Any] {
            return array.contains(where: textContainsUnread)
        }
        guard let value = string(raw)?.lowercased() else { return false }
        let tokens = Set(value.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        return tokens.contains("unread")
    }

    private func appServerThreadStatus(_ dict: [String: Any], explicitUnread: Bool) -> ThreadRunStatus? {
        if let activeStatus = appServerStatus(from: dict["status"]) {
            return activeStatus
        }
        return explicitUnread ? .unread : nil
    }

    private func appServerStatus(from raw: Any?) -> ThreadRunStatus? {
        let statusText = appServerStatusText(from: raw)
        let tokens = Set(statusText.split { !$0.isLetter && !$0.isNumber }.map(String.init))

        if tokens.contains("notloaded")
            || tokens.contains("completed")
            || tokens.contains("complete")
            || tokens.contains("done")
            || tokens.contains("archived")
            || tokens.contains("idle") {
            return nil
        }

        if tokens.contains("running")
            || tokens.contains("active")
            || tokens.contains("inprogress")
            || statusText.contains("in_progress") {
            return .running
        }
        if tokens.contains("waiting")
            || tokens.contains("wait")
            || tokens.contains("needsinput")
            || statusText.contains("needs_input")
            || statusText.contains("user_input") {
            return .waiting
        }
        return nil
    }

    private func appServerStatusText(from raw: Any?) -> String {
        let rawText: String
        if let dict = raw as? [String: Any] {
            let type = string(dict["type"]) ?? ""
            let flags = (dict["activeFlags"] as? [Any])?.compactMap(string).joined(separator: " ") ?? ""
            rawText = "\(type) \(flags)"
        } else {
            rawText = string(raw) ?? ""
        }
        return rawText.lowercased()
    }

    private func globalUnreadThreadIDs() -> Set<String> {
        let fileURL = URL(fileURLWithPath: home)
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent(".codex-global-state.json")
        guard let data = try? Data(contentsOf: fileURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let atoms = object["electron-persisted-atom-state"] as? [String: Any],
              let unreadByHost = atoms["unread-thread-ids-by-host-v1"] as? [String: Any] else {
            return []
        }

        var ids = Set<String>()
        for value in unreadByHost.values {
            if let array = value as? [Any] {
                ids.formUnion(array.compactMap(string))
            }
        }
        return ids
    }

    private func firstArray(in object: [String: Any], keys: [String]) -> [Any] {
        for key in keys {
            if let array = object[key] as? [Any] {
                return array
            }
        }
        for value in object.values {
            if let nested = value as? [String: Any] {
                let array = firstArray(in: nested, keys: keys)
                if !array.isEmpty {
                    return array
                }
            }
        }
        return []
    }

    private func recentLoggedThreads(limit: Int, lookbackHours: Int) -> [LoggedThread] {
        guard let db = logsDatabaseURLs().first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            return []
        }
        let since = Int(Date().timeIntervalSince1970) - max(1, lookbackHours) * 3600
        let sql = """
        select thread_id, max(ts)
        from logs
        where ts >= \(since)
          and thread_id is not null
        group by thread_id
        order by max(ts) desc
        limit \(max(1, limit));
        """
        return runSQLite(databaseURL: db, sql: sql)
            .split(separator: "\n")
            .compactMap { line in
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard parts.count >= 2, let seconds = TimeInterval(parts[1]) else { return nil }
                return LoggedThread(id: String(parts[0]), lastActivity: Date(timeIntervalSince1970: seconds))
            }
    }

    private func unreadStateThreads(threadIDs: Set<String>, externalReadAtByID: [String: Date]) -> [CodexThreadItem] {
        guard !threadIDs.isEmpty,
              let db = stateDatabaseURLs().first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            return []
        }
        let ids = threadIDs.map(sqlStringLiteral).joined(separator: ",")
        let sql = """
        select id, title, preview, cwd, tokens_used, model,
               coalesce(nullif(updated_at_ms, 0), updated_at * 1000) as updated_ms
        from threads
        where archived = 0
          and id in (\(ids))
        order by updated_ms desc;
        """
        return runSQLiteJSON(databaseURL: db, sql: sql).compactMap { row in
            guard let id = string(row["id"]) else { return nil }
            let title = cleanTitleCandidate(
                string(row["title"]),
                string(row["preview"])
            ) ?? String(id.prefix(8))
            let updatedMS = double(row["updated_ms"]) ?? Date().timeIntervalSince1970 * 1000
            let lastActivity = unixDate(seconds: updatedMS)
            let codexUpdatedAt = unixDate(seconds: updatedMS)
            let externalReadAt = externalReadAtByID[id]
            if isAppServerReadThrough(externalReadAt: externalReadAt, lastActivity: lastActivity) {
                return nil
            }
            let tokenBreakdown = TokenBreakdown.totalOnly(intValue(row["tokens_used"]))
            return CodexThreadItem(
                id: id,
                title: title,
                preview: cleanPreview(string(row["preview"])),
                cwd: string(row["cwd"]),
                lastActivity: lastActivity,
                startedAt: nil,
                externalReadAt: externalReadAt,
                status: .unread,
                turns: 0,
                compressionCount: nil,
                source: "state",
                isExplicitUnread: true,
                codexUpdatedAt: codexUpdatedAt,
                tokensUsed: tokenBreakdown.displayTotal,
                tokenBreakdown: tokenBreakdown,
                model: string(row["model"])
            )
        }
    }

    private func stateThreadMetadata(limit: Int = 300) -> [String: ThreadStateMetadata] {
        guard let db = stateDatabaseURLs().first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            return [:]
        }
        let sql = """
        select id, tokens_used, model,
               coalesce(nullif(updated_at_ms, 0), updated_at * 1000) as updated_ms
        from threads
        where archived = 0
        order by updated_ms desc
        limit \(max(1, limit));
        """
        var result: [String: ThreadStateMetadata] = [:]
        for row in runSQLiteJSON(databaseURL: db, sql: sql) {
            guard let id = string(row["id"]) else { continue }
            let tokenBreakdown = TokenBreakdown.totalOnly(intValue(row["tokens_used"]))
            result[id] = ThreadStateMetadata(
                tokensUsed: tokenBreakdown.displayTotal,
                tokenBreakdown: tokenBreakdown,
                model: string(row["model"]),
                updatedAt: double(row["updated_ms"]).map(unixDate(seconds:))
            )
        }
        return result
    }

    private func runSQLite(databaseURL: URL, sql: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-batch", "-noheader", "-separator", "\t", databaseURL.path, sql]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return ""
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return "" }
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private func runSQLiteJSON(databaseURL: URL, sql: String) -> [[String: Any]] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-json", databaseURL.path, sql]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return []
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    private func rolloutURL(threadID: String, lastActivity: Date, lookbackHours: Int) -> URL? {
        let cutoff = Date().addingTimeInterval(-TimeInterval(max(1, lookbackHours)) * 3600)
        for root in sessionRoots() {
            for directory in candidateRolloutDirectories(root: root, around: lastActivity) {
                guard let urls = try? fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }
                for url in urls where url.lastPathComponent.hasPrefix("rollout-")
                    && url.pathExtension == "jsonl"
                    && url.lastPathComponent.contains(threadID) {
                    let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    if let modified = values?.contentModificationDate, modified < cutoff {
                        continue
                    }
                    return url
                }
            }
        }
        return nil
    }

    private func readClaudeThreads(limit: Int, lookbackHours: Int) -> [CodexThreadItem] {
        let cutoff = Date().addingTimeInterval(-TimeInterval(max(1, lookbackHours)) * 3600)
        var items: [CodexThreadItem] = []
        for root in claudeProjectRoots() {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                guard (values?.contentModificationDate ?? .distantPast) >= cutoff,
                      let item = claudeThreadItem(fileURL: url, cutoff: cutoff) else {
                    continue
                }
                items.append(item)
            }
        }
        return items
            .sorted(by: stableThreadOrder)
            .prefix(limit)
            .map { $0 }
    }

    private func claudeThreadItem(fileURL: URL, cutoff: Date) -> CodexThreadItem? {
        let key = fileURL.path
        let fallbackSessionID = fileURL.deletingPathExtension().lastPathComponent
        var state = claudeScanCache[key] ?? ClaudeScanState(sessionID: fallbackSessionID)
        guard let chunk = appendedContent(fileURL: fileURL, position: state.position) else {
            claudeScanCache.removeValue(forKey: key)
            return nil
        }
        if chunk.restarted {
            state = ClaudeScanState(sessionID: fallbackSessionID)
        }
        for line in chunk.body.split(separator: "\n", omittingEmptySubsequences: true) {
            applyClaudeLine(String(line), to: &state)
        }
        state.position = chunk.position
        claudeScanCache[key] = state
        guard !chunk.tail.isEmpty else {
            return claudeThreadItem(from: state, cutoff: cutoff)
        }
        var transient = state
        applyClaudeLine(chunk.tail, to: &transient)
        return claudeThreadItem(from: transient, cutoff: cutoff)
    }

    /// Titles and previews only ever use the head of a message, so persisted fold
    /// state must not hang on to multi-megabyte pasted prompts.
    private func cappedScanText(_ value: String) -> String {
        value.count > 4096 ? String(value.prefix(4096)) : value
    }

    private func applyClaudeLine(_ line: String, to state: inout ClaudeScanState) {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        if let value = string(object["sessionId"]), !value.isEmpty {
            state.sessionID = value
        }
        if let value = string(object["cwd"]), !value.isEmpty {
            state.cwd = value
        }
        let timestamp = string(object["timestamp"]).flatMap(iso8601Date)
        if let timestamp {
            state.lastActivity = maxDate(state.lastActivity ?? timestamp, timestamp)
        }

        let type = string(object["type"]) ?? ""
        if type == "queue-operation" {
            if let timestamp {
                state.lastQueueAt = timestamp
                state.lastQueueOperation = string(object["operation"])
            }
            return
        }
        if type == "last-prompt" {
            if let value = string(object["lastPrompt"]), !value.isEmpty {
                state.lastPrompt = cappedScanText(value)
            }
            return
        }
        if type == "ai-title" {
            if let value = cleanTitle(string(object["aiTitle"])) {
                state.aiTitle = value
            }
            return
        }

        guard let message = object["message"] as? [String: Any] else { return }
        let role = string(message["role"]) ?? type
        let contentText = messageContentText(message["content"])
        if role == "user" {
            if let timestamp {
                state.latestUserAt = timestamp
            }
            let isToolResult = bool(object["toolUseResult"]) == true
                || messageContentContainsType(message["content"], "tool_result")
            let toolResultIDs = messageContentToolResultIDs(message["content"])
            let isInteractiveToolResult = !toolResultIDs.isEmpty
                && !state.latestAssistantInteractiveToolIDs.isDisjoint(with: toolResultIDs)
            state.latestUserIsToolResult = isToolResult
            state.latestUserIsInteractiveToolResult = isInteractiveToolResult
            if let contentText {
                state.firstUserText = state.firstUserText ?? cappedScanText(contentText)
                state.latestUserText = cappedScanText(contentText)
            }
            // Only genuine human prompts count as turns. Tool results are
            // role=user but automated; sidechain/meta messages are injected.
            let isSidechain = (object["isSidechain"] as? Bool) ?? false
            let isMeta = (object["isMeta"] as? Bool) ?? false
            if !isToolResult, !isSidechain, !isMeta,
               let contentText, !contentText.isEmpty {
                state.turns += 1
            }
        } else if role == "assistant" {
            if let timestamp {
                state.latestAssistantAt = timestamp
            }
            state.latestUserIsToolResult = false
            state.latestUserIsInteractiveToolResult = false
            if let value = string(message["model"]), !value.isEmpty {
                state.model = value
            }
            if let usage = message["usage"] as? [String: Any] {
                let input = intValue(usage["input_tokens"]) ?? 0
                let cacheRead = intValue(usage["cache_read_input_tokens"]) ?? 0
                let cacheCreate = intValue(usage["cache_creation_input_tokens"]) ?? 0
                let output = intValue(usage["output_tokens"]) ?? 0
                let totalInput = input + cacheRead + cacheCreate
                if totalInput + output > 0 {
                    state.tokens.add(TokenBreakdown(
                        input: totalInput,
                        cachedInput: cacheRead,
                        output: output,
                        reasoningOutput: 0,
                        total: totalInput + output,
                        hasDetailedCounters: true
                    ))
                }
            }
            let stopReason = string(message["stop_reason"] ?? message["stopReason"])?.lowercased()
            let interactiveToolIDs = messageContentToolUses(message["content"])
                .filter { isInteractiveUserInputTool($0.name) }
                .compactMap(\.id)
            state.latestAssistantInteractiveToolIDs = Set(interactiveToolIDs)
            let assistantRequestedUserInput = !state.latestAssistantInteractiveToolIDs.isEmpty
            state.latestAssistantIsRunning = !assistantRequestedUserInput
                && (stopReason == "tool_use"
                    || messageContentContainsType(message["content"], "tool_use"))
            state.latestAssistantNeedsInput = stopReason == "pause_turn" || assistantRequestedUserInput
            if let contentText {
                state.latestAssistantText = cappedScanText(contentText)
            }
        }
    }

    private func claudeThreadItem(from state: ClaudeScanState, cutoff: Date) -> CodexThreadItem? {
        guard let activityDate = state.lastActivity,
              activityDate >= cutoff,
              state.turns > 0 || state.latestAssistantText != nil else {
            return nil
        }

        let pendingUserResponse = !state.latestUserIsInteractiveToolResult
            && (state.latestUserAt ?? .distantPast) > (state.latestAssistantAt ?? .distantPast)
        let queuedAfterAssistant = state.lastQueueOperation == "enqueue"
            && (state.lastQueueAt ?? .distantPast) > (state.latestAssistantAt ?? .distantPast)
        let assistantWaitingForInput = state.latestAssistantNeedsInput
            && (state.latestAssistantAt ?? .distantPast) >= (state.latestUserAt ?? .distantPast)
        let interactiveToolResultWaiting = state.latestUserIsInteractiveToolResult
            && (state.latestUserAt ?? .distantPast) >= (state.latestAssistantAt ?? .distantPast)
        let assistantRunningTool = state.latestAssistantIsRunning
            && (state.latestAssistantAt ?? .distantPast) >= (state.latestUserAt ?? .distantPast)
        let userToolResultStillActive = state.latestUserIsToolResult
            && !state.latestUserIsInteractiveToolResult
            && (state.latestUserAt ?? .distantPast) >= (state.latestAssistantAt ?? .distantPast)
        let looksRunning = pendingUserResponse || queuedAfterAssistant || assistantRunningTool || userToolResultStillActive
        // A running turn streams to the transcript every few seconds; if the session
        // has gone silent past the timeout the turn has stopped (window closed or died
        // mid-flight), so it is no longer running even though the log ends mid-turn.
        let isRunning = looksRunning
            && Date().timeIntervalSince(activityDate) <= runningActivityTimeout
        let isWaitingForUser = !isRunning && (assistantWaitingForInput || interactiveToolResultWaiting)
        let status: ThreadRunStatus = isRunning ? .running : (isWaitingForUser ? .waiting : .unread)
        let startedAt: Date?
        if isRunning {
            startedAt = state.latestUserAt ?? state.latestAssistantAt ?? state.lastQueueAt ?? activityDate
        } else if isWaitingForUser {
            startedAt = state.latestAssistantAt ?? activityDate
        } else {
            startedAt = nil
        }
        let title = state.aiTitle
            ?? cleanTitle(state.lastPrompt)
            ?? cleanTitle(state.firstUserText)
            ?? state.cwd.map(shortFolderName)
            ?? String(state.sessionID.prefix(8))
        let preview = cleanPreview(state.latestAssistantText ?? state.latestUserText)
        return CodexThreadItem(
            id: "claude:\(state.sessionID)",
            title: title,
            preview: preview,
            cwd: state.cwd,
            lastActivity: activityDate,
            startedAt: startedAt,
            externalReadAt: nil,
            status: status,
            turns: state.turns,
            compressionCount: nil,
            source: "claude-code",
            isExplicitUnread: false,
            codexUpdatedAt: nil,
            tokensUsed: state.tokens.displayTotal,
            tokenBreakdown: state.tokens,
            model: state.model
        )
    }

    private func messageContentText(_ raw: Any?) -> String? {
        if let text = raw as? String {
            return text
        }
        if let array = raw as? [[String: Any]] {
            let text = array.compactMap { item -> String? in
                let type = string(item["type"]) ?? ""
                guard type.isEmpty || type == "text" else { return nil }
                return string(item["text"] ?? item["content"])
            }.joined(separator: " ")
            return text.isEmpty ? nil : text
        }
        if let dict = raw as? [String: Any] {
            return string(dict["text"] ?? dict["content"])
        }
        return nil
    }

    private func messageContentContainsType(_ raw: Any?, _ expectedType: String) -> Bool {
        if let array = raw as? [[String: Any]] {
            return array.contains { string($0["type"]) == expectedType }
        }
        if let dict = raw as? [String: Any] {
            return string(dict["type"]) == expectedType
        }
        return false
    }

    private func messageContentToolUses(_ raw: Any?) -> [(name: String, id: String?)] {
        if let array = raw as? [[String: Any]] {
            return array.compactMap { item in
                guard string(item["type"]) == "tool_use",
                      let name = string(item["name"]) else {
                    return nil
                }
                return (name, string(item["id"]))
            }
        }
        if let dict = raw as? [String: Any],
           string(dict["type"]) == "tool_use",
           let name = string(dict["name"]) {
            return [(name, string(dict["id"]))]
        }
        return []
    }

    private func messageContentToolResultIDs(_ raw: Any?) -> Set<String> {
        if let array = raw as? [[String: Any]] {
            return Set(array.compactMap { item in
                guard string(item["type"]) == "tool_result" else { return nil }
                return string(item["tool_use_id"])
            })
        }
        if let dict = raw as? [String: Any],
           string(dict["type"]) == "tool_result",
           let id = string(dict["tool_use_id"]) {
            return [id]
        }
        return []
    }

    private func isInteractiveUserInputTool(_ name: String) -> Bool {
        let normalized = name.lowercased()
            .replacingOccurrences(of: "-", with: "_")
        return normalized == "askuserquestion"
            || normalized == "ask_user_question"
            || normalized == "request_user_input"
            || normalized.hasSuffix("__askuserquestion")
            || normalized.hasSuffix("__ask_user_question")
            || normalized.hasSuffix("__request_user_input")
    }

    private func candidateRolloutDirectories(root: URL, around date: Date) -> [URL] {
        var directories = [root]
        let calendar = Calendar(identifier: .gregorian)
        let dates = [-1, 0, 1].compactMap { calendar.date(byAdding: .day, value: $0, to: date) }
        for date in dates {
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = components.year,
                  let month = components.month,
                  let day = components.day else { continue }
            directories.append(
                root
                    .appendingPathComponent(String(format: "%04d", year), isDirectory: true)
                    .appendingPathComponent(String(format: "%02d", month), isDirectory: true)
                    .appendingPathComponent(String(format: "%02d", day), isDirectory: true)
            )
        }
        return unique(directories)
    }

    /// Reads the bytes appended to `fileURL` since `position`. The bookmark only
    /// advances past complete lines; a half-written final line comes back as
    /// `tail` and is parsed transiently until its newline lands.
    private func appendedContent(fileURL: URL, position: FileScanPosition) -> AppendedContent? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        var start = position.offset
        var restarted = false
        if size < position.size || start > size {
            start = 0
            restarted = true
        }
        guard size > start else {
            return AppendedContent(
                body: "",
                tail: "",
                position: FileScanPosition(offset: start, size: size),
                restarted: restarted
            )
        }
        guard (try? handle.seek(toOffset: start)) != nil,
              let data = try? handle.read(upToCount: Int(size - start)) else {
            return nil
        }
        guard let lastNewline = data.lastIndex(of: 0x0A) else {
            return AppendedContent(
                body: "",
                tail: String(decoding: data, as: UTF8.self),
                position: FileScanPosition(offset: start, size: size),
                restarted: restarted
            )
        }
        let bodyData = data[data.startIndex...lastNewline]
        let tailData = data[data.index(after: lastNewline)...]
        return AppendedContent(
            body: String(decoding: bodyData, as: UTF8.self),
            tail: String(decoding: tailData, as: UTF8.self),
            position: FileScanPosition(offset: start + UInt64(bodyData.count), size: size),
            restarted: restarted
        )
    }

    private func rolloutSummary(fileURL: URL) -> RolloutSummary? {
        let key = fileURL.path
        var state = rolloutScanCache[key] ?? RolloutScanState()
        guard let chunk = appendedContent(fileURL: fileURL, position: state.position) else {
            rolloutScanCache.removeValue(forKey: key)
            return nil
        }
        if chunk.restarted {
            state = RolloutScanState()
        }
        for line in chunk.body.split(separator: "\n", omittingEmptySubsequences: true) {
            applyRolloutLine(String(line), to: &state)
        }
        state.position = chunk.position
        rolloutScanCache[key] = state
        guard !chunk.tail.isEmpty else {
            return state.summary
        }
        var transient = state
        applyRolloutLine(chunk.tail, to: &transient)
        return transient.summary
    }

    private func clearInteractiveWaiting(_ state: inout RolloutScanState) {
        state.summary.isWaitingForInput = false
        state.pendingInteractiveCallIDs.removeAll()
        state.pendingInteractiveCallWithoutID = false
    }

    private func applyRolloutLine(_ line: String, to state: inout RolloutScanState) {
        // Extracting the event date parses the whole line as JSON; do it lazily so
        // lines that match no marker below skip that cost entirely.
        var resolvedEventDate: Date?? = nil
        func lineEventDate() -> Date? {
            if resolvedEventDate == nil {
                resolvedEventDate = .some(eventDate(from: line))
            }
            return resolvedEventDate ?? nil
        }
        if state.summary.cwd == nil, line.contains(#""type":"session_meta""#) {
            state.summary.cwd = extractJSONString(line: line, key: "cwd")
        }
        if line.contains(#""type":"turn_context""#) {
            if let cwd = extractJSONString(line: line, key: "cwd"),
               !cwd.isEmpty {
                state.summary.cwd = cwd
            }
            state.summary.isRunning = true
            clearInteractiveWaiting(&state)
            state.summary.turns += 1
            state.summary.lastTaskEventAt = lineEventDate() ?? state.summary.lastTaskEventAt
            state.summary.currentTurnStartedAt = lineEventDate() ?? state.summary.currentTurnStartedAt
        }
        if state.summary.title == nil,
           line.contains(#""type":"response_item""#),
           line.contains(#""payload":{"type":"message""#),
           line.contains(#""type":"message""#),
           line.contains(#""role":"user""#) {
            if let candidate = userMessageText(from: line),
               let title = displayTitleCandidate(candidate) {
                state.summary.title = title
            }
        }
        if isUserMessage(line: line) {
            clearInteractiveWaiting(&state)
        }
        if line.contains(#""type":"response_item""#),
           line.contains(#""payload":{"type":"message""#),
           line.contains(#""role":"assistant""#),
           let candidate = assistantMessageText(from: line),
           let preview = cleanPreview(candidate) {
            state.summary.preview = preview
        }
        if let call = functionCallInfo(from: line),
           isInteractiveUserInputTool(call.name) {
            state.summary.isRunning = true
            state.summary.isWaitingForInput = true
            if let callID = call.callID {
                state.pendingInteractiveCallIDs.insert(callID)
            } else {
                state.pendingInteractiveCallWithoutID = true
            }
            let waitingAt = lineEventDate() ?? state.summary.lastTaskEventAt ?? state.summary.currentTurnStartedAt
            state.summary.lastWaitingAt = waitingAt ?? state.summary.lastWaitingAt
            state.summary.lastTaskEventAt = waitingAt ?? state.summary.lastTaskEventAt
        } else if isFunctionCallOutput(line: line),
                  state.summary.isWaitingForInput {
            let callID = functionCallOutputID(from: line)
            let matchesPendingCall = callID.map {
                state.pendingInteractiveCallIDs.contains($0)
                    || (state.pendingInteractiveCallWithoutID && state.pendingInteractiveCallIDs.isEmpty)
            } ?? state.pendingInteractiveCallWithoutID
            if matchesPendingCall {
                if let callID {
                    state.pendingInteractiveCallIDs.remove(callID)
                }
                if state.pendingInteractiveCallWithoutID {
                    state.pendingInteractiveCallWithoutID = false
                }
                if state.pendingInteractiveCallIDs.isEmpty && !state.pendingInteractiveCallWithoutID {
                    state.summary.isWaitingForInput = false
                }
                state.summary.isRunning = true
                state.summary.lastTaskEventAt = lineEventDate() ?? state.summary.lastTaskEventAt
            }
        }
        if isFinalAssistantMessage(line: line) {
            state.summary.isRunning = false
            clearInteractiveWaiting(&state)
            state.summary.lastTaskEventAt = lineEventDate() ?? state.summary.lastTaskEventAt
            state.summary.lastCompletionAt = lineEventDate() ?? state.summary.lastCompletionAt
            state.summary.currentTurnStartedAt = nil
        }
        guard line.contains(#""type":"event_msg""#) else { return }
        if line.contains(#""type":"context_compacted""#) {
            state.summary.compressionCount += 1
        }
        if line.contains(#""type":"token_count""#),
           let currentCounters = tokenCounters(from: line) {
            let delta = TokenBreakdown.delta(from: state.previousTokenCounters, to: currentCounters)
            state.previousTokenCounters = currentCounters
            if delta.hasAny {
                state.summary.tokenBreakdown.add(delta)
            }
        }
        if line.contains(#""type":"task_started""#) {
            let wasAlreadyRunning = state.summary.isRunning
            state.summary.isRunning = true
            clearInteractiveWaiting(&state)
            if !wasAlreadyRunning {
                state.summary.turns += 1
            }
            state.summary.lastTaskEventAt = lineEventDate() ?? state.summary.lastTaskEventAt
            state.summary.currentTurnStartedAt = lineEventDate() ?? state.summary.currentTurnStartedAt
        } else if line.contains(#""type":"task_complete""#) || line.contains(#""type":"turn_aborted""#) {
            state.summary.isRunning = false
            clearInteractiveWaiting(&state)
            state.summary.lastTaskEventAt = lineEventDate() ?? state.summary.lastTaskEventAt
            state.summary.lastCompletionAt = lineEventDate() ?? state.summary.lastCompletionAt
            state.summary.currentTurnStartedAt = nil
            if let candidate = completedAgentMessageText(from: line),
               let preview = cleanPreview(candidate) {
                state.summary.preview = preview
            }
        }
    }

    private func isUserMessage(line: String) -> Bool {
        guard line.contains(#""type":"response_item""#),
              line.contains(#""payload":{"type":"message""#),
              line.contains(#""role":"user""#),
              let payload = responseItemPayload(from: line) else {
            return false
        }
        return string(payload["type"]) == "message" && string(payload["role"]) == "user"
    }

    private func isFinalAssistantMessage(line: String) -> Bool {
        guard line.contains(#""type":"response_item""#),
              line.contains(#""payload":{"type":"message""#),
              line.contains(#""role":"assistant""#),
              let payload = responseItemPayload(from: line),
              string(payload["type"]) == "message",
              string(payload["role"]) == "assistant" else {
            return false
        }
        return string(payload["phase"]) == "final"
    }

    private func functionCallInfo(from line: String) -> (name: String, callID: String?)? {
        guard line.contains(#""type":"response_item""#),
              line.contains(#""type":"function_call""#),
              let payload = responseItemPayload(from: line),
              string(payload["type"]) == "function_call",
              let name = string(payload["name"]) else {
            return nil
        }
        return (name, string(payload["call_id"] ?? payload["id"]))
    }

    private func isFunctionCallOutput(line: String) -> Bool {
        guard line.contains(#""type":"response_item""#),
              line.contains(#""type":"function_call_output""#),
              let payload = responseItemPayload(from: line),
              string(payload["type"]) == "function_call_output" else {
            return false
        }
        return true
    }

    private func functionCallOutputID(from line: String) -> String? {
        guard let payload = responseItemPayload(from: line),
              string(payload["type"]) == "function_call_output" else {
            return nil
        }
        return string(payload["call_id"] ?? payload["id"])
    }

    private func responseItemPayload(from line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "response_item",
              let payload = object["payload"] as? [String: Any] else {
            return nil
        }
        return payload
    }

    private func tokenCounters(from line: String) -> TokenBreakdown? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["payload"] as? [String: Any],
              string(payload["type"]) == "token_count" else {
            return nil
        }
        let breakdown = tokenBreakdown(from: payload)
        guard breakdown.hasAny || breakdown.hasDetailedCounters else { return nil }
        return breakdown
    }

    private func eventDate(from line: String) -> Date? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let payload = object["payload"] as? [String: Any] {
            if let completedAt = double(payload["completed_at"]) {
                return unixDate(seconds: completedAt)
            }
            if let startedAt = double(payload["started_at"]) {
                return unixDate(seconds: startedAt)
            }
        }
        guard let timestamp = string(object["timestamp"]) else { return nil }
        return iso8601Date(timestamp)
    }

    private func userMessageText(from line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["payload"] as? [String: Any],
              payload["role"] as? String == "user" else {
            return nil
        }
        if let content = payload["content"] as? [[String: Any]] {
            let text = content.compactMap { string($0["text"] ?? $0["input_text"]) }.joined(separator: " ")
            return text.isEmpty ? nil : text
        }
        return string(payload["text"])
    }

    private func assistantMessageText(from line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["payload"] as? [String: Any],
              payload["role"] as? String == "assistant" else {
            return nil
        }
        if let content = payload["content"] as? [[String: Any]] {
            let text = content.compactMap { string($0["text"] ?? $0["output_text"]) }.joined(separator: " ")
            return text.isEmpty ? nil : text
        }
        return string(payload["text"])
    }

    private func completedAgentMessageText(from line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["payload"] as? [String: Any],
              payload["type"] as? String == "task_complete" else {
            return nil
        }
        return string(payload["last_agent_message"])
    }

    private func displayTitleCandidate(_ value: String) -> String? {
        let markers = [
            "## My request for Codex:",
            "My request for Codex:",
            "## My request:",
            "My request:"
        ]
        for marker in markers {
            if let range = value.range(of: marker) {
                let tail = String(value[range.upperBound...])
                return cleanTitle(firstUsefulLine(in: tail))
            }
        }

        let compact = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if compact.hasPrefix("# AGENTS.md instructions")
            || compact.hasPrefix("<environment_context>")
            || compact.hasPrefix("<permissions instructions>")
            || compact.hasPrefix("<app-context>") {
            return nil
        }
        return cleanTitle(firstUsefulLine(in: compact))
    }

    private func firstUsefulLine(in value: String) -> String {
        for rawLine in value.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard !line.hasPrefix("<image ")
                    && !line.hasPrefix("# Files mentioned")
                    && !line.hasPrefix("## ") else {
                continue
            }
            guard cleanTitle(line) != nil else { continue }
            return line
        }
        return value
    }

    private func extractJSONString(line: String, key: String) -> String? {
        let pattern = "\"\(key)\":\""
        guard let keyRange = line.range(of: pattern) else { return nil }
        var index = keyRange.upperBound
        var value = ""
        var escaped = false
        while index < line.endIndex {
            let character = line[index]
            if escaped {
                value.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                break
            } else {
                value.append(character)
            }
            index = line.index(after: index)
        }
        return value.isEmpty ? nil : value
    }

    private func sessionRoots() -> [URL] {
        let codexHome = URL(fileURLWithPath: home).appendingPathComponent(".codex", isDirectory: true)
        var roots = [
            codexHome.appendingPathComponent("sessions", isDirectory: true)
        ]
        if let env = ProcessInfo.processInfo.environment["CODEX_HOME"], !env.isEmpty {
            let custom = URL(fileURLWithPath: (env as NSString).expandingTildeInPath, isDirectory: true)
            roots.append(custom.appendingPathComponent("sessions", isDirectory: true))
        }
        return unique(roots)
    }

    private func claudeProjectRoots() -> [URL] {
        var roots: [URL] = []
        if let raw = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !raw.isEmpty {
            roots.append(contentsOf: raw.split(separator: ",").map { value in
                let path = String(value).trimmingCharacters(in: .whitespacesAndNewlines)
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
                return url.lastPathComponent == "projects" ? url : url.appendingPathComponent("projects", isDirectory: true)
            })
        }
        let xdgConfigHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
            .flatMap { $0.isEmpty ? nil : $0 }
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
            ?? URL(fileURLWithPath: home).appendingPathComponent(".config", isDirectory: true)
        roots.append(
            xdgConfigHome
                .appendingPathComponent("claude", isDirectory: true)
                .appendingPathComponent("projects", isDirectory: true)
        )
        roots.append(
            URL(fileURLWithPath: home)
                .appendingPathComponent(".claude", isDirectory: true)
                .appendingPathComponent("projects", isDirectory: true)
        )
        return unique(roots)
    }

    private func logsDatabaseURLs() -> [URL] {
        let codexHome = URL(fileURLWithPath: home).appendingPathComponent(".codex", isDirectory: true)
        return [
            codexHome.appendingPathComponent("logs_2.sqlite"),
            codexHome.appendingPathComponent("sqlite/logs_2.sqlite")
        ]
    }

    private func stateDatabaseURLs() -> [URL] {
        let codexHome = URL(fileURLWithPath: home).appendingPathComponent(".codex", isDirectory: true)
        return [
            codexHome.appendingPathComponent("state_5.sqlite"),
            codexHome.appendingPathComponent("sqlite/state_5.sqlite")
        ]
    }

    private func codexExecutablePath() -> String? {
        [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ].first { fileManager.isExecutableFile(atPath: $0) }
    }
}

final class ReadStateStore {
    private static let schemaVersion = 5
    private static let readWatermarkTolerance: TimeInterval = 60
    /// A thread first seen as "unread" may simply be one whose running phase every
    /// scan missed — scans are periodic and can be starved for minutes under system
    /// load. Anything active more recently than this is surfaced instead of being
    /// silently marked read; kept above `runningActivityTimeout` so a turn that
    /// stalled out still shows up as done.
    private static let missedActivityGrace: TimeInterval = 15 * 60
    private static let recentCompletionVisibilityWindow: TimeInterval = 60 * 60
    private static let legacyAutoReadSlack: TimeInterval = 90
    private static let codexOpenUpdatedAtSlack: TimeInterval = 1
    private let fileManager = FileManager.default
    private let fileURL: URL
    private let lock = NSLock()
    private var state: ReadStateFile

    init() {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        let directory = support.appendingPathComponent("Task Bar", isDirectory: true)
        let legacyDirectories = [
            support.appendingPathComponent("Codex Bar", isDirectory: true),
            support.appendingPathComponent("Codex Pet Bar", isDirectory: true)
        ]
        fileURL = directory.appendingPathComponent("read-state.json")
        let sourceURLs = [fileURL] + legacyDirectories.map { $0.appendingPathComponent("read-state.json") }
        let readableURL = sourceURLs.first { FileManager.default.fileExists(atPath: $0.path) } ?? fileURL
        if let data = try? Data(contentsOf: readableURL),
           let decoded = try? JSONDecoder().decode(ReadStateFile.self, from: data) {
            state = ReadStateFile(
                schemaVersion: decoded.schemaVersion ?? Self.schemaVersion,
                didBaselineExistingWaiting: decoded.didBaselineExistingWaiting,
                openedAt: decoded.openedAt,
                runningSeenAt: decoded.runningSeenAt ?? [:],
                userReadAt: decoded.userReadAt,
                codexUpdatedAtSeen: decoded.codexUpdatedAtSeen ?? [:]
            )
        } else {
            state = ReadStateFile(
                schemaVersion: Self.schemaVersion,
                didBaselineExistingWaiting: false,
                openedAt: [:],
                runningSeenAt: [:],
                userReadAt: [:],
                codexUpdatedAtSeen: [:]
            )
        }
    }

    func visibleThreads(from items: [CodexThreadItem]) -> [CodexThreadItem] {
        lock.lock()
        var current = state
        var didChange = false
        if !current.didBaselineExistingWaiting {
            for item in items where shouldBaselineAsRead(item, state: current) {
                current.openedAt[item.id] = readThroughTime(for: item)
            }
            current.didBaselineExistingWaiting = true
            didChange = true
        }

        var runningSeenAt = current.runningSeenAt ?? [:]
        for item in items where item.status == .running || item.status == .stale {
            let timestamp = max(Date().timeIntervalSince1970, item.lastActivity.timeIntervalSince1970)
            if (runningSeenAt[item.id] ?? 0) < timestamp {
                runningSeenAt[item.id] = timestamp
                didChange = true
            }
        }
        current.runningSeenAt = runningSeenAt

        for item in items where !item.isExplicitUnread {
            guard let externalReadAt = item.externalReadAt,
                  externalReadAt.timeIntervalSince1970 + Self.readWatermarkTolerance >= item.lastActivity.timeIntervalSince1970 else {
                continue
            }
            let timestamp = readThroughTime(for: item, at: externalReadAt)
            if (current.openedAt[item.id] ?? 0) < timestamp {
                current.openedAt[item.id] = timestamp
                didChange = true
            }
            if (current.userReadAt?[item.id] ?? 0) < timestamp {
                var userReadAt = current.userReadAt ?? [:]
                userReadAt[item.id] = timestamp
                current.userReadAt = userReadAt
                didChange = true
            }
        }

        for item in items {
            if syncCodexOpenState(for: item, state: &current) {
                didChange = true
            }
        }

        var visible: [CodexThreadItem] = []
        for item in items {
            switch item.status {
            case .running, .stale:
                visible.append(item)
            case .waiting:
                let readAt = current.openedAt[item.id] ?? 0
                let userReadAt = current.userReadAt?[item.id] ?? 0
                guard max(readAt, userReadAt) < item.lastActivity.timeIntervalSince1970 else { continue }
                visible.append(item)
            case .unread:
                let readAt = current.openedAt[item.id] ?? 0
                let userReadAt = current.userReadAt?[item.id] ?? 0
                guard userReadAt < item.lastActivity.timeIntervalSince1970 else { continue }
                if item.isExplicitUnread {
                    visible.append(item)
                    continue
                }
                if readAt >= item.lastActivity.timeIntervalSince1970,
                   !shouldShowDespiteAutomaticReadWatermark(item, readAt: readAt, state: current) {
                    continue
                }
                if shouldShowCompletedThread(item, state: current) {
                    visible.append(item)
                } else if Date().timeIntervalSince(item.lastActivity) < Self.missedActivityGrace {
                    // Recently active but never observed running: the scanner most
                    // likely sampled between its events. Record it as seen-active so
                    // it stays visible until the user acts, like any finished thread.
                    var seenAt = current.runningSeenAt ?? [:]
                    seenAt[item.id] = item.lastActivity.timeIntervalSince1970
                    current.runningSeenAt = seenAt
                    didChange = true
                    visible.append(item)
                } else {
                    current.openedAt[item.id] = readThroughTime(for: item)
                    didChange = true
                }
            }
        }
        state = current
        if didChange {
            saveLocked()
        }
        lock.unlock()
        return visible
    }

    func markRead(_ item: CodexThreadItem) {
        lock.lock()
        let timestamp = readThroughTime(for: item)
        state.openedAt[item.id] = timestamp
        var userReadAt = state.userReadAt ?? [:]
        userReadAt[item.id] = timestamp
        state.userReadAt = userReadAt
        saveLocked()
        lock.unlock()
    }

    func markRead(threadID: String, at date: Date = Date()) {
        lock.lock()
        let timestamp = date.timeIntervalSince1970
        state.openedAt[threadID] = timestamp
        var userReadAt = state.userReadAt ?? [:]
        userReadAt[threadID] = timestamp
        state.userReadAt = userReadAt
        saveLocked()
        lock.unlock()
    }

    func markWaitingRead(_ items: [CodexThreadItem], at date: Date = Date()) {
        lock.lock()
        var userReadAt = state.userReadAt ?? [:]
        for item in items where isReadDismissible(item.status) {
            let timestamp = readThroughTime(for: item, at: date)
            state.openedAt[item.id] = timestamp
            userReadAt[item.id] = timestamp
        }
        state.userReadAt = userReadAt
        state.didBaselineExistingWaiting = true
        saveLocked()
        lock.unlock()
    }

    private func shouldBaselineAsRead(_ item: CodexThreadItem, state: ReadStateFile) -> Bool {
        guard isReadDismissible(item.status), !item.isExplicitUnread else { return false }
        guard item.status == .unread else { return true }
        return !shouldShowCompletedThread(item, state: state)
    }

    private func shouldShowCompletedThread(_ item: CodexThreadItem, state: ReadStateFile) -> Bool {
        guard item.status == .unread else { return false }
        if (state.runningSeenAt?[item.id] ?? 0) > 0 {
            return true
        }
        return Date().timeIntervalSince(item.lastActivity) <= Self.recentCompletionVisibilityWindow
    }

    private func shouldShowDespiteAutomaticReadWatermark(_ item: CodexThreadItem, readAt: TimeInterval, state: ReadStateFile) -> Bool {
        guard (state.userReadAt?[item.id] ?? 0) <= 0 else { return false }
        guard shouldShowCompletedThread(item, state: state) else { return false }
        guard state.userReadAt != nil else { return true }
        let automaticWatermarkCutoff = item.lastActivity.timeIntervalSince1970
            + Self.readWatermarkTolerance
            + Self.legacyAutoReadSlack
        return readAt <= automaticWatermarkCutoff
    }

    private func syncCodexOpenState(for item: CodexThreadItem, state: inout ReadStateFile) -> Bool {
        guard let codexUpdatedAt = item.codexUpdatedAt?.timeIntervalSince1970,
              codexUpdatedAt > 0,
              item.status == .unread,
              !item.isExplicitUnread else {
            return false
        }

        var didChange = false
        var seen = state.codexUpdatedAtSeen ?? [:]
        let previous = seen[item.id]
        if previous.map({ codexUpdatedAt > $0 }) ?? true {
            seen[item.id] = codexUpdatedAt
            state.codexUpdatedAtSeen = seen
            didChange = true
        }

        guard let previous,
              codexUpdatedAt > previous + Self.codexOpenUpdatedAtSlack,
              codexUpdatedAt + Self.readWatermarkTolerance >= item.lastActivity.timeIntervalSince1970 else {
            return didChange
        }

        let timestamp = readThroughTime(for: item, at: Date(timeIntervalSince1970: codexUpdatedAt))
        if (state.openedAt[item.id] ?? 0) < timestamp {
            state.openedAt[item.id] = timestamp
            didChange = true
        }
        var userReadAt = state.userReadAt ?? [:]
        if (userReadAt[item.id] ?? 0) < timestamp {
            userReadAt[item.id] = timestamp
            state.userReadAt = userReadAt
            didChange = true
        }
        return didChange
    }

    private func readThroughTime(for item: CodexThreadItem, at date: Date = Date()) -> TimeInterval {
        max(date.timeIntervalSince1970, item.lastActivity.timeIntervalSince1970 + Self.readWatermarkTolerance)
    }

    private func saveLocked() {
        let directory = fileURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        state.schemaVersion = Self.schemaVersion
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
