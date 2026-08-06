import Darwin
import Foundation

/// Watches the directories that contain model-routing inputs and reports only
/// when one of the target files actually changes.
final class CodexConfigWatcher {
    typealias ChangeHandler = () -> Void

    private let fileManager: FileManager
    private let queue: DispatchQueue
    private let callbackQueue: DispatchQueue
    private let debounceInterval: TimeInterval
    private let onChange: ChangeHandler
    private var targetURLs: [URL] = []
    private var lastContents: [String: Data?] = [:]
    private var directorySources: [String: DispatchSourceFileSystemObject] = [:]
    private var targetFileSources: [String: DispatchSourceFileSystemObject] = [:]
    private var pendingComparison: DispatchWorkItem?

    init(
        fileManager: FileManager = .default,
        queue: DispatchQueue = DispatchQueue(label: "local.ai-token-meter.codex-config-watcher"),
        callbackQueue: DispatchQueue = .main,
        debounceInterval: TimeInterval = 0.25,
        onChange: @escaping ChangeHandler
    ) {
        self.fileManager = fileManager
        self.queue = queue
        self.callbackQueue = callbackQueue
        self.debounceInterval = debounceInterval
        self.onChange = onChange
    }

    deinit {
        pendingComparison?.cancel()
        for source in directorySources.values {
            source.cancel()
        }
        for source in targetFileSources.values {
            source.cancel()
        }
    }

    func watch(targetURLs: [URL], ready: (() -> Void)? = nil) {
        let normalizedTargets = Dictionary(
            targetURLs.map { ($0.standardizedFileURL.path, $0.standardizedFileURL) },
            uniquingKeysWith: { first, _ in first }
        )
        .values
        .sorted { $0.path < $1.path }

        queue.async { [weak self] in
            guard let self else { return }
            self.targetURLs = normalizedTargets
            self.lastContents = self.readContents(of: normalizedTargets)
            self.replaceDirectorySourcesIfNeeded(for: normalizedTargets)
            self.replaceTargetFileSources(for: normalizedTargets)
            if let ready {
                self.callbackQueue.async(execute: ready)
            }
        }
    }

    private func replaceDirectorySourcesIfNeeded(for targets: [URL]) {
        let directoryURLs = Dictionary(
            targets.map {
                let directory = nearestExistingDirectory(
                    startingAt: $0.deletingLastPathComponent()
                )
                return (directory.path, directory)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let desiredPaths = Set(directoryURLs.keys)
        guard desiredPaths != Set(directorySources.keys) else { return }

        for source in directorySources.values {
            source.cancel()
        }
        directorySources.removeAll()

        for path in desiredPaths.sorted() {
            guard let directoryURL = directoryURLs[path] else { continue }
            let descriptor = open(directoryURL.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete],
                queue: queue
            )
            source.setEventHandler { [weak self] in
                self?.scheduleComparison()
            }
            source.setCancelHandler {
                close(descriptor)
            }
            directorySources[path] = source
            source.resume()
        }
    }

    private func replaceTargetFileSources(for targets: [URL]) {
        for source in targetFileSources.values {
            source.cancel()
        }
        targetFileSources.removeAll()

        for target in targets {
            let path = target.standardizedFileURL.path
            guard fileManager.fileExists(atPath: path) else { continue }
            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .extend, .attrib, .rename, .delete],
                queue: queue
            )
            source.setEventHandler { [weak self] in
                self?.scheduleComparison()
            }
            source.setCancelHandler {
                close(descriptor)
            }
            targetFileSources[path] = source
            source.resume()
        }
    }

    private func nearestExistingDirectory(startingAt url: URL) -> URL {
        var candidate = url.standardizedFileURL
        while candidate.path != "/" {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: "/", isDirectory: true)
    }

    private func scheduleComparison() {
        pendingComparison?.cancel()
        let comparison = DispatchWorkItem { [weak self] in
            self?.compareContents()
        }
        pendingComparison = comparison
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: comparison)
    }

    private func compareContents() {
        let currentContents = readContents(of: targetURLs)
        guard !contentsEqual(currentContents, lastContents) else { return }
        lastContents = currentContents
        callbackQueue.async { [weak self] in
            self?.onChange()
        }
    }

    private func readContents(of urls: [URL]) -> [String: Data?] {
        Dictionary(
            uniqueKeysWithValues: urls.map {
                ($0.path, fileManager.contents(atPath: $0.path))
            }
        )
    }

    private func contentsEqual(
        _ lhs: [String: Data?],
        _ rhs: [String: Data?]
    ) -> Bool {
        guard lhs.keys == rhs.keys else { return false }
        return lhs.allSatisfy { path, data in
            data == rhs[path] ?? nil
        }
    }
}
