import Cocoa
import Foundation

private final class FlippedCanvasView: NSView {
    override var isFlipped: Bool { true }
}

private func descendantThreadRow(in view: NSView, threadID: String) -> ThreadRowView? {
    if let row = view as? ThreadRowView, row.representedThreadID == threadID {
        return row
    }
    for child in view.subviews {
        if let row = descendantThreadRow(in: child, threadID: threadID) {
            return row
        }
    }
    return nil
}

private func printThreads() {
    let items = ReadStateStore()
        .visibleThreads(from: CodexActivityReader().read(limit: taskBarCandidateThreadLimit))
        .sorted(by: stableThreadOrder)
        .limitedForTaskBar(limit: taskBarVisibleThreadLimit)
    if items.isEmpty {
        print("No running or unread Codex, Claude, or OpenCode turns")
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
        let plan = item.plan.map { "\tplan=\($0.displayedStepNumber)/\($0.steps.count)" } ?? ""
        let usage = "\tturns=\(item.turns)\tmodel=\(item.model ?? "-")"
            + "\ttokens=\(item.tokenBreakdown.displayTotal.map(String.init) ?? "-")"
            + "\tin=\(item.tokenBreakdown.input)\tcached=\(item.tokenBreakdown.cachedInput)\tout=\(item.tokenBreakdown.output)"
        print("\(prefix)\(label)\t\(timing)\t\(folder)\t\(identity)\t\(item.id)\t\(item.source)\(usage)\(preview)\(plan)")
    }
    for item in items.primaryThreads {
        printItem(item)
        for subtask in items.subtasks(parentID: item.id) {
            printItem(subtask, prefix: "  ↳ ")
        }
    }
}

private func testPlanParser() {
    let arguments = #"{"explanation":"fixture","plan":[{"step":"读取数据","status":"completed"},{"step":"实现界面","status":"in_progress"},{"step":"验证结果","status":"pending"}]}"#
    let payload: [String: Any] = [
        "type": "function_call",
        "name": "update_plan",
        "arguments": arguments
    ]
    let object: [String: Any] = [
        "type": "response_item",
        "payload": payload
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: object),
          let line = String(data: data, encoding: .utf8),
          let plan = parseTaskPlanFunctionCall(line),
          plan.steps.count == 3,
          plan.displayedStepNumber == 2,
          Int(round(plan.progress * 100)) == 67,
          plan.currentStepText == "实现界面" else {
        fputs("plan parser self-test failed\n", stderr)
        exit(1)
    }
    let customPayload: [String: Any] = [
        "type": "custom_tool_call",
        "name": "exec",
        "input": #"const result = await tools.update_plan({explanation:"fixture",plan:[{step:"读取数据",status:"completed"},{step:"实现界面",status:"in_progress"},{step:"验证结果",status:"pending"}]});"#
    ]
    let customObject: [String: Any] = [
        "type": "response_item",
        "payload": customPayload
    ]
    guard let customData = try? JSONSerialization.data(withJSONObject: customObject),
          let customLine = String(data: customData, encoding: .utf8),
          let customPlan = parseTaskPlan(inRolloutLine: customLine),
          customPlan.steps.count == 3,
          customPlan.displayedStepNumber == 2,
          customPlan.currentStepText == "实现界面" else {
        fputs("custom tool plan parser self-test failed\n", stderr)
        exit(1)
    }
    let temporaryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("task-bar-plan-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: temporaryURL) }
    let filler = String(repeating: "x", count: 600 * 1024)
    let fixture = [
        #"{"type":"event_msg","payload":{"type":"agent_message","message":"\#(filler)"}}"#,
        customLine,
        #"{"type":"event_msg","payload":{"type":"agent_message","message":"\#(filler)"}}"#
    ].joined(separator: "\n") + "\n"
    do {
        try Data(fixture.utf8).write(to: temporaryURL)
    } catch {
        fputs("plan history self-test fixture failed: \(error)\n", stderr)
        exit(1)
    }
    guard let recovered = latestTaskPlan(inRollout: temporaryURL),
          recovered.steps.count == 3,
          recovered.displayedStepNumber == 2 else {
        fputs("plan history self-test failed\n", stderr)
        exit(1)
    }
    print("plan parser self-test passed: \(plan.displayedStepNumber)/\(plan.steps.count), custom tool and restart recovery passed")
}

private func testTaskLaunchRouting() {
    guard codexThreadLaunchTarget(source: "vscode", historyMode: "paginated") == .codexDesktopActivationOnly,
          codexThreadLaunchTarget(source: "vscode", historyMode: " PAGINATED ") == .codexDesktopActivationOnly,
          codexThreadLaunchTarget(source: "vscode", historyMode: "legacy") == .codexDesktop,
          codexThreadLaunchTarget(source: "vscode") == .codexDesktop,
          codexThreadLaunchTarget(source: " VSCode ") == .codexDesktop,
          codexThreadLaunchTarget(source: "desktop") == .codexDesktop,
          codexThreadLaunchTarget(source: nil) == .codexDesktop,
          sourceLabel(mockTaskBarThreads().first { $0.source == "vscode" }
              ?? mockTaskBarThreads()[0]) == "Codex" else {
        fputs("task launch routing self-test failed\n", stderr)
        exit(1)
    }
    print("task launch routing self-test passed: paginated tasks activate Codex; legacy tasks deep-link")
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
        agentPath: String? = nil,
        plan: TaskPlan? = nil,
        launchTarget: TaskLaunchTarget = .codexDesktop
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
            agentPath: agentPath,
            plan: plan,
            launchTarget: launchTarget
        )
    }
    let demoPlan = TaskPlan(
        explanation: "正在验证正式匹配的多竞品处理",
        steps: [
            TaskPlanStep(text: "梳理正式匹配现有多路召回与 small match 召回入口", status: .completed),
            TaskPlanStep(text: "设计并实现 small match 主产品与竞品多路召回及来源归因", status: .completed),
            TaskPlanStep(text: "补充单元与回归测试，覆盖去重、来源优先级、name/url 返回", status: .completed),
            TaskPlanStep(text: "运行 Arachne 目标测试及相关回归测试", status: .inProgress),
            TaskPlanStep(text: "整理改动、测试证据与后续测试环境验证项", status: .pending)
        ]
    )
    return [
        item(id: "codex:1", title: "这是怎么回事", preview: "已通过 PR 合并到 `main`。", status: .unread, ago: 75, source: "vscode", launchTarget: .visualStudioCode),
        item(id: "codex:poster", title: "我在川西形成我之前做了个地图，你找找那…", preview: "我会用 `generate-trip-map` 增加独立的“一键最短路径”按钮。", status: .running, ago: 482, source: "codex", plan: demoPlan),
        item(id: "codex:claude-home", title: "挖掘 Task Bar 支持 Claude Home 对话", preview: "候选验证通过：双 App 构建、周统计解析、实时额度。", status: .running, ago: 230, source: "codex", plan: demoPlan),
        item(id: "codex:campaign", title: "实现这个需求", preview: "测试 Mongo 查询正在等待集群响应；不会修改任何数据。", status: .running, ago: 888, source: "codex"),
        item(id: "codex:poster:wall", title: "构思 Codex 对战 Claude 海报", preview: "正在完善限额墙方案。", status: .running, ago: 86, source: "codex", kind: .subtask, parentID: "codex:poster", nickname: "Kepler", agentPath: "/root/poster_wall"),
        item(id: "codex:poster:kickdoor", title: "构思 Codex 对战 Claude 海报", preview: "踢门方案已经完成。", status: .unread, ago: 250, source: "codex", kind: .subtask, parentID: "codex:poster", nickname: "Locke", agentPath: "/root/poster_kickdoor"),
        item(id: "codex:poster:knockout", title: "构思 Codex 对战 Claude 海报", preview: "击倒方案已经完成。", status: .unread, ago: 280, source: "codex", kind: .subtask, parentID: "codex:poster", nickname: "Mill", agentPath: "/root/poster_knockout")
    ]
}

private func renderTaskBar(to path: String, showPlanHover: Bool = false, showRowHover: Bool = false) {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    var mock = mockTaskBarThreads().sorted(by: stableThreadOrder)
    if showPlanHover {
        mock = mock.filter { !$0.isSubtask }
    }
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
        usesExternalSurface: TaskBarBuild.isBeta,
        onResize: { _, _ in }
    )

    let renderedView: NSView
    if showPlanHover,
       let planItem = mock.first(where: { $0.plan != nil }),
       let plan = planItem.plan {
        let planView = taskPlanPreviewView(for: plan)
        let contentSize = content.frame.size
        let size = NSSize(
            width: contentSize.width + planView.frame.width - 12,
            height: max(contentSize.height, planView.frame.height)
        )
        let canvas = FlippedCanvasView(frame: NSRect(origin: .zero, size: size))
        canvas.wantsLayer = true
        canvas.layer?.backgroundColor = NSColor.clear.cgColor
        content.frame = NSRect(
            x: 0,
            y: (size.height - contentSize.height) / 2,
            width: contentSize.width,
            height: contentSize.height
        )
        canvas.addSubview(content)
        canvas.addSubview(planView)
        canvas.layoutSubtreeIfNeeded()
        content.layoutSubtreeIfNeeded()
        let row = descendantThreadRow(in: content, threadID: planItem.id)
        row?.setRenderPreviewHovering(true)
        row?.needsDisplay = true
        let rowRect = row.map { $0.convert($0.bounds, to: content) }
        let desiredY = content.frame.minY
            + (rowRect?.midY ?? contentSize.height / 2)
            - planView.frame.height / 2
        planView.frame.origin = NSPoint(
            x: contentSize.width - 12,
            y: min(max(0, desiredY), size.height - planView.frame.height)
        )
        renderedView = canvas
    } else {
        renderedView = content
        if showRowHover,
           let item = mock.primaryThreads.first(where: { selectedTab.matches($0.status) }),
           let row = descendantThreadRow(in: content, threadID: item.id) {
            row.setRenderPreviewHovering(true)
            row.needsDisplay = true
        }
    }
    let size = renderedView.frame.size
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentView = renderedView
    window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
    window.orderFront(nil)
    defer { window.orderOut(nil) }
    renderedView.frame = NSRect(origin: .zero, size: size)
    renderedView.layoutSubtreeIfNeeded()
    renderedView.needsDisplay = true
    renderedView.display()
    window.displayIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.08))
    renderedView.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    func displayHierarchy(_ view: NSView) {
        view.needsDisplay = true
        view.display()
        view.subviews.forEach(displayHierarchy)
    }
    displayHierarchy(renderedView)

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
    ), let context = NSGraphicsContext(bitmapImageRep: rep), let layer = renderedView.layer else {
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

private func renderTaskBarSettings(to path: String) {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let settings = TaskBarSettingsView(onSettingsChanged: {})
    do {
        try settings.writePreview(to: path)
        print("wrote \(path) (\(Int(settings.bounds.width))x\(Int(settings.bounds.height)))")
    } catch {
        fputs("settings render failed: \(error)\n", stderr)
        exit(1)
    }
}

if CommandLine.arguments.contains("--self-test-plan-parser") {
    testPlanParser()
} else if CommandLine.arguments.contains("--self-test-task-routing") {
    testTaskLaunchRouting()
} else if CommandLine.arguments.contains("--print") {
    printThreads()
} else if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--render-taskbar=") }) {
    renderTaskBar(to: String(arg.dropFirst("--render-taskbar=".count)))
} else if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--render-taskbar-plan-hover=") }) {
    renderTaskBar(
        to: String(arg.dropFirst("--render-taskbar-plan-hover=".count)),
        showPlanHover: true
    )
} else if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--render-taskbar-row-hover=") }) {
    renderTaskBar(
        to: String(arg.dropFirst("--render-taskbar-row-hover=".count)),
        showRowHover: true
    )
} else if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--render-taskbar-settings=") }) {
    renderTaskBarSettings(to: String(arg.dropFirst("--render-taskbar-settings=".count)))
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
