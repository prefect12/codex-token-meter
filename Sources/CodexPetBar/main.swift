import Cocoa
import CoreText
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
    let status: ThreadRunStatus
    let turns: Int
    let source: String
}

private struct ReadStateFile: Codable {
    var didBaselineExistingWaiting: Bool
    var openedAt: [String: TimeInterval]
}

private struct LoggedThread {
    let id: String
    let lastActivity: Date
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
}

final class CodexActivityReader {
    private let fileManager = FileManager.default
    private let home = NSHomeDirectory()

    func read(limit: Int = 12, lookbackHours: Int = 12) -> [CodexThreadItem] {
        var byID: [String: CodexThreadItem] = [:]
        for item in readFromAppServer(limit: limit) {
            byID[item.id] = item
        }

        for logged in recentLoggedThreads(limit: max(limit * 3, 18), lookbackHours: lookbackHours) {
            let rollout = rolloutURL(threadID: logged.id, lastActivity: logged.lastActivity, lookbackHours: lookbackHours)
            let summary = rollout.flatMap(rolloutSummary)
            guard let summary, summary.turns > 0 else { continue }
            if let existing = byID[logged.id] {
                byID[logged.id] = CodexThreadItem(
                    id: existing.id,
                    title: existing.title,
                    preview: summary.preview ?? existing.preview,
                    cwd: existing.cwd ?? summary.cwd,
                    lastActivity: maxDate(existing.lastActivity, summary.lastTaskEventAt),
                    startedAt: existing.startedAt ?? (summary.isRunning ? summary.currentTurnStartedAt : nil),
                    status: existing.status,
                    turns: existing.turns > 0 ? existing.turns : summary.turns,
                    source: existing.source
                )
                continue
            }
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
                status: status,
                turns: summary.turns,
                source: "logs"
            )
        }

        return Array(byID.values)
            .sorted(by: stableThreadOrder)
            .prefix(limit)
            .map { $0 }
    }

    private func readFromAppServer(limit: Int) -> [CodexThreadItem] {
        guard let codexPath = codexExecutablePath() else { return [] }
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
            return []
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
            #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"codex-bar","version":"0.1.0"},"capabilities":{}}}"#,
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
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return [] }
        return parseAppServerThreads(text: text, limit: limit)
    }

    private func parseAppServerThreads(text: String, limit: Int) -> [CodexThreadItem] {
        var items: [CodexThreadItem] = []
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
                let title = cleanTitle(string(dict["title"] ?? dict["name"] ?? dict["preview"])) ?? String(id.prefix(8))
                let cwd = string(dict["cwd"] ?? dict["workingDirectory"] ?? dict["path"])
                let updatedSeconds = double(dict["updatedAt"] ?? dict["updated_at"] ?? dict["lastActivityAt"]) ?? Date().timeIntervalSince1970
                guard let status = appServerStatus(from: dict["status"]) else { continue }
                items.append(CodexThreadItem(
                    id: id,
                    title: title,
                    preview: cleanPreview(string(dict["lastAgentMessage"] ?? dict["lastMessage"] ?? dict["subtitle"] ?? dict["summary"])),
                    cwd: cwd,
                    lastActivity: Date(timeIntervalSince1970: updatedSeconds > 10_000_000_000 ? updatedSeconds / 1000 : updatedSeconds),
                    startedAt: nil,
                    status: status,
                    turns: Int(double(dict["turns"] ?? dict["turnCount"]) ?? 0),
                    source: "app-server"
                ))
            }
        }
        return Array(items.prefix(limit))
    }

    private func appServerStatus(from raw: Any?) -> ThreadRunStatus? {
        let rawText: String
        if let dict = raw as? [String: Any] {
            let type = string(dict["type"]) ?? ""
            let flags = (dict["activeFlags"] as? [Any])?.compactMap(string).joined(separator: " ") ?? ""
            rawText = "\(type) \(flags)"
        } else {
            rawText = string(raw) ?? ""
        }
        let statusText = rawText.lowercased()
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
            codexHome.appendingPathComponent("sessions", isDirectory: true),
            codexHome.appendingPathComponent("archived_sessions", isDirectory: true)
        ]
        if let env = ProcessInfo.processInfo.environment["CODEX_HOME"], !env.isEmpty {
            let custom = URL(fileURLWithPath: (env as NSString).expandingTildeInPath, isDirectory: true)
            roots.append(custom.appendingPathComponent("sessions", isDirectory: true))
            roots.append(custom.appendingPathComponent("archived_sessions", isDirectory: true))
        }
        return unique(roots)
    }

    private func logsDatabaseURLs() -> [URL] {
        let codexHome = URL(fileURLWithPath: home).appendingPathComponent(".codex", isDirectory: true)
        return [
            codexHome.appendingPathComponent("logs_2.sqlite"),
            codexHome.appendingPathComponent("sqlite/logs_2.sqlite")
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
    private static let readWatermarkTolerance: TimeInterval = 60
    private let fileManager = FileManager.default
    private let fileURL: URL
    private let launchDate = Date()
    private let lock = NSLock()
    private var state: ReadStateFile

    init() {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        let directory = support.appendingPathComponent("Codex Bar", isDirectory: true)
        let legacyDirectory = support.appendingPathComponent("Codex Pet Bar", isDirectory: true)
        fileURL = directory.appendingPathComponent("read-state.json")
        let legacyFileURL = legacyDirectory.appendingPathComponent("read-state.json")
        let sourceURL = fileManager.fileExists(atPath: fileURL.path) ? fileURL : legacyFileURL
        if let data = try? Data(contentsOf: sourceURL),
           let decoded = try? JSONDecoder().decode(ReadStateFile.self, from: data) {
            state = decoded
        } else {
            state = ReadStateFile(didBaselineExistingWaiting: false, openedAt: [:])
        }
    }

    func visibleThreads(from items: [CodexThreadItem]) -> [CodexThreadItem] {
        lock.lock()
        var current = state
        if !current.didBaselineExistingWaiting {
            for item in items where isReadDismissible(item.status) {
                current.openedAt[item.id] = readThroughTime(for: item)
            }
            current.didBaselineExistingWaiting = true
            state = current
            saveLocked()
        }
        let visible = items.filter { item in
            switch item.status {
            case .running, .stale:
                return true
            case .waiting, .unread:
                if item.lastActivity < launchDate {
                    current.openedAt[item.id] = readThroughTime(for: item)
                    state = current
                    saveLocked()
                    return false
                }
                let readAt = current.openedAt[item.id] ?? 0
                return readAt < item.lastActivity.timeIntervalSince1970
            }
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
            color = NSColor.systemBlue
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
    private let titleLabel = NSTextField(labelWithString: "Codex Bar")
    private let summaryLabel = NSTextField(labelWithString: "")

    init(runningCount: Int, unreadCount: Int) {
        super.init(frame: NSRect(x: 0, y: 0, width: menuPanelWidth, height: 62))
        wantsLayer = true
        layer?.backgroundColor = menuPanelBackground.cgColor

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        summaryLabel.stringValue = summaryText(runningCount: runningCount, unreadCount: unreadCount)
        summaryLabel.font = .systemFont(ofSize: 11, weight: .medium)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.lineBreakMode = .byTruncatingTail
        addSubview(summaryLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        titleLabel.frame = NSRect(x: 16, y: 29, width: bounds.width - 32, height: 18)
        summaryLabel.frame = NSRect(x: 16, y: 10, width: bounds.width - 32, height: 15)
    }
}

final class EmptyStateView: NSView {
    private let label = NSTextField(labelWithString: "No running or unread Codex turns")

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: menuPanelWidth, height: 40))
        wantsLayer = true
        layer?.backgroundColor = menuPanelBackground.cgColor
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: 16, y: 11, width: bounds.width - 32, height: 18)
    }
}

final class StatusPillView: NSView {
    var title: String {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    var color: NSColor {
        didSet { needsDisplay = true }
    }

    init(title: String, color: NSColor) {
        self.title = title
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        let textSize = attributedTitle().size()
        return NSSize(width: ceil(textSize.width) + 18, height: 19)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let pillRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        color.withAlphaComponent(0.13).setFill()
        NSBezierPath(roundedRect: pillRect, xRadius: 6, yRadius: 6).fill()
        color.withAlphaComponent(0.25).setStroke()
        let border = NSBezierPath(roundedRect: pillRect, xRadius: 6, yRadius: 6)
        border.lineWidth = 1
        border.stroke()

        let text = attributedTitle()
        let line = CTLineCreateWithAttributedString(text)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let lineHeight = ascent + descent
        let x = floor((bounds.width - width) / 2)
        let baselineY = floor((bounds.height - lineHeight) / 2 + descent)

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.textPosition = CGPoint(x: x, y: baselineY)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private func attributedTitle() -> NSAttributedString {
        NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: color
            ]
        )
    }
}

final class ThreadRowView: NSView {
    private let item: CodexThreadItem
    private let onOpen: (String) -> Void
    private let statusDot = NSView()
    private let statusLabelView: StatusPillView
    private let titleLabel = NSTextField(labelWithString: "")
    private let previewLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private var trackingAreaRef: NSTrackingArea?
    private var isHovering = false {
        didSet { needsDisplay = true }
    }

    init(item: CodexThreadItem, onOpen: @escaping (String) -> Void) {
        self.item = item
        self.onOpen = onOpen
        self.statusLabelView = StatusPillView(title: statusLabel(item.status), color: statusColor(item.status))
        super.init(frame: NSRect(x: 0, y: 0, width: menuPanelWidth, height: 76))
        wantsLayer = true
        layer?.backgroundColor = menuPanelBackground.cgColor

        statusDot.wantsLayer = true
        statusDot.layer?.backgroundColor = statusColor(item.status).withAlphaComponent(0.92).cgColor
        statusDot.layer?.cornerRadius = 4
        addSubview(statusDot)

        addSubview(statusLabelView)

        titleLabel.stringValue = item.title
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        addSubview(titleLabel)

        previewLabel.stringValue = item.preview ?? ""
        previewLabel.font = .systemFont(ofSize: 12, weight: .medium)
        previewLabel.textColor = .labelColor.withAlphaComponent(0.82)
        previewLabel.maximumNumberOfLines = 2
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.cell?.wraps = true
        previewLabel.cell?.isScrollable = false
        previewLabel.isHidden = item.preview == nil
        addSubview(previewLabel)

        detailLabel.stringValue = detailText(for: item)
        detailLabel.font = .systemFont(ofSize: 10, weight: .medium)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
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
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        trackingAreaRef = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
    }

    override func mouseUp(with event: NSEvent) {
        onOpen(item.id)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isHovering else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.13).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 10, dy: 4), xRadius: 7, yRadius: 7).fill()
    }

    override func layout() {
        super.layout()
        statusDot.frame = NSRect(x: 16, y: 57, width: 7, height: 7)
        titleLabel.frame = NSRect(x: 42, y: 53, width: bounds.width - 58, height: 17)
        if item.preview == nil {
            previewLabel.frame = .zero
            titleLabel.frame.origin.y = 40
        } else {
            previewLabel.frame = NSRect(x: 42, y: 21, width: bounds.width - 58, height: 30)
        }
        let pillWidth = max(58, min(86, statusLabelView.intrinsicContentSize.width))
        statusLabelView.frame = NSRect(x: 42, y: 3, width: pillWidth, height: 19)
        detailLabel.frame = NSRect(x: 42 + pillWidth + 10, y: 4, width: bounds.width - 42 - pillWidth - 26, height: 16)
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

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let reader = CodexActivityReader()
    private let icon = PetStatusIcon()
    private let readState = ReadStateStore()
    private var threads: [CodexThreadItem] = []
    private var refreshTimer: Timer?
    private var animationTimer: Timer?
    private var readInFlight = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.toolTip = "Codex Bar"
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            self?.updateStatusIcon()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
        refresh()
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
                if self.menu.highlightedItem == nil {
                    self.rebuildMenu()
                }
            }
        }
    }

    private func updateStatusIcon() {
        let primaryStatus = threads.map(\.status).sorted { statusRank($0) < statusRank($1) }.first
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

    private func rebuildMenu() {
        menu.removeAllItems()
        let active = threads.filter { $0.status == .running || $0.status == .stale }
        let unreadCount = threads.filter { isReadDismissible($0.status) }.count
        let headerItem = NSMenuItem()
        headerItem.view = PanelHeaderView(runningCount: active.count, unreadCount: unreadCount)
        menu.addItem(headerItem)
        menu.addItem(separatorItem())

        if threads.isEmpty {
            let emptyItem = NSMenuItem()
            emptyItem.view = EmptyStateView()
            menu.addItem(emptyItem)
        } else {
            for thread in threads {
                let item = NSMenuItem()
                item.view = ThreadRowView(item: thread) { [weak self] id in
                    self?.openThread(id: id)
                }
                menu.addItem(item)
                if thread.id != threads.last?.id {
                    menu.addItem(separatorItem())
                }
            }
        }

        menu.addItem(separatorItem())
        menu.addItem(commandItem(title: "Open Codex", symbolName: "arrow.up.right.square", shortcut: "⌘O", selector: #selector(openCodexApp), keyEquivalent: "o") { [weak self] in
            self?.menu.cancelTracking()
            self?.openCodexApp()
        })
        menu.addItem(commandItem(title: "Refresh", symbolName: "arrow.clockwise", shortcut: "⌘R", selector: #selector(refreshFromMenu), keyEquivalent: "r") { [weak self] in
            self?.menu.cancelTracking()
            self?.refreshFromMenu()
        })
        menu.addItem(commandItem(title: "Mark all as read", symbolName: "tray", shortcut: nil, selector: #selector(markWaitingAsRead), keyEquivalent: "", enabled: threads.contains { isReadDismissible($0.status) }) { [weak self] in
            self?.menu.cancelTracking()
            self?.markWaitingAsRead()
        })
        menu.addItem(separatorItem())
        menu.addItem(commandItem(title: "Quit Codex Bar", symbolName: "power", shortcut: "⌘Q", selector: #selector(quit), keyEquivalent: "q") { [weak self] in
            self?.menu.cancelTracking()
            self?.quit()
        })
    }

    private func separatorItem() -> NSMenuItem {
        let item = NSMenuItem()
        item.view = MenuSeparatorView()
        return item
    }

    private func commandItem(
        title: String,
        symbolName: String,
        shortcut: String?,
        selector: Selector,
        keyEquivalent: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: keyEquivalent)
        item.target = self
        item.isEnabled = enabled
        item.view = CommandRowView(title: title, symbolName: symbolName, shortcut: shortcut, enabled: enabled, action: action)
        return item
    }

    private func tooltip(for thread: CodexThreadItem) -> String {
        var lines = [
            thread.title,
            "Thread: \(thread.id)",
            "Status: \(statusLabel(thread.status))",
            "Last activity: \(relative(thread.lastActivity))",
            "Source: \(thread.source)"
        ]
        if thread.status == .running || thread.status == .stale,
           let startedAt = thread.startedAt {
            lines.append("Elapsed: \(durationSince(startedAt))")
        }
        if let cwd = thread.cwd {
            lines.append("Folder: \(cwd)")
        }
        return lines.joined(separator: "\n")
    }

    private func openThread(id: String) {
        guard let url = URL(string: "codex://threads/\(id)") else {
            return
        }
        if let item = threads.first(where: { $0.id == id }) {
            readState.markRead(item)
        } else {
            readState.markRead(threadID: id)
        }
        threads.removeAll { $0.id == id && isReadDismissible($0.status) }
        updateStatusIcon()
        rebuildMenu()
        menu.cancelTracking()
        NSWorkspace.shared.open(url)
    }

    @objc private func refreshFromMenu() {
        refresh()
    }

    @objc private func openCodexApp() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Codex.app"), configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func markWaitingAsRead() {
        readState.markWaitingRead(threads)
        threads.removeAll { isReadDismissible($0.status) }
        updateStatusIcon()
        rebuildMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private func summaryText(runningCount: Int, unreadCount: Int) -> String {
    if runningCount == 0 && unreadCount == 0 {
        return "All caught up"
    }
    return "\(runningCount) running  ·  \(unreadCount) unread"
}

private func statusColor(_ status: ThreadRunStatus) -> NSColor {
    switch status {
    case .running:
        return NSColor(calibratedRed: 0.35, green: 0.74, blue: 0.38, alpha: 1)
    case .stale:
        return NSColor(calibratedRed: 0.82, green: 0.58, blue: 0.30, alpha: 1)
    case .waiting:
        return NSColor(calibratedRed: 0.36, green: 0.62, blue: 0.91, alpha: 1)
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

private func stableThreadOrder(_ lhs: CodexThreadItem, _ rhs: CodexThreadItem) -> Bool {
    let lhsRank = statusRank(lhs.status)
    let rhsRank = statusRank(rhs.status)
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
    if (item.status == .running || item.status == .stale),
       let startedAt = item.startedAt {
        return "\(durationSince(startedAt))  ·  \(folder)"
    }
    return "\(folder)  ·  \(relative(item.lastActivity))"
}

private let menuPanelWidth: CGFloat = 390
private let menuPanelBackground = NSColor(calibratedWhite: 0.105, alpha: 0.97)

private func isReadDismissible(_ status: ThreadRunStatus) -> Bool {
    switch status {
    case .waiting, .unread:
        return true
    case .running, .stale:
        return false
    }
}

private func cleanTitle(_ value: String?) -> String? {
    guard let value else { return nil }
    let compact = value
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\t", with: " ")
        .split(separator: " ")
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !compact.isEmpty else { return nil }
    if compact.count <= 68 {
        return compact
    }
    return String(compact.prefix(65)) + "..."
}

private func cleanPreview(_ value: String?) -> String? {
    guard let value else { return nil }
    let compact = value
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

private func unixDate(seconds: Double) -> Date {
    Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1000 : seconds)
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

private func relative(_ date: Date) -> String {
    let seconds = max(0, Int(Date().timeIntervalSince(date)))
    if seconds < 60 { return "\(seconds)s ago" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m ago" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h ago" }
    return "\(hours / 24)d ago"
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

private func printThreads() {
    let items = ReadStateStore().visibleThreads(from: CodexActivityReader().read())
    if items.isEmpty {
        print("No running or unread Codex turns")
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
