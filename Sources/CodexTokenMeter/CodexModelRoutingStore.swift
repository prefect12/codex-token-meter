import Foundation

struct CodexModelOption: Equatable {
    let slug: String
    let displayName: String
    let description: String
    let defaultReasoningEffort: String
    let supportedReasoningEfforts: [String]
}

struct CodexConfigSelection: Codable, Equatable {
    var model: String?
    var reasoningEffort: String?
    var contextWindow: Int?
    var autoCompactTokenLimit: Int?
    var planModeReasoningEffort: String? = nil
}

struct CodexProtectedRoutingState: Codable, Equatable {
    static let currentVersion = 1

    let version: Int
    let selectionsByPath: [String: CodexConfigSelection]

    init(
        version: Int = CodexProtectedRoutingState.currentVersion,
        selectionsByPath: [String: CodexConfigSelection]
    ) {
        self.version = version
        self.selectionsByPath = selectionsByPath
    }
}

enum CodexProjectConfigValue: Equatable {
    case inherited
    case value(String)
    case mixed

    var explicitValue: String? {
        if case let .value(value) = self {
            return value
        }
        return nil
    }
}

struct CodexSavedProject: Equatable {
    let id: String
    let name: String
    let rootPaths: [String]
}

struct CodexProjectRoutingSnapshot: Equatable {
    let project: CodexSavedProject
    let model: CodexProjectConfigValue
    let reasoningEffort: CodexProjectConfigValue
    let contextWindow: CodexProjectConfigValue
    let autoCompactTokenLimit: CodexProjectConfigValue
    let planModeReasoningEffort: CodexProjectConfigValue
    var blocksGlobalInheritance = false

    var hasMixedValues: Bool {
        model == .mixed || reasoningEffort == .mixed
            || contextWindow == .mixed || autoCompactTokenLimit == .mixed
            || planModeReasoningEffort == .mixed
    }

    var inheritsEverything: Bool {
        model == .inherited && reasoningEffort == .inherited
            && contextWindow == .inherited && autoCompactTokenLimit == .inherited
            && planModeReasoningEffort == .inherited
    }
}

struct CodexModelRoutingSnapshot: Equatable {
    let global: CodexConfigSelection
    let models: [CodexModelOption]
    let projects: [CodexProjectRoutingSnapshot]
}

enum CodexModelRoutingStoreError: LocalizedError {
    case invalidUTF8(String)
    case missingGlobalDefault(String)
    case missingProject(String)

    var errorDescription: String? {
        switch self {
        case let .invalidUTF8(path):
            return "The Codex config is not valid UTF-8: \(path)"
        case let .missingGlobalDefault(key):
            return "The global Codex config does not define \(key)."
        case let .missingProject(id):
            return "The Codex project could not be found: \(id)"
        }
    }
}

final class CodexModelRoutingStore {
    private struct CachedModelCatalog: Decodable {
        let models: [CachedModel]
    }

    private struct CachedModel: Decodable {
        struct ReasoningLevel: Decodable {
            let effort: String
        }

        let slug: String
        let displayName: String
        let description: String?
        let defaultReasoningLevel: String?
        let supportedReasoningLevels: [ReasoningLevel]
        let visibility: String?
        let priority: Int?

        enum CodingKeys: String, CodingKey {
            case slug
            case displayName = "display_name"
            case description
            case defaultReasoningLevel = "default_reasoning_level"
            case supportedReasoningLevels = "supported_reasoning_levels"
            case visibility
            case priority
        }
    }

    let codexHomeURL: URL
    private let fileManager: FileManager

    init(
        codexHomeURL: URL = CodexModelRoutingStore.defaultCodexHomeURL(),
        fileManager: FileManager = .default
    ) {
        self.codexHomeURL = codexHomeURL.standardizedFileURL
        self.fileManager = fileManager
    }

    static func defaultCodexHomeURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
    }

    var globalConfigURL: URL {
        codexHomeURL.appendingPathComponent("config.toml")
    }

    var globalStateURL: URL {
        codexHomeURL.appendingPathComponent(".codex-global-state.json")
    }

    var modelCacheURL: URL {
        codexHomeURL.appendingPathComponent("models_cache.json")
    }

    func loadSnapshot() -> CodexModelRoutingSnapshot {
        let models = loadModels()
        let global = (try? readSelection(at: globalConfigURL)) ?? CodexConfigSelection()
        let projects = loadProjects().map { project in
            let rootSelections = project.rootPaths.map {
                (try? readSelection(at: projectConfigURL(rootPath: $0))) ?? CodexConfigSelection()
            }
            return CodexProjectRoutingSnapshot(
                project: project,
                model: mergedValue(rootSelections.map(\.model)),
                reasoningEffort: mergedValue(rootSelections.map(\.reasoningEffort)),
                contextWindow: mergedIntegerValue(rootSelections.map(\.contextWindow)),
                autoCompactTokenLimit: mergedIntegerValue(rootSelections.map(\.autoCompactTokenLimit)),
                planModeReasoningEffort: mergedValue(rootSelections.map(\.planModeReasoningEffort))
            )
        }
        return CodexModelRoutingSnapshot(global: global, models: models, projects: projects)
    }

    func routingInputURLs(for snapshot: CodexModelRoutingSnapshot) -> [URL] {
        [
            globalConfigURL,
            globalStateURL,
            modelCacheURL,
        ] + snapshot.projects.flatMap { project in
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

    /// Restores only the model-routing keys captured by Token Meter. Other
    /// Codex settings in the same files are intentionally preserved.
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
                // Projects discovered after protection was enabled inherit the
                // protected global default until configured from Token Meter.
                let desired = state.selectionsByPath[url.path] ?? CodexConfigSelection()
                if try readSelection(at: url) != desired {
                    try writeSelection(desired, at: url)
                    changed = true
                }
            }
        }
        return changed
    }

    func writeGlobal(_ selection: CodexConfigSelection) throws {
        try writeSelection(selection, at: globalConfigURL)
    }

    func writeProject(
        id: String,
        selection: CodexConfigSelection
    ) throws {
        guard let project = loadProjects().first(where: { $0.id == id }) else {
            throw CodexModelRoutingStoreError.missingProject(id)
        }
        for rootPath in project.rootPaths {
            try writeSelection(selection, at: projectConfigURL(rootPath: rootPath))
        }
    }

    func readSelection(at url: URL) throws -> CodexConfigSelection {
        guard fileManager.fileExists(atPath: url.path) else {
            return CodexConfigSelection()
        }
        let data = try Data(contentsOf: url)
        guard let source = String(data: data, encoding: .utf8) else {
            throw CodexModelRoutingStoreError.invalidUTF8(url.path)
        }
        return CodexConfigSelection(
            model: Self.topLevelStringValue(for: "model", in: source),
            reasoningEffort: Self.topLevelStringValue(for: "model_reasoning_effort", in: source),
            contextWindow: Self.topLevelIntegerValue(for: "model_context_window", in: source),
            autoCompactTokenLimit: Self.topLevelIntegerValue(for: "model_auto_compact_token_limit", in: source),
            planModeReasoningEffort: Self.topLevelStringValue(for: "plan_mode_reasoning_effort", in: source)
        )
    }

    func loadProjects() -> [CodexSavedProject] {
        guard let data = try? Data(contentsOf: globalStateURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let localProjects = object["local-projects"] as? [String: Any] else {
            return []
        }

        let order = object["project-order"] as? [String] ?? []
        let orderIndex = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        let projects = localProjects.compactMap { id, raw -> CodexSavedProject? in
            guard let dictionary = raw as? [String: Any],
                  let name = dictionary["name"] as? String,
                  let rawRoots = dictionary["rootPaths"] as? [String] else {
                return nil
            }
            let roots = rawRoots
                .map { ($0 as NSString).standardizingPath }
                .filter { fileManager.fileExists(atPath: $0) }
            guard !roots.isEmpty else { return nil }
            return CodexSavedProject(id: id, name: name, rootPaths: roots)
        }

        return projects.sorted {
            let lhs = orderIndex[$0.id] ?? Int.max
            let rhs = orderIndex[$1.id] ?? Int.max
            if lhs != rhs { return lhs < rhs }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func loadModels() -> [CodexModelOption] {
        if let data = try? Data(contentsOf: modelCacheURL),
           let catalog = try? JSONDecoder().decode(CachedModelCatalog.self, from: data) {
            let visible = catalog.models
                .filter { $0.visibility == nil || $0.visibility == "list" }
                .sorted {
                    let lhs = $0.priority ?? Int.max
                    let rhs = $1.priority ?? Int.max
                    if lhs != rhs { return lhs < rhs }
                    return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
                .map {
                    let efforts = $0.supportedReasoningLevels.map(\.effort)
                    return CodexModelOption(
                        slug: $0.slug,
                        displayName: $0.displayName,
                        description: $0.description ?? "",
                        defaultReasoningEffort: $0.defaultReasoningLevel ?? efforts.first ?? "medium",
                        supportedReasoningEfforts: efforts.isEmpty ? Self.fallbackReasoningEfforts : efforts
                    )
                }
            if !visible.isEmpty {
                return visible
            }
        }
        return [
            CodexModelOption(
                slug: "gpt-5.6-sol",
                displayName: "GPT-5.6-Sol",
                description: "Latest frontier agentic coding model.",
                defaultReasoningEffort: "medium",
                supportedReasoningEfforts: Self.fallbackReasoningEfforts
            ),
            CodexModelOption(
                slug: "gpt-5.6-terra",
                displayName: "GPT-5.6-Terra",
                description: "Balanced agentic coding model for everyday work.",
                defaultReasoningEffort: "medium",
                supportedReasoningEfforts: Self.fallbackReasoningEfforts
            ),
            CodexModelOption(
                slug: "gpt-5.6-luna",
                displayName: "GPT-5.6-Luna",
                description: "Fast and affordable agentic coding model.",
                defaultReasoningEffort: "medium",
                supportedReasoningEfforts: ["low", "medium", "high", "xhigh", "max"]
            )
        ]
    }

    func projectConfigURL(rootPath: String) -> URL {
        URL(fileURLWithPath: rootPath, isDirectory: true)
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("config.toml")
    }

    static func updatedTOML(
        _ source: String,
        selection: CodexConfigSelection,
        extraTopLevelStrings: [String: String?] = [:]
    ) -> String {
        var lines = source.components(separatedBy: "\n")
        if lines.isEmpty {
            lines = [""]
        }

        func topLevelBoundary() -> Int {
            lines.firstIndex {
                let trimmed = $0.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("[")
            } ?? lines.count
        }

        func update(key: String, value: String?) {
            let boundary = topLevelBoundary()
            if let index = lines[..<boundary].firstIndex(where: { isAssignment($0, key: key) }) {
                if let value {
                    lines[index] = "\(key) = \"\(tomlEscaped(value))\""
                } else {
                    lines.remove(at: index)
                }
                return
            }
            guard let value else { return }
            var insertionIndex = topLevelBoundary()
            while insertionIndex > 0,
                  lines[insertionIndex - 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                insertionIndex -= 1
            }
            lines.insert("\(key) = \"\(tomlEscaped(value))\"", at: insertionIndex)
        }

        func updateInteger(key: String, value: Int?) {
            let boundary = topLevelBoundary()
            if let index = lines[..<boundary].firstIndex(where: { isAssignment($0, key: key) }) {
                if let value {
                    lines[index] = "\(key) = \(value)"
                } else {
                    lines.remove(at: index)
                }
                return
            }
            guard let value else { return }
            var insertionIndex = topLevelBoundary()
            while insertionIndex > 0,
                  lines[insertionIndex - 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                insertionIndex -= 1
            }
            lines.insert("\(key) = \(value)", at: insertionIndex)
        }

        update(key: "model", value: selection.model)
        update(key: "model_reasoning_effort", value: selection.reasoningEffort)
        updateInteger(key: "model_context_window", value: selection.contextWindow)
        updateInteger(key: "model_auto_compact_token_limit", value: selection.autoCompactTokenLimit)
        update(key: "plan_mode_reasoning_effort", value: selection.planModeReasoningEffort)
        for (key, value) in extraTopLevelStrings {
            update(key: key, value: value)
        }

        var result = lines.joined(separator: "\n")
        if !result.hasSuffix("\n") {
            result.append("\n")
        }
        return result
    }

    static func topLevelStringValue(for key: String, in source: String) -> String? {
        for line in source.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                break
            }
            guard isAssignment(line, key: key),
                  let equals = line.firstIndex(of: "=") else {
                continue
            }
            let raw = line[line.index(after: equals)...]
                .trimmingCharacters(in: .whitespaces)
            guard raw.first == "\"" else { return nil }
            var value = ""
            var escaped = false
            for character in raw.dropFirst() {
                if escaped {
                    value.append(character)
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    return value
                } else {
                    value.append(character)
                }
            }
            return nil
        }
        return nil
    }

    static func topLevelIntegerValue(for key: String, in source: String) -> Int? {
        for line in source.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                break
            }
            guard isAssignment(line, key: key),
                  let equals = line.firstIndex(of: "=") else {
                continue
            }
            let raw = line[line.index(after: equals)...]
                .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return Int(raw)
        }
        return nil
    }

    private static let fallbackReasoningEfforts = ["low", "medium", "high", "xhigh", "max", "ultra"]

    /// Writes only the project-configuration keys at an already resolved project
    /// config URL. The protection controller uses this for a task-scoped
    /// override; callers must restore the captured selection afterwards.
    func writeSelection(_ selection: CodexConfigSelection, at url: URL) throws {
        if !fileManager.fileExists(atPath: url.path),
           selection.model == nil,
           selection.reasoningEffort == nil,
           selection.contextWindow == nil,
           selection.autoCompactTokenLimit == nil,
           selection.planModeReasoningEffort == nil {
            return
        }
        let source: String
        if fileManager.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            guard let existing = String(data: data, encoding: .utf8) else {
                throw CodexModelRoutingStoreError.invalidUTF8(url.path)
            }
            source = existing
        } else {
            source = ""
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }
        let updated = Self.updatedTOML(source, selection: selection)
        try Data(updated.utf8).write(to: url, options: .atomic)
    }

    private func mergedValue(_ values: [String?]) -> CodexProjectConfigValue {
        guard let first = values.first else { return .inherited }
        if values.dropFirst().contains(where: { $0 != first }) {
            return .mixed
        }
        return first.map(CodexProjectConfigValue.value) ?? .inherited
    }

    private func mergedIntegerValue(_ values: [Int?]) -> CodexProjectConfigValue {
        guard let first = values.first else { return .inherited }
        if values.dropFirst().contains(where: { $0 != first }) {
            return .mixed
        }
        return first.map { .value(String($0)) } ?? .inherited
    }

    private static func isAssignment(_ line: String, key: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#"), trimmed.hasPrefix(key) else { return false }
        let remainder = trimmed.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
        return remainder.hasPrefix("=")
    }

    private static func tomlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
