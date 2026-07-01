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
        var latestUserIsToolResult = false
        var latestAssistantAt: Date?
        var latestAssistantIsRunning = false
        var latestAssistantNeedsInput = false
        var lastActivity: Date?
        var lastQueueOperation: String?
        var lastQueueAt: Date?
        var turns = 0
        var model: String?
        var tokens = TokenBreakdown()

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
                let isToolResult = bool(object["toolUseResult"]) == true
                    || self.messageContentContainsType(message["content"], "tool_result")
                latestUserIsToolResult = isToolResult
                if let contentText {
                    firstUserText = firstUserText ?? contentText
                    latestUserText = contentText
                }
                // Only genuine human prompts count as turns. Tool results are
                // role=user but automated; sidechain/meta messages are injected.
                let isSidechain = (object["isSidechain"] as? Bool) ?? false
                let isMeta = (object["isMeta"] as? Bool) ?? false
                if !isToolResult, !isSidechain, !isMeta,
                   let contentText, !contentText.isEmpty {
                    turns += 1
                }
            } else if role == "assistant" {
                if let timestamp {
                    latestAssistantAt = timestamp
                }
                latestUserIsToolResult = false
                if let value = string(message["model"]), !value.isEmpty {
                    model = value
                }
                if let usage = message["usage"] as? [String: Any] {
                    let input = intValue(usage["input_tokens"]) ?? 0
                    let cacheRead = intValue(usage["cache_read_input_tokens"]) ?? 0
                    let cacheCreate = intValue(usage["cache_creation_input_tokens"]) ?? 0
                    let output = intValue(usage["output_tokens"]) ?? 0
                    let totalInput = input + cacheRead + cacheCreate
                    if totalInput + output > 0 {
                        tokens.add(TokenBreakdown(
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
                latestAssistantIsRunning = stopReason == "tool_use"
                    || self.messageContentContainsType(message["content"], "tool_use")
                latestAssistantNeedsInput = stopReason == "pause_turn"
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
        let assistantWaitingForInput = latestAssistantNeedsInput
            && (latestAssistantAt ?? .distantPast) >= (latestUserAt ?? .distantPast)
        let assistantRunningTool = latestAssistantIsRunning
            && (latestAssistantAt ?? .distantPast) >= (latestUserAt ?? .distantPast)
        let userToolResultStillActive = latestUserIsToolResult
            && (latestUserAt ?? .distantPast) >= (latestAssistantAt ?? .distantPast)
        let isRunning = pendingUserResponse || queuedAfterAssistant || assistantRunningTool || userToolResultStillActive
        let isWaitingForUser = !isRunning && assistantWaitingForInput
        let status: ThreadRunStatus = isRunning ? .running : (isWaitingForUser ? .waiting : .unread)
        let startedAt: Date?
        if isRunning {
            startedAt = latestUserAt ?? latestAssistantAt ?? lastQueueAt ?? activityDate
        } else if isWaitingForUser {
            startedAt = latestAssistantAt ?? activityDate
        } else {
            startedAt = nil
        }
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
            startedAt: startedAt,
            externalReadAt: nil,
            status: status,
            turns: turns,
            compressionCount: nil,
            source: "claude-code",
            isExplicitUnread: false,
            tokensUsed: tokens.displayTotal,
            tokenBreakdown: tokens,
            model: model
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
            let eventDate = self.eventDate(from: line)
            if summary.cwd == nil, line.contains(#""type":"session_meta""#) {
                summary.cwd = self.extractJSONString(line: line, key: "cwd")
            }
            if line.contains(#""type":"turn_context""#) {
                if let cwd = self.extractJSONString(line: line, key: "cwd"),
                   !cwd.isEmpty {
                    summary.cwd = cwd
                }
                summary.isRunning = true
                summary.turns += 1
                summary.lastTaskEventAt = eventDate ?? summary.lastTaskEventAt
                summary.currentTurnStartedAt = eventDate ?? summary.currentTurnStartedAt
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
            if self.isFinalAssistantMessage(line: line) {
                summary.isRunning = false
                summary.lastTaskEventAt = eventDate ?? summary.lastTaskEventAt
                summary.lastCompletionAt = eventDate ?? summary.lastCompletionAt
                summary.currentTurnStartedAt = nil
            }
            guard line.contains(#""type":"event_msg""#) else { return }
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
                let wasAlreadyRunning = summary.isRunning
                summary.isRunning = true
                if !wasAlreadyRunning {
                    summary.turns += 1
                }
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

    private func isFinalAssistantMessage(line: String) -> Bool {
        guard line.contains(#""type":"response_item""#),
              line.contains(#""payload":{"type":"message""#),
              line.contains(#""role":"assistant""#),
              let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["payload"] as? [String: Any],
              string(payload["type"]) == "message",
              string(payload["role"]) == "assistant" else {
            return false
        }
        return string(payload["phase"]) == "final"
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

    func image(status: ThreadRunStatus?, showsRedDot: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        let color: NSColor
        switch status {
        case .running:
            color = NSColor.systemGreen
        case .stale:
            color = NSColor.systemYellow
        case .waiting:
            color = NSColor.systemYellow
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

        if showsRedDot {
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: NSRect(x: 11.5, y: 1.5, width: 6, height: 6)).fill()
        }

        image.unlockFocus()
        image.isTemplate = false
        frame += 1
        return image
    }
}

enum TaskBarTab: Int, CaseIterable {
    case all
    case running
    case waiting
    case done

    var title: String {
        switch self {
        case .all: return "All"
        case .running: return "Running"
        case .waiting: return "Waiting"
        case .done: return "Done"
        }
    }

    func matches(_ status: ThreadRunStatus) -> Bool {
        switch self {
        case .all: return true
        case .running: return status == .running || status == .stale
        case .waiting: return status == .waiting
        case .done: return status == .unread
        }
    }

    var emptyMessage: String {
        switch self {
        case .all: return "No active Codex or Claude tasks"
        case .running: return "Nothing running right now"
        case .waiting: return "Nothing waiting on you"
        case .done: return "No finished tasks to review"
        }
    }
}

/// App-style rounded icon drawn to echo a checklist, matching the Task Bar mark.
final class TaskBarAppIconView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds
        let radius = rect.width * 0.28
        let background = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        if let gradient = NSGradient(
            starting: NSColor(calibratedWhite: 1.0, alpha: 1.0),
            ending: NSColor(calibratedWhite: 0.85, alpha: 1.0)
        ) {
            gradient.draw(in: background, angle: 90)
        } else {
            NSColor.white.setFill()
            background.fill()
        }

        let bulletColors = [
            NSColor(calibratedRed: 0.96, green: 0.52, blue: 0.22, alpha: 1),
            NSColor(calibratedRed: 0.29, green: 0.55, blue: 0.96, alpha: 1),
            NSColor(calibratedRed: 0.96, green: 0.52, blue: 0.22, alpha: 1)
        ]
        let leftX = rect.width * 0.24
        let lineX = rect.width * 0.44
        let lineRight = rect.width * 0.76
        let bulletSize = rect.width * 0.13
        let lineHeight = rect.width * 0.085
        let rowSpacing = rect.height * 0.21
        let firstY = rect.height * 0.31
        for index in 0..<3 {
            let centerY = firstY + CGFloat(index) * rowSpacing
            let bulletRect = NSRect(x: leftX, y: centerY - bulletSize / 2, width: bulletSize, height: bulletSize)
            bulletColors[index].setFill()
            NSBezierPath(roundedRect: bulletRect, xRadius: bulletSize * 0.3, yRadius: bulletSize * 0.3).fill()
            let lineRect = NSRect(x: lineX, y: centerY - lineHeight / 2, width: lineRight - lineX, height: lineHeight)
            NSColor(calibratedWhite: 0.52, alpha: 0.9).setFill()
            NSBezierPath(roundedRect: lineRect, xRadius: lineHeight / 2, yRadius: lineHeight / 2).fill()
        }
    }
}

extension TaskBarTab {
    var symbolName: String {
        switch self {
        case .all: return "list.bullet"
        case .running: return "play.circle.fill"
        case .waiting: return "clock.fill"
        case .done: return "checkmark.circle.fill"
        }
    }

    var tintColor: NSColor {
        switch self {
        case .all: return NSColor(calibratedWhite: 0.85, alpha: 1)
        case .running: return statusAccentColor(.running)
        case .waiting: return statusAccentColor(.waiting)
        case .done: return statusAccentColor(.unread)
        }
    }
}

/// Compact header chip such as "Running 3": muted label + colored count, optional leading dot.
final class CountChipView: NSView {
    private let dotView = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private let showsDot: Bool

    init(title: String, count: Int, color: NSColor, showsDot: Bool) {
        self.showsDot = showsDot
        super.init(frame: .zero)
        wantsLayer = true

        if showsDot {
            dotView.wantsLayer = true
            dotView.layer?.backgroundColor = color.cgColor
            dotView.layer?.cornerRadius = 3
            addSubview(dotView)
        }

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = NSColor(calibratedWhite: 0.72, alpha: 1)
        addSubview(titleLabel)

        countLabel.stringValue = "\(count)"
        countLabel.font = .systemFont(ofSize: 11.5, weight: .bold)
        countLabel.textColor = count > 0 ? color : color.withAlphaComponent(0.45)
        addSubview(countLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func textWidth(_ field: NSTextField) -> CGFloat {
        let font = field.font ?? NSFont.systemFont(ofSize: 12)
        return ceil((field.stringValue as NSString).size(withAttributes: [.font: font]).width)
    }

    var preferredWidth: CGFloat {
        let dotWidth: CGFloat = showsDot ? 6 + 6 : 0
        return 11 + dotWidth + textWidth(titleLabel) + 6 + textWidth(countLabel) + 12
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor(calibratedWhite: 1.0, alpha: 0.05).setFill()
        path.fill()
        path.lineWidth = 1
        NSColor(calibratedWhite: 1.0, alpha: 0.12).setStroke()
        path.stroke()
    }

    override func layout() {
        super.layout()
        let midY = bounds.midY
        var x: CGFloat = 11
        if showsDot {
            dotView.frame = NSRect(x: x, y: midY - 3, width: 6, height: 6)
            x += 6 + 6
        }
        let titleW = textWidth(titleLabel)
        titleLabel.frame = NSRect(x: x, y: midY - 8, width: titleW, height: 16)
        x += titleW + 6
        countLabel.frame = NSRect(x: x, y: midY - 8, width: textWidth(countLabel) + 2, height: 16)
    }
}

final class PanelHeaderView: NSView {
    private let iconView = TaskBarAppIconView()
    private let titleLabel = NSTextField(labelWithString: "Task Bar")
    private var chips: [CountChipView] = []

    init(runningCount: Int, waitingCount: Int, unreadCount: Int) {
        super.init(frame: NSRect(x: 0, y: 0, width: menuPanelWidth, height: 56))
        wantsLayer = true

        addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        chips = [
            CountChipView(title: "Running", count: runningCount, color: statusAccentColor(.running), showsDot: true),
            CountChipView(title: "Waiting", count: waitingCount, color: statusAccentColor(.waiting), showsDot: false),
            CountChipView(title: "Done", count: unreadCount, color: statusAccentColor(.unread), showsDot: false)
        ]
        chips.forEach { addSubview($0) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let iconSize: CGFloat = 26
        iconView.frame = NSRect(x: 18, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)

        let chipHeight: CGFloat = 24
        let spacing: CGFloat = 7
        var rightEdge = bounds.maxX - 18
        for chip in chips.reversed() {
            let width = chip.preferredWidth
            chip.frame = NSRect(x: rightEdge - width, y: (bounds.height - chipHeight) / 2, width: width, height: chipHeight)
            rightEdge -= (width + spacing)
        }

        let titleX = iconView.frame.maxX + 11
        let chipsLeft = chips.first?.frame.minX ?? bounds.maxX
        titleLabel.frame = NSRect(x: titleX, y: (bounds.height - 24) / 2, width: max(0, chipsLeft - 10 - titleX), height: 24)
    }
}

/// Segmented control with icons (All / Running / Waiting / Done) for filtering tasks.
final class TaskBarTabsView: NSView {
    private let tabs: [TaskBarTab]
    private var selectedIndex: Int
    var onSelect: (TaskBarTab) -> Void
    private var iconViews: [NSImageView] = []
    private var labelViews: [NSTextField] = []

    init(tabs: [TaskBarTab], selected: TaskBarTab, onSelect: @escaping (TaskBarTab) -> Void) {
        self.tabs = tabs
        self.selectedIndex = tabs.firstIndex(of: selected) ?? 0
        self.onSelect = onSelect
        super.init(frame: NSRect(x: 0, y: 0, width: menuPanelWidth, height: 42))
        wantsLayer = true

        for (index, tab) in tabs.enumerated() {
            let isSelected = index == selectedIndex
            let icon = NSImageView()
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            icon.image = NSImage(systemSymbolName: tab.symbolName, accessibilityDescription: tab.title)?
                .withSymbolConfiguration(config)
            icon.contentTintColor = tab.tintColor
            icon.imageScaling = .scaleProportionallyDown
            addSubview(icon)
            iconViews.append(icon)

            let label = NSTextField(labelWithString: tab.title)
            label.font = .systemFont(ofSize: 11.5, weight: isSelected ? .semibold : .medium)
            label.textColor = isSelected ? .white : NSColor(calibratedWhite: 0.6, alpha: 1)
            label.lineBreakMode = .byClipping
            addSubview(label)
            labelViews.append(label)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var containerRect: NSRect {
        NSRect(x: 14, y: 6, width: bounds.width - 28, height: 30)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let container = containerRect
        NSColor(calibratedWhite: 1.0, alpha: 0.08).setFill()
        NSBezierPath(roundedRect: container, xRadius: 9, yRadius: 9).fill()

        let segmentWidth = container.width / CGFloat(tabs.count)
        let cell = NSRect(
            x: container.minX + CGFloat(selectedIndex) * segmentWidth,
            y: container.minY,
            width: segmentWidth,
            height: container.height
        ).insetBy(dx: 3, dy: 3)
        let selection = NSBezierPath(roundedRect: cell, xRadius: 7, yRadius: 7)
        NSColor(calibratedWhite: 1.0, alpha: 0.16).setFill()
        selection.fill()
        selection.lineWidth = 1
        NSColor(calibratedWhite: 1.0, alpha: 0.08).setStroke()
        selection.stroke()
    }

    private func labelWidth(_ field: NSTextField) -> CGFloat {
        let font = field.font ?? NSFont.systemFont(ofSize: 12.5)
        return ceil((field.stringValue as NSString).size(withAttributes: [.font: font]).width)
    }

    override func layout() {
        super.layout()
        let container = containerRect
        let segmentWidth = container.width / CGFloat(tabs.count)
        let iconWidth: CGFloat = 14
        let gap: CGFloat = 6
        for index in tabs.indices {
            let cell = NSRect(
                x: container.minX + CGFloat(index) * segmentWidth,
                y: container.minY,
                width: segmentWidth,
                height: container.height
            )
            let label = labelViews[index]
            let icon = iconViews[index]
            let width = labelWidth(label)
            let groupWidth = iconWidth + gap + width
            let startX = cell.midX - groupWidth / 2
            icon.frame = NSRect(x: startX, y: cell.midY - 7, width: iconWidth, height: 14)
            label.frame = NSRect(x: startX + iconWidth + gap, y: cell.midY - 8, width: width + 1, height: 16)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let container = containerRect
        guard container.insetBy(dx: 0, dy: -6).contains(point) else { return }
        let segmentWidth = container.width / CGFloat(tabs.count)
        let index = min(tabs.count - 1, max(0, Int((point.x - container.minX) / segmentWidth)))
        guard index != selectedIndex else { return }
        selectedIndex = index
        needsDisplay = true
        onSelect(tabs[index])
    }
}

final class EmptyStateView: NSView {
    private let label = NSTextField(labelWithString: "")

    init(message: String = "") {
        super.init(frame: NSRect(x: 0, y: 0, width: menuPanelWidth, height: taskBarEmptyStateHeight))
        label.stringValue = message
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = NSColor(calibratedWhite: 0.55, alpha: 1)
        label.alignment = .center
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 2
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: 20, y: (bounds.height - 34) / 2, width: bounds.width - 40, height: 34)
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

    static func clampedPopoverSize(_ size: NSSize) -> NSSize {
        let maxSize = taskBarPopoverMaxResizableSize()
        return NSSize(
            width: min(max(size.width, taskBarPopoverMinWidth), maxSize.width),
            height: min(max(size.height, taskBarPopoverMinHeight), maxSize.height)
        )
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
    private let onDismiss: (String) -> Void
    private let showPlatformLabel: Bool
    private let showStatusDot: Bool
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let clockIconView = NSImageView()
    private let durationLabel = NSTextField(labelWithString: "")
    private let metaDotView = NSView()
    private let metaStatusLabel = NSTextField(labelWithString: "")
    private var trackingAreaRef: NSTrackingArea?
    private var elapsedTimer: Timer?
    private var mouseDownPoint = NSPoint.zero
    private var dragStartOffset: CGFloat = 0
    private var swipeOffset: CGFloat = 0
    private var isSwipeTracking = false
    private var scrollSwipeSettleTimer: Timer?
    private var didDrag = false
    private var isHovering = false {
        didSet { needsDisplay = true }
    }

    init(
        item: CodexThreadItem,
        showPlatformLabel: Bool,
        showStatusDot: Bool,
        onOpen: @escaping (String) -> Void,
        onDismiss: @escaping (String) -> Void
    ) {
        self.item = item
        self.showPlatformLabel = showPlatformLabel
        self.showStatusDot = showStatusDot
        self.onOpen = onOpen
        self.onDismiss = onDismiss
        super.init(frame: NSRect(x: 0, y: 0, width: menuPanelWidth, height: taskBarRowHeight))
        wantsLayer = true
        let tooltip = tooltipText(for: item)
        setAccessibilityHelp(tooltip)

        let accent = statusAccentColor(item.status)

        titleLabel.stringValue = item.title
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        addSubview(titleLabel)

        detailLabel.stringValue = item.preview ?? detailText(for: item)
        detailLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
        detailLabel.textColor = NSColor(calibratedWhite: 0.62, alpha: 1)
        detailLabel.maximumNumberOfLines = 2
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.cell?.wraps = true
        detailLabel.cell?.isScrollable = false
        addSubview(detailLabel)

        let clockConfig = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        clockIconView.image = NSImage(systemSymbolName: "clock", accessibilityDescription: nil)?
            .withSymbolConfiguration(clockConfig)
        clockIconView.contentTintColor = NSColor(calibratedWhite: 0.5, alpha: 1)
        clockIconView.imageScaling = .scaleProportionallyDown
        addSubview(clockIconView)

        durationLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        durationLabel.textColor = NSColor(calibratedWhite: 0.5, alpha: 1)
        durationLabel.lineBreakMode = .byClipping
        addSubview(durationLabel)

        metaDotView.wantsLayer = true
        metaDotView.layer?.backgroundColor = accent.cgColor
        metaDotView.layer?.cornerRadius = 2.5
        addSubview(metaDotView)

        metaStatusLabel.stringValue = rowStatusLabel(item.status)
        metaStatusLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        metaStatusLabel.textColor = accent
        metaStatusLabel.lineBreakMode = .byTruncatingTail
        addSubview(metaStatusLabel)

        updateElapsedLabel()
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

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        dragStartOffset = swipeOffset
        isSwipeTracking = false
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        let point = event.locationInWindow
        let deltaX = point.x - mouseDownPoint.x
        let deltaY = point.y - mouseDownPoint.y
        guard isReadDismissible(item.status) else {
            didDrag = hypot(deltaX, deltaY) > 3
            return
        }

        if !isSwipeTracking {
            guard abs(deltaX) > 6 || abs(deltaY) > 6 else { return }
            guard abs(deltaX) > abs(deltaY) * 1.2 else { return }
            isSwipeTracking = true
            ThreadHoverPanel.shared.hide(owner: self)
        }

        didDrag = true
        setSwipeOffset(min(0, max(-ThreadRowView.dismissRevealWidth, dragStartOffset + deltaX)), animated: false)
    }

    override func mouseUp(with event: NSEvent) {
        ThreadHoverPanel.shared.hide(owner: self)
        if isSwipeTracking {
            if swipeOffset <= -ThreadRowView.dismissThreshold {
                onDismiss(item.id)
            } else {
                setSwipeOffset(0, animated: true)
            }
            isSwipeTracking = false
            didDrag = false
            return
        }
        guard !didDrag else {
            didDrag = false
            return
        }
        onOpen(item.id)
    }

    override func scrollWheel(with event: NSEvent) {
        guard isReadDismissible(item.status), event.hasPreciseScrollingDeltas else {
            super.scrollWheel(with: event)
            return
        }

        let horizontal = event.scrollingDeltaX
        let vertical = event.scrollingDeltaY
        guard abs(horizontal) > 0.4, abs(horizontal) > abs(vertical) * 1.35 else {
            super.scrollWheel(with: event)
            return
        }

        ThreadHoverPanel.shared.hide(owner: self)
        isSwipeTracking = true
        scrollSwipeSettleTimer?.invalidate()

        let revealDelta = event.isDirectionInvertedFromDevice ? horizontal : -horizontal
        let nextOffset = min(0, max(-ThreadRowView.dismissRevealWidth, swipeOffset - revealDelta))
        setSwipeOffset(nextOffset, animated: false)

        switch event.phase {
        case .ended, .cancelled:
            settleScrollSwipe()
        default:
            let timer = Timer(timeInterval: 0.18, repeats: false) { [weak self] _ in
                self?.settleScrollSwipe()
            }
            scrollSwipeSettleTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
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
        scrollSwipeSettleTimer?.invalidate()
        ThreadHoverPanel.shared.hide(owner: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Divider between rows.
        NSColor(calibratedWhite: 1.0, alpha: 0.06).setFill()
        NSRect(x: 20, y: 0, width: bounds.width - 40, height: 1).fill()

        // Colored status accent bar at the leading edge.
        if !isSwipeTracking || swipeOffset > -1 {
            let barRect = NSRect(x: 8 + swipeOffset, y: 14, width: 3.5, height: bounds.height - 28)
            statusAccentColor(item.status).setFill()
            NSBezierPath(roundedRect: barRect, xRadius: 1.75, yRadius: 1.75).fill()
        }

        if swipeOffset < -1, isReadDismissible(item.status) {
            let revealWidth = min(ThreadRowView.dismissRevealWidth, -swipeOffset + 16)
            let revealRect = NSRect(
                x: bounds.maxX - revealWidth - 8,
                y: 6,
                width: revealWidth,
                height: bounds.height - 12
            )
            NSColor.systemRed.withAlphaComponent(0.82).setFill()
            NSBezierPath(roundedRect: revealRect, xRadius: 10, yRadius: 10).fill()
            drawDismissLabel(in: revealRect)
        }
        guard isHovering, !isSwipeTracking else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 4), xRadius: 12, yRadius: 12).fill()
    }

    override func layout() {
        super.layout()
        let offset = swipeOffset
        let contentX: CGFloat = 26
        let contentWidth = max(120, bounds.width - 18 - contentX)

        titleLabel.frame = NSRect(x: contentX + offset, y: bounds.height - 32, width: contentWidth, height: 20)
        detailLabel.frame = NSRect(x: contentX + offset, y: 28, width: contentWidth, height: 32)

        clockIconView.frame = NSRect(x: contentX + offset, y: 11, width: 11, height: 11)
        durationLabel.frame = NSRect(x: contentX + 16 + offset, y: 9, width: 58, height: 15)
        metaDotView.frame = NSRect(x: contentX + 76 + offset, y: 14, width: 5, height: 5)
        metaStatusLabel.frame = NSRect(x: contentX + 87 + offset, y: 9, width: max(0, contentWidth - 87), height: 15)
    }

    private func setSwipeOffset(_ offset: CGFloat, animated: Bool) {
        swipeOffset = offset
        let updates = {
            self.needsLayout = true
            self.layoutSubtreeIfNeeded()
            self.needsDisplay = true
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                updates()
            }
        } else {
            updates()
        }
    }

    private func drawDismissLabel(in rect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.94),
            .paragraphStyle: paragraph
        ]
        ("移除" as NSString).draw(in: rect.insetBy(dx: 10, dy: 22), withAttributes: attributes)
    }

    private func settleScrollSwipe() {
        scrollSwipeSettleTimer?.invalidate()
        scrollSwipeSettleTimer = nil
        guard isSwipeTracking else { return }
        isSwipeTracking = false
        if swipeOffset <= -ThreadRowView.dismissThreshold {
            onDismiss(item.id)
        } else {
            setSwipeOffset(0, animated: true)
        }
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
        durationLabel.stringValue = text
        durationLabel.isHidden = text.isEmpty
        clockIconView.isHidden = text.isEmpty
    }

    private static let dismissRevealWidth: CGFloat = 86
    private static let dismissThreshold: CGFloat = 58
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
    private let settingsButton: TaskBarActionButton
    private let quitButton: TaskBarActionButton

    init(
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        settingsButton = CommandButtonBarView.makeButton(
            title: "Settings",
            symbolName: "gearshape",
            tint: NSColor(calibratedWhite: 0.78, alpha: 1),
            action: onOpenSettings
        )
        quitButton = CommandButtonBarView.makeButton(
            title: "Quit",
            symbolName: "power",
            tint: NSColor(calibratedRed: 0.94, green: 0.36, blue: 0.34, alpha: 1),
            action: onQuit
        )
        super.init(frame: NSRect(x: 0, y: 0, width: menuPanelWidth, height: 46))
        wantsLayer = true
        layer?.backgroundColor = menuPanelBackground.cgColor
        addSubview(settingsButton)
        addSubview(quitButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func makeButton(
        title: String,
        symbolName: String,
        tint: NSColor,
        action: @escaping () -> Void
    ) -> TaskBarActionButton {
        let button = TaskBarActionButton(title: title, action: action)
        button.isBordered = false
        button.wantsLayer = true
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = tint
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.toolTip = title
        button.attributedTitle = NSAttributedString(string: " " + title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: tint
        ])
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        image?.isTemplate = true
        button.image = image
        return button
    }

    override func layout() {
        super.layout()
        settingsButton.sizeToFit()
        var settingsFrame = settingsButton.frame
        settingsFrame.origin = NSPoint(x: 18, y: (bounds.height - settingsFrame.height) / 2)
        settingsButton.frame = settingsFrame

        quitButton.sizeToFit()
        var quitFrame = quitButton.frame
        quitFrame.origin = NSPoint(x: bounds.maxX - 18 - quitFrame.width, y: (bounds.height - quitFrame.height) / 2)
        quitButton.frame = quitFrame
    }
}

/// Centered "N of M tasks" summary strip below the list.
private final class TaskCountView: NSView {
    private let label = NSTextField(labelWithString: "")

    init(shown: Int, total: Int) {
        super.init(frame: NSRect(x: 0, y: 0, width: menuPanelWidth, height: 26))
        wantsLayer = true
        layer?.backgroundColor = menuPanelBackground.cgColor
        label.font = .systemFont(ofSize: 10.5, weight: .medium)
        label.textColor = NSColor(calibratedWhite: 0.5, alpha: 1)
        label.alignment = .center
        addSubview(label)
        update(shown: shown, total: total)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(shown: Int, total: Int) {
        let noun = total == 1 ? "task" : "tasks"
        label.stringValue = "\(shown) of \(total) \(noun)"
    }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: 16, y: (bounds.height - 16) / 2, width: bounds.width - 32, height: 16)
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

private final class PopoverResizeHandleView: NSView {
    var onResize: ((NSSize, Bool) -> Void)?

    private var startMouse = NSPoint.zero
    private var startSize = NSSize.zero
    private var lastSize = NSSize.zero
    private var didDrag = false

    override var isFlipped: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        ThreadHoverPanel.shared.hideAll()
        startMouse = NSEvent.mouseLocation
        startSize = superview?.bounds.size ?? bounds.size
        lastSize = startSize
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        let currentMouse = NSEvent.mouseLocation
        let nextSize = NSSize(
            width: startSize.width + currentMouse.x - startMouse.x,
            height: startSize.height + startMouse.y - currentMouse.y
        )
        lastSize = TaskBarSettings.clampedPopoverSize(nextSize)
        didDrag = true
        onResize?(lastSize, false)
    }

    override func mouseUp(with event: NSEvent) {
        guard didDrag else { return }
        onResize?(lastSize, true)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.white.withAlphaComponent(0.34).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.4
        for offset in [CGFloat(0), CGFloat(5), CGFloat(10)] {
            path.move(to: NSPoint(x: bounds.maxX - 4 - offset, y: bounds.maxY - 2))
            path.line(to: NSPoint(x: bounds.maxX - 2, y: bounds.maxY - 4 - offset))
        }
        path.stroke()
    }
}

private final class TaskBarPopoverContentView: NSView {
    private let headerView: PanelHeaderView
    private let tabsView: TaskBarTabsView
    private let topSeparator = MenuSeparatorView()
    private var rowsView: TaskBarRowsView
    private let rowsScrollView: NSScrollView
    private let taskCountView: TaskCountView
    private let taskCountHeight: CGFloat
    private let bottomSeparator = MenuSeparatorView()
    private let commandBar: CommandButtonBarView
    private let resizeHandle = PopoverResizeHandleView()
    private var rowsContentHeight: CGFloat
    private let onResize: (NSSize, Bool) -> Void

    // Retained so the tab filter can be re-applied in place, without a full rebuild.
    private let allThreads: [CodexThreadItem]
    private let totalCount: Int
    private let showPlatformLabels: Bool
    private let showStatusDots: Bool
    private let onOpenThread: (String) -> Void
    private let onDismissThread: (String) -> Void
    private let externalSelectTab: (TaskBarTab) -> Void
    private var selectedTab: TaskBarTab

    init(
        threads: [CodexThreadItem],
        runningCount: Int,
        waitingCount: Int,
        unreadCount: Int,
        selectedTab: TaskBarTab,
        showPlatformLabels: Bool,
        showStatusDots: Bool,
        onOpenThread: @escaping (String) -> Void,
        onDismissThread: @escaping (String) -> Void,
        onSelectTab: @escaping (TaskBarTab) -> Void,
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void,
        initialSize: NSSize?,
        onResize: @escaping (NSSize, Bool) -> Void
    ) {
        self.onResize = onResize
        self.allThreads = threads
        self.showPlatformLabels = showPlatformLabels
        self.showStatusDots = showStatusDots
        self.onOpenThread = onOpenThread
        self.onDismissThread = onDismissThread
        self.externalSelectTab = onSelectTab
        self.selectedTab = selectedTab

        headerView = PanelHeaderView(
            runningCount: runningCount,
            waitingCount: waitingCount,
            unreadCount: unreadCount
        )
        tabsView = TaskBarTabsView(tabs: TaskBarTab.allCases, selected: selectedTab, onSelect: { _ in })

        let total = runningCount + waitingCount + unreadCount
        totalCount = total
        let filtered = threads.filter { selectedTab.matches($0.status) }
        taskCountView = TaskCountView(shown: filtered.count, total: total)
        taskCountView.isHidden = total == 0
        taskCountHeight = total == 0 ? 0 : taskCountView.frame.height

        let rowViews = TaskBarPopoverContentView.makeRowViews(
            filtered: filtered,
            selectedTab: selectedTab,
            showPlatformLabels: showPlatformLabels,
            showStatusDots: showStatusDots,
            onOpenThread: onOpenThread,
            onDismissThread: onDismissThread
        )
        rowsView = TaskBarRowsView(rowViews: rowViews)
        rowsContentHeight = rowsView.frame.height
        commandBar = CommandButtonBarView(
            onOpenSettings: onOpenSettings,
            onQuit: onQuit
        )

        let fixedHeight = headerView.frame.height
            + tabsView.frame.height
            + topSeparator.frame.height
            + taskCountHeight
            + bottomSeparator.frame.height
            + commandBar.frame.height
        let maxRowsHeight = max(taskBarEmptyStateHeight, taskBarPopoverMaxHeight() - fixedHeight)
        let naturalRowsHeight = min(rowsContentHeight, maxRowsHeight)
        let naturalHeight = fixedHeight + naturalRowsHeight
        let naturalSize = NSSize(width: menuPanelWidth, height: naturalHeight)
        let initialSize = TaskBarSettings.clampedPopoverSize(initialSize ?? naturalSize)

        let scrollView = NSScrollView(frame: .zero)
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = rowsView
        rowsScrollView = scrollView

        super.init(frame: NSRect(origin: .zero, size: initialSize))
        wantsLayer = true
        layer?.backgroundColor = menuPanelBackground.cgColor
        appearance = NSAppearance(named: .darkAqua)

        addSubview(headerView)
        addSubview(tabsView)
        addSubview(topSeparator)
        addSubview(rowsScrollView)
        addSubview(taskCountView)
        addSubview(bottomSeparator)
        addSubview(commandBar)
        addSubview(resizeHandle)
        resizeHandle.onResize = { [weak self] size, persist in
            self?.applyResize(size, persist: persist)
        }
        tabsView.onSelect = { [weak self] tab in
            self?.selectTab(tab)
        }
    }

    /// Re-filter and swap the list rows in place, keeping the surrounding chrome
    /// (header, tabs, footer) and the popover size stable so switching tabs never flashes.
    private func selectTab(_ tab: TaskBarTab) {
        guard tab != selectedTab else { return }
        selectedTab = tab
        externalSelectTab(tab)

        let filtered = allThreads.filter { tab.matches($0.status) }
        let rowViews = TaskBarPopoverContentView.makeRowViews(
            filtered: filtered,
            selectedTab: tab,
            showPlatformLabels: showPlatformLabels,
            showStatusDots: showStatusDots,
            onOpenThread: onOpenThread,
            onDismissThread: onDismissThread
        )
        let newRowsView = TaskBarRowsView(rowViews: rowViews)
        rowsView = newRowsView
        rowsContentHeight = newRowsView.frame.height
        rowsScrollView.documentView = newRowsView
        taskCountView.update(shown: filtered.count, total: totalCount)
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    private static func makeRowViews(
        filtered: [CodexThreadItem],
        selectedTab: TaskBarTab,
        showPlatformLabels: Bool,
        showStatusDots: Bool,
        onOpenThread: @escaping (String) -> Void,
        onDismissThread: @escaping (String) -> Void
    ) -> [NSView] {
        if filtered.isEmpty {
            return [EmptyStateView(message: selectedTab.emptyMessage)]
        }
        return filtered.map { thread in
            ThreadRowView(
                item: thread,
                showPlatformLabel: showPlatformLabels,
                showStatusDot: showStatusDots,
                onOpen: onOpenThread,
                onDismiss: onDismissThread
            )
        }
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

        tabsView.frame = NSRect(x: 0, y: y, width: bounds.width, height: tabsView.frame.height)
        y += tabsView.frame.height

        topSeparator.frame = NSRect(x: 0, y: y, width: bounds.width, height: topSeparator.frame.height)
        y += topSeparator.frame.height

        let fixedHeight = headerView.frame.height
            + tabsView.frame.height
            + topSeparator.frame.height
            + taskCountHeight
            + bottomSeparator.frame.height
            + commandBar.frame.height
        let rowsViewportHeight = max(taskBarEmptyStateHeight, bounds.height - fixedHeight)
        let rowsFrame = NSRect(x: 0, y: y, width: bounds.width, height: rowsViewportHeight)
        rowsScrollView.frame = rowsFrame
        rowsScrollView.hasVerticalScroller = rowsContentHeight > rowsViewportHeight + 0.5
        rowsView.frame = NSRect(
            x: 0,
            y: 0,
            width: rowsScrollView.contentSize.width,
            height: max(rowsContentHeight, rowsViewportHeight)
        )
        y += rowsViewportHeight

        taskCountView.frame = NSRect(x: 0, y: y, width: bounds.width, height: taskCountHeight)
        y += taskCountHeight

        bottomSeparator.frame = NSRect(x: 0, y: y, width: bounds.width, height: bottomSeparator.frame.height)
        y += bottomSeparator.frame.height

        commandBar.frame = NSRect(x: 0, y: y, width: bounds.width, height: commandBar.frame.height)
        resizeHandle.frame = NSRect(x: bounds.maxX - 18, y: bounds.maxY - 18, width: 18, height: 18)
        resizeHandle.needsDisplay = true
    }

    private func applyResize(_ size: NSSize, persist: Bool) {
        let clamped = TaskBarSettings.clampedPopoverSize(size)
        setFrameSize(clamped)
        needsLayout = true
        onResize(clamped, persist)
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
    private var transientPopoverSize: NSSize?
    private var selectedTab: TaskBarTab = .all
    private var lastThreadsSignature = ""

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
                let signature = self.threadsSignature(visible)
                let changed = signature != self.lastThreadsSignature
                self.threads = visible
                self.lastThreadsSignature = signature
                self.updateStatusIcon()
                // Only rebuild when the visible set actually changed; per-row timers keep
                // elapsed times ticking, so a static list never needs to flash.
                if changed, self.popover.isShown {
                    self.rebuildPopover()
                }
            }
        }
    }

    private func threadsSignature(_ items: [CodexThreadItem]) -> String {
        items.map { "\($0.id)|\(statusRank($0.status))|\($0.title)|\($0.preview ?? "")" }
            .joined(separator: ";")
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.toolTip = "Task Bar"
        button.action = #selector(togglePopover)
        button.target = self
    }

    private func updateStatusIcon() {
        let runningCount = threads.filter { $0.status == .running || $0.status == .stale }.count
        let waitingCount = threads.filter { $0.status == .waiting }.count
        let unreadCount = threads.filter { $0.status == .unread }.count
        let actionNeededCount = waitingCount + unreadCount
        let totalCount = runningCount + actionNeededCount
        let statusIconStatus: ThreadRunStatus = waitingCount > 0 ? .waiting : (unreadCount > 0 ? .unread : .running)
        statusItem.button?.image = icon.image(status: statusIconStatus, showsRedDot: actionNeededCount > 0)
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
            if transientPopoverSize != nil {
                transientPopoverSize = nil
                rebuildPopover()
            } else {
                popover.performClose(nil)
            }
            return
        }
        transientPopoverSize = nil
        rebuildPopover()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        refresh()
    }

    private func rebuildPopover() {
        let active = threads.filter { $0.status == .running || $0.status == .stale }
        let waitingCount = threads.filter { $0.status == .waiting }.count
        let unreadCount = threads.filter { $0.status == .unread }.count
        let controller = NSViewController()
        let content = TaskBarPopoverContentView(
            threads: threads,
            runningCount: active.count,
            waitingCount: waitingCount,
            unreadCount: unreadCount,
            selectedTab: selectedTab,
            showPlatformLabels: TaskBarSettings.showPlatformLabels,
            showStatusDots: TaskBarSettings.showStatusDots,
            onOpenThread: { [weak self] id in
                self?.openThread(id: id)
            },
            onDismissThread: { [weak self] id in
                self?.dismissThread(id: id)
            },
            onSelectTab: { [weak self] tab in
                self?.selectedTab = tab
            },
            onOpenSettings: { [weak self] in
                self?.openSettingsWindow()
            },
            onQuit: { [weak self] in
                self?.popover.performClose(nil)
                ThreadHoverPanel.shared.hideAll()
                self?.quit()
            },
            initialSize: transientPopoverSize,
            onResize: { [weak self, weak controller] size, _ in
                controller?.preferredContentSize = size
                self?.popover.contentSize = size
                self?.transientPopoverSize = size
            }
        )
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

    private func dismissThread(id: String) {
        let selectedItem = threads.first(where: { $0.id == id })
        if let item = selectedItem, isReadDismissible(item.status) {
            readState.markRead(item)
        } else {
            readState.markRead(threadID: id)
        }
        threads.removeAll { $0.id == id && isReadDismissible($0.status) }
        lastThreadsSignature = threadsSignature(threads)
        updateStatusIcon()
        if popover.isShown {
            rebuildPopover()
        }
        ThreadHoverPanel.shared.hideAll()
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

/// Brighter, more saturated status colors used for icons, accents, and chips.
private func statusAccentColor(_ status: ThreadRunStatus) -> NSColor {
    switch status {
    case .running:
        return NSColor(calibratedRed: 0.30, green: 0.80, blue: 0.45, alpha: 1)
    case .stale:
        return NSColor(calibratedRed: 0.95, green: 0.70, blue: 0.30, alpha: 1)
    case .waiting:
        return NSColor(calibratedRed: 0.98, green: 0.68, blue: 0.20, alpha: 1)
    case .unread:
        return NSColor(calibratedRed: 0.36, green: 0.62, blue: 0.98, alpha: 1)
    }
}

private func rowStatusLabel(_ status: ThreadRunStatus) -> String {
    switch status {
    case .running, .stale:
        return "Running"
    case .waiting:
        return "Waiting"
    case .unread:
        return "Done"
    }
}

/// Clock-style elapsed time: "MM:SS", or "HH:MM:SS" once past an hour.
private func clockDuration(_ date: Date) -> String {
    let total = max(0, Int(Date().timeIntervalSince(date)))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    if hours > 0 {
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%02d:%02d", minutes, seconds)
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

private extension Array where Element == CodexThreadItem {
    func limitedForTaskBar(limit: Int) -> [CodexThreadItem] {
        let limit = Swift.max(1, limit)
        let active = filter { $0.status == .running || $0.status == .stale || $0.status == .waiting }
        let remaining = filter { $0.status == .unread }.prefix(Swift.max(0, limit - active.count))
        return Array(active + remaining)
    }
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
        return clockDuration(item.startedAt ?? item.lastActivity)
    case .waiting:
        return clockDuration(item.lastActivity)
    case .unread:
        return clockDuration(item.lastActivity)
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

private let menuPanelWidth: CGFloat = 420
private let taskBarPopoverMinWidth: CGFloat = 340
private let taskBarPopoverMinHeight: CGFloat = 200
private let menuPanelBackground = NSColor(calibratedWhite: 0.105, alpha: 0.97)
private let taskBarRowHeight: CGFloat = 92
private let taskBarEmptyStateHeight: CGFloat = 120

private func taskBarPopoverMaxHeight() -> CGFloat {
    let mouse = NSEvent.mouseLocation
    let screenHeight = NSScreen.screens.first { $0.frame.contains(mouse) }?.visibleFrame.height
        ?? NSScreen.main?.visibleFrame.height
        ?? 900
    return min(620, max(360, screenHeight - 110))
}

private func taskBarPopoverMaxResizableSize() -> NSSize {
    let mouse = NSEvent.mouseLocation
    let visibleFrame = NSScreen.screens.first { $0.frame.contains(mouse) }?.visibleFrame
        ?? NSScreen.main?.visibleFrame
        ?? NSRect(x: 0, y: 0, width: 900, height: 900)
    return NSSize(
        width: max(taskBarPopoverMinWidth, min(760, visibleFrame.width - 48)),
        height: max(taskBarPopoverMinHeight, visibleFrame.height - 110)
    )
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

private func mockTaskBarThreads() -> [CodexThreadItem] {
    func item(id: String, title: String, preview: String, status: ThreadRunStatus, ago: TimeInterval, source: String) -> CodexThreadItem {
        CodexThreadItem(
            id: id,
            title: title,
            preview: preview,
            cwd: "/Users/demo/Projects/task-bar",
            lastActivity: Date().addingTimeInterval(-ago),
            startedAt: Date().addingTimeInterval(-ago),
            externalReadAt: nil,
            status: status,
            turns: 12,
            compressionCount: nil,
            source: source,
            isExplicitUnread: status == .unread,
            tokensUsed: 128_000,
            tokenBreakdown: TokenBreakdown(),
            model: "gpt-5-codex"
        )
    }
    return [
        item(id: "codex:1", title: "Automation: 更新飞书 @ 我任务文档", preview: "脚本正在同步飞书，我等最终状态文件返回。", status: .running, ago: 47, source: "codex"),
        item(id: "claude:2", title: "这个看起来不太对，帮忙看看呀 @ 杨工", preview: "已经跨过 18:54 的大批次，累计 23034 条，时间跳到现在。", status: .running, ago: 7333, source: "claude-code"),
        item(id: "codex:3", title: "帮我安装最新的 main 的 codex bar", preview: "我会同时压三处：header 高度/字号、列表字号、底部按钮宽度。顶部间距也从上一版收紧。", status: .running, ago: 9201, source: "codex")
    ]
}

private func renderTaskBar(to path: String) {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let mock = mockTaskBarThreads()
    let running = mock.filter { $0.status == .running || $0.status == .stale }.count
    let waiting = mock.filter { $0.status == .waiting }.count
    let unread = mock.filter { $0.status == .unread }.count

    let tabArg = CommandLine.arguments.first { $0.hasPrefix("--tab=") }.map { String($0.dropFirst(6)) }
    let selectedTab: TaskBarTab
    switch tabArg {
    case "running": selectedTab = .running
    case "waiting": selectedTab = .waiting
    case "done": selectedTab = .done
    default: selectedTab = .all
    }
    let content = TaskBarPopoverContentView(
        threads: mock,
        runningCount: running,
        waitingCount: waiting,
        unreadCount: unread,
        selectedTab: selectedTab,
        showPlatformLabels: true,
        showStatusDots: true,
        onOpenThread: { _ in },
        onDismissThread: { _ in },
        onSelectTab: { _ in },
        onOpenSettings: {},
        onQuit: {},
        initialSize: nil,
        onResize: { _, _ in }
    )

    let size = content.frame.size
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentView = content
    content.frame = NSRect(origin: .zero, size: size)
    content.layoutSubtreeIfNeeded()

    guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
        print("render failed: no bitmap rep")
        return
    }
    content.cacheDisplay(in: content.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        print("render failed: no png data")
        return
    }
    do {
        try data.write(to: URL(fileURLWithPath: path))
        print("wrote \(path) (\(Int(size.width))x\(Int(size.height)))")
    } catch {
        print("render failed: \(error)")
    }
}

if CommandLine.arguments.contains("--print") {
    printThreads()
} else if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--render-taskbar=") }) {
    renderTaskBar(to: String(arg.dropFirst("--render-taskbar=".count)))
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
