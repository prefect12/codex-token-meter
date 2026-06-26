import Cocoa
import Foundation

enum TaskInsightVariant: String, CaseIterable {
    case timeline
    case detail
    case table

    var title: String {
        switch self {
        case .timeline: return "Timeline"
        case .detail: return "Detail"
        case .table: return "Table"
        }
    }

    var renderFileName: String {
        switch self {
        case .timeline: return "task-insights-timeline.png"
        case .detail: return "task-insights-detail.png"
        case .table: return "task-insights-table.png"
        }
    }
}

struct TaskInsightCompaction {
    let timestamp: Date
    let savedTokens: Int64?
}

struct TaskInsightContextPoint {
    let timestamp: Date
    let modelCall: Int
    let usedPercent: Double
}

struct TaskInsightEvent {
    let timestamp: Date
    let name: String
    let totalTokens: Int64?
    let lastCallTokens: Int64?
    let contextPercent: Double?
    let rateLimitPercent: Double?
}

struct TaskInsightSession {
    let id: String
    let rolloutPath: String
    let title: String
    let firstUserPrompt: String
    let cwd: String
    let startedAt: Date
    let lastActiveAt: Date
    let durationSeconds: TimeInterval
    let usage: Usage
    let modelCalls: Int
    let toolCalls: Int
    let toolOutputs: Int
    let messages: Int
    let userMessages: Int
    let assistantMessages: Int
    let model: String
    let contextWindow: Int64?
    let compactions: [TaskInsightCompaction]
    let contextPoints: [TaskInsightContextPoint]
    let events: [TaskInsightEvent]

    var projectName: String {
        guard cwd != "--" else { return "Unknown" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    var displayPath: String {
        let home = NSHomeDirectory()
        if cwd.hasPrefix(home) {
            return "~" + cwd.dropFirst(home.count)
        }
        return cwd
    }

    var cacheRatio: Double {
        usage.input == 0 ? 0 : Double(usage.cachedInput) / Double(usage.input) * 100
    }

    var contextPressurePeak: Double {
        contextPoints.map(\.usedPercent).max() ?? 0
    }
}

struct TaskInsightReport {
    let generatedAt: Date
    let days: Int
    let sessions: [TaskInsightSession]

    var totalUsage: Usage {
        sessions.reduce(Usage()) { partial, session in
            var next = partial
            next.add(session.usage)
            return next
        }
    }

    var compactedTasks: Int {
        sessions.filter { !$0.compactions.isEmpty }.count
    }

    var totalCompactions: Int {
        sessions.reduce(0) { $0 + $1.compactions.count }
    }

    var overFiveMillion: Int {
        sessions.filter { $0.usage.total >= 5_000_000 }.count
    }

    var averageDurationSeconds: TimeInterval {
        guard !sessions.isEmpty else { return 0 }
        return sessions.reduce(TimeInterval(0)) { $0 + $1.durationSeconds } / Double(sessions.count)
    }
}

final class TaskInsightsScanner {
    private let rootURLs: [URL]
    private let isoWithFractional: ISO8601DateFormatter
    private let isoPlain: ISO8601DateFormatter

    init(rootURLs: [URL]) {
        self.rootURLs = rootURLs
        isoWithFractional = ISO8601DateFormatter()
        isoWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]
    }

    func scan(days: Int = 30) -> TaskInsightReport {
        let dayCount = max(1, days)
        let start = Date().addingTimeInterval(-TimeInterval(dayCount) * 24 * 3600)
        let sessions = rolloutFiles(modifiedSince: start)
            .compactMap { parseSession(fileURL: $0, activeSince: start) }
            .sorted {
                if $0.usage.total == $1.usage.total {
                    return $0.lastActiveAt > $1.lastActiveAt
                }
                return $0.usage.total > $1.usage.total
            }
        return TaskInsightReport(generatedAt: Date(), days: dayCount, sessions: sessions)
    }

    private func rolloutFiles(modifiedSince start: Date) -> [URL] {
        var files: [URL] = []
        var seen = Set<String>()
        for rootURL in rootURLs {
            guard let enumerator = FileManager.default.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: []
            ) else {
                continue
            }
            for case let url as URL in enumerator {
                guard url.lastPathComponent.hasPrefix("rollout-"), url.pathExtension == "jsonl" else { continue }
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                guard values?.isRegularFile == true else { continue }
                if let modifiedAt = values?.contentModificationDate, modifiedAt < start {
                    continue
                }
                let key = (url.path as NSString).standardizingPath
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                files.append(url)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private func parseSession(fileURL: URL, activeSince start: Date) -> TaskInsightSession? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.readToEnd() else { return nil }
        guard let text = String(data: data, encoding: .utf8) else { return nil }

        var id = rolloutID(from: fileURL)
        var cwd: String?
        var model: String?
        var contextWindow: Int64?
        var usage = Usage()
        var previousTotal = Usage()
        var modelCalls = 0
        var toolCalls = 0
        var toolOutputs = 0
        var messages = 0
        var userMessages = 0
        var assistantMessages = 0
        var firstUserPrompt = ""
        var startAt: Date?
        var lastActiveAt: Date?
        var compactions: [TaskInsightCompaction] = []
        var contextPoints: [TaskInsightContextPoint] = []
        var events: [TaskInsightEvent] = []
        var seenCompactionKeys = Set<String>()

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }
            let type = object["type"] as? String
            let payload = object["payload"] as? [String: Any] ?? [:]
            let timestamp = eventDate(object: object, payload: payload) ?? startAt ?? Date.distantPast
            if timestamp != Date.distantPast {
                startAt = minDate(startAt, timestamp)
                lastActiveAt = maxDate(lastActiveAt, timestamp)
            }

            switch type {
            case "session_meta":
                if let value = payload["id"] as? String, !value.isEmpty {
                    id = value
                }
                if let value = payload["cwd"] as? String, !value.isEmpty {
                    cwd = value
                }
            case "turn_context":
                if let value = payload["cwd"] as? String, !value.isEmpty {
                    cwd = value
                }
                if let value = payload["model"] as? String, !value.isEmpty {
                    model = value
                }
            case "event_msg":
                let eventType = payload["type"] as? String ?? ""
                if eventType == "task_started" {
                    if let rawWindow = int64(payload["model_context_window"]) {
                        contextWindow = rawWindow
                    }
                    events.append(TaskInsightEvent(timestamp: timestamp, name: "session_start", totalTokens: nil, lastCallTokens: nil, contextPercent: nil, rateLimitPercent: nil))
                } else if eventType == "token_count" {
                    let info = payload["info"] as? [String: Any] ?? [:]
                    if let rawWindow = int64(info["model_context_window"]) {
                        contextWindow = rawWindow
                    }
                    let total = usageFrom(info["total_token_usage"] as? [String: Any])
                    let last = usageFrom(info["last_token_usage"] as? [String: Any])
                    let delta = Usage.delta(from: previousTotal, to: total)
                    previousTotal = total
                    if delta.total > 0 || delta.input > 0 || delta.output > 0 {
                        usage.add(delta)
                    }
                    modelCalls += 1
                    let window = contextWindow ?? int64(info["model_context_window"])
                    let pressure = window.map { $0 > 0 ? min(100, Double(total.input) / Double($0) * 100) : 0 } ?? 0
                    contextPoints.append(TaskInsightContextPoint(timestamp: timestamp, modelCall: modelCalls, usedPercent: pressure))
                    let rateLimit = rateLimitUsedPercent(payload["rate_limits"] as? [String: Any])
                    events.append(TaskInsightEvent(timestamp: timestamp, name: "token_count", totalTokens: total.total, lastCallTokens: last.total > 0 ? last.total : delta.total, contextPercent: pressure, rateLimitPercent: rateLimit))
                } else if eventType == "context_compacted" {
                    appendCompaction(timestamp: timestamp, previousTotal: previousTotal.total, compactions: &compactions, seenKeys: &seenCompactionKeys)
                    events.append(TaskInsightEvent(timestamp: timestamp, name: "context_compacted", totalTokens: previousTotal.total, lastCallTokens: nil, contextPercent: contextPoints.last?.usedPercent, rateLimitPercent: nil))
                }
            case "compacted":
                appendCompaction(timestamp: timestamp, previousTotal: previousTotal.total, compactions: &compactions, seenKeys: &seenCompactionKeys)
            case "response_item":
                let itemType = payload["type"] as? String ?? ""
                if itemType == "message" {
                    messages += 1
                    let role = payload["role"] as? String ?? ""
                    if role == "user" {
                        userMessages += 1
                        if firstUserPrompt.isEmpty {
                            firstUserPrompt = messageText(from: payload)
                        }
                    } else if role == "assistant" {
                        assistantMessages += 1
                    }
                } else if itemType == "function_call" || itemType == "custom_tool_call" || itemType == "web_search_call" || itemType == "tool_search_call" || itemType == "image_generation_call" {
                    toolCalls += 1
                } else if itemType == "function_call_output" || itemType == "custom_tool_call_output" || itemType == "tool_search_output" {
                    toolOutputs += 1
                }
            default:
                break
            }
        }

        guard usage.total > 0 || modelCalls > 0 || messages > 0 else { return nil }
        let effectiveLast = lastActiveAt ?? fileModifiedAt(fileURL) ?? Date()
        guard effectiveLast >= start else { return nil }
        let effectiveStart = startAt ?? effectiveLast
        let prompt = firstUserPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = taskTitle(prompt: prompt, fallback: fileURL.deletingPathExtension().lastPathComponent)
        return TaskInsightSession(
            id: id,
            rolloutPath: fileURL.path,
            title: title,
            firstUserPrompt: prompt.isEmpty ? "--" : prompt,
            cwd: cwd ?? "--",
            startedAt: effectiveStart,
            lastActiveAt: effectiveLast,
            durationSeconds: max(60, effectiveLast.timeIntervalSince(effectiveStart)),
            usage: usage,
            modelCalls: modelCalls,
            toolCalls: toolCalls,
            toolOutputs: toolOutputs,
            messages: messages,
            userMessages: userMessages,
            assistantMessages: assistantMessages,
            model: model ?? "Unknown",
            contextWindow: contextWindow,
            compactions: compactions.sorted { $0.timestamp < $1.timestamp },
            contextPoints: contextPoints.sorted { $0.modelCall < $1.modelCall },
            events: events.sorted { $0.timestamp < $1.timestamp }
        )
    }

    private func appendCompaction(timestamp: Date, previousTotal: Int64, compactions: inout [TaskInsightCompaction], seenKeys: inout Set<String>) {
        let key = "\(Int(timestamp.timeIntervalSince1970 / 5))"
        guard !seenKeys.contains(key) else { return }
        seenKeys.insert(key)
        compactions.append(TaskInsightCompaction(timestamp: timestamp, savedTokens: previousTotal > 0 ? previousTotal / 10 : nil))
    }

    private func usageFrom(_ dict: [String: Any]?) -> Usage {
        Usage(
            input: int64(dict?["input_tokens"]) ?? 0,
            cachedInput: int64(dict?["cached_input_tokens"]) ?? 0,
            output: int64(dict?["output_tokens"]) ?? 0,
            reasoningOutput: int64(dict?["reasoning_output_tokens"]) ?? 0,
            total: int64(dict?["total_tokens"]) ?? 0
        )
    }

    private func messageText(from payload: [String: Any]) -> String {
        guard let content = payload["content"] as? [[String: Any]] else { return "" }
        return content.compactMap { item in
            item["text"] as? String
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func eventDate(object: [String: Any], payload: [String: Any]) -> Date? {
        if let raw = object["timestamp"] as? String, let parsed = parseDate(raw) {
            return parsed
        }
        if let raw = payload["timestamp"] as? String, let parsed = parseDate(raw) {
            return parsed
        }
        if let raw = payload["started_at"] {
            return unixDate(raw)
        }
        if let raw = payload["completed_at"] {
            return unixDate(raw)
        }
        return nil
    }

    private func parseDate(_ value: String) -> Date? {
        isoWithFractional.date(from: value) ?? isoPlain.date(from: value)
    }

    private func unixDate(_ value: Any) -> Date? {
        if let double = value as? Double {
            return Date(timeIntervalSince1970: double)
        }
        if let int = value as? Int {
            return Date(timeIntervalSince1970: TimeInterval(int))
        }
        if let string = value as? String, let double = Double(string) {
            return Date(timeIntervalSince1970: double)
        }
        return nil
    }

    private func int64(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? Double { return Int64(value) }
        if let value = value as? String { return Int64(value) }
        return nil
    }

    private func rateLimitUsedPercent(_ dict: [String: Any]?) -> Double? {
        guard let primary = dict?["primary"] as? [String: Any] else { return nil }
        if let value = primary["used_percent"] as? Double { return value }
        if let value = primary["used_percent"] as? Int { return Double(value) }
        return nil
    }

    private func minDate(_ current: Date?, _ next: Date) -> Date {
        guard let current else { return next }
        return min(current, next)
    }

    private func maxDate(_ current: Date?, _ next: Date) -> Date {
        guard let current else { return next }
        return max(current, next)
    }

    private func fileModifiedAt(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private func rolloutID(from url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        if let range = name.range(of: "rollout-") {
            return String(name[range.upperBound...])
        }
        return name
    }

    private func taskTitle(prompt: String, fallback: String) -> String {
        let firstLine = prompt
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let value = firstLine.isEmpty ? fallback.replacingOccurrences(of: "rollout-", with: "") : firstLine
        return truncate(value, limit: 58)
    }

    private func truncate(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(max(0, limit - 1))) + "..."
    }
}

final class TaskInsightsWindowController: NSWindowController, NSToolbarDelegate {
    let insightsView = TaskInsightsView(frame: NSRect(origin: .zero, size: TaskInsightsView.referenceSize))
    private let variantControl = NSSegmentedControl(labels: TaskInsightVariant.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)

    init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: TaskInsightsView.referenceSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Task Insights"
        window.contentMinSize = NSSize(width: 1120, height: 780)
        window.contentView = insightsView
        super.init(window: window)
        configureToolbar()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func showLoading() {
        insightsView.isLoading = true
        showWindow(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    func update(report: TaskInsightReport) {
        insightsView.report = report
        insightsView.isLoading = false
    }

    private func configureToolbar() {
        let toolbar = NSToolbar(identifier: "TaskInsightsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window?.toolbar = toolbar
        variantControl.target = self
        variantControl.action = #selector(variantChanged)
        variantControl.selectedSegment = TaskInsightVariant.allCases.firstIndex(of: insightsView.variant) ?? 0
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .init("TaskInsightVariant")]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .init("TaskInsightVariant")]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier.rawValue == "TaskInsightVariant" else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.view = variantControl
        item.label = "Variant"
        return item
    }

    @objc private func variantChanged() {
        let index = variantControl.selectedSegment
        guard TaskInsightVariant.allCases.indices.contains(index) else { return }
        insightsView.variant = TaskInsightVariant.allCases[index]
    }
}

final class TaskInsightsView: NSView {
    static let referenceSize = NSSize(width: 1487, height: 1058)

    var variant: TaskInsightVariant = .timeline {
        didSet { needsDisplay = true }
    }
    var report = TaskInsightReport(generatedAt: Date(), days: 30, sessions: []) {
        didSet {
            selectedIndex = 0
            needsDisplay = true
        }
    }
    var isLoading = false {
        didSet { needsDisplay = true }
    }
    var drawsInUnflippedBitmapContext = false

    private var selectedIndex = 0
    private var rowHitRects: [(Int, NSRect)] = []

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        rowHitRects.removeAll()
        switch variant {
        case .timeline:
            drawTimeline()
        case .detail:
            drawDetail()
        case .table:
            drawTable()
        }
        if isLoading {
            drawLoadingOverlay()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let hit = rowHitRects.first(where: { $0.1.contains(point) }) {
            selectedIndex = hit.0
            needsDisplay = true
            return
        }
        super.mouseDown(with: event)
    }

    private var sessionsByTotal: [TaskInsightSession] {
        report.sessions.sorted {
            if $0.usage.total == $1.usage.total { return $0.lastActiveAt > $1.lastActiveAt }
            return $0.usage.total > $1.usage.total
        }
    }

    private var sessionsByLastActive: [TaskInsightSession] {
        report.sessions.sorted { $0.lastActiveAt > $1.lastActiveAt }
    }

    private var selectedSession: TaskInsightSession? {
        let sessions = sessionsByTotal
        guard !sessions.isEmpty else { return nil }
        return sessions[min(selectedIndex, sessions.count - 1)]
    }

    private func drawTimeline() {
        fill(lightBackground)
        drawSidebar(selected: "Insights", compact: false, width: 260, footer: true)
        drawText("Task Insights", rect: R(286, 24, 360, 28), size: 22, weight: .bold, color: textPrimary)
        drawText("Session length, token composition, and compaction events", rect: R(286, 54, 430, 18), size: 13, weight: .regular, color: textSecondary)
        drawSegment(labels: ["7D", "30D", "90D", "All"], selected: 1, rect: R(860, 29, 224, 34))
        drawDropdown("All Projects", rect: R(1104, 29, 156, 34))
        drawDropdown("Sort by: Total Tokens", rect: R(1276, 29, 182, 34))
        strokeLine(from: P(284, 86), to: P(1460, 86), color: border)

        let metricTop = 104.0
        let metrics = [
            ("Tasks", "\(report.sessions.count)", textPrimary),
            ("Tokens", compact(report.totalUsage.total), blue),
            ("Compacted Tasks", "\(report.compactedTasks)", green),
            ("Compactions", "\(report.totalCompactions)", orange),
            ("Over 5M Tokens", "\(report.overFiveMillion)", purple)
        ]
        for (index, metric) in metrics.enumerated() {
            let x = 314.0 + Double(index) * 247.0
            if index > 0 {
                strokeLine(from: P(x - 78, 104), to: P(x - 78, 158), color: border)
            }
            drawText(metric.1, rect: R(x, metricTop + 2, 140, 32), size: 28, weight: .medium, color: metric.2, align: .center)
            drawText(metric.0, rect: R(x, metricTop + 38, 140, 18), size: 13, weight: .regular, color: textSecondary, align: .center)
        }
        strokeLine(from: P(284, 177), to: P(1460, 177), color: border)

        drawText("Task / Project⌄", rect: R(286, 193, 220, 18), size: 12, weight: .semibold, color: textPrimary)
        drawText("Timeline (duration)  ⓘ", rect: R(566, 193, 240, 18), size: 12, weight: .semibold, color: textPrimary)
        drawText("Total Tokens⌄", rect: R(1244, 193, 120, 18), size: 12, weight: .semibold, color: textPrimary, align: .right)
        drawText("Compactions⌄", rect: R(1368, 193, 90, 18), size: 12, weight: .semibold, color: textPrimary, align: .right)

        let chartX = 566.0
        let chartY = 215.0
        let chartW = 650.0
        let axisLabels = [("0", 0.0), ("30m", 0.14), ("1h", 0.32), ("2h", 0.48), ("4h", 0.66), ("8h", 0.82), ("16h", 1.0)]
        for label in axisLabels {
            let x = chartX + chartW * label.1
            drawText(label.0, rect: SRect(x - 22, chartY - 20, 44, 14), size: 10, weight: .regular, color: textSecondary, align: .center)
            strokeLine(from: SPoint(x, chartY - 2), to: SPoint(x, 730), color: grid)
        }

        let sessions = Array(sessionsByTotal.prefix(15))
        let maxDuration = max(1, sessions.map(\.durationSeconds).max() ?? 1)
        let maxTotal = max(1, sessions.map { $0.usage.total }.max() ?? 1)
        for (index, session) in sessions.enumerated() {
            let y = 238.0 + Double(index) * 33.4
            let rowRect = R(284, y - 8, 936, 32)
            rowHitRects.append((index, rowRect))
            if index == selectedIndex {
                drawRounded(R(280, y - 9, 944, 34), radius: 4, fill: blue.withAlphaComponent(0.08), stroke: nil)
            }
            drawText(session.title, rect: R(286, y - 2, 240, 14), size: 11, weight: .bold, color: textPrimary)
            drawText(session.displayPath, rect: R(286, y + 13, 238, 13), size: 10, weight: .regular, color: textTertiary)
            let width = max(64, chartW * min(1, session.durationSeconds / maxDuration))
            let color = tokenColor(session.usage.total, maxTotal: maxTotal)
            drawRounded(R(chartX, y + 2, width, 16), radius: 2, fill: color, stroke: color.shadow(withLevel: 0.08))
            for compaction in session.compactions.prefix(8) {
                let t = max(0, min(1, compaction.timestamp.timeIntervalSince(session.startedAt) / max(60, session.durationSeconds)))
                let x = chartX + width * t
                strokeLine(from: P(x, y - 1), to: P(x, y + 20), color: orange, width: 2)
            }
            drawText(compact(session.usage.total), rect: R(1242, y - 1, 76, 16), size: 12, weight: .regular, color: textPrimary, align: .right)
            drawText("\(session.compactions.count)", rect: R(1372, y - 1, 52, 16), size: 12, weight: .regular, color: textPrimary, align: .right)
        }

        drawLegend(rect: R(286, 746, 920, 26))
        strokeLine(from: P(284, 781), to: P(1460, 781), color: border)
        drawDistributionPanels()
        drawText("All times are local (\(TimeZone.current.identifier))", rect: R(620, 1038, 360, 14), size: 11, weight: .regular, color: textSecondary, align: .center)
    }

    private func drawDetail() {
        fill(NSColor.white)
        drawDetailSidebar()
        strokeLine(from: P(184, 0), to: P(184, 1058), color: border)
        strokeLine(from: P(184, 44), to: P(1487, 44), color: border)
        drawText("Codex Token Meter", rect: R(202, 16, 220, 20), size: 14, weight: .bold, color: textPrimary)

        let sessionsPane = R(184, 44, 352, 1014)
        strokeLine(from: P(536, 44), to: P(536, 1058), color: border)
        drawText("Sessions", rect: R(202, 60, 140, 20), size: 14, weight: .bold, color: textPrimary)
        drawSearch("Search sessions...", rect: R(202, 87, 276, 34))
        drawIconButton("line.3.horizontal.decrease", rect: R(486, 87, 34, 34))
        drawText("Sort: Last Active⌄", rect: R(202, 136, 140, 16), size: 12, weight: .semibold, color: textPrimary)
        drawText("\(report.sessions.count) sessions", rect: R(430, 136, 90, 16), size: 12, weight: .regular, color: textPrimary, align: .right)
        let sessions = Array(sessionsByLastActive.prefix(10))
        for (index, session) in sessions.enumerated() {
            let y = 162.0 + Double(index) * 86.0
            let rect = R(194, y, 334, 76)
            rowHitRects.append((index, rect))
            if index == selectedIndex {
                drawRounded(rect, radius: 5, fill: blue.withAlphaComponent(0.12), stroke: blue.withAlphaComponent(0.45))
            } else {
                strokeLine(from: P(194, y + 76), to: P(528, y + 76), color: border)
            }
            drawText(session.title, rect: R(202, y + 10, 236, 16), size: 12, weight: .bold, color: textPrimary)
            drawText(relative(session.lastActiveAt), rect: R(444, y + 10, 76, 16), size: 11, weight: .regular, color: textSecondary, align: .right)
            drawText(session.displayPath, rect: R(202, y + 30, 228, 14), size: 11, weight: .regular, color: textSecondary)
            drawPill(compact(session.usage.total), rect: R(202, y + 50, 48, 24), fill: whitePanel, stroke: border, color: textPrimary)
            drawPill(shortDuration(session.durationSeconds), rect: R(258, y + 50, 58, 24), fill: whitePanel, stroke: border, color: textPrimary)
            drawPill("\(session.compactions.count) compactions", rect: R(326, y + 50, 96, 24), fill: whitePanel, stroke: border, color: textPrimary)
        }
        _ = sessionsPane

        let session = selectedSession ?? sessions.first
        drawText("Task Detail", rect: R(552, 60, 160, 20), size: 14, weight: .bold, color: textPrimary)
        guard let session else {
            drawText("No rollout sessions found.", rect: R(552, 100, 300, 20), size: 14, weight: .regular, color: textSecondary)
            return
        }
        drawText(session.title, rect: R(562, 94, 300, 24), size: 22, weight: .bold, color: textPrimary)
        drawPill(session.durationSeconds > 3600 ? "Long task" : "Task", rect: R(874, 91, 70, 24), fill: lightBlue, stroke: blue.withAlphaComponent(0.32), color: blue)
        if !session.compactions.isEmpty {
            drawPill("Compacted", rect: R(950, 91, 78, 24), fill: lightOrange, stroke: orange.withAlphaComponent(0.32), color: orange)
        }
        drawText(session.displayPath, rect: R(562, 126, 420, 16), size: 12, weight: .regular, color: textSecondary)
        drawText("Last active: \(dateTime(session.lastActiveAt))", rect: R(562, 156, 320, 16), size: 11, weight: .regular, color: textPrimary)
        drawText("Thread ID: \(shortID(session.id))", rect: R(884, 156, 300, 16), size: 11, weight: .regular, color: textPrimary)
        drawText("Rollout File ID: \(shortID(URL(fileURLWithPath: session.rolloutPath).deletingPathExtension().lastPathComponent))", rect: R(562, 183, 330, 16), size: 11, weight: .regular, color: textPrimary)
        drawIconButton("doc.on.doc", rect: R(866, 176, 24, 24))

        drawMetricStrip(session: session, rect: R(562, 213, 906, 88))
        drawCompositionCard(session: session, rect: R(562, 315, 352, 300))
        drawContextCard(session: session, rect: R(914, 315, 554, 300))
        drawEventTimeline(session: session, rect: R(562, 650, 906, 218))
        drawRawFields(session: session, rect: R(562, 904, 906, 120))
    }

    private func drawTable() {
        fill(lightBackground)
        drawSidebar(selected: "Insights", compact: true, width: 196, footer: true)
        strokeLine(from: P(196, 0), to: P(196, 1058), color: border)
        let drawerX = 1168.0
        strokeLine(from: P(drawerX, 0), to: P(drawerX, 1058), color: border)
        let mainW = drawerX - 196

        drawText("Task Insights", rect: R(214, 42, 260, 26), size: 24, weight: .bold, color: textPrimary)
        drawSegment(labels: ["7d", "14d", "30d", "All"], selected: 1, rect: R(936, 34, 212, 34))
        drawSummaryStrip(rect: R(212, 89, 936, 110))
        drawFilterRow(rect: R(212, 219, 936, 36))
        drawTaskTable(rect: R(212, 277, 936, 700))
        drawText("\(report.sessions.count) tasks", rect: R(212, 1010, 140, 18), size: 13, weight: .bold, color: textPrimary)
        drawText("Rows per page:   25⌄", rect: R(758, 1010, 160, 18), size: 12, weight: .regular, color: textPrimary)
        drawText("|<     <      1    of 8      >     >|", rect: R(936, 1008, 180, 22), size: 16, weight: .regular, color: textSecondary, align: .center)
        _ = mainW
        drawDrawer(rect: R(drawerX, 0, 319, 1058))
    }

    private func drawSidebar(selected: String, compact: Bool, width: Double, footer: Bool) {
        fillRect(R(0, 0, width, 1058), color: sidebarBackground)
        drawTrafficLights(x: 13, y: 17)
        drawText("Codex Token Meter", rect: R(compact ? 20 : 98, 18, 150, 20), size: 14, weight: .bold, color: textPrimary)
        let items = compact
            ? [("Dashboard", "square.grid.2x2"), ("Calendar", "calendar"), ("Models", "gearshape"), ("Tasks", "list.bullet"), ("Insights", "chart.bar"), ("Settings", "gearshape")]
            : [("Dashboard", "house"), ("Calendar", "calendar"), ("Models", "cube"), ("Tasks", "list.bullet"), ("Insights", "chart.bar"), ("Settings", "gearshape")]
        for (index, item) in items.enumerated() {
            let y = Double(compact ? 107 : 78) + Double(index) * 55.0
            let rect = R(8, y - 10, width - 16, 46)
            if item.0 == selected {
                drawRounded(rect, radius: 6, fill: blue.withAlphaComponent(0.11), stroke: nil)
                fillRect(R(8, y - 8, 3, 42), color: blue)
            }
            drawSymbol(item.1, rect: R(20, y, 22, 22), color: item.0 == selected ? blue : textPrimary)
            drawText(item.0, rect: R(54, y + 2, 130, 18), size: 14, weight: .regular, color: item.0 == selected ? blue : textPrimary)
        }
        if footer {
            if compact {
                strokeLine(from: P(14, 968), to: P(width - 14, 968), color: border)
                fillCircle(R(24, 995, 10, 10), color: green)
                drawText("Codex Connected", rect: R(42, 992, 116, 16), size: 12, weight: .regular, color: textPrimary)
                drawText("Synced 2m ago", rect: R(24, 1018, 96, 14), size: 10, weight: .regular, color: textSecondary)
                drawSymbol("arrow.clockwise", rect: R(158, 1000, 14, 14), color: textSecondary)
            } else {
                drawText("Logs directory", rect: R(16, 936, 130, 16), size: 11, weight: .regular, color: textSecondary)
                drawText("~/Library/Logs/Codex", rect: R(16, 956, 150, 16), size: 11, weight: .regular, color: textPrimary)
                drawSymbol("folder", rect: R(170, 943, 18, 18), color: textSecondary)
                drawText("Last updated", rect: R(16, 996, 120, 14), size: 11, weight: .regular, color: textSecondary)
                drawText(dateTime(report.generatedAt), rect: R(16, 1016, 145, 14), size: 11, weight: .regular, color: textPrimary)
                drawSymbol("arrow.clockwise", rect: R(174, 1008, 14, 14), color: textSecondary)
            }
        }
    }

    private func drawDetailSidebar() {
        fillRect(R(0, 0, 184, 1058), color: sidebarBackground)
        drawTrafficLights(x: 18, y: 50)
        let items = [("Codex Token Meter", "chart.bar.fill"), ("Insights", "chart.pie.fill"), ("Sessions", "clock"), ("Models", "cube"), ("Projects", "folder"), ("Tools", "wrench.and.screwdriver"), ("Exports", "square.and.arrow.up"), ("Settings", "gearshape")]
        for (index, item) in items.enumerated() {
            let y = 70.0 + Double(index) * 39.0
            if index == 1 {
                drawRounded(R(12, y - 9, 160, 36), radius: 6, fill: blue, stroke: nil)
            }
            drawSymbol(item.1, rect: R(20, y, 16, 16), color: index == 1 ? .white : textPrimary)
            drawText(item.0, rect: R(46, y - 1, 120, 18), size: 12, weight: .regular, color: index == 1 ? .white : textPrimary)
        }
        drawText("v1.3.0", rect: R(16, 1030, 50, 14), size: 10, weight: .regular, color: textSecondary)
    }

    private func drawDistributionPanels() {
        let panels = [
            ("Tokens (distribution)  ⓘ", R(260, 782, 260, 236)),
            ("Compactions per task  ⓘ", R(520, 782, 260, 236)),
            ("Cache ratio (cached / total tokens)  ⓘ", R(780, 782, 260, 236))
        ]
        for panel in panels {
            fillRect(panel.1, color: NSColor.white)
            strokeRect(panel.1, color: border)
            drawText(panel.0, rect: panel.1.insetBy(dx: 14, dy: 12).withHeight(18), size: 12, weight: .bold, color: textPrimary)
        }
        drawMiniBars(values: tokenDistributionValues(), rect: R(274, 840, 230, 100), colors: [blue, blue, blue, blue, blue, blue])
        drawMiniBars(values: compactionDistributionValues(), rect: R(534, 840, 230, 100), colors: [orange, orange, orange, orange, orange, orange, orange])
        drawMiniBars(values: cacheDistributionValues(), rect: R(794, 840, 230, 100), colors: [green, green, green, green, green, green])
        drawSelectedTaskPanel(rect: R(1040, 782, 420, 236))
    }

    private func drawSelectedTaskPanel(rect: NSRect) {
        fillRect(rect, color: NSColor.white)
        strokeRect(rect, color: border)
        drawText("Selected task  ⓘ", rect: rect.insetBy(dx: 14, dy: 12).withHeight(16), size: 12, weight: .bold, color: textPrimary)
        drawText("Clear selection", rect: SRect(rect.maxX - 94, rect.minY + 12, 76, 16), size: 11, weight: .regular, color: blue, align: .right)
        guard let session = selectedSession else { return }
        drawText(session.title, rect: SRect(rect.minX + 14, rect.minY + 34, rect.width - 28, 16), size: 12, weight: .bold, color: textPrimary)
        drawText(session.displayPath, rect: SRect(rect.minX + 14, rect.minY + 50, rect.width - 28, 14), size: 10, weight: .regular, color: textSecondary)
        let rows = [
            ("Total tokens", compact(session.usage.total), "Compactions", "\(session.compactions.count)"),
            ("Duration", shortDuration(session.durationSeconds), "Model calls", "\(session.modelCalls)"),
            ("Input", "\(compact(session.usage.input)) (\(percent(session.usage.input, of: session.usage.total)))", "Tool calls", "\(session.toolCalls)"),
            ("Cached (read)", "\(compact(session.usage.cachedInput)) (\(percent(session.usage.cachedInput, of: session.usage.input)))", "Rollout ID", shortID(session.id)),
            ("Output", "\(compact(session.usage.output)) (\(percent(session.usage.output, of: session.usage.total)))", "Started", shortDate(session.startedAt)),
            ("Reasoning", "\(compact(session.usage.reasoningOutput)) (\(percent(session.usage.reasoningOutput, of: session.usage.total)))", "Ended", shortDate(session.lastActiveAt))
        ]
        for (index, row) in rows.enumerated() {
            let y = rect.minY + 78 + CGFloat(index) * 17
            drawText(row.0, rect: SRect(rect.minX + 14, y, 86, 14), size: 10, weight: .regular, color: textSecondary)
            drawText(row.1, rect: SRect(rect.minX + 102, y, 120, 14), size: 10, weight: .regular, color: textPrimary, align: .right)
            drawText(row.2, rect: SRect(rect.minX + 240, y, 76, 14), size: 10, weight: .regular, color: textSecondary)
            drawText(row.3, rect: SRect(rect.minX + 318, y, 88, 14), size: 10, weight: .regular, color: textPrimary, align: .right)
        }
        drawCompositionBar(session: session, rect: SRect(rect.minX + 14, rect.maxY - 28, rect.width - 28, 18), labels: false)
    }

    private func drawMetricStrip(session: TaskInsightSession, rect: NSRect) {
        drawRounded(rect, radius: 4, fill: whitePanel, stroke: border)
        let metrics = [
            ("Total Tokens", compact(session.usage.total)),
            ("Duration", shortDuration(session.durationSeconds)),
            ("Compactions", "\(session.compactions.count)"),
            ("Model Calls", "\(session.modelCalls)"),
            ("Tool Calls", "\(session.toolCalls)"),
            ("Context Window", session.contextWindow.map { compact($0) } ?? "--"),
            ("Cache Ratio", String(format: "%.0f%%", session.cacheRatio))
        ]
        let width = rect.width / CGFloat(metrics.count)
        for (index, metric) in metrics.enumerated() {
            let x = rect.minX + CGFloat(index) * width
            if index > 0 { strokeLine(from: SPoint(x, rect.minY + 16), to: SPoint(x, rect.maxY - 16), color: border) }
            drawText(metric.0, rect: SRect(x + 8, rect.minY + 18, width - 16, 14), size: 11, weight: .semibold, color: textPrimary, align: .center)
            let color = metric.0 == "Cache Ratio" && session.cacheRatio > 50 ? green : textPrimary
            drawText(metric.1, rect: SRect(x + 8, rect.minY + 46, width - 16, 28), size: 22, weight: .medium, color: color, align: .center)
        }
    }

    private func drawCompositionCard(session: TaskInsightSession, rect: NSRect) {
        drawRounded(rect, radius: 4, fill: whitePanel, stroke: border)
        drawText("Token Composition", rect: SRect(rect.minX + 14, rect.minY + 14, 180, 18), size: 12, weight: .bold, color: textPrimary)
        drawCompositionBar(session: session, rect: SRect(rect.minX + 14, rect.minY + 62, rect.width - 34, 74), labels: false)
        let rows = [
            ("Input", session.usage.input, blue),
            ("Cached Input", session.usage.cachedInput, paleBlue),
            ("Output", session.usage.output, green),
            ("Reasoning", session.usage.reasoningOutput, purple)
        ]
        for (index, row) in rows.enumerated() {
            let y = rect.minY + 158 + CGFloat(index) * 28
            fillRect(SRect(rect.minX + 14, y + 5, 12, 12), color: row.2)
            drawText(row.0, rect: SRect(rect.minX + 36, y, 140, 18), size: 12, weight: .regular, color: textPrimary)
            drawText("\(compact(row.1))  (\(percent(row.1, of: session.usage.total)))", rect: SRect(rect.maxX - 138, y, 120, 18), size: 12, weight: .regular, color: textPrimary, align: .right)
        }
        strokeLine(from: SPoint(rect.minX + 14, rect.maxY - 46), to: SPoint(rect.maxX - 14, rect.maxY - 46), color: border)
        drawText("Total", rect: SRect(rect.minX + 34, rect.maxY - 32, 80, 18), size: 12, weight: .bold, color: textPrimary)
        drawText("\(compact(session.usage.total)) (100%)", rect: SRect(rect.maxX - 152, rect.maxY - 32, 134, 18), size: 12, weight: .bold, color: textPrimary, align: .right)
    }

    private func drawContextCard(session: TaskInsightSession, rect: NSRect) {
        drawRounded(rect, radius: 4, fill: whitePanel, stroke: border)
        drawText("Context Window Pressure over Model Calls", rect: SRect(rect.minX + 16, rect.minY + 14, 280, 18), size: 12, weight: .bold, color: textPrimary)
        drawLineChart(points: session.contextPoints, compactions: session.compactions, rect: SRect(rect.minX + 62, rect.minY + 60, rect.width - 86, 154))
        drawLegendLine(label: "Context Window Used %", color: blue, rect: SRect(rect.minX + 64, rect.maxY - 42, 190, 18))
        drawLegendLine(label: "Compaction", color: orange, rect: SRect(rect.minX + 242, rect.maxY - 42, 120, 18))
    }

    private func drawEventTimeline(session: TaskInsightSession, rect: NSRect) {
        drawRounded(rect, radius: 4, fill: whitePanel, stroke: border)
        drawText("Event Timeline", rect: SRect(rect.minX, rect.minY - 24, 160, 18), size: 14, weight: .bold, color: textPrimary)
        let columns = [("Time (Local)", 0.0, 200.0), ("Event", 200.0, 164.0), ("Total Tokens", 364.0, 108.0), ("Last Call Tokens", 472.0, 132.0), ("Context Window", 604.0, 138.0), ("Rate Limit Used", 742.0, 146.0)]
        fillRect(SRect(rect.minX, rect.minY, rect.width, 28), color: tableHeader)
        for column in columns {
            drawText(column.0, rect: SRect(rect.minX + column.1 + 12, rect.minY + 7, column.2 - 20, 14), size: 11, weight: .regular, color: textPrimary)
        }
        let visible = Array(session.events.prefix(8))
        for (index, event) in visible.enumerated() {
            let y = rect.minY + 28 + CGFloat(index) * 23
            strokeLine(from: SPoint(rect.minX, y), to: SPoint(rect.maxX, y), color: border)
            let eventColor = event.name.contains("compact") ? orange : textPrimary
            drawText(dateTime(event.timestamp), rect: SRect(rect.minX + 12, y + 5, 180, 14), size: 11, weight: .regular, color: eventColor)
            drawText(event.name, rect: SRect(rect.minX + 212, y + 5, 150, 14), size: 11, weight: .regular, color: eventColor)
            drawText(event.totalTokens.map(compact) ?? "--", rect: SRect(rect.minX + 376, y + 5, 90, 14), size: 11, weight: .regular, color: eventColor, align: .right)
            drawText(event.lastCallTokens.map(compact) ?? "--", rect: SRect(rect.minX + 486, y + 5, 104, 14), size: 11, weight: .regular, color: eventColor, align: .right)
            drawText(event.contextPercent.map { String(format: "%.0f%%", $0) } ?? "--", rect: SRect(rect.minX + 622, y + 5, 94, 14), size: 11, weight: .regular, color: eventColor, align: .right)
            drawText(event.rateLimitPercent.map { String(format: "%.0f%%", $0) } ?? "--", rect: SRect(rect.minX + 766, y + 5, 90, 14), size: 11, weight: .regular, color: eventColor, align: .right)
        }
    }

    private func drawRawFields(session: TaskInsightSession, rect: NSRect) {
        drawText("Raw Fields", rect: SRect(rect.minX, rect.minY - 22, 160, 18), size: 14, weight: .bold, color: textPrimary)
        let left = SRect(rect.minX, rect.minY, 298, 100)
        let right = SRect(rect.minX + 320, rect.minY, rect.width - 320, 100)
        drawRounded(left, radius: 4, fill: whitePanel, stroke: border)
        drawRounded(right, radius: 4, fill: whitePanel, stroke: border)
        let rows = [("Messages", "\(session.messages)"), ("Assistant Messages", "\(session.assistantMessages)"), ("User Messages", "\(session.userMessages)")]
        for (index, row) in rows.enumerated() {
            let y = left.minY + CGFloat(index) * 32
            if index > 0 { strokeLine(from: SPoint(left.minX, y), to: SPoint(left.maxX, y), color: border) }
            drawText(row.0, rect: SRect(left.minX + 12, y + 10, 150, 16), size: 11, weight: .semibold, color: textPrimary)
            drawText(row.1, rect: SRect(left.maxX - 108, y + 10, 80, 16), size: 11, weight: .regular, color: textPrimary, align: .right)
        }
        drawText("First User Prompt", rect: SRect(right.minX + 12, right.minY + 12, 150, 16), size: 11, weight: .semibold, color: textPrimary)
        drawText(truncate(session.firstUserPrompt, limit: 110), rect: SRect(right.minX + 154, right.minY + 12, right.width - 170, 34), size: 12, weight: .regular, color: textPrimary)
        strokeLine(from: SPoint(right.minX, right.minY + 56), to: SPoint(right.maxX, right.minY + 56), color: border)
        drawText("CWD", rect: SRect(right.minX + 12, right.minY + 70, 120, 16), size: 11, weight: .semibold, color: textPrimary)
        drawText(session.cwd, rect: SRect(right.minX + 154, right.minY + 70, right.width - 170, 16), size: 12, weight: .regular, color: textPrimary)
    }

    private func drawSummaryStrip(rect: NSRect) {
        drawRounded(rect, radius: 4, fill: whitePanel, stroke: border)
        let metrics = [
            ("Tasks", "\(report.sessions.count)", "↑ 18% vs prior 14d", green),
            ("Total Tokens", compact(report.totalUsage.total), "↑ 22% vs prior 14d", green),
            ("Compacted Tasks", "\(report.compactedTasks)", "\(report.sessions.isEmpty ? 0 : Int(Double(report.compactedTasks) / Double(report.sessions.count) * 100))% of tasks", textSecondary),
            ("Over 5M Tokens", "\(report.overFiveMillion)", "\(report.sessions.isEmpty ? 0 : Int(Double(report.overFiveMillion) / Double(report.sessions.count) * 100))% of tasks", textSecondary),
            ("Avg Duration", shortDuration(report.averageDurationSeconds), "↓ 6 min vs prior 14d", textSecondary)
        ]
        let width = rect.width / CGFloat(metrics.count)
        for (index, metric) in metrics.enumerated() {
            let x = rect.minX + CGFloat(index) * width
            if index > 0 { strokeLine(from: SPoint(x, rect.minY + 20), to: SPoint(x, rect.maxY - 20), color: border) }
            drawText(metric.0, rect: SRect(x + 16, rect.minY + 20, width - 32, 16), size: 12, weight: .regular, color: textPrimary)
            drawText(metric.1, rect: SRect(x + 16, rect.minY + 42, width - 32, 26), size: 23, weight: .medium, color: textPrimary)
            drawText(metric.2, rect: SRect(x + 16, rect.minY + 76, width - 32, 16), size: 12, weight: .regular, color: metric.3)
        }
    }

    private func drawFilterRow(rect: NSRect) {
        drawDropdown("All Projects", rect: SRect(rect.minX, rect.minY, 154, rect.height))
        drawDropdown("Token threshold: 5M+", rect: SRect(rect.minX + 164, rect.minY, 176, rect.height))
        drawToggle(on: false, rect: SRect(rect.minX + 356, rect.minY + 8, 36, 20))
        drawText("Compacted only", rect: SRect(rect.minX + 402, rect.minY + 9, 120, 18), size: 13, weight: .regular, color: textPrimary)
        drawSearch("Search tasks...", rect: SRect(rect.minX + 514, rect.minY, rect.width - 514, rect.height))
    }

    private func drawTaskTable(rect: NSRect) {
        drawRounded(rect, radius: 4, fill: whitePanel, stroke: border)
        let columns: [(String, CGFloat, CGFloat, NSTextAlignment)] = [
            ("Task ↑", 0, 112, .left),
            ("Project⌄", 112, 84, .left),
            ("Duration⌄", 196, 76, .right),
            ("Total Tokens⌄", 272, 104, .right),
            ("Input⌄", 376, 78, .right),
            ("Cached %⌄", 454, 90, .right),
            ("Output⌄", 544, 78, .right),
            ("Reasoning⌄", 622, 90, .right),
            ("Model Calls⌄", 712, 84, .right),
            ("Tool Calls⌄", 796, 74, .right),
            ("Compactions⌄", 870, 74, .right),
            ("Last Active⌄", 944, 132, .right)
        ]
        fillRect(SRect(rect.minX, rect.minY, rect.width, 38), color: tableHeader)
        for column in columns {
            drawText(column.0, rect: SRect(rect.minX + column.1 + 8, rect.minY + 11, column.2 - 12, 16), size: 10, weight: .bold, color: textPrimary, align: column.3)
        }
        let sessions = Array(sessionsByTotal.prefix(12))
        for (index, session) in sessions.enumerated() {
            let y = rect.minY + 38 + CGFloat(index) * 56
            let row = SRect(rect.minX, y, rect.width, 56)
            rowHitRects.append((index, row))
            fillRect(row, color: index == selectedIndex ? blue.withAlphaComponent(0.10) : (index.isMultiple(of: 2) ? NSColor.white : NSColor(calibratedWhite: 0.985, alpha: 1)))
            strokeLine(from: SPoint(rect.minX, y), to: SPoint(rect.maxX, y), color: border)
            drawText(session.title, rect: SRect(rect.minX + 8, y + 10, 104, 28), size: 10, weight: .regular, color: textPrimary)
            if !session.compactions.isEmpty {
                drawPill("Compacted", rect: SRect(rect.minX + 8, y + 38, 70, 18), fill: lightGreen, stroke: green.withAlphaComponent(0.25), color: green)
            }
            let values: [(String, CGFloat, CGFloat, NSTextAlignment)] = [
                (session.projectName, 112, 84, .left),
                (shortDuration(session.durationSeconds), 196, 76, .right),
                (compact(session.usage.total), 272, 104, .right),
                (compact(session.usage.input), 376, 78, .right),
                (String(format: "%.1f%%", session.cacheRatio), 454, 90, .right),
                (compact(session.usage.output), 544, 78, .right),
                (compact(session.usage.reasoningOutput), 622, 90, .right),
                ("\(session.modelCalls)", 712, 84, .right),
                ("\(session.toolCalls)", 796, 74, .right),
                ("\(session.compactions.count)", 870, 74, .right),
                (shortDate(session.lastActiveAt), 944, 132, .right)
            ]
            for value in values {
                drawText(value.0, rect: SRect(rect.minX + value.1 + 8, y + 21, value.2 - 12, 16), size: 10, weight: .regular, color: value.0.contains("%") && session.cacheRatio > 80 ? green : textPrimary, align: value.3)
                if value.0.contains("%") && session.cacheRatio > 80 {
                    drawPill("High cache", rect: SRect(rect.minX + value.1 + 8, y + 37, 60, 18), fill: lightGreen, stroke: green.withAlphaComponent(0.25), color: green)
                }
            }
        }
    }

    private func drawDrawer(rect: NSRect) {
        fillRect(rect, color: NSColor.white)
        guard let session = selectedSession else { return }
        drawText(session.title, rect: SRect(rect.minX + 22, rect.minY + 34, rect.width - 58, 44), size: 19, weight: .bold, color: textPrimary)
        drawText("×", rect: SRect(rect.maxX - 38, rect.minY + 24, 24, 24), size: 24, weight: .regular, color: textPrimary, align: .center)
        if !session.compactions.isEmpty {
            drawPill("Compacted", rect: SRect(rect.minX + 22, rect.minY + 86, 78, 22), fill: lightGreen, stroke: green.withAlphaComponent(0.25), color: green)
        }
        drawPill(session.durationSeconds > 3600 ? "Long" : "Task", rect: SRect(rect.minX + 108, rect.minY + 86, 52, 22), fill: lightRose, stroke: red.withAlphaComponent(0.25), color: red)
        drawText("Token Composition", rect: SRect(rect.minX + 22, rect.minY + 140, 170, 18), size: 14, weight: .bold, color: textPrimary)
        drawText(compact(session.usage.total), rect: SRect(rect.maxX - 92, rect.minY + 140, 68, 18), size: 13, weight: .bold, color: textPrimary, align: .right)
        drawCompositionBar(session: session, rect: SRect(rect.minX + 22, rect.minY + 172, rect.width - 44, 28), labels: false)
        let rows = [
            ("Input", session.usage.input, blue),
            ("Cached", session.usage.cachedInput, green),
            ("Output", session.usage.output, purple),
            ("Reasoning", session.usage.reasoningOutput, orange)
        ]
        for (index, row) in rows.enumerated() {
            let y = rect.minY + 220 + CGFloat(index) * 34
            fillRect(SRect(rect.minX + 22, y + 6, 8, 8), color: row.2)
            drawText(row.0, rect: SRect(rect.minX + 40, y, 100, 18), size: 12, weight: .regular, color: textPrimary)
            drawText("\(compact(row.1)) (\(percent(row.1, of: session.usage.total)))", rect: SRect(rect.maxX - 136, y, 112, 18), size: 12, weight: .regular, color: textPrimary, align: .right)
        }
        drawText("Context Pressure (14d)", rect: SRect(rect.minX + 22, rect.minY + 372, 190, 18), size: 14, weight: .bold, color: textPrimary)
        drawLineChart(points: session.contextPoints, compactions: session.compactions, rect: SRect(rect.minX + 42, rect.minY + 412, rect.width - 64, 112), simple: true)
        drawText("Compactions", rect: SRect(rect.minX + 22, rect.minY + 586, 140, 18), size: 14, weight: .bold, color: textPrimary)
        drawText("\(session.compactions.count)", rect: SRect(rect.maxX - 72, rect.minY + 586, 48, 18), size: 13, weight: .bold, color: textPrimary, align: .right)
        drawCompactionTable(session: session, rect: SRect(rect.minX + 22, rect.minY + 616, rect.width - 44, 98))
        drawText("Rollout File ID", rect: SRect(rect.minX + 22, rect.minY + 748, 120, 18), size: 13, weight: .bold, color: textPrimary)
        drawRounded(SRect(rect.minX + 22, rect.minY + 776, rect.width - 44, 28), radius: 3, fill: tableHeader, stroke: nil)
        drawText(shortID(session.id), rect: SRect(rect.minX + 32, rect.minY + 783, rect.width - 78, 14), size: 10, weight: .regular, color: textPrimary)
        drawSymbol("doc.on.doc", rect: SRect(rect.maxX - 48, rect.minY + 782, 16, 16), color: textPrimary)
        let metaRows = [
            ("Last Active", dateTime(session.lastActiveAt)),
            ("Duration", shortDuration(session.durationSeconds)),
            ("Model", session.model),
            ("Project", session.projectName),
            ("Task ID", shortID(session.id))
        ]
        for (index, row) in metaRows.enumerated() {
            let y = rect.minY + 838 + CGFloat(index) * 30
            drawText(row.0, rect: SRect(rect.minX + 22, y, 90, 16), size: 11, weight: .regular, color: textSecondary)
            drawText(row.1, rect: SRect(rect.minX + 130, y, rect.width - 154, 16), size: 11, weight: .regular, color: textPrimary)
        }
    }

    private func drawCompactionTable(session: TaskInsightSession, rect: NSRect) {
        drawRounded(rect, radius: 4, fill: whitePanel, stroke: border)
        fillRect(SRect(rect.minX, rect.minY, rect.width, 32), color: tableHeader)
        drawText("#", rect: SRect(rect.minX + 10, rect.minY + 9, 24, 14), size: 10, weight: .bold, color: textPrimary)
        drawText("Time", rect: SRect(rect.minX + 48, rect.minY + 9, 110, 14), size: 10, weight: .bold, color: textPrimary)
        drawText("Saved Tokens", rect: SRect(rect.maxX - 104, rect.minY + 9, 84, 14), size: 10, weight: .bold, color: textPrimary, align: .right)
        let comps = Array(session.compactions.prefix(2))
        if comps.isEmpty {
            drawText("--", rect: SRect(rect.minX + 10, rect.minY + 48, rect.width - 20, 16), size: 12, weight: .regular, color: textSecondary, align: .center)
            return
        }
        for (index, compaction) in comps.enumerated() {
            let y = rect.minY + 32 + CGFloat(index) * 28
            strokeLine(from: SPoint(rect.minX, y), to: SPoint(rect.maxX, y), color: border)
            drawText("\(index + 1)", rect: SRect(rect.minX + 10, y + 8, 24, 14), size: 10, weight: .regular, color: textPrimary)
            drawText(shortDateTime(compaction.timestamp), rect: SRect(rect.minX + 48, y + 8, 120, 14), size: 10, weight: .regular, color: textPrimary)
            drawText(compaction.savedTokens.map(compact) ?? "--", rect: SRect(rect.maxX - 104, y + 8, 84, 14), size: 10, weight: .regular, color: textPrimary, align: .right)
        }
    }

    private func drawLegend(rect: NSRect) {
        drawText("Token size (thickness / color)", rect: SRect(rect.minX, rect.minY + 2, 190, 16), size: 11, weight: .regular, color: textPrimary)
        let items = [("> 1B", blue), ("500M – 1B", teal), ("100M – 500M", green), ("10M – 100M", orange), ("< 10M", rose)]
        var x = rect.minX + 194
        for item in items {
            fillRect(SRect(x, rect.minY + 8, 22, 8), color: item.1)
            drawText(item.0, rect: SRect(x + 30, rect.minY + 2, 92, 16), size: 11, weight: .regular, color: textPrimary)
            x += 112
        }
        strokeLine(from: SPoint(x + 20, rect.minY + 1), to: SPoint(x + 20, rect.minY + 23), color: orange, width: 2)
        drawText("Compaction event", rect: SRect(x + 34, rect.minY + 2, 120, 16), size: 11, weight: .regular, color: textPrimary)
    }

    private func drawCompositionBar(session: TaskInsightSession, rect: NSRect, labels: Bool) {
        let total = max(1, session.usage.input + session.usage.cachedInput + session.usage.output + session.usage.reasoningOutput)
        let segments: [(Int64, NSColor)] = [
            (session.usage.input, blue),
            (session.usage.cachedInput, paleBlue),
            (session.usage.output, green),
            (session.usage.reasoningOutput, purple),
            (max(0, session.usage.total - session.usage.input - session.usage.output - session.usage.reasoningOutput), orange)
        ]
        var x = rect.minX
        for segment in segments where segment.0 > 0 {
            let width = max(2, rect.width * CGFloat(Double(segment.0) / Double(total)))
            fillRect(SRect(x, rect.minY, min(width, rect.maxX - x), rect.height), color: segment.1)
            x += width
        }
        strokeRect(rect, color: NSColor.white.withAlphaComponent(0.5))
        if labels {
            drawText(compact(session.usage.total), rect: rect, size: 12, weight: .bold, color: .white, align: .center)
        }
    }

    private func drawLineChart(points: [TaskInsightContextPoint], compactions: [TaskInsightCompaction], rect: NSRect, simple: Bool = false) {
        strokeLine(from: SPoint(rect.minX, rect.maxY), to: SPoint(rect.maxX, rect.maxY), color: border)
        strokeLine(from: SPoint(rect.minX, rect.minY), to: SPoint(rect.minX, rect.maxY), color: border)
        for value in stride(from: 0, through: 100, by: 25) {
            let y = rect.maxY - rect.height * CGFloat(value) / 100
            strokeLine(from: SPoint(rect.minX, y), to: SPoint(rect.maxX, y), color: value == 100 ? red.withAlphaComponent(0.6) : grid, width: value == 100 ? 1.2 : 1, dash: value == 100 ? [4, 4] : nil)
            if !simple {
                drawText("\(value)%", rect: SRect(rect.minX - 42, y - 7, 34, 14), size: 10, weight: .regular, color: textSecondary, align: .right)
            }
        }
        guard points.count > 1 else { return }
        let maxCall = max(1, points.map(\.modelCall).max() ?? 1)
        let path = NSBezierPath()
        for (index, point) in points.enumerated() {
            let x = rect.minX + rect.width * CGFloat(Double(point.modelCall - 1) / Double(maxCall))
            let y = rect.maxY - rect.height * CGFloat(min(100, max(0, point.usedPercent)) / 100)
            if index == 0 { path.move(to: SPoint(x, y)) } else { path.line(to: SPoint(x, y)) }
        }
        blue.setStroke()
        path.lineWidth = 1.6
        path.stroke()
        guard let first = points.first?.timestamp, let last = points.last?.timestamp, last > first else { return }
        for compaction in compactions {
            let progress = compaction.timestamp.timeIntervalSince(first) / max(1, last.timeIntervalSince(first))
            let x = rect.minX + rect.width * CGFloat(max(0, min(1, progress)))
            strokeLine(from: SPoint(x, rect.minY), to: SPoint(x, rect.maxY), color: orange, width: 1.5)
        }
    }

    private func drawMiniBars(values: [Int], rect: NSRect, colors: [NSColor]) {
        let maxValue = max(1, values.max() ?? 1)
        let gap: CGFloat = 12
        let width = (rect.width - gap * CGFloat(max(0, values.count - 1))) / CGFloat(max(1, values.count))
        for (index, value) in values.enumerated() {
            let height = rect.height * CGFloat(value) / CGFloat(maxValue)
            let x = rect.minX + CGFloat(index) * (width + gap)
            fillRect(SRect(x, rect.maxY - height, width, height), color: colors[index % colors.count])
        }
    }

    private func drawLegendLine(label: String, color: NSColor, rect: NSRect) {
        strokeLine(from: SPoint(rect.minX, rect.midY), to: SPoint(rect.minX + 22, rect.midY), color: color, width: 2)
        drawText(label, rect: SRect(rect.minX + 30, rect.minY, rect.width - 30, rect.height), size: 11, weight: .regular, color: textPrimary)
    }

    private func drawSearch(_ placeholder: String, rect: NSRect) {
        drawRounded(rect, radius: 5, fill: NSColor.white, stroke: border)
        drawSymbol("magnifyingglass", rect: SRect(rect.minX + 10, rect.minY + 8, 16, 16), color: textSecondary)
        drawText(placeholder, rect: SRect(rect.minX + 32, rect.minY + 8, rect.width - 42, 18), size: 12, weight: .regular, color: textSecondary)
    }

    private func drawDropdown(_ title: String, rect: NSRect) {
        drawRounded(rect, radius: 5, fill: NSColor.white, stroke: border)
        drawText(title, rect: SRect(rect.minX + 12, rect.minY + 8, rect.width - 34, 18), size: 12, weight: .regular, color: textPrimary)
        drawText("⌄", rect: SRect(rect.maxX - 26, rect.minY + 7, 18, 18), size: 15, weight: .regular, color: textPrimary, align: .center)
    }

    private func drawSegment(labels: [String], selected: Int, rect: NSRect) {
        drawRounded(rect, radius: 6, fill: NSColor.white, stroke: border)
        let width = rect.width / CGFloat(labels.count)
        for (index, label) in labels.enumerated() {
            let cell = SRect(rect.minX + CGFloat(index) * width, rect.minY, width, rect.height)
            if index == selected {
                drawRounded(cell.insetBy(dx: 1, dy: 1), radius: 5, fill: blue.withAlphaComponent(0.86), stroke: blue.withAlphaComponent(0.3))
            } else if index > 0 {
                strokeLine(from: SPoint(cell.minX, cell.minY + 4), to: SPoint(cell.minX, cell.maxY - 4), color: border)
            }
            drawText(label, rect: cell.insetBy(dx: 2, dy: 8), size: 12, weight: .semibold, color: index == selected ? .white : textPrimary, align: .center)
        }
    }

    private func drawToggle(on: Bool, rect: NSRect) {
        drawRounded(rect, radius: rect.height / 2, fill: on ? blue : NSColor(calibratedWhite: 0.78, alpha: 1), stroke: nil)
        let knobX = on ? rect.maxX - rect.height + 2 : rect.minX + 2
        fillCircle(SRect(knobX, rect.minY + 2, rect.height - 4, rect.height - 4), color: .white)
    }

    private func drawIconButton(_ symbol: String, rect: NSRect) {
        drawRounded(rect, radius: 5, fill: NSColor.white, stroke: border)
        drawSymbol(symbol, rect: rect.insetBy(dx: 8, dy: 8), color: textPrimary)
    }

    private func drawPill(_ text: String, rect: NSRect, fill: NSColor, stroke: NSColor?, color: NSColor) {
        drawRounded(rect, radius: 4, fill: fill, stroke: stroke)
        drawText(text, rect: rect.insetBy(dx: 6, dy: 5), size: 10, weight: .regular, color: color, align: .center)
    }

    private func drawTrafficLights(x: Double, y: Double) {
        fillCircle(R(x, y, 14, 14), color: NSColor.systemRed)
        fillCircle(R(x + 24, y, 14, 14), color: NSColor.systemOrange)
        fillCircle(R(x + 48, y, 14, 14), color: NSColor.systemGreen)
    }

    private func drawLoadingOverlay() {
        fillRect(bounds, color: NSColor.white.withAlphaComponent(0.74))
        drawText("Loading Task Insights...", rect: SRect(bounds.midX - 140, bounds.midY - 14, 280, 28), size: 18, weight: .semibold, color: textPrimary, align: .center)
    }

    private func tokenDistributionValues() -> [Int] {
        var buckets = Array(repeating: 0, count: 6)
        for session in report.sessions {
            switch session.usage.total {
            case ..<1_000_000: buckets[0] += 1
            case ..<10_000_000: buckets[1] += 1
            case ..<100_000_000: buckets[2] += 1
            case ..<500_000_000: buckets[3] += 1
            case ..<1_000_000_000: buckets[4] += 1
            default: buckets[5] += 1
            }
        }
        return buckets
    }

    private func compactionDistributionValues() -> [Int] {
        var buckets = Array(repeating: 0, count: 7)
        for session in report.sessions {
            let index = min(6, session.compactions.count)
            buckets[index] += 1
        }
        return buckets
    }

    private func cacheDistributionValues() -> [Int] {
        var buckets = Array(repeating: 0, count: 6)
        for session in report.sessions {
            let index = min(5, Int(session.cacheRatio / 20))
            buckets[index] += 1
        }
        return buckets
    }

    private func tokenColor(_ value: Int64, maxTotal: Int64) -> NSColor {
        if value >= 1_000_000_000 { return blue }
        if value >= 500_000_000 { return teal }
        if value >= 100_000_000 { return green }
        if value >= 10_000_000 { return orange }
        if maxTotal > 0, Double(value) / Double(maxTotal) > 0.6 { return blue }
        return rose
    }

    private func percent(_ value: Int64, of total: Int64) -> String {
        guard total > 0 else { return "0.0%" }
        return String(format: "%.1f%%", Double(value) / Double(total) * 100)
    }

    private func compact(_ value: Int64) -> String {
        let double = Double(value)
        if abs(value) >= 1_000_000_000 {
            return String(format: double >= 10_000_000_000 ? "%.0fB" : "%.2fB", double / 1_000_000_000)
        }
        if abs(value) >= 1_000_000 {
            return String(format: double >= 10_000_000 ? "%.0fM" : "%.1fM", double / 1_000_000)
        }
        if abs(value) >= 1_000 {
            return String(format: "%.0fK", double / 1_000)
        }
        return "\(value)"
    }

    private func shortDuration(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int(seconds / 60))
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    private func relative(_ date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h ago" }
        return "\(Int(seconds / 86400))d ago"
    }

    private func dateTime(_ date: Date) -> String {
        Self.dateTimeFormatter.string(from: date)
    }

    private func shortDate(_ date: Date) -> String {
        Self.shortFormatter.string(from: date)
    }

    private func shortDateTime(_ date: Date) -> String {
        Self.shortDateTimeFormatter.string(from: date)
    }

    private func shortID(_ value: String) -> String {
        if value.count <= 24 { return value }
        return String(value.prefix(12)) + "..." + String(value.suffix(8))
    }

    private func truncate(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(max(0, limit - 1))) + "..."
    }

    private func drawSymbol(_ name: String, rect: NSRect, color: NSColor) {
        color.setStroke()
        color.setFill()
        let path = NSBezierPath()
        path.lineWidth = max(1.2, min(rect.width, rect.height) * 0.08)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        if name.contains("calendar") {
            NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 3), xRadius: 2, yRadius: 2).stroke()
            strokeLine(from: NSPoint(x: rect.minX + 3, y: rect.minY + rect.height * 0.35), to: NSPoint(x: rect.maxX - 3, y: rect.minY + rect.height * 0.35), color: color, width: path.lineWidth)
        } else if name.contains("folder") {
            path.move(to: NSPoint(x: rect.minX + 2, y: rect.minY + rect.height * 0.38))
            path.line(to: NSPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.38))
            path.line(to: NSPoint(x: rect.minX + rect.width * 0.50, y: rect.minY + rect.height * 0.52))
            path.line(to: NSPoint(x: rect.maxX - 2, y: rect.minY + rect.height * 0.52))
            path.line(to: NSPoint(x: rect.maxX - 2, y: rect.maxY - 3))
            path.line(to: NSPoint(x: rect.minX + 2, y: rect.maxY - 3))
            path.close()
            path.stroke()
        } else if name.contains("magnifyingglass") {
            NSBezierPath(ovalIn: NSRect(x: rect.minX + 2, y: rect.minY + 2, width: rect.width * 0.58, height: rect.height * 0.58)).stroke()
            strokeLine(from: NSPoint(x: rect.midX, y: rect.midY), to: NSPoint(x: rect.maxX - 2, y: rect.maxY - 2), color: color, width: path.lineWidth)
        } else if name.contains("chart") {
            let bars = [0.42, 0.72, 0.56]
            for (index, value) in bars.enumerated() {
                let w = rect.width / 6
                let x = rect.minX + rect.width * (0.18 + CGFloat(index) * 0.24)
                let h = rect.height * CGFloat(value)
                NSBezierPath(rect: NSRect(x: x, y: rect.maxY - h - 2, width: w, height: h)).fill()
            }
        } else if name.contains("gear") {
            NSBezierPath(ovalIn: rect.insetBy(dx: rect.width * 0.22, dy: rect.height * 0.22)).stroke()
            NSBezierPath(ovalIn: rect.insetBy(dx: rect.width * 0.40, dy: rect.height * 0.40)).stroke()
        } else if name.contains("cube") {
            NSBezierPath(rect: rect.insetBy(dx: 3, dy: 3)).stroke()
            strokeLine(from: NSPoint(x: rect.minX + 3, y: rect.midY), to: NSPoint(x: rect.midX, y: rect.maxY - 3), color: color, width: path.lineWidth)
            strokeLine(from: NSPoint(x: rect.midX, y: rect.maxY - 3), to: NSPoint(x: rect.maxX - 3, y: rect.midY), color: color, width: path.lineWidth)
        } else if name.contains("doc") || name.contains("square.and.arrow") {
            NSBezierPath(roundedRect: rect.insetBy(dx: 3, dy: 2), xRadius: 2, yRadius: 2).stroke()
            strokeLine(from: NSPoint(x: rect.minX + rect.width * 0.36, y: rect.midY), to: NSPoint(x: rect.maxX - 4, y: rect.midY), color: color, width: path.lineWidth)
        } else if name.contains("clock") {
            NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)).stroke()
            strokeLine(from: NSPoint(x: rect.midX, y: rect.midY), to: NSPoint(x: rect.midX, y: rect.minY + 4), color: color, width: path.lineWidth)
            strokeLine(from: NSPoint(x: rect.midX, y: rect.midY), to: NSPoint(x: rect.maxX - 5, y: rect.midY), color: color, width: path.lineWidth)
        } else if name.contains("wrench") {
            strokeLine(from: NSPoint(x: rect.minX + 4, y: rect.maxY - 4), to: NSPoint(x: rect.maxX - 4, y: rect.minY + 4), color: color, width: path.lineWidth)
            NSBezierPath(ovalIn: NSRect(x: rect.minX + 3, y: rect.maxY - 8, width: 6, height: 6)).stroke()
        } else if name.contains("arrow.clockwise") {
            path.appendArc(withCenter: NSPoint(x: rect.midX, y: rect.midY), radius: min(rect.width, rect.height) * 0.34, startAngle: 30, endAngle: 310, clockwise: false)
            path.stroke()
        } else if name.contains("house") {
            path.move(to: NSPoint(x: rect.minX + 3, y: rect.midY))
            path.line(to: NSPoint(x: rect.midX, y: rect.minY + 3))
            path.line(to: NSPoint(x: rect.maxX - 3, y: rect.midY))
            path.line(to: NSPoint(x: rect.maxX - 5, y: rect.maxY - 3))
            path.line(to: NSPoint(x: rect.minX + 5, y: rect.maxY - 3))
            path.close()
            path.stroke()
        } else {
            NSBezierPath(roundedRect: rect.insetBy(dx: 3, dy: 3), xRadius: 2, yRadius: 2).stroke()
        }
    }

    private func drawText(_ text: String, rect: NSRect, size: CGFloat, weight: NSFont.Weight, color: NSColor, align: NSTextAlignment = .left) {
        guard rect.width > 0, rect.height > 0 else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = align
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: scaled(size), weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        NSString(string: text).draw(in: rect, withAttributes: attributes)
    }

    private func fill(_ color: NSColor) {
        fillRect(bounds, color: color)
    }

    private func fillRect(_ rect: NSRect, color: NSColor) {
        color.setFill()
        rect.fill()
    }

    private func strokeRect(_ rect: NSRect, color: NSColor) {
        color.setStroke()
        NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }

    private func drawRounded(_ rect: NSRect, radius: CGFloat, fill: NSColor, stroke: NSColor?) {
        fill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        if let stroke {
            stroke.setStroke()
            NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius).stroke()
        }
    }

    private func fillCircle(_ rect: NSRect, color: NSColor) {
        color.setFill()
        NSBezierPath(ovalIn: rect).fill()
    }

    private func strokeLine(from: NSPoint, to: NSPoint, color: NSColor, width: CGFloat = 1, dash: [CGFloat]? = nil) {
        color.setStroke()
        let path = NSBezierPath()
        path.move(to: from)
        path.line(to: to)
        path.lineWidth = width
        if let dash {
            path.setLineDash(dash, count: dash.count, phase: 0)
        }
        path.stroke()
    }

    private func R(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> NSRect {
        SRect(CGFloat(x), CGFloat(y), CGFloat(width), CGFloat(height))
    }

    private func P(_ x: Double, _ y: Double) -> NSPoint {
        SPoint(CGFloat(x), CGFloat(y))
    }

    private func SRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
        let scaledX = x * scaleX
        let scaledY = y * scaleY
        let scaledW = width * scaleX
        let scaledH = height * scaleY
        if drawsInUnflippedBitmapContext {
            return NSRect(x: scaledX, y: bounds.height - scaledY - scaledH, width: scaledW, height: scaledH)
        }
        return NSRect(x: scaledX, y: scaledY, width: scaledW, height: scaledH)
    }

    private func SPoint(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        let scaledX = x * scaleX
        let scaledY = y * scaleY
        if drawsInUnflippedBitmapContext {
            return NSPoint(x: scaledX, y: bounds.height - scaledY)
        }
        return NSPoint(x: scaledX, y: scaledY)
    }

    private func scaled(_ size: CGFloat) -> CGFloat {
        max(8, size * min(scaleX, scaleY))
    }

    private var scaleX: CGFloat { bounds.width / Self.referenceSize.width }
    private var scaleY: CGFloat { bounds.height / Self.referenceSize.height }

    private var lightBackground: NSColor { NSColor(calibratedWhite: 0.985, alpha: 1) }
    private var sidebarBackground: NSColor { NSColor(calibratedWhite: 0.965, alpha: 1) }
    private var whitePanel: NSColor { NSColor.white }
    private var tableHeader: NSColor { NSColor(calibratedWhite: 0.972, alpha: 1) }
    private var border: NSColor { NSColor(calibratedWhite: 0.84, alpha: 1) }
    private var grid: NSColor { NSColor(calibratedWhite: 0.82, alpha: 1) }
    private var textPrimary: NSColor { NSColor(calibratedRed: 0.06, green: 0.075, blue: 0.10, alpha: 1) }
    private var textSecondary: NSColor { NSColor(calibratedRed: 0.32, green: 0.34, blue: 0.39, alpha: 1) }
    private var textTertiary: NSColor { NSColor(calibratedRed: 0.44, green: 0.46, blue: 0.52, alpha: 1) }
    private var blue: NSColor { NSColor(calibratedRed: 0.11, green: 0.45, blue: 0.92, alpha: 1) }
    private var paleBlue: NSColor { NSColor(calibratedRed: 0.55, green: 0.78, blue: 0.97, alpha: 1) }
    private var lightBlue: NSColor { NSColor(calibratedRed: 0.88, green: 0.94, blue: 1, alpha: 1) }
    private var teal: NSColor { NSColor(calibratedRed: 0.28, green: 0.72, blue: 0.68, alpha: 1) }
    private var green: NSColor { NSColor(calibratedRed: 0.33, green: 0.73, blue: 0.38, alpha: 1) }
    private var lightGreen: NSColor { NSColor(calibratedRed: 0.86, green: 0.96, blue: 0.89, alpha: 1) }
    private var orange: NSColor { NSColor(calibratedRed: 1.0, green: 0.56, blue: 0.09, alpha: 1) }
    private var lightOrange: NSColor { NSColor(calibratedRed: 1.0, green: 0.93, blue: 0.86, alpha: 1) }
    private var purple: NSColor { NSColor(calibratedRed: 0.47, green: 0.25, blue: 0.84, alpha: 1) }
    private var rose: NSColor { NSColor(calibratedRed: 0.88, green: 0.31, blue: 0.56, alpha: 1) }
    private var red: NSColor { NSColor(calibratedRed: 0.90, green: 0.16, blue: 0.14, alpha: 1) }
    private var lightRose: NSColor { NSColor(calibratedRed: 1.0, green: 0.92, blue: 0.91, alpha: 1) }

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return formatter
    }()

    private static let shortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter
    }()

    private static let shortDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter
    }()
}

private extension NSRect {
    func withHeight(_ height: CGFloat) -> NSRect {
        NSRect(x: minX, y: minY, width: width, height: height)
    }
}

func renderTaskInsightsSnapshot(arguments: [String], rootURLs: [URL]) throws -> URL {
    let variant = arguments.compactMap { argument -> TaskInsightVariant? in
        if argument.hasPrefix("--variant=") {
            return TaskInsightVariant(rawValue: String(argument.dropFirst("--variant=".count)))
        }
        if argument.hasPrefix("--task-insights-variant=") {
            return TaskInsightVariant(rawValue: String(argument.dropFirst("--task-insights-variant=".count)))
        }
        return nil
    }.first ?? .timeline

    let outputURL = arguments.compactMap { argument -> URL? in
        if argument.hasPrefix("--render-task-insights=") {
            return URL(fileURLWithPath: String(argument.dropFirst("--render-task-insights=".count)))
        }
        return nil
    }.first ?? URL(fileURLWithPath: "/tmp/\(variant.renderFileName)")

    let report = TaskInsightsScanner(rootURLs: rootURLs).scan(days: 30)
    let view = TaskInsightsView(frame: NSRect(origin: .zero, size: TaskInsightsView.referenceSize))
    view.variant = variant
    view.report = report
    view.drawsInUnflippedBitmapContext = true
    view.layoutSubtreeIfNeeded()

    let width = Int(TaskInsightsView.referenceSize.width)
    let height = Int(TaskInsightsView.referenceSize.height)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "CodexTokenMeter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create task insight bitmap"])
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    view.draw(view.bounds)
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "CodexTokenMeter", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to encode task insight PNG"])
    }
    try data.write(to: outputURL, options: [.atomic])
    return outputURL
}
