import Foundation

@main
struct USRelayHoursTests {
    static func main() throws {
        let formatter = ISO8601DateFormatter()
        let cases: [(String, USRelayWindow)] = [
            ("2026-10-19T12:59:59Z", .closed), ("2026-10-19T13:00:00Z", .open),
            ("2026-10-19T21:59:59Z", .open), ("2026-10-19T22:00:00Z", .closed),
            ("2026-10-20T04:00:00Z", .night), ("2026-10-24T16:00:00Z", .closed),
            ("2026-11-02T13:59:59Z", .closed), ("2026-11-02T14:00:00Z", .open),
            ("2026-03-09T13:00:00Z", .open),
        ]
        for (instant, expected) in cases {
            let snapshot = USRelayHours.snapshot(policy: .approved, now: formatter.date(from: instant)!)
            precondition(snapshot.state == expected, "NY schedule mismatch at \(instant)")
            precondition(snapshot.allowed, "Hours must only remind, never block calls")
            precondition(snapshot.inWorkingHours == (expected == .open))
        }
        let friday = USRelayHours.snapshot(policy: .approved, now: formatter.date(from: "2026-10-30T22:00:00Z")!)
        precondition(friday.nextOpen == formatter.date(from: "2026-11-02T14:00:00Z"), "Weekend opening must reflect DST change")
        let summerNine = USRelayHours.snapshot(policy: .approved, now: formatter.date(from: "2026-10-19T13:00:00Z")!)
        let winterNine = USRelayHours.snapshot(policy: .approved, now: formatter.date(from: "2026-11-02T14:00:00Z")!)
        precondition(summerNine.menuClock == "09:00" && winterNine.menuClock == "09:00", "Menu clock must display New York time across DST")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("us-hours-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("policy.json")
        precondition(USRelayHours.current(policyURL: file) == nil, "Do not add an indicator without a configured relay")
        try Data("{}".utf8).write(to: file)
        precondition(USRelayHours.current(policyURL: file)?.state == .unavailable, "Invalid policy must never appear open")
        let fixture = Data(#"{"version":2,"outside_hours_mode":"warn","timezone":"America/New_York","weekdays":[0,1,2,3,4],"start_hour":9,"end_hour":18,"night_start_hour":22,"night_end_hour":8}"#.utf8)
        precondition(USRelayPolicy.decode(fixture) == .approved, "Decode the relay's policy contract")
        if FileManager.default.fileExists(atPath: USRelayHours.policyURL.path) {
            let actual = try Data(contentsOf: USRelayHours.policyURL)
            precondition(USRelayPolicy.decode(actual) == .approved, "UI and relay must use the same approved policy")
        }
        print("US relay reminder checks passed: boundaries, weekends, DST, no hours blocking, absent/invalid/shared policy.")
    }
}
