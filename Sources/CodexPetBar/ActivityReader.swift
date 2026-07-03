import Cocoa
import Foundation

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
                let toolResultIDs = self.messageContentToolResultIDs(message["content"])
                let isInteractiveToolResult = !toolResultIDs.isEmpty
                    && !latestAssistantInteractiveToolIDs.isDisjoint(with: toolResultIDs)
                latestUserIsToolResult = isToolResult
                latestUserIsInteractiveToolResult = isInteractiveToolResult
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
                latestUserIsInteractiveToolResult = false
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
                let interactiveToolIDs = self.messageContentToolUses(message["content"])
                    .filter { self.isInteractiveUserInputTool($0.name) }
                    .compactMap(\.id)
                latestAssistantInteractiveToolIDs = Set(interactiveToolIDs)
                let assistantRequestedUserInput = !latestAssistantInteractiveToolIDs.isEmpty
                latestAssistantIsRunning = !assistantRequestedUserInput
                    && (stopReason == "tool_use"
                        || self.messageContentContainsType(message["content"], "tool_use"))
                latestAssistantNeedsInput = stopReason == "pause_turn" || assistantRequestedUserInput
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

        let pendingUserResponse = !latestUserIsInteractiveToolResult
            && (latestUserAt ?? .distantPast) > (latestAssistantAt ?? .distantPast)
        let queuedAfterAssistant = lastQueueOperation == "enqueue"
            && (lastQueueAt ?? .distantPast) > (latestAssistantAt ?? .distantPast)
        let assistantWaitingForInput = latestAssistantNeedsInput
            && (latestAssistantAt ?? .distantPast) >= (latestUserAt ?? .distantPast)
        let interactiveToolResultWaiting = latestUserIsInteractiveToolResult
            && (latestUserAt ?? .distantPast) >= (latestAssistantAt ?? .distantPast)
        let assistantRunningTool = latestAssistantIsRunning
            && (latestAssistantAt ?? .distantPast) >= (latestUserAt ?? .distantPast)
        let userToolResultStillActive = latestUserIsToolResult
            && !latestUserIsInteractiveToolResult
            && (latestUserAt ?? .distantPast) >= (latestAssistantAt ?? .distantPast)
        let isRunning = pendingUserResponse || queuedAfterAssistant || assistantRunningTool || userToolResultStillActive
        let isWaitingForUser = !isRunning && (assistantWaitingForInput || interactiveToolResultWaiting)
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
                    let timestamp = readThroughTime(for: item)
                    if (current.openedAt[item.id] ?? 0) < timestamp {
                        current.openedAt[item.id] = timestamp
                        didChange = true
                    }
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
