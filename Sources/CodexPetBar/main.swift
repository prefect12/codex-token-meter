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
    func printItem(_ item: CodexThreadItem, prefix: String = "") {
        let folder = shortFolderName(item.cwd)
        let timing = item.status == .running
            ? item.startedAt.map { "elapsed \(durationSince($0))" } ?? relative(item.lastActivity)
            : relative(item.lastActivity)
        let preview = item.preview.map { "\t\($0)" } ?? ""
        let label = item.isSubtask ? "Subtask \(statusLabel(item.status))" : statusLabel(item.status)
        let identity = item.isSubtask
            ? [item.agentNickname, item.agentPath].compactMap { $0 }.joined(separator: " · ")
            : item.title
        print("\(prefix)\(label)\t\(timing)\t\(folder)\t\(identity)\t\(item.id)\t\(item.source)\(preview)")
    }
    for item in items.primaryThreads {
        printItem(item)
        for subtask in items.subtasks(parentID: item.id) {
            printItem(subtask, prefix: "  ↳ ")
        }
    }
}

private func mockTaskBarThreads() -> [CodexThreadItem] {
    func item(
        id: String,
        title: String,
        preview: String,
        status: ThreadRunStatus,
        ago: TimeInterval,
        source: String,
        kind: CodexThreadKind = .root,
        parentID: String? = nil,
        nickname: String? = nil,
        agentPath: String? = nil
    ) -> CodexThreadItem {
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
            codexUpdatedAt: nil,
            tokensUsed: 128_000,
            tokenBreakdown: TokenBreakdown(),
            model: "gpt-5-codex",
            threadKind: kind,
            parentThreadID: parentID,
            agentNickname: nickname,
            agentPath: agentPath
        )
    }
    return [
        item(id: "codex:1", title: "019f68d1-3407-7621-8073-d5afe292…", preview: "我继续往目标推进，不等账户密钥。当前线上 v6 实际可用。", status: .running, ago: 103, source: "codex"),
        item(id: "codex:poster", title: "构思 Codex 对战 Claude 海报", preview: "第一张“教父阴影”已经出来了，构图和暗示关系非常准。", status: .running, ago: 482, source: "codex"),
        item(id: "codex:poster:wall", title: "构思 Codex 对战 Claude 海报", preview: "正在完善限额墙方案。", status: .running, ago: 86, source: "codex", kind: .subtask, parentID: "codex:poster", nickname: "Kepler", agentPath: "/root/poster_wall"),
        item(id: "codex:poster:kickdoor", title: "构思 Codex 对战 Claude 海报", preview: "踢门方案已经完成。", status: .unread, ago: 250, source: "codex", kind: .subtask, parentID: "codex:poster", nickname: "Locke", agentPath: "/root/poster_kickdoor"),
        item(id: "codex:poster:knockout", title: "构思 Codex 对战 Claude 海报", preview: "击倒方案已经完成。", status: .unread, ago: 280, source: "codex", kind: .subtask, parentID: "codex:poster", nickname: "Mill", agentPath: "/root/poster_knockout")
    ]
}

private func renderTaskBar(to path: String) {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    var mock = mockTaskBarThreads().sorted(by: stableThreadOrder)
    if let countArg = CommandLine.arguments.first(where: { $0.hasPrefix("--count=") }),
       let count = Int(countArg.dropFirst("--count=".count)) {
        mock = Array(mock.prefix(max(0, count)))
    }
    let primary = mock.primaryThreads
    let running = primary.filter { $0.status == .running }.count
    let waiting = primary.filter { $0.status == .waiting }.count
    let unread = primary.filter { $0.status == .unread }.count

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
        collapsedThreadIDs: [],
        onSetSubtasksExpanded: { _, _ in },
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
    window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
    window.orderFront(nil)
    defer { window.orderOut(nil) }
    content.frame = NSRect(origin: .zero, size: size)
    content.layoutSubtreeIfNeeded()
    content.needsDisplay = true
    content.display()
    window.displayIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.08))
    content.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    func displayHierarchy(_ view: NSView) {
        view.needsDisplay = true
        view.display()
        view.subviews.forEach(displayHierarchy)
    }
    displayHierarchy(content)

    let scale = NSScreen.main?.backingScaleFactor ?? 2
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width * scale),
        pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep), let layer = content.layer else {
        print("render failed: no bitmap rep")
        return
    }
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: scale, y: scale)
    context.cgContext.translateBy(x: 0, y: size.height)
    context.cgContext.scaleBy(x: 1, y: -1)
    layer.render(in: context.cgContext)
    NSGraphicsContext.restoreGraphicsState()
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
