import Darwin
import Foundation

/// Runs a short-lived helper process without attaching asynchronous pipe readers.
///
/// Task Bar performs this work from its single background refresh. Waiting on that
/// same thread is intentional: it keeps refreshes serialized, while the process
/// termination handler only signals completion and never occupies another blocked
/// dispatch worker. Redirecting stdout to an unlinked temporary file also avoids
/// pipe-capacity deadlocks for larger SQLite results.
enum TaskBarProcessRunner {
    /// Writes to a child-process pipe without allowing a closed reader to send
    /// SIGPIPE to the Task Bar process. Darwin reports the closed pipe as EPIPE,
    /// which FileHandle's throwing API turns into a normal failure here.
    static func write(_ data: Data, toPipe handle: FileHandle) -> Bool {
        guard Darwin.fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else {
            return false
        }
        do {
            try handle.write(contentsOf: data)
            return true
        } catch {
            return false
        }
    }

    static func run(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval
    ) -> Data? {
        guard timeout > 0, let outputHandle = makeUnlinkedTemporaryFile() else {
            return nil
        }
        defer {
            try? outputHandle.close()
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputHandle
        process.standardError = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            finished.signal()
        }

        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            return nil
        }

        guard finished.wait(timeout: .now() + timeout) == .success else {
            terminate(process, finished: finished)
            process.terminationHandler = nil
            return nil
        }
        process.terminationHandler = nil

        guard process.terminationStatus == 0 else {
            return nil
        }

        do {
            try outputHandle.seek(toOffset: 0)
            return try outputHandle.readToEnd() ?? Data()
        } catch {
            return nil
        }
    }

    private static func terminate(_ process: Process, finished: DispatchSemaphore) {
        if process.isRunning {
            process.terminate()
        }
        if finished.wait(timeout: .now() + 0.25) == .success {
            return
        }
        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
        _ = finished.wait(timeout: .now() + 0.5)
    }

    private static func makeUnlinkedTemporaryFile() -> FileHandle? {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("taskbar-process-output.XXXXXX")
        var template = Array(path.utf8CString)
        let descriptor = template.withUnsafeMutableBufferPointer { buffer -> Int32 in
            guard let baseAddress = buffer.baseAddress else {
                return -1
            }
            let descriptor = Darwin.mkstemp(baseAddress)
            if descriptor >= 0 {
                Darwin.unlink(baseAddress)
            }
            return descriptor
        }
        guard descriptor >= 0 else {
            return nil
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }
}
