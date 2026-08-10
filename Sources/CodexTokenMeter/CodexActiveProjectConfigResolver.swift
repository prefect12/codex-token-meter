import Foundation

/// Locates the project behind the most recently selected Codex task. The
/// desktop app records task model/effort and cwd in its local state database;
/// this reader asks only for that one recent row and never reads prompts.
struct CodexActiveProjectConfigResolver {
    private let routingStore: CodexModelRoutingStore
    private let now: () -> Date

    init(
        routingStore: CodexModelRoutingStore,
        now: @escaping () -> Date = Date.init
    ) {
        self.routingStore = routingStore
        self.now = now
    }

    func mostRecentlySelectedProjectConfigURL(
        matching selection: CodexConfigSelection
    ) -> URL? {
        guard let model = selection.model,
              let effort = selection.reasoningEffort,
              let cwd = mostRecentlySelectedTaskCWD(model: model, effort: effort),
              let projectRoot = projectRoot(forTaskCWD: cwd) else {
            return nil
        }
        return routingStore.projectConfigURL(rootPath: projectRoot)
    }

    private func mostRecentlySelectedTaskCWD(model: String, effort: String) -> String? {
        guard let databaseURL = stateDatabaseURL() else { return nil }
        let sql = """
        SELECT cwd
        FROM threads
        WHERE archived = 0
          AND model = '\(sqlEscaped(model))'
          AND reasoning_effort = '\(sqlEscaped(effort))'
          AND updated_at_ms >= \(Int64(now().timeIntervalSince1970 * 1_000) - 120_000)
        ORDER BY updated_at_ms DESC
        LIMIT 1;
        """
        return runSQLite(databaseURL: databaseURL, sql: sql)
            ?? runSQLite(
                databaseURL: databaseURL,
                sql: """
                SELECT cwd
                FROM threads
                WHERE archived = 0
                  AND updated_at_ms >= \(Int64(now().timeIntervalSince1970 * 1_000) - 120_000)
                ORDER BY updated_at_ms DESC
                LIMIT 1;
                """
            )
    }

    private func stateDatabaseURL() -> URL? {
        let candidates = [
            routingStore.codexHomeURL.appendingPathComponent("state_5.sqlite"),
            routingStore.codexHomeURL.appendingPathComponent("sqlite/state_5.sqlite"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func runSQLite(databaseURL: URL, sql: String) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-noheader", databaseURL.path, sql]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let value = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .split(separator: "\n", maxSplits: 1).first,
                  !value.isEmpty else {
                return nil
            }
            return String(value)
        } catch {
            return nil
        }
    }

    private func projectRoot(forTaskCWD cwd: String) -> String? {
        let canonicalCWD = URL(fileURLWithPath: cwd).standardizedFileURL.path
        if let matchingRoot = routingStore.loadProjects()
            .flatMap(\.rootPaths)
            .first(where: { canonicalCWD == $0 || canonicalCWD.hasPrefix($0 + "/") }) {
            return matchingRoot
        }

        let git = Process()
        let output = Pipe()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["-C", canonicalCWD, "rev-parse", "--path-format=absolute", "--git-common-dir"]
        git.standardOutput = output
        git.standardError = FileHandle.nullDevice
        do {
            try git.run()
            git.waitUntilExit()
            guard git.terminationStatus == 0,
                  let commonDirectory = String(
                    data: output.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                  )?.trimmingCharacters(in: .whitespacesAndNewlines),
                  commonDirectory.hasSuffix("/.git") else {
                return nil
            }
            let root = URL(fileURLWithPath: commonDirectory)
                .deletingLastPathComponent()
                .standardizedFileURL.path
            return routingStore.loadProjects().flatMap(\.rootPaths).contains(root) ? root : nil
        } catch {
            return nil
        }
    }

    private func sqlEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }
}
