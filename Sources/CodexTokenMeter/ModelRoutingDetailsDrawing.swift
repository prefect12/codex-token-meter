import Cocoa

private let modelRoutingMixedValue = "__mixed__"
private let modelRoutingNotApplicableValue = "__not_applicable__"

enum ModelRoutingPlatform: String, CaseIterable {
    case codex
    case claude
}

private struct ModelRoutingColumns {
    let project: NSRect
    let model: NSRect
    let effort: NSRect
    let status: NSRect
}

private func modelRoutingColumns(in row: NSRect) -> ModelRoutingColumns {
    let horizontalPadding: CGFloat = row.width >= 900 ? 20 : 14
    let gap: CGFloat = row.width >= 900 ? 16 : 10
    let statusWidth: CGFloat = row.width >= 900 ? 126 : 88
    let effortWidth: CGFloat = row.width >= 900 ? 190 : 128
    let modelWidth: CGFloat = row.width >= 900 ? 264 : 176
    let status = NSRect(
        x: row.maxX - horizontalPadding - statusWidth,
        y: row.minY,
        width: statusWidth,
        height: row.height
    )
    let effort = NSRect(
        x: status.minX - gap - effortWidth,
        y: row.minY,
        width: effortWidth,
        height: row.height
    )
    let model = NSRect(
        x: effort.minX - gap - modelWidth,
        y: row.minY,
        width: modelWidth,
        height: row.height
    )
    let project = NSRect(
        x: row.minX + horizontalPadding,
        y: row.minY,
        width: max(96, model.minX - gap - row.minX - horizontalPadding),
        height: row.height
    )
    return ModelRoutingColumns(project: project, model: model, effort: effort, status: status)
}

private func modelRoutingSearchRect(in toolbar: NSRect) -> NSRect {
    NSRect(
        x: toolbar.minX,
        y: toolbar.minY + 3,
        width: min(260, max(170, toolbar.width * 0.28)),
        height: 28
    )
}

private func modelRoutingPlatformRects(in content: NSRect) -> [ModelRoutingPlatform: NSRect] {
    let width: CGFloat = 170
    let gap: CGFloat = 8
    let buttonWidth = (width - gap) / 2
    let startX = content.maxX - width
    return [
        .codex: NSRect(x: startX, y: content.minY + 6, width: buttonWidth, height: 30),
        .claude: NSRect(x: startX + buttonWidth + gap, y: content.minY + 6, width: buttonWidth, height: 30),
    ]
}

struct ModelRoutingPageLayout {
    let protectionRect: NSRect
    let globalRect: NSRect
    let toolbarRect: NSRect
    let tableRect: NSRect
    let tableHeaderRect: NSRect
    let projectRows: [String: NSRect]
    let inheritedDividerY: CGFloat?
    let footerRect: NSRect
}

final class ModelRoutingControls: NSObject, NSSearchFieldDelegate {
    enum Scope: Hashable {
        case global
        case project(String)
    }

    enum Field {
        case model
        case effort
    }

    enum ProjectFilter: Int {
        case all
        case overridden
        case inherited
    }

    struct Binding {
        let scope: Scope
        let field: Field
    }

    private(set) var snapshot: CodexModelRoutingSnapshot
    private(set) var statusMessage: String?
    private(set) var statusIsError = false
    private(set) var query = ""
    private(set) var projectFilter: ProjectFilter = .all
    private(set) var selectedPlatform: ModelRoutingPlatform

    private let codexStore: CodexModelRoutingStore
    private let claudeStore: ClaudeModelRoutingStore
    private let protectionPreferences: CodexModelRoutingProtectionPreferences
    private var configWatcher: CodexConfigWatcher?
    private weak var host: UsageDetailsView?
    private var bindings: [ObjectIdentifier: Binding] = [:]
    private var inheritanceBindings: [ObjectIdentifier: String] = [:]
    private var modelPopups: [Scope: NSPopUpButton] = [:]
    private var effortPopups: [Scope: NSPopUpButton] = [:]
    private var inheritanceCheckboxes: [String: NSButton] = [:]
    private let searchField = NSSearchField()
    private let filterControl = NSSegmentedControl(
        labels: ["", "", ""],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let codexPlatformButton = NSButton(title: "Codex", target: nil, action: nil)
    private let claudePlatformButton = NSButton(title: "Claude", target: nil, action: nil)
    private let protectionSwitch = NSSwitch(frame: .zero)
    private let refreshButton = NSButton(title: "", target: nil, action: nil)

    init(
        codexStore: CodexModelRoutingStore = CodexModelRoutingStore(),
        claudeStore: ClaudeModelRoutingStore = ClaudeModelRoutingStore(),
        protectionPreferences: CodexModelRoutingProtectionPreferences =
            CodexModelRoutingProtectionPreferences()
    ) {
        self.codexStore = codexStore
        self.claudeStore = claudeStore
        self.protectionPreferences = protectionPreferences
        if protectionPreferences.isEnabled {
            if let protected = protectionPreferences.protectedState() {
                _ = try? codexStore.restoreProtectedRoutingState(protected)
            } else {
                protectionPreferences.enable(capturing: codexStore.captureProtectedRoutingState())
            }
        }
        selectedPlatform = ModelRoutingPlatform(
            rawValue: UserDefaults.standard.string(forKey: "selectedModelRoutingPlatform") ?? ""
        ) ?? .codex
        snapshot = selectedPlatform == .codex
            ? codexStore.loadSnapshot()
            : claudeStore.loadSnapshot()
        super.init()
        configWatcher = CodexConfigWatcher { [weak self] in
            self?.handleExternalConfigChange()
        }
        updateConfigWatcher()
    }

    var isCodexDefaultsProtectionEnabled: Bool {
        protectionPreferences.isEnabled
    }

    func setCodexDefaultsProtectionEnabled(_ enabled: Bool) {
        if enabled {
            protectionPreferences.enable(capturing: codexStore.captureProtectedRoutingState())
            statusMessage = localized(
                chinese: "已锁定 Token Meter 默认配置",
                english: "Token Meter defaults are now protected",
                japanese: "Token Meter の既定設定を保護しました"
            )
        } else {
            protectionPreferences.disable()
            statusMessage = localized(
                chinese: "已允许 Codex 更新默认配置",
                english: "Codex may now update defaults",
                japanese: "Codex による既定設定の更新を許可しました"
            )
        }
        statusIsError = false
        protectionSwitch.state = enabled ? .on : .off
        updateConfigWatcher()
        invalidateLayout()
    }

    var visibleProjects: [CodexProjectRoutingSnapshot] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return snapshot.projects
            .filter { project in
                let matchesFilter: Bool
                switch projectFilter {
                case .all:
                    matchesFilter = true
                case .overridden:
                    matchesFilter = !project.inheritsEverything
                case .inherited:
                    matchesFilter = project.inheritsEverything
                }
                guard matchesFilter else { return false }
                guard !normalizedQuery.isEmpty else { return true }
                return project.project.name.localizedCaseInsensitiveContains(normalizedQuery)
                    || project.project.rootPaths.contains {
                        $0.localizedCaseInsensitiveContains(normalizedQuery)
                    }
            }
            .enumerated()
            .sorted { lhs, rhs in
                if projectFilter == .all,
                   lhs.element.inheritsEverything != rhs.element.inheritsEverything {
                    return !lhs.element.inheritsEverything
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    func install(in host: UsageDetailsView) {
        self.host = host

        searchField.controlSize = .small
        searchField.font = .systemFont(ofSize: 12, weight: .medium)
        searchField.appearance = NSAppearance(named: .darkAqua)
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.delegate = self
        searchField.sendsWholeSearchString = false
        searchField.sendsSearchStringImmediately = true
        searchField.isHidden = true
        host.addSubview(searchField)

        filterControl.controlSize = .regular
        filterControl.segmentStyle = .rounded
        filterControl.appearance = NSAppearance(named: .darkAqua)
        filterControl.selectedSegmentBezelColor = host.accentBlue
        filterControl.selectedSegment = ProjectFilter.all.rawValue
        filterControl.target = self
        filterControl.action = #selector(filterChanged(_:))
        filterControl.isHidden = true
        host.addSubview(filterControl)

        configurePlatformButton(codexPlatformButton, platform: .codex, in: host)
        configurePlatformButton(claudePlatformButton, platform: .claude, in: host)
        updatePlatformButtonStyles()

        protectionSwitch.controlSize = .small
        protectionSwitch.appearance = NSAppearance(named: .darkAqua)
        protectionSwitch.state = isCodexDefaultsProtectionEnabled ? .on : .off
        protectionSwitch.target = self
        protectionSwitch.action = #selector(protectionChanged(_:))
        protectionSwitch.isHidden = true
        protectionSwitch.setAccessibilityLabel(
            localized(
                chinese: "锁定 Codex 默认模型",
                english: "Protect Codex defaults",
                japanese: "Codex の既定モデルを保護"
            )
        )
        host.addSubview(protectionSwitch)

        refreshButton.isBordered = true
        refreshButton.bezelStyle = .rounded
        refreshButton.controlSize = .regular
        refreshButton.font = .systemFont(ofSize: 11.5, weight: .semibold)
        refreshButton.contentTintColor = NSColor.white.withAlphaComponent(0.82)
        refreshButton.appearance = NSAppearance(named: .darkAqua)
        refreshButton.target = self
        refreshButton.action = #selector(refreshRequested)
        refreshButton.isHidden = true
        host.addSubview(refreshButton)

        rebuildPopups()
    }

    private func configurePlatformButton(
        _ button: NSButton,
        platform: ModelRoutingPlatform,
        in host: UsageDetailsView
    ) {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.masksToBounds = true
        button.layer?.borderWidth = 1
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.contentTintColor = .white
        button.appearance = NSAppearance(named: .darkAqua)
        button.target = self
        button.action = #selector(platformButtonChanged(_:))
        button.setAccessibilityRole(.radioButton)
        button.setAccessibilityLabel(
            localized(
                chinese: "配置 \(platform == .codex ? "Codex" : "Claude")",
                english: "Configure \(platform == .codex ? "Codex" : "Claude")",
                japanese: "\(platform == .codex ? "Codex" : "Claude") を設定"
            )
        )
        button.isHidden = true
        host.addSubview(button)
    }

    private func updatePlatformButtonStyles() {
        guard let host else { return }
        for (platform, button) in [
            (ModelRoutingPlatform.codex, codexPlatformButton),
            (ModelRoutingPlatform.claude, claudePlatformButton),
        ] {
            let selected = selectedPlatform == platform
            button.state = selected ? .on : .off
            button.layer?.backgroundColor = (
                selected
                    ? host.accentBlue.withAlphaComponent(0.72)
                    : host.inputSurfaceColor.withAlphaComponent(0.82)
            ).cgColor
            button.layer?.borderColor = (
                selected
                    ? host.accentTeal.withAlphaComponent(0.38)
                    : host.borderColor
            ).cgColor
            button.setAccessibilityValue(selected)
        }
    }

    func reload() {
        snapshot = loadActiveSnapshot()
        updateConfigWatcher()
        rebuildPopups()
        invalidateLayout()
    }

    func selectPlatform(_ platform: ModelRoutingPlatform) {
        guard selectedPlatform != platform else { return }
        selectedPlatform = platform
        UserDefaults.standard.set(platform.rawValue, forKey: "selectedModelRoutingPlatform")
        statusMessage = nil
        statusIsError = false
        updatePlatformButtonStyles()
        reload()
    }

    func configure(query: String?, filter rawFilter: String?) {
        if let query {
            self.query = query
            searchField.stringValue = query
        }
        if let rawFilter {
            switch rawFilter {
            case "overridden", "override":
                projectFilter = .overridden
            case "inherited", "inherit":
                projectFilter = .inherited
            default:
                projectFilter = .all
            }
            filterControl.selectedSegment = projectFilter.rawValue
        }
        invalidateLayout()
    }

    func layout(in content: NSRect, visible: Bool) {
        let layout = host?.modelRoutingPageLayout(in: content)
        searchField.isHidden = !visible
        filterControl.isHidden = !visible
        codexPlatformButton.isHidden = !visible
        claudePlatformButton.isHidden = !visible
        protectionSwitch.isHidden = !visible || selectedPlatform != .codex
        refreshButton.isHidden = !visible

        for popup in modelPopups.values {
            popup.isHidden = true
        }
        for popup in effortPopups.values {
            popup.isHidden = true
        }
        for checkbox in inheritanceCheckboxes.values {
            checkbox.isHidden = true
        }
        guard visible, let layout else { return }

        let platformRects = modelRoutingPlatformRects(in: content)
        codexPlatformButton.frame = platformRects[.codex] ?? .zero
        claudePlatformButton.frame = platformRects[.claude] ?? .zero
        protectionSwitch.state = isCodexDefaultsProtectionEnabled ? .on : .off
        protectionSwitch.frame = NSRect(
            x: layout.protectionRect.maxX - 68,
            y: layout.protectionRect.midY - 12,
            width: 48,
            height: 24
        )

        searchField.placeholderString = localized(
            chinese: "搜索项目",
            english: "Search projects",
            japanese: "プロジェクトを検索"
        )
        searchField.setAccessibilityLabel(searchField.placeholderString ?? "")
        // A borderless NSSearchField draws its icon and text slightly above the
        // visual center of our custom search surface.
        searchField.frame = modelRoutingSearchRect(in: layout.toolbarRect)
            .insetBy(dx: 7, dy: 1)
            .offsetBy(dx: 0, dy: 2)

        filterControl.setLabel(localized(chinese: "全部", english: "All", japanese: "すべて"), forSegment: 0)
        filterControl.setLabel(localized(chinese: "项目设置", english: "Project setting", japanese: "プロジェクト設定"), forSegment: 1)
        filterControl.setLabel(localized(chinese: "跟随全局", english: "Follows global", japanese: "グローバルに従う"), forSegment: 2)
        let filterWidth = min(332, max(264, layout.toolbarRect.width * 0.31))
        filterControl.frame = NSRect(
            x: layout.toolbarRect.maxX - filterWidth,
            y: layout.toolbarRect.minY,
            width: filterWidth,
            height: 34
        )

        refreshButton.title = localized(
            chinese: "重新读取项目…",
            english: "Reload projects…",
            japanese: "プロジェクトを再読込…"
        )
        refreshButton.frame = NSRect(
            x: layout.footerRect.minX,
            y: layout.footerRect.minY + 10,
            width: 132,
            height: 32
        )

        layoutGlobalPopups(in: layout.globalRect)
        for project in visibleProjects {
            guard let row = layout.projectRows[project.project.id] else { continue }
            layoutProjectControls(project: project, row: row)
        }
    }

    func effectiveGlobalModel() -> String {
        if let model = snapshot.global.model {
            return model
        }
        return snapshot.models.first?.slug ?? "gpt-5.6-terra"
    }

    func effectiveGlobalEffort() -> String {
        snapshot.global.reasoningEffort
            ?? modelOption(slug: effectiveGlobalModel())?.defaultReasoningEffort
            ?? "medium"
    }

    func modelOption(slug: String?) -> CodexModelOption? {
        guard let slug else { return nil }
        return snapshot.models.first { $0.slug == slug }
    }

    var platformDisplayName: String {
        selectedPlatform == .codex ? "Codex" : "Claude"
    }

    private func loadActiveSnapshot() -> CodexModelRoutingSnapshot {
        switch selectedPlatform {
        case .codex:
            return codexStore.loadSnapshot()
        case .claude:
            return claudeStore.loadSnapshot()
        }
    }

    private func writeGlobal(model: String, reasoningEffort: String?) throws {
        switch selectedPlatform {
        case .codex:
            guard let reasoningEffort, !reasoningEffort.isEmpty else {
                throw CodexModelRoutingStoreError.missingGlobalDefault("model_reasoning_effort")
            }
            try codexStore.writeGlobal(model: model, reasoningEffort: reasoningEffort)
        case .claude:
            try claudeStore.writeGlobal(model: model, reasoningEffort: reasoningEffort)
        }
    }

    private func writeProject(
        id: String,
        model: String?,
        reasoningEffort: String?
    ) throws {
        switch selectedPlatform {
        case .codex:
            try codexStore.writeProject(
                id: id,
                model: model,
                reasoningEffort: reasoningEffort
            )
        case .claude:
            try claudeStore.writeProject(
                id: id,
                model: model,
                reasoningEffort: reasoningEffort
            )
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField, field === searchField else { return }
        query = field.stringValue
        invalidateLayout()
    }

    @objc private func filterChanged(_ sender: NSSegmentedControl) {
        projectFilter = ProjectFilter(rawValue: sender.selectedSegment) ?? .all
        invalidateLayout()
    }

    @objc private func platformButtonChanged(_ sender: NSButton) {
        selectPlatform(sender === claudePlatformButton ? .claude : .codex)
    }

    @objc private func protectionChanged(_ sender: NSSwitch) {
        setCodexDefaultsProtectionEnabled(sender.state == .on)
    }

    @objc private func refreshRequested() {
        statusMessage = nil
        statusIsError = false
        reload()
    }

    private func handleExternalConfigChange() {
        if protectionPreferences.isEnabled,
           let protected = protectionPreferences.protectedState() {
            do {
                let restored = try codexStore.restoreProtectedRoutingState(protected)
                if restored {
                    statusMessage = localized(
                        chinese: "已恢复 Token Meter 的 Codex 默认配置",
                        english: "Restored Token Meter's Codex defaults",
                        japanese: "Token Meter の Codex 既定設定を復元しました"
                    )
                    statusIsError = false
                    reload()
                    return
                }
            } catch {
                statusMessage = error.localizedDescription
                statusIsError = true
                reload()
                return
            }
        }
        statusMessage = localized(
            chinese: "已同步外部配置",
            english: "Synced external configuration",
            japanese: "外部設定と同期しました"
        )
        statusIsError = false
        reload()
    }

    private func updateConfigWatcher() {
        let codexSnapshot = selectedPlatform == .codex
            ? snapshot
            : codexStore.loadSnapshot()
        var urls = codexStore.routingInputURLs(for: codexSnapshot)
        if selectedPlatform == .claude {
            urls.append(contentsOf: claudeStore.routingInputURLs(for: snapshot))
        }
        configWatcher?.watch(targetURLs: urls)
    }

    @objc private func popupChanged(_ sender: NSPopUpButton) {
        guard let binding = bindings[ObjectIdentifier(sender)] else { return }
        do {
            switch binding.scope {
            case .global:
                try writeGlobalChange(field: binding.field, sender: sender)
            case let .project(id):
                try writeProjectChange(id: id, field: binding.field, sender: sender)
            }
            recordProtectedCodexDefaultsIfNeeded()
            statusMessage = localized(
                chinese: "已保存",
                english: "Saved",
                japanese: "保存済み"
            )
            statusIsError = false
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
        reload()
    }

    @objc private func inheritanceChanged(_ sender: NSButton) {
        guard let id = inheritanceBindings[ObjectIdentifier(sender)] else { return }
        do {
            if sender.state == .on {
                try writeProject(id: id, model: nil, reasoningEffort: nil)
            } else {
                try writeProject(
                    id: id,
                    model: effectiveGlobalModel(),
                    reasoningEffort: effectiveGlobalEffort()
                )
            }
            recordProtectedCodexDefaultsIfNeeded()
            statusMessage = localized(
                chinese: "已保存",
                english: "Saved",
                japanese: "保存済み"
            )
            statusIsError = false
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
        reload()
    }

    private func recordProtectedCodexDefaultsIfNeeded() {
        guard selectedPlatform == .codex, protectionPreferences.isEnabled else { return }
        protectionPreferences.updateProtectedState(codexStore.captureProtectedRoutingState())
    }

    private func invalidateLayout() {
        host?.onPreferredHeightChanged?()
        host?.needsDisplay = true
        host?.needsLayout = true
    }

    private func writeGlobalChange(field: Field, sender: NSPopUpButton) throws {
        var model = snapshot.global.model ?? effectiveGlobalModel()
        var effort: String? = snapshot.global.reasoningEffort
            ?? modelOption(slug: model)?.defaultReasoningEffort
        if effort?.isEmpty == true {
            effort = nil
        }
        let value = selectedValue(in: sender)
        switch field {
        case .model:
            model = value
            let supported = modelOption(slug: model)?.supportedReasoningEfforts ?? []
            if supported.isEmpty {
                effort = nil
            } else if effort.map({ !supported.contains($0) }) ?? true {
                effort = preferredEffort(for: model)
            }
        case .effort:
            effort = value == modelRoutingNotApplicableValue ? nil : value
        }
        guard !model.isEmpty else {
            throw CodexModelRoutingStoreError.missingGlobalDefault("model")
        }
        if selectedPlatform == .codex, effort?.isEmpty != false {
            throw CodexModelRoutingStoreError.missingGlobalDefault("model_reasoning_effort")
        }
        try writeGlobal(model: model, reasoningEffort: effort)
    }

    private func writeProjectChange(id: String, field: Field, sender: NSPopUpButton) throws {
        guard let project = snapshot.projects.first(where: { $0.project.id == id }) else {
            throw CodexModelRoutingStoreError.missingProject(id)
        }
        var model = project.model.explicitValue ?? effectiveGlobalModel()
        var effort: String? = project.reasoningEffort.explicitValue ?? effectiveGlobalEffort()
        if effort?.isEmpty == true {
            effort = nil
        }
        let value = selectedValue(in: sender)

        switch field {
        case .model:
            model = value
            let supported = modelOption(slug: model)?.supportedReasoningEfforts ?? []
            if supported.isEmpty {
                effort = nil
            } else if effort.map({ !supported.contains($0) }) ?? true {
                effort = preferredEffort(for: model)
            }
        case .effort:
            effort = value == modelRoutingNotApplicableValue ? nil : value
        }
        try writeProject(id: id, model: model, reasoningEffort: effort)
    }

    private func rebuildPopups() {
        for popup in modelPopups.values {
            popup.removeFromSuperview()
        }
        for popup in effortPopups.values {
            popup.removeFromSuperview()
        }
        for checkbox in inheritanceCheckboxes.values {
            checkbox.removeFromSuperview()
        }
        bindings.removeAll()
        inheritanceBindings.removeAll()
        modelPopups.removeAll()
        effortPopups.removeAll()
        inheritanceCheckboxes.removeAll()

        installPopups(scope: .global, project: nil)
        for project in snapshot.projects {
            installPopups(scope: .project(project.project.id), project: project)
        }
        host?.needsLayout = true
    }

    private func installPopups(scope: Scope, project: CodexProjectRoutingSnapshot?) {
        guard let host else { return }
        let modelPopup = makePopup()
        let effortPopup = makePopup()
        modelPopups[scope] = modelPopup
        effortPopups[scope] = effortPopup
        bindings[ObjectIdentifier(modelPopup)] = Binding(scope: scope, field: .model)
        bindings[ObjectIdentifier(effortPopup)] = Binding(scope: scope, field: .effort)
        host.addSubview(modelPopup)
        host.addSubview(effortPopup)

        let selectedModel: CodexProjectConfigValue
        let selectedEffort: CodexProjectConfigValue
        if let project {
            selectedModel = project.model
            selectedEffort = project.reasoningEffort
        } else {
            selectedModel = snapshot.global.model.map(CodexProjectConfigValue.value) ?? .inherited
            selectedEffort = snapshot.global.reasoningEffort.map(CodexProjectConfigValue.value) ?? .inherited
        }
        configureModelPopup(modelPopup, selected: selectedModel)
        configureEffortPopup(
            effortPopup,
            scope: scope,
            selectedModel: selectedModel,
            selectedEffort: selectedEffort
        )

        if let project {
            let checkbox = makeInheritanceCheckbox(project: project)
            inheritanceCheckboxes[project.project.id] = checkbox
            inheritanceBindings[ObjectIdentifier(checkbox)] = project.project.id
            host.addSubview(checkbox)

            let controlsEnabled = !project.inheritsEverything && !project.hasMixedValues
            modelPopup.isEnabled = controlsEnabled
            effortPopup.isEnabled = controlsEnabled && modelSupportsEffort(
                project.model.explicitValue ?? effectiveGlobalModel()
            )
            modelPopup.alphaValue = controlsEnabled ? 1 : 0.52
            effortPopup.alphaValue = effortPopup.isEnabled ? 1 : 0.52
        } else {
            effortPopup.isEnabled = modelSupportsEffort(
                snapshot.global.model ?? effectiveGlobalModel()
            )
            effortPopup.alphaValue = effortPopup.isEnabled ? 1 : 0.52
        }
    }

    private func makePopup() -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.controlSize = .regular
        popup.font = .systemFont(ofSize: 12, weight: .semibold)
        popup.isBordered = false
        popup.isHidden = true
        popup.wantsLayer = true
        popup.layer?.cornerRadius = 7
        popup.layer?.borderWidth = 1
        popup.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        popup.layer?.backgroundColor = host?.inputSurfaceColor.cgColor
        popup.appearance = NSAppearance(named: .darkAqua)
        popup.target = self
        popup.action = #selector(popupChanged(_:))
        return popup
    }

    private func makeInheritanceCheckbox(project: CodexProjectRoutingSnapshot) -> NSButton {
        let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(inheritanceChanged(_:)))
        checkbox.controlSize = .small
        checkbox.appearance = NSAppearance(named: .darkAqua)
        checkbox.allowsMixedState = true
        if project.blocksGlobalInheritance {
            checkbox.state = .off
            checkbox.isEnabled = false
            checkbox.toolTip = localized(
                chinese: "此项目的共享 .claude/settings.json 已设置模型或思考强度，因此不能直接跟随全局。本页仍可用私有设置覆盖它。",
                english: "This project's shared .claude/settings.json sets a model or effort, so it cannot directly follow global. You can still override it privately here.",
                japanese: "共有 .claude/settings.json にモデルまたは思考強度があるため、直接グローバルには従えません。この画面で非公開に上書きできます。"
            )
        } else if project.hasMixedValues {
            checkbox.state = .mixed
            checkbox.contentTintColor = host?.accentAmber
            checkbox.toolTip = localized(
                chinese: "多个根目录设置不同。勾选后统一跟随全局；取消后使用当前全局值创建项目设置。",
                english: "Settings differ across roots. Check to follow global everywhere, or uncheck to create project settings from the current global values.",
                japanese: "ルート間で設定が異なります。チェックするとすべてグローバルに従い、外すと現在のグローバル値からプロジェクト設定を作成します。"
            )
        } else if project.inheritsEverything {
            checkbox.state = .on
            checkbox.toolTip = localized(
                chinese: "正在跟随全局。取消勾选后可修改项目设置。",
                english: "Following global. Uncheck to edit project settings.",
                japanese: "グローバルに従っています。チェックを外すとプロジェクト設定を編集できます。"
            )
        } else {
            checkbox.state = .off
            checkbox.toolTip = localized(
                chinese: "正在使用项目设置。勾选后将移除项目设置并跟随全局。",
                english: "Using project settings. Check to remove them and follow global.",
                japanese: "プロジェクト設定を使用しています。チェックすると設定を削除してグローバルに従います。"
            )
        }
        checkbox.setAccessibilityLabel(
            localized(
                chinese: "\(project.project.name) 跟随全局",
                english: "\(project.project.name) follows global",
                japanese: "\(project.project.name) はグローバルに従う"
            )
        )
        checkbox.isHidden = true
        return checkbox
    }

    private func configureModelPopup(
        _ popup: NSPopUpButton,
        selected: CodexProjectConfigValue
    ) {
        popup.removeAllItems()
        if selected == .mixed {
            addItem(
                to: popup,
                title: localized(chinese: "多个根目录设置不同", english: "Settings differ across roots", japanese: "ルート間で設定が異なる"),
                value: modelRoutingMixedValue,
                enabled: false
            )
        }
        for model in snapshot.models {
            addItem(to: popup, title: model.displayName, value: model.slug)
        }

        let selectedValue: String
        switch selected {
        case .inherited:
            selectedValue = effectiveGlobalModel()
        case let .value(value):
            if !snapshot.models.contains(where: { $0.slug == value }) {
                addItem(to: popup, title: value, value: value)
            }
            selectedValue = value
        case .mixed:
            selectedValue = modelRoutingMixedValue
        }
        select(value: selectedValue, in: popup)
        popup.setAccessibilityLabel(
            localized(chinese: "默认模型", english: "Default model", japanese: "既定モデル")
        )
    }

    private func configureEffortPopup(
        _ popup: NSPopUpButton,
        scope: Scope,
        selectedModel: CodexProjectConfigValue,
        selectedEffort: CodexProjectConfigValue
    ) {
        popup.removeAllItems()
        if selectedEffort == .mixed {
            addItem(
                to: popup,
                title: localized(chinese: "多个根目录设置不同", english: "Settings differ across roots", japanese: "ルート間で設定が異なる"),
                value: modelRoutingMixedValue,
                enabled: false
            )
        }
        let model = selectedModel.explicitValue ?? effectiveGlobalModel()
        var efforts = modelOption(slug: model)?.supportedReasoningEfforts
            ?? fallbackEfforts
        if efforts.isEmpty {
            addItem(
                to: popup,
                title: localized(chinese: "不适用", english: "Not applicable", japanese: "対象外"),
                value: modelRoutingNotApplicableValue,
                enabled: false
            )
            select(value: modelRoutingNotApplicableValue, in: popup)
            popup.setAccessibilityLabel(
                localized(chinese: "默认思考强度", english: "Default reasoning effort", japanese: "既定の思考強度")
            )
            return
        }
        let explicitEffort = selectedEffort.explicitValue
        if let explicitEffort, !efforts.contains(explicitEffort) {
            efforts.append(explicitEffort)
        }
        for effort in efforts {
            let isUnsupportedPersistedClaudeEffort = selectedPlatform == .claude
                && !fallbackEfforts.contains(effort)
            addItem(
                to: popup,
                title: isUnsupportedPersistedClaudeEffort
                    ? localized(
                        chinese: "\(effort)（仅会话）",
                        english: "\(effort) (session only)",
                        japanese: "\(effort)（セッションのみ）"
                    )
                    : effort,
                value: effort,
                enabled: !isUnsupportedPersistedClaudeEffort
            )
        }
        if selectedPlatform == .claude,
           let explicitEffort,
           !fallbackEfforts.contains(explicitEffort) {
            popup.toolTip = localized(
                chinese: "\(explicitEffort) 不能保存到 Claude 设置；请选择 low、medium、high 或 xhigh。",
                english: "\(explicitEffort) cannot be persisted in Claude settings; choose low, medium, high, or xhigh.",
                japanese: "\(explicitEffort) は Claude 設定に保存できません。low、medium、high、xhigh のいずれかを選択してください。"
            )
        } else {
            popup.toolTip = nil
        }

        let selectedValue: String
        switch selectedEffort {
        case .inherited:
            if case .project = scope {
                selectedValue = effectiveGlobalEffort()
            } else {
                selectedValue = snapshot.global.reasoningEffort ?? preferredEffort(for: model)
            }
        case let .value(value):
            selectedValue = value
        case .mixed:
            selectedValue = modelRoutingMixedValue
        }
        select(value: selectedValue, in: popup)
        popup.setAccessibilityLabel(
            localized(chinese: "默认思考强度", english: "Default reasoning effort", japanese: "既定の思考強度")
        )
    }

    private func layoutGlobalPopups(in row: NSRect) {
        let rightPadding: CGFloat = 156
        let effortWidth: CGFloat = row.width >= 900 ? 174 : 120
        let modelWidth: CGFloat = row.width >= 900 ? 238 : 180
        let gap: CGFloat = row.width >= 900 ? 112 : 12
        let effortX = row.maxX - rightPadding - effortWidth
        let modelX = effortX - gap - modelWidth
        let y = row.midY - 18
        modelPopups[.global]?.frame = NSRect(x: modelX, y: y, width: modelWidth, height: 36)
        effortPopups[.global]?.frame = NSRect(x: effortX, y: y, width: effortWidth, height: 36)
        modelPopups[.global]?.isHidden = false
        effortPopups[.global]?.isHidden = false
    }

    private func layoutProjectControls(project: CodexProjectRoutingSnapshot, row: NSRect) {
        let scope = Scope.project(project.project.id)
        let columns = modelRoutingColumns(in: row)
        modelPopups[scope]?.frame = columns.model.insetBy(dx: 0, dy: 18)
        effortPopups[scope]?.frame = columns.effort.insetBy(dx: 0, dy: 18)
        modelPopups[scope]?.isHidden = false
        effortPopups[scope]?.isHidden = false
        if let checkbox = inheritanceCheckboxes[project.project.id] {
            checkbox.frame = NSRect(
                x: columns.status.midX - 10,
                y: columns.status.midY - 10,
                width: 20,
                height: 20
            )
            checkbox.isHidden = false
        }
    }

    private func preferredEffort(for model: String) -> String {
        guard let option = modelOption(slug: model) else {
            return selectedPlatform == .claude ? "high" : "medium"
        }
        if option.supportedReasoningEfforts.contains("medium") {
            return "medium"
        }
        return option.defaultReasoningEffort
    }

    private var fallbackEfforts: [String] {
        switch selectedPlatform {
        case .codex:
            return ["low", "medium", "high", "xhigh", "max", "ultra"]
        case .claude:
            return ["low", "medium", "high", "xhigh"]
        }
    }

    private func modelSupportsEffort(_ model: String) -> Bool {
        !(modelOption(slug: model)?.supportedReasoningEfforts ?? fallbackEfforts).isEmpty
    }

    private func selectedValue(in popup: NSPopUpButton) -> String {
        popup.selectedItem?.representedObject as? String ?? ""
    }

    private func addItem(
        to popup: NSPopUpButton,
        title: String,
        value: String,
        enabled: Bool = true
    ) {
        popup.addItem(withTitle: title)
        popup.lastItem?.representedObject = value
        popup.lastItem?.isEnabled = enabled
    }

    private func select(value: String, in popup: NSPopUpButton) {
        if let item = popup.itemArray.first(where: { ($0.representedObject as? String) == value }) {
            popup.select(item)
        }
    }

    private func localized(chinese: String, english: String, japanese: String) -> String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return chinese
        case .japanese: return japanese
        default: return english
        }
    }
}

extension UsageDetailsView {
    func modelRoutingPageLayout(in content: NSRect) -> ModelRoutingPageLayout {
        let protectionRect = NSRect(
            x: content.minX,
            y: content.minY + 58,
            width: content.width,
            height: 96
        )
        let globalRect = NSRect(
            x: content.minX,
            y: protectionRect.maxY + 14,
            width: content.width,
            height: 88
        )
        let toolbarRect = NSRect(x: content.minX, y: globalRect.maxY + 28, width: content.width, height: 34)
        let projects = modelRoutingControls.visibleProjects
        let headerHeight: CGFloat = 48
        let rowHeight: CGFloat = 72
        let emptyHeight: CGFloat = 92
        let tableHeight = headerHeight + (projects.isEmpty ? emptyHeight : rowHeight * CGFloat(projects.count))
        let tableRect = NSRect(
            x: content.minX,
            y: toolbarRect.maxY + 18,
            width: content.width,
            height: tableHeight
        )
        let tableHeaderRect = NSRect(
            x: tableRect.minX,
            y: tableRect.minY,
            width: tableRect.width,
            height: headerHeight
        )
        var rows: [String: NSRect] = [:]
        var y = tableHeaderRect.maxY
        var inheritedDividerY: CGFloat?
        var sawOverride = false
        for project in projects {
            if project.inheritsEverything, sawOverride, inheritedDividerY == nil {
                inheritedDividerY = y
            }
            if !project.inheritsEverything {
                sawOverride = true
            }
            rows[project.project.id] = NSRect(
                x: tableRect.minX,
                y: y,
                width: tableRect.width,
                height: rowHeight
            )
            y += rowHeight
        }
        let footerRect = NSRect(
            x: content.minX + 4,
            y: tableRect.maxY + 22,
            width: content.width - 8,
            height: 56
        )
        return ModelRoutingPageLayout(
            protectionRect: protectionRect,
            globalRect: globalRect,
            toolbarRect: toolbarRect,
            tableRect: tableRect,
            tableHeaderRect: tableHeaderRect,
            projectRows: rows,
            inheritedDividerY: inheritedDividerY,
            footerRect: footerRect
        )
    }

    func drawModelRoutingPage(content: NSRect) {
        let layout = modelRoutingPageLayout(in: content)
        drawCodexDefaultsProtection(layout.protectionRect)
        drawPanel(layout.globalRect)
        drawGlobalRoutingStrip(layout.globalRect)
        drawRoutingSearchSurface(modelRoutingSearchRect(in: layout.toolbarRect))
        drawProjectRoutingTable(layout)
        drawRoutingFooter(layout.footerRect)
    }

    private func drawCodexDefaultsProtection(_ rect: NSRect) {
        let isCodex = modelRoutingControls.selectedPlatform == .codex
        let enabled = modelRoutingControls.isCodexDefaultsProtectionEnabled
        let fillColor = isCodex && enabled
            ? accentBlue.withAlphaComponent(0.13)
            : panelSurfaceColor.withAlphaComponent(0.82)
        fillColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()

        (isCodex && enabled ? accentTeal.withAlphaComponent(0.34) : borderColor).setStroke()
        let border = NSBezierPath(
            roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
            xRadius: 9,
            yRadius: 9
        )
        border.lineWidth = 1
        border.stroke()

        drawSymbolIcon(
            isCodex ? (enabled ? "checkmark.shield.fill" : "shield") : "info.circle",
            in: NSRect(x: rect.minX + 20, y: rect.minY + 22, width: 22, height: 22),
            color: isCodex && enabled ? accentTeal : NSColor.white.withAlphaComponent(0.46),
            pointSize: 16
        )

        let textX = rect.minX + 56
        let trailingSpace: CGFloat = isCodex ? 96 : 24
        let textWidth = max(160, rect.width - 56 - trailingSpace)
        drawText(
            isCodex
                ? modelRoutingLocalized(
                    chinese: "锁定 Codex 默认配置",
                    english: "Protect Codex defaults",
                    japanese: "Codex の既定設定を保護"
                )
                : modelRoutingLocalized(
                    chinese: "Claude 默认配置不受锁定保护",
                    english: "Claude defaults are not protected",
                    japanese: "Claude の既定設定は保護対象外です"
                ),
            rect: NSRect(x: textX, y: rect.minY + 16, width: textWidth, height: 22),
            font: .systemFont(ofSize: 13.5, weight: .bold),
            color: .white
        )
        drawMultilineText(
            isCodex
                ? modelRoutingLocalized(
                    chinese: "仅对 Codex 生效。对话内临时切换模型和思考强度仍然有效；如果 Codex 把这次选择写回配置文件，Token Meter 会自动恢复本页保存的默认值，之后的新对话继续使用这里的设置。只恢复 model 和 model_reasoning_effort，不改动其他配置。",
                    english: "Codex only. Temporary model and effort changes still work within a conversation. If Codex writes that choice back to its config, Token Meter restores the defaults saved here for future conversations. Only model and model_reasoning_effort are restored.",
                    japanese: "Codex のみに適用されます。会話内でのモデルや思考強度の一時変更はそのまま利用できます。Codex がその選択を設定ファイルへ書き戻した場合、Token Meter は今後の会話向けにこのページの既定値を復元します。復元対象は model と model_reasoning_effort のみです。"
                )
                : modelRoutingLocalized(
                    chinese: "此功能目前不对 Claude 生效。下方的 Claude 全局和项目默认值仍会正常保存，但 Token Meter 不会监控或自动恢复 Claude 在会话中改写的模型配置。",
                    english: "This protection does not currently apply to Claude. Claude global and project defaults below are still saved normally, but Token Meter does not monitor or automatically restore model settings changed from a Claude conversation.",
                    japanese: "この保護機能は現在 Claude には適用されません。下の Claude グローバル設定とプロジェクト設定は通常どおり保存されますが、会話から変更されたモデル設定を Token Meter が監視・自動復元することはありません。"
                ),
            rect: NSRect(x: textX, y: rect.minY + 42, width: textWidth, height: 42),
            font: .systemFont(ofSize: 10.5, weight: .medium),
            color: NSColor.white.withAlphaComponent(0.56)
        )
    }

    private func drawRoutingSearchSurface(_ rect: NSRect) {
        inputSurfaceColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        NSColor.white.withAlphaComponent(0.12).setStroke()
        let border = NSBezierPath(
            roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
            xRadius: 7,
            yRadius: 7
        )
        border.lineWidth = 1
        border.stroke()
    }

    private func drawGlobalRoutingStrip(_ row: NSRect) {
        let compact = row.width < 900
        drawText(
            modelRoutingLocalized(chinese: "全局默认", english: "Global default", japanese: "グローバル既定値"),
            rect: NSRect(
                x: row.minX + 20,
                y: row.minY + 31,
                width: compact ? 130 : max(130, row.width - 820),
                height: 24
            ),
            font: .systemFont(ofSize: 15, weight: .bold),
            color: .white
        )

        if !compact {
            let effortWidth: CGFloat = 174
            let modelWidth: CGFloat = 238
            let rightPadding: CGFloat = 156
            let effortX = row.maxX - rightPadding - effortWidth
            let modelX = effortX - 112 - modelWidth
            drawRight(
                modelRoutingLocalized(chinese: "默认模型", english: "Model", japanese: "モデル"),
                rect: NSRect(x: modelX - 86, y: row.minY + 34, width: 72, height: 18),
                color: NSColor.white.withAlphaComponent(0.60),
                font: .systemFont(ofSize: 11.5, weight: .semibold)
            )
            drawRight(
                modelRoutingLocalized(chinese: "思考强度", english: "Effort", japanese: "思考強度"),
                rect: NSRect(x: effortX - 98, y: row.minY + 34, width: 84, height: 18),
                color: NSColor.white.withAlphaComponent(0.60),
                font: .systemFont(ofSize: 11.5, weight: .semibold)
            )
        }

        let hasExplicitGlobal = modelRoutingControls.snapshot.global.model != nil
            && (
                modelRoutingControls.selectedPlatform == .claude
                    || modelRoutingControls.snapshot.global.reasoningEffort != nil
            )
        let defaultStatus = hasExplicitGlobal
            ? modelRoutingLocalized(chinese: "已保存", english: "Saved", japanese: "保存済み")
            : modelRoutingLocalized(
                chinese: "使用 \(modelRoutingControls.platformDisplayName) 默认",
                english: "Using \(modelRoutingControls.platformDisplayName) defaults",
                japanese: "\(modelRoutingControls.platformDisplayName) 既定値を使用"
            )
        let statusText = modelRoutingControls.statusMessage ?? defaultStatus
        let statusColor = modelRoutingControls.statusIsError
            ? accentRose
            : NSColor.white.withAlphaComponent(0.60)
        let statusRect = NSRect(x: row.maxX - 132, y: row.minY + 30, width: 112, height: 26)
        if !modelRoutingControls.statusIsError {
            drawSymbolIcon(
                "checkmark.circle",
                in: NSRect(x: statusRect.minX, y: statusRect.minY + 3, width: 18, height: 18),
                color: statusColor,
                pointSize: 13
            )
        }
        drawTruncatedText(
            statusText,
            rect: NSRect(x: statusRect.minX + 24, y: statusRect.minY + 3, width: statusRect.width - 24, height: 20),
            font: .systemFont(ofSize: 11.5, weight: .semibold),
            color: statusColor
        )
    }

    private func drawProjectRoutingTable(_ layout: ModelRoutingPageLayout) {
        panelSurfaceColor.setFill()
        NSBezierPath(roundedRect: layout.tableRect, xRadius: 9, yRadius: 9).fill()
        borderColor.setStroke()
        let border = NSBezierPath(roundedRect: layout.tableRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        border.lineWidth = 1
        border.stroke()

        let columns = modelRoutingColumns(in: layout.tableHeaderRect)
        drawTableHeader(
            modelRoutingLocalized(chinese: "项目", english: "Project", japanese: "プロジェクト"),
            rect: columns.project
        )
        drawTableHeader(
            modelRoutingLocalized(chinese: "默认模型", english: "Default model", japanese: "既定モデル"),
            rect: columns.model
        )
        drawTableHeader(
            modelRoutingLocalized(chinese: "思考强度", english: "Reasoning effort", japanese: "思考強度"),
            rect: columns.effort
        )
        drawCentered(
            modelRoutingLocalized(chinese: "跟随全局", english: "Follow global", japanese: "グローバルに従う"),
            rect: columns.status.insetBy(dx: 0, dy: 15),
            font: .systemFont(ofSize: 10.5, weight: .bold),
            color: NSColor.white.withAlphaComponent(0.58)
        )
        drawRoutingSeparator(y: layout.tableHeaderRect.maxY, table: layout.tableRect, strong: false)

        let projects = modelRoutingControls.visibleProjects
        if projects.isEmpty {
            let message = modelRoutingControls.query.isEmpty
                ? modelRoutingLocalized(
                    chinese: "没有符合当前筛选条件的项目",
                    english: "No projects match this filter",
                    japanese: "このフィルターに一致するプロジェクトはありません"
                )
                : modelRoutingLocalized(
                    chinese: "没有找到匹配的项目",
                    english: "No matching projects",
                    japanese: "一致するプロジェクトがありません"
                )
            drawCentered(
                message,
                rect: NSRect(
                    x: layout.tableRect.minX + 20,
                    y: layout.tableHeaderRect.maxY + 30,
                    width: layout.tableRect.width - 40,
                    height: 24
                ),
                font: .systemFont(ofSize: 12, weight: .semibold),
                color: NSColor.white.withAlphaComponent(0.46)
            )
            return
        }

        for (index, project) in projects.enumerated() {
            guard let row = layout.projectRows[project.project.id] else { continue }
            if index > 0 {
                drawRoutingSeparator(
                    y: row.minY,
                    table: layout.tableRect,
                    strong: layout.inheritedDividerY == row.minY
                )
            }
            let rowColumns = modelRoutingColumns(in: row)
            drawTruncatedText(
                project.project.name,
                rect: rowColumns.project.insetBy(dx: 0, dy: 25),
                font: .systemFont(ofSize: 13, weight: .semibold),
                color: NSColor.white.withAlphaComponent(0.90)
            )
        }
    }

    private func drawTableHeader(_ title: String, rect: NSRect) {
        drawText(
            title,
            rect: rect.insetBy(dx: 0, dy: 15),
            font: .systemFont(ofSize: 10.5, weight: .bold),
            color: NSColor.white.withAlphaComponent(0.58)
        )
    }

    private func drawRoutingSeparator(y: CGFloat, table: NSRect, strong: Bool) {
        let color = strong
            ? NSColor.white.withAlphaComponent(0.22)
            : NSColor.white.withAlphaComponent(0.075)
        color.setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: table.minX + 10, y: y))
        path.line(to: NSPoint(x: table.maxX - 10, y: y))
        path.lineWidth = strong ? 1.3 : 1
        path.stroke()
    }

    private func drawRoutingFooter(_ rect: NSRect) {
        let countText: String
        if modelRoutingControls.selectedPlatform == .claude {
            countText = modelRoutingLocalized(
                chinese: "Claude 项目设置保存为本机私有配置，不修改团队共享文件",
                english: "Claude project settings stay private on this Mac; shared team files are not changed",
                japanese: "Claude プロジェクト設定はこの Mac の非公開設定に保存され、共有ファイルは変更されません"
            )
        } else {
            countText = modelRoutingLocalized(
                chinese: "配置作用范围：当前列表中的 Codex 项目",
                english: "Configuration scope: listed Codex projects",
                japanese: "設定範囲：一覧の Codex プロジェクト"
            )
        }
        drawRight(
            countText,
            rect: NSRect(x: rect.minX + 154, y: rect.minY + 16, width: rect.width - 154, height: 20),
            color: NSColor.white.withAlphaComponent(0.42),
            font: .systemFont(ofSize: 10.5, weight: .medium)
        )
    }

    private func modelRoutingLocalized(chinese: String, english: String, japanese: String) -> String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return chinese
        case .japanese: return japanese
        default: return english
        }
    }
}
