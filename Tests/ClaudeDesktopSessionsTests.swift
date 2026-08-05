import Foundation

@main
enum ClaudeDesktopSessionsTests {
    private static var failures: [String] = []

    static func main() {
        testNativeEntryIsIndexedByCLISession()
        testFreshestEntryWinsOverImported()
        testImportedEntryWinsWhenItIsTheFreshest()
        testGlobalLastFocusedIncludesUnlinkedEntries()

        if failures.isEmpty {
            print("PASS: ClaudeDesktopSessions")
            return
        }
        for failure in failures {
            FileHandle.standardError.write(Data("FAIL: \(failure)\n".utf8))
        }
        exit(1)
    }

    /// A session created inside the desktop app gets a random desktop id, so it is
    /// only reachable through `sessionId` — never through the CLI session uuid.
    private static func testNativeEntryIsIndexedByCLISession() {
        let root = makeFixtureRoot()
        defer { cleanUp(root) }
        write(
            root: root,
            filename: "local_5ae2f260-dbe8-4cbe-8a17-d033973e0333.json",
            fields: [
                "sessionId": "local_5ae2f260-dbe8-4cbe-8a17-d033973e0333",
                "cliSessionId": "892d98e7-7bbb-4d1f-bc95-afe10c89991c",
                "model": "claude-opus-5",
                "title": "Taskbar 数据和跳转问题",
                "cwd": "/tmp/worktree",
                "lastFocusedAt": 1_785_948_024_619,
                "lastActivityAt": 1_785_948_151_533
            ]
        )

        let index = ClaudeDesktopSessionIndex(root: root)
        guard let session = index.currentSession(forCLISession: "892d98e7-7bbb-4d1f-bc95-afe10c89991c") else {
            failures.append("native desktop entry should be indexed by its cliSessionId")
            return
        }
        expect(session.desktopID == "local_5ae2f260-dbe8-4cbe-8a17-d033973e0333", "desktop id should come from sessionId")
        expect(!session.isImported, "a random desktop id is not an imported entry")
        expect(session.model == "claude-opus-5", "model should be read from desktop metadata")
        expect(session.title == "Taskbar 数据和跳转问题", "title should be read from desktop metadata")
        expect(session.cwd == "/tmp/worktree", "cwd should be read from desktop metadata")
    }

    /// When one CLI session owns both an imported and a natively created entry,
    /// the live conversation is whichever one was touched last.
    private static func testFreshestEntryWinsOverImported() {
        let root = makeFixtureRoot()
        defer { cleanUp(root) }
        let cliID = "672093b4-8a4f-4f40-8722-0eb7b74ec873"
        write(
            root: root,
            filename: "local_\(cliID).json",
            fields: [
                "sessionId": "local_\(cliID)",
                "cliSessionId": cliID,
                "lastFocusedAt": 1_783_311_583_795,
                "lastActivityAt": 1_783_311_583_795
            ]
        )
        write(
            root: root,
            filename: "local_661af0ef-1b27-45ab-ac1b-e131720169a8.json",
            fields: [
                "sessionId": "local_661af0ef-1b27-45ab-ac1b-e131720169a8",
                "cliSessionId": cliID,
                "lastFocusedAt": 1_783_312_644_849,
                "lastActivityAt": 1_783_312_644_849
            ]
        )

        let index = ClaudeDesktopSessionIndex(root: root)
        let sessions = index.sessions(forCLISession: cliID)
        expect(sessions.count == 2, "both desktop entries should be indexed")
        expect(
            sessions.first?.desktopID == "local_661af0ef-1b27-45ab-ac1b-e131720169a8",
            "the newer native entry should outrank the older imported entry"
        )
    }

    private static func testImportedEntryWinsWhenItIsTheFreshest() {
        let root = makeFixtureRoot()
        defer { cleanUp(root) }
        let cliID = "05f5c82f-6bab-4bc8-bf96-ac9ab5afbe13"
        write(
            root: root,
            filename: "local_\(cliID).json",
            fields: [
                "sessionId": "local_\(cliID)",
                "cliSessionId": cliID,
                "lastFocusedAt": 1_783_310_900_000,
                "lastActivityAt": 1_783_310_900_000
            ]
        )
        write(
            root: root,
            filename: "local_d3352419-8216-4669-954a-30fdd5f38e84.json",
            fields: [
                "sessionId": "local_d3352419-8216-4669-954a-30fdd5f38e84",
                "cliSessionId": cliID,
                "lastFocusedAt": 1_783_310_728_365,
                "lastActivityAt": 1_783_310_728_365
            ]
        )

        let index = ClaudeDesktopSessionIndex(root: root)
        guard let current = index.currentSession(forCLISession: cliID) else {
            failures.append("imported entry should be indexed")
            return
        }
        expect(current.isImported, "an entry named local_<cliSessionId>.json is an imported entry")
        expect(current.desktopID == "local_\(cliID)", "the freshest entry should win")
    }

    /// Desktop entries with no `cliSessionId` still tell us whether some other
    /// conversation is the one currently on screen.
    private static func testGlobalLastFocusedIncludesUnlinkedEntries() {
        let root = makeFixtureRoot()
        defer { cleanUp(root) }
        write(
            root: root,
            filename: "local_487a52bc-ad67-42ba-945d-4d237618feb2.json",
            fields: [
                "sessionId": "local_487a52bc-ad67-42ba-945d-4d237618feb2",
                "lastFocusedAt": 1_784_022_058_094
            ]
        )
        write(
            root: root,
            filename: "local_9dd34aa9-ce34-430b-b45e-bb59d8d3b141.json",
            fields: [
                "sessionId": "local_9dd34aa9-ce34-430b-b45e-bb59d8d3b141",
                "cliSessionId": "4254c627-3d89-4bf3-8375-04d2a99ebb10",
                "isArchived": true,
                "lastFocusedAt": 1_783_861_263_392
            ]
        )

        let index = ClaudeDesktopSessionIndex(root: root)
        expect(index.globalLastFocused() == 1_784_022_058_094, "global focus should span entries without a cliSessionId")
        expect(
            index.sessions(forCLISession: "487a52bc-ad67-42ba-945d-4d237618feb2").isEmpty,
            "a desktop id must not be matched as if it were a CLI session id"
        )
        expect(
            index.currentSession(forCLISession: "4254c627-3d89-4bf3-8375-04d2a99ebb10")?.isArchived == true,
            "archived flag should be preserved"
        )
    }

    private static func makeFixtureRoot() -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("claude-desktop-sessions-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: root.appendingPathComponent("account", isDirectory: true)
                .appendingPathComponent("org", isDirectory: true),
            withIntermediateDirectories: true
        )
        return root
    }

    private static func write(root: URL, filename: String, fields: [String: Any]) {
        let url = root.appendingPathComponent("account", isDirectory: true)
            .appendingPathComponent("org", isDirectory: true)
            .appendingPathComponent(filename)
        guard let data = try? JSONSerialization.data(withJSONObject: fields) else {
            failures.append("could not encode fixture \(filename)")
            return
        }
        try? data.write(to: url)
    }

    private static func cleanUp(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }

    private static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            failures.append(message)
        }
    }
}
