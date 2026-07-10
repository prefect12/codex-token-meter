import CoreServices
import Foundation

final class RolloutActivityMonitor {
    typealias ActivityHandler = ([URL]) -> Void

    private let queue = DispatchQueue(label: "local.task-bar.rollout-activity")
    private let pendingLock = NSLock()
    private let handler: ActivityHandler
    private let roots: [URL]
    private var stream: FSEventStreamRef?
    private var pendingPaths = Set<String>()
    private var pendingDelivery: DispatchWorkItem?

    init(roots: [URL], handler: @escaping ActivityHandler) {
        self.roots = roots.filter { FileManager.default.fileExists(atPath: $0.path) }
        self.handler = handler
    }

    func start() {
        guard stream == nil, !roots.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            let monitor = Unmanaged<RolloutActivityMonitor>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: CFArray.self) as? [String] ?? []
            monitor.consume(paths: Array(paths.prefix(count)))
        }
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagWatchRoot
                | kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            roots.map(\.path) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.15,
            flags
        ) else {
            return
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        if !FSEventStreamStart(stream) {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        pendingLock.lock()
        pendingDelivery?.cancel()
        pendingDelivery = nil
        pendingPaths.removeAll()
        pendingLock.unlock()
    }

    deinit {
        stop()
    }

    private func consume(paths: [String]) {
        pendingLock.lock()
        for path in paths where path.hasSuffix(".jsonl") {
            pendingPaths.insert(path)
        }
        guard !pendingPaths.isEmpty else {
            pendingLock.unlock()
            return
        }

        guard pendingDelivery == nil else {
            pendingLock.unlock()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingLock.lock()
            let urls = self.pendingPaths.sorted().map(URL.init(fileURLWithPath:))
            self.pendingPaths.removeAll()
            self.pendingDelivery = nil
            self.pendingLock.unlock()
            self.handler(urls)
        }
        pendingDelivery = work
        pendingLock.unlock()
        // Coalesce bursts without repeatedly postponing delivery. Codex can append
        // several events per turn, but the first write should still wake Task Bar.
        queue.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}

func taskBarRolloutRootURLs(home: String = NSHomeDirectory()) -> [URL] {
    var homes = configuredCodexHomeURLs(home: home)
    if let raw = ProcessInfo.processInfo.environment["CODEX_HOME"], !raw.isEmpty {
        homes.append(URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true))
    }
    var seen = Set<String>()
    return homes.flatMap { codexHome in
        [
            codexHome.appendingPathComponent("sessions", isDirectory: true),
            codexHome.appendingPathComponent("archived_sessions", isDirectory: true)
        ]
    }.filter { seen.insert($0.standardizedFileURL.path).inserted }
}
