import Cocoa

private let modelRoutingMixedValue = "__mixed__"
private let modelRoutingNotApplicableValue = "__not_applicable__"
private let modelRoutingBuiltInPlanDefaultValue = "__built_in_plan_default__"

private final class SearchTextFieldCell: NSTextFieldCell {
    private func centeredRect(for bounds: NSRect) -> NSRect {
        let horizontalPadding: CGFloat = 34
        let measuredHeight = ceil(cellSize.height)
        return NSRect(
            x: bounds.minX + horizontalPadding,
            y: bounds.minY + floor((bounds.height - measuredHeight) / 2),
            width: max(0, bounds.width - horizontalPadding - 8),
            height: min(bounds.height, measuredHeight)
        )
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        centeredRect(for: rect)
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        centeredRect(for: rect)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: centeredRect(for: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: centeredRect(for: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

private final class CompressionPercentageTextFieldCell: NSTextFieldCell {
    private func centeredRect(for bounds: NSRect) -> NSRect {
        let horizontalPadding: CGFloat = 12
        let measuredHeight = ceil(cellSize.height)
        return NSRect(
            x: bounds.minX + horizontalPadding,
            y: bounds.midY - measuredHeight / 2,
            width: max(0, bounds.width - horizontalPadding * 2),
            height: min(bounds.height, measuredHeight)
        )
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        NSColor(calibratedRed: 0.105, green: 0.13, blue: 0.18, alpha: 0.98).setFill()
        NSBezierPath(roundedRect: cellFrame, xRadius: 9, yRadius: 9).fill()
        NSColor.systemBlue.withAlphaComponent(0.94).setStroke()
        let border = NSBezierPath(roundedRect: cellFrame.insetBy(dx: 0.75, dy: 0.75), xRadius: 8.25, yRadius: 8.25)
        border.lineWidth = 1.5
        border.stroke()
        // drawInterior() asks drawingRect(forBounds:) for its text geometry, so
        // pass the full cell frame here to avoid applying the horizontal inset twice.
        super.drawInterior(withFrame: cellFrame, in: controlView)
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        centeredRect(for: rect)
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        centeredRect(for: rect)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: centeredRect(for: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: centeredRect(for: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

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

private struct ModelRoutingContextControlsLayout {
    let infoWidth: CGFloat
    let popupRect: NSRect
    let sliderRect: NSRect
    let percentageRect: NSRect
    let tokenLimitRect: NSRect
}

private func modelRoutingContextControlsLayout(in panel: NSRect) -> ModelRoutingContextControlsLayout {
    let horizontalInset: CGFloat = 16
    let gap: CGFloat = 12
    let availableWidth = max(0, panel.width - horizontalInset * 2)
    // Keep the localized field names readable in the compact inspector. The
    // slider can safely become shorter; clipping the label is much harder to
    // interpret than a short track.
    let infoWidth = min(
        min(150, max(0, availableWidth - gap)),
        max(128, availableWidth * 0.42)
    )
    let controlX = panel.minX + horizontalInset + infoWidth + gap
    let controlWidth = max(0, panel.maxX - horizontalInset - controlX)
    let percentageWidth = min(92, max(78, controlWidth * 0.20))
    // The threshold number is derived information, rather than a second input.
    // Reserve enough room to name its unit at normal widths, while allowing the
    // slider to remain usable in the compact inspector.
    let preferredTokenLimitWidth: CGFloat = 204
    let minimumTokenLimitWidth: CGFloat = 156
    let minimumSliderWidth: CGFloat = 110
    let tokenLimitWidth = min(
        preferredTokenLimitWidth,
        max(minimumTokenLimitWidth, controlWidth - percentageWidth - 16 - minimumSliderWidth)
    )
    let sliderWidth = max(0, controlWidth - percentageWidth - tokenLimitWidth - 16)

    return ModelRoutingContextControlsLayout(
        infoWidth: infoWidth,
        popupRect: NSRect(x: controlX, y: panel.minY + 55, width: controlWidth, height: 34),
        sliderRect: NSRect(x: controlX, y: panel.minY + 95, width: sliderWidth, height: 34),
        percentageRect: NSRect(x: controlX + sliderWidth + 8, y: panel.minY + 95, width: percentageWidth, height: 34),
        tokenLimitRect: NSRect(x: controlX + sliderWidth + percentageWidth + 16, y: panel.minY + 95, width: tokenLimitWidth, height: 34)
    )
}

private struct ModelRoutingGlobalColumns {
    let strategy: NSRect
    let context: NSRect
}

private func modelRoutingGlobalColumns(in row: NSRect) -> ModelRoutingGlobalColumns {
    let horizontalInset: CGFloat = 20
    let columnGap: CGFloat = 28
    let availableWidth = max(0, row.width - horizontalInset * 2 - columnGap)
    let strategyWidth = availableWidth / 2
    let strategy = NSRect(
        x: row.minX + horizontalInset,
        y: row.minY + 64,
        width: strategyWidth,
        height: 126
    )
    let context = NSRect(
        x: strategy.maxX + columnGap,
        y: strategy.minY,
        width: max(0, row.maxX - horizontalInset - strategy.maxX - columnGap),
        height: strategy.height
    )
    return ModelRoutingGlobalColumns(strategy: strategy, context: context)
}

private func modelRoutingGlobalContextControlsLayout(in column: NSRect) -> ModelRoutingContextControlsLayout {
    let infoWidth: CGFloat = 118
    let gap: CGFloat = 12
    let controlX = column.minX + infoWidth + gap
    let controlWidth = max(0, column.maxX - controlX)
    let percentageWidth = min(92, max(78, controlWidth * 0.20))
    let tokenLimitWidth = min(204, max(156, controlWidth - percentageWidth - 16 - 110))
    let sliderWidth = max(0, controlWidth - percentageWidth - tokenLimitWidth - 16)

    return ModelRoutingContextControlsLayout(
        infoWidth: infoWidth,
        popupRect: NSRect(x: controlX, y: column.minY, width: controlWidth, height: 34),
        sliderRect: NSRect(x: controlX, y: column.minY + 42, width: sliderWidth, height: 34),
        percentageRect: NSRect(x: controlX + sliderWidth + 8, y: column.minY + 42, width: percentageWidth, height: 34),
        tokenLimitRect: NSRect(x: controlX + sliderWidth + percentageWidth + 16, y: column.minY + 42, width: tokenLimitWidth, height: 34)
    )
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

private func modelRoutingActionRects(
    toolbar: NSRect,
    above inspector: NSRect
) -> (discard: NSRect, save: NSRect) {
    // Keep the actions immediately above the selected-project inspector. The
    // inspector can be much taller than the viewport, so its footer is not an
    // acceptable home for Save; placing the actions by the project card also
    // keeps them visually tied to the configuration being edited.
    let gap: CGFloat = 10
    let actionWidth: CGFloat = 126
    let discard = NSRect(
        x: inspector.maxX - actionWidth,
        y: toolbar.minY + 2,
        width: actionWidth,
        height: 30
    )
    let save = NSRect(
        x: discard.minX - gap - actionWidth,
        y: discard.minY,
        width: actionWidth,
        height: discard.height
    )
    return (discard, save)
}

struct ModelRoutingPageLayout {
    let globalRect: NSRect
    let toolbarRect: NSRect
    let projectListRect: NSRect
    let inspectorRect: NSRect
    let runStrategyRect: NSRect
    let contextRect: NSRect
    let planRect: NSRect
    let projectRows: [String: NSRect]
    let footerRect: NSRect
}

final class ModelRoutingControls: NSObject, NSSearchFieldDelegate {
    enum Scope: Hashable {
        case global
        case project(String)
    }

    enum Field: Equatable {
        case model
        case effort
        case contextWindow
        case autoCompactTokenLimit
        case planModeReasoningEffort
    }

    private enum ProjectSection: CaseIterable {
        case runStrategy
        case contextAndCompaction
        case planMode
    }

    private struct SectionInheritanceBinding {
        let projectID: String
        let section: ProjectSection
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
    private(set) var selectedProjectID: String?

    private let codexStore: CodexModelRoutingStore
    private let claudeStore: ClaudeModelRoutingStore
    private let protectionPreferences: CodexModelRoutingProtectionPreferences
    private let claudeProtectionPreferences: ClaudeModelRoutingProtectionPreferences
    private var configWatcher: CodexConfigWatcher?
    private weak var host: UsageDetailsView?
    private var bindings: [ObjectIdentifier: Binding] = [:]
    private var sectionInheritanceBindings: [ObjectIdentifier: SectionInheritanceBinding] = [:]
    private var draftSelections: [Scope: CodexConfigSelection] = [:]
    private var modelPopups: [Scope: NSPopUpButton] = [:]
    private var effortPopups: [Scope: NSPopUpButton] = [:]
    private var contextPopups: [Scope: NSPopUpButton] = [:]
    private var compressionSliders: [Scope: NSSlider] = [:]
    private var compressionPercentageFields: [Scope: NSTextField] = [:]
    private var sectionInheritanceCheckboxes: [ProjectSection: NSButton] = [:]
    private let searchField = NSTextField()
    private let searchIconView = NSImageView()
    private let filterControl = NSSegmentedControl(
        labels: ["", "", ""],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let codexPlatformButton = NSButton(title: "Codex", target: nil, action: nil)
    private let claudePlatformButton = NSButton(title: "Claude", target: nil, action: nil)
    private let protectionSwitch = NSSwitch(frame: .zero)
    private var planModeEffortPopups: [Scope: NSPopUpButton] = [:]
    private let refreshButton = NSButton(title: "", target: nil, action: nil)
    private let discardButton = NSButton(title: "", target: nil, action: nil)
    private let saveButton = NSButton(title: "", target: nil, action: nil)

    init(
        codexStore: CodexModelRoutingStore = CodexModelRoutingStore(),
        claudeStore: ClaudeModelRoutingStore = ClaudeModelRoutingStore(),
        protectionPreferences: CodexModelRoutingProtectionPreferences =
            CodexModelRoutingProtectionPreferences(),
        claudeProtectionPreferences: ClaudeModelRoutingProtectionPreferences =
            ClaudeModelRoutingProtectionPreferences()
    ) {
        self.codexStore = codexStore
        self.claudeStore = claudeStore
        self.protectionPreferences = protectionPreferences
        self.claudeProtectionPreferences = claudeProtectionPreferences
        if protectionPreferences.isEnabled {
            if let protected = protectionPreferences.protectedState() {
                _ = try? codexStore.restoreProtectedRoutingState(protected)
            } else {
                protectionPreferences.enable(capturing: codexStore.captureProtectedRoutingState())
            }
        }
        if claudeProtectionPreferences.isEnabled {
            if let protected = claudeProtectionPreferences.protectedState() {
                _ = try? claudeStore.restoreProtectedRoutingState(protected)
            } else {
                claudeProtectionPreferences.enable(capturing: claudeStore.captureProtectedRoutingState())
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

    private var isClaudeDefaultsProtectionEnabled: Bool {
        claudeProtectionPreferences.isEnabled
    }

    var isDefaultsProtectionEnabled: Bool {
        selectedPlatform == .codex
            ? isCodexDefaultsProtectionEnabled
            : isClaudeDefaultsProtectionEnabled
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

    private func setClaudeDefaultsProtectionEnabled(_ enabled: Bool) {
        if enabled {
            claudeProtectionPreferences.enable(capturing: claudeStore.captureProtectedRoutingState())
            statusMessage = localized(
                chinese: "已锁定 Token Meter 的 Claude 默认配置",
                english: "Token Meter's Claude defaults are now protected",
                japanese: "Token Meter の Claude 既定設定を保護しました"
            )
        } else {
            claudeProtectionPreferences.disable()
            statusMessage = localized(
                chinese: "已允许 Claude 更新默认配置",
                english: "Claude may now update defaults",
                japanese: "Claude による既定設定の更新を許可しました"
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
                    matchesFilter = !followsSystemConfiguration(project)
                case .inherited:
                    matchesFilter = followsSystemConfiguration(project)
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
                   followsSystemConfiguration(lhs.element) != followsSystemConfiguration(rhs.element) {
                    return !followsSystemConfiguration(lhs.element)
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    var selectedProject: CodexProjectRoutingSnapshot? {
        let projects = visibleProjects
        if let selectedProjectID,
           let project = projects.first(where: { $0.project.id == selectedProjectID }) {
            return project
        }
        return projects.first
    }

    func effectivePlanModeReasoningEffort(for project: CodexProjectRoutingSnapshot) -> String {
        let selection = displayedProjectSelection(project)
        return selection.planModeReasoningEffort
            ?? effectiveGlobalPlanModeReasoningEffort()
    }

    private func effectiveGlobalPlanModeReasoningEffort() -> String {
        displayedGlobalSelection.planModeReasoningEffort
            ?? preferredEffort(for: effectiveGlobalModel())
    }

    func compressionPercent(for project: CodexProjectRoutingSnapshot) -> Int {
        compressionPercent(for: displayedProjectSelection(project))
    }

    func compressionTokenLimitText(for project: CodexProjectRoutingSnapshot) -> String {
        let selection = displayedProjectSelection(project)
        let context = selection.contextWindow ?? displayedGlobalSelection.contextWindow ?? 258_400
        let limit = selection.autoCompactTokenLimit
            ?? displayedGlobalSelection.autoCompactTokenLimit
            ?? context * 85 / 100
        return formattedTokenCount(limit)
    }

    func globalCompressionPercent() -> Int {
        compressionPercent(for: displayedGlobalSelection)
    }

    func globalCompressionTokenLimitText() -> String {
        let selection = displayedGlobalSelection
        let context = selection.contextWindow ?? 258_400
        return formattedTokenCount(selection.autoCompactTokenLimit ?? context * 85 / 100)
    }

    private func compressionPercent(for selection: CodexConfigSelection) -> Int {
        let context = selection.contextWindow ?? displayedGlobalSelection.contextWindow ?? 258_400
        let limit = selection.autoCompactTokenLimit
            ?? displayedGlobalSelection.autoCompactTokenLimit
            ?? context * 85 / 100
        return max(1, min(99, Int((Double(limit) / Double(max(context, 1)) * 100).rounded())))
    }

    private func compressionSelection(for scope: Scope) -> CodexConfigSelection? {
        switch scope {
        case .global:
            return displayedGlobalSelection
        case let .project(id):
            guard let project = snapshot.projects.first(where: { $0.project.id == id }) else { return nil }
            return displayedProjectSelection(project)
        }
    }

    private func updateCompressionDraft(scope: Scope, percent: Int) -> Int? {
        guard let current = compressionSelection(for: scope) else { return nil }
        let context: Int
        switch scope {
        case .global:
            context = current.contextWindow ?? 258_400
        case .project:
            context = current.contextWindow ?? displayedGlobalSelection.contextWindow ?? 258_400
        }
        draftSelections[scope] = CodexConfigSelection(
            model: current.model ?? effectiveGlobalModel(),
            reasoningEffort: current.reasoningEffort ?? effectiveGlobalEffort(),
            contextWindow: context,
            autoCompactTokenLimit: context * percent / 100,
            planModeReasoningEffort: current.planModeReasoningEffort
        )
        return context
    }

    private func isProjectSectionInherited(
        _ section: ProjectSection,
        for project: CodexProjectRoutingSnapshot
    ) -> Bool {
        let selection = displayedProjectSelection(project)
        switch section {
        case .runStrategy:
            return selection.model == nil && selection.reasoningEffort == nil
        case .contextAndCompaction:
            return selection.contextWindow == nil && selection.autoCompactTokenLimit == nil
        case .planMode:
            return selection.planModeReasoningEffort == nil
        }
    }

    private func hasMixedValues(
        in section: ProjectSection,
        for project: CodexProjectRoutingSnapshot
    ) -> Bool {
        guard draftSelections[.project(project.project.id)] == nil else { return false }
        switch section {
        case .runStrategy:
            return project.model == .mixed || project.reasoningEffort == .mixed
        case .contextAndCompaction:
            return project.contextWindow == .mixed || project.autoCompactTokenLimit == .mixed
        case .planMode:
            return project.planModeReasoningEffort == .mixed
        }
    }

    func selectProject(id: String) {
        guard visibleProjects.contains(where: { $0.project.id == id }) else { return }
        selectedProjectID = id
        rebuildPopups()
        invalidateLayout()
    }

    func install(in host: UsageDetailsView) {
        self.host = host

        searchField.cell = SearchTextFieldCell(textCell: "")
        searchField.controlSize = .regular
        searchField.font = .systemFont(ofSize: 12, weight: .medium)
        searchField.appearance = NSAppearance(named: .darkAqua)
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.delegate = self
        searchField.isHidden = true
        host.addSubview(searchField)

        searchIconView.image = NSImage(
            systemSymbolName: "magnifyingglass",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        )
        searchIconView.contentTintColor = NSColor.white.withAlphaComponent(0.74)
        searchIconView.imageScaling = .scaleProportionallyDown
        searchIconView.isHidden = true
        host.addSubview(searchIconView)

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
        protectionSwitch.state = isDefaultsProtectionEnabled ? .on : .off
        protectionSwitch.target = self
        protectionSwitch.action = #selector(protectionChanged(_:))
        protectionSwitch.isHidden = true
        protectionSwitch.setAccessibilityLabel(
            localized(
                chinese: "锁定默认模型",
                english: "Protect default models",
                japanese: "既定モデルを保護"
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
        refreshButton.setAccessibilityLabel(
            localized(chinese: "刷新项目", english: "Refresh projects", japanese: "プロジェクトを更新")
        )
        host.addSubview(refreshButton)

        for button in [discardButton, saveButton] {
            button.isBordered = true
            button.bezelStyle = .rounded
            button.controlSize = .regular
            button.font = .systemFont(ofSize: 11.5, weight: .semibold)
            button.appearance = NSAppearance(named: .darkAqua)
            button.isHidden = true
            host.addSubview(button)
        }
        discardButton.target = self
        discardButton.action = #selector(discardRequested)
        discardButton.contentTintColor = NSColor.white.withAlphaComponent(0.76)
        discardButton.setAccessibilityLabel(
            localized(chinese: "放弃未保存的修改", english: "Discard unsaved changes", japanese: "未保存の変更を破棄")
        )
        saveButton.target = self
        saveButton.action = #selector(saveRequested)
        saveButton.isBordered = false
        saveButton.wantsLayer = true
        saveButton.layer?.cornerRadius = 7
        saveButton.layer?.masksToBounds = true
        saveButton.contentTintColor = .white
        saveButton.setAccessibilityLabel(
            localized(chinese: "保存配置", english: "Save configuration", japanese: "設定を保存")
        )

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
        if !visibleProjects.contains(where: { $0.project.id == selectedProjectID }) {
            selectedProjectID = visibleProjects.first?.project.id
        }
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

    /// Debug hook for a deterministic pending-save render. It never writes a
    /// local Codex or Claude configuration file.
    func configurePreviewUnsavedChange() {
        guard let project = snapshot.projects.first else { return }
        let model = snapshot.models.first(where: { $0.slug == "gpt-5.6-terra" })?.slug
            ?? effectiveGlobalModel()
        draftSelections[.project(project.project.id)] = CodexConfigSelection(
            model: model,
            reasoningEffort: preferredEffort(for: model)
        )
        statusMessage = localized(
            chinese: "有未保存的修改",
            english: "Unsaved changes",
            japanese: "未保存の変更があります"
        )
        statusIsError = false
        rebuildPopups()
        invalidateLayout()
    }

    func layout(in content: NSRect, visible: Bool) {
        let layout = host?.modelRoutingPageLayout(in: content)
        searchField.isHidden = !visible
        searchIconView.isHidden = !visible
        filterControl.isHidden = true
        codexPlatformButton.isHidden = !visible
        claudePlatformButton.isHidden = !visible
        protectionSwitch.isHidden = true
        refreshButton.isHidden = !visible
        discardButton.isHidden = !visible
        saveButton.isHidden = !visible

        for popup in modelPopups.values {
            popup.isHidden = true
        }
        for popup in effortPopups.values {
            popup.isHidden = true
        }
        for popup in contextPopups.values {
            popup.isHidden = true
        }
        for slider in compressionSliders.values {
            slider.isHidden = true
        }
        for field in compressionPercentageFields.values {
            field.isHidden = true
        }
        for checkbox in sectionInheritanceCheckboxes.values {
            checkbox.isHidden = true
        }
        for popup in planModeEffortPopups.values {
            popup.isHidden = true
        }
        guard visible, let layout else { return }

        let platformRects = modelRoutingPlatformRects(in: content)
        codexPlatformButton.frame = platformRects[.codex] ?? .zero
        claudePlatformButton.frame = platformRects[.claude] ?? .zero
        searchField.placeholderString = localized(
            chinese: "搜索项目",
            english: "Search projects",
            japanese: "プロジェクトを検索"
        )
        searchField.setAccessibilityLabel(searchField.placeholderString ?? "")
        let searchRect = modelRoutingSearchRect(in: layout.toolbarRect)
        searchField.frame = searchRect
            .insetBy(dx: 7, dy: 0)
        searchIconView.frame = NSRect(
            x: searchRect.minX + 12,
            y: searchRect.midY - 10,
            width: 20,
            height: 20
        )

        refreshButton.title = localized(
            chinese: "刷新项目",
            english: "Refresh projects",
            japanese: "プロジェクトを更新"
        )
        refreshButton.frame = NSRect(
            x: layout.footerRect.minX,
            y: layout.footerRect.minY + 10,
            width: 104,
            height: 32
        )

        let actionRects = modelRoutingActionRects(
            toolbar: layout.toolbarRect,
            above: layout.inspectorRect
        )

        discardButton.title = localized(chinese: "放弃", english: "Discard", japanese: "破棄")
        discardButton.frame = actionRects.discard
        discardButton.isEnabled = hasUnsavedChanges
        discardButton.alphaValue = hasUnsavedChanges ? 1 : 0.42

        saveButton.title = hasUnsavedChanges
            ? localized(
                chinese: "保存配置（\(unsavedChangeCount)）",
                english: "Save (\(unsavedChangeCount))",
                japanese: "設定を保存（\(unsavedChangeCount)）"
            )
            : localized(chinese: "保存配置", english: "Save configuration", japanese: "設定を保存")
        saveButton.frame = actionRects.save
        saveButton.isEnabled = hasUnsavedChanges
        saveButton.alphaValue = hasUnsavedChanges ? 1 : 0.42
        saveButton.layer?.backgroundColor = (
            hasUnsavedChanges
                ? host?.accentBlue.withAlphaComponent(0.88)
                : host?.inputSurfaceColor.withAlphaComponent(0.70)
        )?.cgColor

        layoutGlobalPopups(in: layout.globalRect)
        if let project = selectedProject {
            layoutSelectedProjectControls(project: project, layout: layout)
            layoutSectionInheritanceCheckboxes(project: project, layout: layout)
        }
    }

    func effectiveGlobalModel() -> String {
        if let model = displayedGlobalSelection.model {
            return model
        }
        return snapshot.models.first?.slug ?? "gpt-5.6-terra"
    }

    func effectiveGlobalEffort() -> String {
        displayedGlobalSelection.reasoningEffort
            ?? modelOption(slug: effectiveGlobalModel())?.defaultReasoningEffort
            ?? "medium"
    }

    func followsSystemConfiguration(_ project: CodexProjectRoutingSnapshot) -> Bool {
        project.inheritsEverything
    }

    func modelOption(slug: String?) -> CodexModelOption? {
        guard let slug else { return nil }
        return snapshot.models.first { $0.slug == slug }
    }

    var platformDisplayName: String {
        selectedPlatform == .codex ? "Codex" : "Claude"
    }

    var hasUnsavedChanges: Bool {
        !draftSelections.isEmpty
    }

    var unsavedChangeCount: Int {
        draftSelections.count
    }

    private var displayedGlobalSelection: CodexConfigSelection {
        draftSelections[.global] ?? snapshot.global
    }

    private func loadActiveSnapshot() -> CodexModelRoutingSnapshot {
        switch selectedPlatform {
        case .codex:
            return codexStore.loadSnapshot()
        case .claude:
            return claudeStore.loadSnapshot()
        }
    }

    private func displayedProjectSelection(_ project: CodexProjectRoutingSnapshot) -> CodexConfigSelection {
        let scope = Scope.project(project.project.id)
        if let draft = draftSelections[scope] {
            return draft
        }
        return CodexConfigSelection(
            model: project.model.explicitValue,
            reasoningEffort: project.reasoningEffort.explicitValue,
            contextWindow: project.contextWindow.explicitValue.flatMap(Int.init),
            autoCompactTokenLimit: project.autoCompactTokenLimit.explicitValue.flatMap(Int.init),
            planModeReasoningEffort: project.planModeReasoningEffort.explicitValue
        )
    }

    private func writeGlobal(_ selection: CodexConfigSelection) throws {
        switch selectedPlatform {
        case .codex:
            guard let model = selection.model, !model.isEmpty else {
                throw CodexModelRoutingStoreError.missingGlobalDefault("model")
            }
            guard let reasoningEffort = selection.reasoningEffort, !reasoningEffort.isEmpty else {
                throw CodexModelRoutingStoreError.missingGlobalDefault("model_reasoning_effort")
            }
            try codexStore.writeGlobal(selection)
        case .claude:
            try claudeStore.writeGlobal(model: selection.model ?? "", reasoningEffort: selection.reasoningEffort)
        }
    }

    private func writeProject(id: String, selection: CodexConfigSelection) throws {
        switch selectedPlatform {
        case .codex:
            try codexStore.writeProject(id: id, selection: selection)
        case .claude:
            try claudeStore.writeProject(
                id: id,
                model: selection.model,
                reasoningEffort: selection.reasoningEffort
            )
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === searchField else { return }
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
        if selectedPlatform == .codex {
            setCodexDefaultsProtectionEnabled(sender.state == .on)
        } else {
            setClaudeDefaultsProtectionEnabled(sender.state == .on)
        }
    }

    @objc private func refreshRequested() {
        let previousProjectIDs = Set(snapshot.projects.map(\.project.id))
        statusMessage = nil
        statusIsError = false
        reload()
        let discovered = snapshot.projects.count
        let added = snapshot.projects.filter { !previousProjectIDs.contains($0.project.id) }.count
        statusMessage = localized(
            chinese: added > 0 ? "已刷新 \(discovered) 个项目，新增 \(added) 个" : "已刷新 \(discovered) 个项目",
            english: added > 0 ? "Refreshed \(discovered) projects, found \(added) new" : "Refreshed \(discovered) projects",
            japanese: added > 0 ? "\(discovered) 件を更新、\(added) 件を追加" : "\(discovered) 件のプロジェクトを更新"
        )
        invalidateLayout()
    }

    private func handleExternalConfigChange() {
        let isCodex = selectedPlatform == .codex
        // Codex restoration is owned by the app-lifetime controller because it
        // must preserve the task-scoped override grace period. Restoring here
        // would race that controller and immediately undo the Desktop picker.
        if !isCodex, let protected = claudeProtectionPreferences.protectedState() {
            do {
                let restored = try claudeStore.restoreProtectedRoutingState(protected)
                if restored {
                    statusMessage = localized(
                        chinese: "已恢复 Token Meter 的 Claude 默认配置",
                        english: "Restored Token Meter's Claude defaults",
                        japanese: "Token Meter の Claude 既定設定を復元しました"
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
                draftSelections[.global] = try proposedGlobalChange(field: binding.field, sender: sender)
            case let .project(id):
                draftSelections[binding.scope] = try proposedProjectChange(
                    id: id,
                    field: binding.field,
                    sender: sender
                )
            }
            statusMessage = localized(
                chinese: "有未保存的修改",
                english: "Unsaved changes",
                japanese: "未保存の変更があります"
            )
            statusIsError = false
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
        rebuildPopups()
        invalidateLayout()
    }

    @objc private func compressionSliderChanged(_ sender: NSSlider) {
        guard let binding = bindings[ObjectIdentifier(sender)] else { return }
        let percent = max(5, min(95, Int((Double(sender.integerValue) / 5).rounded()) * 5))
        sender.integerValue = percent
        guard let context = updateCompressionDraft(scope: binding.scope, percent: percent) else { return }
        statusMessage = localized(chinese: "有未保存的修改", english: "Unsaved changes", japanese: "未保存の変更があります")
        statusIsError = false
        configureCompressionPercentageField(compressionPercentageFields[binding.scope], percent: percent)
        sender.toolTip = "\(percent)% · \(formattedTokenCount(context * percent / 100))"
        invalidateLayout()
    }

    @objc private func compressionPercentageChanged(_ sender: NSTextField) {
        guard let binding = bindings[ObjectIdentifier(sender)] else { return }
        let rawValue = sender.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "%", with: "")
        guard let percent = Int(rawValue), (1...99).contains(percent) else {
            statusMessage = localized(
                chinese: "请输入 1 到 99 的整数百分比",
                english: "Enter a whole percentage from 1 to 99",
                japanese: "1 から 99 の整数パーセントを入力してください"
            )
            statusIsError = true
            configureCompressionPercentageField(
                sender,
                percent: compressionSelection(for: binding.scope).map(compressionPercent(for:)) ?? 85
            )
            invalidateLayout()
            return
        }

        guard let context = updateCompressionDraft(scope: binding.scope, percent: percent) else { return }
        statusMessage = localized(chinese: "有未保存的修改", english: "Unsaved changes", japanese: "未保存の変更があります")
        statusIsError = false
        configureCompressionPercentageField(sender, percent: percent)
        if let slider = compressionSliders[binding.scope] {
            let sliderPercent = max(5, min(95, Int((Double(percent) / 5).rounded()) * 5))
            slider.integerValue = sliderPercent
            slider.toolTip = "\(percent)% · \(formattedTokenCount(context * percent / 100))"
        }
        invalidateLayout()
    }

    @objc private func sectionInheritanceChanged(_ sender: NSButton) {
        guard let binding = sectionInheritanceBindings[ObjectIdentifier(sender)],
              let project = snapshot.projects.first(where: { $0.project.id == binding.projectID }) else {
            return
        }
        let scope = Scope.project(binding.projectID)
        let current = displayedProjectSelection(project)
        var updated = current
        if sender.state == .on {
            switch binding.section {
            case .runStrategy:
                updated.model = nil
                updated.reasoningEffort = nil
            case .contextAndCompaction:
                updated.contextWindow = nil
                updated.autoCompactTokenLimit = nil
            case .planMode:
                updated.planModeReasoningEffort = nil
            }
        } else {
            switch binding.section {
            case .runStrategy:
                updated.model = current.model ?? effectiveGlobalModel()
                updated.reasoningEffort = current.reasoningEffort ?? effectiveGlobalEffort()
            case .contextAndCompaction:
                let context = current.contextWindow
                    ?? displayedGlobalSelection.contextWindow
                    ?? 258_400
                updated.contextWindow = context
                updated.autoCompactTokenLimit = current.autoCompactTokenLimit
                    ?? displayedGlobalSelection.autoCompactTokenLimit
                    ?? context * 85 / 100
            case .planMode:
                updated.planModeReasoningEffort = current.planModeReasoningEffort
                    ?? effectiveGlobalPlanModeReasoningEffort()
            }
        }
        draftSelections[scope] = updated
        statusMessage = localized(
            chinese: "有未保存的修改",
            english: "Unsaved changes",
            japanese: "未保存の変更があります"
        )
        statusIsError = false
        rebuildPopups()
        invalidateLayout()
    }

    @objc private func discardRequested() {
        guard hasUnsavedChanges else { return }
        draftSelections.removeAll()
        statusMessage = localized(chinese: "已放弃未保存的修改", english: "Discarded unsaved changes", japanese: "未保存の変更を破棄しました")
        statusIsError = false
        reload()
    }

    @objc private func saveRequested() {
        guard hasUnsavedChanges else { return }
        let drafts = draftSelections
        let savedChangeCount = drafts.count
        do {
            if let global = drafts[.global] {
                guard let model = global.model, !model.isEmpty else {
                    throw CodexModelRoutingStoreError.missingGlobalDefault("model")
                }
                try writeGlobal(global)
            }
            for (scope, selection) in drafts {
                guard case let .project(id) = scope else { continue }
                try writeProject(id: id, selection: selection)
            }
            draftSelections.removeAll()
            recordProtectedCodexDefaultsIfNeeded()
            statusMessage = localized(
                chinese: "已保存 \(savedChangeCount) 项配置；新建聊天后生效",
                english: "Saved \(savedChangeCount) configuration changes; applies to new chats",
                japanese: "\(savedChangeCount) 件の設定を保存しました。新しい会話から有効です"
            )
            statusIsError = false
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
        reload()
    }

    private func recordProtectedCodexDefaultsIfNeeded() {
        if selectedPlatform == .codex, protectionPreferences.isEnabled {
            protectionPreferences.updateProtectedState(codexStore.captureProtectedRoutingState())
        } else if selectedPlatform == .claude, claudeProtectionPreferences.isEnabled {
            claudeProtectionPreferences.updateProtectedState(claudeStore.captureProtectedRoutingState())
        }
    }

    private func invalidateLayout() {
        host?.onPreferredHeightChanged?()
        host?.needsDisplay = true
        host?.needsLayout = true
    }

    private func proposedGlobalChange(field: Field, sender: NSPopUpButton) throws -> CodexConfigSelection {
        var model = displayedGlobalSelection.model ?? effectiveGlobalModel()
        var effort: String? = displayedGlobalSelection.reasoningEffort
            ?? modelOption(slug: model)?.defaultReasoningEffort
        var contextWindow = displayedGlobalSelection.contextWindow
        var autoCompactTokenLimit = displayedGlobalSelection.autoCompactTokenLimit
        var planModeReasoningEffort = displayedGlobalSelection.planModeReasoningEffort
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
        case .contextWindow:
            contextWindow = Int(value)
            if let contextWindow, (autoCompactTokenLimit ?? 0) >= contextWindow {
                autoCompactTokenLimit = contextWindow * 85 / 100
            }
        case .autoCompactTokenLimit:
            autoCompactTokenLimit = Int(value)
        case .planModeReasoningEffort:
            planModeReasoningEffort = value == modelRoutingBuiltInPlanDefaultValue ? nil : value
        }
        guard !model.isEmpty else {
            throw CodexModelRoutingStoreError.missingGlobalDefault("model")
        }
        if selectedPlatform == .codex, effort?.isEmpty != false {
            throw CodexModelRoutingStoreError.missingGlobalDefault("model_reasoning_effort")
        }
        return CodexConfigSelection(
            model: model,
            reasoningEffort: effort,
            contextWindow: contextWindow,
            autoCompactTokenLimit: autoCompactTokenLimit,
            planModeReasoningEffort: planModeReasoningEffort
        )
    }

    private func proposedProjectChange(id: String, field: Field, sender: NSPopUpButton) throws -> CodexConfigSelection {
        guard let project = snapshot.projects.first(where: { $0.project.id == id }) else {
            throw CodexModelRoutingStoreError.missingProject(id)
        }
        let current = displayedProjectSelection(project)
        if field == .planModeReasoningEffort {
            return CodexConfigSelection(
                model: current.model,
                reasoningEffort: current.reasoningEffort,
                contextWindow: current.contextWindow,
                autoCompactTokenLimit: current.autoCompactTokenLimit,
                planModeReasoningEffort: selectedValue(in: sender) == modelRoutingBuiltInPlanDefaultValue
                    ? nil
                    : selectedValue(in: sender)
            )
        }
        var model = current.model ?? effectiveGlobalModel()
        var effort: String? = current.reasoningEffort ?? effectiveGlobalEffort()
        var contextWindow = current.contextWindow ?? displayedGlobalSelection.contextWindow
        var autoCompactTokenLimit = current.autoCompactTokenLimit ?? displayedGlobalSelection.autoCompactTokenLimit
        let planModeReasoningEffort = current.planModeReasoningEffort
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
        case .contextWindow:
            contextWindow = Int(value)
            if let contextWindow, (autoCompactTokenLimit ?? 0) >= contextWindow {
                autoCompactTokenLimit = contextWindow * 85 / 100
            }
        case .autoCompactTokenLimit:
            autoCompactTokenLimit = Int(value)
        case .planModeReasoningEffort:
            break
        }
        return CodexConfigSelection(
            model: model,
            reasoningEffort: effort,
            contextWindow: contextWindow,
            autoCompactTokenLimit: autoCompactTokenLimit,
            planModeReasoningEffort: planModeReasoningEffort
        )
    }

    private func rebuildPopups() {
        for popup in modelPopups.values {
            popup.removeFromSuperview()
        }
        for popup in effortPopups.values {
            popup.removeFromSuperview()
        }
        for popup in contextPopups.values {
            popup.removeFromSuperview()
        }
        for slider in compressionSliders.values {
            slider.removeFromSuperview()
        }
        for field in compressionPercentageFields.values {
            field.removeFromSuperview()
        }
        for checkbox in sectionInheritanceCheckboxes.values {
            checkbox.removeFromSuperview()
        }
        for popup in planModeEffortPopups.values {
            popup.removeFromSuperview()
        }
        bindings.removeAll()
        sectionInheritanceBindings.removeAll()
        modelPopups.removeAll()
        effortPopups.removeAll()
        contextPopups.removeAll()
        compressionSliders.removeAll()
        compressionPercentageFields.removeAll()
        sectionInheritanceCheckboxes.removeAll()
        planModeEffortPopups.removeAll()

        installPopups(scope: .global, project: nil)
        for project in snapshot.projects {
            installPopups(scope: .project(project.project.id), project: project)
        }
        if selectedPlatform == .codex,
           let project = selectedProject,
           let host {
            for section in ProjectSection.allCases {
                let checkbox = makeSectionInheritanceCheckbox(project: project, section: section)
                sectionInheritanceCheckboxes[section] = checkbox
                sectionInheritanceBindings[ObjectIdentifier(checkbox)] = SectionInheritanceBinding(
                    projectID: project.project.id,
                    section: section
                )
                host.addSubview(checkbox)
            }
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

        if selectedPlatform == .codex {
            let planEffortPopup = makePopup()
            planModeEffortPopups[scope] = planEffortPopup
            bindings[ObjectIdentifier(planEffortPopup)] = Binding(
                scope: scope,
                field: .planModeReasoningEffort
            )
            host.addSubview(planEffortPopup)
        }

        let supportsContextControls = project != nil || (scope == .global && selectedPlatform == .codex)
        if supportsContextControls {
            let contextPopup = makePopup()
            let compressionSlider = makeCompressionSlider()
            let compressionPercentageField = makeCompressionPercentageField()
            contextPopups[scope] = contextPopup
            compressionSliders[scope] = compressionSlider
            compressionPercentageFields[scope] = compressionPercentageField
            bindings[ObjectIdentifier(contextPopup)] = Binding(scope: scope, field: .contextWindow)
            bindings[ObjectIdentifier(compressionSlider)] = Binding(scope: scope, field: .autoCompactTokenLimit)
            bindings[ObjectIdentifier(compressionPercentageField)] = Binding(scope: scope, field: .autoCompactTokenLimit)
            host.addSubview(contextPopup)
            host.addSubview(compressionSlider)
            host.addSubview(compressionPercentageField)
        }

        let selectedModel: CodexProjectConfigValue
        let selectedEffort: CodexProjectConfigValue
        if let project {
            if let selection = draftSelections[scope] {
                selectedModel = selection.model.map(CodexProjectConfigValue.value) ?? .inherited
                selectedEffort = selection.reasoningEffort.map(CodexProjectConfigValue.value) ?? .inherited
            } else {
                selectedModel = project.model
                selectedEffort = project.reasoningEffort
            }
        } else {
            selectedModel = displayedGlobalSelection.model.map(CodexProjectConfigValue.value) ?? .inherited
            selectedEffort = displayedGlobalSelection.reasoningEffort.map(CodexProjectConfigValue.value) ?? .inherited
        }
        configureModelPopup(modelPopup, selected: selectedModel)
        configureEffortPopup(
            effortPopup,
            scope: scope,
            selectedModel: selectedModel,
            selectedEffort: selectedEffort
        )

        if let project {
            let selectedContext: CodexProjectConfigValue
            let selectedCompression: CodexProjectConfigValue
            if let selection = draftSelections[scope] {
                selectedContext = selection.contextWindow.map { .value(String($0)) } ?? .inherited
                selectedCompression = selection.autoCompactTokenLimit.map { .value(String($0)) } ?? .inherited
            } else {
                selectedContext = project.contextWindow
                selectedCompression = project.autoCompactTokenLimit
            }
            configureContextPopup(contextPopups[scope], selected: selectedContext)
            configureCompressionSlider(
                compressionSliders[scope],
                context: selectedContext,
                selected: selectedCompression
            )
            configureCompressionPercentageField(
                compressionPercentageFields[scope],
                percent: compressionPercent(for: project)
            )
            let strategyEnabled = !isProjectSectionInherited(.runStrategy, for: project)
                && !hasMixedValues(in: .runStrategy, for: project)
            let contextEnabled = !isProjectSectionInherited(.contextAndCompaction, for: project)
                && !hasMixedValues(in: .contextAndCompaction, for: project)
            let planEnabled = !isProjectSectionInherited(.planMode, for: project)
                && !hasMixedValues(in: .planMode, for: project)
            modelPopup.isEnabled = strategyEnabled
            effortPopup.isEnabled = strategyEnabled && modelSupportsEffort(
                selectedModel.explicitValue ?? effectiveGlobalModel()
            )
            contextPopups[scope]?.isEnabled = contextEnabled && selectedPlatform == .codex
            compressionSliders[scope]?.isEnabled = contextEnabled && selectedPlatform == .codex
            compressionPercentageFields[scope]?.isEnabled = contextEnabled && selectedPlatform == .codex
            planModeEffortPopups[scope]?.isEnabled = planEnabled && selectedPlatform == .codex
            configurePlanModeEffortPopup(planModeEffortPopups[scope], scope: scope, project: project)
            modelPopup.alphaValue = strategyEnabled ? 1 : 0.52
            effortPopup.alphaValue = effortPopup.isEnabled ? 1 : 0.52
            contextPopups[scope]?.alphaValue = contextPopups[scope]?.isEnabled == true ? 1 : 0.52
            compressionSliders[scope]?.alphaValue = compressionSliders[scope]?.isEnabled == true ? 1 : 0.52
            compressionPercentageFields[scope]?.alphaValue = compressionPercentageFields[scope]?.isEnabled == true ? 1 : 0.52
            planModeEffortPopups[scope]?.alphaValue = planModeEffortPopups[scope]?.isEnabled == true ? 1 : 0.52
        } else {
            effortPopup.isEnabled = modelSupportsEffort(
                snapshot.global.model ?? effectiveGlobalModel()
            )
            effortPopup.alphaValue = effortPopup.isEnabled ? 1 : 0.52
            if selectedPlatform == .codex {
                let globalSelection = displayedGlobalSelection
                let selectedContext = globalSelection.contextWindow.map { CodexProjectConfigValue.value(String($0)) } ?? .inherited
                let selectedCompression = globalSelection.autoCompactTokenLimit.map { CodexProjectConfigValue.value(String($0)) } ?? .inherited
                configureContextPopup(contextPopups[scope], selected: selectedContext)
                configureCompressionSlider(
                    compressionSliders[scope],
                    context: selectedContext,
                    selected: selectedCompression
                )
                configureCompressionPercentageField(
                    compressionPercentageFields[scope],
                    percent: globalCompressionPercent()
                )
                contextPopups[scope]?.isEnabled = true
                compressionSliders[scope]?.isEnabled = true
                compressionPercentageFields[scope]?.isEnabled = true
            }
            configurePlanModeEffortPopup(planModeEffortPopups[scope], scope: scope, project: nil)
            planModeEffortPopups[scope]?.isEnabled = true
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

    private func makeSectionInheritanceCheckbox(
        project: CodexProjectRoutingSnapshot,
        section: ProjectSection
    ) -> NSButton {
        let checkbox = NSButton(
            checkboxWithTitle: localized(
                chinese: "跟随全局默认",
                english: "Follow global default",
                japanese: "グローバル既定値に従う"
            ),
            target: self,
            action: #selector(sectionInheritanceChanged(_:))
        )
        checkbox.controlSize = .small
        checkbox.font = .systemFont(ofSize: 10, weight: .medium)
        checkbox.appearance = NSAppearance(named: .darkAqua)
        let followsGlobal = isProjectSectionInherited(section, for: project)
        checkbox.state = followsGlobal ? .on : .off
        checkbox.toolTip = followsGlobal
            ? localized(
                chinese: "此分区使用全局默认值；取消勾选可复制当前默认值并单独修改。",
                english: "This section uses the global default. Uncheck to copy that value and customize it.",
                japanese: "このセクションはグローバル既定値を使用します。チェックを外すと現在の既定値をコピーして個別に変更できます。"
            )
            : localized(
                chinese: "此分区使用项目自定义值；勾选后会移除该分区的项目覆盖。",
                english: "This section has a project override. Checking removes only this section's override.",
                japanese: "このセクションはプロジェクト上書きを使用中です。チェックするとこのセクションの上書きだけを削除します。"
            )
        checkbox.setAccessibilityLabel(
            localized(
                chinese: "\(project.project.name) 此分区跟随全局默认",
                english: "\(project.project.name) section follows global default",
                japanese: "\(project.project.name) のこのセクションはグローバル既定値に従う"
            )
        )
        checkbox.isHidden = true
        return checkbox
    }

    private func layoutSectionInheritanceCheckboxes(
        project: CodexProjectRoutingSnapshot,
        layout: ModelRoutingPageLayout
    ) {
        guard selectedPlatform == .codex else { return }
        let panels: [(ProjectSection, NSRect)] = [
            (.runStrategy, layout.runStrategyRect),
            (.contextAndCompaction, layout.contextRect),
            (.planMode, layout.planRect),
        ]
        for (section, panel) in panels {
            guard let checkbox = sectionInheritanceCheckboxes[section] else { continue }
            checkbox.frame = NSRect(
                x: panel.maxX - 145,
                y: panel.minY + 12,
                width: 129,
                height: 24
            )
            checkbox.state = isProjectSectionInherited(section, for: project) ? .on : .off
            checkbox.isHidden = false
        }
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

    private func configurePlanModeEffortPopup(
        _ popup: NSPopUpButton?,
        scope: Scope,
        project: CodexProjectRoutingSnapshot?
    ) {
        guard let popup else { return }
        popup.removeAllItems()
        let model: String
        let selected: String?
        if let project {
            model = displayedProjectSelection(project).model ?? effectiveGlobalModel()
            selected = displayedProjectSelection(project).planModeReasoningEffort
            if selected == nil, displayedGlobalSelection.planModeReasoningEffort == nil {
                addItem(
                    to: popup,
                    title: localized(
                        chinese: "Codex 内置 Plan 默认（不单独设置）",
                        english: "Codex built-in Plan default",
                        japanese: "Codex 内蔵の Plan 既定値"
                    ),
                    value: modelRoutingBuiltInPlanDefaultValue
                )
            }
        } else {
            model = effectiveGlobalModel()
            selected = displayedGlobalSelection.planModeReasoningEffort
            addItem(
                to: popup,
                title: localized(
                    chinese: "Codex 内置 Plan 默认（不单独设置）",
                    english: "Codex built-in Plan default",
                    japanese: "Codex 内蔵の Plan 既定値"
                ),
                value: modelRoutingBuiltInPlanDefaultValue
            )
        }
        var efforts = modelOption(slug: model)?.supportedReasoningEfforts ?? fallbackEfforts
        if let selected, !efforts.contains(selected) {
            efforts.append(selected)
        }
        for effort in efforts {
            addItem(to: popup, title: effort, value: effort)
        }
        let effective = selected
            ?? (displayedGlobalSelection.planModeReasoningEffort == nil
                ? modelRoutingBuiltInPlanDefaultValue
                : effectiveGlobalPlanModeReasoningEffort())
        select(value: effective, in: popup)
        popup.setAccessibilityLabel(
            localized(chinese: "Plan 思考强度", english: "Plan reasoning effort", japanese: "プラン思考強度")
        )
        popup.toolTip = project == nil
            ? localized(
                chinese: "设置所有未覆盖项目的 Plan 思考强度；Plan 使用运行策略模型。",
                english: "Sets Plan reasoning effort for projects without an override. Plan uses the run-strategy model.",
                japanese: "未上書きプロジェクトの Plan 思考強度を設定します。Plan は実行戦略モデルを使用します。"
            )
            : localized(
                chinese: "写入此项目的 .codex/config.toml；新建 Plan 后生效。",
                english: "Writes this project's .codex/config.toml; applies to new Plans.",
                japanese: "このプロジェクトの .codex/config.toml に保存し、新しいプランから有効です。"
            )
    }

    private func configureContextPopup(_ popup: NSPopUpButton?, selected: CodexProjectConfigValue) {
        guard let popup else { return }
        popup.removeAllItems()
        let values = [128_000, 258_400, 512_000, 1_000_000]
        for value in values {
            addItem(to: popup, title: compactContextTokenCount(value), value: String(value))
        }
        let explicit = selected.explicitValue ?? displayedGlobalSelection.contextWindow.map(String.init)
        if let explicit, !values.contains(Int(explicit) ?? -1) {
            addItem(to: popup, title: compactContextTokenCount(Int(explicit) ?? 0), value: explicit)
        }
        select(value: explicit ?? String(values[1]), in: popup)
        popup.setAccessibilityLabel(localized(chinese: "有效上下文窗口", english: "Context window", japanese: "コンテキストウィンドウ"))
    }

    private func configureCompressionSlider(
        _ slider: NSSlider?,
        context: CodexProjectConfigValue,
        selected: CodexProjectConfigValue
    ) {
        guard let slider else { return }
        let contextValue = Int(context.explicitValue ?? "")
            ?? displayedGlobalSelection.contextWindow
            ?? 258_400
        let tokenLimit = Int(selected.explicitValue ?? "")
            ?? displayedGlobalSelection.autoCompactTokenLimit
            ?? contextValue * 85 / 100
        let percent = max(1, min(99, Int((Double(tokenLimit) / Double(max(contextValue, 1)) * 100).rounded())))
        let sliderPercent = max(5, min(95, Int((Double(percent) / 5).rounded()) * 5))
        slider.integerValue = sliderPercent
        slider.toolTip = "\(percent)% · \(formattedTokenCount(contextValue * percent / 100))"
    }

    private func makeCompressionSlider() -> NSSlider {
        let slider = NSSlider(value: 85, minValue: 5, maxValue: 95, target: self, action: #selector(compressionSliderChanged(_:)))
        slider.numberOfTickMarks = 0
        slider.allowsTickMarkValuesOnly = false
        slider.isContinuous = true
        slider.controlSize = .small
        slider.appearance = NSAppearance(named: .darkAqua)
        slider.isHidden = true
        slider.setAccessibilityLabel(localized(chinese: "自动压缩阈值百分比", english: "Auto-compaction percentage", japanese: "自動圧縮しきい値の割合"))
        return slider
    }

    private func makeCompressionPercentageField() -> NSTextField {
        let field = NSTextField()
        field.cell = CompressionPercentageTextFieldCell(textCell: "")
        field.alignment = .center
        field.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .bold)
        field.textColor = NSColor.white.withAlphaComponent(0.92)
        field.backgroundColor = .clear
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.appearance = NSAppearance(named: .darkAqua)
        field.target = self
        field.action = #selector(compressionPercentageChanged(_:))
        field.toolTip = localized(
            chinese: "可输入任意整数百分比（1–99）",
            english: "Enter any whole percentage from 1 to 99",
            japanese: "1 から 99 までの任意の整数パーセントを入力できます"
        )
        field.setAccessibilityLabel(localized(chinese: "自动压缩阈值百分比", english: "Auto-compaction percentage", japanese: "自動圧縮しきい値の割合"))
        field.isHidden = true
        return field
    }

    private func configureCompressionPercentageField(_ field: NSTextField?, percent: Int) {
        field?.stringValue = "\(percent)%"
    }

    private func formattedTokenCount(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func compactContextTokenCount(_ value: Int) -> String {
        let valueInThousands = Double(value) / 1_000
        let formatted = valueInThousands.rounded() == valueInThousands
            ? String(Int(valueInThousands))
            : String(format: "%.1f", valueInThousands)
        return "\(formatted)K"
    }

    private func layoutGlobalPopups(in row: NSRect) {
        if selectedPlatform == .codex {
            let columns = modelRoutingGlobalColumns(in: row)
            let strategyLabelWidth: CGFloat = 96
            let strategyControlX = columns.strategy.minX + strategyLabelWidth + 12
            let strategyControlWidth = max(0, columns.strategy.maxX - strategyControlX)
            modelPopups[.global]?.frame = NSRect(
                x: strategyControlX,
                y: columns.strategy.minY,
                width: strategyControlWidth,
                height: 34
            )
            effortPopups[.global]?.frame = NSRect(
                x: strategyControlX,
                y: columns.strategy.minY + 42,
                width: strategyControlWidth,
                height: 34
            )
            modelPopups[.global]?.isHidden = false
            effortPopups[.global]?.isHidden = false

            let contextLayout = modelRoutingGlobalContextControlsLayout(in: columns.context)
            contextPopups[.global]?.frame = contextLayout.popupRect
            compressionSliders[.global]?.frame = contextLayout.sliderRect
            compressionPercentageFields[.global]?.frame = contextLayout.percentageRect
            contextPopups[.global]?.isHidden = false
            compressionSliders[.global]?.isHidden = false
            compressionPercentageFields[.global]?.isHidden = false
            let planPopupY = columns.strategy.minY + 84
            planModeEffortPopups[.global]?.frame = NSRect(
                x: strategyControlX,
                y: planPopupY,
                width: strategyControlWidth,
                height: 34
            )
            planModeEffortPopups[.global]?.isHidden = false
            return
        }

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
        planModeEffortPopups[.global]?.isHidden = true
    }

    private func layoutSelectedProjectControls(project: CodexProjectRoutingSnapshot, layout: ModelRoutingPageLayout) {
        let scope = Scope.project(project.project.id)
        let panel = layout.runStrategyRect
        let labelWidth = min(132, max(96, panel.width * 0.38))
        let controlX = panel.minX + labelWidth + 12
        let controlWidth = max(0, panel.maxX - controlX - 16)
        modelPopups[scope]?.frame = NSRect(x: controlX, y: panel.minY + 61, width: controlWidth, height: 34)
        effortPopups[scope]?.frame = NSRect(x: controlX, y: panel.minY + 107, width: controlWidth, height: 34)
        modelPopups[scope]?.isHidden = false
        effortPopups[scope]?.isHidden = false
        let contextPanel = layout.contextRect
        let contextLayout = modelRoutingContextControlsLayout(in: contextPanel)
        contextPopups[scope]?.frame = contextLayout.popupRect
        compressionSliders[scope]?.frame = contextLayout.sliderRect
        compressionPercentageFields[scope]?.frame = contextLayout.percentageRect
        contextPopups[scope]?.isHidden = false
        compressionSliders[scope]?.isHidden = false
        compressionPercentageFields[scope]?.isHidden = false
        planModeEffortPopups[scope]?.frame = NSRect(
            x: controlX,
            y: layout.planRect.minY + 61,
            width: controlWidth,
            height: 34
        )
        planModeEffortPopups[scope]?.isHidden = selectedPlatform != .codex
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
        let globalRect = NSRect(
            x: content.minX,
            y: content.minY + 58,
            width: content.width,
            height: modelRoutingControls.selectedPlatform == .codex ? 212 : 96
        )
        let toolbarRect = NSRect(x: content.minX, y: globalRect.maxY + 18, width: min(332, content.width * 0.37), height: 34)
        let projects = modelRoutingControls.visibleProjects
        let projectListWidth = min(360, max(286, content.width * 0.36))
        let bodyY = toolbarRect.maxY + 16
        let rowHeight: CGFloat = 82
        let listHeight = max(430, CGFloat(max(projects.count, 1)) * rowHeight + 58)
        let projectListRect = NSRect(
            x: content.minX,
            y: bodyY,
            width: projectListWidth,
            height: listHeight
        )
        let inspectorRect = NSRect(
            x: projectListRect.maxX + 14,
            y: bodyY,
            width: max(0, content.maxX - projectListRect.maxX - 14),
            height: listHeight
        )
        let panelX = inspectorRect.minX + 14
        let panelWidth = inspectorRect.width - 28
        let runStrategyRect = NSRect(x: panelX, y: inspectorRect.minY + 54, width: panelWidth, height: 158)
        let contextRect = NSRect(x: panelX, y: runStrategyRect.maxY + 14, width: panelWidth, height: 150)
        let planRect = NSRect(x: panelX, y: contextRect.maxY + 14, width: panelWidth, height: 150)
        var rows: [String: NSRect] = [:]
        var y = projectListRect.minY + 48
        for project in projects {
            rows[project.project.id] = NSRect(
                x: projectListRect.minX + 10,
                y: y,
                width: projectListRect.width - 20,
                height: rowHeight
            )
            y += rowHeight
        }
        let footerRect = NSRect(
            x: content.minX + 4,
            y: max(projectListRect.maxY, inspectorRect.maxY) + 18,
            width: content.width - 8,
            height: 56
        )
        return ModelRoutingPageLayout(
            globalRect: globalRect,
            toolbarRect: toolbarRect,
            projectListRect: projectListRect,
            inspectorRect: inspectorRect,
            runStrategyRect: runStrategyRect,
            contextRect: contextRect,
            planRect: planRect,
            projectRows: rows,
            footerRect: footerRect
        )
    }

    func drawModelRoutingPage(content: NSRect) {
        let layout = modelRoutingPageLayout(in: content)
        drawPanel(layout.globalRect)
        drawGlobalRoutingStrip(layout.globalRect)
        drawRoutingSearchSurface(modelRoutingSearchRect(in: layout.toolbarRect))
        drawProjectConfigurationList(layout)
        drawProjectConfigurationInspector(layout)
        drawRoutingFooter(layout.footerRect)
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

        if modelRoutingControls.selectedPlatform == .codex {
            let columns = modelRoutingGlobalColumns(in: row)
            let contextLayout = modelRoutingGlobalContextControlsLayout(in: columns.context)

            NSColor.white.withAlphaComponent(0.09).setStroke()
            let horizontalDivider = NSBezierPath()
            horizontalDivider.move(to: NSPoint(x: row.minX + 20, y: row.minY + 52))
            horizontalDivider.line(to: NSPoint(x: row.maxX - 20, y: row.minY + 52))
            horizontalDivider.lineWidth = 1
            horizontalDivider.stroke()
            let verticalDivider = NSBezierPath()
            verticalDivider.move(to: NSPoint(x: columns.strategy.maxX + 14, y: columns.strategy.minY))
            verticalDivider.line(to: NSPoint(x: columns.strategy.maxX + 14, y: columns.strategy.maxY))
            verticalDivider.lineWidth = 1
            verticalDivider.stroke()

            let labelColor = NSColor.white.withAlphaComponent(0.62)
            let labelFont = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
            drawText(
                modelRoutingLocalized(chinese: "默认模型", english: "Model", japanese: "モデル"),
                rect: NSRect(x: columns.strategy.minX, y: columns.strategy.minY + 8, width: 96, height: 18),
                font: labelFont,
                color: labelColor
            )
            drawText(
                modelRoutingLocalized(chinese: "思考强度", english: "Effort", japanese: "思考強度"),
                rect: NSRect(x: columns.strategy.minX, y: columns.strategy.minY + 50, width: 96, height: 18),
                font: labelFont,
                color: labelColor
            )
            drawText(
                modelRoutingLocalized(chinese: "Plan 思考强度", english: "Plan effort", japanese: "Plan 思考強度"),
                rect: NSRect(x: columns.strategy.minX, y: columns.strategy.minY + 92, width: 96, height: 18),
                font: labelFont,
                color: labelColor
            )
            drawText(
                modelRoutingLocalized(chinese: "有效上下文窗口", english: "Context window", japanese: "コンテキストウィンドウ"),
                rect: NSRect(x: columns.context.minX, y: columns.context.minY + 8, width: contextLayout.infoWidth, height: 18),
                font: labelFont,
                color: labelColor
            )
            drawText(
                modelRoutingLocalized(chinese: "自动压缩阈值", english: "Auto-compaction", japanese: "自動圧縮しきい値"),
                rect: NSRect(x: columns.context.minX, y: columns.context.minY + 50, width: contextLayout.infoWidth, height: 18),
                font: labelFont,
                color: labelColor
            )
            drawCompressionTokenLimit(
                modelRoutingControls.globalCompressionTokenLimitText(),
                rect: contextLayout.tokenLimitRect
            )
        } else if !compact {
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
        let defaultStatus = modelRoutingControls.hasUnsavedChanges
            ? modelRoutingLocalized(chinese: "未保存", english: "Unsaved", japanese: "未保存")
            : hasExplicitGlobal
            ? modelRoutingLocalized(chinese: "已保存", english: "Saved", japanese: "保存済み")
            : modelRoutingLocalized(
                chinese: "使用 \(modelRoutingControls.platformDisplayName) 默认",
                english: "Using \(modelRoutingControls.platformDisplayName) defaults",
                japanese: "\(modelRoutingControls.platformDisplayName) 既定値を使用"
            )
        let statusText = modelRoutingControls.statusMessage ?? defaultStatus
        let statusColor = modelRoutingControls.statusIsError
            ? accentRose
            : modelRoutingControls.hasUnsavedChanges
                ? accentAmber
            : NSColor.white.withAlphaComponent(0.60)
        let statusRect = NSRect(x: row.maxX - 132, y: row.minY + 30, width: 112, height: 26)
        if !modelRoutingControls.statusIsError {
            drawSymbolIcon(
                modelRoutingControls.hasUnsavedChanges ? "pencil.circle" : "checkmark.circle",
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

    private func drawProjectConfigurationList(_ layout: ModelRoutingPageLayout) {
        drawPanel(layout.projectListRect)
        drawText(
            modelRoutingLocalized(chinese: "项目列表", english: "Projects", japanese: "プロジェクト"),
            rect: NSRect(x: layout.projectListRect.minX + 16, y: layout.projectListRect.minY + 16, width: 150, height: 22),
            font: .systemFont(ofSize: 14, weight: .bold),
            color: .white
        )
        let projects = modelRoutingControls.visibleProjects
        guard !projects.isEmpty else {
            drawCentered(
                modelRoutingLocalized(chinese: "没有找到匹配的项目", english: "No matching projects", japanese: "一致するプロジェクトがありません"),
                rect: layout.projectListRect.insetBy(dx: 18, dy: 70),
                font: .systemFont(ofSize: 12, weight: .semibold),
                color: NSColor.white.withAlphaComponent(0.46)
            )
            return
        }
        for project in projects {
            guard let row = layout.projectRows[project.project.id] else { continue }
            let followsSystem = modelRoutingControls.followsSystemConfiguration(project)
            let selected = modelRoutingControls.selectedProject?.project.id == project.project.id
            if selected && !followsSystem {
                accentBlue.withAlphaComponent(0.26).setFill()
                NSBezierPath(roundedRect: row, xRadius: 8, yRadius: 8).fill()
                accentBlue.withAlphaComponent(0.86).setStroke()
                let border = NSBezierPath(roundedRect: row.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
                border.lineWidth = 1
                border.stroke()
            }
            let model = followsSystem
                ? modelRoutingControls.effectiveGlobalModel()
                : project.model.explicitValue ?? modelRoutingControls.effectiveGlobalModel()
            let effort = followsSystem
                ? modelRoutingControls.effectiveGlobalEffort()
                : project.reasoningEffort.explicitValue ?? modelRoutingControls.effectiveGlobalEffort()
            drawTruncatedText(
                project.project.name,
                rect: NSRect(x: row.minX + 14, y: row.minY + 17, width: row.width - 28, height: 20),
                font: .systemFont(ofSize: 13, weight: .semibold),
                color: NSColor.white.withAlphaComponent(followsSystem ? 0.46 : 0.92)
            )
            drawTruncatedText(
                "\(model) / \(effort)",
                rect: NSRect(x: row.minX + 14, y: row.minY + 43, width: row.width - 158, height: 18),
                font: .systemFont(ofSize: 10.5, weight: .medium),
                color: NSColor.white.withAlphaComponent(followsSystem ? 0.32 : (selected ? 0.74 : 0.48))
            )
        }
    }

    private func drawProjectConfigurationInspector(_ layout: ModelRoutingPageLayout) {
        drawPanel(layout.inspectorRect)
        guard let project = modelRoutingControls.selectedProject else {
            drawCentered(
                modelRoutingLocalized(chinese: "选择一个项目以查看配置", english: "Select a project to view its configuration", japanese: "プロジェクトを選択して設定を表示"),
                rect: layout.inspectorRect.insetBy(dx: 24, dy: 24),
                font: .systemFont(ofSize: 13, weight: .semibold),
                color: NSColor.white.withAlphaComponent(0.52)
            )
            return
        }
        drawText(project.project.name, rect: NSRect(x: layout.inspectorRect.minX + 18, y: layout.inspectorRect.minY + 17, width: layout.inspectorRect.width - 168, height: 24), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
        drawInspectorSection(
            title: modelRoutingLocalized(chinese: "运行策略", english: "Run strategy", japanese: "実行戦略"),
            rect: layout.runStrategyRect
        )
        drawText(modelRoutingLocalized(chinese: "默认模型", english: "Default model", japanese: "既定モデル"), rect: NSRect(x: layout.runStrategyRect.minX + 16, y: layout.runStrategyRect.minY + 69, width: 112, height: 18), font: .systemFont(ofSize: 11.5, weight: .semibold), color: NSColor.white.withAlphaComponent(0.62))
        drawText(modelRoutingLocalized(chinese: "思考强度", english: "Reasoning effort", japanese: "思考強度"), rect: NSRect(x: layout.runStrategyRect.minX + 16, y: layout.runStrategyRect.minY + 115, width: 112, height: 18), font: .systemFont(ofSize: 11.5, weight: .semibold), color: NSColor.white.withAlphaComponent(0.62))

        drawInspectorSection(
            title: modelRoutingLocalized(chinese: "上下文与压缩", english: "Context & compaction", japanese: "コンテキストと圧縮"),
            rect: layout.contextRect
        )
        let contextLayout = modelRoutingContextControlsLayout(in: layout.contextRect)
        let contextInfoRect = NSRect(
            x: layout.contextRect.minX + 16,
            y: layout.contextRect.minY + 61,
            width: contextLayout.infoWidth,
            height: 18
        )
        drawText(modelRoutingLocalized(chinese: "有效上下文窗口", english: "Context window", japanese: "コンテキストウィンドウ"), rect: contextInfoRect, font: .systemFont(ofSize: 11.5, weight: .semibold), color: NSColor.white.withAlphaComponent(0.62))
        drawText(modelRoutingLocalized(chinese: "自动压缩阈值", english: "Auto-compaction", japanese: "自動圧縮しきい値"), rect: contextInfoRect.offsetBy(dx: 0, dy: 42), font: .systemFont(ofSize: 11.5, weight: .semibold), color: NSColor.white.withAlphaComponent(0.62))
        drawCompressionTokenLimit(
            modelRoutingControls.compressionTokenLimitText(for: project),
            rect: contextLayout.tokenLimitRect
        )

        drawInspectorSection(
            title: modelRoutingLocalized(chinese: "Plan 模式", english: "Plan mode", japanese: "プランモード"),
            rect: layout.planRect
        )
        drawText(modelRoutingLocalized(chinese: "Plan 思考强度", english: "Plan effort", japanese: "Plan 思考強度"), rect: NSRect(x: layout.planRect.minX + 16, y: layout.planRect.minY + 61, width: 132, height: 18), font: .systemFont(ofSize: 11.5, weight: .semibold), color: NSColor.white.withAlphaComponent(0.62))
        drawText(modelRoutingLocalized(chinese: "Plan 使用运行策略模型", english: "Plan uses the run-strategy model", japanese: "Plan は実行戦略モデルを使用"), rect: NSRect(x: layout.planRect.minX + 16, y: layout.planRect.minY + 108, width: layout.planRect.width - 32, height: 16), font: .systemFont(ofSize: 10.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.42))
    }

    private func drawInspectorSection(title: String, rect: NSRect) {
        inputSurfaceColor.withAlphaComponent(0.68).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        NSColor.white.withAlphaComponent(0.10).setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        border.lineWidth = 1
        border.stroke()
        drawText(title, rect: NSRect(x: rect.minX + 16, y: rect.minY + 14, width: rect.width - 176, height: 20), font: .systemFont(ofSize: 13, weight: .bold), color: .white)
        NSColor.white.withAlphaComponent(0.09).setStroke()
        let divider = NSBezierPath()
        divider.move(to: NSPoint(x: rect.minX + 16, y: rect.minY + 45))
        divider.line(to: NSPoint(x: rect.maxX - 16, y: rect.minY + 45))
        divider.lineWidth = 1
        divider.stroke()
    }

    private func drawCompressionTokenLimit(_ tokenLimit: String, rect: NSRect) {
        // This is intentionally a quieter, read-only companion to the editable
        // percentage field. Giving the number an explicit unit prevents it from
        // looking like a second, unrelated text input.
        inputSurfaceColor.withAlphaComponent(0.74).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 9.5, yRadius: 9.5)
        border.lineWidth = 1
        border.stroke()

        let label = modelRoutingLocalized(
            chinese: "上下文 token",
            english: "Context tokens",
            japanese: "コンテキスト token"
        )
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .bold)
        let labelFont = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        let valueWidth = measuredTextWidth(tokenLimit, font: valueFont)
        let horizontalInset: CGFloat = 12
        func lineHeight(for font: NSFont) -> CGFloat {
            ceil(font.ascender - font.descender + font.leading)
        }
        func verticallyCenteredTextRect(x: CGFloat, width: CGFloat, font: NSFont) -> NSRect {
            let lineHeight = lineHeight(for: font)
            return NSRect(
                x: x,
                y: rect.midY - lineHeight / 2,
                width: width,
                height: lineHeight
            )
        }
        let valueRect = NSRect(
            x: max(rect.minX + horizontalInset, rect.maxX - horizontalInset - valueWidth),
            y: rect.midY - lineHeight(for: valueFont) / 2,
            width: min(valueWidth, rect.width - horizontalInset * 2),
            height: lineHeight(for: valueFont)
        )
        let labelRect = verticallyCenteredTextRect(
            x: rect.minX + horizontalInset,
            width: max(0, valueRect.minX - rect.minX - horizontalInset - 8),
            font: labelFont
        )
        drawTruncatedText(
            label,
            rect: labelRect,
            font: labelFont,
            color: NSColor.white.withAlphaComponent(0.54)
        )
        drawRight(
            tokenLimit,
            rect: valueRect,
            color: NSColor.white.withAlphaComponent(0.86),
            font: valueFont
        )
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
        let statusText = modelRoutingControls.hasUnsavedChanges
            ? modelRoutingLocalized(
                chinese: "\(modelRoutingControls.unsavedChangeCount) 项修改待保存 · 保存后影响新建聊天",
                english: "\(modelRoutingControls.unsavedChangeCount) changes waiting to save · applies to new chats",
                japanese: "\(modelRoutingControls.unsavedChangeCount) 件の変更が未保存 · 新しい会話から有効"
            )
            : countText
        let statusColor = modelRoutingControls.hasUnsavedChanges
            ? accentAmber.withAlphaComponent(0.92)
            : NSColor.white.withAlphaComponent(0.42)
        drawRight(
            statusText,
            rect: NSRect(x: rect.minX + 120, y: rect.minY + 16, width: rect.width - 354, height: 20),
            color: statusColor,
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
