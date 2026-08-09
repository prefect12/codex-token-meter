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
    /// Gives Codex Desktop time to attach a user-selected model or effort to
    /// the active task before restoring the saved defaults for the next task.
    static let defaultConversationOverrideGraceInterval: TimeInterval = 30

    private let routingStore: CodexModelRoutingStore
    private let preferences: CodexModelRoutingProtectionPreferences
    private let callbackQueue: DispatchQueue
    private let conversationOverrideGraceInterval: TimeInterval
    private var watcher: CodexConfigWatcher?
    private var pendingRestoration: DispatchWorkItem?

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
        scheduleProtectedDefaultsRestoration()
    }

    private func scheduleProtectedDefaultsRestoration() {
        pendingRestoration?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.enforceProtectedDefaultsIfNeeded()
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
}
