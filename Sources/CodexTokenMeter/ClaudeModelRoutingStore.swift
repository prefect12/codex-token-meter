import Foundation

enum ClaudeModelRoutingStoreError: LocalizedError {
    case invalidJSON(String)
    case invalidRootObject(String)
    case missingProject(String)
    case unsupportedPersistentEffort(String)
    case invalidCompactionSetting(String)

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
        case let .invalidCompactionSetting(path):
            return "The Claude compaction settings are invalid: \(path)"
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
                if shared.model != nil || shared.reasoningEffort != nil
                    || shared.contextWindow != nil || shared.autoCompactTokenLimit != nil {
                    hasSharedProjectOverride = true
                }
                return CodexConfigSelection(
                    model: local.model ?? shared.model,
                    reasoningEffort: local.reasoningEffort ?? shared.reasoningEffort,
                    contextWindow: local.contextWindow ?? shared.contextWindow,
                    autoCompactTokenLimit: local.autoCompactTokenLimit ?? shared.autoCompactTokenLimit
                )
            }
            return CodexProjectRoutingSnapshot(
                project: project,
                model: mergedValue(rootSelections.map(\.model)),
                reasoningEffort: mergedValue(rootSelections.map(\.reasoningEffort)),
                contextWindow: mergedIntegerValue(rootSelections.map(\.contextWindow)),
                autoCompactTokenLimit: mergedIntegerValue(rootSelections.map(\.autoCompactTokenLimit)),
                planModeReasoningEffort: .inherited,
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

    /// Shared project settings are display inputs, not Token Meter-owned
    /// defaults, and must not be included in protection or restoration.
    func protectedRoutingInputURLs(for snapshot: CodexModelRoutingSnapshot) -> [URL] {
        [globalConfigURL] + snapshot.projects.flatMap { project in
            project.project.rootPaths.map(projectConfigURL(rootPath:))
        }
    }

    func captureProtectedRoutingState() -> CodexProtectedRoutingState {
        var selections = [
            globalConfigURL.standardizedFileURL.path:
                ((try? readSelection(at: globalConfigURL)) ?? CodexConfigSelection())
        ]
        for project in loadProjects() {
            for rootPath in project.rootPaths {
                let url = projectConfigURL(rootPath: rootPath).standardizedFileURL
                selections[url.path] = (try? readSelection(at: url)) ?? CodexConfigSelection()
            }
        }
        return CodexProtectedRoutingState(selectionsByPath: selections)
    }

    /// Restores only the routing and compaction keys managed by Token Meter.
    @discardableResult
    func restoreProtectedRoutingState(_ state: CodexProtectedRoutingState) throws -> Bool {
        guard state.version == CodexProtectedRoutingState.currentVersion else { return false }
        var changed = false
        let globalPath = globalConfigURL.standardizedFileURL.path
        if let desiredGlobal = state.selectionsByPath[globalPath],
           try readSelection(at: globalConfigURL) != desiredGlobal {
            try writeSelection(desiredGlobal, at: globalConfigURL)
            changed = true
        }
        for project in loadProjects() {
            for rootPath in project.rootPaths {
                let url = projectConfigURL(rootPath: rootPath).standardizedFileURL
                let desired = state.selectionsByPath[url.path] ?? CodexConfigSelection()
                if try readSelection(at: url) != desired {
                    try writeSelection(desired, at: url)
                    changed = true
                }
            }
        }
        return changed
    }

    func writeGlobal(model: String, reasoningEffort: String?, compactWindow: Int? = nil, compactPercent: Int? = nil) throws {
        try validatePersistentEffort(reasoningEffort)
        try validateCompaction(window: compactWindow, percent: compactPercent)
        try writeSelection(
            CodexConfigSelection(
                model: model.isEmpty || model == "default" ? nil : model,
                reasoningEffort: reasoningEffort,
                contextWindow: compactWindow,
                autoCompactTokenLimit: compactPercent
            ),
            at: globalConfigURL
        )
    }

    func writeProject(
        id: String,
        model: String?,
        reasoningEffort: String?,
        compactWindow: Int? = nil,
        compactPercent: Int? = nil
    ) throws {
        try validatePersistentEffort(reasoningEffort)
        try validateCompaction(window: compactWindow, percent: compactPercent)
        guard let project = loadProjects().first(where: { $0.id == id }) else {
            throw ClaudeModelRoutingStoreError.missingProject(id)
        }
        let selection = CodexConfigSelection(
            model: model == "default" ? nil : model,
            reasoningEffort: reasoningEffort,
            contextWindow: compactWindow,
            autoCompactTokenLimit: compactPercent
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
        let env = object["env"] as? [String: Any] ?? [:]
        let model = object["model"] as? String
        var effort = object["effortLevel"] as? String
        if url.standardizedFileURL == globalConfigURL.standardizedFileURL,
           let model, Self.canonicalEffortModelID(for: model) == "claude-opus-5-5" {
            let modelSettings = object["modelSettings"] as? [String: Any]
            let opusSettings = modelSettings?["claude-opus-5-5"] as? [String: Any]
            // Opus 5.5 ignores the legacy top-level effortLevel in user settings.
            effort = opusSettings?["effortLevel"] as? String
        }
        return CodexConfigSelection(
            model: model,
            reasoningEffort: effort,
            contextWindow: Self.integer(env["CLAUDE_CODE_AUTO_COMPACT_WINDOW"])
                ?? Self.integer(object["autoCompactWindow"]),
            autoCompactTokenLimit: Self.integer(env["CLAUDE_AUTOCOMPACT_PCT_OVERRIDE"])
        )
    }

    func loadProjects() -> [CodexSavedProject] {
        projectsProvider()
    }

    func loadModels() -> [CodexModelOption] {
        [
            CodexModelOption(
                slug: "default",
                displayName: "Claude Code Default",
                description: "Use the runtime default for your account and provider.",
                defaultReasoningEffort: "high",
                supportedReasoningEfforts: ["low", "medium", "high", "xhigh"]
            ),
            CodexModelOption(
                slug: "fable",
                displayName: "Fable · Latest",
                description: "Use the Fable version selected by Claude Code and your provider.",
                defaultReasoningEffort: "high",
                supportedReasoningEfforts: ["low", "medium", "high", "xhigh"]
            ),
            CodexModelOption(
                slug: "opus",
                displayName: "Opus",
                description: "Use the Opus version selected by Claude Code and your provider.",
                defaultReasoningEffort: "medium",
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
                slug: "claude-fable-5-1",
                displayName: "Fable 5.1",
                description: "Pin Fable 5.1; requires Claude Code 2.1.257 or newer and provider access.",
                defaultReasoningEffort: "high",
                supportedReasoningEfforts: ["low", "medium", "high", "xhigh"]
            ),
            CodexModelOption(
                slug: "claude-opus-5-5",
                displayName: "Opus 5.5",
                description: "Pin Opus 5.5; requires Claude Code 2.1.280 or newer and provider access.",
                defaultReasoningEffort: "medium",
                supportedReasoningEfforts: ["low", "medium", "high", "xhigh"]
            ),
            CodexModelOption(
                slug: "claude-fable-5",
                displayName: "Fable 5",
                description: "Previous Claude Fable version.",
                defaultReasoningEffort: "high",
                supportedReasoningEfforts: ["low", "medium", "high", "xhigh"]
            ),
            CodexModelOption(
                slug: "claude-opus-5",
                displayName: "Opus 5",
                description: "Previous Claude Opus version.",
                defaultReasoningEffort: "high",
                supportedReasoningEfforts: ["low", "medium", "high", "xhigh"]
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
        projectLocalSettingsRoot(rootPath: rootPath)
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.local.json")
    }

    /// Claude Code v2.1.211+ keeps project-local settings at the main checkout
    /// root for every linked Git worktree, including sessions started below it.
    private func projectLocalSettingsRoot(rootPath: String) -> URL {
        let start = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
        var directory = start
        while true {
            let gitEntry = directory.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: gitEntry.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue { return directory }
                if let contents = try? String(contentsOf: gitEntry, encoding: .utf8),
                   let gitdir = contents.split(separator: "\n").first,
                   gitdir.hasPrefix("gitdir: ") {
                    let rawGitdir = String(gitdir.dropFirst("gitdir: ".count))
                    let gitDirectory = URL(fileURLWithPath: rawGitdir,
                        relativeTo: directory).standardizedFileURL
                    let commonFile = gitDirectory.appendingPathComponent("commondir")
                    if let rawCommon = try? String(contentsOf: commonFile, encoding: .utf8) {
                        let common = URL(fileURLWithPath: rawCommon.trimmingCharacters(in: .whitespacesAndNewlines),
                            relativeTo: gitDirectory).standardizedFileURL
                        if common.lastPathComponent == ".git" {
                            return common.deletingLastPathComponent()
                        }
                    }
                }
                return directory
            }
            if directory.path == "/" { return start }
            directory = directory.deletingLastPathComponent().standardizedFileURL
        }
    }

    func sharedProjectConfigURL(rootPath: String) -> URL {
        URL(fileURLWithPath: rootPath, isDirectory: true)
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    static func updatedJSON(
        _ source: Data?,
        selection: CodexConfigSelection,
        path: String = "settings.json",
        globalUserSettings: Bool = false
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
        } else if !globalUserSettings {
            object.removeValue(forKey: "effortLevel")
        }

        if globalUserSettings, let model = selection.model,
           let canonical = canonicalEffortModelID(for: model) {
            if object["modelSettings"] != nil && !(object["modelSettings"] is [String: Any]) {
                throw ClaudeModelRoutingStoreError.invalidRootObject(path)
            }
            var modelSettings = object["modelSettings"] as? [String: Any] ?? [:]
            var perModel = modelSettings[canonical] as? [String: Any] ?? [:]
            if let reasoningEffort = selection.reasoningEffort {
                perModel["effortLevel"] = reasoningEffort
            } else {
                perModel.removeValue(forKey: "effortLevel")
            }
            if perModel.isEmpty { modelSettings.removeValue(forKey: canonical) }
            else { modelSettings[canonical] = perModel }
            if !modelSettings.isEmpty { object["modelSettings"] = modelSettings }
            else { object.removeValue(forKey: "modelSettings") }
        }

        if let window = selection.contextWindow {
            object["autoCompactWindow"] = window
        } else {
            object.removeValue(forKey: "autoCompactWindow")
        }

        if object["env"] != nil && !(object["env"] is [String: Any]) {
            throw ClaudeModelRoutingStoreError.invalidCompactionSetting(path)
        }
        var env = object["env"] as? [String: Any] ?? [:]
        // Migrate the earlier Token Meter env override so /autocompact and
        // --autocompact can control the new, ordinary settings key.
        env.removeValue(forKey: "CLAUDE_CODE_AUTO_COMPACT_WINDOW")
        if let percent = selection.autoCompactTokenLimit {
            env["CLAUDE_AUTOCOMPACT_PCT_OVERRIDE"] = String(percent)
        } else {
            env.removeValue(forKey: "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE")
        }
        if !env.isEmpty {
            object["env"] = env
        } else {
            object.removeValue(forKey: "env")
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
        if !exists, selection.model == nil, selection.reasoningEffort == nil,
           selection.contextWindow == nil, selection.autoCompactTokenLimit == nil {
            return
        }
        let existing = exists ? try Data(contentsOf: url) : nil
        let updated = try Self.updatedJSON(
            existing, selection: selection, path: url.path,
            globalUserSettings: url.standardizedFileURL == globalConfigURL.standardizedFileURL
        )
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

    private func validateCompaction(window: Int?, percent: Int?) throws {
        if let window, !(100_000...1_000_000).contains(window) {
            throw ClaudeModelRoutingStoreError.invalidCompactionSetting("compact window")
        }
        if let percent, !(1...100).contains(percent) {
            throw ClaudeModelRoutingStoreError.invalidCompactionSetting("compact percent")
        }
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? String { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func canonicalEffortModelID(for model: String) -> String? {
        let base = model.replacingOccurrences(of: "[1m]", with: "")
        switch base {
        case "opus": return "claude-opus-5-5"
        case "sonnet": return "claude-sonnet-5"
        case "fable": return "claude-fable-5-1"
        default: return base.hasPrefix("claude-") ? base : nil
        }
    }

    private func mergedIntegerValue(_ values: [Int?]) -> CodexProjectConfigValue {
        mergedValue(values.map { $0.map(String.init) })
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
