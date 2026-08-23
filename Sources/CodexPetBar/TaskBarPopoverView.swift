import Cocoa
import Foundation

final class PopoverResizeHandleView: NSView {
    var onResize: ((NSSize, Bool) -> Void)?

    private var startMouse = NSPoint.zero
    private var startSize = NSSize.zero
    private var lastSize = NSSize.zero
    private var didDrag = false

    override var isFlipped: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        ThreadHoverPanel.shared.hideAll()
        startMouse = NSEvent.mouseLocation
        startSize = superview?.bounds.size ?? bounds.size
        lastSize = startSize
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        let currentMouse = NSEvent.mouseLocation
        let nextSize = NSSize(
            width: startSize.width + currentMouse.x - startMouse.x,
            height: startSize.height + startMouse.y - currentMouse.y
        )
        lastSize = TaskBarSettings.clampedPopoverSize(nextSize)
        didDrag = true
        onResize?(lastSize, false)
    }

    override func mouseUp(with event: NSEvent) {
        guard didDrag else { return }
        onResize?(lastSize, true)
    }
}

final class TaskBarPopoverContentView: NSView {
    private let headerView: PanelHeaderView
    private let tabsView: TaskBarTabsView
    private let topSeparator = MenuSeparatorView()
    private var rowsView: TaskBarRowsView
    private let rowsScrollView: NSScrollView
    private let taskCountView: TaskCountView
    private let taskCountHeight: CGFloat
    private let bottomSeparator = MenuSeparatorView()
    private let commandBar: CommandButtonBarView
    private let resizeHandle = PopoverResizeHandleView()
    private var rowsContentHeight: CGFloat
    private let onResize: (NSSize, Bool) -> Void
    private let shouldAnimateEntrance: Bool
    private let usesExternalSurface: Bool
    private var didAnimateEntrance = false

    // Retained so the tab filter can be re-applied in place, without a full rebuild.
    private let allThreads: [CodexThreadItem]
    private let totalCount: Int
    private let showPlatformLabels: Bool
    private let rowLayout: TaskRowLayoutStyle
    private let onOpenThread: (String) -> Void
    private let onDismissThread: (String) -> Void
    private let onTogglePin: (String) -> Void
    private let manualReorderEnabled: Bool
    private let onSetSubtasksExpanded: (String, Bool) -> Void
    private let externalSelectTab: (TaskBarTab) -> Void
    private var selectedTab: TaskBarTab
    private var expandedThreadIDs: Set<String>

    init(
        threads: [CodexThreadItem],
        runningCount: Int,
        waitingCount: Int,
        unreadCount: Int,
        selectedTab: TaskBarTab,
        showPlatformLabels: Bool,
        rowLayout: TaskRowLayoutStyle,
        onOpenThread: @escaping (String) -> Void,
        onDismissThread: @escaping (String) -> Void,
        onTogglePin: @escaping (String) -> Void,
        collapsedThreadIDs: Set<String>,
        onSetSubtasksExpanded: @escaping (String, Bool) -> Void,
        onSelectTab: @escaping (TaskBarTab) -> Void,
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void,
        initialSize: NSSize?,
        shouldAnimateEntrance: Bool = false,
        usesExternalSurface: Bool = false,
        onResize: @escaping (NSSize, Bool) -> Void
    ) {
        self.onResize = onResize
        self.shouldAnimateEntrance = shouldAnimateEntrance
        self.usesExternalSurface = usesExternalSurface
        self.allThreads = threads
        self.showPlatformLabels = showPlatformLabels
        self.rowLayout = rowLayout
        self.onOpenThread = onOpenThread
        self.onDismissThread = onDismissThread
        self.onTogglePin = onTogglePin
        self.manualReorderEnabled = TaskBarSettings.threadSortMode == .manual
        self.onSetSubtasksExpanded = onSetSubtasksExpanded
        self.externalSelectTab = onSelectTab
        self.selectedTab = selectedTab
        let parentIDs = Set(threads.compactMap { $0.isSubtask ? $0.parentThreadID : nil })
        self.expandedThreadIDs = parentIDs.subtracting(collapsedThreadIDs)

        headerView = PanelHeaderView(
            runningCount: runningCount,
            waitingCount: waitingCount,
            unreadCount: unreadCount
        )
        tabsView = TaskBarTabsView(tabs: TaskBarTab.allCases, selected: selectedTab, onSelect: { _ in })

        let total = runningCount + waitingCount + unreadCount
        totalCount = total
        let filtered = threads.primaryThreads.filter { selectedTab.matches($0.status) }
        taskCountView = TaskCountView(shown: filtered.count, total: total)
        // "N of M tasks" footer removed: uninformative next to the header chips.
        taskCountView.isHidden = true
        taskCountHeight = 0

        var initialToggleHandler: ((String) -> Void)?
        var initialManualDragHandler: ((String, TaskThreadManualDragPhase, NSPoint) -> Void)?
        let rowViews = TaskBarPopoverContentView.makeRowViews(
            allThreads: threads,
            filteredRoots: filtered,
            selectedTab: selectedTab,
            expandedThreadIDs: expandedThreadIDs,
            showPlatformLabels: showPlatformLabels,
            rowLayout: rowLayout,
            onOpenThread: onOpenThread,
            onDismissThread: onDismissThread,
            onTogglePin: onTogglePin,
            onToggleSubtasks: { id in initialToggleHandler?(id) },
            manualReorderEnabled: manualReorderEnabled,
            onManualReorderDrag: { id, phase, point in initialManualDragHandler?(id, phase, point) }
        )
        rowsView = TaskBarRowsView(
            rowViews: rowViews,
            manualReorderEnabled: manualReorderEnabled,
            onManualOrderCommitted: TaskBarSettings.setManualThreadOrder
        )
        rowsContentHeight = rowsView.frame.height
        commandBar = CommandButtonBarView(
            onOpenSettings: onOpenSettings,
            onQuit: onQuit
        )

        let navigationChromeHeight = usesExternalSurface ? 0 : (
            headerView.frame.height
            + tabsView.frame.height
            + topSeparator.frame.height
        )
        let fixedHeight = navigationChromeHeight
            + taskCountHeight
            + bottomSeparator.frame.height
            + commandBar.frame.height
        let maxRowsHeight = max(taskBarEmptyStateHeight, taskBarPopoverMaxHeight() - fixedHeight)
        let naturalRowsHeight = min(rowsContentHeight, maxRowsHeight)
        let naturalHeight = fixedHeight + naturalRowsHeight
        let naturalSize = NSSize(width: menuPanelWidth, height: naturalHeight)
        let initialSize = TaskBarSettings.clampedPopoverSize(initialSize ?? naturalSize)

        let scrollView = NSScrollView(frame: .zero)
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = rowsView
        rowsScrollView = scrollView

        super.init(frame: NSRect(origin: .zero, size: initialSize))
        wantsLayer = true
        let classic = TaskBarBuild.isClassicPage
        layer?.backgroundColor = (classic ? menuPanelBackground : NSColor.clear).cgColor
        layer?.cornerRadius = usesExternalSurface || classic ? 0 : 20
        layer?.masksToBounds = !usesExternalSurface && !classic
        appearance = NSAppearance(named: .darkAqua)

        addSubview(headerView)
        addSubview(tabsView)
        addSubview(topSeparator)
        addSubview(rowsScrollView)
        addSubview(taskCountView)
        addSubview(bottomSeparator)
        addSubview(commandBar)
        addSubview(resizeHandle)
        headerView.isHidden = usesExternalSurface
        tabsView.isHidden = usesExternalSurface
        topSeparator.isHidden = usesExternalSurface
        resizeHandle.onResize = { [weak self] size, persist in
            self?.applyResize(size, persist: persist)
        }
        tabsView.onSelect = { [weak self] tab in
            self?.selectTab(tab)
        }
        initialToggleHandler = { [weak self] id in
            self?.toggleSubtasks(for: id)
        }
        initialManualDragHandler = { [weak self] id, phase, point in
            self?.rowsView.handleManualReorderDrag(id: id, phase: phase, windowPoint: point)
        }
    }

    /// Re-filter and swap the list rows in place, keeping the surrounding chrome
    /// (header, tabs, footer) and the popover size stable so switching tabs never flashes.
    private func selectTab(_ tab: TaskBarTab) {
        guard tab != selectedTab else { return }
        selectedTab = tab
        externalSelectTab(tab)

        rebuildRows(for: tab)
    }

    private func rebuildRows(for tab: TaskBarTab) {
        let filtered = allThreads.primaryThreads.filter { tab.matches($0.status) }
        let rowViews = TaskBarPopoverContentView.makeRowViews(
            allThreads: allThreads,
            filteredRoots: filtered,
            selectedTab: tab,
            expandedThreadIDs: expandedThreadIDs,
            showPlatformLabels: showPlatformLabels,
            rowLayout: rowLayout,
            onOpenThread: onOpenThread,
            onDismissThread: onDismissThread,
            onTogglePin: onTogglePin,
            onToggleSubtasks: { [weak self] id in
                self?.toggleSubtasks(for: id)
            },
            manualReorderEnabled: manualReorderEnabled,
            onManualReorderDrag: { [weak self] id, phase, point in
                self?.rowsView.handleManualReorderDrag(id: id, phase: phase, windowPoint: point)
            }
        )
        let newRowsView = TaskBarRowsView(
            rowViews: rowViews,
            manualReorderEnabled: manualReorderEnabled,
            onManualOrderCommitted: TaskBarSettings.setManualThreadOrder
        )
        rowsView = newRowsView
        rowsContentHeight = newRowsView.frame.height
        rowsScrollView.documentView = newRowsView
        taskCountView.update(shown: filtered.count, total: totalCount)
        needsLayout = true
        layoutSubtreeIfNeeded()
        if !TaskBarBuild.isClassicPage {
            DispatchQueue.main.async {
                newRowsView.animateRefresh()
            }
        }
    }

    private func toggleSubtasks(for threadID: String) {
        let expanded: Bool
        if expandedThreadIDs.contains(threadID) {
            expandedThreadIDs.remove(threadID)
            expanded = false
        } else {
            expandedThreadIDs.insert(threadID)
            expanded = true
        }
        onSetSubtasksExpanded(threadID, expanded)
        rebuildRows(for: selectedTab)
    }

    private static func makeRowViews(
        allThreads: [CodexThreadItem],
        filteredRoots: [CodexThreadItem],
        selectedTab: TaskBarTab,
        expandedThreadIDs: Set<String>,
        showPlatformLabels: Bool,
        rowLayout: TaskRowLayoutStyle,
        onOpenThread: @escaping (String) -> Void,
        onDismissThread: @escaping (String) -> Void,
        onTogglePin: @escaping (String) -> Void,
        onToggleSubtasks: @escaping (String) -> Void,
        manualReorderEnabled: Bool,
        onManualReorderDrag: @escaping (String, TaskThreadManualDragPhase, NSPoint) -> Void
    ) -> [NSView] {
        if filteredRoots.isEmpty {
            return [EmptyStateView(message: selectedTab.emptyMessage)]
        }
        return filteredRoots.map { thread in
            let children = allThreads.subtasks(parentID: thread.id)
            return ThreadGroupView(
                root: thread,
                subtasks: children,
                isExpanded: expandedThreadIDs.contains(thread.id),
                showPlatformLabel: showPlatformLabels,
                rowLayout: rowLayout,
                onOpen: onOpenThread,
                onDismiss: onDismissThread,
                onTogglePin: onTogglePin,
                onToggleSubtasks: onToggleSubtasks,
                manualReorderEnabled: manualReorderEnabled,
                onManualReorderDrag: onManualReorderDrag
            )
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    func playEntranceMotion() {
        guard shouldAnimateEntrance, !TaskBarBuild.isClassicPage, !didAnimateEntrance else { return }
        didAnimateEntrance = true

        if !usesExternalSurface {
            TaskBarMotion.prepareForReveal(headerView, offsetY: -12, scale: 0.97)
            TaskBarMotion.prepareForReveal(tabsView, offsetY: -9, scale: 0.985)
            TaskBarMotion.prepareForReveal(topSeparator, offsetY: -6, scale: 1)
        }
        TaskBarMotion.prepareForReveal(rowsScrollView, offsetY: -6, scale: 0.995)
        TaskBarMotion.prepareForReveal(commandBar, offsetY: 8, scale: 0.99)
        rowsView.prepareForEntrance()

        if usesExternalSurface {
            TaskBarMotion.reveal(rowsScrollView, delay: 0.05, offsetY: -6, scale: 0.995)
            rowsView.animateEntrance(startDelay: 0.10)
            TaskBarMotion.reveal(commandBar, delay: 0.18, offsetY: 8, scale: 0.99)
        } else {
            TaskBarMotion.reveal(headerView, delay: 0.03, offsetY: -12, scale: 0.97)
            TaskBarMotion.reveal(tabsView, delay: 0.08, offsetY: -9, scale: 0.985)
            TaskBarMotion.reveal(topSeparator, delay: 0.12, offsetY: -6, scale: 1)
            TaskBarMotion.reveal(rowsScrollView, delay: 0.14, offsetY: -6, scale: 0.995)
            rowsView.animateEntrance(startDelay: 0.19)
            TaskBarMotion.reveal(commandBar, delay: 0.27, offsetY: 8, scale: 0.99)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !usesExternalSurface, !TaskBarBuild.isClassicPage else { return }
        let panel = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 20, yRadius: 20)
        if let gradient = NSGradient(
            starting: NSColor(calibratedRed: 0.085, green: 0.070, blue: 0.090, alpha: 0.99),
            ending: menuPanelBackground
        ) {
            gradient.draw(in: panel, angle: 90)
        } else {
            menuPanelBackground.setFill()
            panel.fill()
        }
        taskBarPanelBorder.setStroke()
        panel.lineWidth = 1
        panel.stroke()
    }

    override func layout() {
        super.layout()
        var y: CGFloat = 0
        let headerHeight = usesExternalSurface ? 0 : headerView.frame.height
        headerView.frame = NSRect(x: 0, y: y, width: bounds.width, height: headerHeight)
        y += headerHeight

        let tabsHeight = usesExternalSurface ? 0 : tabsView.frame.height
        tabsView.frame = NSRect(x: 0, y: y, width: bounds.width, height: tabsHeight)
        y += tabsHeight

        let separatorHeight = usesExternalSurface ? 0 : topSeparator.frame.height
        topSeparator.frame = NSRect(x: 0, y: y, width: bounds.width, height: separatorHeight)
        y += separatorHeight

        let fixedHeight = headerHeight
            + tabsHeight
            + separatorHeight
            + taskCountHeight
            + bottomSeparator.frame.height
            + commandBar.frame.height
        let minRowsHeight = min(rowsContentHeight, taskBarEmptyStateHeight)
        let rowsViewportHeight = max(minRowsHeight, bounds.height - fixedHeight)
        let rowsFrame = NSRect(x: 0, y: y, width: bounds.width, height: rowsViewportHeight)
        rowsScrollView.frame = rowsFrame
        rowsScrollView.hasVerticalScroller = rowsContentHeight > rowsViewportHeight + 0.5
        rowsView.frame = NSRect(
            x: 0,
            y: 0,
            width: rowsScrollView.contentSize.width,
            height: max(rowsContentHeight, rowsViewportHeight)
        )
        y += rowsViewportHeight

        taskCountView.frame = NSRect(x: 0, y: y, width: bounds.width, height: taskCountHeight)
        y += taskCountHeight

        bottomSeparator.frame = NSRect(x: 0, y: y, width: bounds.width, height: bottomSeparator.frame.height)
        y += bottomSeparator.frame.height

        commandBar.frame = NSRect(x: 0, y: y, width: bounds.width, height: commandBar.frame.height)
        resizeHandle.frame = NSRect(x: bounds.maxX - 18, y: bounds.maxY - 18, width: 18, height: 18)
        resizeHandle.needsDisplay = true
    }

    private func applyResize(_ size: NSSize, persist: Bool) {
        let clamped = TaskBarSettings.clampedPopoverSize(size)
        setFrameSize(clamped)
        needsLayout = true
        onResize(clamped, persist)
    }
}
