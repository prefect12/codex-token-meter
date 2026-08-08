import Foundation

final class ClaudeModelRoutingProtectionPreferences {
    static let enabledKey = "claudeDefaultsProtectionEnabled"
    static let protectedStateKey = "claudeProtectedRoutingState"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool { defaults.bool(forKey: Self.enabledKey) }

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

/// Protects Claude defaults for the menu-bar app's full lifetime. It restores
/// only user-owned global and private project settings, never shared project
/// `.claude/settings.json` files.
final class ClaudeModelRoutingProtectionController {
    private let routingStore: ClaudeModelRoutingStore
    private let preferences: ClaudeModelRoutingProtectionPreferences
    private var watcher: CodexConfigWatcher?

    init(
        routingStore: ClaudeModelRoutingStore = ClaudeModelRoutingStore(),
        preferences: ClaudeModelRoutingProtectionPreferences =
            ClaudeModelRoutingProtectionPreferences(),
        callbackQueue: DispatchQueue = DispatchQueue(
            label: "local.ai-token-meter.claude-routing-protection",
            qos: .utility
        ),
        onWatcherReady: (() -> Void)? = nil
    ) {
        self.routingStore = routingStore
        self.preferences = preferences
        enforceProtectedDefaultsIfNeeded()
        watcher = CodexConfigWatcher(callbackQueue: callbackQueue) { [weak self] in
            self?.handleExternalChange()
        }
        refreshWatcherTargets(ready: onWatcherReady)
    }

    private func handleExternalChange() {
        enforceProtectedDefaultsIfNeeded()
        refreshWatcherTargets()
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
        watcher?.watch(
            targetURLs: routingStore.protectedRoutingInputURLs(for: routingStore.loadSnapshot()),
            ready: ready
        )
    }
}
