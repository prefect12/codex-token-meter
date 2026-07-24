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
    private var settingsWindowController: TaskBarSettingsWindowController?
    private var rolloutActivityMonitor: RolloutActivityMonitor?
    private var readInFlight = false
    private var pendingRefresh = false
    private var scheduledRefresh: DispatchWorkItem?
    private var lastRefreshStartedAt = Date.distantPast
    private var pendingRolloutEnrichment = false
    private var pendingPriorityRolloutURLs: [String: URL] = [:]
    private var selectedTab: TaskBarTab = .all
    private var collapsedThreadIDs = Set<String>()
    private var lastThreadsSignature = ""
    private var lastStatusIconSignature = ""
    private let refreshInterval: TimeInterval = 15
    private let minimumRefreshInterval: TimeInterval = 2

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
        startRolloutActivityMonitor()
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func applicationWillResignActive(_ notification: Notification) {
        ThreadHoverPanel.shared.hideAll()
    }

    func applicationWillTerminate(_ notification: Notification) {
        scheduledRefresh?.cancel()
        rolloutActivityMonitor?.stop()
        ThreadHoverPanel.shared.hideAll()
    }

    private func refresh(includeRolloutEnrichment: Bool = false, priorityRolloutURLs: [URL] = []) {
        pendingRolloutEnrichment = pendingRolloutEnrichment || includeRolloutEnrichment
        for url in priorityRolloutURLs {
            pendingPriorityRolloutURLs[url.path] = url
        }
        guard !readInFlight else {
            pendingRefresh = true
            return
        }
        let remainingDelay = minimumRefreshInterval - Date().timeIntervalSince(lastRefreshStartedAt)
        guard remainingDelay <= 0 else {
            pendingRefresh = true
            schedulePendingRefresh(after: remainingDelay)
            return
        }
        scheduledRefresh?.cancel()
        scheduledRefresh = nil
        readInFlight = true
        pendingRefresh = false
        lastRefreshStartedAt = Date()
        let shouldEnrichRollouts = pendingRolloutEnrichment
        pendingRolloutEnrichment = false
        let prioritized = Array(pendingPriorityRolloutURLs.values)
        pendingPriorityRolloutURLs.removeAll()
        DispatchQueue.global(qos: .utility).async {
            let items = self.reader.read(
                limit: taskBarCandidateThreadLimit,
                includeRolloutEnrichment: shouldEnrichRollouts,
                priorityRolloutURLs: prioritized
            )
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
                if self.pendingRefresh || !self.pendingPriorityRolloutURLs.isEmpty {
                    let delay = max(0, self.minimumRefreshInterval - Date().timeIntervalSince(self.lastRefreshStartedAt))
                    self.schedulePendingRefresh(after: delay)
                }
            }
        }
    }

    private func schedulePendingRefresh(after delay: TimeInterval) {
        guard scheduledRefresh == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.scheduledRefresh = nil
            self.refresh()
        }
        scheduledRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: work)
    }

    private func startRolloutActivityMonitor() {
        rolloutActivityMonitor?.stop()
        let monitor = RolloutActivityMonitor(roots: taskBarRolloutRootURLs()) { [weak self] urls in
            DispatchQueue.main.async {
                self?.refresh(priorityRolloutURLs: urls)
            }
        }
        rolloutActivityMonitor = monitor
        monitor.start()
    }

    private func threadsSignature(_ items: [CodexThreadItem]) -> String {
        items.map {
            let planSignature = $0.plan?.steps
                .map { "\($0.status.rawValue):\($0.text)" }
                .joined(separator: ",") ?? ""
            return "\($0.id)|\(statusRank($0.status))|\($0.title)|\($0.preview ?? "")|\($0.threadKind.rawValue)|\($0.parentThreadID ?? "")|\($0.agentNickname ?? "")|\($0.agentPath ?? "")|\(planSignature)"
        }
            .joined(separator: ";")
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.toolTip = "Task Bar"
        button.action = #selector(togglePopover)
        button.target = self
    }

    private func updateStatusIcon() {
        let primaryThreads = threads.primaryThreads
        let runningCount = primaryThreads.filter { $0.status == .running }.count
        let waitingCount = primaryThreads.filter { $0.status == .waiting }.count
        let unreadCount = primaryThreads.filter { $0.status == .unread }.count
        let actionNeededCount = waitingCount + unreadCount
        let totalCount = runningCount + actionNeededCount
        let statusIconStatus: ThreadRunStatus = waitingCount > 0 ? .waiting : (unreadCount > 0 ? .unread : .running)
        let showsRedDot = actionNeededCount > 0
        let title = totalCount > 0 ? " \(totalCount)" : ""
        let signature = "\(runningCount)|\(waitingCount)|\(unreadCount)|\(statusIconStatus)|\(showsRedDot)|\(title)"
        guard signature != lastStatusIconSignature else { return }
        lastStatusIconSignature = signature

        statusItem.button?.image = icon.image(status: statusIconStatus, showsRedDot: showsRedDot)
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.title = title
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
        refresh(includeRolloutEnrichment: true)
    }

    private func rebuildPopover() {
        ThreadHoverPanel.shared.hideAll()
        let primaryThreads = threads.primaryThreads
        let active = primaryThreads.filter { $0.status == .running }
        let waitingCount = primaryThreads.filter { $0.status == .waiting }.count
        let unreadCount = primaryThreads.filter { $0.status == .unread }.count
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
            collapsedThreadIDs: collapsedThreadIDs,
            onSetSubtasksExpanded: { [weak self] id, expanded in
                if expanded {
                    self?.collapsedThreadIDs.remove(id)
                } else {
                    self?.collapsedThreadIDs.insert(id)
                }
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
                self?.startRolloutActivityMonitor()
                self?.refresh()
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
            openClaudeThread(id: selectedItem.id, fallbackFolder: selectedItem.cwd)
            return
        }
        if id.hasPrefix("claude:") {
            openClaudeThread(id: id, fallbackFolder: nil)
            return
        }

        if let selectedItem, isCodexAPIThread(selectedItem) {
            openCodexAPIThread(id: selectedItem.id)
            return
        }

        openCodexThread(id: id)
    }

    /// Both Codex and the local Codex API app can register `codex:`. A Task Bar
    /// Codex row represents a desktop thread, so send the URL to Codex.app
    /// explicitly instead of relying on LaunchServices' current default handler.
    private func openCodexThread(id: String) {
        guard let encodedID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "codex://threads/\(encodedID)") else {
            return
        }
        if let appURL = codexDesktopAppURL() {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration) { _, error in
                if error != nil {
                    NSWorkspace.shared.open(url)
                }
            }
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func codexDesktopAppURL() -> URL? {
        let applicationsURL = URL(fileURLWithPath: "/Applications/Codex.app", isDirectory: true)
        if FileManager.default.fileExists(atPath: applicationsURL.path) {
            return applicationsURL
        }
        guard let registeredURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex"),
              FileManager.default.fileExists(atPath: registeredURL.path) else {
            return nil
        }
        return registeredURL
    }

    private func openCodexAPIThread(id: String) {
        guard let encodedID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "codex-api://threads/\(encodedID)") else {
            return
        }
        if let appURL = codexAPIAppURL() {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration) { _, error in
                if error != nil {
                    NSWorkspace.shared.open(url)
                }
            }
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func codexAPIAppURL() -> URL? {
        let userApplicationsURL = URL(fileURLWithPath: "\(NSHomeDirectory())/Applications/Codex API.app", isDirectory: true)
        if FileManager.default.fileExists(atPath: userApplicationsURL.path) {
            return userApplicationsURL
        }
        let applicationsURL = URL(fileURLWithPath: "/Applications/Codex API.app", isDirectory: true)
        if FileManager.default.fileExists(atPath: applicationsURL.path) {
            return applicationsURL
        }
        guard let registeredURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex.api.local"),
              FileManager.default.fileExists(atPath: registeredURL.path) else {
            return nil
        }
        return registeredURL
    }

    /// Claude Home thread ids are `claude-home:<conversation-uuid>` and use the
    /// desktop app's native conversation route. Claude Code thread ids are
    /// `claude:<session-uuid>` and are ordered to avoid both
    /// duplicate imports and full page reloads as far as the desktop app's deep
    /// links allow: (1) if the desktop app is already showing this session
    /// (its `lastFocusedAt` is the store-wide maximum), just activate the app;
    /// (2) an imported entry is reachable smoothly via `claude://resume`, whose
    /// import step dedupes by the deterministic `local_<uuid>` key — which is
    /// also why (3) natively created entries (random desktop id) must instead
    /// use `claude://claude.ai/claude-code-desktop/<id>`, the only route that
    /// reaches them without importing a duplicate, at the cost of a full page
    /// load; (4) sessions the desktop app has never seen resume normally.
    /// Fall back to just foregrounding the app (or the working folder) when we
    /// don't have a usable session id.
    private func openClaudeThread(id: String, fallbackFolder: String?) {
        if id.hasPrefix("claude-home:") {
            let conversationID = String(id.dropFirst("claude-home:".count))
            guard UUID(uuidString: conversationID) != nil,
                  let url = URL(string: "claude://claude.ai/chat/\(conversationID)") else {
                openClaudeApp(fallbackFolder: fallbackFolder)
                return
            }
            NSWorkspace.shared.open(url)
            return
        }
        let sessionID = id.hasPrefix("claude:") ? String(id.dropFirst("claude:".count)) : id
        guard UUID(uuidString: sessionID) != nil else {
            openClaudeApp(fallbackFolder: fallbackFolder)
            return
        }
        let match = claudeDesktopSessionMatch(forCLISession: sessionID)
        if match.targetLastFocused > 0, match.targetLastFocused >= match.globalLastFocused,
           let running = NSRunningApplication.runningApplications(withBundleIdentifier: claudeDesktopBundleID).first {
            running.activate()
            return
        }
        if match.importedExists, !match.importedArchived,
           let url = URL(string: "claude://resume?session=\(sessionID)") {
            NSWorkspace.shared.open(url)
            return
        }
        if let desktopID = match.nativeID ?? (match.importedExists ? "local_\(sessionID)" : nil),
           let url = URL(string: "claude://claude.ai/claude-code-desktop/\(desktopID)") {
            NSWorkspace.shared.open(url)
            return
        }
        if let url = URL(string: "claude://resume?session=\(sessionID)") {
            NSWorkspace.shared.open(url)
            return
        }
        openClaudeApp(fallbackFolder: fallbackFolder)
    }

    private let claudeDesktopBundleID = "com.anthropic.claudefordesktop"

    private struct ClaudeDesktopSessionMatch {
        var importedExists = false
        var importedArchived = false
        var nativeID: String?
        var targetLastFocused: Double = 0
        var globalLastFocused: Double = 0
    }

    /// Claude Desktop keeps one metadata JSON per session under
    /// `~/Library/Application Support/Claude/claude-code-sessions/<account>/<org>/`,
    /// named `local_<desktop-session-id>.json` with a `cliSessionId` field linking
    /// it to the CLI transcript. The CLI session can be wrapped by an imported
    /// entry (file named `local_<cliID>.json`, reachable smoothly via the
    /// idempotent resume deep link) and/or a natively created entry (random
    /// desktop id, reachable only via the hard-reloading claude-code-desktop
    /// route); `lastFocusedAt` maxima let the caller detect that the desktop app
    /// is already showing this session so a plain activate suffices.
    private func claudeDesktopSessionMatch(forCLISession cliID: String) -> ClaudeDesktopSessionMatch {
        var match = ClaudeDesktopSessionMatch()
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions", isDirectory: true)
        guard let accountDirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return match
        }
        let importedFile = "local_\(cliID).json"
        var nativeActivity = 0.0
        for accountDir in accountDirs {
            guard let orgDirs = try? fm.contentsOfDirectory(at: accountDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for orgDir in orgDirs {
                guard let files = try? fm.contentsOfDirectory(at: orgDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
                for file in files {
                    let name = file.lastPathComponent
                    guard name.hasPrefix("local_"), name.hasSuffix(".json"),
                          let data = try? Data(contentsOf: file),
                          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        continue
                    }
                    let lastFocused = object["lastFocusedAt"] as? Double ?? 0
                    match.globalLastFocused = max(match.globalLastFocused, lastFocused)
                    if name == importedFile {
                        match.importedExists = true
                        match.importedArchived = object["isArchived"] as? Bool ?? false
                        match.targetLastFocused = max(match.targetLastFocused, lastFocused)
                    } else if object["cliSessionId"] as? String == cliID {
                        let activity = object["lastActivityAt"] as? Double ?? 0
                        if match.nativeID == nil || activity > nativeActivity {
                            match.nativeID = object["sessionId"] as? String ?? String(name.dropLast(".json".count))
                            nativeActivity = activity
                        }
                        match.targetLastFocused = max(match.targetLastFocused, lastFocused)
                    }
                }
            }
        }
        return match
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
