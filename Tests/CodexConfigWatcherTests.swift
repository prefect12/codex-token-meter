import Foundation

@main
struct CodexConfigWatcherTests {
    static func main() throws {
        try detectsCreatedAndAtomicallyReplacedConfig()
        try detectsInPlaceConfigWrite()
        try ignoresUnrelatedDirectoryChanges()
        print("CodexConfigWatcherTests passed")
    }

    private static func detectsInPlaceConfigWrite() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let configURL = fixture.appendingPathComponent("config.toml")
        try Data("model = \"gpt-5.6-luna\"\n".utf8).write(to: configURL)
        let callbackQueue = DispatchQueue(label: "CodexConfigWatcherTests.in-place")
        let changed = DispatchSemaphore(value: 0)
        let watcher = CodexConfigWatcher(
            callbackQueue: callbackQueue,
            debounceInterval: 0.05
        ) {
            changed.signal()
        }
        try waitUntilReady(watcher: watcher, target: configURL)

        let handle = try FileHandle(forWritingTo: configURL)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("model = \"gpt-5.6-terra\"\n".utf8))
        try handle.close()
        try expectSignal(changed, message: "writing an existing config in place should trigger a change")
    }

    private static func detectsCreatedAndAtomicallyReplacedConfig() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let configURL = fixture
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("config.toml")
        let callbackQueue = DispatchQueue(label: "CodexConfigWatcherTests.callback")
        let created = DispatchSemaphore(value: 0)
        var callbackCount = 0
        let watcher = CodexConfigWatcher(
            callbackQueue: callbackQueue,
            debounceInterval: 0.05
        ) {
            callbackCount += 1
            created.signal()
        }
        try waitUntilReady(watcher: watcher, target: configURL)

        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("model = \"gpt-5.6-terra\"\n".utf8).write(to: configURL, options: .atomic)
        try expectSignal(created, message: "creating config.toml should trigger a change")

        let replaced = DispatchSemaphore(value: 0)
        watcher.watch(targetURLs: [configURL]) {
            replaced.signal()
        }
        try expectSignal(replaced, message: "watcher should reconfigure after config creation")
        try Data("model = \"gpt-5.6-sol\"\n".utf8).write(to: configURL, options: .atomic)
        try expectEventually(
            timeout: 2,
            message: "atomically replacing config.toml should trigger a second change"
        ) {
            callbackQueue.sync { callbackCount >= 2 }
        }
    }

    private static func ignoresUnrelatedDirectoryChanges() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let configDirectory = fixture.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(
            at: configDirectory,
            withIntermediateDirectories: true
        )
        let configURL = configDirectory.appendingPathComponent("config.toml")
        try Data("model = \"gpt-5.6-terra\"\n".utf8).write(to: configURL)
        let callbackQueue = DispatchQueue(label: "CodexConfigWatcherTests.unrelated")
        let unexpected = DispatchSemaphore(value: 0)
        let watcher = CodexConfigWatcher(
            callbackQueue: callbackQueue,
            debounceInterval: 0.05
        ) {
            unexpected.signal()
        }
        try waitUntilReady(watcher: watcher, target: configURL)

        let unrelatedURL = configDirectory.appendingPathComponent("unrelated.txt")
        try Data("unchanged routing".utf8).write(to: unrelatedURL, options: .atomic)
        guard unexpected.wait(timeout: .now() + 0.3) == .timedOut else {
            throw failure("unrelated directory changes must not trigger a routing refresh")
        }
    }

    private static func makeFixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-config-watcher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func waitUntilReady(
        watcher: CodexConfigWatcher,
        target: URL
    ) throws {
        let ready = DispatchSemaphore(value: 0)
        watcher.watch(targetURLs: [target]) {
            ready.signal()
        }
        try expectSignal(ready, message: "watcher should finish configuring")
    }

    private static func expectSignal(
        _ semaphore: DispatchSemaphore,
        message: String
    ) throws {
        guard semaphore.wait(timeout: .now() + 2) == .success else {
            throw failure(message)
        }
    }

    private static func expectEventually(
        timeout: TimeInterval,
        message: String,
        condition: () -> Bool
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        throw failure(message)
    }

    private static func failure(_ message: String) -> NSError {
        NSError(
            domain: "CodexConfigWatcherTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
