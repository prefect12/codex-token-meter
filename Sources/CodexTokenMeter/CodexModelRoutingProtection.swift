import Foundation

final class CodexModelRoutingProtectionPreferences {
    static let enabledKey = "codexDefaultsProtectionEnabled"
    static let protectedStateKey = "codexProtectedRoutingState"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        defaults.bool(forKey: Self.enabledKey)
    }

    func enable(capturing state: CodexProtectedRoutingState) {
        save(state)
        defaults.set(true, forKey: Self.enabledKey)
    }

    func disable() {
        defaults.set(false, forKey: Self.enabledKey)
        defaults.removeObject(forKey: Self.protectedStateKey)
    }

    func updateProtectedState(_ state: CodexProtectedRoutingState) {
        guard isEnabled else { return }
        save(state)
    }

    func protectedState() -> CodexProtectedRoutingState? {
        guard isEnabled,
              let data = defaults.data(forKey: Self.protectedStateKey),
              let state = try? JSONDecoder().decode(CodexProtectedRoutingState.self, from: data),
              state.version == CodexProtectedRoutingState.currentVersion else {
            return nil
        }
        return state
    }

    private func save(_ state: CodexProtectedRoutingState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.protectedStateKey)
    }
}

/// Keeps protection active for the entire menu-bar app lifetime, including
/// before the details window or Default Models page has ever been opened.
final class CodexModelRoutingProtectionController {
    /// Keeps a user-selected task override in place long enough for Codex
    /// Desktop to bind it to the active task before the fixed defaults return.
    static let defaultConversationOverrideGraceInterval: TimeInterval = 60

    private let routingStore: CodexModelRoutingStore
    private let preferences: CodexModelRoutingProtectionPreferences
    private let callbackQueue: DispatchQueue
    private let conversationOverrideGraceInterval: TimeInterval
    private var watcher: CodexConfigWatcher?
    private var pendingRestoration: DispatchWorkItem?
    private var lastObservedGlobalModificationDate: Date?
    private var lastObservedRoutingModificationDates: [String: Date] = [:]
    private var lastSelectedProjectID: String?

    init(
        routingStore: CodexModelRoutingStore = CodexModelRoutingStore(),
        preferences: CodexModelRoutingProtectionPreferences =
            CodexModelRoutingProtectionPreferences(),
        callbackQueue: DispatchQueue = DispatchQueue(
            label: "local.ai-token-meter.codex-routing-protection",
            qos: .utility
        ),
        conversationOverrideGraceInterval: TimeInterval =
            CodexModelRoutingProtectionController.defaultConversationOverrideGraceInterval,
        onWatcherReady: (() -> Void)? = nil
    ) {
        self.routingStore = routingStore
        self.preferences = preferences
        self.callbackQueue = callbackQueue
        self.conversationOverrideGraceInterval = max(0, conversationOverrideGraceInterval)
        enforceProtectedDefaultsIfNeeded()
        lastObservedGlobalModificationDate = globalConfigModificationDate()
        lastObservedRoutingModificationDates = routingConfigModificationDates()
        lastSelectedProjectID = routingStore.selectedProject()?.id
        watcher = CodexConfigWatcher(callbackQueue: callbackQueue) { [weak self] in
            self?.handleExternalChange()
        }
        refreshWatcherTargets(ready: onWatcherReady)
    }

    deinit {
        pendingRestoration?.cancel()
    }

    private func handleExternalChange() {
        refreshWatcherTargets()
        let selectedProjectID = routingStore.selectedProject()?.id
        if selectedProjectID != lastSelectedProjectID {
            pendingRestoration?.cancel()
            lastSelectedProjectID = selectedProjectID
            enforceProtectedDefaultsIfNeeded()
            lastObservedGlobalModificationDate = globalConfigModificationDate()
            lastObservedRoutingModificationDates = routingConfigModificationDates()
            return
        }

        let globalModificationDate = globalConfigModificationDate()
        let globalConfigWasRewritten = globalModificationDate != lastObservedGlobalModificationDate
        let routingModificationDates = routingConfigModificationDates()
        let routingConfigWasRewritten =
            routingModificationDates != lastObservedRoutingModificationDates
        lastObservedGlobalModificationDate = globalModificationDate
        lastObservedRoutingModificationDates = routingModificationDates

        // Project discovery and model-catalog updates share this watcher so its
        // targets stay current, but they must not extend a task override beyond
        // the promised grace period.
        guard routingConfigWasRewritten else { return }
        guard preferences.isEnabled else { return }
        if globalConfigWasRewritten {
            scheduleProtectedDefaultsRestoration()
            return
        }
        _ = try? routingStore.clearProjectRoutingOverrides()
        lastObservedRoutingModificationDates = routingConfigModificationDates()
    }

    private func scheduleProtectedDefaultsRestoration() {
        pendingRestoration?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.enforceProtectedDefaultsIfNeeded()
            self.lastObservedGlobalModificationDate = self.globalConfigModificationDate()
            self.lastObservedRoutingModificationDates = self.routingConfigModificationDates()
            self.lastSelectedProjectID = self.routingStore.selectedProject()?.id
            self.refreshWatcherTargets()
        }
        pendingRestoration = workItem
        callbackQueue.asyncAfter(
            deadline: .now() + conversationOverrideGraceInterval,
            execute: workItem
        )
    }

    private func enforceProtectedDefaultsIfNeeded() {
        guard preferences.isEnabled else { return }
        let protected: CodexProtectedRoutingState
        if let existing = preferences.protectedState() {
            protected = existing
        } else {
            protected = routingStore.captureProtectedRoutingState()
            preferences.enable(capturing: protected)
        }
        _ = try? routingStore.activateVirtualProjectDefaults(protected)
    }

    private func refreshWatcherTargets(ready: (() -> Void)? = nil) {
        let snapshot = routingStore.loadSnapshot()
        watcher?.watch(
            targetURLs: routingStore.routingInputURLs(for: snapshot),
            ready: ready
        )
    }

    private func globalConfigModificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: routingStore.globalConfigURL.path))?[.modificationDate]
            as? Date
    }

    private func routingConfigModificationDates() -> [String: Date] {
        let snapshot = routingStore.loadSnapshot()
        let urls = [routingStore.globalConfigURL] + snapshot.projects.flatMap { project in
            project.project.rootPaths.map(routingStore.projectConfigURL(rootPath:))
        }
        return Dictionary(uniqueKeysWithValues: urls.compactMap { url in
            guard let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate]
                as? Date else {
                return nil
            }
            return (url.standardizedFileURL.path, date)
        })
    }
}
