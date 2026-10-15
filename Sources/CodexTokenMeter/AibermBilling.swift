import Foundation
import CryptoKit
import Security
import LocalAuthentication

// Provider charges are account/key counters, never local token-price estimates.
struct AibermCredential: Codable {
    let baseURL: URL
    let secret: String
    let userID: Int?

    init(baseURL: String, secret: String, userID: Int? = nil) throws {
        guard let url = URL(string: baseURL), url.scheme == "https",
              ["aiberm.com", "aiberm.org"].contains(url.host?.lowercased() ?? ""),
              url.port == nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil,
              ["", "/", "/v1", "/v1/"].contains(url.path),
              !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !secret.contains(where: { $0.isWhitespace }), userID == nil || userID! > 0 else {
            throw AibermBillingError.configuration
        }
        self.baseURL = URL(string: "https://\(url.host!.lowercased())")!
        self.secret = secret
        self.userID = userID
    }

    var fingerprint: String {
        SHA256.hash(data: Data("\(baseURL.absoluteString)|\(userID ?? 0)|\(secret)".utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    static func discover(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> AibermCredential? {
        func object(_ path: String) -> [String: Any]? {
            guard let data = try? Data(contentsOf: home.appendingPathComponent(path)) else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        if let env = object(".claude/settings.json")?["env"] as? [String: Any],
           let base = env["ANTHROPIC_BASE_URL"] as? String {
            for name in ["ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY"] {
                if let key = env[name] as? String,
                   let credential = try? AibermCredential(baseURL: base, secret: key) { return credential }
            }
        }
        let library = "Library/Application Support/Claude-3p/configLibrary/"
        if let meta = object(library + "_meta.json"),
           let id = meta["appliedId"] as? String, UUID(uuidString: id) != nil,
           let config = object(library + id + ".json"),
           let base = config["inferenceGatewayBaseUrl"] as? String,
           let key = config["inferenceGatewayApiKey"] as? String {
            return try? AibermCredential(baseURL: base, secret: key)
        }
        return nil
    }
}

enum AibermBillingError: String, Error {
    case configuration, authorization, network, invalidResponse, unsupportedUnits, keychain
}

struct AibermBillingSnapshot: Codable {
    let fingerprint: String
    let fetchedAt: Date
    let host: String
    let spentUSD: Double
    // For API keys this is the key budget, NOT the wallet balance.
    let remainingUSD: Double?
    let unlimited: Bool
    let requestCount: Int?
    let expiresAt: Date?
}

struct AibermBillingCache: Codable {
    var key: AibermBillingSnapshot?
    var account: AibermBillingSnapshot?

    func matching(key: AibermCredential?, account: AibermCredential?) -> Self {
        Self(key: self.key?.fingerprint == key?.fingerprint ? self.key : nil,
             account: self.account?.fingerprint == account?.fingerprint ? self.account : nil)
    }
}

struct AibermBalancePresentation {
    let snapshot: AibermBillingSnapshot?
    var failed = false
    var now = Date()

    var isStale: Bool { failed || snapshot.map { now.timeIntervalSince($0.fetchedAt) > 180 } == true }
    var title: String {
        guard let amount = snapshot?.remainingUSD else { return "A$—" }
        return (isStale ? "~" : "") + String(format: "$%.2f", locale: Locale(identifier: "en_US_POSIX"), amount)
    }
    var tooltip: String {
        guard let snapshot, let amount = snapshot.remainingUSD else {
            return "Aiberm 账户余额未授权 / Account not connected\nAPI 账单 → 连接账户 / API Billing → Connect account"
        }
        let date = DateFormatter.localizedString(from: snapshot.fetchedAt, dateStyle: .short, timeStyle: .medium)
        return "Aiberm · USD " + String(format: "%.6f", amount) + "\n" + date
            + (isStale ? "\n缓存余额，等待刷新 / Cached balance; awaiting refresh" : "")
    }
}

final class AibermHTTPTransport: NSObject, URLSessionTaskDelegate {
    // Do not forward authorization to redirects, or use browser session cookies.
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }

    func send(_ request: URLRequest) throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let result = AibermHTTPResult()
        let signal = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: request) { data, response, error in
            result.data = data
            result.status = (response as? HTTPURLResponse)?.statusCode
            result.failed = error != nil
            signal.signal()
        }
        task.resume()
        guard signal.wait(timeout: .now() + 12) == .success, !result.failed else {
            task.cancel(); throw AibermBillingError.network
        }
        if result.status == 401 || result.status == 403 { throw AibermBillingError.authorization }
        guard result.status == 200, let data = result.data, data.count < 1_000_000 else {
            throw AibermBillingError.invalidResponse
        }
        return data
    }
}

private final class AibermHTTPResult: @unchecked Sendable {
    var data: Data?
    var status: Int?
    var failed = false
}

struct AibermBillingClient {
    var transport: (URLRequest) throws -> Data = { try AibermHTTPTransport().send($0) }
    var now: () -> Date = Date.init

    func fetch(_ credential: AibermCredential) throws -> AibermBillingSnapshot {
        func get(_ path: String, authenticated: Bool = true) throws -> [String: Any] {
            var request = URLRequest(url: credential.baseURL.appendingPathComponent(path))
            request.timeoutInterval = 10
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if authenticated {
                request.setValue("Bearer " + credential.secret, forHTTPHeaderField: "Authorization")
                if let id = credential.userID { request.setValue(String(id), forHTTPHeaderField: "New-Api-User") }
            }
            guard let object = try JSONSerialization.jsonObject(with: transport(request)) as? [String: Any] else {
                throw AibermBillingError.invalidResponse
            }
            if (object["success"] as? Bool) == false || (object["code"] as? Bool) == false || object["error"] != nil {
                throw AibermBillingError.authorization
            }
            return object
        }
        let status = try get("api/status", authenticated: false)
        guard let metadata = status["data"] as? [String: Any],
              let units = Self.number(metadata["quota_per_unit"]), units > 0,
              metadata["quota_display_type"] as? String == "USD" else {
            throw AibermBillingError.unsupportedUnits
        }
        let isAccount = credential.userID != nil
        let envelope = try get(isAccount ? "api/user/self" : "api/usage/token/")
        guard let data = envelope["data"] as? [String: Any],
              let used = Self.number(data[isAccount ? "used_quota" : "total_used"]), used >= 0 else {
            throw AibermBillingError.invalidResponse
        }
        if let userID = credential.userID {
            guard Self.number(data["id"]) == Double(userID) else { throw AibermBillingError.authorization }
        }
        let unlimited = !isAccount && (data["unlimited_quota"] as? Bool) == true
        let remaining = Self.number(data[isAccount ? "quota" : "total_available"])
        guard unlimited || remaining != nil else { throw AibermBillingError.invalidResponse }
        let requests = Self.number(data["request_count"])
        let expires = Self.number(data["expires_at"]) ?? 0
        return AibermBillingSnapshot(
            fingerprint: credential.fingerprint, fetchedAt: now(), host: credential.baseURL.host!,
            spentUSD: used / units, remainingUSD: unlimited ? nil : remaining.map { $0 / units },
            unlimited: unlimited, requestCount: requests.flatMap { $0 >= 0 && $0 < Double(Int.max) ? Int($0) : nil },
            expiresAt: expires > 0 ? Date(timeIntervalSince1970: expires) : nil
        )
    }

    static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }
}

enum AibermAccountKeychain {
    private static let service = "com.codextokenmeter.aiberm-account"
    private static var query: [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                kSecAttrAccount as String: "billing", kSecUseAuthenticationContext as String: context]
    }
    static func read() -> AibermCredential? {
        var request = query
        request[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let saved = try? JSONDecoder().decode(AibermCredential.self, from: data) else { return nil }
        return try? AibermCredential(baseURL: saved.baseURL.absoluteString, secret: saved.secret, userID: saved.userID)
    }
    static func save(_ credential: AibermCredential) throws {
        let data = try JSONEncoder().encode(credential)
        let changes = [kSecValueData as String: data]
        let update = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw AibermBillingError.keychain }
        var request = query
        request[kSecValueData as String] = data
        request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(request as CFDictionary, nil) == errSecSuccess else { throw AibermBillingError.keychain }
    }
    static func remove() throws {
        let result = SecItemDelete(query as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw AibermBillingError.keychain }
    }
}

final class AibermBillingStore {
    static let shared = AibermBillingStore()
    static let updated = Notification.Name("AibermBillingUpdated")
    static let cacheURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Codex Token Meter/aiberm-billing.json")
    private(set) var cache = AibermBillingCache()
    private(set) var isRefreshing = false
    private(set) var keyError: AibermBillingError?
    private(set) var accountError: AibermBillingError?
    private(set) var hasAccount = false
    private var lastAttempt = Date.distantPast
    private var generation = 0
    private var timer: Timer?

    init() {
        let account = AibermAccountKeychain.read()
        hasAccount = account != nil
        if let data = try? Data(contentsOf: Self.cacheURL),
           let saved = try? JSONDecoder().decode(AibermBillingCache.self, from: data) {
            cache = saved.matching(key: AibermCredential.discover(), account: account)
        }
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func refresh(force: Bool = false) {
        guard !isRefreshing, force || Date().timeIntervalSince(lastAttempt) >= 60 else { return }
        let key = AibermCredential.discover()
        let account = AibermAccountKeychain.read()
        hasAccount = account != nil
        cache = cache.matching(key: key, account: account)
        isRefreshing = true
        lastAttempt = Date()
        let currentGeneration = generation
        NotificationCenter.default.post(name: Self.updated, object: nil)
        DispatchQueue.global(qos: .utility).async {
            let client = AibermBillingClient()
            let keyResult = key.map { credential in Result { try client.fetch(credential) } }
            let accountResult = account.map { credential in Result { try client.fetch(credential) } }
            DispatchQueue.main.async {
                self.isRefreshing = false
                guard currentGeneration == self.generation else { self.refresh(force: true); return }
                // A config/key rotation must not retain another key's bill.
                if key?.fingerprint == AibermCredential.discover()?.fingerprint {
                    switch keyResult {
                    case .success(let value): self.cache.key = value; self.keyError = nil
                    case .failure(let error): self.keyError = error as? AibermBillingError ?? .network
                    case nil: self.cache.key = nil; self.keyError = .configuration
                    }
                } else { self.cache.key = nil; self.keyError = .configuration }
                switch accountResult {
                case .success(let value): self.cache.account = value; self.accountError = nil
                case .failure(let error): self.accountError = error as? AibermBillingError ?? .network
                case nil: self.cache.account = nil; self.accountError = nil
                }
                try? Self.persist(self.cache)
                NotificationCenter.default.post(name: Self.updated, object: nil)
            }
        }
    }

    func connect(_ credential: AibermCredential, completion: @escaping (AibermBillingError?) -> Void) {
        // Validate before replacing a working account authorization.
        DispatchQueue.global(qos: .utility).async {
            do {
                let snapshot = try AibermBillingClient().fetch(credential)
                try AibermAccountKeychain.save(credential)
                DispatchQueue.main.async {
                    self.generation += 1
                    self.hasAccount = true
                    self.cache.account = snapshot
                    self.accountError = nil
                    try? Self.persist(self.cache)
                    NotificationCenter.default.post(name: Self.updated, object: nil)
                    completion(nil)
                }
            } catch { DispatchQueue.main.async { completion(error as? AibermBillingError ?? .network) } }
        }
    }

    func disconnect() throws {
        try AibermAccountKeychain.remove()
        generation += 1
        hasAccount = false
        cache.account = nil
        accountError = nil
        try Self.persist(cache)
        NotificationCenter.default.post(name: Self.updated, object: nil)
    }

    static func persist(_ cache: AibermBillingCache, to url: URL = cacheURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(cache).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
