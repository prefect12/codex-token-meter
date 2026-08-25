import Foundation
import SQLite3

/// Read-only recent-session reader for the local OpenCode / OpenChamber store.
///
/// OpenCode persists one row for every session and writes message completion state
/// into the JSON payload. The database contains no durable unread marker, so a
/// completed assistant message is presented as Done and the existing Task Bar
/// read-state store controls whether it remains visible. An incomplete assistant
/// message or a newer user message is the only evidence used to label a session
/// Running.
final class OpenCodeActivityReader {
    private let explicitDatabaseURL: URL?
    private let activeTimeout: TimeInterval = 10 * 60
    /// Unlike Codex transcripts, OpenCode records assistant completion directly.
    /// A session still incomplete after this window is no longer actionable in a
    /// task bar; keep it briefly for diagnosis, then let it leave the list.
    private let staleVisibilityTimeout: TimeInterval = 30 * 60

    init(databaseURL: URL? = nil) {
        explicitDatabaseURL = databaseURL
    }

    func read(limit: Int, cutoff: Date) -> [CodexThreadItem] {
        let databaseURL = explicitDatabaseURL
            ?? URL(fileURLWithPath: TaskBarSettings.openCodeDirectory, isDirectory: true)
                .appendingPathComponent("opencode.db")
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return [] }

        var database: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let database else {
            sqlite3_close(database)
            return []
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 250)

        let sql = """
        SELECT s.id,
               s.title,
               s.directory,
               s.parent_id,
               s.time_created,
               s.time_updated,
               m.time_created,
               COALESCE(json_extract(s.model, '$.id'), s.model),
               s.tokens_input,
               s.tokens_output,
               s.tokens_reasoning,
               s.tokens_cache_read,
               s.tokens_cache_write,
               json_extract(m.data, '$.role'),
               json_extract(m.data, '$.time.completed'),
               json_extract(p.data, '$.text'),
               (
                   SELECT COUNT(*)
                   FROM message user_message
                   WHERE user_message.session_id = s.id
                     AND json_extract(user_message.data, '$.role') = 'user'
               )
        FROM session s
        LEFT JOIN message m ON m.id = (
            SELECT latest.id
            FROM message latest
            WHERE latest.session_id = s.id
            ORDER BY latest.time_created DESC, latest.id DESC
            LIMIT 1
        )
        LEFT JOIN part p ON p.id = (
            SELECT latest_part.id
            FROM part latest_part
            WHERE latest_part.session_id = s.id
              AND json_extract(latest_part.data, '$.type') = 'text'
            ORDER BY latest_part.time_created DESC, latest_part.id DESC
            LIMIT 1
        )
        WHERE s.time_archived IS NULL
          AND s.time_updated >= ?
        ORDER BY s.time_updated DESC
        LIMIT ?
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(cutoff.timeIntervalSince1970 * 1000))
        sqlite3_bind_int(statement, 2, Int32(max(limit, 1)))

        let now = Date()
        var items: [CodexThreadItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawID = text(statement, 0), !rawID.isEmpty,
                  let rawTitle = text(statement, 1), !rawTitle.isEmpty else {
                continue
            }
            let createdAt = date(milliseconds: Int64(integer(statement, 4)))
            let updatedAt = date(milliseconds: Int64(integer(statement, 5)))
            let lastMessageAt = date(milliseconds: Int64(integer(statement, 6)))
            guard updatedAt >= cutoff else { continue }
            let role = text(statement, 13)
            let assistantCompleted = sqlite3_column_type(statement, 14) != SQLITE_NULL
            let preview = compactPreview(text(statement, 15))
            let turns = integer(statement, 16)
            let isFresh = now.timeIntervalSince(updatedAt) <= activeTimeout
            let isRunning = isFresh && (role == "user" || (role == "assistant" && !assistantCompleted))
            let status: ThreadRunStatus
            if isRunning {
                status = .running
            } else if role == "user" || (role == "assistant" && !assistantCompleted) {
                status = .stale
            } else {
                status = .unread
            }
            let itemID = "opencode:\(rawID)"
            if status == .stale,
               !TaskBarSettings.isPinned(itemID),
               now.timeIntervalSince(updatedAt) > staleVisibilityTimeout {
                continue
            }

            let freshInput = integer(statement, 8)
            let output = integer(statement, 9)
            let reasoning = integer(statement, 10)
            let cachedInput = integer(statement, 11)
            let cacheWrite = integer(statement, 12)
            let input = freshInput + cachedInput + cacheWrite
            let total = input + output + reasoning
            let tokenBreakdown = TokenBreakdown(
                input: input,
                cachedInput: cachedInput,
                output: output,
                reasoningOutput: reasoning,
                total: total,
                hasDetailedCounters: total > 0
            )
            let parentID = text(statement, 3).map { "opencode:\($0)" }
            items.append(CodexThreadItem(
                id: itemID,
                title: rawTitle,
                preview: preview,
                cwd: text(statement, 2),
                lastActivity: updatedAt,
                startedAt: isRunning ? max(createdAt, lastMessageAt) : nil,
                externalReadAt: nil,
                status: status,
                turns: turns,
                compressionCount: nil,
                source: "opencode",
                isExplicitUnread: false,
                codexUpdatedAt: nil,
                tokensUsed: tokenBreakdown.displayTotal,
                tokenBreakdown: tokenBreakdown,
                model: text(statement, 7),
                threadKind: parentID == nil ? .root : .subtask,
                parentThreadID: parentID,
                agentNickname: nil,
                agentPath: nil,
                plan: nil,
                launchTarget: .codexDesktop
            ))
        }
        return items
    }

    private func date(milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    private func compactPreview(_ value: String?) -> String? {
        guard let value else { return nil }
        let compact = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else { return nil }
        return compact.count > 280 ? String(compact.prefix(280)) + "…" : compact
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    private func integer(_ statement: OpaquePointer, _ index: Int32) -> Int {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? 0 : Int(sqlite3_column_int64(statement, index))
    }
}
