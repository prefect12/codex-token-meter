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

    // Retained so the tab filter can be re-applied in place, without a full rebuild.
    private let allThreads: [CodexThreadItem]
    private let totalCount: Int
    private let showPlatformLabels: Bool
    private let rowLayout: TaskRowLayoutStyle
    private let onOpenThread: (String) -> Void
    private let onDismissThread: (String) -> Void
    private let externalSelectTab: (TaskBarTab) -> Void
    private var selectedTab: TaskBarTab

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
        onSelectTab: @escaping (TaskBarTab) -> Void,
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void,
        initialSize: NSSize?,
        onResize: @escaping (NSSize, Bool) -> Void
    ) {
        self.onResize = onResize
        self.allThreads = threads
        self.showPlatformLabels = showPlatformLabels
        self.rowLayout = rowLayout
        self.onOpenThread = onOpenThread
        self.onDismissThread = onDismissThread
        self.externalSelectTab = onSelectTab
        self.selectedTab = selectedTab

        headerView = PanelHeaderView(
            runningCount: runningCount,
            waitingCount: waitingCount,
            unreadCount: unreadCount
        )
        tabsView = TaskBarTabsView(tabs: TaskBarTab.allCases, selected: selectedTab, onSelect: { _ in })

        let total = runningCount + waitingCount + unreadCount
        totalCount = total
        let filtered = threads.filter { selectedTab.matches($0.status) }
        taskCountView = TaskCountView(shown: filtered.count, total: total)
        // "N of M tasks" footer removed: uninformative next to the header chips.
        taskCountView.isHidden = true
        taskCountHeight = 0

        let rowViews = TaskBarPopoverContentView.makeRowViews(
            filtered: filtered,
            selectedTab: selectedTab,
            showPlatformLabels: showPlatformLabels,
            rowLayout: rowLayout,
            onOpenThread: onOpenThread,
            onDismissThread: onDismissThread
        )
        rowsView = TaskBarRowsView(rowViews: rowViews)
        rowsContentHeight = rowsView.frame.height
        commandBar = CommandButtonBarView(
            onOpenSettings: onOpenSettings,
            onQuit: onQuit
        )

        let fixedHeight = headerView.frame.height
            + tabsView.frame.height
            + topSeparator.frame.height
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
        layer?.backgroundColor = menuPanelBackground.cgColor
        appearance = NSAppearance(named: .darkAqua)

        addSubview(headerView)
        addSubview(tabsView)
        addSubview(topSeparator)
        addSubview(rowsScrollView)
        addSubview(taskCountView)
        addSubview(bottomSeparator)
        addSubview(commandBar)
        addSubview(resizeHandle)
        resizeHandle.onResize = { [weak self] size, persist in
            self?.applyResize(size, persist: persist)
        }
        tabsView.onSelect = { [weak self] tab in
            self?.selectTab(tab)
        }
    }

    /// Re-filter and swap the list rows in place, keeping the surrounding chrome
    /// (header, tabs, footer) and the popover size stable so switching tabs never flashes.
    private func selectTab(_ tab: TaskBarTab) {
        guard tab != selectedTab else { return }
        selectedTab = tab
        externalSelectTab(tab)

        let filtered = allThreads.filter { tab.matches($0.status) }
        let rowViews = TaskBarPopoverContentView.makeRowViews(
            filtered: filtered,
            selectedTab: tab,
            showPlatformLabels: showPlatformLabels,
            rowLayout: rowLayout,
            onOpenThread: onOpenThread,
            onDismissThread: onDismissThread
        )
        let newRowsView = TaskBarRowsView(rowViews: rowViews)
        rowsView = newRowsView
        rowsContentHeight = newRowsView.frame.height
        rowsScrollView.documentView = newRowsView
        taskCountView.update(shown: filtered.count, total: totalCount)
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    private static func makeRowViews(
        filtered: [CodexThreadItem],
        selectedTab: TaskBarTab,
        showPlatformLabels: Bool,
        rowLayout: TaskRowLayoutStyle,
        onOpenThread: @escaping (String) -> Void,
        onDismissThread: @escaping (String) -> Void
    ) -> [NSView] {
        if filtered.isEmpty {
            return [EmptyStateView(message: selectedTab.emptyMessage)]
        }
        return filtered.map { thread in
            ThreadRowView(
                item: thread,
                showPlatformLabel: showPlatformLabels,
                rowLayout: rowLayout,
                onOpen: onOpenThread,
                onDismiss: onDismissThread
            )
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        var y: CGFloat = 0
        headerView.frame = NSRect(x: 0, y: y, width: bounds.width, height: headerView.frame.height)
        y += headerView.frame.height

        tabsView.frame = NSRect(x: 0, y: y, width: bounds.width, height: tabsView.frame.height)
        y += tabsView.frame.height

        topSeparator.frame = NSRect(x: 0, y: y, width: bounds.width, height: topSeparator.frame.height)
        y += topSeparator.frame.height

        let fixedHeight = headerView.frame.height
            + tabsView.frame.height
            + topSeparator.frame.height
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
