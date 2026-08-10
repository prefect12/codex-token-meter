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
    private let temporaryOverrideTargetProvider: (CodexConfigSelection) -> URL?
    private var watcher: CodexConfigWatcher?
    private var pendingRestoration: DispatchWorkItem?
    private var lastObservedGlobalSelection = CodexConfigSelection()
    private var lastObservedGlobalModificationDate: Date?
    private var lastObservedRoutingModificationDates: [String: Date] = [:]

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
        temporaryOverrideTargetProvider: ((CodexConfigSelection) -> URL?)? = nil,
        onWatcherReady: (() -> Void)? = nil
    ) {
        self.routingStore = routingStore
        self.preferences = preferences
        self.callbackQueue = callbackQueue
        self.conversationOverrideGraceInterval = max(0, conversationOverrideGraceInterval)
        self.temporaryOverrideTargetProvider = temporaryOverrideTargetProvider ?? { [routingStore] selection in
            CodexActiveProjectConfigResolver(routingStore: routingStore)
                .mostRecentlySelectedProjectConfigURL(matching: selection)
        }
        enforceProtectedDefaultsIfNeeded()
        lastObservedGlobalSelection = (try? routingStore.readSelection(at: routingStore.globalConfigURL))
            ?? CodexConfigSelection()
        lastObservedGlobalModificationDate = globalConfigModificationDate()
        lastObservedRoutingModificationDates = routingConfigModificationDates()
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
        let globalSelection = (try? routingStore.readSelection(at: routingStore.globalConfigURL))
            ?? CodexConfigSelection()
        let globalModificationDate = globalConfigModificationDate()
        let globalConfigWasRewritten = globalModificationDate != lastObservedGlobalModificationDate
        let routingModificationDates = routingConfigModificationDates()
        let routingConfigWasRewritten =
            routingModificationDates != lastObservedRoutingModificationDates
        lastObservedGlobalSelection = globalSelection
        lastObservedGlobalModificationDate = globalModificationDate
        lastObservedRoutingModificationDates = routingModificationDates

        // Project discovery and model-catalog updates share this watcher so its
        // targets stay current, but they must not extend a task override beyond
        // the promised grace period.
        guard routingConfigWasRewritten else { return }

        if globalConfigWasRewritten,
           applyTaskScopedOverrideIfNeeded(selection: globalSelection) {
            scheduleProtectedDefaultsRestoration()
            return
        }
        scheduleProtectedDefaultsRestoration()
    }

    /// Codex Desktop currently persists a picker choice to the global config,
    /// while an explicit project config wins during task resolution. Mirror that
    /// one external choice to the *selected* project's config for the grace
    /// period, then restore the saved per-project default. This deliberately
    /// never changes other projects.
    private func applyTaskScopedOverrideIfNeeded(selection: CodexConfigSelection) -> Bool {
        guard preferences.protectedState() != nil,
              let projectConfigURL = temporaryOverrideTargetProvider(selection) else {
            return false
        }
        do {
            try routingStore.writeSelection(selection, at: projectConfigURL)
            return true
        } catch {
            return false
        }
    }

    private func scheduleProtectedDefaultsRestoration() {
        pendingRestoration?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.enforceProtectedDefaultsIfNeeded()
            self.lastObservedGlobalSelection = (try? self.routingStore.readSelection(
                at: self.routingStore.globalConfigURL
            )) ?? CodexConfigSelection()
            self.lastObservedGlobalModificationDate = self.globalConfigModificationDate()
            self.lastObservedRoutingModificationDates = self.routingConfigModificationDates()
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
        if let protected = preferences.protectedState() {
            _ = try? routingStore.restoreProtectedRoutingState(protected)
        } else {
            preferences.enable(capturing: routingStore.captureProtectedRoutingState())
        }
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
