import Cocoa
import Foundation
import ServiceManagement
import UserNotifications

// MARK: - App Lifecycle

private struct DashboardReportBundle {
    let report: TokenReport
    let codexReport: TokenReport?
    let claudeReport: TokenReport?
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let dashboardController = DashboardViewController()
    private let detailsController = UsageDetailsWindowController()
    private var scanner = CodexTokenScanner(rootURLs: AppSettings.logFolderURLs)
    private var claudeScanner = ClaudeTokenScanner(rootURLs: AppSettings.claudeLogFolderURLs)
    private let rateLimitReader = LiveRateLimitReader()
    private let accountUsageReader = AccountUsageReader()
    private let serviceStatusReader = CodexServiceStatusReader()
    private let localFormatter = DateFormatter()
    private let scanQueue = DispatchQueue(label: "local.codex-token-meter.scan", qos: .utility)
    private let liveQueue = DispatchQueue(label: "local.codex-token-meter.live", qos: .utility)
    private var selectedWindow: WindowOption = .week
    private var selectedQuota: QuotaViewOption = .all
    private var latestState = DashboardState()
    private var reportCache: [ReportCacheKey: TokenReport] = [:]
    private var accountUsage: AccountUsageSnapshot?
    private var liveLimits: [LiveRateLimit] = []
    private var serviceStatus: CodexServiceStatusSnapshot?
    private var refreshTimer: Timer?
    private var liveRefreshTimer: Timer?
    private var activeScans: Set<ReportCacheKey> = []
    private var liveRefreshInFlight = false
    private var statusSpinnerTimer: Timer?
    private var statusSpinnerFrame = 0
    private var statusIsLoading = false
    private var detailsLoadGeneration = 0
    private let refreshInterval: TimeInterval = 300
    private let liveRefreshInterval: TimeInterval = 60
    private let statusIconSize = NSSize(width: 14, height: 14)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        localFormatter.locale = Locale(identifier: "en_US_POSIX")
        localFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        localFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        selectedWindow = .day
        if let rawQuota = UserDefaults.standard.string(forKey: "selectedQuotaView"),
           let quota = QuotaViewOption.option(from: rawQuota) {
            selectedQuota = quota
        }
        if !QuotaViewOption.visibleCases.contains(selectedQuota) {
            selectedQuota = QuotaViewOption.visibleCases.first ?? .codex
        }

        NSApp.applicationIconImage = NSImage(named: "LogoHeader")
        popover.contentViewController = dashboardController
        updateDashboardSize(for: selectedQuota)
        popover.behavior = .transient
        configureStatusButton()

        dashboardController.dashboardView.onWindowChanged = { [weak self] option in self?.selectWindow(option) }
        dashboardController.dashboardView.onQuotaChanged = { [weak self] option in self?.selectQuota(option) }
        dashboardController.dashboardView.onRefresh = { [weak self] in
            self?.refresh(forceLive: false)
            self?.refreshLiveLimits()
        }
        dashboardController.dashboardView.onOpenDetails = { [weak self] in self?.openUsageDetailsWindow() }
        dashboardController.dashboardView.onOpenSettings = { [weak self] in self?.openSettingsWindow() }
        dashboardController.dashboardView.onOpenCodexStatus = { [weak self] in self?.openCodexStatusPage() }
        dashboardController.dashboardView.onQuit = { NSApp.terminate(nil) }
        detailsController.detailsView.onLanguageChanged = { [weak self] language in
            AppLanguage.current = language
            self?.applyLanguage()
        }
        detailsController.detailsView.onNumberUnitStyleChanged = { [weak self] style in
            self?.changeNumberUnitStyle(style)
        }
        detailsController.detailsView.onStatusDisplayChanged = { [weak self] option in
            guard let self else { return }
            StatusDisplayOption.current = option
            detailsController.detailsView.needsDisplay = true
            updateStatusTitle(report: latestState.report, limits: liveLimits, quota: selectedQuota)
        }
        detailsController.detailsView.onQuotaDisplayStyleChanged = { [weak self] style in
            self?.changeQuotaDisplayStyle(style)
        }
        detailsController.detailsView.onPlanCostChanged = { [weak self] value in self?.changePlanCost(value) }
        detailsController.detailsView.onPaymentStartDayChanged = { [weak self] value in self?.changePaymentStartDay(value) }
        detailsController.detailsView.onPaymentCurrencyChanged = { [weak self] currency in self?.changePaymentCurrency(currency) }
        detailsController.detailsView.onDisplayCurrencyChanged = { [weak self] currency in self?.changeDisplayCurrency(currency) }
        detailsController.detailsView.onShowHistoricalEmptyWeeksChanged = { [weak self] isOn in self?.changeShowHistoricalEmptyWeeks(isOn) }
        detailsController.detailsView.onChooseLogFolder = { [weak self] in self?.chooseLogFolder() }
        detailsController.detailsView.onResetLogFolder = { [weak self] in self?.resetLogFolder() }
        detailsController.detailsView.onOpenLogFolder = { [weak self] in self?.openSessionsFolder() }
        detailsController.detailsView.onLaunchAtLoginChanged = { [weak self] isOn in self?.changeLaunchAtLogin(isOn) }
        detailsController.detailsView.onShowCodexStatusChanged = { [weak self] isOn in self?.changeShowCodexStatus(isOn) }
        detailsController.detailsView.onQuotaWarningsChanged = { [weak self] isOn in self?.changeQuotaWarnings(isOn) }
        detailsController.detailsView.onProfileAPITotalsChanged = { [weak self] isOn in self?.changeProfileAPITotals(isOn) }
        applyLanguage()
        QuotaWarningManager.shared.requestAuthorization()

        refresh(forceLive: false)
        refreshLiveLimits()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh(forceLive: false)
        }
        liveRefreshTimer = Timer.scheduledTimer(withTimeInterval: liveRefreshInterval, repeats: true) { [weak self] _ in
            self?.refreshLiveLimits()
        }
    }

    private func configureStatusButton() {
        statusItem.length = NSStatusItem.variableLength
        guard let button = statusItem.button else { return }
        button.image = statusIconImage()
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.title = "--%"
        button.toolTip = "Token Meter"
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        button.action = #selector(togglePopover)
        button.target = self
    }

    private func statusIconImage() -> NSImage? {
        let image = NSImage(named: "StatusIconTemplate")
        image?.isTemplate = true
        image?.size = statusIconSize
        return image
    }

    private func setStatusLoading(_ loading: Bool) {
        guard statusIsLoading != loading else { return }
        statusIsLoading = loading
        statusSpinnerTimer?.invalidate()
        statusSpinnerTimer = nil

        guard let button = statusItem.button else { return }
        if loading {
            statusSpinnerFrame = 0
            updateStatusSpinnerImage()
            let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
                self?.updateStatusSpinnerImage()
            }
            statusSpinnerTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else {
            button.image = statusIconImage()
        }
    }

    private func updateStatusSpinnerImage() {
        guard let button = statusItem.button else { return }
        button.image = spinnerImage(frame: statusSpinnerFrame)
        statusSpinnerFrame = (statusSpinnerFrame + 1) % 12
    }

    private func spinnerImage(frame: Int) -> NSImage {
        let size = statusIconSize
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setStroke()
        let center = NSPoint(x: size.width / 2, y: size.height / 2)
        let radius: CGFloat = 4.8
        let start = CGFloat(frame) * 30
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: start + 255, clockwise: false)
        path.lineWidth = 1.8
        path.lineCapStyle = .round
        path.stroke()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func applyLanguage() {
        detailsController.applyLanguage()
        dashboardController.dashboardView.applyLanguage()
        dashboardController.dashboardView.update(latestState)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            updateDashboardSize(for: selectedQuota)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func updateDashboardSize(for quota: QuotaViewOption) {
        let size = DashboardView.preferredSize(for: quota)
        dashboardController.setDashboardSize(size)
        popover.contentSize = size
    }

    private func selectWindow(_ option: WindowOption) {
        selectedWindow = option
        UserDefaults.standard.set(option.rawValue, forKey: "selectedWindowHours")
        showCachedOrLoadingState()
        refresh(forceLive: false)
        if liveLimits.isEmpty {
            refreshLiveLimits()
        }
    }

    private func selectQuota(_ option: QuotaViewOption) {
        selectedQuota = option
        UserDefaults.standard.set(option.rawValue, forKey: "selectedQuotaView")
        updateDashboardSize(for: option)
        showCachedOrLoadingState()
        refresh(forceLive: false)
        if liveLimits.isEmpty {
            refreshLiveLimits()
        }
    }

    private func showCachedOrLoadingState() {
        let key = ReportCacheKey(window: selectedWindow, quota: selectedQuota)
        if let cached = reportCache[key] {
            latestState = DashboardState(
                report: cached,
                profileReport: profileReport(window: selectedWindow, quota: selectedQuota, accountUsage: accountUsage, localReport: cached),
                accountUsage: accountUsage,
                costReferenceReport: costReferenceReport(quota: selectedQuota, fallback: cached),
                liveLimits: liveLimits,
                serviceStatus: serviceStatus,
                selectedWindow: selectedWindow,
                selectedQuota: selectedQuota,
                nextRefreshAt: latestState.nextRefreshAt,
                isLoading: false,
                error: nil
            )
            dashboardController.dashboardView.update(latestState)
            updateStatusTitle(report: cached, limits: liveLimits, quota: selectedQuota)
        } else {
            latestState = DashboardState(
                report: TokenReport(scannedAt: Date()),
                profileReport: profileReport(window: selectedWindow, quota: selectedQuota, accountUsage: accountUsage, localReport: nil),
                accountUsage: accountUsage,
                costReferenceReport: costReferenceReport(quota: selectedQuota, fallback: nil),
                liveLimits: liveLimits,
                serviceStatus: serviceStatus,
                selectedWindow: selectedWindow,
                selectedQuota: selectedQuota,
                nextRefreshAt: latestState.nextRefreshAt,
                isLoading: true,
                error: nil
            )
            dashboardController.dashboardView.update(latestState)
            updateStatusTitle(report: latestState.report, limits: liveLimits, quota: selectedQuota)
        }
    }

    private func refresh(forceLive: Bool) {
        let window = selectedWindow
        let quota = selectedQuota
        let key = ReportCacheKey(window: window, quota: quota)
        guard !activeScans.contains(key) else { return }
        activeScans.insert(key)

        latestState = DashboardState(
            report: reportCache[key] ?? TokenReport(scannedAt: Date()),
            profileReport: profileReport(window: window, quota: quota, accountUsage: accountUsage, localReport: reportCache[key]),
            accountUsage: accountUsage,
            costReferenceReport: costReferenceReport(quota: quota, fallback: reportCache[key]),
            liveLimits: liveLimits,
            serviceStatus: serviceStatus,
            selectedWindow: window,
            selectedQuota: quota,
            nextRefreshAt: latestState.nextRefreshAt,
            isLoading: reportCache[key] == nil,
            error: nil
        )
        dashboardController.dashboardView.update(latestState)
        updateStatusTitle(report: latestState.report, limits: liveLimits, quota: quota)
        let currentLimits = liveLimits
        let currentAccountUsage = accountUsage

        scanQueue.async {
            let bundle = self.scanReportBundle(window: window, quota: quota)
            let report = bundle.report
            let accountUsage = self.readAccountUsageIfNeeded(fallback: currentAccountUsage)
            let limits = forceLive ? self.rateLimitReader.read() : currentLimits
            if forceLive, !limits.isEmpty {
                AppSettings.learnModelLimit(from: limits)
                CostHistoryStore.shared.record(limits: limits)
                QuotaWarningManager.shared.evaluate(limits: limits)
            }
            let nextRefresh = Date().addingTimeInterval(self.refreshInterval)
            DispatchQueue.main.async {
                self.activeScans.remove(key)
                self.reportCache[key] = report
                if let accountUsage {
                    self.accountUsage = accountUsage
                } else if !AppSettings.profileAPITotalsEnabled {
                    self.accountUsage = nil
                }
                if forceLive, !limits.isEmpty {
                    self.liveLimits = limits
                }
                if self.selectedWindow == window && self.selectedQuota == quota {
                    let effectiveLimits = forceLive && !limits.isEmpty ? limits : self.liveLimits
                    self.latestState = DashboardState(
                        report: report,
                        codexReport: bundle.codexReport,
                        claudeReport: bundle.claudeReport,
                        profileReport: self.profileReport(window: window, quota: quota, accountUsage: self.accountUsage, localReport: report),
                        accountUsage: self.accountUsage,
                        costReferenceReport: self.costReferenceReport(quota: quota, fallback: report),
                        liveLimits: effectiveLimits,
                        serviceStatus: self.serviceStatus,
                        selectedWindow: window,
                        selectedQuota: quota,
                        nextRefreshAt: nextRefresh,
                        isLoading: false,
                        error: effectiveLimits.isEmpty ? "Live limits unavailable" : nil
                    )
                    self.updateStatusTitle(report: report, limits: self.latestState.liveLimits, quota: quota)
                    self.dashboardController.dashboardView.update(self.latestState)
                } else if forceLive, !limits.isEmpty {
                    self.latestState.liveLimits = limits
                    self.latestState.serviceStatus = self.serviceStatus
                    self.latestState.accountUsage = self.accountUsage
                    self.latestState.profileReport = self.profileReport(window: self.latestState.selectedWindow, quota: self.latestState.selectedQuota, accountUsage: self.accountUsage, localReport: self.latestState.report)
                    self.updateStatusTitle(report: self.latestState.report, limits: limits, quota: self.latestState.selectedQuota)
                    self.dashboardController.dashboardView.update(self.latestState)
                }
                self.prewarmAllWindows()
            }
        }
    }

    private func refreshLiveLimits() {
        guard !liveRefreshInFlight else { return }
        liveRefreshInFlight = true
        liveQueue.async {
            let limits = self.rateLimitReader.read()
            let serviceStatus = self.serviceStatusReader.read()
            AppSettings.learnModelLimit(from: limits)
            CostHistoryStore.shared.record(limits: limits)
            QuotaWarningManager.shared.evaluate(limits: limits)
            let costReferenceReport = self.liveCostReferenceReport(limits: limits)
            DispatchQueue.main.async {
                self.liveRefreshInFlight = false
                if let serviceStatus {
                    self.serviceStatus = serviceStatus
                    self.latestState.serviceStatus = serviceStatus
                    self.detailsController.updateServiceStatus(serviceStatus)
                }
                guard !limits.isEmpty else {
                    self.updateStatusTitle(report: self.latestState.report, limits: self.liveLimits, quota: self.latestState.selectedQuota)
                    self.dashboardController.dashboardView.update(self.latestState)
                    return
                }
                self.liveLimits = limits
                self.latestState.liveLimits = limits
                self.latestState.error = nil
                self.updateStatusTitle(report: self.latestState.report, limits: limits, quota: self.latestState.selectedQuota)
                self.dashboardController.dashboardView.update(self.latestState)
                self.detailsController.updateLiveLimits(limits, costReferenceReport: costReferenceReport, serviceStatus: self.serviceStatus)
            }
        }
    }

    private func prewarmAllWindows() {
        for quota in QuotaViewOption.visibleCases {
            prewarm(window: .day, quota: quota)
            prewarm(window: .week, quota: quota)
            prewarm(window: .month, quota: quota)
        }
    }

    private func prewarm(window: WindowOption, quota: QuotaViewOption) {
        let key = ReportCacheKey(window: window, quota: quota)
        guard reportCache[key] == nil, !activeScans.contains(key) else { return }
        activeScans.insert(key)
        scanQueue.async {
            let bundle = self.scanReportBundle(window: window, quota: quota)
            let report = bundle.report
            DispatchQueue.main.async {
                self.activeScans.remove(key)
                self.reportCache[key] = report
                self.updateStatusTitle(report: self.latestState.report, limits: self.liveLimits, quota: self.latestState.selectedQuota)
                if self.selectedWindow == window && self.selectedQuota == quota {
                    self.latestState = DashboardState(
                        report: report,
                        codexReport: bundle.codexReport,
                        claudeReport: bundle.claudeReport,
                        profileReport: self.profileReport(window: window, quota: quota, accountUsage: self.accountUsage, localReport: report),
                        accountUsage: self.accountUsage,
                        costReferenceReport: self.costReferenceReport(quota: quota, fallback: report),
                        liveLimits: self.liveLimits,
                        serviceStatus: self.serviceStatus,
                        selectedWindow: window,
                        selectedQuota: quota,
                        nextRefreshAt: self.latestState.nextRefreshAt,
                        isLoading: false,
                        error: nil
                    )
                    self.updateStatusTitle(report: report, limits: self.liveLimits, quota: quota)
                    self.dashboardController.dashboardView.update(self.latestState)
                } else if window == .week && self.selectedQuota == quota {
                    self.latestState.costReferenceReport = report
                    self.dashboardController.dashboardView.update(self.latestState)
                }
            }
        }
    }

    private func readAccountUsageIfNeeded(fallback: AccountUsageSnapshot?) -> AccountUsageSnapshot? {
        guard AppSettings.profileAPITotalsEnabled else { return nil }
        return accountUsageReader.read() ?? fallback
    }

    private func scanReport(window: WindowOption, quota: QuotaViewOption) -> TokenReport {
        scanReportBundle(window: window, quota: quota).report
    }

    private func scanReportBundle(window: WindowOption, quota: QuotaViewOption) -> DashboardReportBundle {
        switch quota {
        case .claude:
            let claude = claudeScanner.scan(window: window)
            return DashboardReportBundle(report: claude, codexReport: nil, claudeReport: claude)
        case .all:
            let codex = scanner.scan(window: window)
            let claude = claudeScanner.scan(window: window)
            return DashboardReportBundle(report: mergedTokenReports([codex, claude], scannedAt: Date()), codexReport: codex, claudeReport: claude)
        case .codex:
            let codex = scanner.scan(window: window)
            return DashboardReportBundle(report: codex, codexReport: codex, claudeReport: nil)
        default:
            let report = scanner.scan(window: window, includedModelName: quota.includedModelName, excludedModelName: quota.excludedModelName)
            return DashboardReportBundle(report: report, codexReport: report, claudeReport: nil)
        }
    }

    private func profileReport(window: WindowOption, quota: QuotaViewOption, accountUsage: AccountUsageSnapshot?, localReport: TokenReport?) -> TokenReport? {
        guard AppSettings.profileAPITotalsEnabled,
              quota.usesCodexProfileAPI,
              let accountUsage,
              accountUsage.hasData else {
            return nil
        }
        let report: TokenReport
        if window == .day {
            let todayReport = accountUsage.report(days: 1)
            if todayReport.usage.total == 0, localReport?.usage.total ?? 0 > 0 {
                report = todayReport
            } else {
                report = accountUsage.report(window: window)
            }
        } else {
            report = accountUsage.report(window: window)
        }
        return profileReportWithLocalFallback(report, localReport: localReport)
    }

    private func costReferenceReport(quota: QuotaViewOption, fallback: TokenReport?) -> TokenReport? {
        reportCache[ReportCacheKey(window: .week, quota: quota)] ?? fallback
    }

    private func liveCostReferenceReport(limits: [LiveRateLimit]) -> TokenReport? {
        guard let weekly = costEstimateLimit(from: limits)?.secondary,
              weekly.usedPercent > 0,
              weekly.windowMinutes > 0,
              let resetsAt = weekly.resetsAt else {
            return nil
        }
        let start = resetsAt.addingTimeInterval(-TimeInterval(weekly.windowMinutes) * 60)
        let now = Date()
        guard start < now else { return nil }
        return scanner.scan(from: start, to: now)
    }

    private func updateStatusTitle(report: TokenReport, limits: [LiveRateLimit], quota: QuotaViewOption) {
        statusItem.length = NSStatusItem.variableLength
        guard let button = statusItem.button else { return }
        let option = StatusDisplayOption.current
        requestStatusUsageIfNeeded(option: option, quota: quota)
        let title = statusTitle(report: report, limits: limits, quota: quota, option: option)
        let pending = latestState.isLoading || statusValueIsPending(option: option, quota: quota, limits: limits)
        button.title = title ?? "--"
        setStatusLoading(pending)
    }

    private func statusTitle(report: TokenReport, limits: [LiveRateLimit], quota: QuotaViewOption, option: StatusDisplayOption) -> String? {
        let limit = selectedLimit(from: limits, quota: quota)
        switch option {
        case .fiveHourPercent:
            if let live = limit?.primary.remainingPercent {
                return "\(Int(round(live)))%"
            }
        case .weeklyPercent:
            if let live = limit?.secondary.remainingPercent {
                return "\(Int(round(live)))%"
            }
        case .weeklyTokens:
            if let usage = statusUsage(window: .week, quota: quota)?.usage, usage.total > 0 {
                return compact(usage.total)
            }
        case .dailyTokens:
            if let usage = statusUsage(window: .day, quota: quota)?.usage, usage.total > 0 {
                return compact(usage.total)
            }
        }
        return nil
    }

    private func requestStatusUsageIfNeeded(option: StatusDisplayOption, quota: QuotaViewOption) {
        guard let window = option.requiredReportWindow else { return }
        let key = ReportCacheKey(window: window, quota: quota)
        guard reportCache[key] == nil, !activeScans.contains(key) else { return }
        prewarm(window: window, quota: quota)
    }

    private func statusValueIsPending(option: StatusDisplayOption, quota: QuotaViewOption, limits: [LiveRateLimit]) -> Bool {
        switch option {
        case .fiveHourPercent:
            return limits.isEmpty && selectedLimit(from: limits, quota: quota)?.primary.remainingPercent == nil && liveRefreshInFlight
        case .weeklyPercent:
            return limits.isEmpty && selectedLimit(from: limits, quota: quota)?.secondary.remainingPercent == nil && liveRefreshInFlight
        case .weeklyTokens, .dailyTokens:
            guard let window = option.requiredReportWindow else { return false }
            let key = ReportCacheKey(window: window, quota: quota)
            return reportCache[key] == nil && activeScans.contains(key)
        }
    }

    private func statusUsage(window: WindowOption, quota: QuotaViewOption) -> TokenReport? {
        let key = ReportCacheKey(window: window, quota: quota)
        let localReport = reportCache[key] ?? (latestState.selectedWindow == window && latestState.selectedQuota == quota ? latestState.report : nil)
        if let profileReport = profileReport(window: window, quota: quota, accountUsage: accountUsage, localReport: localReport) {
            return profileReport
        }
        if let cached = reportCache[key] {
            return cached
        }
        if latestState.selectedWindow == window && latestState.selectedQuota == quota {
            return latestState.report
        }
        return nil
    }

    private func selectedLimit(from limits: [LiveRateLimit], quota: QuotaViewOption) -> LiveRateLimit? {
        if let exact = limits.first(where: { $0.id == quota.liveLimitID }) {
            return exact
        }
        if quota == .spark {
            return limits.first { $0.id != QuotaViewOption.all.liveLimitID }
        }
        return nil
    }

    private func openSessionsFolder() {
        NSWorkspace.shared.open(AppSettings.logFolderOpenURL)
    }

    private func openCodexStatusPage() {
        guard let url = URL(string: "https://status.openai.com") else { return }
        NSWorkspace.shared.open(url)
    }

    private func chooseLogFolder() {
        let panel = NSOpenPanel()
        panel.title = t(.logFolder)
        panel.message = t(.logFolderHint)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = AppSettings.logFolderURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        AppSettings.logFolderURL = url
        reloadScannerFromSettings()
    }

    private func resetLogFolder() {
        AppSettings.resetLogFolder()
        reloadScannerFromSettings()
    }

    private func changePlanCost(_ value: Double) {
        AppSettings.monthlyPlanCost = value
        detailsController.detailsView.needsDisplay = true
        detailsController.detailsView.needsLayout = true
        dashboardController.dashboardView.update(latestState)
    }

    private func changePaymentStartDay(_ value: String) {
        AppSettings.paymentStartDay = value
        detailsController.detailsView.needsDisplay = true
        detailsController.detailsView.needsLayout = true
    }

    private func changePaymentCurrency(_ currency: CurrencyCode) {
        let oldCurrency = AppSettings.paymentCurrency
        guard oldCurrency != currency else { return }
        AppSettings.monthlyPlanCost = convertCurrency(AppSettings.monthlyPlanCost, from: oldCurrency, to: currency)
        AppSettings.paymentCurrency = currency
        if UserDefaults.standard.string(forKey: AppSettings.displayCurrencyKey) == nil {
            AppSettings.displayCurrency = currency
        }
        detailsController.detailsView.needsDisplay = true
        detailsController.detailsView.needsLayout = true
        dashboardController.dashboardView.update(latestState)
    }

    private func changeDisplayCurrency(_ currency: CurrencyCode) {
        AppSettings.displayCurrency = currency
        detailsController.detailsView.needsDisplay = true
        detailsController.detailsView.needsLayout = true
        dashboardController.dashboardView.update(latestState)
    }

    private func changeNumberUnitStyle(_ style: NumberUnitStyle) {
        NumberUnitStyle.current = style
        detailsController.detailsView.needsDisplay = true
        dashboardController.dashboardView.update(latestState)
        updateStatusTitle(report: latestState.report, limits: liveLimits, quota: selectedQuota)
    }

    private func changeQuotaDisplayStyle(_ style: QuotaDisplayStyle) {
        QuotaDisplayStyle.current = style
        detailsController.detailsView.needsDisplay = true
        dashboardController.dashboardView.needsLayout = true
        dashboardController.dashboardView.update(latestState)
    }

    private func changeShowHistoricalEmptyWeeks(_ value: Bool) {
        AppSettings.showHistoricalEmptyWeeks = value
        detailsController.detailsView.needsDisplay = true
        detailsController.detailsView.needsLayout = true
    }

    private func changeLaunchAtLogin(_ value: Bool) {
        _ = LoginItemManager.setEnabled(value)
        detailsController.detailsView.needsDisplay = true
        detailsController.detailsView.needsLayout = true
    }

    private func changeShowCodexStatus(_ value: Bool) {
        AppSettings.showCodexStatusEnabled = value
        detailsController.detailsView.needsDisplay = true
        detailsController.detailsView.needsLayout = true
        dashboardController.dashboardView.needsLayout = true
        dashboardController.dashboardView.update(latestState)
    }

    private func changeQuotaWarnings(_ value: Bool) {
        AppSettings.quotaWarningsEnabled = value
        if value {
            QuotaWarningManager.shared.requestAuthorization()
            QuotaWarningManager.shared.evaluate(limits: liveLimits)
        }
        detailsController.detailsView.needsDisplay = true
        detailsController.detailsView.needsLayout = true
    }

    private func changeProfileAPITotals(_ value: Bool) {
        AppSettings.profileAPITotalsEnabled = value
        if !value {
            accountUsage = nil
            latestState.accountUsage = nil
            latestState.profileReport = nil
            if var snapshot = detailsController.detailsView.snapshot {
                snapshot.accountUsage = nil
                detailsController.detailsView.snapshot = snapshot
            }
        }
        detailsController.detailsView.needsDisplay = true
        detailsController.detailsView.needsLayout = true
        dashboardController.dashboardView.update(latestState)
        updateStatusTitle(report: latestState.report, limits: liveLimits, quota: selectedQuota)
        refresh(forceLive: false)
        if detailsController.window?.isVisible == true {
            openDetailsWindow()
        }
    }

    private func reloadScannerFromSettings() {
        scanner = CodexTokenScanner(rootURLs: AppSettings.logFolderURLs)
        claudeScanner = ClaudeTokenScanner(rootURLs: AppSettings.claudeLogFolderURLs)
        reportCache.removeAll()
        activeScans.removeAll()
        detailsController.detailsView.needsDisplay = true
        refresh(forceLive: false)
    }

    private func openUsageDetailsWindow() {
        detailsController.detailsView.showUsagePage()
        openDetailsWindow()
    }

    private func openSettingsWindow() {
        detailsController.detailsView.showSettingsPage()
        openDetailsWindow()
    }

    private func openDetailsWindow() {
        detailsLoadGeneration += 1
        let loadGeneration = detailsLoadGeneration
        detailsController.showLoading()
        if liveLimits.isEmpty {
            refreshLiveLimits()
        }
        let limits = liveLimits
        let currentServiceStatus = serviceStatus
        let currentAccountUsage = accountUsage
        let updateProgress: (Double, L10nKey) -> Void = { [weak self] fraction, messageKey in
            DispatchQueue.main.async {
                guard let self, self.detailsLoadGeneration == loadGeneration else { return }
                self.detailsController.updateLoadingProgress(DetailsLoadingProgress(fraction: fraction, messageKey: messageKey))
            }
        }
        scanQueue.async {
            updateProgress(0.12, .loadingAllUsage)
            let all = self.scanner.scan(days: 365)
            updateProgress(0.28, .loadingSparkUsage)
            let spark = self.scanner.scan(days: 365, includedModelName: QuotaViewOption.spark.includedModelName)
            updateProgress(0.44, .loadingOtherUsage)
            let other = self.scanner.scan(days: 365, excludedModelName: QuotaViewOption.other.excludedModelName)
            updateProgress(0.62, .loadingRepoInsights)
            let repoInsightReports = self.scanner.scanRepoInsights(windows: [7, 30, 90])
            let repoInsights = repoInsightReports[90] ?? self.scanner.scanRepoInsights(days: 90)
            updateProgress(0.82, .loadingProfileTotals)
            let costReferenceReport = self.liveCostReferenceReport(limits: limits)
            let accountUsage = self.readAccountUsageIfNeeded(fallback: currentAccountUsage)
            updateProgress(0.94, .loadingFinalizing)
            let snapshot = DetailsSnapshot(all: all, spark: spark, other: other, repoInsights: repoInsights, repoInsightReports: repoInsightReports, liveLimits: limits, serviceStatus: currentServiceStatus, costReferenceReport: costReferenceReport, accountUsage: accountUsage)
            DispatchQueue.main.async {
                guard self.detailsLoadGeneration == loadGeneration else { return }
                if let accountUsage {
                    self.accountUsage = accountUsage
                    self.latestState.accountUsage = accountUsage
                    self.latestState.profileReport = self.profileReport(window: self.latestState.selectedWindow, quota: self.latestState.selectedQuota, accountUsage: accountUsage, localReport: self.latestState.report)
                    self.dashboardController.dashboardView.update(self.latestState)
                    self.updateStatusTitle(report: self.latestState.report, limits: self.liveLimits, quota: self.selectedQuota)
                } else if !AppSettings.profileAPITotalsEnabled {
                    self.accountUsage = nil
                    self.latestState.accountUsage = nil
                    self.latestState.profileReport = nil
                }
                self.detailsController.update(snapshot: snapshot)
            }
        }
    }

    private func summaryText(state: DashboardState) -> String {
        let report = state.report
        var lines = [
            "Token Meter - \(state.selectedWindow.title)",
            "Scanned: \(localFormatter.string(from: report.scannedAt)) Asia/Shanghai",
            "Next refresh: \(localFormatter.string(from: state.nextRefreshAt)) Asia/Shanghai",
            "Sessions: \(report.sessions)",
            "Turns: \(report.turns)",
            "Total: \(report.usage.total)",
            "Input: \(report.usage.input)",
            "Cached input: \(report.usage.cachedInput)",
            "Fresh input: \(report.usage.freshInput)",
            "Output: \(report.usage.output)",
            "Reasoning output: \(report.usage.reasoningOutput)",
            String(format: "Cache percent: %.1f%%", report.usage.cachePercent)
        ]
        for limit in state.liveLimits {
            lines.append("\(limit.name): 5h \(limit.primary.usedPercent)% used, weekly \(limit.secondary.usedPercent)% used")
        }
        if let limit = selectedLimit(from: state.liveLimits, quota: state.selectedQuota),
           let estimate = planCostEstimate(report: report, selectedDay: nil, limit: limit) {
            lines.append("Payment currency: \(AppSettings.paymentCurrency.rawValue)")
            lines.append("Display currency: \(AppSettings.displayCurrency.rawValue)")
            lines.append("Plan cost: \(paymentMoney(estimate.monthlyCost))/month")
            lines.append("Today value: \(displayMoney(estimate.todayValue))")
            lines.append("Weekly used value: \(displayMoney(estimate.weeklyUsedValue))")
            lines.append("Weekly unused value: \(displayMoney(estimate.weeklyUnusedValue))")
        }
        lines.append("By day:")
        for day in report.byDay {
            lines.append("\(day.day)\t\(day.usage.total)\t\(day.usage.input)\t\(day.usage.cachedInput)\t\(day.usage.output)\tturns=\(day.turns)")
        }
        return lines.joined(separator: "\n")
    }
}
