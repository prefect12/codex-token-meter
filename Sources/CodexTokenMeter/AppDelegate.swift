import Cocoa
import Foundation
import ServiceManagement
import UserNotifications

// MARK: - App Lifecycle

private struct LiveCostReferenceCache {
    let cycleStart: Date
    let cachedAt: Date
    let report: TokenReport
}

private struct ModelRangeCacheKey: Hashable {
    let startDay: Date
    let endDay: Date
}

private struct ModelRangeReports {
    let codex: TokenReport
    let claude: TokenReport
    let api: TokenReport
    let all: TokenReport
    let cachedAt: Date
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let dashboardController = DashboardViewController()
    private let detailsController = UsageDetailsWindowController()
    private let codexModelRoutingProtectionController =
        CodexModelRoutingProtectionController()
    private let claudeModelRoutingProtectionController =
        ClaudeModelRoutingProtectionController()
    private var scanner = CodexTokenScanner(rootURLs: AppSettings.logFolderURLs)
    private var claudeScanner = ClaudeTokenScanner(rootURLs: AppSettings.claudeLogFolderURLs)
    private let rateLimitReader = LiveRateLimitReader()
    private let accountUsageReader = AccountUsageReader()
    private let resetCreditsReader = RateLimitResetCreditsReader()
    private let serviceStatusReader = CodexServiceStatusReader()
    private let claudeServiceStatusReader = CodexServiceStatusReader.claude()
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
    private var claudeServiceStatus: CodexServiceStatusSnapshot?
    private var refreshTimer: Timer?
    private var liveRefreshTimer: Timer?
    private var claudeQuotaTimer: Timer?
    private var claudeQuotaRefreshInFlight = false
    private var claudeCaptureWatcher: ClaudeCaptureFileWatcher?
    private var activeScans: Set<ReportCacheKey> = []
    private var liveRefreshInFlight = false
    private var detailsSnapshotPrewarmInFlight = false
    private var statusSpinnerTimer: Timer?
    private var statusSpinnerFrame = 0
    private var statusIsLoading = false
    private var detailsLoadGeneration = 0
    private var modelRangeLoadGeneration = 0
    private var modelRangeRefreshWorkItem: DispatchWorkItem?
    private var modelRangeReportCache: [ModelRangeCacheKey: ModelRangeReports] = [:]
    private let refreshInterval: TimeInterval = 300
    private let popoverRefreshMaxAge: TimeInterval = 60
    private let liveRefreshInterval: TimeInterval = 60
    /// Claude quota runs on its own cadence because its source is a cheap
    /// read-only endpoint, unlike the Codex live refresh it used to ride along
    /// with. While the dashboard is open it tracks close to real time; closed,
    /// it only needs to keep the menu bar roughly current.
    private let claudeQuotaVisibleInterval: TimeInterval = 15
    private let claudeQuotaIdleInterval: TimeInterval = 120
    private let detailsSnapshotPrewarmInterval: TimeInterval = 30 * 60
    private let liveCostReferenceCacheTTL: TimeInterval = 5 * 60
    private let modelRangeReportCacheTTL: TimeInterval = 5 * 60
    private let liveRefreshFailureIntervals: [TimeInterval] = [60, 300, 900]
    private var liveRefreshFailureCount = 0
    private let liveCostReferenceCacheLock = NSLock()
    private var liveCostReferenceCache: LiveCostReferenceCache?
    private let statusIconSize = NSSize(width: 14, height: 14)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ClaudeOAuthUsageRefresher.disableKeychainInteraction()
        localFormatter.locale = Locale(identifier: "en_US_POSIX")
        localFormatter.timeZone = appTimeZone()
        localFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        selectedWindow = .day
        OpenRouterPricingCatalog.shared.refreshIfNeeded()
        if let rawQuota = UserDefaults.standard.string(forKey: "selectedQuotaView"),
           let quota = QuotaViewOption.option(from: rawQuota),
           QuotaViewOption.visibleSelectorOptions.contains(quota) {
            selectedQuota = quota
        } else {
            selectedQuota = QuotaViewOption.visibleDefault
        }
        liveLimits = LiveRateLimitCacheStore.read()

        NSApp.applicationIconImage = NSImage(named: "LogoHeader")
        popover.contentViewController = dashboardController
        resizeDashboardPopover(to: DashboardView.idealSize)
        popover.behavior = .transient
        popover.delegate = self
        configureStatusButton()

        dashboardController.dashboardView.onWindowChanged = { [weak self] option in self?.selectWindow(option) }
        dashboardController.dashboardView.onQuotaChanged = { [weak self] option in self?.selectQuota(option) }
        dashboardController.dashboardView.onPreferredSizeChanged = { [weak self] size in
            self?.resizeDashboardPopover(to: size)
        }
        dashboardController.dashboardView.onRefresh = { [weak self] in
            self?.refresh(forceLive: false)
            self?.refreshLiveLimits()
            self?.refreshClaudeQuota()
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
        detailsController.detailsView.onClaudeThirdRingMetricChanged = { [weak self] metric in
            self?.changeClaudeThirdRingMetric(metric)
        }
        detailsController.detailsView.onShowCombinedFableChanged = { [weak self] isOn in
            self?.changeShowCombinedFable(isOn)
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
        detailsController.detailsView.onQuotaWarningsChanged = { [weak self] isOn in self?.changeQuotaWarnings(isOn) }
        detailsController.detailsView.onProfileAPITotalsChanged = { [weak self] isOn in self?.changeProfileAPITotals(isOn) }
        detailsController.detailsView.onVisibleUsageSourcesChanged = { [weak self] sources in
            self?.changeVisibleUsageSources(sources)
        }
        detailsController.detailsView.onExportMachineUsageReport = { [weak self] in self?.exportMachineUsageReport() }
        detailsController.detailsView.onStorageScanRequested = { [weak self] in self?.refreshStorageSnapshot() }
        detailsController.detailsView.onModelDateRangeChanged = { [weak self] start, end in
            self?.refreshModelDateRange(from: start, to: end)
        }
        detailsController.detailsView.onReasoningDateRangeChanged = { [weak self] start, end in
            self?.refreshReasoningDateRange(from: start, to: end)
        }
        applyLanguage()
        QuotaWarningManager.shared.requestAuthorization()

        reportCache = DashboardReportCacheStore.read()
        refresh(forceLive: false, allowProfileAPI: false)
        if liveLimits.isEmpty {
            refreshLiveLimits()
        } else {
            scheduleNextLiveRefresh(succeeded: true)
        }
        let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh(forceLive: false)
        }
        refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        refreshClaudeQuota()
        startClaudeCaptureWatcher()
        if CommandLine.arguments.contains("--open-details=models") {
            detailsController.detailsView.showSection(.models)
            DispatchQueue.main.async { [weak self] in
                self?.openDetailsWindow()
            }
        } else if CommandLine.arguments.contains("--open-details=reasoning") {
            detailsController.detailsView.showSection(.reasoning, insightWindowDays: 90, source: .codex)
            DispatchQueue.main.async { [weak self] in
                self?.openDetailsWindow()
            }
        } else if CommandLine.arguments.contains("--open-details=ranking") || CommandLine.arguments.contains("--open-details=combination-ranking") {
            detailsController.detailsView.showSection(.combinationRanking, insightWindowDays: 90)
            DispatchQueue.main.async { [weak self] in
                self?.openDetailsWindow()
            }
        }
        configureClaudeKeychainAccess()
    }

    /// Reuses an existing persistent grant without ever opening SecurityAgent.
    /// New or revoked grants must be requested explicitly by the user through
    /// `--grant-claude-keychain`; automatic app lifecycle work stays silent.
    private func configureClaudeKeychainAccess() {
        let refresher = ClaudeOAuthUsageRefresher.shared
        guard refresher.needsInitialKeychainAccess else {
            AppSettings.claudeKeychainAccessRequested = true
            return
        }
        let authorized = refresher.hasPersistentKeychainAccess
        AppSettings.claudeKeychainAccessEnabled = authorized
        if authorized {
            AppSettings.claudeKeychainAccessRequested = true
        }
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

    private func refreshModelDateRange(from start: Date, to end: Date) {
        modelRangeRefreshWorkItem?.cancel()
        modelRangeLoadGeneration += 1
        let generation = modelRangeLoadGeneration
        rememberVisibleModelRange()
        if let cached = cachedModelRangeReports(from: start, to: end) {
            applyModelRangeReports(cached, from: start, to: end, generation: generation)
            if Date().timeIntervalSince(cached.cachedAt) <= modelRangeReportCacheTTL {
                return
            }
        }
        let presetDayCount = modelPresetDayCount(from: start, to: end)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.scanQueue.async {
                let codex: TokenReport
                let claude: TokenReport
                if let presetDayCount {
                    codex = self.scanner.scan(days: presetDayCount, partition: .codex)
                    claude = self.claudeScanner.scan(days: presetDayCount)
                } else {
                    codex = self.scanner.scan(from: start, to: end, partition: .codex)
                    claude = self.claudeScanner.scan(from: start, to: end)
                }
                let api = mergedTokenReport([
                    presetDayCount.map { self.scanner.scan(days: $0, partition: .api) }
                        ?? self.scanner.scan(from: start, to: end, partition: .api),
                    presetDayCount.map { ExternalAPIUsageStore.readReport(days: $0) }
                        ?? ExternalAPIUsageStore.readReport(from: start, to: end),
                    presetDayCount.map { OpenCodeTokenScanner.shared.scan(days: $0) }
                        ?? OpenCodeTokenScanner.shared.scan(from: start, to: end)
                ])
                let all = mergedTokenReport([codex, claude, api])
                DispatchQueue.main.async {
                    let reports = ModelRangeReports(
                        codex: codex,
                        claude: claude,
                        api: api,
                        all: all,
                        cachedAt: Date()
                    )
                    self.modelRangeReportCache[self.modelRangeCacheKey(from: start, to: end)] = reports
                    self.applyModelRangeReports(reports, from: start, to: end, generation: generation)
                }
            }
        }
        modelRangeRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func refreshReasoningDateRange(from start: Date, to end: Date) {
        let calendar = appCalendar()
        let rangeStart = calendar.startOfDay(for: min(start, end))
        let selectedEnd = calendar.startOfDay(for: max(start, end))
        let rangeEnd = min(
            Date(),
            calendar.date(byAdding: .day, value: 1, to: selectedEnd)?.addingTimeInterval(-0.001) ?? selectedEnd
        )
        scanQueue.async { [weak self] in
            guard let self else { return }
            let codexInsights = self.scanner.scanRepoInsights(from: rangeStart, to: rangeEnd, partition: .codex)
            var apiInsights = self.scanner.scanRepoInsights(from: rangeStart, to: rangeEnd, partition: .api)
            apiInsights.reasoning = mergedReasoningInsightsReports([
                apiInsights.reasoning,
                OpenCodeTokenScanner.shared.scanReasoningInsights(from: rangeStart, to: rangeEnd)
            ])
            let claude = self.claudeScanner.scan(from: rangeStart, to: rangeEnd)
            DispatchQueue.main.async {
                guard var snapshot = self.detailsController.detailsView.snapshot,
                      self.detailsController.detailsView.selectedInsightWindowDays == 0 else {
                    self.detailsController.detailsView.isReasoningDateRangeLoading = false
                    return
                }
                snapshot.codexRepoInsightReports[0] = codexInsights
                snapshot.apiRepoInsightReports[0] = apiInsights
                snapshot.reasoningClaude = claude
                snapshot.reasoningRangeStart = rangeStart
                snapshot.reasoningRangeEnd = rangeEnd
                self.detailsController.detailsView.isReasoningDateRangeLoading = false
                self.detailsController.update(snapshot: snapshot)
            }
        }
    }

    private func modelRangeCacheKey(from start: Date, to end: Date) -> ModelRangeCacheKey {
        let calendar = appCalendar()
        return ModelRangeCacheKey(
            startDay: calendar.startOfDay(for: min(start, end)),
            endDay: calendar.startOfDay(for: max(start, end))
        )
    }

    private func modelPresetDayCount(from start: Date, to end: Date) -> Int? {
        let calendar = appCalendar()
        let key = modelRangeCacheKey(from: start, to: end)
        let today = calendar.startOfDay(for: Date())
        guard key.endDay == today else { return nil }
        let dayCount = (calendar.dateComponents([.day], from: key.startDay, to: key.endDay).day ?? -1) + 1
        return [7, 30, 90].contains(dayCount) ? dayCount : nil
    }

    private func cachedModelRangeReports(from start: Date, to end: Date) -> ModelRangeReports? {
        let key = modelRangeCacheKey(from: start, to: end)
        if let cached = modelRangeReportCache[key] {
            return cached
        }

        guard let dayCount = modelPresetDayCount(from: start, to: end) else { return nil }
        let window: WindowOption
        switch dayCount {
        case 7: window = .week
        case 30: window = .month
        default: return nil
        }
        guard let codex = reportCache[ReportCacheKey(window: window, quota: .codex)],
              let claude = reportCache[ReportCacheKey(window: window, quota: .claude)],
              let all = reportCache[ReportCacheKey(window: window, quota: .all)] else {
            return nil
        }
        let cachedAt = min(codex.scannedAt, min(claude.scannedAt, all.scannedAt))
        let api = reportCache[ReportCacheKey(window: window, quota: .api)]
            ?? mergedTokenReport([
                scanner.scan(window: window, partition: .api),
                ExternalAPIUsageStore.readReport(window: window),
                OpenCodeTokenScanner.shared.scan(window: window)
            ])
        let reports = ModelRangeReports(codex: codex, claude: claude, api: api, all: all, cachedAt: cachedAt)
        modelRangeReportCache[key] = reports
        return reports
    }

    private func rememberVisibleModelRange() {
        guard let snapshot = detailsController.detailsView.snapshot,
              let start = snapshot.modelRangeStart,
              let end = snapshot.modelRangeEnd,
              let codex = snapshot.modelCodex,
              let claude = snapshot.modelClaude,
              let all = snapshot.modelAll else {
            return
        }
        let key = modelRangeCacheKey(from: start, to: end)
        guard modelRangeReportCache[key] == nil else { return }
        modelRangeReportCache[key] = ModelRangeReports(
            codex: codex,
            claude: claude,
            api: snapshot.modelAPI ?? snapshot.api,
            all: all,
            cachedAt: Date()
        )
    }

    private func applyModelRangeReports(
        _ reports: ModelRangeReports,
        from start: Date,
        to end: Date,
        generation: Int
    ) {
        guard generation == modelRangeLoadGeneration,
              var snapshot = detailsController.detailsView.snapshot else {
            if generation == modelRangeLoadGeneration {
                detailsController.detailsView.isModelDateRangeLoading = false
            }
            return
        }
        snapshot.modelCodex = reports.codex
        snapshot.modelClaude = reports.claude
        snapshot.modelAPI = reports.api
        snapshot.modelAll = reports.all
        snapshot.modelRangeStart = start
        snapshot.modelRangeEnd = end
        detailsController.detailsView.isModelDateRangeLoading = false
        detailsController.update(snapshot: snapshot)
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
            // Drop back to the idle cadence now that nobody is watching.
            scheduleClaudeQuotaRefresh()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            if Date().timeIntervalSince(latestState.report.scannedAt) >= popoverRefreshMaxAge {
                refresh(forceLive: false)
            }
            refreshLiveLimits()
            refreshClaudeQuota()
        }
    }

    /// `.transient` popovers also close on an outside click, which never routes
    /// through `togglePopover`.
    func popoverDidClose(_ notification: Notification) {
        scheduleClaudeQuotaRefresh()
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
        guard QuotaViewOption.visibleSelectorOptions.contains(option) else { return }
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
                apiReport: platformReports.api,
                profileReport: profileReport(window: selectedWindow, quota: selectedQuota, accountUsage: accountUsage, localReport: cached),
                accountUsage: accountUsage,
                costReferenceReport: costReferenceReport(quota: selectedQuota, fallback: cached),
                liveLimits: liveLimits,
                resetCredits: resetCredits,
                serviceStatus: serviceStatus,
                claudeServiceStatus: claudeServiceStatus,
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
                apiReport: platformReports.api,
                profileReport: profileReport(window: selectedWindow, quota: selectedQuota, accountUsage: accountUsage, localReport: nil),
                accountUsage: accountUsage,
                costReferenceReport: costReferenceReport(quota: selectedQuota, fallback: nil),
                liveLimits: liveLimits,
                resetCredits: resetCredits,
                serviceStatus: serviceStatus,
                claudeServiceStatus: claudeServiceStatus,
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

    private func cachedPlatformReports(window: WindowOption, quota: QuotaViewOption) -> (codex: TokenReport?, claude: TokenReport?, api: TokenReport?) {
        guard quota == .all else { return (nil, nil, nil) }
        let enabled = Set(QuotaViewOption.visiblePlatformCases)
        return (
            enabled.contains(.codex) ? reportCache[ReportCacheKey(window: window, quota: .codex)] : nil,
            enabled.contains(.claude) ? reportCache[ReportCacheKey(window: window, quota: .claude)] : nil,
            enabled.contains(.api) ? reportCache[ReportCacheKey(window: window, quota: .api)] : nil
        )
    }

    private func refresh(forceLive: Bool, allowProfileAPI: Bool = true) {
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
            apiReport: platformReports.api,
            profileReport: profileReport(window: window, quota: quota, accountUsage: accountUsage, localReport: reportCache[key]),
            accountUsage: accountUsage,
            costReferenceReport: costReferenceReport(quota: quota, fallback: reportCache[key]),
            liveLimits: liveLimits,
            resetCredits: resetCredits,
            serviceStatus: serviceStatus,
            claudeServiceStatus: claudeServiceStatus,
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
            let apiReport: TokenReport?
            let report: TokenReport
            if quota == .all {
                let enabled = Set(QuotaViewOption.visiblePlatformCases)
                let codex = enabled.contains(.codex) ? self.scanner.scan(window: window, partition: .codex) : nil
                let claude = enabled.contains(.claude) ? self.claudeScanner.scan(window: window) : nil
                let api = enabled.contains(.api) ? mergedTokenReport([
                    self.scanner.scan(window: window, partition: .api),
                    ExternalAPIUsageStore.readReport(window: window),
                    OpenCodeTokenScanner.shared.scan(window: window)
                ]) : nil
                codexReport = codex
                claudeReport = claude
                apiReport = api
                report = mergedTokenReport([codex, claude, api].compactMap { $0 })
            } else {
                codexReport = nil
                claudeReport = nil
                apiReport = quota == .api ? self.scanReport(window: window, source: .api) : nil
                report = apiReport ?? self.scanReport(window: window, source: quota)
            }
            let accountUsage = quota.usesCodexProfileAPI && allowProfileAPI
                ? self.readAccountUsageIfNeeded(fallback: currentAccountUsage)
                : currentAccountUsage
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
                if let apiReport {
                    self.reportCache[ReportCacheKey(window: window, quota: .api)] = apiReport
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
                        apiReport: apiReport ?? cachedPlatforms.api,
                        profileReport: self.profileReport(window: window, quota: quota, accountUsage: self.accountUsage, localReport: report),
                        accountUsage: self.accountUsage,
                        costReferenceReport: self.costReferenceReport(quota: quota, fallback: report),
                        liveLimits: effectiveLimits,
                        resetCredits: effectiveResetCredits,
                        serviceStatus: self.serviceStatus,
                        claudeServiceStatus: self.claudeServiceStatus,
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
                    self.latestState.claudeServiceStatus = self.claudeServiceStatus
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

    private func refreshLiveLimits() {
        guard !liveRefreshInFlight else { return }
        liveRefreshTimer?.invalidate()
        liveRefreshTimer = nil
        liveRefreshInFlight = true
        let currentLimits = liveLimits
        let currentResetCredits = resetCredits
        liveQueue.async {
            let claudeStore = ClaudeStatuslineStore()
            _ = ClaudeOAuthUsageRefresher.shared.refreshIfNeeded(store: claudeStore)
            let freshLimits = combinedLiveLimits(codexReader: self.rateLimitReader, claudeStore: claudeStore)
            let limits = self.mergedLiveLimits(fresh: freshLimits, fallback: currentLimits)
            let freshResetCredits = self.resetCreditsReader.read()
            let effectiveResetCredits = freshResetCredits ?? currentResetCredits
            let serviceStatus = self.serviceStatusReader.read()
            let claudeServiceStatus = self.claudeServiceStatusReader.read()
            let freshCodexLimits = codexTrackedLiveLimits(freshLimits)
            let codexRefreshSucceeded = !freshCodexLimits.isEmpty
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
                self.scheduleNextLiveRefresh(succeeded: codexRefreshSucceeded)
                if let serviceStatus {
                    self.serviceStatus = serviceStatus
                    self.latestState.serviceStatus = serviceStatus
                    self.detailsController.updateServiceStatus(serviceStatus)
                }
                if let claudeServiceStatus {
                    self.claudeServiceStatus = claudeServiceStatus
                    self.latestState.claudeServiceStatus = claudeServiceStatus
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

    /// Pulls Claude quota on its own schedule and merges just those windows into
    /// the dashboard. Deliberately lighter than `refreshLiveLimits`: no Codex
    /// read, no service-status requests, so it is cheap enough to run often.
    private func refreshClaudeQuota() {
        guard !claudeQuotaRefreshInFlight else { return }
        claudeQuotaRefreshInFlight = true
        liveQueue.async { [weak self] in
            guard let self else { return }
            let store = ClaudeStatuslineStore()
            _ = ClaudeOAuthUsageRefresher.shared.refreshIfNeeded(store: store)
            let snapshot = store.read()
            let claudeLimits = [snapshot?.liveRateLimit, snapshot?.fableLiveRateLimit].compactMap { $0 }
            DispatchQueue.main.async {
                self.claudeQuotaRefreshInFlight = false
                self.scheduleClaudeQuotaRefresh()
                self.applyClaudeLimits(claudeLimits)
            }
        }
    }

    /// Replaces only the Claude-owned windows so a Claude update never drops or
    /// resurrects Codex limits fetched on the other cadence.
    private func applyClaudeLimits(_ claudeLimits: [LiveRateLimit]) {
        guard !claudeLimits.isEmpty else { return }
        let claudeIDs = Set(claudeLimits.map(\.id))
        var merged = liveLimits.filter { !claudeIDs.contains($0.id) }
        merged.append(contentsOf: claudeLimits)
        merged.sort { $0.id < $1.id }
        guard merged != liveLimits else { return }
        liveLimits = merged
        latestState.liveLimits = merged
        latestState.error = nil
        LiveRateLimitCacheStore.write(merged)
        updateStatusTitle(report: latestState.report, limits: merged, quota: latestState.selectedQuota)
        dashboardController.dashboardView.update(latestState)
        detailsController.updateLiveLimits(
            merged,
            costReferenceReport: liveCostReferenceReport(limits: merged),
            serviceStatus: serviceStatus
        )
    }

    private func scheduleClaudeQuotaRefresh() {
        claudeQuotaTimer?.invalidate()
        let delay = popover.isShown ? claudeQuotaVisibleInterval : claudeQuotaIdleInterval
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            self?.refreshClaudeQuota()
        }
        claudeQuotaTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// A statusline write from any Claude Code session is a free, immediate
    /// signal that the numbers moved; reflect it without waiting for a poll.
    private func startClaudeCaptureWatcher() {
        let watcher = ClaudeCaptureFileWatcher { [weak self] in
            guard let self else { return }
            let snapshot = ClaudeStatuslineStore().read()
            self.applyClaudeLimits(
                [snapshot?.liveRateLimit, snapshot?.fableLiveRateLimit].compactMap { $0 }
            )
        }
        claudeCaptureWatcher = watcher
        watcher.start()
    }

    private func scheduleNextLiveRefresh(succeeded: Bool) {
        liveRefreshTimer?.invalidate()
        if succeeded {
            liveRefreshFailureCount = 0
        } else {
            liveRefreshFailureCount += 1
        }
        let delay: TimeInterval
        if succeeded {
            delay = liveRefreshInterval
        } else {
            let index = min(max(0, liveRefreshFailureCount - 1), liveRefreshFailureIntervals.count - 1)
            delay = liveRefreshFailureIntervals[index]
        }
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            self?.refreshLiveLimits()
        }
        liveRefreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
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
                        apiReport: platformReports.api,
                        profileReport: self.profileReport(window: window, quota: quota, accountUsage: self.accountUsage, localReport: report),
                        accountUsage: self.accountUsage,
                        costReferenceReport: self.costReferenceReport(quota: quota, fallback: report),
                        liveLimits: self.liveLimits,
                        resetCredits: self.resetCredits,
                        serviceStatus: self.serviceStatus,
                        claudeServiceStatus: self.claudeServiceStatus,
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
                    } else if quota == .api {
                        self.latestState.apiReport = report
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
            let enabled = Set(QuotaViewOption.visiblePlatformCases)
            var reports: [TokenReport] = []
            if enabled.contains(.codex) { reports.append(scanner.scan(window: window, partition: .codex)) }
            if enabled.contains(.claude) { reports.append(claudeScanner.scan(window: window)) }
            if enabled.contains(.api) {
                reports.append(mergedTokenReport([
                    scanner.scan(window: window, partition: .api),
                    ExternalAPIUsageStore.readReport(window: window),
                    OpenCodeTokenScanner.shared.scan(window: window)
                ]))
            }
            return mergedTokenReport(reports)
        case .codex:
            return scanner.scan(window: window, partition: .codex)
        case .claude:
            return claudeScanner.scan(window: window)
        case .api:
            return mergedTokenReport([
                scanner.scan(window: window, partition: .api),
                ExternalAPIUsageStore.readReport(window: window),
                OpenCodeTokenScanner.shared.scan(window: window)
            ])
        }
    }

    private func scanReport(days: Int, source: QuotaViewOption) -> TokenReport {
        switch source {
        case .all:
            let enabled = Set(QuotaViewOption.visiblePlatformCases)
            var reports: [TokenReport] = []
            if enabled.contains(.codex) { reports.append(scanner.scan(days: days, partition: .codex)) }
            if enabled.contains(.claude) { reports.append(claudeScanner.scan(days: days)) }
            if enabled.contains(.api) {
                reports.append(mergedTokenReport([
                    scanner.scan(days: days, partition: .api),
                    ExternalAPIUsageStore.readReport(days: days),
                    OpenCodeTokenScanner.shared.scan(days: days)
                ]))
            }
            return mergedTokenReport(reports)
        case .codex:
            return scanner.scan(days: days, partition: .codex)
        case .claude:
            return claudeScanner.scan(days: days)
        case .api:
            return mergedTokenReport([
                scanner.scan(days: days, partition: .api),
                ExternalAPIUsageStore.readReport(days: days),
                OpenCodeTokenScanner.shared.scan(days: days)
            ])
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
        liveCostReferenceCacheLock.lock()
        if let cached = liveCostReferenceCache,
           abs(cached.cycleStart.timeIntervalSince(start)) < 1,
           now.timeIntervalSince(cached.cachedAt) < liveCostReferenceCacheTTL {
            liveCostReferenceCacheLock.unlock()
            return cached.report
        }
        liveCostReferenceCacheLock.unlock()

        let report = scanner.scan(from: start, to: now, partition: .codex)
        liveCostReferenceCacheLock.lock()
        liveCostReferenceCache = LiveCostReferenceCache(cycleStart: start, cachedAt: now, report: report)
        liveCostReferenceCacheLock.unlock()
        return report
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
        let limit = limits.first { $0.id == metric.liveLimitID }
        let text: String?
        switch metric.quotaMetric {
        case .fiveHour:
            text = statusPercentText(limit?.primary?.remainingPercent, source: metric.source)
        case .weekly:
            text = statusPercentText(limit?.secondary?.remainingPercent, source: metric.source)
        }
        guard let text else { return nil }
        return text
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
        case .api:
            rawURL = "https://openrouter.ai/models"
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

    private func changeClaudeThirdRingMetric(_ metric: ClaudeThirdRingMetric) {
        AppSettings.claudeThirdRingMetric = metric
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

    private func changeShowCombinedFable(_ value: Bool) {
        AppSettings.showCombinedFableEnabled = value
        detailsController.detailsView.needsDisplay = true
        detailsController.detailsView.needsLayout = true
        dashboardController.dashboardView.update(latestState)
    }

    private func changeVisibleUsageSources(_ sources: Set<QuotaViewOption>) {
        AppSettings.setVisibleUsageSources(sources)
        let visibleOptions = QuotaViewOption.visibleSelectorOptions
        if !visibleOptions.contains(selectedQuota) {
            selectedQuota = QuotaViewOption.visibleDefault
            UserDefaults.standard.set(selectedQuota.rawValue, forKey: "selectedQuotaView")
        }
        reportCache = reportCache.filter { $0.key.quota != .all }
        modelRangeReportCache.removeAll()
        detailsController.detailsView.normalizeVisibleSourceSelection()
        detailsController.detailsView.needsDisplay = true
        detailsController.detailsView.needsLayout = true
        showCachedOrLoadingState()
        refresh(forceLive: false)
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
            openDetailsWindow(forceRefresh: true)
        }
    }

    private func reloadScannerFromSettings() {
        scanner = CodexTokenScanner(rootURLs: AppSettings.logFolderURLs)
        reportCache.removeAll()
        activeScans.removeAll()
        liveCostReferenceCacheLock.lock()
        liveCostReferenceCache = nil
        liveCostReferenceCacheLock.unlock()
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

    private func openUsageDetailsWindow() {
        detailsController.detailsView.showUsagePage()
        openDetailsWindow()
    }

    private func openSettingsWindow() {
        detailsController.detailsView.showSettingsPage()
        openDetailsWindow(showLoading: false)
    }

    private func openDetailsWindow(showLoading: Bool = true, forceRefresh: Bool = false) {
        detailsLoadGeneration += 1
        let loadGeneration = detailsLoadGeneration
        let cached = DetailsSnapshotCacheStore.readWithFreshness(maxAge: refreshInterval)
        let cachedSnapshot = cached.map { hydratedDetailsSnapshot($0.snapshot) }
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
        if !forceRefresh, cached?.isFresh == true {
            return
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
                var displaySnapshot = snapshot
                if let visibleSnapshot = self.detailsController.detailsView.snapshot,
                   visibleSnapshot.modelRangeStart != nil {
                    displaySnapshot.modelAll = visibleSnapshot.modelAll
                    displaySnapshot.modelCodex = visibleSnapshot.modelCodex
                    displaySnapshot.modelClaude = visibleSnapshot.modelClaude
                    displaySnapshot.modelRangeStart = visibleSnapshot.modelRangeStart
                    displaySnapshot.modelRangeEnd = visibleSnapshot.modelRangeEnd
                }
                self.detailsController.update(snapshot: displaySnapshot)
            }
        }
    }

    private func prewarmDetailsSnapshot() {
        guard !detailsSnapshotPrewarmInFlight,
              detailsController.window?.isVisible != true,
              !DetailsSnapshotCacheStore.isFresh(maxAge: detailsSnapshotPrewarmInterval) else { return }
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
            if hydrated.costReferenceReport == nil {
                hydrated.costReferenceReport = reportCache[ReportCacheKey(window: .week, quota: .codex)]
            }
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
        let codex = scanner.scan(days: 365, partition: .codex)
        updateProgress?(0.28, .loadingClaudeUsage)
        let claudeDetails = claudeScanner.scanWithRepoInsights(days: 365, insightWindows: [7, 30, 90])
        let claude = claudeDetails.report
        updateProgress?(0.44, .loadingAllUsage)
        let api = mergedTokenReport([
            scanner.scan(days: 365, partition: .api),
            ExternalAPIUsageStore.readReport(days: 365),
            OpenCodeTokenScanner.shared.scan(days: 365)
        ])
        let all = mergedTokenReport([codex, claude, api])
        let modelCodex = scanner.scan(days: 90, partition: .codex)
        let modelClaude = claudeScanner.scan(days: 90)
        let modelAPI = mergedTokenReport([
            scanner.scan(days: 90, partition: .api),
            ExternalAPIUsageStore.readReport(days: 90),
            OpenCodeTokenScanner.shared.scan(days: 90)
        ])
        let modelAll = mergedTokenReport([modelCodex, modelClaude, modelAPI])
        updateProgress?(0.62, .loadingRepoInsights)
        let codexRepoInsightReports = scanner.scanRepoInsights(windows: [7, 30, 90], partition: .codex)
        var apiRepoInsightReports = scanner.scanRepoInsights(windows: [7, 30, 90], partition: .api)
        for days in [7, 30, 90] {
            guard var report = apiRepoInsightReports[days] else { continue }
            report.reasoning = mergedReasoningInsightsReports([
                report.reasoning,
                OpenCodeTokenScanner.shared.scanReasoningInsights(days: days)
            ])
            apiRepoInsightReports[days] = report
        }
        let claudeRepoInsightReports = claudeDetails.repoInsights
        let repoInsightReports = Dictionary(uniqueKeysWithValues: [7, 30, 90].map { days in
            let report = mergedRepoInsightsReport(
                [
                    codexRepoInsightReports[days] ?? RepoInsightsReport(rows: [], scannedAt: Date(), windowDays: days),
                    claudeRepoInsightReports[days] ?? RepoInsightsReport(rows: [], scannedAt: Date(), windowDays: days),
                    apiRepoInsightReports[days] ?? RepoInsightsReport(rows: [], scannedAt: Date(), windowDays: days)
                ],
                windowDays: days
            )
            return (days, report)
        })
        let repoInsights = repoInsightReports[90] ?? RepoInsightsReport(rows: [], scannedAt: Date(), windowDays: 90)
        let codexRepoInsights = codexRepoInsightReports[90] ?? RepoInsightsReport(rows: [], scannedAt: Date(), windowDays: 90)
        let claudeRepoInsights = claudeRepoInsightReports[90] ?? RepoInsightsReport(rows: [], scannedAt: Date(), windowDays: 90)
        let apiRepoInsights = apiRepoInsightReports[90] ?? RepoInsightsReport(rows: [], scannedAt: Date(), windowDays: 90)
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
            api: api,
            modelAll: modelAll,
            modelCodex: modelCodex,
            modelClaude: modelClaude,
            modelAPI: modelAPI,
            modelRangeStart: appCalendar().startOfDay(
                for: appCalendar().date(byAdding: .day, value: -89, to: Date()) ?? Date()
            ),
            modelRangeEnd: Date(),
            repoInsights: repoInsights,
            repoInsightReports: repoInsightReports,
            codexRepoInsights: codexRepoInsights,
            codexRepoInsightReports: codexRepoInsightReports,
            claudeRepoInsights: claudeRepoInsights,
            claudeRepoInsightReports: claudeRepoInsightReports,
            apiRepoInsights: apiRepoInsights,
            apiRepoInsightReports: apiRepoInsightReports,
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
            let fiveHour = limit.primary.map { "\($0.usedPercent)%" } ?? "unavailable"
            let weekly = limit.secondary.map { "\($0.usedPercent)%" } ?? "unavailable"
            lines.append("\(limit.name): 5h \(fiveHour) used, weekly \(weekly) used")
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
