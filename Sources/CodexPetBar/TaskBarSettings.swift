import Cocoa
import Foundation

enum TaskTokenUnitStyle: String, CaseIterable {
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

/// Where a row places its time / status / platform metadata.
/// `.standard` keeps them on a single line beneath the text; `.compact`
/// stacks them in a narrow left rail so each row is shorter and the list
/// can breathe at a narrower width.
/// Not `private`: it appears in the (internal) `ThreadRowView.init` signature.
enum TaskRowLayoutStyle: String, CaseIterable {
    case standard
    case compact

    var title: String {
        switch self {
        case .standard: return "底部"
        case .compact: return "左侧"
        }
    }

    var rowHeight: CGFloat {
        switch self {
        case .standard: return taskBarRowHeight
        case .compact: return taskBarCompactRowHeight
        }
    }
}

enum TaskHoverField: String, CaseIterable, Hashable {
    case status
    case input
    case output
    case cacheRate
    case tokenTotal
    case turns
    case compression
    case model
    case folder
    case branch
    case worktree

    var title: String {
        switch self {
        case .status: return "状态"
        case .input: return "输入"
        case .output: return "输出"
        case .cacheRate: return "缓存率"
        case .tokenTotal: return "Token 消耗"
        case .turns: return "对话轮次"
        case .compression: return "压缩次数"
        case .model: return "模型"
        case .folder: return "文件夹"
        case .branch: return "分支"
        case .worktree: return "Worktree"
        }
    }
}

enum TaskHoverLayoutItem: Equatable {
    case field(TaskHoverField)
    case separator(String)

    var storageToken: String {
        switch self {
        case .field(let field): return field.rawValue
        case .separator(let id): return "separator:\(id)"
        }
    }

    var visibilityKey: String {
        switch self {
        case .field(let field): return field.rawValue
        case .separator(let id): return "separator:\(id)"
        }
    }

    init?(storageToken: String) {
        if storageToken == "separator" {
            self = .separator("legacy")
            return
        }
        if storageToken.hasPrefix("separator:") {
            let id = String(storageToken.dropFirst("separator:".count))
            self = .separator(id.isEmpty ? "legacy" : id)
            return
        }
        guard let field = TaskHoverField(rawValue: storageToken) else { return nil }
        self = .field(field)
    }
}

enum TaskBarSettings {
    private static let showPlatformLabelsKey = "showPlatformLabels"
    private static let tokenUnitStyleKey = "tokenUnitStyle"
    private static let rowLayoutKey = "taskRowLayout"
    private static let statusGroupOrderKey = "statusGroupOrder"
    private static let popoverWidthKey = "popoverWidth"
    private static let popoverHeightKey = "popoverHeight"
    private static let hoverLayoutKey = "hoverLayout"
    private static let hoverHiddenFieldsKey = "hoverHiddenFields"
    private static let pinnedThreadsKey = "pinnedThreadIDs"
    private static let pinnedThreadsCap = 100
    private static let pinnedThreadsLock = NSLock()
    private static var pinnedThreadsCache: Set<String>?

    static let defaultHoverLayout: [TaskHoverLayoutItem] = [
        .field(.status),
        .separator("tokens"),
        .field(.input),
        .field(.output),
        .field(.cacheRate),
        .field(.tokenTotal),
        .separator("conversation"),
        .field(.turns),
        .field(.compression),
        .field(.model),
        .separator("context"),
        .field(.folder),
        .field(.branch),
        .field(.worktree)
    ]

    /// Thread ids pinned to the top of the list. Cached in memory because the sort
    /// comparator reads this per comparison, potentially off the main thread.
    static var pinnedThreadIDs: Set<String> {
        pinnedThreadsLock.lock()
        defer { pinnedThreadsLock.unlock() }
        if let cached = pinnedThreadsCache { return cached }
        let stored = Set(UserDefaults.standard.stringArray(forKey: pinnedThreadsKey) ?? [])
        pinnedThreadsCache = stored
        return stored
    }

    static func isPinned(_ threadID: String) -> Bool {
        pinnedThreadIDs.contains(threadID)
    }

    static func togglePin(_ threadID: String) {
        setPinned(!isPinned(threadID), for: threadID)
    }

    static func setPinned(_ pinned: Bool, for threadID: String) {
        pinnedThreadsLock.lock()
        defer { pinnedThreadsLock.unlock() }
        var stored = UserDefaults.standard.stringArray(forKey: pinnedThreadsKey) ?? []
        stored.removeAll { $0 == threadID }
        if pinned {
            stored.append(threadID)
            // Oldest pins fall off first so stale ids cannot accumulate forever.
            if stored.count > pinnedThreadsCap {
                stored.removeFirst(stored.count - pinnedThreadsCap)
            }
        }
        UserDefaults.standard.set(stored, forKey: pinnedThreadsKey)
        pinnedThreadsCache = Set(stored)
    }

    /// User-resized popover size, persisted across opens and launches. `nil` until first resize.
    static var popoverSize: NSSize? {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: popoverWidthKey) != nil,
                  defaults.object(forKey: popoverHeightKey) != nil else {
                return nil
            }
            let size = NSSize(
                width: CGFloat(defaults.double(forKey: popoverWidthKey)),
                height: CGFloat(defaults.double(forKey: popoverHeightKey))
            )
            guard size.width > 1, size.height > 1 else { return nil }
            return size
        }
        set {
            let defaults = UserDefaults.standard
            if let newValue {
                defaults.set(Double(newValue.width), forKey: popoverWidthKey)
                defaults.set(Double(newValue.height), forKey: popoverHeightKey)
            } else {
                defaults.removeObject(forKey: popoverWidthKey)
                defaults.removeObject(forKey: popoverHeightKey)
            }
        }
    }

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

    /// User-defined order of the three status groups in the "All" tab. Falls back to
    /// the default order whenever the stored value is missing or corrupt.
    static var statusGroupOrder: [TaskStatusGroup] {
        get {
            guard let raw = UserDefaults.standard.string(forKey: statusGroupOrderKey) else {
                return TaskStatusGroup.defaultOrder
            }
            let groups = raw.split(separator: ",").compactMap { TaskStatusGroup(rawValue: String($0)) }
            // Require each group to appear exactly once; otherwise treat as corrupt.
            guard groups.count == TaskStatusGroup.allCases.count,
                  Set(groups).count == TaskStatusGroup.allCases.count else {
                return TaskStatusGroup.defaultOrder
            }
            return groups
        }
        set {
            UserDefaults.standard.set(newValue.map(\.rawValue).joined(separator: ","), forKey: statusGroupOrderKey)
        }
    }

    static var hoverLayout: [TaskHoverLayoutItem] {
        get {
            guard let raw = UserDefaults.standard.string(forKey: hoverLayoutKey), !raw.isEmpty else {
                return defaultHoverLayout
            }
            let stored = raw.split(separator: ",", omittingEmptySubsequences: false)
                .compactMap { TaskHoverLayoutItem(storageToken: String($0)) }
            guard !stored.isEmpty else { return defaultHoverLayout }

            var seenFields = Set<TaskHoverField>()
            var separatorIndex = 0
            var seenSeparators = Set<String>()
            var sanitized: [TaskHoverLayoutItem] = []
            for item in stored {
                switch item {
                case .separator(let id):
                    separatorIndex += 1
                    let rawID = id == "legacy" ? "custom\(separatorIndex)" : id
                    let nextID = seenSeparators.contains(rawID) ? "\(rawID)-\(separatorIndex)" : rawID
                    seenSeparators.insert(nextID)
                    sanitized.append(.separator(nextID))
                case .field(let field):
                    guard !seenFields.contains(field) else { continue }
                    seenFields.insert(field)
                    sanitized.append(.field(field))
                }
            }
            for field in TaskHoverField.allCases where !seenFields.contains(field) {
                sanitized.append(.field(field))
            }
            return sanitized
        }
        set {
            UserDefaults.standard.set(newValue.map(\.storageToken).joined(separator: ","), forKey: hoverLayoutKey)
        }
    }

    static var hoverHiddenItemIDs: Set<String> {
        get {
            guard let raw = UserDefaults.standard.string(forKey: hoverHiddenFieldsKey), !raw.isEmpty else {
                return []
            }
            return Set(raw.split(separator: ",").map(String.init))
        }
        set {
            UserDefaults.standard.set(newValue.sorted().joined(separator: ","), forKey: hoverHiddenFieldsKey)
        }
    }

    static func resetHoverLayout() {
        UserDefaults.standard.removeObject(forKey: hoverLayoutKey)
        UserDefaults.standard.removeObject(forKey: hoverHiddenFieldsKey)
    }

    static var rowLayout: TaskRowLayoutStyle {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: rowLayoutKey),
                  let style = TaskRowLayoutStyle(rawValue: rawValue) else {
                return .standard
            }
            return style
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: rowLayoutKey)
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

final class TaskBarSettingsWindowController: NSWindowController {
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
        window.contentMinSize = NSSize(width: 680, height: 620)
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

private enum TaskBarSettingsSection: CaseIterable {
    case settings
    case hover
    case about

    var title: String {
        switch self {
        case .settings: return "设置"
        case .hover: return "Hover"
        case .about: return "关于"
        }
    }
}

private enum TaskBarSettingsInfo: CaseIterable {
    case layout
    case tokenUnit

    var title: String {
        switch self {
        case .layout: return "信息位置"
        case .tokenUnit: return "Token 单位"
        }
    }

    var body: String {
        switch self {
        case .layout:
            return "选“左侧”把时间 / 状态 / 平台移到左栏，行更窄、可显示更多任务。"
        case .tokenUnit:
            return "只影响 hover 中的输入 / 输出等数字；缓存率和金额不变。"
        }
    }

    var tooltip: String {
        "\(title)\n\(body)"
    }
}

private final class TaskBarSettingsView: NSView {
    static let preferredSize = NSSize(width: 720, height: 660)

    private let onSettingsChanged: () -> Void
    private var selectedSection: TaskBarSettingsSection = .settings
    private var settingsTrackingArea: NSTrackingArea?
    private var sidebarItemRects: [TaskBarSettingsSection: NSRect] = [:]
    private var infoMarkRects: [TaskBarSettingsInfo: NSRect] = [:]
    private var hoveredInfo: TaskBarSettingsInfo?
    private var platformOptionRects: [Bool: NSRect] = [:]
    private var tokenUnitOptionRects: [TaskTokenUnitStyle: NSRect] = [:]
    private var layoutOptionRects: [TaskRowLayoutStyle: NSRect] = [:]
    private var hoverEyeRects: [String: NSRect] = [:]
    private var hoverDeleteSeparatorRects: [String: NSRect] = [:]
    private var hoverAddSeparatorRect: NSRect?
    private var hoverResetRect: NSRect?
    private var hoverListClipRect: NSRect = .zero
    private var hoverScrollOffset: CGFloat = 0

    // Drag-to-reorder state for the "All" status-order card.
    private let statusOrderRowHeight: CGFloat = 38
    private let statusOrderRowGap: CGFloat = 8
    private var statusOrderRowRects: [NSRect] = []
    private var statusOrderRowsTop: CGFloat = 0
    private var draggingGroup: TaskStatusGroup?
    private var liveOrder: [TaskStatusGroup] = []
    private var dragPointerY: CGFloat = 0
    private var dragGrabOffset: CGFloat = 0

    // Drag-to-reorder state for hover field layout.
    private let hoverOrderRowHeight: CGFloat = 30
    private let hoverOrderRowGap: CGFloat = 6
    private var hoverOrderRowRects: [NSRect] = []
    private var hoverOrderRowsTop: CGFloat = 0
    private var draggingHoverItem: TaskHoverLayoutItem?
    private var liveHoverLayout: [TaskHoverLayoutItem] = []
    private var hoverDragPointerY: CGFloat = 0
    private var hoverDragGrabOffset: CGFloat = 0

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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let settingsTrackingArea {
            removeTrackingArea(settingsTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        settingsTrackingArea = trackingArea
    }

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
        switch selectedSection {
        case .settings:
            drawSettingsPage(content: content)
        case .hover:
            drawHoverPage(content: content)
        case .about:
            drawAboutPage(content: content)
        }
    }

    private func drawSettingsPage(content: NSRect) {
        clearHoverHitRects()
        infoMarkRects.removeAll(keepingCapacity: true)
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

        let settingsCard = NSRect(x: content.minX, y: content.minY + 78, width: content.width, height: 186)
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

        let layoutStyles = TaskRowLayoutStyle.allCases
        let layoutPillY = settingsCard.minY + 48
        layoutOptionRects.removeAll(keepingCapacity: true)
        drawSettingLabel(
            "信息位置",
            rect: NSRect(x: settingsCard.minX + 16, y: layoutPillY + 7, width: binaryOptionX - settingsCard.minX - 32, height: 20),
            info: .layout
        )
        for (index, style) in layoutStyles.enumerated() {
            let optionRect = NSRect(
                x: binaryOptionX + CGFloat(index) * (binaryPillWidth + pillGap),
                y: layoutPillY,
                width: binaryPillWidth,
                height: pillHeight
            )
            layoutOptionRects[style] = optionRect
            drawSelectablePill(style.title, rect: optionRect, selected: TaskBarSettings.rowLayout == style)
        }

        let labelPillY = settingsCard.minY + 92
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

        let unitPillWidth: CGFloat = 82
        let unitStyles = TaskTokenUnitStyle.allCases
        let unitOptionX = settingsCard.maxX - 16 - unitPillWidth * CGFloat(unitStyles.count) - pillGap * CGFloat(unitStyles.count - 1)
        let unitPillY = settingsCard.minY + 136
        tokenUnitOptionRects.removeAll(keepingCapacity: true)
        drawSettingLabel(
            "Token 单位",
            rect: NSRect(x: settingsCard.minX + 16, y: unitPillY + 7, width: unitOptionX - settingsCard.minX - 32, height: 20),
            info: .tokenUnit
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

        let orderCard = NSRect(x: content.minX, y: settingsCard.maxY + 16, width: content.width, height: 208)
        drawStatusOrderCard(orderCard)

        if let hoveredInfo {
            drawInfoHoverCard(hoveredInfo)
        }
    }

    private func drawHoverPage(content: NSRect) {
        platformOptionRects.removeAll(keepingCapacity: true)
        tokenUnitOptionRects.removeAll(keepingCapacity: true)
        layoutOptionRects.removeAll(keepingCapacity: true)
        statusOrderRowRects.removeAll(keepingCapacity: true)
        infoMarkRects.removeAll(keepingCapacity: true)
        clearHoverHitRects()

        drawText(
            "Hover 字段",
            rect: NSRect(x: content.minX, y: content.minY, width: content.width, height: 34),
            font: .systemFont(ofSize: 26, weight: .bold),
            color: .white
        )
        drawText(
            "字段显隐、顺序和分隔线",
            rect: NSRect(x: content.minX, y: content.minY + 36, width: content.width, height: 20),
            font: .systemFont(ofSize: 13, weight: .medium),
            color: NSColor.white.withAlphaComponent(0.56)
        )

        let card = NSRect(x: content.minX, y: content.minY + 78, width: content.width, height: content.height - 78)
        drawPanel(card)
        let resetRect = NSRect(x: card.maxX - 108, y: card.minY + 16, width: 92, height: 30)
        let addRect = NSRect(x: resetRect.minX - 84, y: card.minY + 16, width: 72, height: 30)
        hoverAddSeparatorRect = addRect
        hoverResetRect = resetRect
        drawText(
            "Hover 内容",
            rect: NSRect(x: card.minX + 16, y: card.minY + 17, width: addRect.minX - card.minX - 28, height: 22),
            font: .systemFont(ofSize: 16, weight: .bold),
            color: .white
        )
        drawSmallButton("+ 横线", rect: addRect, emphasized: true)
        drawSmallButton("恢复默认", rect: resetRect, emphasized: false)

        drawHoverLayoutRows(in: card)
    }

    private func drawAboutPage(content: NSRect) {
        platformOptionRects.removeAll(keepingCapacity: true)
        tokenUnitOptionRects.removeAll(keepingCapacity: true)
        layoutOptionRects.removeAll(keepingCapacity: true)
        statusOrderRowRects.removeAll(keepingCapacity: true)
        clearHoverHitRects()

        drawText(
            "关于 Task Bar",
            rect: NSRect(x: content.minX, y: content.minY, width: content.width, height: 34),
            font: .systemFont(ofSize: 26, weight: .bold),
            color: .white
        )
        drawText(
            "任务状态、排序和本地数据说明",
            rect: NSRect(x: content.minX, y: content.minY + 36, width: content.width, height: 20),
            font: .systemFont(ofSize: 13, weight: .medium),
            color: NSColor.white.withAlphaComponent(0.56)
        )

        let statusCard = NSRect(x: content.minX, y: content.minY + 78, width: content.width, height: 126)
        drawPanel(statusCard)
        drawText(
            "状态约定",
            rect: NSRect(x: statusCard.minX + 18, y: statusCard.minY + 20, width: statusCard.width - 36, height: 26),
            font: .systemFont(ofSize: 19, weight: .bold),
            color: .white
        )
        drawStatusLegend(
            items: statusLegendItems(),
            rect: NSRect(x: statusCard.minX + 18, y: statusCard.minY + 68, width: statusCard.width - 36, height: 42)
        )

        let dataCard = NSRect(x: content.minX, y: statusCard.maxY + 16, width: content.width, height: 126)
        drawPanel(dataCard)
        drawText(
            "数据来源",
            rect: NSRect(x: dataCard.minX + 18, y: dataCard.minY + 20, width: dataCard.width - 36, height: 24),
            font: .systemFont(ofSize: 17, weight: .bold),
            color: .white
        )
        drawText(
            "Task Bar 读取本机 Codex 会话和 Claude Code 项目日志，只在本地整理任务状态。",
            rect: NSRect(x: dataCard.minX + 18, y: dataCard.minY + 58, width: dataCard.width - 36, height: 18),
            font: .systemFont(ofSize: 12.5, weight: .medium),
            color: NSColor.white.withAlphaComponent(0.62)
        )
        drawText(
            "状态、顺序和布局偏好保存在本机 UserDefaults，不上传会话内容。",
            rect: NSRect(x: dataCard.minX + 18, y: dataCard.minY + 82, width: dataCard.width - 36, height: 18),
            font: .systemFont(ofSize: 12.5, weight: .medium),
            color: NSColor.white.withAlphaComponent(0.52)
        )
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for (section, rect) in sidebarItemRects where rect.contains(point) {
            guard selectedSection != section else { return }
            selectedSection = section
            draggingGroup = nil
            draggingHoverItem = nil
            hoveredInfo = nil
            toolTip = nil
            needsDisplay = true
            return
        }
        if selectedSection == .hover {
            handleHoverMouseDown(at: point)
            return
        }
        guard selectedSection == .settings else {
            super.mouseDown(with: event)
            return
        }
        for (style, rect) in layoutOptionRects where rect.contains(point) {
            guard TaskBarSettings.rowLayout != style else { return }
            TaskBarSettings.rowLayout = style
            needsDisplay = true
            onSettingsChanged()
            return
        }
        for (showLabels, rect) in platformOptionRects where rect.contains(point) {
            guard TaskBarSettings.showPlatformLabels != showLabels else { return }
            TaskBarSettings.showPlatformLabels = showLabels
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
        for (index, rect) in statusOrderRowRects.enumerated() where rect.contains(point) {
            let order = TaskBarSettings.statusGroupOrder
            guard index < order.count else { break }
            liveOrder = order
            draggingGroup = order[index]
            dragPointerY = point.y
            dragGrabOffset = point.y - rect.minY
            needsDisplay = true
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let nextInfo = selectedSection == .settings
            ? infoMarkRects.first(where: { $0.value.contains(point) })?.key
            : nil
        guard nextInfo != hoveredInfo else { return }
        hoveredInfo = nextInfo
        toolTip = nextInfo?.tooltip
        (nextInfo == nil ? NSCursor.arrow : NSCursor.pointingHand).set()
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoveredInfo = nil
        toolTip = nil
        NSCursor.arrow.set()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        if selectedSection == .hover, draggingHoverItem != nil {
            hoverDragPointerY = convert(event.locationInWindow, from: nil).y
            reflowLiveHoverLayoutForDrag()
            needsDisplay = true
            return
        }
        guard selectedSection == .settings, draggingGroup != nil else {
            super.mouseDragged(with: event)
            return
        }
        dragPointerY = convert(event.locationInWindow, from: nil).y
        reflowLiveOrderForDrag()
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        guard selectedSection == .hover, hoverListClipRect.height > 1 else {
            super.scrollWheel(with: event)
            return
        }
        let maxOffset = maxHoverScrollOffset()
        guard maxOffset > 0 else {
            super.scrollWheel(with: event)
            return
        }
        let direction: CGFloat = event.isDirectionInvertedFromDevice ? -1 : 1
        hoverScrollOffset = min(max(hoverScrollOffset + event.scrollingDeltaY * direction, 0), maxOffset)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if selectedSection == .hover, draggingHoverItem != nil {
            let newLayout = liveHoverLayout
            draggingHoverItem = nil
            if newLayout != TaskBarSettings.hoverLayout {
                TaskBarSettings.hoverLayout = newLayout
                onSettingsChanged()
            }
            needsDisplay = true
            return
        }
        guard selectedSection == .settings, draggingGroup != nil else {
            super.mouseUp(with: event)
            return
        }
        let newOrder = liveOrder
        draggingGroup = nil
        if newOrder != TaskBarSettings.statusGroupOrder {
            TaskBarSettings.statusGroupOrder = newOrder
            onSettingsChanged()
        }
        needsDisplay = true
    }

    private func handleHoverMouseDown(at point: NSPoint) {
        if hoverAddSeparatorRect?.contains(point) == true {
            var layout = TaskBarSettings.hoverLayout
            layout.append(.separator("custom-\(UUID().uuidString)"))
            TaskBarSettings.hoverLayout = layout
            hoverScrollOffset = maxHoverScrollOffset(layout: layout)
            needsDisplay = true
            onSettingsChanged()
            return
        }
        if hoverResetRect?.contains(point) == true {
            TaskBarSettings.resetHoverLayout()
            hoverScrollOffset = 0
            needsDisplay = true
            onSettingsChanged()
            return
        }
        for (key, rect) in hoverEyeRects where hoverListClipRect.contains(point) && rect.contains(point) {
            var hiddenItems = TaskBarSettings.hoverHiddenItemIDs
            if hiddenItems.contains(key) {
                hiddenItems.remove(key)
            } else {
                hiddenItems.insert(key)
            }
            TaskBarSettings.hoverHiddenItemIDs = hiddenItems
            needsDisplay = true
            onSettingsChanged()
            return
        }
        for (key, rect) in hoverDeleteSeparatorRects where hoverListClipRect.contains(point) && rect.contains(point) {
            var layout = TaskBarSettings.hoverLayout
            layout.removeAll { item in
                if case .separator = item {
                    return item.visibilityKey == key
                }
                return false
            }
            var hiddenItems = TaskBarSettings.hoverHiddenItemIDs
            hiddenItems.remove(key)
            TaskBarSettings.hoverLayout = layout
            TaskBarSettings.hoverHiddenItemIDs = hiddenItems
            hoverScrollOffset = min(hoverScrollOffset, maxHoverScrollOffset(layout: layout))
            needsDisplay = true
            onSettingsChanged()
            return
        }
        guard hoverListClipRect.contains(point) else { return }
        let layout = TaskBarSettings.hoverLayout
        for (index, rect) in hoverOrderRowRects.enumerated() where rect.contains(point) {
            guard index < layout.count else { break }
            liveHoverLayout = layout
            draggingHoverItem = layout[index]
            hoverDragPointerY = point.y
            hoverDragGrabOffset = point.y - rect.minY
            needsDisplay = true
            return
        }
    }

    /// Moves the grabbed group to whichever slot the pointer is currently hovering over.
    private func reflowLiveOrderForDrag() {
        guard let group = draggingGroup, let currentIndex = liveOrder.firstIndex(of: group) else { return }
        let step = statusOrderRowHeight + statusOrderRowGap
        let draggedCenter = (dragPointerY - dragGrabOffset) + statusOrderRowHeight / 2
        var target = Int(((draggedCenter - statusOrderRowsTop) / step).rounded())
        target = min(max(target, 0), liveOrder.count - 1)
        guard target != currentIndex else { return }
        liveOrder.remove(at: currentIndex)
        liveOrder.insert(group, at: target)
    }

    private func reflowLiveHoverLayoutForDrag() {
        guard let item = draggingHoverItem, let currentIndex = liveHoverLayout.firstIndex(of: item) else { return }
        let step = hoverOrderRowHeight + hoverOrderRowGap
        let draggedCenter = (hoverDragPointerY - hoverDragGrabOffset) + hoverOrderRowHeight / 2
        var target = Int(((draggedCenter - hoverOrderRowsTop) / step).rounded())
        target = min(max(target, 0), liveHoverLayout.count - 1)
        guard target != currentIndex else { return }
        liveHoverLayout.remove(at: currentIndex)
        liveHoverLayout.insert(item, at: target)
    }

    private func maxHoverScrollOffset(layout: [TaskHoverLayoutItem]? = nil) -> CGFloat {
        let itemCount = layout?.count ?? TaskBarSettings.hoverLayout.count
        guard itemCount > 0, hoverListClipRect.height > 1 else { return 0 }
        let contentHeight = CGFloat(itemCount) * hoverOrderRowHeight + CGFloat(max(0, itemCount - 1)) * hoverOrderRowGap
        return max(0, contentHeight - hoverListClipRect.height)
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

        sidebarItemRects.removeAll(keepingCapacity: true)
        for (index, section) in TaskBarSettingsSection.allCases.enumerated() {
            let itemRect = NSRect(x: 18, y: 118 + CGFloat(index) * 52, width: width - 36, height: 42)
            sidebarItemRects[section] = itemRect
            if section == selectedSection {
                accentBlue.withAlphaComponent(0.82).setFill()
                NSBezierPath(roundedRect: itemRect, xRadius: 8, yRadius: 8).fill()
                NSColor.white.withAlphaComponent(0.08).setStroke()
                NSBezierPath(roundedRect: itemRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
            }
            drawText(
                section.title,
                rect: NSRect(x: itemRect.minX + 22, y: itemRect.minY + 10, width: itemRect.width - 44, height: 22),
                font: .systemFont(ofSize: 15, weight: .semibold),
                color: section == selectedSection ? .white : NSColor.white.withAlphaComponent(0.72)
            )
        }
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

    private func drawSettingLabel(_ title: String, rect: NSRect, info: TaskBarSettingsInfo) {
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        drawText(title, rect: rect, font: font, color: .white)
        let titleWidth = min(rect.width - 20, measuredTextWidth(title, font: font))
        let iconRect = NSRect(x: rect.minX + titleWidth + 7, y: rect.minY + 2, width: 16, height: 16)
        infoMarkRects[info] = iconRect
        drawInfoMark(rect: iconRect, highlighted: hoveredInfo == info)
    }

    private func drawInfoMark(rect: NSRect, highlighted: Bool) {
        (highlighted ? accentTeal.withAlphaComponent(0.28) : NSColor.white.withAlphaComponent(0.10)).setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
        (highlighted ? accentTeal.withAlphaComponent(0.74) : NSColor.white.withAlphaComponent(0.18)).setStroke()
        NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5)).stroke()
        drawCentered(
            "?",
            rect: rect.offsetBy(dx: 0, dy: -0.5),
            font: .systemFont(ofSize: 10, weight: .bold),
            color: highlighted ? accentTeal : NSColor.white.withAlphaComponent(0.58)
        )
    }

    private func drawInfoHoverCard(_ info: TaskBarSettingsInfo) {
        guard let sourceRect = infoMarkRects[info] else { return }
        let cardWidth = min(CGFloat(308), bounds.width - 44)
        let textWidth = cardWidth - 28
        let titleFont = NSFont.systemFont(ofSize: 12.5, weight: .bold)
        let bodyFont = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        let bodyHeight = measuredWrappedTextHeight(info.body, width: textWidth, font: bodyFont)
        let cardHeight = max(CGFloat(78), 14 + 16 + 6 + bodyHeight + 14)

        var cardX = sourceRect.maxX + 12
        if cardX + cardWidth > bounds.maxX - 18 {
            cardX = sourceRect.minX - cardWidth - 12
        }
        cardX = min(max(cardX, bounds.minX + 18), bounds.maxX - cardWidth - 18)

        var cardY = sourceRect.minY - 18
        if cardY + cardHeight > bounds.maxY - 18 {
            cardY = bounds.maxY - cardHeight - 18
        }
        cardY = max(cardY, bounds.minY + 18)

        let card = NSRect(x: cardX, y: cardY, width: cardWidth, height: cardHeight)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.34)
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -5)
        shadow.set()
        NSColor(calibratedRed: 0.070, green: 0.085, blue: 0.112, alpha: 0.98).setFill()
        NSBezierPath(roundedRect: card, xRadius: 8, yRadius: 8).fill()
        NSGraphicsContext.restoreGraphicsState()

        accentTeal.withAlphaComponent(0.30).setStroke()
        NSBezierPath(roundedRect: card.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
        accentTeal.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: NSRect(x: card.minX, y: card.minY + 12, width: 3, height: card.height - 24), xRadius: 1.5, yRadius: 1.5).fill()

        drawText(
            info.title,
            rect: NSRect(x: card.minX + 14, y: card.minY + 12, width: textWidth, height: 16),
            font: titleFont,
            color: .white
        )
        drawWrappedText(
            info.body,
            rect: NSRect(x: card.minX + 14, y: card.minY + 34, width: textWidth, height: bodyHeight),
            font: bodyFont,
            color: NSColor.white.withAlphaComponent(0.68)
        )
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

    private func statusLegendItems() -> [(String, String, NSColor)] {
        [
            ("RUN", "运行中", NSColor.systemGreen),
            ("REVIEW", "待检查", NSColor.systemBlue),
            ("INPUT", "待输入", NSColor.systemOrange),
            ("DONE", "已完成", NSColor.white.withAlphaComponent(0.45))
        ]
    }

    private func drawStatusOrderCard(_ card: NSRect) {
        drawPanel(card)
        drawText(
            "「全部」列表顺序",
            rect: NSRect(x: card.minX + 16, y: card.minY + 16, width: card.width - 32, height: 22),
            font: .systemFont(ofSize: 16, weight: .bold),
            color: .white
        )
        drawText(
            "拖动分组，调整「全部」标签下任务的先后顺序（靠上＝靠前）。",
            rect: NSRect(x: card.minX + 16, y: card.minY + 42, width: card.width - 32, height: 18),
            font: .systemFont(ofSize: 12, weight: .medium),
            color: NSColor.white.withAlphaComponent(0.52)
        )
        drawStatusOrderRows(in: card)
    }

    private func drawHoverLayoutRows(in card: NSRect) {
        let layout = draggingHoverItem != nil ? liveHoverLayout : TaskBarSettings.hoverLayout
        let hiddenItems = TaskBarSettings.hoverHiddenItemIDs
        let rowX = card.minX + 16
        let rowW = card.width - 32
        let rowsTop = card.minY + 58
        hoverListClipRect = NSRect(
            x: rowX,
            y: rowsTop,
            width: rowW,
            height: max(0, card.maxY - rowsTop - 14)
        )
        hoverScrollOffset = min(hoverScrollOffset, maxHoverScrollOffset(layout: layout))
        hoverOrderRowsTop = rowsTop - hoverScrollOffset
        let step = hoverOrderRowHeight + hoverOrderRowGap
        hoverOrderRowRects = layout.indices.map { index in
            NSRect(x: rowX, y: rowsTop - hoverScrollOffset + CGFloat(index) * step, width: rowW, height: hoverOrderRowHeight)
        }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: hoverListClipRect).addClip()
        for (index, item) in layout.enumerated() where item != draggingHoverItem {
            guard hoverOrderRowRects[index].intersects(hoverListClipRect) else { continue }
            drawHoverLayoutRow(
                item,
                rect: hoverOrderRowRects[index],
                position: index + 1,
                hidden: hiddenItems.contains(item.visibilityKey),
                floating: false
            )
        }
        if let item = draggingHoverItem, let index = layout.firstIndex(of: item) {
            let minTop = hoverListClipRect.minY
            let maxTop = hoverListClipRect.maxY - hoverOrderRowHeight
            let floatTop = min(max(hoverDragPointerY - hoverDragGrabOffset, minTop), maxTop)
            let floatRect = NSRect(x: rowX, y: floatTop, width: rowW, height: hoverOrderRowHeight)
            drawHoverLayoutRow(
                item,
                rect: floatRect,
                position: index + 1,
                hidden: hiddenItems.contains(item.visibilityKey),
                floating: true
            )
        }
        NSGraphicsContext.restoreGraphicsState()

        if maxHoverScrollOffset(layout: layout) > 0 {
            drawHoverScrollbar(in: hoverListClipRect, layoutCount: layout.count)
        }
    }

    private func clearHoverHitRects() {
        hoverEyeRects.removeAll(keepingCapacity: true)
        hoverDeleteSeparatorRects.removeAll(keepingCapacity: true)
        hoverOrderRowRects.removeAll(keepingCapacity: true)
        hoverAddSeparatorRect = nil
        hoverResetRect = nil
        hoverListClipRect = .zero
    }

    private func drawHoverLayoutRow(_ item: TaskHoverLayoutItem, rect: NSRect, position: Int, hidden: Bool, floating: Bool) {
        (floating ? accentBlue.withAlphaComponent(0.24) : inputSurfaceColor.withAlphaComponent(hidden ? 0.42 : 0.82)).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        (floating ? accentTeal.withAlphaComponent(0.5) : borderColor).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()

        let textY = rect.minY + (rect.height - 16) / 2
        drawText(
            "\(position)",
            rect: NSRect(x: rect.minX + 14, y: textY, width: 20, height: 16),
            font: .systemFont(ofSize: 12, weight: .bold),
            color: NSColor.white.withAlphaComponent(hidden ? 0.24 : 0.42)
        )

        let titleColor = NSColor.white.withAlphaComponent(hidden ? 0.36 : 0.84)
        switch item {
        case .field(let field):
            drawText(
                field.title,
                rect: NSRect(x: rect.minX + 46, y: textY, width: rect.width - 150, height: 16),
                font: .systemFont(ofSize: 12.5, weight: .semibold),
                color: titleColor
            )
        case .separator:
            drawText(
                "横线",
                rect: NSRect(x: rect.minX + 46, y: textY, width: 48, height: 16),
                font: .systemFont(ofSize: 12.5, weight: .semibold),
                color: titleColor
            )
            NSColor.white.withAlphaComponent(hidden ? 0.08 : 0.18).setFill()
            NSRect(x: rect.minX + 96, y: rect.midY, width: rect.width - 210, height: 1).fill()
            let deleteRect = NSRect(x: rect.maxX - 108, y: rect.minY + 4, width: 28, height: rect.height - 8)
            hoverDeleteSeparatorRects[item.visibilityKey] = deleteRect
            drawDeleteIcon(in: deleteRect, highlighted: floating)
        }

        let eyeRect = NSRect(x: rect.maxX - 76, y: rect.minY + 4, width: 28, height: rect.height - 8)
        hoverEyeRects[item.visibilityKey] = eyeRect
        drawEyeIcon(in: eyeRect, visible: !hidden, highlighted: floating)
        drawDragHandle(in: NSRect(x: rect.maxX - 38, y: rect.minY, width: 38, height: rect.height))
    }

    private func drawDeleteIcon(in rect: NSRect, highlighted: Bool) {
        let buttonRect = rect.insetBy(dx: 4, dy: 3)
        NSColor.white.withAlphaComponent(highlighted ? 0.24 : 0.16).setFill()
        NSBezierPath(roundedRect: buttonRect, xRadius: 8, yRadius: 8).fill()
        NSColor.white.withAlphaComponent(highlighted ? 0.46 : 0.30).setStroke()
        let outline = NSBezierPath(roundedRect: buttonRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        outline.lineWidth = 1
        outline.stroke()

        NSColor.white.withAlphaComponent(highlighted ? 0.98 : 0.90).setStroke()
        let iconRect = buttonRect.insetBy(dx: 6.5, dy: 5.5)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: iconRect.minX, y: iconRect.minY))
        path.line(to: NSPoint(x: iconRect.maxX, y: iconRect.maxY))
        path.move(to: NSPoint(x: iconRect.maxX, y: iconRect.minY))
        path.line(to: NSPoint(x: iconRect.minX, y: iconRect.maxY))
        path.lineWidth = 2
        path.lineCapStyle = .round
        path.stroke()
    }

    private func drawEyeIcon(in rect: NSRect, visible: Bool, highlighted: Bool) {
        let eyeColor = NSColor.white.withAlphaComponent(visible ? (highlighted ? 0.90 : 0.78) : 0.34)
        let drawRect = rect.insetBy(dx: 5, dy: 4)
        if let image = NSImage(systemSymbolName: "eye", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13.5, weight: .semibold)) {
            image.isTemplate = true
            eyeColor.set()
            image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            eyeColor.setStroke()
            let fallback = NSBezierPath(ovalIn: rect.insetBy(dx: 5, dy: 6))
            fallback.lineWidth = 1.2
            fallback.stroke()
        }
        guard !visible else {
            return
        }
        NSColor.white.withAlphaComponent(0.68).setStroke()
        let slash = NSBezierPath()
        slash.move(to: NSPoint(x: drawRect.minX + 1, y: drawRect.maxY - 1))
        slash.line(to: NSPoint(x: drawRect.maxX - 1, y: drawRect.minY + 1))
        slash.lineWidth = 2
        slash.stroke()
    }

    private func drawHoverScrollbar(in rect: NSRect, layoutCount: Int) {
        let maxOffset = maxHoverScrollOffset(layout: TaskBarSettings.hoverLayout)
        guard maxOffset > 0 else { return }
        let contentHeight = CGFloat(layoutCount) * hoverOrderRowHeight + CGFloat(max(0, layoutCount - 1)) * hoverOrderRowGap
        let thumbHeight = max(32, rect.height * rect.height / max(contentHeight, rect.height))
        let travel = max(1, rect.height - thumbHeight)
        let thumbY = rect.minY + travel * (hoverScrollOffset / maxOffset)
        NSColor.white.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: NSRect(x: rect.maxX - 4, y: rect.minY + 2, width: 2, height: rect.height - 4), xRadius: 1, yRadius: 1).fill()
        NSColor.white.withAlphaComponent(0.34).setFill()
        NSBezierPath(roundedRect: NSRect(x: rect.maxX - 5, y: thumbY, width: 3, height: thumbHeight), xRadius: 1.5, yRadius: 1.5).fill()
    }

    /// Draws the three draggable rows. During a drag the settled rows follow `liveOrder`
    /// while the grabbed row floats under the pointer, on top of the others.
    private func drawStatusOrderRows(in card: NSRect) {
        let order = draggingGroup != nil ? liveOrder : TaskBarSettings.statusGroupOrder
        let rowsTop = card.minY + 72
        statusOrderRowsTop = rowsTop
        let rowX = card.minX + 16
        let rowW = card.width - 32
        let step = statusOrderRowHeight + statusOrderRowGap
        statusOrderRowRects = order.indices.map { index in
            NSRect(x: rowX, y: rowsTop + CGFloat(index) * step, width: rowW, height: statusOrderRowHeight)
        }
        for (index, group) in order.enumerated() where group != draggingGroup {
            drawStatusOrderRow(group, rect: statusOrderRowRects[index], position: index + 1, floating: false)
        }
        if let group = draggingGroup, let index = order.firstIndex(of: group) {
            let maxTop = rowsTop + CGFloat(order.count - 1) * step
            let floatTop = min(max(dragPointerY - dragGrabOffset, rowsTop), maxTop)
            let floatRect = NSRect(x: rowX, y: floatTop, width: rowW, height: statusOrderRowHeight)
            drawStatusOrderRow(group, rect: floatRect, position: index + 1, floating: true)
        }
    }

    private func drawStatusOrderRow(_ group: TaskStatusGroup, rect: NSRect, position: Int, floating: Bool) {
        (floating ? accentBlue.withAlphaComponent(0.24) : inputSurfaceColor.withAlphaComponent(0.82)).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        (floating ? accentTeal.withAlphaComponent(0.5) : borderColor).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()

        let textY = rect.minY + (rect.height - 16) / 2
        drawText(
            "\(position)",
            rect: NSRect(x: rect.minX + 14, y: textY, width: 14, height: 16),
            font: .systemFont(ofSize: 12.5, weight: .bold),
            color: NSColor.white.withAlphaComponent(0.42)
        )

        let dotSize: CGFloat = 9
        let dotRect = NSRect(x: rect.minX + 36, y: rect.midY - dotSize / 2, width: dotSize, height: dotSize)
        group.accentColor.setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        drawText(
            group.badge,
            rect: NSRect(x: rect.minX + 54, y: textY, width: 54, height: 16),
            font: .systemFont(ofSize: 11.5, weight: .bold),
            color: group.accentColor
        )
        drawText(
            group.displayName,
            rect: NSRect(x: rect.minX + 106, y: textY, width: rect.width - 150, height: 16),
            font: .systemFont(ofSize: 12.5, weight: .semibold),
            color: NSColor.white.withAlphaComponent(0.82)
        )

        drawDragHandle(in: NSRect(x: rect.maxX - 38, y: rect.minY, width: 38, height: rect.height))
    }

    /// A 2×3 grid of dots signalling the row is draggable.
    private func drawDragHandle(in rect: NSRect) {
        let dot: CGFloat = 2.6
        let colGap: CGFloat = 5
        let rowGap: CGFloat = 5
        let cols = 2
        let rows = 3
        let startX = rect.midX - (CGFloat(cols - 1) * colGap) / 2 - dot / 2
        let startY = rect.midY - (CGFloat(rows - 1) * rowGap) / 2 - dot / 2
        NSColor.white.withAlphaComponent(0.32).setFill()
        for r in 0..<rows {
            for c in 0..<cols {
                let dotRect = NSRect(x: startX + CGFloat(c) * colGap, y: startY + CGFloat(r) * rowGap, width: dot, height: dot)
                NSBezierPath(ovalIn: dotRect).fill()
            }
        }
    }

    private func drawText(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color])
    }

    private func measuredTextWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private func measuredWrappedTextHeight(_ text: String, width: CGFloat, font: NSFont) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        return ceil((text as NSString).boundingRect(
            with: NSSize(width: width, height: 1000),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: font, .paragraphStyle: paragraph]
        ).height)
    }

    private func drawWrappedText(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 2
        (text as NSString).draw(
            in: rect,
            withAttributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
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
