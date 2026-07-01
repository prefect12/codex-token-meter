import Cocoa
import Foundation

enum ThreadRunStatus {
    case running
    case stale
    case waiting
    case unread
}

struct CodexThreadItem {
    let id: String
    let title: String
    let preview: String?
    let cwd: String?
    let lastActivity: Date
    let startedAt: Date?
    let externalReadAt: Date?
    let status: ThreadRunStatus
    let turns: Int
    let compressionCount: Int?
    let source: String
    let isExplicitUnread: Bool
    let tokensUsed: Int?
    let tokenBreakdown: TokenBreakdown
    let model: String?
}

struct TokenBreakdown {
    var input: Int = 0
    var cachedInput: Int = 0
    var output: Int = 0
    var reasoningOutput: Int = 0
    var total: Int = 0
    var hasDetailedCounters = false

    var hasAny: Bool {
        input > 0 || cachedInput > 0 || output > 0 || reasoningOutput > 0 || total > 0
    }

    var displayTotal: Int? {
        if total > 0 { return total }
        let inferred = input + output
        return inferred > 0 ? inferred : nil
    }

    static func totalOnly(_ value: Int?) -> TokenBreakdown {
        guard let value, value > 0 else { return TokenBreakdown() }
        return TokenBreakdown(total: value)
    }

    static func delta(from previous: TokenBreakdown, to current: TokenBreakdown) -> TokenBreakdown {
        TokenBreakdown(
            input: max(0, current.input - previous.input),
            cachedInput: max(0, current.cachedInput - previous.cachedInput),
            output: max(0, current.output - previous.output),
            reasoningOutput: max(0, current.reasoningOutput - previous.reasoningOutput),
            total: max(0, current.total - previous.total),
            hasDetailedCounters: current.hasDetailedCounters
        )
    }

    mutating func add(_ other: TokenBreakdown) {
        input += other.input
        cachedInput += other.cachedInput
        output += other.output
        reasoningOutput += other.reasoningOutput
        total += other.total
        hasDetailedCounters = hasDetailedCounters || other.hasDetailedCounters
    }

    func resolved(with fallback: TokenBreakdown) -> TokenBreakdown {
        guard hasAny || hasDetailedCounters else { return fallback }
        guard total == 0, fallback.total > 0 else { return self }
        var result = self
        result.total = fallback.total
        return result
    }
}

private struct ReadStateFile: Codable {
    var schemaVersion: Int?
    var didBaselineExistingWaiting: Bool
    var openedAt: [String: TimeInterval]
    var runningSeenAt: [String: TimeInterval]?
}

private struct LoggedThread {
    let id: String
    let lastActivity: Date
}

private struct ThreadStateMetadata {
    let tokensUsed: Int?
    let tokenBreakdown: TokenBreakdown
    let model: String?
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
    var turns = 0
    var lastTaskEventAt: Date?
    var lastCompletionAt: Date?
    var currentTurnStartedAt: Date?
    var tokenBreakdown = TokenBreakdown()
    var compressionCount = 0
}

final class CodexActivityReader {
    private let fileManager = FileManager.default
    private let home = NSHomeDirectory()

    func read(limit: Int = 12, lookbackHours: Int = 12) -> [CodexThreadItem] {
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
            let activityDate = summary.isRunning
                ? maxDate(logged.lastActivity, summary.lastTaskEventAt)
                : summary.lastCompletionAt ?? summary.lastTaskEventAt ?? logged.lastActivity
            let isStale = summary.isRunning && Date().timeIntervalSince(activityDate) > 10 * 60
            let status: ThreadRunStatus
            if isStale {
                status = .stale
            } else if summary.isRunning {
                status = .running
            } else {
                status = .unread
            }
            let externalReadAt = appServerSnapshot.externalReadAtByID[logged.id]
            let explicitUnread = unreadThreadIDs.contains(logged.id)
                && !isAppServerReadThrough(externalReadAt: externalReadAt, lastActivity: activityDate)
            if let existing = byID[logged.id] {
                let preferLoggedStatus = statusRank(status) < statusRank(existing.status)
                let tokenBreakdown = summary.tokenBreakdown.resolved(with: existing.tokenBreakdown)
                let mergedTitle = cleanTitle(summary.title)
                    ?? cleanTitle(existing.title)
                    ?? summary.cwd.map(shortFolderName)
                    ?? existing.title
                byID[logged.id] = CodexThreadItem(
                    id: existing.id,
                    title: mergedTitle,
                    preview: summary.preview ?? existing.preview,
                    cwd: existing.cwd ?? summary.cwd,
                    lastActivity: maxDate(existing.lastActivity, activityDate),
                    startedAt: preferLoggedStatus ? summary.currentTurnStartedAt : existing.startedAt,
                    externalReadAt: maxOptionalDate(existing.externalReadAt, externalReadAt),
                    status: preferLoggedStatus ? status : existing.status,
                    turns: max(existing.turns, summary.turns),
                    compressionCount: mergedCompressionCount(existing.compressionCount, summary.compressionCount),
                    source: preferLoggedStatus ? "\(existing.source)+logs" : existing.source,
                    isExplicitUnread: existing.isExplicitUnread || explicitUnread,
                    tokensUsed: existing.tokensUsed ?? tokenBreakdown.displayTotal,
                    tokenBreakdown: tokenBreakdown,
                    model: existing.model
                )
                continue
            }
            let title = cleanTitle(summary.title)
                ?? summary.cwd.map(shortFolderName)
                ?? String(logged.id.prefix(8))
            byID[logged.id] = CodexThreadItem(
                id: logged.id,
                title: title,
                preview: summary.preview,
                cwd: summary.cwd,
                lastActivity: activityDate,
                startedAt: summary.isRunning ? summary.currentTurnStartedAt : nil,
                externalReadAt: externalReadAt,
                status: status,
                turns: summary.turns,
                compressionCount: summary.compressionCount,
                source: "logs",
                isExplicitUnread: explicitUnread,
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
            .prefix(limit)
            .map { $0 }
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
                    tokensUsed: tokenBreakdown.displayTotal,
                    tokenBreakdown: tokenBreakdown,
                    model: string(dict["model"] ?? dict["modelName"])
                ))
        }
        return AppServerThreadSnapshot(items: Array(items.prefix(limit)), externalReadAtByID: externalReadAtByID)
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
            "viewed_at",
            "recencyAt",
            "recency_at"
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
                model: string(row["model"])
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
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        var sessionID = fileURL.deletingPathExtension().lastPathComponent
        var cwd: String?
        var firstUserText: String?
        var latestUserText: String?
        var latestAssistantText: String?
        var lastPrompt: String?
        var aiTitle: String?
        var latestUserAt: Date?
        var latestAssistantAt: Date?
        var latestAssistantNeedsAction = false
        var lastActivity: Date?
        var lastQueueOperation: String?
        var lastQueueAt: Date?
        var turns = 0

        text.enumerateLines { line, _ in
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            if let value = string(object["sessionId"]), !value.isEmpty {
                sessionID = value
            }
            if let value = string(object["cwd"]), !value.isEmpty {
                cwd = value
            }
            let timestamp = string(object["timestamp"]).flatMap(iso8601Date)
            if let timestamp {
                lastActivity = maxDate(lastActivity ?? timestamp, timestamp)
            }

            let type = string(object["type"]) ?? ""
            if type == "queue-operation" {
                if let timestamp {
                    lastQueueAt = timestamp
                    lastQueueOperation = string(object["operation"])
                }
                return
            }
            if type == "last-prompt" {
                if let value = string(object["lastPrompt"]), !value.isEmpty {
                    lastPrompt = value
                }
                return
            }
            if type == "ai-title" {
                if let value = cleanTitle(string(object["aiTitle"])) {
                    aiTitle = value
                }
                return
            }

            guard let message = object["message"] as? [String: Any] else { return }
            let role = string(message["role"]) ?? type
            let contentText = self.messageContentText(message["content"])
            if role == "user" {
                if let timestamp {
                    latestUserAt = timestamp
                }
                if let contentText {
                    firstUserText = firstUserText ?? contentText
                    latestUserText = contentText
                }
                turns += 1
            } else if role == "assistant" {
                if let timestamp {
                    latestAssistantAt = timestamp
                }
                let stopReason = string(message["stop_reason"] ?? message["stopReason"])?.lowercased()
                latestAssistantNeedsAction = stopReason == "tool_use"
                    || stopReason == "pause_turn"
                    || self.messageContentContainsType(message["content"], "tool_use")
                if let contentText {
                    latestAssistantText = contentText
                }
            }
        }

        guard let activityDate = lastActivity,
              activityDate >= cutoff,
              turns > 0 || latestAssistantText != nil else {
            return nil
        }

        let pendingUserResponse = (latestUserAt ?? .distantPast) > (latestAssistantAt ?? .distantPast)
        let queuedAfterAssistant = lastQueueOperation == "enqueue"
            && (lastQueueAt ?? .distantPast) > (latestAssistantAt ?? .distantPast)
        let assistantWaitingForAction = latestAssistantNeedsAction
            && (latestAssistantAt ?? .distantPast) >= (latestUserAt ?? .distantPast)
        let isWaitingForUser = pendingUserResponse || queuedAfterAssistant || assistantWaitingForAction
        let title = aiTitle
            ?? cleanTitle(lastPrompt)
            ?? cleanTitle(firstUserText)
            ?? cwd.map(shortFolderName)
            ?? String(sessionID.prefix(8))
        let preview = cleanPreview(latestAssistantText ?? latestUserText)
        return CodexThreadItem(
            id: "claude:\(sessionID)",
            title: title,
            preview: preview,
            cwd: cwd,
            lastActivity: activityDate,
            startedAt: isWaitingForUser ? (latestUserAt ?? lastQueueAt ?? activityDate) : nil,
            externalReadAt: nil,
            status: isWaitingForUser ? .waiting : .unread,
            turns: turns,
            compressionCount: nil,
            source: "claude-code",
            isExplicitUnread: false,
            tokensUsed: nil,
            tokenBreakdown: TokenBreakdown(),
            model: nil
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

    private func rolloutSummary(fileURL: URL) -> RolloutSummary? {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        var summary = RolloutSummary()
        var previousTokenCounters = TokenBreakdown()
        text.enumerateLines { line, _ in
            if summary.cwd == nil, line.contains(#""type":"session_meta""#) {
                summary.cwd = self.extractJSONString(line: line, key: "cwd")
            }
            if line.contains(#""type":"turn_context""#),
               let cwd = self.extractJSONString(line: line, key: "cwd"),
               !cwd.isEmpty {
                summary.cwd = cwd
            }
            if summary.title == nil,
               line.contains(#""type":"response_item""#),
               line.contains(#""payload":{"type":"message""#),
               line.contains(#""type":"message""#),
               line.contains(#""role":"user""#) {
                if let candidate = self.userMessageText(from: line),
                   let title = self.displayTitleCandidate(candidate) {
                    summary.title = title
                }
            }
            if line.contains(#""type":"response_item""#),
               line.contains(#""payload":{"type":"message""#),
               line.contains(#""role":"assistant""#),
               let candidate = self.assistantMessageText(from: line),
               let preview = cleanPreview(candidate) {
                summary.preview = preview
            }
            guard line.contains(#""type":"event_msg""#) else { return }
            let eventDate = self.eventDate(from: line)
            if line.contains(#""type":"context_compacted""#) {
                summary.compressionCount += 1
            }
            if line.contains(#""type":"token_count""#),
               let currentCounters = self.tokenCounters(from: line) {
                let delta = TokenBreakdown.delta(from: previousTokenCounters, to: currentCounters)
                previousTokenCounters = currentCounters
                if delta.hasAny {
                    summary.tokenBreakdown.add(delta)
                }
            }
            if line.contains(#""type":"task_started""#) {
                summary.isRunning = true
                summary.turns += 1
                summary.lastTaskEventAt = eventDate ?? summary.lastTaskEventAt
                summary.currentTurnStartedAt = eventDate ?? summary.currentTurnStartedAt
            } else if line.contains(#""type":"task_complete""#) || line.contains(#""type":"turn_aborted""#) {
                summary.isRunning = false
                summary.lastTaskEventAt = eventDate ?? summary.lastTaskEventAt
                summary.lastCompletionAt = eventDate ?? summary.lastCompletionAt
                summary.currentTurnStartedAt = nil
                if let candidate = self.completedAgentMessageText(from: line),
                   let preview = cleanPreview(candidate) {
                    summary.preview = preview
                }
            }
        }
        return summary
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
    private static let schemaVersion = 2
    private static let readWatermarkTolerance: TimeInterval = 60
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
                runningSeenAt: decoded.runningSeenAt ?? [:]
            )
        } else {
            state = ReadStateFile(
                schemaVersion: Self.schemaVersion,
                didBaselineExistingWaiting: false,
                openedAt: [:],
                runningSeenAt: [:]
            )
        }
    }

    func visibleThreads(from items: [CodexThreadItem]) -> [CodexThreadItem] {
        lock.lock()
        var current = state
        var didChange = false
        if !current.didBaselineExistingWaiting {
            for item in items where isReadDismissible(item.status) && !item.isExplicitUnread {
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
        }

        var visible: [CodexThreadItem] = []
        for item in items {
            switch item.status {
            case .running, .stale, .waiting:
                visible.append(item)
            case .unread:
                if item.isExplicitUnread {
                    visible.append(item)
                    continue
                }
                let readAt = current.openedAt[item.id] ?? 0
                guard readAt < item.lastActivity.timeIntervalSince1970 else { continue }
                if (current.runningSeenAt?[item.id] ?? 0) > 0 {
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
        state.openedAt[item.id] = readThroughTime(for: item)
        saveLocked()
        lock.unlock()
    }

    func markRead(threadID: String, at date: Date = Date()) {
        lock.lock()
        state.openedAt[threadID] = date.timeIntervalSince1970
        saveLocked()
        lock.unlock()
    }

    func markWaitingRead(_ items: [CodexThreadItem], at date: Date = Date()) {
        lock.lock()
        for item in items where isReadDismissible(item.status) {
            state.openedAt[item.id] = readThroughTime(for: item, at: date)
        }
        state.didBaselineExistingWaiting = true
        saveLocked()
        lock.unlock()
    }

    private func readThroughTime(for item: CodexThreadItem, at date: Date = Date()) -> TimeInterval {
        max(date.timeIntervalSince1970, item.lastActivity.timeIntervalSince1970 + Self.readWatermarkTolerance)
    }

    private func saveLocked() {
        let directory = fileURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}

final class PetStatusIcon {
    private var frame = 0

    func image(status: ThreadRunStatus?, count: Int) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        let color: NSColor
        switch status {
        case .running:
            color = NSColor.systemGreen
        case .stale:
            color = NSColor.systemOrange
        case .waiting:
            color = NSColor.systemOrange
        case .unread:
            color = NSColor.systemBlue
        case nil:
            color = NSColor.white.withAlphaComponent(0.58)
        }

        let bob = status == .running ? CGFloat((frame % 2 == 0) ? 0 : -1) : 0
        let head = NSRect(x: 2, y: 3 + bob, width: 14, height: 12)
        color.withAlphaComponent(0.95).setFill()
        NSBezierPath(roundedRect: head, xRadius: 5, yRadius: 5).fill()

        color.withAlphaComponent(0.88).setStroke()
        let antenna = NSBezierPath()
        antenna.lineWidth = 1.4
        antenna.move(to: NSPoint(x: 9, y: 3 + bob))
        antenna.line(to: NSPoint(x: 9, y: 1 + bob))
        antenna.stroke()

        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(ovalIn: NSRect(x: 5, y: 8 + bob, width: 2.2, height: 2.2)).fill()
        NSBezierPath(ovalIn: NSRect(x: 10.8, y: 8 + bob, width: 2.2, height: 2.2)).fill()

        if count > 0 {
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: NSRect(x: 11.5, y: 1.5, width: 6, height: 6)).fill()
        }

        image.unlockFocus()
        image.isTemplate = false
        frame += 1
        return image
    }
}

final class PanelHeaderView: NSView {
    private let titleLabel = NSTextField(labelWithString: "Task Bar")
    private let summaryLabel = NSTextField(labelWithString: "")

    init(runningCount: Int, waitingCount: Int, unreadCount: Int) {
        super.init(frame: NSRect(x: 0, y: 0, width: menuPanelWidth, height: 58))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        summaryLabel.stringValue = summaryText(
            runningCount: runningCount,
            waitingCount: waitingCount,
            unreadCount: unreadCount
        )
        summaryLabel.font = .systemFont(ofSize: 12, weight: .medium)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.lineBreakMode = .byTruncatingTail
        addSubview(summaryLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        titleLabel.frame = NSRect(x: 16, y: 30, width: bounds.width - 32, height: 20)
        summaryLabel.frame = NSRect(x: 16, y: 12, width: bounds.width - 32, height: 17)
    }
}

final class EmptyStateView: NSView {
    private let label = NSTextField(labelWithString: "No running or unread Codex or Claude turns")

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: menuPanelWidth, height: 42))
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: 16, y: 11, width: bounds.width - 32, height: 20)
    }
}

private enum TaskTokenUnitStyle: String, CaseIterable {
    case chinese
    case english
    case exact

    var title: String {
        switch self {
        case .chinese: return "中文单位"
        case .english: return "英文单位"
        case .exact: return "具体值"
        }
    }
}

private enum TaskBarSettings {
    private static let showPlatformLabelsKey = "showPlatformLabels"
    private static let showStatusDotsKey = "showStatusDots"
    private static let tokenUnitStyleKey = "tokenUnitStyle"

    static var showPlatformLabels: Bool {
        get {
            guard UserDefaults.standard.object(forKey: showPlatformLabelsKey) != nil else {
                return true
            }
            return UserDefaults.standard.bool(forKey: showPlatformLabelsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: showPlatformLabelsKey)
        }
    }

    static var showStatusDots: Bool {
        get {
            guard UserDefaults.standard.object(forKey: showStatusDotsKey) != nil else {
                return false
            }
            return UserDefaults.standard.bool(forKey: showStatusDotsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: showStatusDotsKey)
        }
    }

    static var tokenUnitStyle: TaskTokenUnitStyle {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: tokenUnitStyleKey),
                  let style = TaskTokenUnitStyle(rawValue: rawValue) else {
                return .chinese
            }
            return style
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: tokenUnitStyleKey)
        }
    }
}

private final class TaskBarSettingsWindowController: NSWindowController {
    private let settingsView: TaskBarSettingsView
    private var hasCenteredWindow = false

    init(onSettingsChanged: @escaping () -> Void) {
        let contentView = TaskBarSettingsView(onSettingsChanged: onSettingsChanged)
        settingsView = contentView
        let window = NSWindow(
            contentRect: contentView.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Task Bar 设置"
        window.contentMinSize = NSSize(width: 680, height: 420)
        window.contentView = contentView
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(calibratedRed: 0.055, green: 0.066, blue: 0.086, alpha: 1.0)
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = [.moveToActiveSpace]
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        settingsView.reload()
        if !hasCenteredWindow {
            window?.center()
            hasCenteredWindow = true
        }
        super.showWindow(sender)
    }
}

private final class TaskBarSettingsView: NSView {
    static let preferredSize = NSSize(width: 720, height: 460)

    private let onSettingsChanged: () -> Void
    private var platformOptionRects: [Bool: NSRect] = [:]
    private var statusDotOptionRects: [Bool: NSRect] = [:]
    private var tokenUnitOptionRects: [TaskTokenUnitStyle: NSRect] = [:]

    init(onSettingsChanged: @escaping () -> Void) {
        self.onSettingsChanged = onSettingsChanged
        super.init(frame: NSRect(origin: .zero, size: Self.preferredSize))
        wantsLayer = true
        appearance = NSAppearance(named: .darkAqua)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        needsDisplay = true
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawBackground()

        let sidebarWidth = min(CGFloat(192), max(176, bounds.width * 0.26))
        drawSidebar(width: sidebarWidth)

        let content = NSRect(
            x: sidebarWidth + 28,
            y: 28,
            width: bounds.width - sidebarWidth - 56,
            height: bounds.height - 56
        )
        drawText(
            "任务栏设置",
            rect: NSRect(x: content.minX, y: content.minY, width: content.width, height: 34),
            font: .systemFont(ofSize: 26, weight: .bold),
            color: .white
        )
        drawText(
            "任务来源和列表显示偏好",
            rect: NSRect(x: content.minX, y: content.minY + 36, width: content.width, height: 20),
            font: .systemFont(ofSize: 13, weight: .medium),
            color: NSColor.white.withAlphaComponent(0.56)
        )

        let settingsCard = NSRect(x: content.minX, y: content.minY + 78, width: content.width, height: 206)
        drawPanel(settingsCard)
        drawText(
            "列表显示",
            rect: NSRect(x: settingsCard.minX + 16, y: settingsCard.minY + 16, width: settingsCard.width - 32, height: 22),
            font: .systemFont(ofSize: 16, weight: .bold),
            color: .white
        )

        let pillHeight: CGFloat = 34
        let pillGap: CGFloat = 8
        let binaryPillWidth: CGFloat = 104
        let binaryOptionX = settingsCard.maxX - 16 - binaryPillWidth * 2 - pillGap

        let labelPillY = settingsCard.minY + 48
        let showRect = NSRect(x: binaryOptionX, y: labelPillY, width: binaryPillWidth, height: pillHeight)
        let hideRect = NSRect(x: showRect.maxX + pillGap, y: labelPillY, width: binaryPillWidth, height: pillHeight)
        platformOptionRects = [true: showRect, false: hideRect]
        drawText(
            "来源标签",
            rect: NSRect(x: settingsCard.minX + 16, y: labelPillY + 7, width: binaryOptionX - settingsCard.minX - 32, height: 20),
            font: .systemFont(ofSize: 13, weight: .semibold),
            color: .white
        )
        drawSelectablePill("显示", rect: showRect, selected: TaskBarSettings.showPlatformLabels)
        drawSelectablePill("隐藏", rect: hideRect, selected: !TaskBarSettings.showPlatformLabels)

        let dotPillY = settingsCard.minY + 92
        let dotShowRect = NSRect(x: binaryOptionX, y: dotPillY, width: binaryPillWidth, height: pillHeight)
        let dotHideRect = NSRect(x: dotShowRect.maxX + pillGap, y: dotPillY, width: binaryPillWidth, height: pillHeight)
        statusDotOptionRects = [true: dotShowRect, false: dotHideRect]
        drawText(
            "状态圆点",
            rect: NSRect(x: settingsCard.minX + 16, y: dotPillY + 7, width: binaryOptionX - settingsCard.minX - 32, height: 20),
            font: .systemFont(ofSize: 13, weight: .semibold),
            color: .white
        )
        drawSelectablePill("显示", rect: dotShowRect, selected: TaskBarSettings.showStatusDots)
        drawSelectablePill("隐藏", rect: dotHideRect, selected: !TaskBarSettings.showStatusDots)

        let unitPillWidth: CGFloat = 82
        let unitStyles = TaskTokenUnitStyle.allCases
        let unitOptionX = settingsCard.maxX - 16 - unitPillWidth * CGFloat(unitStyles.count) - pillGap * CGFloat(unitStyles.count - 1)
        let unitPillY = settingsCard.minY + 136
        tokenUnitOptionRects.removeAll(keepingCapacity: true)
        drawText(
            "Token 单位",
            rect: NSRect(x: settingsCard.minX + 16, y: unitPillY + 7, width: unitOptionX - settingsCard.minX - 32, height: 20),
            font: .systemFont(ofSize: 13, weight: .semibold),
            color: .white
        )
        for (index, style) in unitStyles.enumerated() {
            let optionRect = NSRect(
                x: unitOptionX + CGFloat(index) * (unitPillWidth + pillGap),
                y: unitPillY,
                width: unitPillWidth,
                height: pillHeight
            )
            tokenUnitOptionRects[style] = optionRect
            drawSelectablePill(style.title, rect: optionRect, selected: TaskBarSettings.tokenUnitStyle == style)
        }
        drawText(
            "只影响 hover 中的输入 / 输出等 token 数字；缓存率和金额不变。",
            rect: NSRect(x: settingsCard.minX + 16, y: settingsCard.minY + 180, width: settingsCard.width - 32, height: 18),
            font: .systemFont(ofSize: 12, weight: .medium),
            color: NSColor.white.withAlphaComponent(0.52)
        )

        let statusCard = NSRect(x: content.minX, y: settingsCard.maxY + 16, width: content.width, height: 104)
        drawPanel(statusCard)
        drawText(
            "状态约定",
            rect: NSRect(x: statusCard.minX + 16, y: statusCard.minY + 16, width: statusCard.width - 32, height: 22),
            font: .systemFont(ofSize: 16, weight: .bold),
            color: .white
        )
        drawStatusLegend(
            items: [
                ("RUN", "运行中", NSColor.systemGreen),
                ("REVIEW", "待检查", NSColor.systemBlue),
                ("INPUT", "待输入", NSColor.systemOrange),
                ("DONE", "已完成", NSColor.white.withAlphaComponent(0.45))
            ],
            rect: NSRect(x: statusCard.minX + 16, y: statusCard.minY + 56, width: statusCard.width - 32, height: 42)
        )
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for (showLabels, rect) in platformOptionRects where rect.contains(point) {
            guard TaskBarSettings.showPlatformLabels != showLabels else { return }
            TaskBarSettings.showPlatformLabels = showLabels
            needsDisplay = true
            onSettingsChanged()
            return
        }
        for (showDots, rect) in statusDotOptionRects where rect.contains(point) {
            guard TaskBarSettings.showStatusDots != showDots else { return }
            TaskBarSettings.showStatusDots = showDots
            needsDisplay = true
            onSettingsChanged()
            return
        }
        for (style, rect) in tokenUnitOptionRects where rect.contains(point) {
            guard TaskBarSettings.tokenUnitStyle != style else { return }
            TaskBarSettings.tokenUnitStyle = style
            needsDisplay = true
            onSettingsChanged()
            return
        }
        super.mouseDown(with: event)
    }

    private var appBackgroundTop: NSColor {
        NSColor(calibratedRed: 0.055, green: 0.066, blue: 0.086, alpha: 1.0)
    }

    private var appBackgroundBottom: NSColor {
        NSColor(calibratedRed: 0.075, green: 0.090, blue: 0.118, alpha: 1.0)
    }

    private var sidebarBackgroundColor: NSColor {
        NSColor(calibratedRed: 0.046, green: 0.055, blue: 0.073, alpha: 1.0)
    }

    private var panelSurfaceColor: NSColor {
        NSColor(calibratedRed: 0.126, green: 0.148, blue: 0.186, alpha: 0.98)
    }

    private var inputSurfaceColor: NSColor {
        NSColor(calibratedRed: 0.088, green: 0.105, blue: 0.138, alpha: 1.0)
    }

    private var borderColor: NSColor {
        NSColor.white.withAlphaComponent(0.075)
    }

    private var accentBlue: NSColor {
        NSColor(calibratedRed: 0.365, green: 0.548, blue: 1.0, alpha: 1.0)
    }

    private var accentTeal: NSColor {
        NSColor(calibratedRed: 0.279, green: 0.839, blue: 0.702, alpha: 1.0)
    }

    private func drawBackground() {
        if let gradient = NSGradient(starting: appBackgroundTop, ending: appBackgroundBottom) {
            gradient.draw(in: bounds, angle: -90)
        } else {
            appBackgroundTop.setFill()
            bounds.fill()
        }
    }

    private func drawSidebar(width: CGFloat) {
        sidebarBackgroundColor.setFill()
        NSRect(x: 0, y: 0, width: width, height: bounds.height).fill()
        borderColor.setStroke()
        NSBezierPath(rect: NSRect(x: width, y: 0, width: 1, height: bounds.height)).stroke()

        drawText("Task Bar", rect: NSRect(x: 28, y: 28, width: width - 56, height: 28), font: .systemFont(ofSize: 20, weight: .bold), color: .white)
        drawText("Codex + Claude", rect: NSRect(x: 28, y: 58, width: width - 56, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: NSColor.white.withAlphaComponent(0.52))

        let itemRect = NSRect(x: 18, y: 118, width: width - 36, height: 42)
        accentBlue.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: itemRect, xRadius: 8, yRadius: 8).fill()
        drawText("设置", rect: NSRect(x: itemRect.minX + 22, y: itemRect.minY + 10, width: itemRect.width - 44, height: 22), font: .systemFont(ofSize: 15, weight: .semibold), color: .white)
    }

    private func drawPanel(_ rect: NSRect) {
        panelSurfaceColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        NSColor.white.withAlphaComponent(0.035).setFill()
        NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: min(1.5, rect.height)), xRadius: 0, yRadius: 0).fill()
        borderColor.setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
    }

    private func drawSelectablePill(_ title: String, rect: NSRect, selected: Bool) {
        (selected ? accentBlue.withAlphaComponent(0.72) : inputSurfaceColor.withAlphaComponent(0.82)).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        (selected ? accentTeal.withAlphaComponent(0.38) : borderColor).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
        drawCentered(title, rect: rect.insetBy(dx: 8, dy: 0), font: .systemFont(ofSize: 12, weight: .semibold), color: .white)
    }

    private func drawSmallButton(_ title: String, rect: NSRect, emphasized: Bool) {
        (emphasized ? accentBlue.withAlphaComponent(0.72) : NSColor.white.withAlphaComponent(0.12)).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        (emphasized ? accentTeal.withAlphaComponent(0.34) : NSColor.white.withAlphaComponent(0.09)).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7).stroke()
        drawCentered(title, rect: rect.insetBy(dx: 6, dy: 0), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(emphasized ? 0.96 : 0.78))
    }

    private func drawStatusLegend(items: [(String, String, NSColor)], rect: NSRect) {
        let gap: CGFloat = 10
        let itemWidth = (rect.width - gap * CGFloat(items.count - 1)) / CGFloat(items.count)
        for (index, item) in items.enumerated() {
            let itemRect = NSRect(x: rect.minX + CGFloat(index) * (itemWidth + gap), y: rect.minY, width: itemWidth, height: rect.height)
            inputSurfaceColor.withAlphaComponent(0.72).setFill()
            NSBezierPath(roundedRect: itemRect, xRadius: 8, yRadius: 8).fill()
            borderColor.setStroke()
            NSBezierPath(roundedRect: itemRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
            drawText(item.0, rect: NSRect(x: itemRect.minX + 12, y: itemRect.minY + 6, width: itemRect.width - 24, height: 16), font: .systemFont(ofSize: 11, weight: .bold), color: item.2)
            drawText(item.1, rect: NSRect(x: itemRect.minX + 12, y: itemRect.minY + 22, width: itemRect.width - 24, height: 16), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.62))
        }
    }

    private func drawText(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color])
    }

    private func drawCentered(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        let textHeight = ceil((text as NSString).boundingRect(
            with: NSSize(width: rect.width, height: 1000),
            options: [.usesLineFragmentOrigin],
            attributes: attributes
        ).height)
        let drawRect = NSRect(
            x: rect.minX,
            y: rect.minY + max(0, (rect.height - textHeight) / 2),
            width: rect.width,
            height: textHeight
        )
        (text as NSString).draw(in: drawRect, withAttributes: attributes)
    }
}

final class ThreadRowView: NSView {
    private let item: CodexThreadItem
    private let onOpen: (String) -> Void
    private let showPlatformLabel: Bool
    private let showStatusDot: Bool
    private let statusDot = NSView()
    private let statusLabelView = NSTextField(labelWithString: "")
    private let statusElapsedLabel = NSTextField(labelWithString: "")
    private let platformLabelView = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private var trackingAreaRef: NSTrackingArea?
    private var elapsedTimer: Timer?
    private var isHovering = false {
        didSet { needsDisplay = true }
    }

    init(item: CodexThreadItem, showPlatformLabel: Bool, showStatusDot: Bool, onOpen: @escaping (String) -> Void) {
        self.item = item
        self.showPlatformLabel = showPlatformLabel
        self.showStatusDot = showStatusDot
        self.onOpen = onOpen
        super.init(frame: NSRect(x: 0, y: 0, width: menuPanelWidth, height: 76))
        wantsLayer = true
        let tooltip = tooltipText(for: item)
        setAccessibilityHelp(tooltip)

        statusDot.wantsLayer = true
        statusDot.layer?.backgroundColor = statusColor(item.status).cgColor
        statusDot.layer?.cornerRadius = 4
        statusDot.isHidden = !showStatusDot
        addSubview(statusDot)

        statusLabelView.stringValue = compactStatusLabel(item.status)
        statusLabelView.font = .systemFont(ofSize: 11, weight: .semibold)
        statusLabelView.textColor = statusColor(item.status)
        statusLabelView.lineBreakMode = .byTruncatingTail
        addSubview(statusLabelView)

        statusElapsedLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        statusElapsedLabel.textColor = .secondaryLabelColor
        statusElapsedLabel.lineBreakMode = .byTruncatingTail
        statusElapsedLabel.maximumNumberOfLines = 1
        addSubview(statusElapsedLabel)
        updateElapsedLabel()

        platformLabelView.stringValue = sourceLabel(item)
        platformLabelView.font = .systemFont(ofSize: 9, weight: .semibold)
        platformLabelView.textColor = sourceColor(item)
        platformLabelView.lineBreakMode = .byTruncatingTail
        platformLabelView.maximumNumberOfLines = 1
        platformLabelView.isHidden = !showPlatformLabel
        addSubview(platformLabelView)

        titleLabel.stringValue = item.title
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        addSubview(titleLabel)

        detailLabel.stringValue = item.preview ?? detailText(for: item)
        detailLabel.font = .systemFont(ofSize: 12, weight: .medium)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 3
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.cell?.wraps = true
        detailLabel.cell?.isScrollable = false
        addSubview(detailLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect], owner: self)
        trackingAreaRef = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        ThreadHoverPanel.shared.show(item: item, from: self)
    }

    override func mouseMoved(with event: NSEvent) {
        guard isHovering else { return }
        ThreadHoverPanel.shared.show(item: item, from: self)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        ThreadHoverPanel.shared.hide(owner: self)
    }

    override func mouseUp(with event: NSEvent) {
        ThreadHoverPanel.shared.hide(owner: self)
        onOpen(item.id)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            ThreadHoverPanel.shared.hide(owner: self)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopElapsedTimer()
        } else {
            updateElapsedLabel()
            startElapsedTimerIfNeeded()
        }
    }

    deinit {
        stopElapsedTimer()
        ThreadHoverPanel.shared.hide(owner: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isHovering else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 4), xRadius: 8, yRadius: 8).fill()
    }

    override func layout() {
        super.layout()
        let statusTextX: CGFloat = showStatusDot ? 34 : 18
        let statusColumnWidth: CGFloat = showStatusDot ? 62 : 76
        let contentX: CGFloat = 104
        let contentWidth = max(160, bounds.width - contentX - 16)
        statusDot.frame = NSRect(x: 17, y: 54, width: 8, height: 8)
        statusLabelView.frame = NSRect(x: statusTextX, y: 48, width: statusColumnWidth, height: 18)
        statusElapsedLabel.frame = NSRect(x: statusTextX, y: 30, width: statusColumnWidth, height: 16)
        platformLabelView.frame = NSRect(x: statusTextX, y: 12, width: statusColumnWidth, height: 14)
        titleLabel.frame = NSRect(x: contentX, y: 49, width: contentWidth, height: 20)
        detailLabel.frame = NSRect(x: contentX, y: 15, width: contentWidth, height: 34)
    }

    private func startElapsedTimerIfNeeded() {
        guard elapsedTimer == nil, statusElapsedText(for: item) != nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateElapsedLabel()
        }
        elapsedTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func updateElapsedLabel() {
        let text = statusElapsedText(for: item) ?? ""
        statusElapsedLabel.stringValue = text
        statusElapsedLabel.isHidden = text.isEmpty
    }
}

private struct ThreadTooltipRow {
    let label: String
    let value: String
    let valueColor: NSColor
    let gapBefore: CGFloat
    let emphasized: Bool

    init(
        _ label: String,
        _ value: String,
        valueColor: NSColor = NSColor.white.withAlphaComponent(0.88),
        gapBefore: CGFloat = 0,
        emphasized: Bool = false
    ) {
        self.label = label
        self.value = value
        self.valueColor = valueColor
        self.gapBefore = gapBefore
        self.emphasized = emphasized
    }
}

private final class ThreadHoverPanel {
    static let shared = ThreadHoverPanel()

    private weak var owner: NSView?
    private let tooltipView = ThreadTooltipView()
    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 132),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.contentView = tooltipView
        return panel
    }()

    func show(item: CodexThreadItem, from sourceView: NSView) {
        owner = sourceView
        tooltipView.rows = tooltipRows(for: item)
        let size = tooltipView.preferredSize
        tooltipView.frame = NSRect(origin: .zero, size: size)
        panel.setFrame(NSRect(origin: origin(for: size), size: size), display: true)
        panel.orderFrontRegardless()
    }

    func hide(owner sourceView: NSView) {
        guard owner === sourceView else { return }
        owner = nil
        panel.orderOut(nil)
    }

    func hideAll() {
        owner = nil
        panel.orderOut(nil)
    }

    private func origin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let visibleFrame = NSScreen.screens.first { $0.frame.contains(mouse) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let margin: CGFloat = 8
        var x = mouse.x + 16
        var y = mouse.y - size.height - 12

        if x + size.width > visibleFrame.maxX - margin {
            x = mouse.x - size.width - 16
        }
        if y < visibleFrame.minY + margin {
            y = mouse.y + 16
        }

        x = min(max(x, visibleFrame.minX + margin), visibleFrame.maxX - size.width - margin)
        y = min(max(y, visibleFrame.minY + margin), visibleFrame.maxY - size.height - margin)
        return NSPoint(x: x, y: y)
    }
}

private final class ThreadTooltipView: NSView {
    var rows: [ThreadTooltipRow] = [] {
        didSet { needsDisplay = true }
    }

    private let horizontalPadding: CGFloat = 10
    private let verticalPadding: CGFloat = 5
    private let labelValueGap: CGFloat = 16
    private let rowHeight: CGFloat = 16
    private let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
    private let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
    private let emphasizedValueFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)

    override var isFlipped: Bool { true }

    var preferredSize: NSSize {
        let labelWidth = measuredLabelWidth
        let valueWidth = min(max(measuredValueWidth, 86), 208)
        let gaps = rows.reduce(CGFloat(0)) { $0 + $1.gapBefore }
        let width = max(220, horizontalPadding * 2 + labelWidth + labelValueGap + valueWidth)
        let height = verticalPadding * 2 + CGFloat(rows.count) * rowHeight + gaps
        return NSSize(width: ceil(width), height: ceil(height))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        NSColor(calibratedWhite: 0.025, alpha: 0.96).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()

        NSColor.white.withAlphaComponent(0.16).setStroke()
        let border = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        border.lineWidth = 1
        border.stroke()

        let labelWidth = measuredLabelWidth
        let valueX = horizontalPadding + labelWidth + labelValueGap
        let valueWidth = bounds.width - valueX - horizontalPadding
        var y = verticalPadding

        for row in rows {
            y += row.gapBefore
            drawText(
                row.label,
                rect: NSRect(x: horizontalPadding, y: y, width: labelWidth, height: rowHeight),
                font: labelFont,
                color: NSColor.white.withAlphaComponent(0.62)
            )
            drawText(
                row.value,
                rect: NSRect(x: valueX, y: y, width: valueWidth, height: rowHeight),
                font: row.emphasized ? emphasizedValueFont : valueFont,
                color: row.valueColor
            )
            y += rowHeight
        }
    }

    private var measuredLabelWidth: CGFloat {
        let width = rows
            .map { textWidth($0.label, font: labelFont) }
            .max() ?? 0
        return min(max(ceil(width), 56), 78)
    }

    private var measuredValueWidth: CGFloat {
        rows
            .map { textWidth($0.value, font: $0.emphasized ? emphasizedValueFont : valueFont) }
            .max() ?? 0
    }

    private func textWidth(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    private func drawText(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }
}

final class MenuSeparatorView: NSView {
    init(inset: CGFloat = 16) {
        self.inset = inset
        super.init(frame: NSRect(x: 0, y: 0, width: menuPanelWidth, height: 7))
        wantsLayer = true
        layer?.backgroundColor = menuPanelBackground.cgColor
    }

    private let inset: CGFloat

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor(calibratedWhite: 0.33, alpha: 0.72).setFill()
        NSRect(x: inset, y: floor(bounds.height / 2), width: bounds.width - inset * 2, height: 1).fill()
    }
}

final class CommandRowView: NSView {
    private let iconView = NSImageView(frame: .zero)
    private let titleLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let action: () -> Void
    private var trackingAreaRef: NSTrackingArea?
    private var isHovering = false {
        didSet { needsDisplay = true }
    }
    private let enabled: Bool

    init(title: String, symbolName: String, shortcut: String?, enabled: Bool = true, action: @escaping () -> Void) {
        self.action = action
        self.enabled = enabled
        super.init(frame: NSRect(x: 0, y: 0, width: menuPanelWidth, height: 27))
        wantsLayer = true
        layer?.backgroundColor = menuPanelBackground.cgColor

        let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        iconView.image = symbol?.withSymbolConfiguration(config)
        iconView.contentTintColor = enabled ? .labelColor : .disabledControlTextColor
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = enabled ? .labelColor : .disabledControlTextColor
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        shortcutLabel.stringValue = shortcut ?? ""
        shortcutLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        shortcutLabel.textColor = .secondaryLabelColor
        shortcutLabel.alignment = .right
        addSubview(shortcutLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        trackingAreaRef = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        guard enabled else { return }
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
    }

    override func mouseUp(with event: NSEvent) {
        guard enabled else { return }
        action()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isHovering else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 12, dy: 3), xRadius: 6, yRadius: 6).fill()
    }

    override func layout() {
        super.layout()
        iconView.frame = NSRect(x: 16, y: 6, width: 15, height: 15)
        shortcutLabel.frame = NSRect(x: bounds.width - 58, y: 5, width: 42, height: 16)
        titleLabel.frame = NSRect(x: 46, y: 4, width: bounds.width - 108, height: 18)
    }
}

private final class CommandButtonBarView: NSView {
    private let stackView = NSStackView()
    private var buttons: [NSButton] = []

    init(
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        super.init(frame: NSRect(x: 0, y: 0, width: menuPanelWidth, height: 56))
        wantsLayer = true
        layer?.backgroundColor = menuPanelBackground.cgColor

        stackView.orientation = .horizontal
        stackView.spacing = 8
        stackView.distribution = .fillEqually
        addSubview(stackView)

        addButton(title: "设置", symbolName: "gearshape", action: onOpenSettings)
        addButton(title: "退出", symbolName: "power", action: onQuit)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func addButton(title: String, symbolName: String, isActive: Bool = false, action: @escaping () -> Void) {
        let button = TaskBarActionButton(title: title, action: action)
        styleButton(button, title: title, symbolName: symbolName, isActive: isActive)
        buttons.append(button)
        stackView.addArrangedSubview(button)
    }

    private func styleButton(_ button: NSButton, title: String, symbolName: String, isActive: Bool) {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 7
        button.layer?.backgroundColor = NSColor(calibratedWhite: 0.24, alpha: 1).cgColor
        button.layer?.borderWidth = 1
        button.layer?.borderColor = (isActive ? NSColor.controlAccentColor.withAlphaComponent(0.55) : NSColor.white.withAlphaComponent(0.14)).cgColor
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.alignment = .center
        button.contentTintColor = isActive ? NSColor.controlAccentColor : NSColor.white.withAlphaComponent(0.9)
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.toolTip = title

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let color = NSColor.white.withAlphaComponent(0.9)
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
        button.attributedAlternateTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ])
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        image?.isTemplate = true
        button.image = image
    }

    override func layout() {
        super.layout()
        stackView.frame = NSRect(x: 16, y: 8, width: bounds.width - 32, height: 40)
    }
}

private final class TaskBarActionButton: NSButton {
    private let handler: () -> Void

    init(title: String, action: @escaping () -> Void) {
        handler = action
        super.init(frame: .zero)
        self.title = title
        target = self
        self.action = #selector(runAction)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func runAction() {
        handler()
    }
}

private final class TaskBarRowsView: NSView {
    private let arrangedViews: [NSView]
    private let arrangedHeights: [CGFloat]

    init(rowViews: [NSView]) {
        arrangedViews = rowViews
        arrangedHeights = rowViews.map(\.frame.height)
        let height = arrangedHeights.reduce(CGFloat(0), +)
        super.init(frame: NSRect(x: 0, y: 0, width: menuPanelWidth, height: height))
        wantsLayer = true
        layer?.backgroundColor = menuPanelBackground.cgColor
        for view in rowViews {
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        var y: CGFloat = 0
        for (index, view) in arrangedViews.enumerated() {
            let height = arrangedHeights[index]
            view.frame = NSRect(x: 0, y: y, width: bounds.width, height: height)
            y += height
        }
    }
}

private final class TaskBarPopoverContentView: NSView {
    private let headerView: PanelHeaderView
    private let topSeparator = MenuSeparatorView()
    private let rowsView: TaskBarRowsView
    private let rowsScrollView: NSScrollView?
    private let bottomSeparator = MenuSeparatorView()
    private let commandBar: CommandButtonBarView
    private let rowsViewportHeight: CGFloat
    private let rowsContentHeight: CGFloat

    init(
        threads: [CodexThreadItem],
        runningCount: Int,
        waitingCount: Int,
        unreadCount: Int,
        showPlatformLabels: Bool,
        showStatusDots: Bool,
        onOpenThread: @escaping (String) -> Void,
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        headerView = PanelHeaderView(
            runningCount: runningCount,
            waitingCount: waitingCount,
            unreadCount: unreadCount
        )
        let rowViews: [NSView]
        if threads.isEmpty {
            rowViews = [EmptyStateView()]
        } else {
            rowViews = threads.map { thread in
                ThreadRowView(
                    item: thread,
                    showPlatformLabel: showPlatformLabels,
                    showStatusDot: showStatusDots,
                    onOpen: onOpenThread
                )
            }
        }
        rowsView = TaskBarRowsView(rowViews: rowViews)
        rowsContentHeight = rowsView.frame.height
        commandBar = CommandButtonBarView(
            onOpenSettings: onOpenSettings,
            onQuit: onQuit
        )

        let fixedHeight = headerView.frame.height
            + topSeparator.frame.height
            + bottomSeparator.frame.height
            + commandBar.frame.height
        let maxRowsHeight = max(EmptyStateView().frame.height, taskBarPopoverMaxHeight() - fixedHeight)
        rowsViewportHeight = min(rowsContentHeight, maxRowsHeight)

        if rowsContentHeight > rowsViewportHeight + 0.5 {
            let scrollView = NSScrollView(frame: .zero)
            scrollView.borderType = .noBorder
            scrollView.drawsBackground = false
            scrollView.hasVerticalScroller = true
            scrollView.autohidesScrollers = true
            scrollView.scrollerStyle = .overlay
            scrollView.documentView = rowsView
            rowsScrollView = scrollView
        } else {
            rowsScrollView = nil
        }

        let totalHeight = fixedHeight + rowsViewportHeight
        super.init(frame: NSRect(x: 0, y: 0, width: menuPanelWidth, height: totalHeight))
        wantsLayer = true
        layer?.backgroundColor = menuPanelBackground.cgColor
        appearance = NSAppearance(named: .darkAqua)

        addSubview(headerView)
        addSubview(topSeparator)
        if let rowsScrollView {
            addSubview(rowsScrollView)
        } else {
            addSubview(rowsView)
        }
        addSubview(bottomSeparator)
        addSubview(commandBar)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        var y: CGFloat = 0
        headerView.frame = NSRect(x: 0, y: y, width: bounds.width, height: headerView.frame.height)
        y += headerView.frame.height

        topSeparator.frame = NSRect(x: 0, y: y, width: bounds.width, height: topSeparator.frame.height)
        y += topSeparator.frame.height

        let rowsFrame = NSRect(x: 0, y: y, width: bounds.width, height: rowsViewportHeight)
        if let rowsScrollView {
            rowsScrollView.frame = rowsFrame
            rowsView.frame = NSRect(x: 0, y: 0, width: rowsScrollView.contentSize.width, height: rowsContentHeight)
        } else {
            rowsView.frame = rowsFrame
        }
        y += rowsViewportHeight

        bottomSeparator.frame = NSRect(x: 0, y: y, width: bounds.width, height: bottomSeparator.frame.height)
        y += bottomSeparator.frame.height

        commandBar.frame = NSRect(x: 0, y: y, width: bounds.width, height: commandBar.frame.height)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let reader = CodexActivityReader()
    private let icon = PetStatusIcon()
    private let readState = ReadStateStore()
    private var threads: [CodexThreadItem] = []
    private var refreshTimer: Timer?
    private var animationTimer: Timer?
    private var settingsWindowController: TaskBarSettingsWindowController?
    private var readInFlight = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        configureStatusButton()
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            self?.updateStatusIcon()
        }
    }

    private func refresh() {
        guard !readInFlight else { return }
        readInFlight = true
        DispatchQueue.global(qos: .utility).async {
            let items = self.reader.read()
            let visible = self.readState.visibleThreads(from: items)
            DispatchQueue.main.async {
                self.readInFlight = false
                self.threads = visible
                self.updateStatusIcon()
                if self.popover.isShown {
                    self.rebuildPopover()
                }
            }
        }
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.toolTip = "Task Bar"
        button.action = #selector(togglePopover)
        button.target = self
    }

    private func updateStatusIcon() {
        let primaryStatus = threads.map(\.status).sorted { statusDisplayRank($0) < statusDisplayRank($1) }.first
        let runningCount = threads.filter { $0.status == .running || $0.status == .stale }.count
        let unreadCount = threads.filter { isReadDismissible($0.status) }.count
        let totalCount = runningCount + unreadCount
        statusItem.button?.image = icon.image(status: primaryStatus, count: totalCount)
        statusItem.button?.imagePosition = .imageLeading
        if totalCount > 0 {
            statusItem.button?.title = " \(totalCount)"
        } else {
            statusItem.button?.title = ""
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        rebuildPopover()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        refresh()
    }

    private func rebuildPopover() {
        let active = threads.filter { $0.status == .running || $0.status == .stale }
        let waitingCount = threads.filter { $0.status == .waiting }.count
        let unreadCount = threads.filter { $0.status == .unread }.count
        let content = TaskBarPopoverContentView(
            threads: threads,
            runningCount: active.count,
            waitingCount: waitingCount,
            unreadCount: unreadCount,
            showPlatformLabels: TaskBarSettings.showPlatformLabels,
            showStatusDots: TaskBarSettings.showStatusDots,
            onOpenThread: { [weak self] id in
                self?.openThread(id: id)
            },
            onOpenSettings: { [weak self] in
                self?.openSettingsWindow()
            },
            onQuit: { [weak self] in
                self?.popover.performClose(nil)
                ThreadHoverPanel.shared.hideAll()
                self?.quit()
            }
        )
        let controller = NSViewController()
        controller.view = content
        controller.preferredContentSize = content.frame.size
        popover.contentViewController = controller
        popover.contentSize = content.frame.size
    }

    private func openSettingsWindow() {
        popover.performClose(nil)
        ThreadHoverPanel.shared.hideAll()
        if settingsWindowController == nil {
            settingsWindowController = TaskBarSettingsWindowController { [weak self] in
                ThreadHoverPanel.shared.hideAll()
                if self?.popover.isShown == true {
                    self?.rebuildPopover()
                }
            }
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openThread(id: String) {
        let selectedItem = threads.first(where: { $0.id == id })
        if let item = selectedItem {
            readState.markRead(item)
        } else {
            readState.markRead(threadID: id)
        }
        threads.removeAll { $0.id == id && isReadDismissible($0.status) }
        updateStatusIcon()
        if popover.isShown {
            rebuildPopover()
            popover.performClose(nil)
        }
        ThreadHoverPanel.shared.hideAll()

        if let selectedItem, isClaudeThread(selectedItem) {
            openClaudeApp(fallbackFolder: selectedItem.cwd)
            return
        }
        if id.hasPrefix("claude:") {
            openClaudeApp(fallbackFolder: nil)
            return
        }

        guard let url = URL(string: "codex://threads/\(id)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func openClaudeApp(fallbackFolder: String?) {
        let claudeURL = URL(fileURLWithPath: "/Applications/Claude.app")
        if FileManager.default.fileExists(atPath: claudeURL.path) {
            NSWorkspace.shared.open(claudeURL)
        } else if let fallbackFolder {
            NSWorkspace.shared.open(URL(fileURLWithPath: fallbackFolder, isDirectory: true))
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private func summaryText(runningCount: Int, waitingCount: Int, unreadCount: Int) -> String {
    if runningCount == 0 && waitingCount == 0 && unreadCount == 0 {
        return "All caught up"
    }
    var parts: [String] = []
    if runningCount > 0 {
        parts.append("\(runningCount) running")
    }
    if waitingCount > 0 {
        parts.append("\(waitingCount) waiting")
    }
    if unreadCount > 0 {
        parts.append("\(unreadCount) unread")
    }
    return parts.joined(separator: "  ·  ")
}

private func statusColor(_ status: ThreadRunStatus) -> NSColor {
    switch status {
    case .running:
        return NSColor(calibratedRed: 0.35, green: 0.74, blue: 0.38, alpha: 1)
    case .stale:
        return NSColor(calibratedRed: 0.82, green: 0.58, blue: 0.30, alpha: 1)
    case .waiting:
        return NSColor(calibratedRed: 0.91, green: 0.48, blue: 0.28, alpha: 1)
    case .unread:
        return NSColor(calibratedRed: 0.36, green: 0.62, blue: 0.91, alpha: 1)
    }
}

private func compactStatusLabel(_ status: ThreadRunStatus) -> String {
    switch status {
    case .running:
        return "RUN"
    case .stale:
        return "SLOW"
    case .waiting:
        return "WAIT"
    case .unread:
        return "UNREAD"
    }
}

private func statusRank(_ status: ThreadRunStatus) -> Int {
    switch status {
    case .stale: return 0
    case .running: return 1
    case .waiting: return 2
    case .unread: return 3
    }
}

private func statusDisplayRank(_ status: ThreadRunStatus) -> Int {
    switch status {
    case .waiting: return 0
    case .unread: return 1
    case .stale: return 2
    case .running: return 3
    }
}

private func stableThreadOrder(_ lhs: CodexThreadItem, _ rhs: CodexThreadItem) -> Bool {
    let lhsRank = statusDisplayRank(lhs.status)
    let rhsRank = statusDisplayRank(rhs.status)
    if lhsRank != rhsRank { return lhsRank < rhsRank }

    let lhsID = lhs.id.lowercased()
    let rhsID = rhs.id.lowercased()
    if lhsID != rhsID { return lhsID > rhsID }

    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
}

private func statusLabel(_ status: ThreadRunStatus) -> String {
    switch status {
    case .running: return "Running"
    case .stale: return "Running"
    case .waiting: return "Waiting"
    case .unread: return "Unread"
    }
}

private func detailText(for item: CodexThreadItem) -> String {
    let folder = shortFolderName(item.cwd)
    if item.status == .running || item.status == .stale {
        return folder
    }
    return "\(folder)  ·  \(relative(item.lastActivity))"
}

private func statusElapsedText(for item: CodexThreadItem) -> String? {
    switch item.status {
    case .running, .stale:
        guard let startedAt = item.startedAt else { return nil }
        return compactDurationSinceChinese(startedAt)
    case .waiting:
        return compactDurationSinceChinese(item.lastActivity)
    case .unread:
        return compactDurationSinceChinese(item.lastActivity)
    }
}

private func tooltipText(for item: CodexThreadItem) -> String {
    tooltipRows(for: item)
        .map { "\($0.label): \($0.value)" }
        .joined(separator: "\n")
}

private func tooltipRows(for item: CodexThreadItem) -> [ThreadTooltipRow] {
    var rows: [ThreadTooltipRow] = []
    rows.append(ThreadTooltipRow("状态", tooltipStatusLabel(item.status), valueColor: statusColor(item.status), emphasized: true))
    appendTokenBreakdownRows(to: &rows, item.tokenBreakdown)
    rows.append(ThreadTooltipRow("对话轮次", item.turns > 0 ? "\(item.turns)" : "未知", gapBefore: item.tokenBreakdown.hasAny ? 2 : 0))
    if let compressionCount = item.compressionCount {
        rows.append(ThreadTooltipRow("压缩次数", "\(compressionCount)"))
    }
    if let model = item.model, !model.isEmpty {
        rows.append(ThreadTooltipRow("模型", model))
    }
    return rows
}

private func appendTokenBreakdownRows(to rows: inout [ThreadTooltipRow], _ breakdown: TokenBreakdown) {
    if breakdown.hasDetailedCounters {
        rows.append(ThreadTooltipRow("输入", compactTokenCount(breakdown.input), gapBefore: 2))
        rows.append(ThreadTooltipRow("输出", compactTokenCount(breakdown.output)))
        if let cacheRate = cacheRateText(for: breakdown) {
            rows.append(ThreadTooltipRow("缓存率", cacheRate))
        }
        return
    }

    if let total = breakdown.displayTotal {
        rows.append(ThreadTooltipRow("Token 消耗", compactTokenCount(total), gapBefore: 2))
    }
}

private func tooltipStatusLabel(_ status: ThreadRunStatus) -> String {
    switch status {
    case .running: return "运行中"
    case .stale: return "运行较久"
    case .waiting: return "等待输入"
    case .unread: return "未读"
    }
}

private let menuPanelWidth: CGFloat = 390
private let menuPanelBackground = NSColor(calibratedWhite: 0.105, alpha: 0.97)

private func taskBarPopoverMaxHeight() -> CGFloat {
    let mouse = NSEvent.mouseLocation
    let screenHeight = NSScreen.screens.first { $0.frame.contains(mouse) }?.visibleFrame.height
        ?? NSScreen.main?.visibleFrame.height
        ?? 900
    return min(440, max(320, screenHeight - 110))
}

private func isReadDismissible(_ status: ThreadRunStatus) -> Bool {
    switch status {
    case .waiting, .unread:
        return true
    case .running, .stale:
        return false
    }
}

private func isClaudeThread(_ item: CodexThreadItem) -> Bool {
    item.source == "claude-code" || item.id.hasPrefix("claude:")
}

private func sourceLabel(_ item: CodexThreadItem) -> String {
    isClaudeThread(item) ? "Claude" : "Codex"
}

private func sourceColor(_ item: CodexThreadItem) -> NSColor {
    if isClaudeThread(item) {
        return NSColor(calibratedRed: 0.91, green: 0.48, blue: 0.28, alpha: 1)
    }
    return NSColor(calibratedRed: 0.45, green: 0.58, blue: 1.0, alpha: 1)
}

private func mergedCompressionCount(_ existing: Int?, _ candidate: Int) -> Int? {
    guard let existing else { return candidate }
    return max(existing, candidate)
}

private func cleanTitle(_ value: String?) -> String? {
    guard let value else { return nil }
    let compact = normalizedTitleText(value)
    guard !compact.isEmpty else { return nil }
    guard !isUninformativeTitle(compact) else { return nil }
    if compact.count <= 68 {
        return compact
    }
    return String(compact.prefix(65)) + "..."
}

private func cleanTitleCandidate(_ values: String?...) -> String? {
    for value in values {
        if let title = cleanTitle(value) {
            return title
        }
    }
    return nil
}

private func normalizedTitleText(_ value: String) -> String {
    let withoutMarkup = removingBareURLs(
        from: replacingMarkdownLinksWithLabels(
            in: removingMediaMarkup(
                from: removingPluginMarkdownLinks(from: value)
            )
        )
    )
    return withoutMarkup
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\t", with: " ")
        .replacingOccurrences(of: "`", with: "")
        .replacingOccurrences(of: "[", with: " ")
        .replacingOccurrences(of: "]", with: " ")
        .replacingOccurrences(of: "(", with: " ")
        .replacingOccurrences(of: ")", with: " ")
        .split(separator: " ")
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func isUninformativeTitle(_ value: String) -> Bool {
    let lower = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !lower.isEmpty else { return true }
    if lower.hasPrefix("http://")
        || lower.hasPrefix("https://")
        || lower.hasPrefix("www.")
        || lower.hasPrefix("plugin://")
        || lower.hasPrefix("file://")
        || lower.hasPrefix("/var/folders/")
        || lower.hasPrefix("/tmp/")
        || lower.hasPrefix("<image")
        || lower.hasPrefix("image name=")
        || lower.hasPrefix("# files mentioned")
        || lower == "image"
        || lower == "unknown" {
        return true
    }
    if lower.contains("<image")
        || lower.contains("</image>")
        || lower.contains("codex-clipboard-")
        || lower.contains("automation_id")
        || lower.contains("<heartbeat") {
        return true
    }
    let punctuation = CharacterSet(charactersIn: "[](){}<>`'\"·,.;:：/\\|-_ ")
    let stripped = lower.trimmingCharacters(in: punctuation)
    if stripped.isEmpty { return true }
    if looksLikeURLHost(stripped) { return true }
    return false
}

private func removingMediaMarkup(from value: String) -> String {
    var result = value
    result = result.replacingOccurrences(
        of: #"!\[[^\]]*\]\([^\)]*\)"#,
        with: " ",
        options: .regularExpression
    )
    result = result.replacingOccurrences(
        of: #"<image\b[^>]*>.*?</image>"#,
        with: " ",
        options: [.regularExpression, .caseInsensitive]
    )
    result = result.replacingOccurrences(
        of: #"<image\b[^>]*>"#,
        with: " ",
        options: [.regularExpression, .caseInsensitive]
    )
    return result
}

private func replacingMarkdownLinksWithLabels(in value: String) -> String {
    var result = ""
    var index = value.startIndex

    while index < value.endIndex {
        if value[index] == "[",
           let closeBracket = value[index...].firstIndex(of: "]") {
            let openParen = value.index(after: closeBracket)
            if openParen < value.endIndex,
               value[openParen] == "(",
               let closeParen = value[openParen...].firstIndex(of: ")") {
                let label = String(value[value.index(after: index)..<closeBracket])
                if !isUninformativeLinkLabel(label) {
                    result.append(label)
                }
                result.append(" ")
                index = value.index(after: closeParen)
                continue
            }
        }

        result.append(value[index])
        index = value.index(after: index)
    }

    return result
}

private func removingBareURLs(from value: String) -> String {
    value
        .replacingOccurrences(
            of: #"(?i)\b(?:https?://|www\.)\S+"#,
            with: " ",
            options: .regularExpression
        )
        .replacingOccurrences(
            of: #"(?i)\b[a-z0-9.-]+\.(?:com|net|org|io|ai|cn|co|dev|app|site|xyz)(?:/\S*)?"#,
            with: " ",
            options: .regularExpression
        )
}

private func isUninformativeLinkLabel(_ value: String) -> Bool {
    let compact = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if compact.isEmpty { return true }
    let lower = compact.lowercased()
    return lower.hasPrefix("http://")
        || lower.hasPrefix("https://")
        || lower.hasPrefix("www.")
        || looksLikeURLHost(lower)
}

private func looksLikeURLHost(_ value: String) -> Bool {
    guard value.contains(".") else { return false }
    let lower = value.lowercased()
    let hostSuffixes = [".com", ".net", ".org", ".io", ".ai", ".cn", ".co", ".dev", ".app", ".site", ".xyz"]
    return hostSuffixes.contains { suffix in
        lower == String(lower.prefix(max(0, lower.count - suffix.count))) + suffix
            || lower.contains("\(suffix)/")
    }
}

private func cleanPreview(_ value: String?) -> String? {
    guard let value else { return nil }
    let rawCompact = value
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\t", with: " ")
        .split(separator: " ")
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !rawCompact.isEmpty else { return nil }

    guard let previewCandidate = automationPreviewText(from: rawCompact) else {
        return nil
    }
    let compact = removingPluginMarkdownLinks(from: previewCandidate)
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\t", with: " ")
        .split(separator: " ")
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !compact.isEmpty else { return nil }
    if compact.count <= 140 {
        return compact
    }
    return String(compact.prefix(137)) + "..."
}

private func automationPreviewText(from value: String) -> String? {
    let lower = value.lowercased()
    let isAutomationPayload = lower.contains("<heartbeat")
        || lower.contains("<automation_id>")
        || lower.contains("<decision>")
    guard isAutomationPayload else { return value }

    if lower.contains("<decision>dont_notify</decision>") {
        return nil
    }
    if let message = xmlTagValue("message", in: value),
       !message.isEmpty {
        return stripXMLTags(from: message)
    }
    return nil
}

private func xmlTagValue(_ tag: String, in value: String) -> String? {
    let openTag = "<\(tag)>"
    let closeTag = "</\(tag)>"
    guard let start = value.range(of: openTag, options: [.caseInsensitive]),
          let end = value.range(of: closeTag, options: [.caseInsensitive], range: start.upperBound..<value.endIndex) else {
        return nil
    }
    return String(value[start.upperBound..<end.lowerBound])
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func stripXMLTags(from value: String) -> String {
    var result = ""
    var insideTag = false
    for character in value {
        if character == "<" {
            insideTag = true
            result.append(" ")
            continue
        }
        if character == ">" {
            insideTag = false
            continue
        }
        if !insideTag {
            result.append(character)
        }
    }
    return result
}

private func removingPluginMarkdownLinks(from value: String) -> String {
    var result = ""
    var index = value.startIndex

    while index < value.endIndex {
        if value[index] == "[",
           let closeBracket = value[index...].firstIndex(of: "]") {
            let openParen = value.index(after: closeBracket)
            if openParen < value.endIndex,
               value[openParen] == "(" {
                let urlStart = value.index(after: openParen)
                if value[urlStart...].hasPrefix("plugin://"),
                   let closeParen = value[urlStart...].firstIndex(of: ")") {
                    index = value.index(after: closeParen)
                    continue
                }
            }
        }

        result.append(value[index])
        index = value.index(after: index)
    }

    return result
}

private func shortFolderName(_ value: String?) -> String {
    guard let value, !value.isEmpty else { return "unknown" }
    let last = URL(fileURLWithPath: value).lastPathComponent
    return last.isEmpty ? value : last
}

private func unique(_ urls: [URL]) -> [URL] {
    var seen = Set<String>()
    var result: [URL] = []
    for url in urls {
        let key = (url.standardizedFileURL.path as NSString).standardizingPath
        guard !seen.contains(key) else { continue }
        seen.insert(key)
        result.append(url.standardizedFileURL)
    }
    return result
}

private func maxDate(_ lhs: Date, _ rhs: Date?) -> Date {
    guard let rhs else { return lhs }
    return lhs > rhs ? lhs : rhs
}

private func maxOptionalDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
    guard let lhs else { return rhs }
    guard let rhs else { return lhs }
    return lhs > rhs ? lhs : rhs
}

private func unixDate(seconds: Double) -> Date {
    Date(timeIntervalSince1970: normalizedUnixSeconds(seconds))
}

private func normalizedUnixSeconds(_ value: Double) -> Double {
    value > 10_000_000_000 ? value / 1000 : value
}

private func iso8601Date(_ value: String) -> Date? {
    if let date = ISO8601DateFormatter.codexPetBarWithFractionalSeconds.date(from: value) {
        return date
    }
    return ISO8601DateFormatter.codexPetBar.date(from: value)
}

private func string(_ value: Any?) -> String? {
    if let value = value as? String { return value }
    if let value { return "\(value)" }
    return nil
}

private func double(_ value: Any?) -> Double? {
    if let value = value as? Double { return value }
    if let value = value as? Int { return Double(value) }
    if let value = value as? Int64 { return Double(value) }
    if let value = value as? String { return Double(value) }
    return nil
}

private func intValue(_ value: Any?) -> Int? {
    if let value = value as? Int { return value }
    if let value = value as? Int64 { return Int(value) }
    if let value = value as? Double { return Int(value) }
    if let value = value as? String { return Int(value) }
    return nil
}

private func formatInteger(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
}

private func compactTokenCount(_ value: Int) -> String {
    let double = Double(value)
    switch TaskBarSettings.tokenUnitStyle {
    case .chinese:
        if value >= 100_000_000 {
            return String(format: "%.2f亿", double / 100_000_000)
        }
        if value >= 10_000 {
            return String(format: "%.1f万", double / 10_000)
        }
        if value >= 1_000 {
            return formatInteger(value)
        }
    case .english:
        if value >= 1_000_000_000 {
            return String(format: "%.2fB", double / 1_000_000_000)
        }
        if value >= 1_000_000 {
            return String(format: "%.1fM", double / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", double / 1_000)
        }
    case .exact:
        return formatInteger(value)
    }
    return "\(value)"
}

private func cacheRateText(for breakdown: TokenBreakdown) -> String? {
    guard breakdown.hasDetailedCounters, breakdown.input > 0 else { return nil }
    let percent = Double(breakdown.cachedInput) / Double(breakdown.input) * 100
    return String(format: "%.1f%%", percent)
}

private func sqlStringLiteral(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "''"))'"
}

private func bool(_ value: Any?) -> Bool? {
    if let value = value as? Bool { return value }
    if let value = value as? Int { return value != 0 }
    if let value = value as? String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "yes", "1":
            return true
        case "false", "no", "0":
            return false
        default:
            return nil
        }
    }
    return nil
}

private func turnCount(from value: Any?) -> Int {
    if let array = value as? [Any] { return array.count }
    return Int(double(value) ?? 0)
}

private func tokenBreakdown(from dict: [String: Any]) -> TokenBreakdown {
    let source = tokenUsageDictionary(from: dict)
    let totalFallback = intValue(firstValue(in: dict, keys: ["tokens_used", "tokensUsed", "tokens"]))
    let detailedKeys = [
        "input_tokens", "inputTokens",
        "cached_input_tokens", "cachedInputTokens",
        "output_tokens", "outputTokens",
        "reasoning_output_tokens", "reasoningOutputTokens"
    ]

    return TokenBreakdown(
        input: intValue(firstValue(in: source, keys: ["input_tokens", "inputTokens"])) ?? 0,
        cachedInput: intValue(firstValue(in: source, keys: ["cached_input_tokens", "cachedInputTokens"])) ?? 0,
        output: intValue(firstValue(in: source, keys: ["output_tokens", "outputTokens"])) ?? 0,
        reasoningOutput: intValue(firstValue(in: source, keys: ["reasoning_output_tokens", "reasoningOutputTokens"])) ?? 0,
        total: intValue(firstValue(in: source, keys: ["total_tokens", "totalTokens", "total"])) ?? totalFallback ?? 0,
        hasDetailedCounters: containsAnyKey(source, detailedKeys)
    )
}

private func tokenUsageDictionary(from dict: [String: Any]) -> [String: Any] {
    if let usage = firstDictionary(in: dict, keys: ["total_token_usage", "totalTokenUsage", "usage", "tokenUsage", "token_usage"]) {
        return usage
    }
    if let info = dict["info"] as? [String: Any] {
        if let usage = firstDictionary(in: info, keys: ["total_token_usage", "totalTokenUsage", "usage", "tokenUsage", "token_usage"]) {
            return usage
        }
        return info
    }
    return dict
}

private func firstValue(in dict: [String: Any], keys: [String]) -> Any? {
    for key in keys {
        if let value = dict[key] {
            return value
        }
    }
    return nil
}

private func firstDictionary(in dict: [String: Any], keys: [String]) -> [String: Any]? {
    for key in keys {
        if let value = dict[key] as? [String: Any] {
            return value
        }
    }
    return nil
}

private func containsAnyKey(_ dict: [String: Any], _ keys: [String]) -> Bool {
    keys.contains { dict.keys.contains($0) }
}

private func relative(_ date: Date) -> String {
    let seconds = max(0, Int(Date().timeIntervalSince(date)))
    if seconds < 60 { return "\(seconds)s ago" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m ago" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h ago" }
    return "\(hours / 24)d ago"
}

private func relativeChinese(_ date: Date) -> String {
    let seconds = max(0, Int(Date().timeIntervalSince(date)))
    if seconds < 60 { return "\(seconds)秒前" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)分钟前" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)小时前" }
    return "\(hours / 24)天前"
}

private func durationSince(_ date: Date) -> String {
    let seconds = max(0, Int(Date().timeIntervalSince(date)))
    if seconds < 60 { return "\(seconds)s" }
    let minutes = seconds / 60
    let remainderSeconds = seconds % 60
    if minutes < 60 {
        return "\(minutes)m \(remainderSeconds)s"
    }
    let hours = minutes / 60
    let remainderMinutes = minutes % 60
    if hours < 24 {
        return "\(hours)h \(String(format: "%02d", remainderMinutes))m"
    }
    let days = hours / 24
    let remainderHours = hours % 24
    return "\(days)d \(remainderHours)h"
}

private func durationSinceChinese(_ date: Date) -> String {
    let seconds = max(0, Int(Date().timeIntervalSince(date)))
    if seconds < 60 { return "\(seconds)秒" }
    let minutes = seconds / 60
    let remainderSeconds = seconds % 60
    if minutes < 60 {
        return "\(minutes)分 \(remainderSeconds)秒"
    }
    let hours = minutes / 60
    let remainderMinutes = minutes % 60
    if hours < 24 {
        return "\(hours)小时 \(remainderMinutes)分"
    }
    let days = hours / 24
    let remainderHours = hours % 24
    return "\(days)天 \(remainderHours)小时"
}

private func compactDurationSinceChinese(_ date: Date) -> String {
    let seconds = max(0, Int(Date().timeIntervalSince(date)))
    if seconds < 60 { return "\(seconds)秒" }
    let minutes = seconds / 60
    let remainderSeconds = seconds % 60
    if minutes < 60 { return "\(minutes)分\(String(format: "%02d", remainderSeconds))秒" }
    let hours = minutes / 60
    let remainderMinutes = minutes % 60
    if hours < 24 {
        return "\(hours)时\(String(format: "%02d", remainderMinutes))分"
    }
    let days = hours / 24
    let remainderHours = hours % 24
    return "\(days)天\(remainderHours)时"
}

private func printThreads() {
    let items = ReadStateStore().visibleThreads(from: CodexActivityReader().read())
    if items.isEmpty {
        print("No running or unread Codex or Claude turns")
        return
    }
    for item in items {
        let folder = shortFolderName(item.cwd)
        let timing = (item.status == .running || item.status == .stale)
            ? item.startedAt.map { "elapsed \(durationSince($0))" } ?? relative(item.lastActivity)
            : relative(item.lastActivity)
        let preview = item.preview.map { "\t\($0)" } ?? ""
        print("\(statusLabel(item.status))\t\(timing)\t\(folder)\t\(item.title)\t\(item.id)\t\(item.source)\(preview)")
    }
}

if CommandLine.arguments.contains("--print") {
    printThreads()
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}

private extension ISO8601DateFormatter {
    static let codexPetBar: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let codexPetBarWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
