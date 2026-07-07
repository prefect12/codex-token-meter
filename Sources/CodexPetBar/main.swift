import Cocoa
import Foundation

private func printThreads() {
    let items = ReadStateStore()
        .visibleThreads(from: CodexActivityReader().read(limit: taskBarCandidateThreadLimit))
        .sorted(by: stableThreadOrder)
        .limitedForTaskBar(limit: taskBarVisibleThreadLimit)
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
        let breakdown = TokenBreakdown(
            input: 2_387_000,
            cachedInput: 2_305_000,
            output: 99_270,
            reasoningOutput: 21_800,
            total: 2_486_270,
            hasDetailedCounters: true
        )
        return CodexThreadItem(
            id: id,
            title: title,
            preview: preview,
            cwd: "/Users/demo/Projects/task-bar",
            lastActivity: Date().addingTimeInterval(-ago),
            startedAt: Date().addingTimeInterval(-ago),
            externalReadAt: nil,
            status: status,
            turns: 12,
            compressionCount: 1,
            source: source,
            isExplicitUnread: status == .unread,
            codexUpdatedAt: nil,
            tokensUsed: breakdown.displayTotal,
            tokenBreakdown: breakdown,
            model: "gpt-5-codex"
        )
    }
    return [
        item(id: "codex:1", title: "Automation: 更新飞书 @ 我任务文档", preview: "脚本正在同步飞书，我等最终状态文件返回。", status: .running, ago: 47, source: "codex"),
        item(id: "claude:2", title: "这个看起来不太对，帮忙看看呀 @ 杨工", preview: "已经跨过 18:54 的大批次，累计 23034 条，时间跳到现在。", status: .running, ago: 7333, source: "claude-code"),
        item(id: "codex:3", title: "帮我安装最新的 main 的 codex bar", preview: "我会同时压三处：header 高度/字号、列表字号、底部按钮宽度。顶部间距也从上一版收紧。", status: .running, ago: 9201, source: "codex")
    ]
}

private func writePNG(_ view: NSView, to path: String) throws {
    view.layoutSubtreeIfNeeded()
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        throw NSError(domain: "TaskBar", code: 1, userInfo: [NSLocalizedDescriptionKey: "render failed: no bitmap rep"])
    }
    view.cacheDisplay(in: view.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "TaskBar", code: 2, userInfo: [NSLocalizedDescriptionKey: "render failed: no png data"])
    }
    try data.write(to: URL(fileURLWithPath: path))
}

private func renderTaskBar(to path: String) {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    var mock = mockTaskBarThreads().sorted(by: stableThreadOrder)
    if let countArg = CommandLine.arguments.first(where: { $0.hasPrefix("--count=") }),
       let count = Int(countArg.dropFirst("--count=".count)) {
        mock = Array(mock.prefix(max(0, count)))
    }
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
        rowLayout: TaskBarSettings.rowLayout,
        onOpenThread: { _ in },
        onDismissThread: { _ in },
        onTogglePin: { _ in },
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

    do {
        if let hoverArg = CommandLine.arguments.first(where: { $0.hasPrefix("--hover-row=") }),
           let hoverIndex = Int(hoverArg.dropFirst("--hover-row=".count)),
           mock.indices.contains(hoverIndex) {
            let tooltip = ThreadTooltipView()
            tooltip.rows = tooltipRows(for: mock[hoverIndex])
            let tooltipSize = tooltip.preferredSize
            let compositeSize = NSSize(width: max(size.width, 560), height: size.height)
            let composite = NSView(frame: NSRect(origin: .zero, size: compositeSize))
            composite.wantsLayer = true
            composite.layer?.backgroundColor = NSColor.clear.cgColor
            content.frame = NSRect(origin: .zero, size: size)
            tooltip.frame = NSRect(
                x: min(compositeSize.width - tooltipSize.width - 18, 210),
                y: max(18, compositeSize.height - tooltipSize.height - 78),
                width: tooltipSize.width,
                height: tooltipSize.height
            )
            composite.addSubview(content)
            composite.addSubview(tooltip)
            try writePNG(composite, to: path)
            print("wrote \(path) (\(Int(compositeSize.width))x\(Int(compositeSize.height)))")
        } else {
            try writePNG(content, to: path)
            print("wrote \(path) (\(Int(size.width))x\(Int(size.height)))")
        }
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
