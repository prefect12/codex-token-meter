import Cocoa

/// A separate surface keeps provider bills out of subscription/API-equivalent estimates.
final class AibermBillingView: NSView {
    private let store = AibermBillingStore.shared
    private var observer: NSObjectProtocol?
    private var connecting = false
    var demoCache: AibermBillingCache?
    private var labels: [String: NSTextField] = [:]
    private lazy var refreshButton = button("刷新", "Refresh", action: #selector(refreshBilling))
    private lazy var consoleButton = button("打开控制台 ↗", "Open console ↗", action: #selector(openConsole))
    private lazy var connectButton = button("连接账户", "Connect account", action: #selector(connectAccount))
    private lazy var disconnectButton = button("断开账户", "Disconnect", action: #selector(disconnectAccount))
    override var isFlipped: Bool { true }

    private func copy(_ chinese: String, _ english: String) -> String {
        AppLanguage.current == .chinese || AppLanguage.current == .traditionalChinese ? chinese : english
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        appearance = NSAppearance(named: .darkAqua)
        for button in [refreshButton, consoleButton, connectButton, disconnectButton] { addSubview(button) }
        observer = NotificationCenter.default.addObserver(forName: AibermBillingStore.updated, object: nil, queue: .main) { [weak self] _ in
            self?.needsLayout = true
            self?.needsDisplay = true
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    private func button(_ chinese: String, _ english: String, action: Selector) -> NSButton {
        let button = NSButton(title: copy(chinese, english), target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        return button
    }

    private func label(_ id: String, _ value: String, x: CGFloat, y: CGFloat, width: CGFloat,
                       size: CGFloat = 13, color: NSColor = NSColor.white.withAlphaComponent(0.6), bold: Bool = false, height: CGFloat = 22) {
        let field: NSTextField
        if let existing = labels[id] { field = existing }
        else {
            field = NSTextField(wrappingLabelWithString: "")
            field.isSelectable = false
            addSubview(field)
            labels[id] = field
        }
        field.stringValue = value
        field.font = .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        field.textColor = color
        field.frame = NSRect(x: x, y: y, width: width, height: height)
    }

    override func layout() {
        super.layout()
        let cache = demoCache ?? store.cache
        let half = (bounds.width - 16) / 2
        let hasAccount = demoCache?.account != nil || store.hasAccount
        refreshButton.title = store.isRefreshing ? copy("更新中…", "Refreshing…") : copy("刷新", "Refresh")
        refreshButton.isEnabled = !store.isRefreshing && !connecting && demoCache == nil
        consoleButton.title = copy("打开控制台 ↗", "Open console ↗")
        connectButton.title = connecting ? copy("验证中…", "Verifying…") : copy("连接账户", "Connect account")
        disconnectButton.title = copy("断开账户", "Disconnect")
        connectButton.isEnabled = !connecting && demoCache == nil
        disconnectButton.isEnabled = !connecting && demoCache == nil
        disconnectButton.isHidden = !hasAccount
        refreshButton.frame = NSRect(x: bounds.width - 244, y: 13, width: 90, height: 32)
        consoleButton.frame = NSRect(x: bounds.width - 146, y: 13, width: 134, height: 32)
        connectButton.frame = NSRect(x: 18, y: 430, width: 118, height: 32)
        disconnectButton.frame = NSRect(x: 146, y: 430, width: 110, height: 32)

        label("provider", "Aiberm", x: 18, y: 12, width: 180, size: 20, color: .white, bold: true, height: 28)
        label("providerNote", copy("平台实际扣费 · USD", "Provider charges · USD"), x: 128, y: 18, width: max(90, bounds.width - 400), size: 12)
        label("balanceTitle", copy("账户余额", "Account balance"), x: 20, y: 91, width: half - 40, size: 14)
        label("balance", cache.account?.remainingUSD.map(money) ?? "—", x: 20, y: 121, width: half - 40, size: 32, color: .white, bold: true, height: 44)
        let accountDetail = cache.account.map { copy("账户累计扣费 ", "Account lifetime spend ") + money($0.spentUSD) }
            ?? copy("需连接控制台账户，API key 无权读取钱包", "Connect your console account to read the wallet")
        label("balanceDetail", accountDetail, x: 20, y: 177, width: half - 40, size: 12, height: 36)
        label("accountStatus", status(cache.account, error: store.accountError, absent: copy("未授权", "Not connected")), x: 20, y: 218, width: half - 40, size: 11, height: 34)

        let right = half + 36
        label("spentTitle", copy("此 API key · 累计实扣", "This API key · lifetime spend"), x: right, y: 91, width: half - 40, size: 14)
        label("spent", cache.key.map { money($0.spentUSD) } ?? "—", x: right, y: 121, width: half - 40, size: 32, color: NSColor(calibratedRed: 0.39, green: 0.86, blue: 0.75, alpha: 1), bold: true, height: 44)
        let budget = cache.key.map { $0.unlimited ? copy("API key 额度：无限制", "API key budget: unlimited") : copy("API key 剩余额度：", "API key budget remaining: ") + ($0.remainingUSD.map(money) ?? "—") }
            ?? copy("自动读取 Claude Code / Claude App 的 Aiberm 配置", "Reads Aiberm configuration from Claude Code / Claude App")
        label("budget", budget, x: right, y: 177, width: half - 40, size: 12, height: 36)
        label("keyStatus", status(cache.key, error: store.keyError, absent: copy("尚无账单数据", "No billing data yet")), x: right, y: 218, width: half - 40, size: 11, height: 34)

        label("scopeTitle", copy("账单口径", "Billing scope"), x: 20, y: 291, width: bounds.width - 40, size: 15, color: .white, bold: true)
        label("scope", copy("累计实扣由 Aiberm 返回，包含所有设备共用这把 key 的扣费；它不代表本机或今日费用。", "Lifetime spend comes from Aiberm and includes all devices sharing this key; it is not today's or this Mac's cost."), x: 20, y: 324, width: bounds.width - 40, size: 13, height: 42)
        label("estimate", copy("与「用量」中的本地 API 费用估算独立，不重复相加。账户余额与 key 额度也是两项不同的数据。", "Separate from local API cost estimates in Usage. Account balance and key budget are distinct; these values are never added together."), x: 20, y: 372, width: bounds.width - 40, size: 13, height: 42)
        label("authNote", copy("账户授权仅用于读取余额与累计请求数；访问令牌保存在 macOS 钥匙串。", "Account authorization reads balance and request counts. Access tokens are stored in macOS Keychain."), x: 20, y: 482, width: bounds.width - 40, size: 12, height: 34)
        let requests = cache.account?.requestCount.map { String($0) } ?? "—"
        let expiry = cache.key?.expiresAt.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .short) }
            ?? (cache.key == nil ? "—" : copy("未设置", "Not set"))
        label("footer", copy("账户累计请求：", "Account lifetime requests: ") + requests + "    ·    " + copy("key 到期：", "Key expiry: ") + expiry + "    ·    " + copy("每 60 秒自动刷新", "Refreshes every 60 seconds"), x: 0, y: 541, width: bounds.width, size: 11, height: 38)
    }

    override func draw(_ dirtyRect: NSRect) {
        let half = (bounds.width - 16) / 2
        for rect in [NSRect(x: 0, y: 0, width: bounds.width, height: 60),
                     NSRect(x: 0, y: 76, width: half, height: 188),
                     NSRect(x: half + 16, y: 76, width: half, height: 188),
                     NSRect(x: 0, y: 276, width: bounds.width, height: 248)] {
            NSColor(calibratedWhite: 0.11, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14).fill()
            NSColor.white.withAlphaComponent(0.08).setStroke()
            NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14).stroke()
        }
    }

    private func money(_ amount: Double) -> String {
        String(format: amount != 0 && abs(amount) < 1 ? "$%.6f" : "$%.2f", locale: Locale(identifier: "en_US_POSIX"), amount)
    }

    private func status(_ snapshot: AibermBillingSnapshot?, error: AibermBillingError?, absent: String) -> String {
        var text = snapshot.map { copy("更新于 ", "Updated ") + DateFormatter.localizedString(from: $0.fetchedAt, dateStyle: .short, timeStyle: .medium) } ?? absent
        if let error { text += " · " + errorText(error) }
        else if let snapshot, Date().timeIntervalSince(snapshot.fetchedAt) > 180 { text += copy(" · 缓存数据", " · Cached data") }
        if let snapshot, let expiry = snapshot.expiresAt, expiry <= Date() { text += copy(" · key 已到期", " · Key expired") }
        return text
    }

    private func errorText(_ error: AibermBillingError) -> String {
        switch error {
        case .configuration: return copy("未找到 Aiberm 配置", "No Aiberm configuration")
        case .authorization: return copy("授权失效，请重新连接", "Authorization failed; reconnect")
        case .network: return copy("刷新失败，保留上次数据", "Refresh failed; showing last data")
        case .invalidResponse: return copy("接口响应异常", "Invalid API response")
        case .unsupportedUnits: return copy("无法确认计费单位", "Unrecognized billing units")
        case .keychain: return copy("钥匙串保存失败", "Could not save to Keychain")
        }
    }

    @objc private func refreshBilling() { store.refresh(force: true) }
    @objc private func openConsole() { NSWorkspace.shared.open(URL(string: "https://aiberm.com/console")!) }

    @objc private func connectAccount() {
        let alert = NSAlert()
        alert.messageText = copy("连接 Aiberm 账户", "Connect Aiberm account")
        alert.informativeText = copy("在控制台个人设置中获取用户 ID 和系统访问令牌（不是 sk- API key）。令牌具有账户 API 权限，并非只读专用。本应用只读查询，验证成功后保存在本机钥匙串。", "Get your user ID and system access token from console personal settings (not an sk- API key). The token has account API permissions, not a read-only scope. This app only reads billing data and saves it in this Mac's Keychain after validation.")
        alert.addButton(withTitle: copy("连接", "Connect"))
        alert.addButton(withTitle: copy("取消", "Cancel"))
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 116))
        let host = NSPopUpButton(frame: NSRect(x: 0, y: 84, width: 360, height: 26))
        host.addItems(withTitles: ["https://aiberm.com", "https://aiberm.org"])
        let id = NSTextField(frame: NSRect(x: 0, y: 44, width: 360, height: 26))
        id.placeholderString = copy("用户 ID", "User ID")
        id.setAccessibilityLabel(copy("用户 ID", "User ID"))
        let token = NSSecureTextField(frame: NSRect(x: 0, y: 4, width: 360, height: 26))
        token.placeholderString = copy("系统访问令牌", "System access token")
        token.setAccessibilityLabel(copy("系统访问令牌", "System access token"))
        [host, id, token].forEach { accessory.addSubview($0) }
        alert.accessoryView = accessory
        let submit: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            guard let userID = Int(id.stringValue),
                  let credential = try? AibermCredential(baseURL: host.titleOfSelectedItem ?? "", secret: token.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), userID: userID) else {
                self.showError(.configuration); return
            }
            token.stringValue = ""
            self.connecting = true
            self.needsLayout = true
            self.store.connect(credential) { [weak self] error in
                self?.connecting = false
                self?.needsLayout = true
                if let error { self?.showError(error) }
            }
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: submit) }
        else { submit(alert.runModal()) }
    }

    @objc private func disconnectAccount() {
        do { try store.disconnect() } catch { showError(.keychain) }
    }

    private func showError(_ error: AibermBillingError) {
        let alert = NSAlert()
        alert.messageText = copy("账户未连接", "Account not connected")
        alert.informativeText = errorText(error)
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }
}
