import Foundation

@main
struct ModelRoutingStoreTests {
    static func main() throws {
        try testTopLevelTOMLUpdatePreservesOtherContent()
        try testProjectGroupWritesEveryRoot()
        try testClaudeJSONUpdatePreservesOtherSettings()
        try testClaudeProjectWritesStayLocal()
        try testClaudeSharedProjectSettingsRemainUntouched()
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

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw NSError(domain: "ModelRoutingStoreTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
