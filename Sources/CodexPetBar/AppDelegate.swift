import Cocoa
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let reader = CodexActivityReader()
    private let icon = PetStatusIcon()
    private let readState = ReadStateStore()
    private var threads: [CodexThreadItem] = []
    private var refreshTimer: Timer?
    private var animationTimer: Timer?
    private var settingsWindowController: TaskBarSettingsWindowController?
    private var readInFlight = false
    private var selectedTab: TaskBarTab = .all
    private var lastThreadsSignature = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(popoverDidClose(_:)),
            name: NSPopover.didCloseNotification,
            object: popover
        )
        configureStatusButton()
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            self?.updateStatusIcon()
        }
    }

    func applicationWillResignActive(_ notification: Notification) {
        ThreadHoverPanel.shared.hideAll()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ThreadHoverPanel.shared.hideAll()
    }

    private func refresh() {
        guard !readInFlight else { return }
        readInFlight = true
        DispatchQueue.global(qos: .utility).async {
            let items = self.reader.read(limit: taskBarCandidateThreadLimit)
            let visible = self.readState.visibleThreads(from: items)
                .sorted(by: stableThreadOrder)
                .limitedForTaskBar(limit: taskBarVisibleThreadLimit)
            DispatchQueue.main.async {
                self.readInFlight = false
                let signature = self.threadsSignature(visible)
                let changed = signature != self.lastThreadsSignature
                self.threads = visible
                self.lastThreadsSignature = signature
                self.updateStatusIcon()
                // Only rebuild when the visible set actually changed; per-row timers keep
                // elapsed times ticking, so a static list never needs to flash.
                if changed, self.popover.isShown {
                    self.rebuildPopover()
                }
            }
        }
    }

    private func threadsSignature(_ items: [CodexThreadItem]) -> String {
        items.map { "\($0.id)|\(statusRank($0.status))|\($0.title)|\($0.preview ?? "")" }
            .joined(separator: ";")
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.toolTip = "Task Bar"
        button.action = #selector(togglePopover)
        button.target = self
    }

    private func updateStatusIcon() {
        let runningCount = threads.filter { $0.status == .running || $0.status == .stale }.count
        let waitingCount = threads.filter { $0.status == .waiting }.count
        let unreadCount = threads.filter { $0.status == .unread }.count
        let actionNeededCount = waitingCount + unreadCount
        let totalCount = runningCount + actionNeededCount
        let statusIconStatus: ThreadRunStatus = waitingCount > 0 ? .waiting : (unreadCount > 0 ? .unread : .running)
        statusItem.button?.image = icon.image(status: statusIconStatus, showsRedDot: actionNeededCount > 0)
        statusItem.button?.imagePosition = .imageLeading
        if totalCount > 0 {
            statusItem.button?.title = " \(totalCount)"
        } else {
            statusItem.button?.title = ""
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            closePopover()
            return
        }
        rebuildPopover()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        refresh()
    }

    private func rebuildPopover() {
        ThreadHoverPanel.shared.hideAll()
        let active = threads.filter { $0.status == .running || $0.status == .stale }
        let waitingCount = threads.filter { $0.status == .waiting }.count
        let unreadCount = threads.filter { $0.status == .unread }.count
        let controller = NSViewController()
        let content = TaskBarPopoverContentView(
            threads: threads,
            runningCount: active.count,
            waitingCount: waitingCount,
            unreadCount: unreadCount,
            selectedTab: selectedTab,
            showPlatformLabels: TaskBarSettings.showPlatformLabels,
            rowLayout: TaskBarSettings.rowLayout,
            onOpenThread: { [weak self] id in
                self?.openThread(id: id)
            },
            onDismissThread: { [weak self] id in
                self?.dismissThread(id: id)
            },
            onTogglePin: { [weak self] id in
                self?.togglePin(id: id)
            },
            onSelectTab: { [weak self] tab in
                self?.selectedTab = tab
            },
            onOpenSettings: { [weak self] in
                self?.openSettingsWindow()
            },
            onQuit: { [weak self] in
                self?.closePopover()
                self?.quit()
            },
            initialSize: TaskBarSettings.popoverSize,
            onResize: { [weak self, weak controller] size, persist in
                controller?.preferredContentSize = size
                self?.popover.contentSize = size
                if persist {
                    TaskBarSettings.popoverSize = size
                }
            }
        )
        controller.view = content
        controller.preferredContentSize = content.frame.size
        popover.contentViewController = controller
        popover.contentSize = content.frame.size
    }

    private func openSettingsWindow() {
        closePopover()
        if settingsWindowController == nil {
            settingsWindowController = TaskBarSettingsWindowController { [weak self] in
                ThreadHoverPanel.shared.hideAll()
                if self?.popover.isShown == true {
                    self?.rebuildPopover()
                }
            }
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func togglePin(id: String) {
        TaskBarSettings.togglePin(id)
        threads.sort(by: stableThreadOrder)
        lastThreadsSignature = threadsSignature(threads)
        if popover.isShown {
            rebuildPopover()
        }
        ThreadHoverPanel.shared.hideAll()
    }

    private func dismissThread(id: String) {
        let selectedItem = threads.first(where: { $0.id == id })
        if let item = selectedItem, isReadDismissible(item.status) {
            readState.markRead(item)
        } else {
            readState.markRead(threadID: id)
        }
        threads.removeAll { $0.id == id && isReadDismissible($0.status) }
        // A dismissed row leaves the list; keeping its pin would silently
        // re-float the thread if it ever reappears.
        if threads.first(where: { $0.id == id }) == nil {
            TaskBarSettings.setPinned(false, for: id)
        }
        lastThreadsSignature = threadsSignature(threads)
        updateStatusIcon()
        if popover.isShown {
            rebuildPopover()
        }
        ThreadHoverPanel.shared.hideAll()
    }

    private func openThread(id: String) {
        let selectedItem = threads.first(where: { $0.id == id })
        if let item = selectedItem {
            readState.markRead(item)
        } else {
            readState.markRead(threadID: id)
        }
        threads.removeAll { $0.id == id && isReadDismissible($0.status) }
        if threads.first(where: { $0.id == id }) == nil {
            TaskBarSettings.setPinned(false, for: id)
        }
        updateStatusIcon()
        if popover.isShown {
            rebuildPopover()
            closePopover()
        }
        ThreadHoverPanel.shared.hideAll()

        if let selectedItem, isClaudeThread(selectedItem) {
            openClaudeApp(fallbackFolder: selectedItem.cwd)
            return
        }
        if id.hasPrefix("claude:") {
            openClaudeApp(fallbackFolder: nil)
            return
        }

        guard let url = URL(string: "codex://threads/\(id)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func openClaudeApp(fallbackFolder: String?) {
        let claudeURL = URL(fileURLWithPath: "/Applications/Claude.app")
        if FileManager.default.fileExists(atPath: claudeURL.path) {
            NSWorkspace.shared.open(claudeURL)
        } else if let fallbackFolder {
            NSWorkspace.shared.open(URL(fileURLWithPath: fallbackFolder, isDirectory: true))
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func popoverDidClose(_ notification: Notification) {
        ThreadHoverPanel.shared.hideAll()
    }

    private func closePopover() {
        popover.performClose(nil)
        ThreadHoverPanel.shared.hideAll()
    }
}
