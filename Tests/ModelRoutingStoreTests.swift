import Foundation

@main
struct ModelRoutingStoreTests {
    static func main() throws {
        try testTopLevelTOMLUpdatePreservesOtherContent()
        try testProjectGroupWritesEveryRoot()
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
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw NSError(domain: "ModelRoutingStoreTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
