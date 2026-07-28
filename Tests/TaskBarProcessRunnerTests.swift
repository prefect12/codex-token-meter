import Foundation

@main
enum TaskBarProcessRunnerTests {
    private static var failures: [String] = []

    static func main() {
        testLargeOutput()
        testTimeout()
        testRepeatedRunsDoNotLeakDescriptors()
        testRepeatedTimeoutsDoNotLeakDescriptors()

        if failures.isEmpty {
            print("PASS: TaskBarProcessRunner")
            return
        }

        for failure in failures {
            FileHandle.standardError.write(Data("FAIL: \(failure)\n".utf8))
        }
        exit(1)
    }

    private static func testLargeOutput() {
        let data = TaskBarProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/sqlite3"),
            arguments: ["-batch", "-noheader", ":memory:", "select hex(zeroblob(100000));"],
            timeout: 3
        )
        expect(data?.count == 200_001, "large SQLite output should be captured without a pipe deadlock")
    }

    private static func testTimeout() {
        let startedAt = Date()
        let data = TaskBarProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["3"],
            timeout: 0.1
        )
        let elapsed = Date().timeIntervalSince(startedAt)
        expect(data == nil, "timed-out process should not return output")
        expect(elapsed < 1.5, "timed-out process should be terminated promptly (elapsed \(elapsed))")
    }

    private static func testRepeatedRunsDoNotLeakDescriptors() {
        let baseline = descriptorCount()
        for index in 0..<200 {
            let data = autoreleasepool {
                TaskBarProcessRunner.run(
                    executableURL: URL(fileURLWithPath: "/usr/bin/sqlite3"),
                    arguments: ["-batch", "-noheader", ":memory:", "select \(index);"],
                    timeout: 2
                )
            }
            expect(data == Data("\(index)\n".utf8), "SQLite run \(index) should return its result")
        }
        let finalCount = descriptorCount()
        expect(
            finalCount <= baseline + 2,
            "repeated runs should not leak file descriptors (before \(baseline), after \(finalCount))"
        )
    }

    private static func testRepeatedTimeoutsDoNotLeakDescriptors() {
        let baseline = descriptorCount()
        for _ in 0..<20 {
            let data = autoreleasepool {
                TaskBarProcessRunner.run(
                    executableURL: URL(fileURLWithPath: "/bin/sleep"),
                    arguments: ["1"],
                    timeout: 0.01
                )
            }
            expect(data == nil, "repeated timed-out process should not return output")
        }
        let finalCount = descriptorCount()
        expect(
            finalCount <= baseline + 2,
            "repeated timeouts should not leak file descriptors (before \(baseline), after \(finalCount))"
        )
    }

    private static func descriptorCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? 0
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures.append(message)
        }
    }
}
