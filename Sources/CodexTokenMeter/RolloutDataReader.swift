import Foundation
import Darwin

/// Codex migrates inactive rollouts to concatenated Zstandard frames. Read them
/// without expanding the history on disk or keeping message bodies in memory.
enum RolloutDataReader {
    static var zstdExecutable: URL? {
        ["/opt/homebrew/bin/zstd", "/usr/local/bin/zstd", "/usr/bin/zstd"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map { URL(fileURLWithPath: $0) }
    }

    static func isRollout(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix("rollout-")
            && (url.pathExtension == "jsonl" || url.lastPathComponent.hasSuffix(".jsonl.zst"))
    }

    static func logicalPath(_ url: URL) -> String {
        (url.pathExtension == "zst" ? url.deletingPathExtension() : url).standardizedFileURL.path
    }

    static func read(_ url: URL) throws -> Data {
        guard url.pathExtension == "zst" else {
            return try Data(contentsOf: url, options: [.mappedIfSafe])
        }
        guard let executable = zstdExecutable else {
            throw NSError(domain: "RolloutDataReader", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Reading compressed Codex history requires zstd."])
        }
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["--decompress", "--stdout", "--quiet", "--", url.path]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer { try? output.fileHandleForReading.close() }

        var result = Data()
        var pending = Data()
        func appendLine(_ line: Data) {
            // The fields used by the scanner precede message bodies. Preserve
            // only accounting/lifecycle records, not prompts or tool output.
            let header = line.prefix(512)
            guard accountingPatterns.contains(where: { header.range(of: $0) != nil }) else { return }
            result.append(line)
            result.append(10)
        }
        do {
            while let chunk = try output.fileHandleForReading.read(upToCount: 1_048_576), !chunk.isEmpty {
                autoreleasepool {
                    var start = 0
                    chunk.withUnsafeBytes { bytes in
                        guard let base = bytes.baseAddress else { return }
                        while start < bytes.count,
                              let newline = memchr(base.advanced(by: start), 10, bytes.count - start) {
                            let index = base.distance(to: UnsafeRawPointer(newline))
                            if pending.isEmpty {
                                appendLine(chunk[start..<index])
                            } else {
                                pending.append(chunk[start..<index])
                                appendLine(pending)
                                pending.removeAll(keepingCapacity: true)
                            }
                            start = index + 1
                        }
                    }
                    pending.append(chunk[start..<chunk.endIndex])
                }
            }
        } catch {
            process.terminate()
            process.waitUntilExit()
            throw error
        }
        if !pending.isEmpty { appendLine(pending) }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "RolloutDataReader", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "Could not decode compressed Codex history."])
        }
        return result
    }

    private static let accountingPatterns = [
        "session_meta", "turn_context", "token_count", "task_started",
        "task_complete", "turn_aborted", "context_compacted",
        "inter_agent_communication_metadata"
    ].map { Data("\"type\":\"\($0)\"".utf8) }
}
