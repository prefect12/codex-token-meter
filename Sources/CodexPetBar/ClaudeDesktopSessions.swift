import Foundation

/// One `local_<desktop-session-id>.json` record written by Claude Desktop under
/// `~/Library/Application Support/Claude/claude-code-sessions/<account>/<org>/`.
///
/// The desktop app writes this metadata when the session is created, so it knows
/// the model, title, branch, and worktree before the CLI transcript contains a
/// single assistant reply. Task Bar uses it both to fill hover fields during the
/// first turn and to pick the deep link that reaches the session the user is
/// actually looking at.
struct ClaudeDesktopSession {
    /// Value of the `sessionId` field; already carries the `local_` prefix.
    var desktopID: String
    var cliSessionID: String?
    /// The file is named `local_<cliSessionID>.json`, i.e. the desktop entry was
    /// created by importing an existing CLI session rather than natively.
    var isImported: Bool
    var isArchived: Bool
    var lastFocusedAt: Double
    var lastActivityAt: Double
    var model: String?
    var effort: String?
    var title: String?
    var cwd: String?
    var branch: String?
    var worktreeName: String?

    /// Newest signal of "this is the entry the user last touched". Focus and
    /// activity are written independently, so neither alone orders the entries.
    var recency: Double { max(lastFocusedAt, lastActivityAt) }
}

/// Cached index over the desktop session metadata directory.
///
/// Reading is cheap per refresh: directory listings are re-walked at most once
/// every `reloadInterval`, and each JSON file is parsed only when its size or
/// modification date changes.
final class ClaudeDesktopSessionIndex {
    static let shared = ClaudeDesktopSessionIndex()

    private struct FileCacheEntry {
        let signature: String
        let session: ClaudeDesktopSession?
    }

    private let root: URL
    private let fileManager = FileManager.default
    private let lock = NSLock()
    private let reloadInterval: TimeInterval = 5
    private var fileCache: [String: FileCacheEntry] = [:]
    private var sessionsByCLIID: [String: [ClaudeDesktopSession]] = [:]
    private var globalLastFocusedValue: Double = 0
    private var lastLoadedAt = Date.distantPast

    init(root: URL? = nil) {
        self.root = root
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions", isDirectory: true)
    }

    /// Every desktop entry that points at the given CLI session, newest first.
    func sessions(forCLISession cliID: String) -> [ClaudeDesktopSession] {
        lock.lock()
        defer { lock.unlock() }
        reloadIfNeededLocked()
        return sessionsByCLIID[cliID] ?? []
    }

    /// The entry the user most recently focused or worked in, if any.
    func currentSession(forCLISession cliID: String) -> ClaudeDesktopSession? {
        sessions(forCLISession: cliID).first
    }

    /// Highest `lastFocusedAt` across every stored session, used to tell whether
    /// the desktop app is already showing a given session.
    func globalLastFocused() -> Double {
        lock.lock()
        defer { lock.unlock() }
        reloadIfNeededLocked()
        return globalLastFocusedValue
    }

    private func reloadIfNeededLocked(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastLoadedAt) >= reloadInterval else { return }
        lastLoadedAt = Date()

        var byCLIID: [String: [ClaudeDesktopSession]] = [:]
        var globalLastFocused: Double = 0
        var seenPaths = Set<String>()

        for file in metadataFiles() {
            seenPaths.insert(file.path)
            guard let session = session(at: file) else { continue }
            globalLastFocused = max(globalLastFocused, session.lastFocusedAt)
            guard let cliID = session.cliSessionID, !cliID.isEmpty else { continue }
            byCLIID[cliID, default: []].append(session)
        }
        for key in fileCache.keys where !seenPaths.contains(key) {
            fileCache.removeValue(forKey: key)
        }
        for (cliID, sessions) in byCLIID {
            byCLIID[cliID] = sessions.sorted { $0.recency > $1.recency }
        }
        sessionsByCLIID = byCLIID
        globalLastFocusedValue = globalLastFocused
    }

    private func metadataFiles() -> [URL] {
        guard let accountDirs = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var files: [URL] = []
        for accountDir in accountDirs {
            guard let orgDirs = try? fileManager.contentsOfDirectory(
                at: accountDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for orgDir in orgDirs {
                guard let entries = try? fileManager.contentsOfDirectory(
                    at: orgDir,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ) else {
                    continue
                }
                for entry in entries
                where entry.lastPathComponent.hasPrefix("local_") && entry.pathExtension == "json" {
                    files.append(entry)
                }
            }
        }
        return files
    }

    private func session(at url: URL) -> ClaudeDesktopSession? {
        let path = url.path
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let signature = "\(values?.fileSize ?? -1)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? -1)"
        if let cached = fileCache[path], cached.signature == signature {
            return cached.session
        }
        let parsed = parseSession(at: url)
        fileCache[path] = FileCacheEntry(signature: signature, session: parsed)
        return parsed
    }

    private func parseSession(at url: URL) -> ClaudeDesktopSession? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let filename = url.lastPathComponent
        let idFromName = String(filename.dropLast(".json".count))
        let cliSessionID = object["cliSessionId"] as? String
        return ClaudeDesktopSession(
            desktopID: object["sessionId"] as? String ?? idFromName,
            cliSessionID: cliSessionID,
            isImported: cliSessionID.map { "local_\($0)" == idFromName } ?? false,
            isArchived: object["isArchived"] as? Bool ?? false,
            lastFocusedAt: doubleValue(object["lastFocusedAt"]),
            lastActivityAt: doubleValue(object["lastActivityAt"]),
            model: nonEmpty(object["model"]),
            effort: nonEmpty(object["effort"]),
            title: nonEmpty(object["title"]),
            cwd: nonEmpty(object["cwd"]),
            branch: nonEmpty(object["branch"]),
            worktreeName: nonEmpty(object["worktreeName"])
        )
    }

    private func doubleValue(_ raw: Any?) -> Double {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        return 0
    }

    private func nonEmpty(_ raw: Any?) -> String? {
        guard let value = raw as? String, !value.isEmpty else { return nil }
        return value
    }
}
