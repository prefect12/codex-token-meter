import Foundation

@main
struct ModelRoutingStoreTests {
    static func main() throws {
        try testTopLevelTOMLUpdatePreservesOtherContent()
        try testProjectGroupWritesEveryRoot()
        try testProtectedDefaultsRestoreOnlyRoutingKeys()
        try testProtectionPreferenceLifecycle()
        try testActiveProjectResolverUsesRecentMatchingTask()
        try testAppLifetimeProtectionRestoresExternalRewrite()
        try testAppLifetimeProtectionKeepsConversationOverrideBriefly()
        try testVirtualProjectDefaultsFollowSelectedProject()
        try testClaudeJSONUpdatePreservesOtherSettings()
        try testClaudeModelCatalogMatchesCurrentSelector()
        try testClaudeProjectWritesStayLocal()
        try testClaudeSharedProjectSettingsRemainUntouched()
        try testClaudeProtectedDefaultsRestoreOnlyPrivateRoutingKeys()
        try testClaudeAppLifetimeProtectionRestoresExternalRewrite()
        print("ModelRoutingStoreTests passed")
    }

    private static func testTopLevelTOMLUpdatePreservesOtherContent() throws {
        let source = """
        # personal defaults
        model = "old-model"
        sandbox_mode = "workspace-write"

        [projects."/tmp/example"]
        model = "nested-model"
        trust_level = "trusted"
        """
        let updated = CodexModelRoutingStore.updatedTOML(
            source,
            selection: CodexConfigSelection(model: "gpt-5.6-sol", reasoningEffort: "medium")
        )
        try require(
            CodexModelRoutingStore.topLevelStringValue(for: "model", in: updated) == "gpt-5.6-sol",
            "global model should be replaced"
        )
        try require(
            CodexModelRoutingStore.topLevelStringValue(for: "model_reasoning_effort", in: updated) == "medium",
            "reasoning effort should be inserted"
        )
        try require(updated.contains("sandbox_mode = \"workspace-write\""), "unrelated global setting should be preserved")
        try require(updated.contains("model = \"nested-model\""), "nested project setting should be preserved")

        let inherited = CodexModelRoutingStore.updatedTOML(
            updated,
            selection: CodexConfigSelection(model: nil, reasoningEffort: nil)
        )
        try require(
            CodexModelRoutingStore.topLevelStringValue(for: "model", in: inherited) == nil,
            "global model override should be removable"
        )
        try require(inherited.contains("model = \"nested-model\""), "removing a top-level key must not remove nested keys")
    }

    private static func testProjectGroupWritesEveryRoot() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-model-routing-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let codexHome = temporaryRoot.appendingPathComponent(".codex", isDirectory: true)
        let firstRoot = temporaryRoot.appendingPathComponent("first", isDirectory: true)
        let secondRoot = temporaryRoot.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        try Data("personality = \"pragmatic\"\n".utf8).write(
            to: codexHome.appendingPathComponent("config.toml")
        )

        let state: [String: Any] = [
            "local-projects": [
                "local-test": [
                    "id": "local-test",
                    "name": "Grouped Project",
                    "rootPaths": [firstRoot.path, secondRoot.path]
                ]
            ],
            "project-order": ["local-test"]
        ]
        try JSONSerialization.data(withJSONObject: state).write(
            to: codexHome.appendingPathComponent(".codex-global-state.json")
        )

        let store = CodexModelRoutingStore(codexHomeURL: codexHome)
        try store.writeGlobal(model: "gpt-5.6-terra", reasoningEffort: "medium")
        try store.writeProject(id: "local-test", model: "gpt-5.6-sol", reasoningEffort: "high")

        let global = try store.readSelection(at: codexHome.appendingPathComponent("config.toml"))
        try require(global == CodexConfigSelection(model: "gpt-5.6-terra", reasoningEffort: "medium"), "global defaults should be written")
        let first = try store.readSelection(at: store.projectConfigURL(rootPath: firstRoot.path))
        let second = try store.readSelection(at: store.projectConfigURL(rootPath: secondRoot.path))
        let expected = CodexConfigSelection(model: "gpt-5.6-sol", reasoningEffort: "high")
        try require(first == expected && second == expected, "every root in a saved project should receive the same override")

        let snapshot = store.loadSnapshot()
        try require(snapshot.projects.count == 1, "saved projects should be discovered")
        try require(snapshot.projects[0].model == .value("gpt-5.6-sol"), "project model should be read back")
        try require(snapshot.projects[0].reasoningEffort == .value("high"), "project effort should be read back")

        try Data("""
        model = "gpt-5.6-terra"
        model_reasoning_effort = "medium"
        """.utf8).write(to: store.projectConfigURL(rootPath: secondRoot.path))
        let mixedSnapshot = store.loadSnapshot()
        try require(mixedSnapshot.projects[0].hasMixedValues, "different root settings should produce a mixed project state")

        try store.writeProject(id: "local-test", model: nil, reasoningEffort: nil)
        let inheritedSnapshot = store.loadSnapshot()
        try require(inheritedSnapshot.projects[0].inheritsEverything, "following global should clear every root override")

        try store.writeProject(id: "local-test", model: "gpt-5.6-terra", reasoningEffort: "medium")
        let projectSnapshot = store.loadSnapshot()
        try require(!projectSnapshot.projects[0].inheritsEverything, "turning off inheritance should create project settings")
        try require(projectSnapshot.projects[0].model == .value("gpt-5.6-terra"), "project model should copy the global value")
        try require(projectSnapshot.projects[0].reasoningEffort == .value("medium"), "project effort should copy the global value")
    }

    private static func testProtectedDefaultsRestoreOnlyRoutingKeys() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-protected-routing-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let codexHome = temporaryRoot.appendingPathComponent("home", isDirectory: true)
        let firstRoot = temporaryRoot.appendingPathComponent("first", isDirectory: true)
        let secondRoot = temporaryRoot.appendingPathComponent("second", isDirectory: true)
        for url in [codexHome, firstRoot, secondRoot] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        let store = CodexModelRoutingStore(codexHomeURL: codexHome)
        try Data("""
        model = "gpt-5.6-luna"
        model_reasoning_effort = "high"
        personality = "pragmatic"
        """.utf8).write(to: store.globalConfigURL)
        let firstConfig = store.projectConfigURL(rootPath: firstRoot.path)
        try FileManager.default.createDirectory(
            at: firstConfig.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("""
        model = "gpt-5.6-sol"
        model_reasoning_effort = "medium"
        sandbox_mode = "danger-full-access"
        """.utf8).write(to: firstConfig)
        try writeProjectState(
            [
                "first": ("First", [firstRoot.path]),
            ],
            to: store.globalStateURL
        )

        let protected = store.captureProtectedRoutingState()

        try Data("""
        model = "gpt-5.6-terra"
        model_reasoning_effort = "low"
        personality = "friendly"
        """.utf8).write(to: store.globalConfigURL, options: .atomic)
        try Data("""
        model = "gpt-5.6-terra"
        model_reasoning_effort = "xhigh"
        sandbox_mode = "read-only"
        """.utf8).write(to: firstConfig, options: .atomic)

        let secondConfig = store.projectConfigURL(rootPath: secondRoot.path)
        try FileManager.default.createDirectory(
            at: secondConfig.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("""
        model = "gpt-5.6-terra"
        model_reasoning_effort = "low"
        approvals_reviewer = "user"
        """.utf8).write(to: secondConfig)
        try writeProjectState(
            [
                "first": ("First", [firstRoot.path]),
                "second": ("Second", [secondRoot.path]),
            ],
            to: store.globalStateURL
        )

        let didRestore = try store.restoreProtectedRoutingState(protected)
        try require(didRestore, "changed routing keys should be restored")
        let restoredGlobalSelection = try store.readSelection(at: store.globalConfigURL)
        try require(
            restoredGlobalSelection
                == CodexConfigSelection(model: "gpt-5.6-luna", reasoningEffort: "high"),
            "global Token Meter defaults should win"
        )
        let restoredGlobal = try String(contentsOf: store.globalConfigURL, encoding: .utf8)
        try require(
            restoredGlobal.contains("personality = \"friendly\""),
            "unrelated external global changes should be preserved"
        )
        let restoredFirstSelection = try store.readSelection(at: firstConfig)
        try require(
            restoredFirstSelection
                == CodexConfigSelection(model: "gpt-5.6-sol", reasoningEffort: "medium"),
            "captured project defaults should be restored"
        )
        let restoredFirst = try String(contentsOf: firstConfig, encoding: .utf8)
        try require(
            restoredFirst.contains("sandbox_mode = \"read-only\""),
            "unrelated project settings should be preserved"
        )
        let restoredSecondSelection = try store.readSelection(at: secondConfig)
        try require(
            restoredSecondSelection == CodexConfigSelection(),
            "projects discovered later should inherit the protected global defaults"
        )
        let restoredSecond = try String(contentsOf: secondConfig, encoding: .utf8)
        try require(
            restoredSecond.contains("approvals_reviewer = \"user\""),
            "clearing a new project override must preserve unrelated settings"
        )
        let didRestoreAgain = try store.restoreProtectedRoutingState(protected)
        try require(!didRestoreAgain, "an already restored configuration should not be rewritten")
    }

    private static func testProtectionPreferenceLifecycle() throws {
        let suiteName = "ModelRoutingProtectionTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw NSError(
                domain: "ModelRoutingStoreTests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "could not create isolated defaults"]
            )
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = CodexModelRoutingProtectionPreferences(defaults: defaults)
        let initial = CodexProtectedRoutingState(
            selectionsByPath: [
                "/tmp/config.toml": CodexConfigSelection(
                    model: "gpt-5.6-luna",
                    reasoningEffort: "high"
                ),
            ]
        )
        try require(!preferences.isEnabled, "protection should default to off")
        preferences.enable(capturing: initial)
        try require(preferences.isEnabled, "enabling protection should persist the toggle")
        try require(
            preferences.protectedState() == initial,
            "enabling protection should persist the Token Meter baseline"
        )

        let updated = CodexProtectedRoutingState(
            selectionsByPath: [
                "/tmp/config.toml": CodexConfigSelection(
                    model: "gpt-5.6-sol",
                    reasoningEffort: "medium"
                ),
            ]
        )
        preferences.updateProtectedState(updated)
        try require(
            preferences.protectedState() == updated,
            "Token Meter edits should update the protected baseline"
        )
        preferences.disable()
        try require(!preferences.isEnabled, "disabling protection should persist the toggle")
        try require(
            preferences.protectedState() == nil,
            "disabling protection should discard the old baseline"
        )
    }

    private static func testAppLifetimeProtectionRestoresExternalRewrite() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-routing-controller-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        let store = CodexModelRoutingStore(codexHomeURL: temporaryRoot)
        try Data("""
        model = "gpt-5.6-sol"
        model_reasoning_effort = "max"
        personality = "pragmatic"
        """.utf8).write(to: store.globalConfigURL)

        let suiteName = "ModelRoutingControllerTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw NSError(
                domain: "ModelRoutingStoreTests",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "could not create controller defaults"]
            )
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = CodexModelRoutingProtectionPreferences(defaults: defaults)
        preferences.enable(capturing: store.captureProtectedRoutingState())
        let watcherReady = DispatchSemaphore(value: 0)
        let controller = CodexModelRoutingProtectionController(
            routingStore: store,
            preferences: preferences,
            callbackQueue: DispatchQueue(label: "ModelRoutingControllerTests.callback"),
            conversationOverrideGraceInterval: 0,
            onWatcherReady: {
                watcherReady.signal()
            }
        )
        defer { withExtendedLifetime(controller) {} }
        guard watcherReady.wait(timeout: .now() + 2) == .success else {
            throw NSError(
                domain: "ModelRoutingStoreTests",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "controller watcher did not become ready"]
            )
        }

        try Data("""
        model = "gpt-5.6-terra"
        model_reasoning_effort = "low"
        personality = "friendly"
        """.utf8).write(to: store.globalConfigURL, options: .atomic)

        let deadline = Date().addingTimeInterval(3)
        var restored = false
        while Date() < deadline {
            if try store.readSelection(at: store.globalConfigURL)
                == CodexConfigSelection(model: "gpt-5.6-sol", reasoningEffort: "max") {
                restored = true
                break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        try require(
            restored,
            "app-lifetime protection should restore an external rewrite without opening the UI"
        )
        let source = try String(contentsOf: store.globalConfigURL, encoding: .utf8)
        try require(
            source.contains("personality = \"friendly\""),
            "app-lifetime protection should preserve unrelated external changes"
        )
    }

    private static func testAppLifetimeProtectionKeepsConversationOverrideBriefly() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-routing-grace-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        let store = CodexModelRoutingStore(codexHomeURL: temporaryRoot)
        let projectRoot = temporaryRoot.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try Data("""
        model = "gpt-5.6-luna"
        model_reasoning_effort = "high"
        """.utf8).write(to: store.globalConfigURL)
        let projectConfigURL = store.projectConfigURL(rootPath: projectRoot.path)
        try FileManager.default.createDirectory(
            at: projectConfigURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("""
        model = "gpt-5.6-terra"
        model_reasoning_effort = "high"
        """.utf8).write(to: projectConfigURL)
        try writeProjectState(
            ["project": ("Project", [projectRoot.path])],
            selectedProjectID: "project",
            to: store.globalStateURL
        )

        let suiteName = "ModelRoutingGraceControllerTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw NSError(
                domain: "ModelRoutingStoreTests",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: "could not create grace controller defaults"]
            )
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = CodexModelRoutingProtectionPreferences(defaults: defaults)
        preferences.enable(capturing: store.captureProtectedRoutingState())
        let watcherReady = DispatchSemaphore(value: 0)
        let controller = CodexModelRoutingProtectionController(
            routingStore: store,
            preferences: preferences,
            callbackQueue: DispatchQueue(label: "ModelRoutingGraceControllerTests.callback"),
            conversationOverrideGraceInterval: 1,
            onWatcherReady: {
                watcherReady.signal()
            }
        )
        defer { withExtendedLifetime(controller) {} }
        guard watcherReady.wait(timeout: .now() + 2) == .success else {
            throw NSError(
                domain: "ModelRoutingStoreTests",
                code: 8,
                userInfo: [NSLocalizedDescriptionKey: "grace controller watcher did not become ready"]
            )
        }

        let selectedForConversation = CodexConfigSelection(
            model: "gpt-5.6-sol",
            reasoningEffort: "max"
        )
        try Data("""
        model = "gpt-5.6-sol"
        model_reasoning_effort = "max"
        """.utf8).write(to: store.globalConfigURL, options: .atomic)

        Thread.sleep(forTimeInterval: 0.7)
        let selectionDuringGracePeriod = try store.readSelection(at: store.globalConfigURL)
        try require(
            selectionDuringGracePeriod == selectedForConversation,
            "protection should leave a brief window for the current conversation override"
        )
        let projectSelectionDuringGracePeriod = try store.readSelection(at: projectConfigURL)
        try require(
            projectSelectionDuringGracePeriod == CodexConfigSelection(),
            "the physical project config must stay clear so Codex Desktop can accept the task override"
        )

        try Data("{}".utf8).write(to: store.modelCacheURL, options: .atomic)
        Thread.sleep(forTimeInterval: 1)
        let restoredGlobalSelection = try store.readSelection(at: store.globalConfigURL)
        try require(
            restoredGlobalSelection
                == CodexConfigSelection(model: "gpt-5.6-terra", reasoningEffort: "high"),
            "model-catalog updates should not postpone restoration beyond the override window"
        )
        let restoredProjectSelection = try store.readSelection(at: projectConfigURL)
        try require(
            restoredProjectSelection == CodexConfigSelection(),
            "the protected project default should remain virtual after restoration"
        )
    }

    private static func testVirtualProjectDefaultsFollowSelectedProject() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-virtual-project-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let codexHome = temporaryRoot.appendingPathComponent("home", isDirectory: true)
        let firstRoot = temporaryRoot.appendingPathComponent("first", isDirectory: true)
        let secondRoot = temporaryRoot.appendingPathComponent("second", isDirectory: true)
        for url in [codexHome, firstRoot, secondRoot] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let store = CodexModelRoutingStore(codexHomeURL: codexHome)
        try Data("""
        model = "gpt-5.6-luna"
        model_reasoning_effort = "low"
        """.utf8).write(to: store.globalConfigURL)
        try writeProjectState(
            [
                "first": ("First", [firstRoot.path]),
                "second": ("Second", [secondRoot.path]),
            ],
            selectedProjectID: "first",
            to: store.globalStateURL
        )
        let firstConfig = store.projectConfigURL(rootPath: firstRoot.path)
        let secondConfig = store.projectConfigURL(rootPath: secondRoot.path)
        for (url, source) in [
            (firstConfig, "model = \"gpt-5.6-terra\"\nmodel_reasoning_effort = \"high\"\n"),
            (secondConfig, "model = \"gpt-5.6-sol\"\nmodel_reasoning_effort = \"medium\"\n"),
        ] {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(source.utf8).write(to: url)
        }

        let suiteName = "VirtualProjectDefaultsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw NSError(
                domain: "ModelRoutingStoreTests",
                code: 9,
                userInfo: [NSLocalizedDescriptionKey: "could not create virtual defaults"]
            )
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = CodexModelRoutingProtectionPreferences(defaults: defaults)
        let protected = store.captureProtectedRoutingState()
        preferences.enable(capturing: protected)
        let watcherReady = DispatchSemaphore(value: 0)
        let controller = CodexModelRoutingProtectionController(
            routingStore: store,
            preferences: preferences,
            callbackQueue: DispatchQueue(label: "VirtualProjectDefaultsTests.callback"),
            conversationOverrideGraceInterval: 0.2,
            onWatcherReady: { watcherReady.signal() }
        )
        defer { withExtendedLifetime(controller) {} }
        guard watcherReady.wait(timeout: .now() + 2) == .success else {
            throw NSError(
                domain: "ModelRoutingStoreTests",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "virtual defaults watcher did not become ready"]
            )
        }
        let firstEffectiveSelection = try store.readSelection(at: store.globalConfigURL)
        try require(
            firstEffectiveSelection
                == CodexConfigSelection(model: "gpt-5.6-terra", reasoningEffort: "high"),
            "the selected project's virtual default should become the effective global default"
        )
        let clearedFirstSelection = try store.readSelection(at: firstConfig)
        let clearedSecondSelection = try store.readSelection(at: secondConfig)
        try require(
            clearedFirstSelection == CodexConfigSelection()
                && clearedSecondSelection == CodexConfigSelection(),
            "physical project routing overrides should be removed"
        )

        try writeProjectState(
            [
                "first": ("First", [firstRoot.path]),
                "second": ("Second", [secondRoot.path]),
            ],
            selectedProjectID: "second",
            to: store.globalStateURL
        )
        let deadline = Date().addingTimeInterval(3)
        var switched = false
        while Date() < deadline {
            if try store.readSelection(at: store.globalConfigURL)
                == CodexConfigSelection(model: "gpt-5.6-sol", reasoningEffort: "medium") {
                switched = true
                break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        try require(switched, "switching projects should activate that project's virtual default")

        let snapshot = store.loadSnapshot(protectedState: protected)
        try require(snapshot.projects[0].model == .value("gpt-5.6-terra"), "the UI should show the first virtual default")
        try require(snapshot.projects[1].model == .value("gpt-5.6-sol"), "the UI should show the second virtual default")
    }

    private static func testActiveProjectResolverUsesRecentMatchingTask() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-active-project-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let codexHome = temporaryRoot.appendingPathComponent("home", isDirectory: true)
        let projectRoot = temporaryRoot.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let store = CodexModelRoutingStore(codexHomeURL: codexHome)
        try writeProjectState(
            ["project": ("Project", [projectRoot.path])],
            to: store.globalStateURL
        )

        let databaseURL = codexHome.appendingPathComponent("state_5.sqlite")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [databaseURL.path, """
        CREATE TABLE threads (cwd TEXT, model TEXT, reasoning_effort TEXT, archived INTEGER, updated_at_ms INTEGER);
        INSERT INTO threads VALUES ('\(projectRoot.path)', 'gpt-5.6-sol', 'max', 0, 1234567890000);
        """]
        try process.run()
        process.waitUntilExit()
        try require(process.terminationStatus == 0, "test state database should be created")

        let resolver = CodexActiveProjectConfigResolver(
            routingStore: store,
            now: { Date(timeIntervalSince1970: 1_234_567_890) }
        )
        let resolved = resolver.mostRecentlySelectedProjectConfigURL(
            matching: CodexConfigSelection(model: "gpt-5.6-sol", reasoningEffort: "max")
        )
        try require(
            resolved == store.projectConfigURL(rootPath: projectRoot.path),
            "a recent matching Codex task should identify only its project config"
        )
    }

    private static func writeProjectState(
        _ projects: [String: (String, [String])],
        selectedProjectID: String? = nil,
        to url: URL
    ) throws {
        let localProjects = Dictionary(uniqueKeysWithValues: projects.map { id, value in
            (
                id,
                [
                    "name": value.0,
                    "rootPaths": value.1,
                ] as [String: Any]
            )
        })
        var object: [String: Any] = [
            "local-projects": localProjects,
            "project-order": projects.keys.sorted(),
        ]
        if let selectedProjectID {
            object["selected-project"] = [
                "type": "local",
                "projectId": selectedProjectID,
            ]
        }
        try JSONSerialization.data(withJSONObject: object).write(to: url)
    }

    private static func testClaudeJSONUpdatePreservesOtherSettings() throws {
        let source = Data("""
        {
          "model": "sonnet",
          "effortLevel": "medium",
          "permissions": {
            "allow": ["Read"]
          },
          "tui": {
            "theme": "dark"
          }
        }
        """.utf8)
        let updated = try ClaudeModelRoutingStore.updatedJSON(
            source,
            selection: CodexConfigSelection(model: "opus", reasoningEffort: "xhigh")
        )
        let object = try JSONSerialization.jsonObject(with: updated) as? [String: Any]
        try require(object?["model"] as? String == "opus", "Claude model should be replaced")
        try require(object?["effortLevel"] as? String == "xhigh", "Claude effort should be replaced")
        try require(object?["permissions"] != nil, "unrelated Claude permissions should be preserved")
        try require(object?["tui"] != nil, "unrelated Claude UI settings should be preserved")

        let inherited = try ClaudeModelRoutingStore.updatedJSON(
            updated,
            selection: CodexConfigSelection(model: nil, reasoningEffort: nil)
        )
        let inheritedObject = try JSONSerialization.jsonObject(with: inherited) as? [String: Any]
        try require(inheritedObject?["model"] == nil, "Claude model override should be removable")
        try require(inheritedObject?["effortLevel"] == nil, "Claude effort override should be removable")
        try require(inheritedObject?["permissions"] != nil, "clearing routing must preserve other settings")
    }

    private static func testClaudeModelCatalogMatchesCurrentSelector() throws {
        let models = ClaudeModelRoutingStore(projectsProvider: { [] }).loadModels()
        try require(
            models.map(\.slug) == [
                "default",
                "fable",
                "opus",
                "sonnet",
                "haiku",
                "claude-opus-4-8",
                "claude-opus-4-7",
                "claude-opus-4-6",
                "claude-sonnet-4-6",
            ],
            "Claude model choices should follow the current Claude Code selector"
        )
        try require(
            models.map(\.displayName) == [
                "Sonnet 5 · Default",
                "Fable 5",
                "Opus 5",
                "Sonnet 5",
                "Haiku 4.5",
                "Opus 4.8",
                "Opus 4.7",
                "Opus 4.6",
                "Sonnet 4.6",
            ],
            "Claude model choices should show the versions users see in Claude Code"
        )
    }

    private static func testClaudeProjectWritesStayLocal() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-model-routing-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let claudeHome = temporaryRoot.appendingPathComponent(".claude", isDirectory: true)
        let projectRoot = temporaryRoot.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try Data("""
        {
          "permissions": {
            "deny": ["Read(.env)"]
          }
        }
        """.utf8).write(to: claudeHome.appendingPathComponent("settings.json"))
        let project = CodexSavedProject(
            id: "claude-project",
            name: "Claude Project",
            rootPaths: [projectRoot.path]
        )
        let store = ClaudeModelRoutingStore(
            claudeHomeURL: claudeHome,
            projectsProvider: { [project] }
        )

        try store.writeGlobal(model: "opus", reasoningEffort: "xhigh")
        try store.writeProject(
            id: project.id,
            model: "sonnet",
            reasoningEffort: "high"
        )
        let global = try store.readSelection(at: store.globalConfigURL)
        try require(
            global == CodexConfigSelection(model: "opus", reasoningEffort: "xhigh"),
            "Claude global defaults should be written"
        )
        try store.writeGlobal(model: "default", reasoningEffort: "high")
        let defaultGlobal = try store.readSelection(at: store.globalConfigURL)
        try require(
            defaultGlobal == CodexConfigSelection(model: nil, reasoningEffort: "high"),
            "Claude Default should clear the persisted model override"
        )
        do {
            try store.writeGlobal(model: "opus", reasoningEffort: "max")
            try require(false, "Claude max effort must not be persisted")
        } catch ClaudeModelRoutingStoreError.unsupportedPersistentEffort("max") {
            // Expected: max remains available only for an active Claude session.
        }
        let localURL = store.projectConfigURL(rootPath: projectRoot.path)
        try require(
            localURL.lastPathComponent == "settings.local.json",
            "Claude project writes must target private local settings"
        )
        let local = try store.readSelection(at: localURL)
        try require(
            local == CodexConfigSelection(model: "sonnet", reasoningEffort: "high"),
            "Claude project defaults should be read back"
        )
        try require(
            !FileManager.default.fileExists(
                atPath: projectRoot
                    .appendingPathComponent(".claude/settings.json")
                    .path
            ),
            "Claude shared project settings must not be created"
        )

        let snapshot = store.loadSnapshot()
        try require(snapshot.projects.count == 1, "Claude projects should be discovered")
        try require(snapshot.projects[0].model == .value("sonnet"), "Claude project model should be explicit")
        try require(snapshot.projects[0].reasoningEffort == .value("high"), "Claude project effort should be explicit")

        try store.writeProject(id: project.id, model: nil, reasoningEffort: nil)
        let inherited = store.loadSnapshot()
        try require(inherited.projects[0].inheritsEverything, "Claude project should be able to follow global")
    }

    private static func testClaudeSharedProjectSettingsRemainUntouched() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-shared-routing-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let claudeHome = temporaryRoot.appendingPathComponent(".claude", isDirectory: true)
        let projectRoot = temporaryRoot.appendingPathComponent("project", isDirectory: true)
        let sharedURL = projectRoot
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(at: claudeHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: sharedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let sharedData = Data("""
        {
          "model": "sonnet",
          "effortLevel": "medium",
          "permissions": {
            "allow": ["Read"]
          }
        }
        """.utf8)
        try sharedData.write(to: sharedURL)
        let project = CodexSavedProject(
            id: "shared-project",
            name: "Shared Project",
            rootPaths: [projectRoot.path]
        )
        let store = ClaudeModelRoutingStore(
            claudeHomeURL: claudeHome,
            projectsProvider: { [project] }
        )

        let sharedSnapshot = store.loadSnapshot()
        try require(
            sharedSnapshot.projects[0].model == .value("sonnet"),
            "shared Claude project model should be reflected"
        )
        try require(
            sharedSnapshot.projects[0].blocksGlobalInheritance,
            "shared Claude routing should block the follow-global control"
        )

        try store.writeProject(id: project.id, model: "opus", reasoningEffort: "high")
        let preservedSharedData = try Data(contentsOf: sharedURL)
        try require(
            preservedSharedData == sharedData,
            "writing a private override must not modify shared Claude settings"
        )
        let local = try store.readSelection(at: store.projectConfigURL(rootPath: projectRoot.path))
        try require(
            local == CodexConfigSelection(model: "opus", reasoningEffort: "high"),
            "private settings should override shared Claude routing"
        )
    }

    private static func testClaudeProtectedDefaultsRestoreOnlyPrivateRoutingKeys() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-routing-protection-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let claudeHome = temporaryRoot.appendingPathComponent(".claude", isDirectory: true)
        let projectRoot = temporaryRoot.appendingPathComponent("project", isDirectory: true)
        let sharedURL = projectRoot.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: sharedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claudeHome, withIntermediateDirectories: true)
        try Data("{\"model\":\"sonnet\",\"effortLevel\":\"high\",\"permissions\":{\"allow\":[\"Read\"]}}".utf8).write(to: claudeHome.appendingPathComponent("settings.json"))
        let sharedData = Data("{\"model\":\"opus\",\"effortLevel\":\"medium\",\"permissions\":{\"deny\":[\"Read(.env)\"]}}".utf8)
        try sharedData.write(to: sharedURL)
        let project = CodexSavedProject(id: "protected-project", name: "Protected", rootPaths: [projectRoot.path])
        let store = ClaudeModelRoutingStore(claudeHomeURL: claudeHome, projectsProvider: { [project] })
        try store.writeProject(id: project.id, model: "haiku", reasoningEffort: nil)
        let protected = store.captureProtectedRoutingState()
        try Data("{\"model\":\"fable\",\"effortLevel\":\"low\",\"permissions\":{\"allow\":[\"Bash\"]}}".utf8).write(to: store.globalConfigURL)
        let localURL = store.projectConfigURL(rootPath: projectRoot.path)
        try Data("{\"model\":\"opus\",\"effortLevel\":\"xhigh\",\"hooks\":{\"PostToolUse\":[]}}".utf8).write(to: localURL)
        let restored = try store.restoreProtectedRoutingState(protected)
        let restoredGlobal = try store.readSelection(at: store.globalConfigURL)
        let restoredLocal = try store.readSelection(at: localURL)
        let global = try String(contentsOf: store.globalConfigURL, encoding: .utf8)
        let local = try String(contentsOf: localURL, encoding: .utf8)
        let finalSharedData = try Data(contentsOf: sharedURL)
        try require(restored, "Claude protection should restore changed routing values")
        try require(restoredGlobal == CodexConfigSelection(model: "sonnet", reasoningEffort: "high"), "Claude protection should restore global model defaults")
        try require(restoredLocal == CodexConfigSelection(model: "haiku", reasoningEffort: nil), "Claude protection should restore private project model defaults")
        try require(global.contains("Bash"), "Claude protection must preserve unrelated global settings")
        try require(local.contains("PostToolUse"), "Claude protection must preserve unrelated private project settings")
        try require(finalSharedData == sharedData, "Claude protection must not modify shared project settings")
    }

    private static func testClaudeAppLifetimeProtectionRestoresExternalRewrite() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-routing-controller-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        let store = ClaudeModelRoutingStore(claudeHomeURL: temporaryRoot, projectsProvider: { [] })
        try Data("{\"model\":\"sonnet\",\"effortLevel\":\"high\",\"permissions\":{\"allow\":[\"Read\"]}}".utf8).write(to: store.globalConfigURL)
        let suiteName = "ClaudeModelRoutingControllerTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw NSError(domain: "ModelRoutingStoreTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "could not create isolated defaults"])
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = ClaudeModelRoutingProtectionPreferences(defaults: defaults)
        preferences.enable(capturing: store.captureProtectedRoutingState())
        let watcherReady = DispatchSemaphore(value: 0)
        let controller = ClaudeModelRoutingProtectionController(
            routingStore: store,
            preferences: preferences,
            callbackQueue: DispatchQueue(label: "ClaudeModelRoutingControllerTests.callback"),
            onWatcherReady: { watcherReady.signal() }
        )
        defer { withExtendedLifetime(controller) {} }
        guard watcherReady.wait(timeout: .now() + 2) == .success else {
            throw NSError(domain: "ModelRoutingStoreTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "controller watcher did not become ready"])
        }
        try Data("{\"model\":\"opus\",\"effortLevel\":\"low\",\"permissions\":{\"allow\":[\"Bash\"]}}".utf8).write(to: store.globalConfigURL, options: .atomic)
        let deadline = Date().addingTimeInterval(3)
        var restored = false
        while Date() < deadline {
            if try store.readSelection(at: store.globalConfigURL) == CodexConfigSelection(model: "sonnet", reasoningEffort: "high") {
                restored = true
                break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        try require(restored, "Claude app-lifetime protection should restore an external rewrite without opening the UI")
        let source = try String(contentsOf: store.globalConfigURL, encoding: .utf8)
        try require(source.contains("Bash"), "Claude app-lifetime protection must preserve unrelated external settings")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw NSError(domain: "ModelRoutingStoreTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
