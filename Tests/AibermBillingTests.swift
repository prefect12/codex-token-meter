import Foundation

@main
struct AibermBillingTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw NSError(domain: message, code: 1) }
    }
    static let status: [String: Any] = ["success": true, "data": ["quota_per_unit": 500000, "quota_display_type": "USD"]]

    static func main() throws {
        let key = try AibermCredential(baseURL: "https://aiberm.com/v1", secret: "test-secret")
        for base in ["http://aiberm.com", "https://aiberm.com.evil.example", "https://aiberm.com@evil.example", "https://aiberm.com:443", "https://aiberm.com/redirect", "https://aiberm.com?next=evil"] {
            try require((try? AibermCredential(baseURL: base, secret: "test")) == nil, "Reject untrusted base: \(base)")
        }
        try require((try? AibermCredential(baseURL: "https://aiberm.com", secret: "test\nheader")) == nil, "Reject header injection")
        var calls: [URLRequest] = []
        let fixedDate = Date(timeIntervalSince1970: 1700000000)
        func client(_ payload: [String: Any], metadata: [String: Any] = status) -> AibermBillingClient {
            AibermBillingClient(transport: { request in
                calls.append(request)
                return try JSONSerialization.data(withJSONObject: request.url!.path == "/api/status" ? metadata : payload)
            }, now: { fixedDate })
        }
        let unlimited = try client(["code": true, "data": ["total_used": 9416, "total_available": -9417, "unlimited_quota": true, "expires_at": 0]]).fetch(key)
        try require(abs(unlimited.spentUSD - 0.018832) < 0.000000001, "Quota units convert to dollars, not token counts or cents")
        try require(unlimited.remainingUSD == nil && unlimited.unlimited, "Unlimited key must never become a wallet balance")
        try require(unlimited.fetchedAt == fixedDate && unlimited.expiresAt == nil, "Use server sampling time and no-expiry semantics")
        try require(calls.count == 2 && calls.allSatisfy { $0.httpMethod == "GET" }, "Only read-only billing calls")
        try require(calls[0].value(forHTTPHeaderField: "Authorization") == nil, "Public status needs no credential")
        try require(calls[1].value(forHTTPHeaderField: "Authorization") == "Bearer test-secret", "Key only in authorization header")
        try require(calls.allSatisfy { $0.url?.query == nil && $0.url?.host == "aiberm.com" }, "Never put credentials in URLs")
        let finite = try client(["code": true, "data": ["total_used": 500000, "total_available": 250000, "unlimited_quota": false, "expires_at": 1800000000]]).fetch(key)
        try require(finite.spentUSD == 1 && finite.remainingUSD == 0.5 && finite.expiresAt != nil, "Finite key budget and expiry")
        let account = try AibermCredential(baseURL: "https://aiberm.org", secret: "account-secret", userID: 42)
        let wallet = try client(["success": true, "data": ["id": 42, "quota": 49990000, "used_quota": 10000, "request_count": 16]]).fetch(account)
        try require(wallet.remainingUSD == 99.98 && wallet.spentUSD == 0.02 && wallet.requestCount == 16, "Account wallet counters are separate from key counters")
        try require(AibermBalancePresentation(snapshot: wallet, now: fixedDate).title == "$99.98", "Menu bar shows actual account balance")
        try require(AibermBalancePresentation(snapshot: wallet, failed: true, now: fixedDate).title == "~$99.98", "Failed refresh marks cached balance")
        try require(AibermBalancePresentation(snapshot: wallet, now: fixedDate.addingTimeInterval(181)).title == "~$99.98", "Old menu balance is visibly stale")
        try require(AibermBalancePresentation(snapshot: nil).title == "A$—", "Missing authorization never shows a fake balance")
        try require(calls.last?.value(forHTTPHeaderField: "New-Api-User") == "42", "Account authorization includes user ID")
        try require(calls.last?.url?.path == "/api/user/self", "Account billing reads self only")
        for payload: [String: Any] in [
            ["success": false, "message": "sensitive server detail"],
            ["code": false], ["error": ["message": "invalid"]],
            ["code": true, "data": ["total_used": -1]],
            ["code": true, "data": ["total_used": true, "total_available": 0]],
            ["code": true, "data": ["total_used": 1]]
        ] {
            try require((try? client(payload).fetch(key)) == nil, "Reject logical errors and malformed counters")
        }
        try require((try? client(["success": true, "data": ["id": 43, "quota": 1, "used_quota": 2]]).fetch(account)) == nil, "Reject account identity mismatch")
        for units: [String: Any] in [["quota_per_unit": 0, "quota_display_type": "USD"], ["quota_per_unit": 500000, "quota_display_type": "CNY"], ["quota_per_unit": true, "quota_display_type": "USD"]] {
            try require((try? client([:], metadata: ["data": units]).fetch(key)) == nil, "Do not guess billing units")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("aiberm-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheURL = root.appendingPathComponent("cache.json")
        let cache = AibermBillingCache(key: unlimited, account: wallet)
        try AibermBillingStore.persist(cache, to: cacheURL)
        let stored = try Data(contentsOf: cacheURL)
        let storedText = String(data: stored, encoding: .utf8)!
        try require(!storedText.contains("test-secret") && !storedText.contains("account-secret"), "Cache never contains credentials")
        let mode = try FileManager.default.attributesOfItem(atPath: cacheURL.path)[.posixPermissions] as? Int
        try require(mode == 0o600, "Billing cache is private")
        let decoded = try JSONDecoder().decode(AibermBillingCache.self, from: stored)
        let rotated = try AibermCredential(baseURL: "https://aiberm.com", secret: "rotated")
        try require(decoded.matching(key: rotated, account: nil).key == nil, "Rotating keys invalidates the cached bill")
        try require(decoded.matching(key: key, account: account).account?.requestCount == 16, "Matching credentials retain last successful readings")
        try require(decoded.matching(key: nil, account: nil).account == nil, "Disconnect removes cached wallet")
        let settings = root.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["env": ["ANTHROPIC_BASE_URL": "https://aiberm.com", "ANTHROPIC_AUTH_TOKEN": "test-secret"]]).write(to: settings)
        try require(AibermCredential.discover(home: root)?.fingerprint == key.fingerprint, "Discover existing Claude Code credentials")
        try FileManager.default.removeItem(at: settings)
        let library = root.appendingPathComponent("Library/Application Support/Claude-3p/configLibrary")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let id = UUID().uuidString
        try JSONSerialization.data(withJSONObject: ["appliedId": id]).write(to: library.appendingPathComponent("_meta.json"))
        try JSONSerialization.data(withJSONObject: ["inferenceGatewayBaseUrl": "https://aiberm.com", "inferenceGatewayApiKey": "test-secret"]).write(to: library.appendingPathComponent(id + ".json"))
        try require(AibermCredential.discover(home: root)?.fingerprint == key.fingerprint, "Fallback to the applied Claude Desktop profile")
        print("AibermBillingTests passed (units, scope, auth, privacy, rotation, discovery)")
    }
}
