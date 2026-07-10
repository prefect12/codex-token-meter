import Cocoa
import Foundation
import ServiceManagement
import UserNotifications

// MARK: - App Lifecycle

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let dashboardController = DashboardViewController()
    private let detailsController = UsageDetailsWindowController()
    private var scanner = CodexTokenScanner(rootURLs: AppSettings.logFolderURLs)
    private var claudeScanner = ClaudeTokenScanner(rootURLs: AppSettings.claudeLogFolderURLs)
    private let rateLimitReader = LiveRateLimitReader()
    private let accountUsageReader = AccountUsageReader()
    private let resetCreditsReader = RateLimitResetCreditsReader()
    private let serviceStatusReader = CodexServiceStatusReader()
    private let localFormatter = DateFormatter()
    private let scanQueue = DispatchQueue(label: "local.codex-token-meter.scan", qos: .utility)
    private let liveQueue = DispatchQueue(label: "local.codex-token-meter.live", qos: .utility)
    private let storageScanQueue = DispatchQueue(label: "local.codex-token-meter.storage-scan", qos: .userInitiated)
    private var selectedWindow: WindowOption = .week
    private var selectedQuota: QuotaViewOption = .all
    private var latestState = DashboardState()
    private var reportCache: [ReportCacheKey: TokenReport] = [:]
    private var accountUsage: AccountUsageSnapshot?
    private var liveLimits: [LiveRateLimit] = []
    private var resetCredits: RateLimitResetCreditsSnapshot?
    private var serviceStatus: CodexServiceStatusSnapshot?
    private var refreshTimer: Timer?
    private var liveRefreshTimer: Timer?
    private var claudeActiveRefreshTimer: Timer?
    private var activeScans: Set<ReportCacheKey> = []
    private var liveRefreshInFlight = false
    private var detailsSnapshotPrewarmInFlight = false
    private var statusSpinnerTimer: Timer?
    private var statusSpinnerFrame = 0
    private var statusIsLoading = false
    private var detailsLoadGeneration = 0
    private let refreshInterval: TimeInterval = 300
    private let liveRefreshInterval: TimeInterval = 15
    private let statusIconSize = NSSize(width: 14, height: 14)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        localFormatter.locale = Locale(identifier: "en_US_POSIX")
        localFormatter.timeZone = appTimeZone()
        localFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        selectedWindow = .day
        if let rawQuota = UserDefaults.standard.string(forKey: "selectedQuotaView"),
           let quota = QuotaViewOption.option(from: rawQuota) {
            selectedQuota = quota
        }
        liveLimits = LiveRateLimitCacheStore.read()

        NSApp.applicationIconImage = NSImage(named: "LogoHeader")
        popover.contentViewController = dashboardController
        resizeDashboardPopover(to: DashboardView.idealSize)
        popover.behavior = .transient
        configureStatusButton()

        dashboardController.dashboardView.onWindowChanged = { [weak self] option in self?.selectWindow(option) }
        dashboardController.dashboardView.onQuotaChanged = { [weak self] option in self?.selectQuota(option) }
        dashboardController.dashboardView.onPreferredSizeChanged = { [weak self] size in
            self?.resizeDashboardPopover(to: size)
        }
        dashboardController.dashboardView.onRefresh = { [weak self] in
            self?.refresh(forceLive: false)
            self?.refreshLiveLimits(allowClaudeActiveRefresh: true)
        }
        dashboardController.dashboardView.onOpenDetails = { [weak self] in self?.openUsageDetailsWindow() }
        dashboardController.dashboardView.onOpenSettings = { [weak self] in self?.openSettingsWindow() }
        dashboardController.dashboardView.onOpenCodexStatus = { [weak self] in self?.openCodexStatusPage() }
        dashboardController.dashboardView.onOpenPlatformStatus = { [weak self] option in
            self?.openPlatformStatusPage(option)
        }
        dashboardController.dashboardView.onQuit = { NSApp.terminate(nil) }
        detailsController.detailsView.onLanguageChanged = { [weak self] language in
            AppLanguage.current = language
            self?.applyLanguage()
        }
        detailsController.detailsView.onNumberUnitStyleChanged = { [weak self] style in
            self?.changeNumberUnitStyle(style)
        }
        detailsController.detailsView.onStatusBarMetricChanged = { [weak self] slot, metric in
            self?.changeStatusBarMetric(slot: slot, metric: metric)
        }
        detailsController.detailsView.onQuotaDisplayStyleChanged = { [weak self] style in
            self?.changeQuotaDisplayStyle(style)
        }
        detailsController.detailsView.onCodexHomeRingMetricChanged = { [weak self] metric in
            self?.changeCodexHomeRingMetric(metric)
        }
        detailsController.detailsView.onClaudeHomeRingMetricChanged = { [weak self] metric in
            self?.changeClaudeHomeRingMetric(metric)
        }
        detailsController.detailsView.onPlanCostChanged = { [weak self] value, source in self?.changePlanCost(value, source: source) }
        detailsController.detailsView.onPaymentStartDayChanged = { [weak self] value, source in self?.changePaymentStartDay(value, source: source) }
        detailsController.detailsView.onPaymentCurrencyChanged = { [weak self] currency, source in self?.changePaymentCurrency(currency, source: source) }
        detailsController.detailsView.onDisplayCurrencyChanged = { [weak self] currency, source in self?.changeDisplayCurrency(currency, source: source) }
        detailsController.detailsView.onShowHistoricalEmptyWeeksChanged = { [weak self] isOn in self?.changeShowHistoricalEmptyWeeks(isOn) }
        detailsController.detailsView.onChooseLogFolder = { [weak self] in self?.chooseLogFolder() }
        detailsController.detailsView.onResetLogFolder = { [weak self] in self?.resetLogFolder() }
        detailsController.detailsView.onOpenLogFolder = { [weak self] in self?.openSessionsFolder() }
        detailsController.detailsView.onChooseCodexAPISource = { [weak self] in self?.chooseCodexAPISource() }
        detailsController.detailsView.onResetCodexAPISources = { [weak self] in self?.resetCodexAPISources() }
        detailsController.detailsView.onOpenCodexAPISource = { [weak self] in self?.openCodexAPISource() }
        detailsController.detailsView.onLaunchAtLoginChanged = { [weak self] isOn in self?.changeLaunchAtLogin(isOn) }
        detailsController.detailsView.onShowCodexStatusChanged = { [weak self] isOn in self?.changeShowCodexStatus(isOn) }
        detailsController.detailsView.onQuotaWarningsChanged = { [weak self] isOn in self?.changeQuotaWarnings(isOn) }
        detailsController.detailsView.onProfileAPITotalsChanged = { [weak self] isOn in self?.changeProfileAPITotals(isOn) }
        detailsController.detailsView.onClaudeActiveQuotaRefreshChanged = { [weak self] isOn in self?.changeClaudeActiveQuotaRefresh(isOn) }
        detailsController.detailsView.onExportMachineUsageReport = { [weak self] in self?.exportMachineUsageReport() }
        detailsController.detailsView.onStorageScanRequested = { [weak self] in self?.refreshStorageSnapshot() }
        applyLanguage()
        QuotaWarningManager.shared.requestAuthorization()

        reportCache = DashboardReportCacheStore.read()
        refresh(forceLive: false)
        refreshLiveLimits()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh(forceLive: false)
        }
        liveRefreshTimer = Timer.scheduledTimer(withTimeInterval: liveRefreshInterval, repeats: true) { [weak self] _ in
            self?.refreshLiveLimits()
        }
        scheduleClaudeActiveRefreshIfNeeded()
    }

    private func refreshStorageSnapshot() {
        if detailsController.detailsView.storageSnapshot == nil,
           let cached = StorageSnapshotCacheStore.read() {
            detailsController.detailsView.storageSnapshot = cached
        }
        storageScanQueue.async { [weak self] in
            let snapshot = StorageScanner.scan()
            StorageSnapshotCacheStore.write(snapshot)
            DispatchQueue.main.async {
                guard let self else { return }
                self.detailsController.detailsView.isStorageScanning = false
                self.detailsController.detailsView.storageSnapshot = snapshot
            }
        }
    }

    private func resizeDashboardPopover(to size: NSSize) {
        guard popover.contentSize != size else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            dashboardController.preferredContentSize = size
            dashboardController.view.frame = NSRect(origin: .zero, size: size)
            dashboardController.dashboardView.frame = NSRect(origin: .zero, size: size)
            dashboardController.dashboardView.layoutSubtreeIfNeeded()
            popover.contentSize = size
        }
    }

    private func configureStatusButton() {
        statusItem.length = NSStatusItem.variableLength
        guard let button = statusItem.button else { return }
        button.image = statusIconImage()
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.title = "--%"
        button.toolTip = "AI Token Meter"
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
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            refreshLiveLimits()
        }
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
        showCachedOrLoadingState()
        refresh(forceLive: false)
        if liveLimits.isEmpty {
            refreshLiveLimits()
        }
    }

    private func showCachedOrLoadingState() {
        let key = ReportCacheKey(window: selectedWindow, quota: selectedQuota)
        let platformReports = cachedPlatformReports(window: selectedWindow, quota: selectedQuota)
        if let cached = reportCache[key] {
            latestState = DashboardState(
                report: cached,
                codexReport: platformReports.codex,
                claudeReport: platformReports.claude,
                profileReport: profileReport(window: selectedWindow, quota: selectedQuota, accountUsage: accountUsage, localReport: cached),
                accountUsage: accountUsage,
                costReferenceReport: costReferenceReport(quota: selectedQuota, fallback: cached),
                liveLimits: liveLimits,
                resetCredits: resetCredits,
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
                codexReport: platformReports.codex,
                claudeReport: platformReports.claude,
                profileReport: profileReport(window: selectedWindow, quota: selectedQuota, accountUsage: accountUsage, localReport: nil),
                accountUsage: accountUsage,
                costReferenceReport: costReferenceReport(quota: selectedQuota, fallback: nil),
                liveLimits: liveLimits,
                resetCredits: resetCredits,
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

    private func cachedPlatformReports(window: WindowOption, quota: QuotaViewOption) -> (codex: TokenReport?, claude: TokenReport?) {
        guard quota == .all else { return (nil, nil) }
        return (
            reportCache[ReportCacheKey(window: window, quota: .codex)],
            reportCache[ReportCacheKey(window: window, quota: .claude)]
        )
    }

    private func refresh(forceLive: Bool) {
        let window = selectedWindow
        let quota = selectedQuota
        let key = ReportCacheKey(window: window, quota: quota)
        guard !activeScans.contains(key) else { return }
        activeScans.insert(key)
        let platformReports = cachedPlatformReports(window: window, quota: quota)

        latestState = DashboardState(
            report: reportCache[key] ?? TokenReport(scannedAt: Date()),
            codexReport: platformReports.codex,
            claudeReport: platformReports.claude,
            profileReport: profileReport(window: window, quota: quota, accountUsage: accountUsage, localReport: reportCache[key]),
            accountUsage: accountUsage,
            costReferenceReport: costReferenceReport(quota: quota, fallback: reportCache[key]),
            liveLimits: liveLimits,
            resetCredits: resetCredits,
            serviceStatus: serviceStatus,
            selectedWindow: window,
            selectedQuota: quota,
            nextRefreshAt: latestState.nextRefreshAt,
            isLoading: true,
            error: nil
        )
        dashboardController.dashboardView.update(latestState)
        updateStatusTitle(report: latestState.report, limits: liveLimits, quota: quota)
        let currentLimits = liveLimits
        let currentAccountUsage = accountUsage
        let currentResetCredits = resetCredits

        scanQueue.async {
            let codexReport: TokenReport?
            let claudeReport: TokenReport?
            let report: TokenReport
            if quota == .all {
                let codex = self.scanner.scan(window: window)
                let claude = self.claudeScanner.scan(window: window)
                codexReport = codex
                claudeReport = claude
                report = mergedTokenReport([codex, claude])
            } else {
                codexReport = nil
                claudeReport = nil
                report = self.scanReport(window: window, source: quota)
            }
            let accountUsage = quota.usesCodexProfileAPI ? self.readAccountUsageIfNeeded(fallback: currentAccountUsage) : currentAccountUsage
            let freshLimits = forceLive ? combinedLiveLimits(codexReader: self.rateLimitReader) : currentLimits
            let limits = forceLive ? self.mergedLiveLimits(fresh: freshLimits, fallback: currentLimits) : currentLimits
            let freshResetCredits = forceLive ? self.resetCreditsReader.read() : currentResetCredits
            let effectiveResetCredits = freshResetCredits ?? currentResetCredits
            let freshCodexLimits = codexTrackedLiveLimits(freshLimits)
            if forceLive, !limits.isEmpty {
                LiveRateLimitCacheStore.write(limits)
            }
            if forceLive, !freshCodexLimits.isEmpty {
                AppSettings.learnModelLimit(from: freshCodexLimits)
                CostHistoryStore.shared.record(limits: freshCodexLimits)
                QuotaCycleStore.shared.record(limits: freshLimits)
                QuotaWarningManager.shared.evaluate(limits: freshCodexLimits)
            }
            let nextRefresh = Date().addingTimeInterval(self.refreshInterval)
            let codexReportForHistory = codexReport ?? (quota == .codex ? report : nil)
            DispatchQueue.main.async {
                self.activeScans.remove(key)
                self.reportCache[key] = report
                if let codexReport {
                    self.reportCache[ReportCacheKey(window: window, quota: .codex)] = codexReport
                }
                if let claudeReport {
                    self.reportCache[ReportCacheKey(window: window, quota: .claude)] = claudeReport
                }
                DashboardReportCacheStore.write(self.reportCache)
                if let accountUsage {
                    self.accountUsage = accountUsage
                } else if !AppSettings.profileAPITotalsEnabled {
                    self.accountUsage = nil
                }
                if forceLive, !limits.isEmpty {
                    self.liveLimits = limits
                }
                if let freshResetCredits {
                    self.resetCredits = freshResetCredits
                }
                MachineUsageReportStore.shared.record(
                    localCodexReport: codexReportForHistory,
                    accountUsage: self.accountUsage,
                    liveLimits: forceLive && !limits.isEmpty ? limits : self.liveLimits
                )
                if self.selectedWindow == window && self.selectedQuota == quota {
                    let cachedPlatforms = self.cachedPlatformReports(window: window, quota: quota)
                    let effectiveLimits = forceLive && !limits.isEmpty ? limits : self.liveLimits
                    self.latestState = DashboardState(
                        report: report,
                        codexReport: codexReport ?? cachedPlatforms.codex,
                        claudeReport: claudeReport ?? cachedPlatforms.claude,
                        profileReport: self.profileReport(window: window, quota: quota, accountUsage: self.accountUsage, localReport: report),
                        accountUsage: self.accountUsage,
                        costReferenceReport: self.costReferenceReport(quota: quota, fallback: report),
                        liveLimits: effectiveLimits,
                        resetCredits: effectiveResetCredits,
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
                    self.latestState.resetCredits = effectiveResetCredits
                    self.latestState.serviceStatus = self.serviceStatus
                    self.latestState.accountUsage = self.accountUsage
                    self.latestState.profileReport = self.profileReport(window: self.latestState.selectedWindow, quota: self.latestState.selectedQuota, accountUsage: self.accountUsage, localReport: self.latestState.report)
                    self.updateStatusTitle(report: self.latestState.report, limits: limits, quota: self.latestState.selectedQuota)
                    self.dashboardController.dashboardView.update(self.latestState)
                }
                self.prewarmAllWindows()
                self.prewarmDetailsSnapshot()
            }
        }
    }

    private func refreshLiveLimits(allowClaudeActiveRefresh: Bool = false) {
        guard !liveRefreshInFlight else { return }
        liveRefreshInFlight = true
        let currentLimits = liveLimits
        let currentResetCredits = resetCredits
        liveQueue.async {
            let claudeStore = ClaudeStatuslineStore()
            if allowClaudeActiveRefresh && AppSettings.claudeActiveQuotaRefreshEnabled {
                _ = ClaudeOAuthUsageRefresher.shared.refreshIfNeeded(store: claudeStore)
                _ = ClaudeActiveQuotaRefresher.shared.refreshIfNeeded(snapshot: claudeStore.read())
            }
            let freshLimits = combinedLiveLimits(codexReader: self.rateLimitReader, claudeStore: claudeStore)
            let limits = self.mergedLiveLimits(fresh: freshLimits, fallback: currentLimits)
            let freshResetCredits = self.resetCreditsReader.read()
            let effectiveResetCredits = freshResetCredits ?? currentResetCredits
            let serviceStatus = self.serviceStatusReader.read()
            let freshCodexLimits = codexTrackedLiveLimits(freshLimits)
            if !limits.isEmpty {
                LiveRateLimitCacheStore.write(limits)
            }
            if !freshCodexLimits.isEmpty {
                AppSettings.learnModelLimit(from: freshCodexLimits)
                CostHistoryStore.shared.record(limits: freshCodexLimits)
                QuotaCycleStore.shared.record(limits: freshLimits)
                QuotaWarningManager.shared.evaluate(limits: freshCodexLimits)
            }
            let costReferenceReport = self.liveCostReferenceReport(limits: limits)
            DispatchQueue.main.async {
                self.liveRefreshInFlight = false
                if let serviceStatus {
                    self.serviceStatus = serviceStatus
                    self.latestState.serviceStatus = serviceStatus
                    self.detailsController.updateServiceStatus(serviceStatus)
                }
                if let freshResetCredits {
                    self.resetCredits = freshResetCredits
                }
                self.latestState.resetCredits = effectiveResetCredits
                self.detailsController.updateResetCredits(effectiveResetCredits)
                guard !limits.isEmpty else {
                    self.updateStatusTitle(report: self.latestState.report, limits: self.liveLimits, quota: self.latestState.selectedQuota)
                    self.dashboardController.dashboardView.update(self.latestState)
                    return
                }
                self.liveLimits = limits
                self.latestState.liveLimits = limits
                self.latestState.resetCredits = effectiveResetCredits
                self.latestState.error = nil
                MachineUsageReportStore.shared.record(
                    localCodexReport: nil,
                    accountUsage: self.accountUsage,
                    liveLimits: limits
                )
                self.updateStatusTitle(report: self.latestState.report, limits: limits, quota: self.latestState.selectedQuota)
                self.dashboardController.dashboardView.update(self.latestState)
                self.detailsController.updateLiveLimits(limits, costReferenceReport: costReferenceReport, serviceStatus: self.serviceStatus)
            }
        }
    }

    private func mergedLiveLimits(fresh: [LiveRateLimit], fallback: [LiveRateLimit]) -> [LiveRateLimit] {
        guard !fresh.isEmpty else { return fallback }
        var merged = fallback
        for limit in fresh {
            if let index = merged.firstIndex(where: { $0.id == limit.id }) {
                merged[index] = limit
            } else {
                merged.append(limit)
            }
        }
        return merged
    }

    private func prewarmAllWindows() {
        for quota in QuotaViewOption.allCases {
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
            let report = self.scanReport(window: window, source: quota)
            DispatchQueue.main.async {
                self.activeScans.remove(key)
                self.reportCache[key] = report
                DashboardReportCacheStore.write(self.reportCache)
                self.updateStatusTitle(report: self.latestState.report, limits: self.liveLimits, quota: self.latestState.selectedQuota)
                if self.selectedWindow == window && self.selectedQuota == quota {
                    let platformReports = self.cachedPlatformReports(window: window, quota: quota)
                    self.latestState = DashboardState(
                        report: report,
                        codexReport: platformReports.codex,
                        claudeReport: platformReports.claude,
                        profileReport: self.profileReport(window: window, quota: quota, accountUsage: self.accountUsage, localReport: report),
                        accountUsage: self.accountUsage,
                        costReferenceReport: self.costReferenceReport(quota: quota, fallback: report),
                        liveLimits: self.liveLimits,
                        resetCredits: self.resetCredits,
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
                } else if self.selectedWindow == window && self.selectedQuota == .all && quota != .all {
                    if quota == .codex {
                        self.latestState.codexReport = report
                    } else if quota == .claude {
                        self.latestState.claudeReport = report
                    }
                    self.latestState.profileReport = self.profileReport(window: window, quota: .all, accountUsage: self.accountUsage, localReport: self.latestState.report)
                    self.dashboardController.dashboardView.update(self.latestState)
                }
            }
        }
    }

    private func scanReport(window: WindowOption, source: QuotaViewOption) -> TokenReport {
        switch source {
        case .all:
            return mergedTokenReport([
                scanner.scan(window: window),
                claudeScanner.scan(window: window)
            ])
        case .codex:
            return scanner.scan(window: window)
        case .claude:
            return claudeScanner.scan(window: window)
        }
    }

    private func scanReport(days: Int, source: QuotaViewOption) -> TokenReport {
        switch source {
        case .all:
            return mergedTokenReport([
                scanner.scan(days: days),
                claudeScanner.scan(days: days)
            ])
        case .codex:
            return scanner.scan(days: days)
        case .claude:
            return claudeScanner.scan(days: days)
        }
    }

    private func readAccountUsageIfNeeded(fallback: AccountUsageSnapshot?) -> AccountUsageSnapshot? {
        guard AppSettings.profileAPITotalsEnabled else { return nil }
        return accountUsageReader.read() ?? fallback
    }

    private func profileReport(window: WindowOption, quota: QuotaViewOption, accountUsage: AccountUsageSnapshot?, localReport: TokenReport?) -> TokenReport? {
        guard AppSettings.profileAPITotalsEnabled else {
            return nil
        }
        let platformReports = cachedPlatformReports(window: window, quota: quota)
        return profileBackedReport(
            window: window,
            quota: quota,
            accountUsage: accountUsage,
            localReport: localReport,
            localCodexReport: platformReports.codex,
            localClaudeReport: platformReports.claude
        )
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
        let metrics = AppSettings.statusBarMetrics
        let title = statusTitle(metrics: metrics, limits: limits)
        let pending = latestState.isLoading || statusValueIsPending(metrics: metrics, limits: limits)
        button.title = title ?? "--"
        setStatusLoading(pending)
    }

    private func statusTitle(metrics: [StatusBarMetric], limits: [LiveRateLimit]) -> String? {
        let parts = metrics.map { statusMetricText($0, limits: limits) }
        guard parts.contains(where: { $0 != nil }) else { return nil }
        return parts.map { $0 ?? "--" }.joined(separator: " | ")
    }

    private func statusMetricText(_ metric: StatusBarMetric, limits: [LiveRateLimit]) -> String? {
        let limit = statusLimit(from: limits, source: metric.source)
        switch metric.quotaMetric {
        case .fiveHour:
            return statusPercentText(limit?.primary.remainingPercent, source: metric.source)
        case .weekly:
            return statusPercentText(limit?.secondary.remainingPercent, source: metric.source)
        }
    }

    private func statusLimit(from limits: [LiveRateLimit], source: QuotaViewOption) -> LiveRateLimit? {
        limits.first { $0.id == source.liveLimitID }
    }

    private func statusPercentText(_ percent: Double?, source: QuotaViewOption) -> String? {
        guard let percent else { return nil }
        return "\(Int(round(percent)))%"
    }

    private func statusValueIsPending(metrics: [StatusBarMetric], limits: [LiveRateLimit]) -> Bool {
        liveRefreshInFlight && metrics.contains { statusMetricText($0, limits: limits) == nil }
    }

    private func selectedLimit(from limits: [LiveRateLimit], quota: QuotaViewOption) -> LiveRateLimit? {
        if let exact = limits.first(where: { $0.id == quota.liveLimitID }) {
            return exact
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

    private func openPlatformStatusPage(_ option: QuotaViewOption) {
        let rawURL: String
        switch option {
        case .all, .codex:
            rawURL = "https://status.openai.com"
        case .claude:
            rawURL = "https://status.claude.com"
        }
        guard let url = URL(string: rawURL) else { return }
        NSWorkspace.shared.open(url)
    }

    private func chooseLogFolder() {
        let panel = NSOpenPanel()
        panel.title = t(.logFolder)
        panel.message = t(.logFolderHint)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = AppSettings.logFolderURL
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        AppSettings.addLogFolderURLs(panel.urls)
        reloadScannerFromSettings()
    }

    private func resetLogFolder() {
        AppSettings.resetLogFolder()
        reloadScannerFromSettings()
    }

    private func openCodexAPISource() {
        NSWorkspace.shared.open(AppSettings.codexAPISourceOpenURL)
    }

    private func exportMachineUsageReport() {
        let copy = AppLanguage.current.machineUsageReportCopy
        let panel = NSOpenPanel()
        panel.title = copy.chooseFolder
        panel.message = copy.hint
        panel.prompt = copy.exportAction
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

        let export = { (response: NSApplication.ModalResponse) in
            guard response == .OK, let parent = panel.url else { return }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let archive = parent.appendingPathComponent("AI-Token-Meter-Usage-Report-\(formatter.string(from: Date())).zip")
            do {
                let output = try MachineUsageReportStore.shared.exportArchive(to: archive)
                NSWorkspace.shared.activateFileViewerSelecting([output])
            } catch {
                NSLog("AI Token Meter machine usage export failed: \(error.localizedDescription)")
                NSSound.beep()
            }
        }
        if let window = detailsController.window {
            panel.beginSheetModal(for: window, completionHandler: export)
        } else {
            export(panel.runModal())
        }
    }

    private func chooseCodexAPISource() {
        let panel = NSOpenPanel()
        panel.title = t(.codexAPISources)
        panel.message = t(.codexAPISourcesHint)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = AppSettings.codexAPISourceOpenURL
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        AppSettings.setCodexAPISourceHomeURLs(panel.urls)
        reloadOfficialAPISourcesFromSettings()
    }

    private func resetCodexAPISources() {
        AppSettings.resetCodexAPISourceHomeURLs()
        reloadOfficialAPISourcesFromSettings()
    }

    private func changePlanCost(_ value: Double, source: QuotaViewOption) {
        guard source != .all else { return }
        AppSettings.setMonthlyPlanCost(value, for: source)
        detailsController.detailsView.needsDisplay = true
        detailsController.detailsView.needsLayout = true
        dashboardController.dashboardView.update(latestState)
    }

    private func changePaymentStartDay(_ value: String, source: QuotaViewOption) {
        guard source != .all else { return }
        AppSettings.setPaymentStartDay(value, for: source)
        detailsController.detailsView.needsDisplay = true
        detailsController.detailsView.needsLayout = true
    }

    private func changePaymentCurrency(_ currency: CurrencyCode, source: QuotaViewOption) {
        guard source != .all else { return }
        let oldCurrency = AppSettings.paymentCurrency(for: source)
        guard oldCurrency != currency else { return }
        AppSettings.setMonthlyPlanCost(convertCurrency(AppSettings.monthlyPlanCost(for: source), from: oldCurrency, to: currency), for: source)
        AppSettings.setPaymentCurrency(currency, for: source)
        detailsController.detailsView.needsDisplay = true
        detailsController.detailsView.needsLayout = true
        dashboardController.dashboardView.update(latestState)
    }

    private func changeDisplayCurrency(_ currency: CurrencyCode, source: QuotaViewOption) {
        if source == .all {
            for option in QuotaViewOption.allCases {
                AppSettings.setDisplayCurrency(currency, for: option)
            }
        } else {
            AppSettings.setDisplayCurrency(currency, for: source)
        }
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

    private func changeStatusBarMetric(slot: StatusBarMetricSlot, metric: StatusBarMetric?) {
        switch slot {
        case .first:
            guard let metric else { return }
            AppSettings.statusBarPrimaryMetric = metric
        case .second:
            AppSettings.statusBarSecondaryMetric = metric
        }
        detailsController.detailsView.needsDisplay = true
        updateStatusTitle(report: latestState.report, limits: liveLimits, quota: selectedQuota)
    }

    private func changeQuotaDisplayStyle(_ style: QuotaDisplayStyle) {
        QuotaDisplayStyle.current = style
        detailsController.detailsView.needsDisplay = true
        dashboardController.dashboardView.needsLayout = true
        dashboardController.dashboardView.update(latestState)
    }

    private func changeCodexHomeRingMetric(_ metric: HomeQuotaRingMetric) {
        AppSettings.codexHomeRingMetric = metric
        detailsController.detailsView.needsDisplay = true
        detailsController.detailsView.needsLayout = true
        dashboardController.dashboardView.update(latestState)
    }

    private func changeClaudeHomeRingMetric(_ metric: HomeQuotaRingMetric) {
        AppSettings.claudeHomeRingMetric = metric
        detailsController.detailsView.needsDisplay = true
        detailsController.detailsView.needsLayout = true
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
            QuotaWarningManager.shared.evaluate(limits: codexTrackedLiveLimits(liveLimits))
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
        reportCache.removeAll()
        activeScans.removeAll()
        DashboardReportCacheStore.write(reportCache)
        DetailsSnapshotCacheStore.remove()
        detailsController.detailsView.needsDisplay = true
        refresh(forceLive: false)
    }

    private func reloadOfficialAPISourcesFromSettings() {
        liveLimits = []
        accountUsage = nil
        resetCredits = nil
        LiveRateLimitCacheStore.remove()
        latestState.liveLimits = []
        latestState.accountUsage = nil
        latestState.profileReport = nil
        latestState.resetCredits = nil
        detailsController.detailsView.needsDisplay = true
        detailsController.detailsView.needsLayout = true
        refresh(forceLive: true)
    }

    private func changeClaudeActiveQuotaRefresh(_ value: Bool) {
        AppSettings.claudeActiveQuotaRefreshEnabled = value
        detailsController.detailsView.needsDisplay = true
        detailsController.detailsView.needsLayout = true
        if value {
            refreshLiveLimits(allowClaudeActiveRefresh: true)
            scheduleClaudeActiveRefreshIfNeeded()
        } else {
            claudeActiveRefreshTimer?.invalidate()
            claudeActiveRefreshTimer = nil
        }
    }

    private func openUsageDetailsWindow() {
        detailsController.detailsView.showUsagePage()
        openDetailsWindow()
    }

    private func openSettingsWindow() {
        detailsController.detailsView.showSettingsPage()
        openDetailsWindow(showLoading: false)
        if AppSettings.claudeActiveQuotaRefreshEnabled {
            refreshLiveLimits(allowClaudeActiveRefresh: true)
            scheduleClaudeActiveRefreshIfNeeded()
        }
    }

    private func scheduleClaudeActiveRefreshIfNeeded() {
        claudeActiveRefreshTimer?.invalidate()
        claudeActiveRefreshTimer = nil
        guard AppSettings.claudeActiveQuotaRefreshEnabled else { return }
        let interval = TimeInterval.random(in: 55...85)
        claudeActiveRefreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            refreshLiveLimits(allowClaudeActiveRefresh: true)
            scheduleClaudeActiveRefreshIfNeeded()
        }
    }

    private func openDetailsWindow(showLoading: Bool = true) {
        detailsLoadGeneration += 1
        let loadGeneration = detailsLoadGeneration
        let cachedSnapshot = DetailsSnapshotCacheStore.read().map(hydratedDetailsSnapshot)
        if let cachedSnapshot {
            detailsController.showCached(snapshot: cachedSnapshot)
        } else if showLoading {
            detailsController.showLoading()
        } else {
            detailsController.showContent()
        }
        if liveLimits.isEmpty {
            refreshLiveLimits()
        }
        let limits = liveLimits
        let currentServiceStatus = serviceStatus
        let currentAccountUsage = accountUsage
        let currentResetCredits = resetCredits
        let updateProgress: (Double, L10nKey) -> Void = { [weak self] fraction, messageKey in
            DispatchQueue.main.async {
                guard let self, self.detailsLoadGeneration == loadGeneration else { return }
                self.detailsController.updateLoadingProgress(DetailsLoadingProgress(fraction: fraction, messageKey: messageKey))
            }
        }
        scanQueue.async {
            let snapshot = self.buildDetailsSnapshot(
                limits: limits,
                serviceStatus: currentServiceStatus,
                currentAccountUsage: currentAccountUsage,
                currentResetCredits: currentResetCredits,
                updateProgress: updateProgress
            )
            DetailsSnapshotCacheStore.write(snapshot)
            DispatchQueue.main.async {
                guard self.detailsLoadGeneration == loadGeneration else { return }
                if let accountUsage = snapshot.accountUsage {
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
                if let resetCredits = snapshot.resetCredits {
                    self.resetCredits = resetCredits
                    self.latestState.resetCredits = resetCredits
                    self.dashboardController.dashboardView.update(self.latestState)
                }
                self.detailsController.update(snapshot: snapshot)
            }
        }
    }

    private func prewarmDetailsSnapshot() {
        guard !detailsSnapshotPrewarmInFlight,
              detailsController.window?.isVisible != true,
              !DetailsSnapshotCacheStore.isFresh(maxAge: 10 * 60) else { return }
        detailsSnapshotPrewarmInFlight = true
        let limits = liveLimits
        let currentServiceStatus = serviceStatus
        let currentAccountUsage = accountUsage
        let currentResetCredits = resetCredits
        scanQueue.async {
            let snapshot = self.buildDetailsSnapshot(
                limits: limits,
                serviceStatus: currentServiceStatus,
                currentAccountUsage: currentAccountUsage,
                currentResetCredits: currentResetCredits,
                updateProgress: nil
            )
            DetailsSnapshotCacheStore.write(snapshot)
            DispatchQueue.main.async {
                self.detailsSnapshotPrewarmInFlight = false
                if let accountUsage = snapshot.accountUsage {
                    self.accountUsage = accountUsage
                } else if !AppSettings.profileAPITotalsEnabled {
                    self.accountUsage = nil
                }
                if let resetCredits = snapshot.resetCredits {
                    self.resetCredits = resetCredits
                    self.latestState.resetCredits = resetCredits
                }
            }
        }
    }

    private func hydratedDetailsSnapshot(_ snapshot: DetailsSnapshot) -> DetailsSnapshot {
        var hydrated = snapshot
        if !liveLimits.isEmpty {
            hydrated.liveLimits = liveLimits
            hydrated.costReferenceReport = liveCostReferenceReport(limits: liveLimits) ?? hydrated.costReferenceReport
        }
        if let serviceStatus {
            hydrated.serviceStatus = serviceStatus
        }
        if let resetCredits {
            hydrated.resetCredits = resetCredits
        }
        if AppSettings.profileAPITotalsEnabled {
            if let accountUsage {
                hydrated.accountUsage = accountUsage
            }
        } else {
            hydrated.accountUsage = nil
        }
        return hydrated
    }

    private func buildDetailsSnapshot(
        limits: [LiveRateLimit],
        serviceStatus: CodexServiceStatusSnapshot?,
        currentAccountUsage: AccountUsageSnapshot?,
        currentResetCredits: RateLimitResetCreditsSnapshot?,
        updateProgress: ((Double, L10nKey) -> Void)?
    ) -> DetailsSnapshot {
        updateProgress?(0.12, .loadingCodexUsage)
        let codex = scanner.scan(days: 365)
        updateProgress?(0.28, .loadingClaudeUsage)
        let claude = claudeScanner.scan(days: 365)
        updateProgress?(0.44, .loadingAllUsage)
        let all = mergedTokenReport([codex, claude])
        updateProgress?(0.62, .loadingRepoInsights)
        let codexRepoInsightReports = scanner.scanRepoInsights(windows: [7, 30, 90])
        let claudeRepoInsightReports = claudeScanner.scanRepoInsights(windows: [7, 30, 90])
        let repoInsightReports = Dictionary(uniqueKeysWithValues: [7, 30, 90].map { days in
            let report = mergedRepoInsightsReport(
                [
                    codexRepoInsightReports[days] ?? RepoInsightsReport(rows: [], scannedAt: Date(), windowDays: days),
                    claudeRepoInsightReports[days] ?? RepoInsightsReport(rows: [], scannedAt: Date(), windowDays: days)
                ],
                windowDays: days
            )
            return (days, report)
        })
        let repoInsights = repoInsightReports[90] ?? RepoInsightsReport(rows: [], scannedAt: Date(), windowDays: 90)
        let codexRepoInsights = codexRepoInsightReports[90] ?? RepoInsightsReport(rows: [], scannedAt: Date(), windowDays: 90)
        let claudeRepoInsights = claudeRepoInsightReports[90] ?? RepoInsightsReport(rows: [], scannedAt: Date(), windowDays: 90)
        updateProgress?(0.82, .loadingProfileTotals)
        let costReferenceReport = liveCostReferenceReport(limits: limits)
        let accountUsage = readAccountUsageIfNeeded(fallback: currentAccountUsage)
        let resetCredits = currentResetCredits ?? resetCreditsReader.read(timeout: 8)
        updateProgress?(0.94, .loadingFinalizing)
        MachineUsageReportStore.shared.record(
            localCodexReport: codex,
            accountUsage: accountUsage,
            liveLimits: limits
        )
        return DetailsSnapshot(
            all: all,
            codex: codex,
            claude: claude,
            repoInsights: repoInsights,
            repoInsightReports: repoInsightReports,
            codexRepoInsights: codexRepoInsights,
            codexRepoInsightReports: codexRepoInsightReports,
            claudeRepoInsights: claudeRepoInsights,
            claudeRepoInsightReports: claudeRepoInsightReports,
            liveLimits: limits,
            serviceStatus: serviceStatus,
            costReferenceReport: costReferenceReport,
            accountUsage: accountUsage,
            resetCredits: resetCredits
        )
    }

    private func summaryText(state: DashboardState) -> String {
        let report = state.report
        var lines = [
            "AI Token Meter - \(state.selectedWindow.title)",
            "Scanned: \(localFormatter.string(from: report.scannedAt)) \(appTimeZone().identifier)",
            "Next refresh: \(localFormatter.string(from: state.nextRefreshAt)) \(appTimeZone().identifier)",
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
        let costSource = state.selectedQuota
        if let limit = selectedLimit(from: state.liveLimits, quota: state.selectedQuota),
           let estimate = planCostEstimate(
            report: report,
            selectedDay: nil,
            limit: limit,
            monthlyCost: AppSettings.monthlyPlanCost(for: costSource),
            paymentStartDay: AppSettings.paymentStartDay(for: costSource)
           ) {
            lines.append("Payment currency: \(AppSettings.paymentCurrency(for: costSource).rawValue)")
            lines.append("Display currency: \(AppSettings.displayCurrency(for: costSource).rawValue)")
            lines.append("Plan cost: \(paymentMoney(estimate.monthlyCost, source: costSource))/month")
            lines.append("Today value: \(displayMoney(estimate.todayValue, source: costSource))")
            lines.append("Weekly used value: \(displayMoney(estimate.weeklyUsedValue, source: costSource))")
            lines.append("Weekly unused value: \(displayMoney(estimate.weeklyUnusedValue, source: costSource))")
        }
        lines.append("By day:")
        for day in report.byDay {
            lines.append("\(day.day)\t\(day.usage.total)\t\(day.usage.input)\t\(day.usage.cachedInput)\t\(day.usage.output)\tturns=\(day.turns)")
        }
        return lines.joined(separator: "\n")
    }
}
