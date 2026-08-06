import Foundation

enum ClaudeModelRoutingStoreError: LocalizedError {
    case invalidJSON(String)
    case invalidRootObject(String)
    case missingProject(String)
    case unsupportedPersistentEffort(String)

    var errorDescription: String? {
        switch self {
        case let .invalidJSON(path):
            return "The Claude settings file is not valid JSON: \(path)"
        case let .invalidRootObject(path):
            return "The Claude settings file must contain a JSON object: \(path)"
        case let .missingProject(id):
            return "The Claude project could not be found: \(id)"
        case let .unsupportedPersistentEffort(effort):
            return "Claude effort \"\(effort)\" is session-only and cannot be saved in settings."
        }
    }
}

/// Reads and writes Claude Code's user default plus private per-project
/// overrides. Project writes intentionally target settings.local.json so this
/// app never changes a repository's shared Claude configuration.
final class ClaudeModelRoutingStore {
    static let persistentEfforts = Set(["low", "medium", "high", "xhigh"])

    let claudeHomeURL: URL
    private let fileManager: FileManager
    private let projectsProvider: () -> [CodexSavedProject]

    init(
        claudeHomeURL: URL = ClaudeModelRoutingStore.defaultClaudeHomeURL(),
        fileManager: FileManager = .default,
        projectsProvider: @escaping () -> [CodexSavedProject] = {
            CodexModelRoutingStore().loadProjects()
        }
    ) {
        self.claudeHomeURL = claudeHomeURL.standardizedFileURL
        self.fileManager = fileManager
        self.projectsProvider = projectsProvider
    }

    static func defaultClaudeHomeURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let override = environment["CLAUDE_CONFIG_DIR"]?
            .split(separator: ",", maxSplits: 1)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(
                fileURLWithPath: (override as NSString).expandingTildeInPath,
                isDirectory: true
            )
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
    }

    var globalConfigURL: URL {
        claudeHomeURL.appendingPathComponent("settings.json")
    }

    func loadSnapshot() -> CodexModelRoutingSnapshot {
        let global = (try? readSelection(at: globalConfigURL)) ?? CodexConfigSelection()
        let projects = loadProjects().map { project in
            var hasSharedProjectOverride = false
            let rootSelections = project.rootPaths.map { rootPath in
                let shared = (try? readSelection(
                    at: sharedProjectConfigURL(rootPath: rootPath)
                )) ?? CodexConfigSelection()
                let local = (try? readSelection(
                    at: projectConfigURL(rootPath: rootPath)
                )) ?? CodexConfigSelection()
                if shared.model != nil || shared.reasoningEffort != nil {
                    hasSharedProjectOverride = true
                }
                return CodexConfigSelection(
                    model: local.model ?? shared.model,
                    reasoningEffort: local.reasoningEffort ?? shared.reasoningEffort
                )
            }
            return CodexProjectRoutingSnapshot(
                project: project,
                model: mergedValue(rootSelections.map(\.model)),
                reasoningEffort: mergedValue(rootSelections.map(\.reasoningEffort)),
                blocksGlobalInheritance: hasSharedProjectOverride
            )
        }
        return CodexModelRoutingSnapshot(
            global: global,
            models: loadModels(),
            projects: projects
        )
    }

    func routingInputURLs(for snapshot: CodexModelRoutingSnapshot) -> [URL] {
        [globalConfigURL] + snapshot.projects.flatMap { project in
            project.project.rootPaths.flatMap { rootPath in
                [
                    sharedProjectConfigURL(rootPath: rootPath),
                    projectConfigURL(rootPath: rootPath),
                ]
            }
        }
    }

    func writeGlobal(model: String, reasoningEffort: String?) throws {
        try validatePersistentEffort(reasoningEffort)
        try writeSelection(
            CodexConfigSelection(
                model: model == "default" ? nil : model,
                reasoningEffort: reasoningEffort
            ),
            at: globalConfigURL
        )
    }

    func writeProject(
        id: String,
        model: String?,
        reasoningEffort: String?
    ) throws {
        try validatePersistentEffort(reasoningEffort)
        guard let project = loadProjects().first(where: { $0.id == id }) else {
            throw ClaudeModelRoutingStoreError.missingProject(id)
        }
        let selection = CodexConfigSelection(
            model: model == "default" ? nil : model,
            reasoningEffort: reasoningEffort
        )
        for rootPath in project.rootPaths {
            try writeSelection(selection, at: projectConfigURL(rootPath: rootPath))
        }
    }

    func readSelection(at url: URL) throws -> CodexConfigSelection {
        guard fileManager.fileExists(atPath: url.path) else {
            return CodexConfigSelection()
        }
        let object = try readObject(at: url)
        return CodexConfigSelection(
            model: object["model"] as? String,
            reasoningEffort: object["effortLevel"] as? String
        )
    }

    func loadProjects() -> [CodexSavedProject] {
        projectsProvider()
    }

    func loadModels() -> [CodexModelOption] {
        [
            CodexModelOption(
                slug: "default",
                displayName: "Sonnet 5 · Default",
                description: "Use Claude Code's default model, currently Sonnet 5.",
                defaultReasoningEffort: "high",
                supportedReasoningEfforts: ["low", "medium", "high", "xhigh"]
            ),
            CodexModelOption(
                slug: "fable",
                displayName: "Fable 5",
                description: "Claude's model for the hardest and longest-running tasks.",
                defaultReasoningEffort: "high",
                supportedReasoningEfforts: ["low", "medium", "high", "xhigh"]
            ),
            CodexModelOption(
                slug: "opus",
                displayName: "Opus 5",
                description: "Claude's model for everyday complex tasks.",
                defaultReasoningEffort: "xhigh",
                supportedReasoningEfforts: ["low", "medium", "high", "xhigh"]
            ),
            CodexModelOption(
                slug: "sonnet",
                displayName: "Sonnet 5",
                description: "Claude's efficient model for routine coding tasks.",
                defaultReasoningEffort: "high",
                supportedReasoningEfforts: ["low", "medium", "high", "xhigh"]
            ),
            CodexModelOption(
                slug: "haiku",
                displayName: "Haiku 4.5",
                description: "Claude's fastest model for quick answers.",
                defaultReasoningEffort: "",
                supportedReasoningEfforts: []
            ),
            CodexModelOption(
                slug: "claude-opus-4-8",
                displayName: "Opus 4.8",
                description: "Previous Claude Opus version.",
                defaultReasoningEffort: "high",
                supportedReasoningEfforts: ["low", "medium", "high", "xhigh"]
            ),
            CodexModelOption(
                slug: "claude-opus-4-7",
                displayName: "Opus 4.7",
                description: "Previous Claude Opus version.",
                defaultReasoningEffort: "high",
                supportedReasoningEfforts: ["low", "medium", "high", "xhigh"]
            ),
            CodexModelOption(
                slug: "claude-opus-4-6",
                displayName: "Opus 4.6",
                description: "Previous Claude Opus version.",
                defaultReasoningEffort: "high",
                supportedReasoningEfforts: ["low", "medium", "high", "xhigh"]
            ),
            CodexModelOption(
                slug: "claude-sonnet-4-6",
                displayName: "Sonnet 4.6",
                description: "Previous Claude Sonnet version.",
                defaultReasoningEffort: "high",
                supportedReasoningEfforts: ["low", "medium", "high", "xhigh"]
            ),
        ]
    }

    func projectConfigURL(rootPath: String) -> URL {
        URL(fileURLWithPath: rootPath, isDirectory: true)
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.local.json")
    }

    func sharedProjectConfigURL(rootPath: String) -> URL {
        URL(fileURLWithPath: rootPath, isDirectory: true)
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    static func updatedJSON(
        _ source: Data?,
        selection: CodexConfigSelection,
        path: String = "settings.json"
    ) throws -> Data {
        var object: [String: Any] = [:]
        if let source, !source.isEmpty {
            let raw: Any
            do {
                raw = try JSONSerialization.jsonObject(with: source)
            } catch {
                throw ClaudeModelRoutingStoreError.invalidJSON(path)
            }
            guard let dictionary = raw as? [String: Any] else {
                throw ClaudeModelRoutingStoreError.invalidRootObject(path)
            }
            object = dictionary
        }

        if let model = selection.model {
            object["model"] = model
        } else {
            object.removeValue(forKey: "model")
        }
        if let reasoningEffort = selection.reasoningEffort {
            object["effortLevel"] = reasoningEffort
        } else {
            object.removeValue(forKey: "effortLevel")
        }

        var data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        data.append(0x0A)
        return data
    }

    private func writeSelection(_ selection: CodexConfigSelection, at url: URL) throws {
        let exists = fileManager.fileExists(atPath: url.path)
        if !exists, selection.model == nil, selection.reasoningEffort == nil {
            return
        }
        let existing = exists ? try Data(contentsOf: url) : nil
        let updated = try Self.updatedJSON(existing, selection: selection, path: url.path)
        if !exists {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }
        try updated.write(to: url, options: .atomic)
    }

    private func validatePersistentEffort(_ effort: String?) throws {
        guard let effort, !Self.persistentEfforts.contains(effort) else { return }
        throw ClaudeModelRoutingStoreError.unsupportedPersistentEffort(effort)
    }

    private func readObject(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ClaudeModelRoutingStoreError.invalidJSON(url.path)
        }
        guard let object = raw as? [String: Any] else {
            throw ClaudeModelRoutingStoreError.invalidRootObject(url.path)
        }
        return object
    }

    private func mergedValue(_ values: [String?]) -> CodexProjectConfigValue {
        guard let first = values.first else { return .inherited }
        if values.dropFirst().contains(where: { $0 != first }) {
            return .mixed
        }
        return first.map(CodexProjectConfigValue.value) ?? .inherited
    }
}
