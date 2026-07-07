import Cocoa
import Foundation

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

func statusColor(_ status: ThreadRunStatus) -> NSColor {
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

func compactStatusLabel(_ status: ThreadRunStatus) -> String {
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
func statusAccentColor(_ status: ThreadRunStatus) -> NSColor {
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

func rowStatusLabel(_ status: ThreadRunStatus) -> String {
    switch status {
    case .running, .stale:
        return "Running"
    case .waiting:
        return "Waiting"
    case .unread:
        return "Done"
    }
}

/// Metadata trailing text: colored status word, optionally followed by the
/// Codex / Claude source label in its accent color.
func rowMetadataAttributed(for item: CodexThreadItem, showSource: Bool) -> NSAttributedString {
    let font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
    let result = NSMutableAttributedString(string: rowStatusLabel(item.status), attributes: [
        .font: font,
        .foregroundColor: statusAccentColor(item.status)
    ])
    if showSource {
        result.append(NSAttributedString(string: "   ·  ", attributes: [
            .font: font,
            .foregroundColor: NSColor(calibratedWhite: 0.42, alpha: 1)
        ]))
        result.append(NSAttributedString(string: sourceLabel(item), attributes: [
            .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
            .foregroundColor: sourceColor(item)
        ]))
    }
    return result
}

/// Just the colored status word — used for the compact layout's left rail,
/// where the source label lives on its own line.
func rowStatusOnlyAttributed(for item: CodexThreadItem) -> NSAttributedString {
    NSAttributedString(string: rowStatusLabel(item.status), attributes: [
        .font: NSFont.systemFont(ofSize: 10.5, weight: .medium),
        .foregroundColor: statusAccentColor(item.status)
    ])
}

/// Just the colored Codex / Claude source label, for the compact left rail.
func rowSourceAttributed(for item: CodexThreadItem) -> NSAttributedString {
    NSAttributedString(string: sourceLabel(item), attributes: [
        .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
        .foregroundColor: sourceColor(item)
    ])
}

/// Clock-style elapsed time: "MM:SS", or "HH:MM:SS" once past an hour.
func clockDuration(_ date: Date) -> String {
    let total = max(0, Int(Date().timeIntervalSince(date)))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    if hours > 0 {
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%02d:%02d", minutes, seconds)
}

func statusRank(_ status: ThreadRunStatus) -> Int {
    switch status {
    case .stale: return 0
    case .running: return 1
    case .waiting: return 2
    case .unread: return 3
    }
}

func statusDisplayRank(_ status: ThreadRunStatus) -> Int {
    let order = TaskBarSettings.statusGroupOrder
    let base = (order.firstIndex(of: TaskStatusGroup.group(for: status)) ?? 0) * 10
    // Within the running group, keep stale ahead of running (historical behavior).
    return status == .running ? base + 1 : base
}

func stableThreadOrder(_ lhs: CodexThreadItem, _ rhs: CodexThreadItem) -> Bool {
    // Pinned threads float above everything; among themselves they keep the
    // same status/user-selected ordering as the rest of the list.
    let pinned = TaskBarSettings.pinnedThreadIDs
    let lhsPinned = pinned.contains(lhs.id)
    let rhsPinned = pinned.contains(rhs.id)
    if lhsPinned != rhsPinned { return lhsPinned }

    let lhsRank = statusDisplayRank(lhs.status)
    let rhsRank = statusDisplayRank(rhs.status)
    if lhsRank != rhsRank { return lhsRank < rhsRank }

    let sortMode = TaskBarSettings.threadSortMode
    let lhsPrimary = threadSortTimestamp(lhs, mode: sortMode)
    let rhsPrimary = threadSortTimestamp(rhs, mode: sortMode)
    if lhsPrimary != rhsPrimary {
        return sortMode.sortsAscending ? lhsPrimary < rhsPrimary : lhsPrimary > rhsPrimary
    }

    let lhsActivity = lhs.lastActivity.timeIntervalSince1970
    let rhsActivity = rhs.lastActivity.timeIntervalSince1970
    if lhsActivity != rhsActivity { return lhsActivity > rhsActivity }

    let lhsID = lhs.id.lowercased()
    let rhsID = rhs.id.lowercased()
    if lhsID != rhsID { return lhsID > rhsID }

    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
}

private func threadSortTimestamp(_ item: CodexThreadItem, mode: TaskThreadSortMode) -> TimeInterval {
    switch mode {
    case .updatedNewest:
        return item.lastActivity.timeIntervalSince1970
    case .startedNewest, .startedOldest:
        return (item.startedAt ?? item.lastActivity).timeIntervalSince1970
    }
}

extension Array where Element == CodexThreadItem {
    func limitedForTaskBar(limit: Int) -> [CodexThreadItem] {
        let limit = Swift.max(1, limit)
        // Keep every active thread and every pinned thread; only cap the remaining
        // finished ("done"/unread) rows to fit the limit.
        let pinned = TaskBarSettings.pinnedThreadIDs
        let alwaysKeptCount = filter { $0.status != .unread || pinned.contains($0.id) }.count
        let doneAllowed = Swift.max(0, limit - alwaysKeptCount)
        // Preserve the incoming sort order (which honors the custom group order) instead of
        // re-segregating active-before-done, so a "done first" order stays intact.
        var doneKept = 0
        return filter { item in
            guard item.status == .unread, !pinned.contains(item.id) else { return true }
            defer { doneKept += 1 }
            return doneKept < doneAllowed
        }
    }
}

func statusLabel(_ status: ThreadRunStatus) -> String {
    switch status {
    case .running: return "Running"
    case .stale: return "Running"
    case .waiting: return "Waiting"
    case .unread: return "Unread"
    }
}

func detailText(for item: CodexThreadItem) -> String {
    let folder = shortFolderName(item.cwd)
    if item.status == .running || item.status == .stale {
        return folder
    }
    return "\(folder)  ·  \(relative(item.lastActivity))"
}

func statusElapsedText(for item: CodexThreadItem) -> String? {
    switch item.status {
    case .running, .stale:
        return clockDuration(item.startedAt ?? item.lastActivity)
    case .waiting:
        return clockDuration(item.lastActivity)
    case .unread:
        return clockDuration(item.lastActivity)
    }
}

func tooltipText(for item: CodexThreadItem) -> String {
    tooltipRows(for: item)
        .filter { !$0.isSeparator }
        .map { "\($0.label): \($0.value)" }
        .joined(separator: "\n")
}

func tooltipRows(for item: CodexThreadItem) -> [ThreadTooltipRow] {
    let hiddenItems = TaskBarSettings.hoverHiddenItemIDs
    var rows: [ThreadTooltipRow] = []
    for layoutItem in TaskBarSettings.hoverLayout {
        guard !hiddenItems.contains(layoutItem.visibilityKey) else { continue }
        switch layoutItem {
        case .separator:
            rows.append(.separator())
        case .field(let field):
            guard let row = tooltipRow(for: field, item: item) else { continue }
            rows.append(row)
        }
    }
    return cleanedTooltipRows(rows)
}

func tooltipRow(for field: TaskHoverField, item: CodexThreadItem) -> ThreadTooltipRow? {
    switch field {
    case .status:
        return ThreadTooltipRow("状态", tooltipStatusLabel(item.status), valueColor: statusColor(item.status), emphasized: true)
    case .folder:
        guard let cwd = item.cwd, !cwd.isEmpty else { return nil }
        return ThreadTooltipRow("文件夹", cwd)
    case .branch:
        if let branch = gitBranchName(for: item.cwd), !branch.isEmpty {
            return ThreadTooltipRow("分支", branch)
        }
        guard item.cwd?.isEmpty == false else { return unavailableContextRow("分支", "未知") }
        return unavailableContextRow("分支", "非 Git 仓库")
    case .worktree:
        if let worktree = worktreeName(for: item.cwd), !worktree.isEmpty {
            return ThreadTooltipRow("Worktree", worktree)
        }
        guard item.cwd?.isEmpty == false else { return unavailableContextRow("Worktree", "未知") }
        return unavailableContextRow("Worktree", gitBranchName(for: item.cwd) == nil ? "普通目录" : "默认工作区")
    case .input:
        guard item.tokenBreakdown.hasDetailedCounters else { return nil }
        return ThreadTooltipRow("输入", compactTokenCount(item.tokenBreakdown.input))
    case .output:
        guard item.tokenBreakdown.hasDetailedCounters else { return nil }
        return ThreadTooltipRow("输出", compactTokenCount(item.tokenBreakdown.output))
    case .cacheRate:
        guard item.tokenBreakdown.hasDetailedCounters,
              let cacheRate = cacheRateText(for: item.tokenBreakdown) else { return nil }
        return ThreadTooltipRow("缓存率", cacheRate)
    case .tokenTotal:
        guard !item.tokenBreakdown.hasDetailedCounters,
              let total = item.tokenBreakdown.displayTotal else { return nil }
        return ThreadTooltipRow("Token 消耗", compactTokenCount(total))
    case .turns:
        return ThreadTooltipRow("对话轮次", item.turns > 0 ? "\(item.turns)" : "未知")
    case .compression:
        guard let compressionCount = item.compressionCount else { return nil }
        return ThreadTooltipRow("压缩次数", "\(compressionCount)")
    case .model:
        guard let model = item.model, !model.isEmpty else { return nil }
        return ThreadTooltipRow("模型", model)
    }
}

private func unavailableContextRow(_ label: String, _ value: String) -> ThreadTooltipRow {
    ThreadTooltipRow(label, value, valueColor: NSColor.white.withAlphaComponent(0.42))
}

func cleanedTooltipRows(_ rows: [ThreadTooltipRow]) -> [ThreadTooltipRow] {
    var result: [ThreadTooltipRow] = []
    for row in rows {
        if row.isSeparator {
            guard !result.isEmpty, result.last?.isSeparator != true else { continue }
        }
        result.append(row)
    }
    while result.last?.isSeparator == true {
        result.removeLast()
    }
    return result
}

func tooltipStatusLabel(_ status: ThreadRunStatus) -> String {
    switch status {
    case .running: return "运行中"
    case .stale: return "运行较久"
    case .waiting: return "等待输入"
    case .unread: return "未读"
    }
}

let menuPanelWidth: CGFloat = 420
let taskBarPopoverMinWidth: CGFloat = 340
let taskBarPopoverMinHeight: CGFloat = 200
let taskBarVisibleThreadLimit = 12
let taskBarCandidateThreadLimit = 48
let menuPanelBackground = NSColor(calibratedWhite: 0.105, alpha: 0.97)
let taskBarRowHeight: CGFloat = 92
let taskBarCompactRowHeight: CGFloat = 72
let taskBarEmptyStateHeight: CGFloat = 120

func taskBarPopoverMaxHeight() -> CGFloat {
    let mouse = NSEvent.mouseLocation
    let screenHeight = NSScreen.screens.first { $0.frame.contains(mouse) }?.visibleFrame.height
        ?? NSScreen.main?.visibleFrame.height
        ?? 900
    return min(620, max(360, screenHeight - 110))
}

func taskBarPopoverMaxResizableSize() -> NSSize {
    let mouse = NSEvent.mouseLocation
    let visibleFrame = NSScreen.screens.first { $0.frame.contains(mouse) }?.visibleFrame
        ?? NSScreen.main?.visibleFrame
        ?? NSRect(x: 0, y: 0, width: 900, height: 900)
    return NSSize(
        width: max(taskBarPopoverMinWidth, min(760, visibleFrame.width - 48)),
        height: max(taskBarPopoverMinHeight, visibleFrame.height - 110)
    )
}

func isReadDismissible(_ status: ThreadRunStatus) -> Bool {
    switch status {
    case .waiting, .unread:
        return true
    case .running, .stale:
        return false
    }
}

func isClaudeThread(_ item: CodexThreadItem) -> Bool {
    item.source == "claude-code" || item.id.hasPrefix("claude:")
}

func isCodexAPIThread(_ item: CodexThreadItem) -> Bool {
    item.source.contains("codex-api")
}

func sourceLabel(_ item: CodexThreadItem) -> String {
    if isClaudeThread(item) {
        return "Claude"
    }
    if isCodexAPIThread(item) {
        return "Codex API"
    }
    return "Codex"
}

func sourceColor(_ item: CodexThreadItem) -> NSColor {
    if isClaudeThread(item) {
        return NSColor(calibratedRed: 0.91, green: 0.48, blue: 0.28, alpha: 1)
    }
    if isCodexAPIThread(item) {
        return NSColor(calibratedRed: 0.36, green: 0.78, blue: 0.88, alpha: 1)
    }
    return NSColor(calibratedRed: 0.45, green: 0.58, blue: 1.0, alpha: 1)
}

func gitBranchName(for cwd: String?) -> String? {
    guard let cwd, !cwd.isEmpty else { return nil }
    let fileManager = FileManager.default
    let folderURL = URL(fileURLWithPath: cwd, isDirectory: true)
    let dotGitURL = folderURL.appendingPathComponent(".git")
    var isDirectory: ObjCBool = false
    var gitDirectoryURL: URL

    if fileManager.fileExists(atPath: dotGitURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
        gitDirectoryURL = dotGitURL
    } else if let gitFile = try? String(contentsOf: dotGitURL, encoding: .utf8),
              let gitdirLine = gitFile.split(separator: "\n").first(where: { $0.lowercased().hasPrefix("gitdir:") }) {
        let path = gitdirLine.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines)
        gitDirectoryURL = path.hasPrefix("/")
            ? URL(fileURLWithPath: path, isDirectory: true)
            : folderURL.appendingPathComponent(path, isDirectory: true).standardizedFileURL
    } else {
        return nil
    }

    guard let head = try? String(contentsOf: gitDirectoryURL.appendingPathComponent("HEAD"), encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines),
          !head.isEmpty else {
        return nil
    }
    if head.hasPrefix("ref: refs/heads/") {
        return String(head.dropFirst("ref: refs/heads/".count))
    }
    if head.count >= 7 {
        return String(head.prefix(7))
    }
    return head
}

func worktreeName(for cwd: String?) -> String? {
    guard let cwd, !cwd.isEmpty else { return nil }
    let normalized = URL(fileURLWithPath: cwd, isDirectory: true).standardizedFileURL.path
    let components = normalized.split(separator: "/").map(String.init)
    if let worktreesIndex = components.firstIndex(of: ".codex"),
       components.indices.contains(worktreesIndex + 2),
       components[worktreesIndex + 1] == "worktrees" {
        let id = components[worktreesIndex + 2]
        let folder = components.last ?? id
        return id == folder ? id : "\(id) / \(folder)"
    }

    let dotGitURL = URL(fileURLWithPath: normalized, isDirectory: true).appendingPathComponent(".git")
    guard let gitFile = try? String(contentsOf: dotGitURL, encoding: .utf8),
          let gitdirLine = gitFile.split(separator: "\n").first(where: { $0.lowercased().hasPrefix("gitdir:") }) else {
        return nil
    }
    let gitdir = String(gitdirLine.dropFirst("gitdir:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
    let gitComponents = gitdir.split(separator: "/").map(String.init)
    guard let index = gitComponents.lastIndex(of: "worktrees"),
          gitComponents.indices.contains(index + 1) else {
        return nil
    }
    return gitComponents[index + 1]
}

func mergedCompressionCount(_ existing: Int?, _ candidate: Int) -> Int? {
    guard let existing else { return candidate }
    return max(existing, candidate)
}

func cleanTitle(_ value: String?) -> String? {
    guard let value else { return nil }
    let compact = normalizedTitleText(value)
    guard !compact.isEmpty else { return nil }
    guard !isUninformativeTitle(compact) else { return nil }
    if compact.count <= 68 {
        return compact
    }
    return String(compact.prefix(65)) + "..."
}

func cleanTitleCandidate(_ values: String?...) -> String? {
    for value in values {
        if let title = cleanTitle(value) {
            return title
        }
    }
    return nil
}

func normalizedTitleText(_ value: String) -> String {
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

func isUninformativeTitle(_ value: String) -> Bool {
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

func removingMediaMarkup(from value: String) -> String {
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

func replacingMarkdownLinksWithLabels(in value: String) -> String {
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

func removingBareURLs(from value: String) -> String {
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

func isUninformativeLinkLabel(_ value: String) -> Bool {
    let compact = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if compact.isEmpty { return true }
    let lower = compact.lowercased()
    return lower.hasPrefix("http://")
        || lower.hasPrefix("https://")
        || lower.hasPrefix("www.")
        || looksLikeURLHost(lower)
}

func looksLikeURLHost(_ value: String) -> Bool {
    guard value.contains(".") else { return false }
    let lower = value.lowercased()
    let hostSuffixes = [".com", ".net", ".org", ".io", ".ai", ".cn", ".co", ".dev", ".app", ".site", ".xyz"]
    return hostSuffixes.contains { suffix in
        lower == String(lower.prefix(max(0, lower.count - suffix.count))) + suffix
            || lower.contains("\(suffix)/")
    }
}

func cleanPreview(_ value: String?) -> String? {
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

func automationPreviewText(from value: String) -> String? {
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

func xmlTagValue(_ tag: String, in value: String) -> String? {
    let openTag = "<\(tag)>"
    let closeTag = "</\(tag)>"
    guard let start = value.range(of: openTag, options: [.caseInsensitive]),
          let end = value.range(of: closeTag, options: [.caseInsensitive], range: start.upperBound..<value.endIndex) else {
        return nil
    }
    return String(value[start.upperBound..<end.lowerBound])
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func stripXMLTags(from value: String) -> String {
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

func removingPluginMarkdownLinks(from value: String) -> String {
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

func shortFolderName(_ value: String?) -> String {
    guard let value, !value.isEmpty else { return "unknown" }
    let last = URL(fileURLWithPath: value).lastPathComponent
    return last.isEmpty ? value : last
}

func unique(_ urls: [URL]) -> [URL] {
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

func maxDate(_ lhs: Date, _ rhs: Date?) -> Date {
    guard let rhs else { return lhs }
    return lhs > rhs ? lhs : rhs
}

func maxOptionalDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
    guard let lhs else { return rhs }
    guard let rhs else { return lhs }
    return lhs > rhs ? lhs : rhs
}

func unixDate(seconds: Double) -> Date {
    Date(timeIntervalSince1970: normalizedUnixSeconds(seconds))
}

func normalizedUnixSeconds(_ value: Double) -> Double {
    value > 10_000_000_000 ? value / 1000 : value
}

func iso8601Date(_ value: String) -> Date? {
    if let date = ISO8601DateFormatter.codexPetBarWithFractionalSeconds.date(from: value) {
        return date
    }
    return ISO8601DateFormatter.codexPetBar.date(from: value)
}

func string(_ value: Any?) -> String? {
    if let value = value as? String { return value }
    if let value { return "\(value)" }
    return nil
}

func double(_ value: Any?) -> Double? {
    if let value = value as? Double { return value }
    if let value = value as? Int { return Double(value) }
    if let value = value as? Int64 { return Double(value) }
    if let value = value as? String { return Double(value) }
    return nil
}

func intValue(_ value: Any?) -> Int? {
    if let value = value as? Int { return value }
    if let value = value as? Int64 { return Int(value) }
    if let value = value as? Double { return Int(value) }
    if let value = value as? String { return Int(value) }
    return nil
}

func formatInteger(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
}

func compactTokenCount(_ value: Int) -> String {
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

func cacheRateText(for breakdown: TokenBreakdown) -> String? {
    guard breakdown.hasDetailedCounters, breakdown.input > 0 else { return nil }
    let percent = Double(breakdown.cachedInput) / Double(breakdown.input) * 100
    return String(format: "%.1f%%", percent)
}

func sqlStringLiteral(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "''"))'"
}

func bool(_ value: Any?) -> Bool? {
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

func turnCount(from value: Any?) -> Int {
    if let array = value as? [Any] { return array.count }
    return Int(double(value) ?? 0)
}

func tokenBreakdown(from dict: [String: Any]) -> TokenBreakdown {
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

func tokenUsageDictionary(from dict: [String: Any]) -> [String: Any] {
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

func firstValue(in dict: [String: Any], keys: [String]) -> Any? {
    for key in keys {
        if let value = dict[key] {
            return value
        }
    }
    return nil
}

func firstDictionary(in dict: [String: Any], keys: [String]) -> [String: Any]? {
    for key in keys {
        if let value = dict[key] as? [String: Any] {
            return value
        }
    }
    return nil
}

func containsAnyKey(_ dict: [String: Any], _ keys: [String]) -> Bool {
    keys.contains { dict.keys.contains($0) }
}

func relative(_ date: Date) -> String {
    let seconds = max(0, Int(Date().timeIntervalSince(date)))
    if seconds < 60 { return "\(seconds)s ago" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m ago" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h ago" }
    return "\(hours / 24)d ago"
}

func relativeChinese(_ date: Date) -> String {
    let seconds = max(0, Int(Date().timeIntervalSince(date)))
    if seconds < 60 { return "\(seconds)秒前" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)分钟前" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)小时前" }
    return "\(hours / 24)天前"
}

func durationSince(_ date: Date) -> String {
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

func durationSinceChinese(_ date: Date) -> String {
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

func compactDurationSinceChinese(_ date: Date) -> String {
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

extension ISO8601DateFormatter {
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
