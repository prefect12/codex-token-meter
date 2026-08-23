import Cocoa
import Foundation

final class TaskProgressRingView: NSView {
    var progress: Double = 0 {
        didSet { needsDisplay = true }
    }
    var lineWidth: CGFloat = 2.5 {
        didSet { needsDisplay = true }
    }
    var trackColor = NSColor.white.withAlphaComponent(0.18) {
        didSet { needsDisplay = true }
    }
    var progressColor = NSColor(calibratedRed: 0.28, green: 0.61, blue: 1.0, alpha: 1) {
        didSet { needsDisplay = true }
    }
    var isAnimating = false {
        didSet { updateAnimationTimer() }
    }
    private var animationPhase: CGFloat = 0
    private var animationTimer: Timer?

    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAnimationTimer()
    }

    deinit {
        animationTimer?.invalidate()
    }

    private func updateAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
        guard isAnimating, window != nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.animationPhase = (self.animationPhase + 4).truncatingRemainder(dividingBy: 360)
            self.needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let diameter = min(bounds.width, bounds.height) - lineWidth
        guard diameter > 0 else { return }
        let ringRect = NSRect(
            x: bounds.midX - diameter / 2,
            y: bounds.midY - diameter / 2,
            width: diameter,
            height: diameter
        )
        let track = NSBezierPath(ovalIn: ringRect)
        track.lineWidth = lineWidth
        trackColor.setStroke()
        track.stroke()

        let clamped = min(1, max(0, progress))
        guard clamped > 0 else { return }
        let drawnProgress = isAnimating ? min(clamped, 0.82) : clamped
        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: NSPoint(x: bounds.midX, y: bounds.midY),
            radius: diameter / 2,
            startAngle: 90 - animationPhase,
            endAngle: 90 - animationPhase - CGFloat(drawnProgress) * 360,
            clockwise: true
        )
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        progressColor.setStroke()
        arc.stroke()
    }
}

private final class SubtaskCountBadgeView: NSView {
    private let text: String
    private let font = NSFont.systemFont(ofSize: 9.5, weight: .medium)

    init(count: Int) {
        text = "\(count) \(count == 1 ? "Subtask" : "Subtasks")"
        super.init(frame: NSRect(x: 0, y: 0, width: 66, height: 22))
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.white.withAlphaComponent(0.055).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.10).setStroke()
        path.lineWidth = 1
        path.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byClipping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedWhite: 0.65, alpha: 1),
            .paragraphStyle: paragraph
        ]
        let textHeight = ceil((text as NSString).size(withAttributes: attributes).height)
        let textRect = NSRect(
            x: 5,
            y: floor((bounds.height - textHeight) / 2) - 0.5,
            width: bounds.width - 10,
            height: textHeight + 1
        )
        (text as NSString).draw(in: textRect, withAttributes: attributes)
    }
}

final class ThreadRowView: NSView {
    private let item: CodexThreadItem
    private let onOpen: (String) -> Void
    private let onDismiss: (String) -> Void
    private let onTogglePin: (String) -> Void
    private let onToggleSubtasks: (String) -> Void
    private let showPlatformLabel: Bool
    private let rowLayout: TaskRowLayoutStyle
    private let subtaskCount: Int
    private let isExpanded: Bool
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let clockIconView = NSImageView()
    private let durationLabel = NSTextField(labelWithString: "")
    private let metaDotView = NSView()
    private let metaStatusLabel = NSTextField(labelWithString: "")
    private let platformLabel = NSTextField(labelWithString: "")
    private let pinIconView = NSImageView()
    private let dismissIconView = NSImageView()
    private let disclosureIconView = NSImageView()
    private let planProgressView = TaskProgressRingView()
    private let subtaskBadgeView: SubtaskCountBadgeView
    private var isPinned: Bool
    private var trackingAreaRef: NSTrackingArea?
    private var elapsedTimer: Timer?
    private var mouseDownPoint = NSPoint.zero
    private var dragStartOffset: CGFloat = 0
    private var swipeOffset: CGFloat = 0
    private var isSwipeTracking = false
    private var scrollSwipeSettleTimer: Timer?
    private var didDrag = false
    private var isHovering = false {
        didSet {
            needsDisplay = true
            updatePinIcon()
            updateDismissIcon()
        }
    }

    var representedThreadID: String { item.id }

    func setRenderPreviewHovering(_ hovering: Bool) {
        isHovering = hovering
    }

    init(
        item: CodexThreadItem,
        showPlatformLabel: Bool,
        rowLayout: TaskRowLayoutStyle,
        onOpen: @escaping (String) -> Void,
        onDismiss: @escaping (String) -> Void,
        onTogglePin: @escaping (String) -> Void,
        subtaskCount: Int,
        isExpanded: Bool,
        onToggleSubtasks: @escaping (String) -> Void
    ) {
        self.item = item
        self.showPlatformLabel = showPlatformLabel
        self.rowLayout = rowLayout
        self.onOpen = onOpen
        self.onDismiss = onDismiss
        self.onTogglePin = onTogglePin
        self.onToggleSubtasks = onToggleSubtasks
        self.subtaskCount = subtaskCount
        self.isExpanded = isExpanded
        self.subtaskBadgeView = SubtaskCountBadgeView(count: subtaskCount)
        self.isPinned = TaskBarSettings.isPinned(item.id)
        super.init(frame: NSRect(x: 0, y: 0, width: menuPanelWidth, height: taskBarDisplayedRowHeight(for: rowLayout)))
        wantsLayer = true
        let tooltip = tooltipText(for: item)
        setAccessibilityHelp(tooltip)

        let accent = statusAccentColor(item.status)

        titleLabel.stringValue = item.title
        titleLabel.font = .systemFont(ofSize: subtaskCount > 0 ? 12.5 : 13, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        addSubview(titleLabel)

        detailLabel.stringValue = item.preview ?? detailText(for: item)
        detailLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
        detailLabel.textColor = NSColor(calibratedWhite: 0.62, alpha: 1)
        detailLabel.maximumNumberOfLines = 2
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.cell?.wraps = true
        detailLabel.cell?.isScrollable = false
        addSubview(detailLabel)

        let clockConfig = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        clockIconView.image = NSImage(systemSymbolName: "clock", accessibilityDescription: nil)?
            .withSymbolConfiguration(clockConfig)
        clockIconView.contentTintColor = NSColor(calibratedWhite: 0.5, alpha: 1)
        clockIconView.imageScaling = .scaleProportionallyDown
        addSubview(clockIconView)

        durationLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        durationLabel.textColor = NSColor(calibratedWhite: 0.5, alpha: 1)
        durationLabel.lineBreakMode = .byClipping
        addSubview(durationLabel)

        metaDotView.wantsLayer = true
        metaDotView.layer?.backgroundColor = accent.cgColor
        metaDotView.layer?.cornerRadius = 2.5
        addSubview(metaDotView)

        metaStatusLabel.lineBreakMode = .byTruncatingTail
        addSubview(metaStatusLabel)

        platformLabel.lineBreakMode = .byTruncatingTail
        addSubview(platformLabel)

        pinIconView.imageScaling = .scaleProportionallyDown
        addSubview(pinIconView)
        updatePinIcon()

        let dismissConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        dismissIconView.image = NSImage(
            systemSymbolName: "trash",
            accessibilityDescription: "从 Task Bar 移除"
        )?.withSymbolConfiguration(dismissConfig)
        dismissIconView.contentTintColor = NSColor.systemRed.withAlphaComponent(0.9)
        dismissIconView.imageScaling = .scaleProportionallyDown
        dismissIconView.toolTip = "从 Task Bar 移除（不会删除原对话）"
        addSubview(dismissIconView)
        updateDismissIcon()

        let disclosureConfig = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        disclosureIconView.image = NSImage(
            systemSymbolName: isExpanded ? "chevron.down" : "chevron.right",
            accessibilityDescription: isExpanded ? "收起子任务" : "展开子任务"
        )?.withSymbolConfiguration(disclosureConfig)
        disclosureIconView.contentTintColor = NSColor(calibratedWhite: 0.58, alpha: 1)
        disclosureIconView.imageScaling = .scaleProportionallyDown
        disclosureIconView.isHidden = subtaskCount == 0
        addSubview(disclosureIconView)

        subtaskBadgeView.isHidden = subtaskCount == 0
        addSubview(subtaskBadgeView)

        if let plan = item.displayedPlan {
            planProgressView.progress = plan.progress
            planProgressView.isAnimating = item.status == .running
            planProgressView.setAccessibilityLabel("任务进度 \(plan.displayedStepNumber) / \(plan.steps.count)")
            planProgressView.toolTip = "任务计划 \(plan.displayedStepNumber) / \(plan.steps.count)"
            // The compact Island row reserves its trailing edge for time, state,
            // and source. Its plan details remain available from the row hover.
            planProgressView.isHidden = TaskBarBuild.isBeta
            addSubview(planProgressView)
        } else {
            planProgressView.isAnimating = false
            planProgressView.isHidden = true
        }

        switch rowLayout {
        case .standard:
            // Status word plus the source label share a single trailing line.
            metaStatusLabel.attributedStringValue = rowMetadataAttributed(for: item, showSource: showPlatformLabel)
            platformLabel.isHidden = true
        case .compact:
            // Status and source get their own lines in the left rail.
            metaStatusLabel.attributedStringValue = rowStatusOnlyAttributed(for: item)
            platformLabel.attributedStringValue = rowSourceAttributed(for: item)
            platformLabel.isHidden = !showPlatformLabel
        }

        updateElapsedLabel()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect], owner: self)
        trackingAreaRef = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateHoverPanel(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        guard isHovering else { return }
        updateHoverPanel(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        ThreadHoverPanel.shared.hide(owner: self)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        dragStartOffset = swipeOffset
        isSwipeTracking = false
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        let point = event.locationInWindow
        let deltaX = point.x - mouseDownPoint.x
        let deltaY = point.y - mouseDownPoint.y
        if !isSwipeTracking {
            guard abs(deltaX) > 6 || abs(deltaY) > 6 else { return }
            guard abs(deltaX) > abs(deltaY) * 1.2 else { return }
            isSwipeTracking = true
            ThreadHoverPanel.shared.hide(owner: self)
        }

        didDrag = true
        setSwipeOffset(min(0, max(-ThreadRowView.dismissRevealWidth, dragStartOffset + deltaX)), animated: false)
    }

    override func mouseUp(with event: NSEvent) {
        ThreadHoverPanel.shared.hide(owner: self)
        if isSwipeTracking {
            if swipeOffset <= -ThreadRowView.dismissThreshold {
                onDismiss(item.id)
            } else {
                setSwipeOffset(0, animated: true)
            }
            isSwipeTracking = false
            didDrag = false
            return
        }
        guard !didDrag else {
            didDrag = false
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if dismissHitRect.contains(point) {
            onDismiss(item.id)
            return
        }
        if pinHitRect.contains(point) {
            togglePinTapped()
            return
        }
        if subtaskToggleHitRect.contains(point) {
            onToggleSubtasks(item.id)
            return
        }
        onOpen(item.id)
    }

    /// Generous hit target around the pin glyph.
    private var pinHitRect: NSRect {
        pinIconView.frame.insetBy(dx: -6, dy: -6)
    }

    /// A visible button makes local cleanup discoverable without changing the
    /// source conversations or their rollout logs.
    private var dismissHitRect: NSRect {
        guard !dismissIconView.isHidden else { return .zero }
        return dismissIconView.frame.insetBy(dx: -6, dy: -6)
    }

    private var subtaskToggleHitRect: NSRect {
        guard subtaskCount > 0 else { return .zero }
        return disclosureIconView.frame.union(subtaskBadgeView.frame).insetBy(dx: -7, dy: -7)
    }

    private var planHoverHitRect: NSRect {
        guard item.displayedPlan != nil else { return .zero }
        return planProgressView.frame.insetBy(dx: -4, dy: -4)
    }

    private func updateHoverPanel(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        ThreadHoverPanel.shared.show(
            item: item,
            from: self,
            near: NSEvent.mouseLocation,
            content: planHoverHitRect.contains(point) ? .plan : .details
        )
    }

    private func togglePinTapped() {
        isPinned.toggle()
        updatePinIcon()
        onTogglePin(item.id)
    }

    private func updatePinIcon() {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        pinIconView.image = NSImage(
            systemSymbolName: isPinned ? "pin.fill" : "pin",
            accessibilityDescription: isPinned ? "取消置顶" : "置顶"
        )?.withSymbolConfiguration(config)
        pinIconView.contentTintColor = isPinned
            ? NSColor(calibratedRed: 0.98, green: 0.68, blue: 0.20, alpha: 1)
            : NSColor(calibratedWhite: 0.5, alpha: 1)
        pinIconView.toolTip = isPinned ? "取消置顶" : "置顶"
        // The progress ring has its own slot immediately to the left of the pin.
        // Keep the pin discoverable on hover even when a task has a live plan.
        pinIconView.isHidden = !(isPinned || isHovering)
    }

    private func updateDismissIcon() {
        dismissIconView.isHidden = !isHovering
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.hasPreciseScrollingDeltas else {
            super.scrollWheel(with: event)
            return
        }

        let horizontal = event.scrollingDeltaX
        let vertical = event.scrollingDeltaY
        guard abs(horizontal) > 0.4, abs(horizontal) > abs(vertical) * 1.35 else {
            super.scrollWheel(with: event)
            return
        }

        ThreadHoverPanel.shared.hide(owner: self)
        isSwipeTracking = true
        scrollSwipeSettleTimer?.invalidate()

        let revealDelta = event.isDirectionInvertedFromDevice ? horizontal : -horizontal
        let nextOffset = min(0, max(-ThreadRowView.dismissRevealWidth, swipeOffset - revealDelta))
        setSwipeOffset(nextOffset, animated: false)

        switch event.phase {
        case .ended, .cancelled:
            settleScrollSwipe()
        default:
            let timer = Timer(timeInterval: 0.18, repeats: false) { [weak self] _ in
                self?.settleScrollSwipe()
            }
            scrollSwipeSettleTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            ThreadHoverPanel.shared.hide(owner: self)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopElapsedTimer()
        } else {
            updateElapsedLabel()
            startElapsedTimerIfNeeded()
        }
    }

    deinit {
        stopElapsedTimer()
        scrollSwipeSettleTimer?.invalidate()
        ThreadHoverPanel.shared.hide(owner: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if TaskBarBuild.isBeta {
            drawIslandRow()
            return
        }

        if TaskBarBuild.isClassicPage {
            NSColor(calibratedWhite: 1.0, alpha: 0.06).setFill()
            NSRect(x: 20, y: 0, width: bounds.width - 40, height: 1).fill()
            if !isSwipeTracking || swipeOffset > -1 {
                let barRect = NSRect(x: 8 + swipeOffset, y: 14, width: 3.5, height: bounds.height - 28)
                statusAccentColor(item.status).setFill()
                NSBezierPath(roundedRect: barRect, xRadius: 1.75, yRadius: 1.75).fill()
            }
            if swipeOffset < -1, isReadDismissible(item.status) {
                let revealWidth = min(ThreadRowView.dismissRevealWidth, -swipeOffset + 16)
                let revealRect = NSRect(x: bounds.maxX - revealWidth - 8, y: 6, width: revealWidth, height: bounds.height - 12)
                NSColor.systemRed.withAlphaComponent(0.82).setFill()
                NSBezierPath(roundedRect: revealRect, xRadius: 10, yRadius: 10).fill()
                drawDismissLabel(in: revealRect)
            }
            guard isHovering, !isSwipeTracking else { return }
            let hoverColor = item.plan == nil ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.white.withAlphaComponent(0.055)
            hoverColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 4), xRadius: 12, yRadius: 12).fill()
            return
        }

        let cardRect = bounds.insetBy(dx: 12, dy: 4)
        let card = NSBezierPath(roundedRect: cardRect, xRadius: 14, yRadius: 14)
        (isHovering ? taskBarCardHover : taskBarCardBackground).setFill()
        card.fill()
        taskBarPanelBorder.withAlphaComponent(isHovering ? 1 : 0.58).setStroke()
        card.lineWidth = 1
        card.stroke()

        // Colored status accent bar at the leading edge.
        if !isSwipeTracking || swipeOffset > -1 {
            let barRect = NSRect(x: 18 + swipeOffset, y: 16, width: 3.5, height: bounds.height - 32)
            statusAccentColor(item.status).setFill()
            NSBezierPath(roundedRect: barRect, xRadius: 1.75, yRadius: 1.75).fill()
        }

        if swipeOffset < -1 {
            let revealWidth = min(ThreadRowView.dismissRevealWidth, -swipeOffset + 16)
            let revealRect = NSRect(
                x: bounds.maxX - revealWidth - 8,
                y: 6,
                width: revealWidth,
                height: bounds.height - 12
            )
            NSColor.systemRed.withAlphaComponent(0.82).setFill()
            NSBezierPath(roundedRect: revealRect, xRadius: 10, yRadius: 10).fill()
            drawDismissLabel(in: revealRect)
        }
        guard isHovering, !isSwipeTracking else { return }
        taskBarWarmAccent.withAlphaComponent(item.plan == nil ? 0.025 : 0.055).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 12, dy: 4), xRadius: 14, yRadius: 14).fill()
    }

    override func layout() {
        super.layout()
        if TaskBarBuild.isBeta {
            layoutIslandRow()
            return
        }
        switch rowLayout {
        case .standard: layoutStandard()
        case .compact: layoutCompact()
        }
    }

    /// Vibe Island's list reads as one activity surface rather than a stack of cards:
    /// a small state dot, compact task copy, then a quiet metadata line.
    private func layoutIslandRow() {
        let offset = swipeOffset
        let contentX: CGFloat = 32
        // Keep the three pieces of operational metadata together at the trailing
        // edge. This leaves the title and context as the readable left column.
        let metadataWidth: CGFloat = showPlatformLabel ? 112 : 58
        let metadataX = bounds.width - metadataWidth - 18
        let timeX = metadataX - 66
        let contentWidth = max(100, timeX - contentX - 10)

        layoutTitleAndPin(x: contentX, y: bounds.height - 24, width: contentWidth, offset: offset)
        detailLabel.frame = NSRect(x: contentX + offset, y: 6, width: contentWidth, height: 16)
        detailLabel.maximumNumberOfLines = 1

        clockIconView.frame = NSRect(x: timeX + offset, y: 20, width: 10, height: 10)
        durationLabel.frame = NSRect(x: timeX + 14 + offset, y: 17.5, width: 50, height: 14)
        metaDotView.frame = NSRect(x: 17 + offset, y: bounds.height - 20, width: 6, height: 6)
        metaStatusLabel.frame = NSRect(x: metadataX + offset, y: 17, width: metadataWidth, height: 15)
        platformLabel.isHidden = true
    }

    private func drawIslandRow() {
        let rowRect = bounds.insetBy(dx: 8, dy: 1)
        if isHovering, !isSwipeTracking {
            NSColor.white.withAlphaComponent(0.055).setFill()
            NSBezierPath(roundedRect: rowRect, xRadius: 8, yRadius: 8).fill()
        }

        if swipeOffset < -1, isReadDismissible(item.status) {
            let revealWidth = min(ThreadRowView.dismissRevealWidth, -swipeOffset + 16)
            let revealRect = NSRect(
                x: bounds.maxX - revealWidth - 8,
                y: 4,
                width: revealWidth,
                height: bounds.height - 8
            )
            NSColor.systemRed.withAlphaComponent(0.82).setFill()
            NSBezierPath(roundedRect: revealRect, xRadius: 8, yRadius: 8).fill()
            drawDismissLabel(in: revealRect)
        } else {
            statusAccentColor(item.status).setFill()
            NSBezierPath(ovalIn: NSRect(x: 17 + swipeOffset, y: bounds.height - 20, width: 6, height: 6)).fill()
        }

        guard bounds.maxY > 1 else { return }
        NSColor.white.withAlphaComponent(isHovering ? 0.12 : 0.075).setFill()
        NSBezierPath.fill(NSRect(x: 32, y: bounds.maxY - 1, width: bounds.width - 50, height: 1))
    }

    /// Title and detail stacked over a single metadata line (time · status · source).
    private func layoutStandard() {
        let offset = swipeOffset
        let classic = TaskBarBuild.isClassicPage
        let contentX: CGFloat = classic ? 26 : 34
        let contentWidth = max(120, bounds.width - (classic ? 18 : 30) - contentX)

        layoutTitleAndPin(x: contentX, y: bounds.height - 32, width: contentWidth, offset: offset)
        detailLabel.frame = NSRect(x: contentX + offset, y: 28, width: contentWidth, height: 32)

        // Clock symbol sits optically low inside its image box; keep it slightly lower
        // while nudging text down so the glyph centers align visually.
        clockIconView.frame = NSRect(x: contentX + offset, y: 13, width: 11, height: 11)
        durationLabel.frame = NSRect(x: contentX + 16 + offset, y: 9, width: 58, height: 15)
        metaDotView.frame = NSRect(x: contentX + 76 + offset, y: 14, width: 5, height: 5)
        metaStatusLabel.frame = NSRect(x: contentX + 87 + offset, y: 10.5, width: max(0, contentWidth - 87), height: 15)
    }

    /// Metadata (time / status / source) stacked in a narrow left rail, with the
    /// title and detail filling the remaining width so rows stay short.
    private func layoutCompact() {
        let offset = swipeOffset
        let classic = TaskBarBuild.isClassicPage
        let contentX: CGFloat = classic ? 26 : 34
        let railWidth: CGFloat = 66
        let railGap: CGFloat = 10
        let rightX = contentX + railWidth + railGap
        let rightWidth = max(80, bounds.width - (classic ? 18 : 30) - rightX)

        layoutTitleAndPin(x: rightX, y: bounds.height - 30, width: rightWidth, offset: offset)
        detailLabel.frame = NSRect(x: rightX + offset, y: 8, width: rightWidth, height: 32)

        // Vertically center however many meta lines are visible (time, status, [source]).
        let lineHeight: CGFloat = 15
        let lineGap: CGFloat = 6
        let showsSource = !platformLabel.isHidden
        let lineCount: CGFloat = showsSource ? 3 : 2
        let groupHeight = lineHeight * lineCount + lineGap * (lineCount - 1)
        var lineY = bounds.height - (bounds.height - groupHeight) / 2 - lineHeight

        clockIconView.frame = NSRect(x: contentX + offset, y: lineY + 2, width: 11, height: 11)
        durationLabel.frame = NSRect(x: contentX + 14 + offset, y: lineY - 0.5, width: railWidth - 14, height: lineHeight)
        lineY -= lineHeight + lineGap

        metaDotView.frame = NSRect(x: contentX + 1 + offset, y: lineY + 5, width: 5, height: 5)
        metaStatusLabel.frame = NSRect(x: contentX + 11 + offset, y: lineY, width: railWidth - 11, height: lineHeight)
        lineY -= lineHeight + lineGap

        if showsSource {
            platformLabel.frame = NSRect(x: contentX + offset, y: lineY, width: railWidth, height: lineHeight)
        }
    }

    private func layoutTitleAndPin(x: CGFloat, y: CGFloat, width: CGFloat, offset: CGFloat) {
        let disclosureWidth: CGFloat = subtaskCount > 0 ? 15 : 0
        disclosureIconView.frame = NSRect(x: x + offset, y: y + 4, width: 11, height: 11)
        let titleX = x + disclosureWidth + offset
        let dismissX = bounds.width - ThreadRowView.dismissTrailingInset - ThreadRowView.dismissIconSize + offset
        let pinX = dismissX - ThreadRowView.dismissIconSize - ThreadRowView.actionIconGap
        let planSize: CGFloat = item.plan == nil ? 0 : 15
        let planX = item.plan == nil ? pinX : pinX - planSize - 6
        let badgeWidth: CGFloat = subtaskCount > 0 ? 66 : 0
        let badgeTrailingX = item.plan == nil ? pinX : planX
        let badgeX = badgeTrailingX - (subtaskCount > 0 ? badgeWidth + 6 : 0)
        planProgressView.frame = NSRect(
            x: planX,
            y: y + 1,
            width: planSize,
            height: planSize
        )
        let titleTrailingX: CGFloat
        if subtaskCount > 0 {
            titleTrailingX = badgeX - 6
        } else if item.plan != nil {
            titleTrailingX = planX - 8
        } else {
            titleTrailingX = pinX - ThreadRowView.titlePinGap
        }
        let titleWidth = max(0, min(width, titleTrailingX - titleX))

        titleLabel.frame = NSRect(x: titleX, y: y, width: titleWidth, height: 20)
        subtaskBadgeView.frame = NSRect(x: badgeX, y: y - 1, width: badgeWidth, height: 22)
        pinIconView.frame = NSRect(
            x: pinX,
            y: titleLabel.frame.midY - ThreadRowView.pinIconSize / 2,
            width: ThreadRowView.pinIconSize,
            height: ThreadRowView.pinIconSize
        )
        dismissIconView.frame = NSRect(
            x: dismissX,
            y: titleLabel.frame.midY - ThreadRowView.dismissIconSize / 2,
            width: ThreadRowView.dismissIconSize,
            height: ThreadRowView.dismissIconSize
        )
    }

    private func setSwipeOffset(_ offset: CGFloat, animated: Bool) {
        swipeOffset = offset
        let updates = {
            self.needsLayout = true
            self.layoutSubtreeIfNeeded()
            self.needsDisplay = true
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                updates()
            }
        } else {
            updates()
        }
    }

    private func drawDismissLabel(in rect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.94),
            .paragraphStyle: paragraph
        ]
        ("移除" as NSString).draw(in: rect.insetBy(dx: 10, dy: 22), withAttributes: attributes)
    }

    private func settleScrollSwipe() {
        scrollSwipeSettleTimer?.invalidate()
        scrollSwipeSettleTimer = nil
        guard isSwipeTracking else { return }
        isSwipeTracking = false
        if swipeOffset <= -ThreadRowView.dismissThreshold {
            onDismiss(item.id)
        } else {
            setSwipeOffset(0, animated: true)
        }
    }

    private func startElapsedTimerIfNeeded() {
        guard elapsedTimer == nil, statusElapsedText(for: item) != nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateElapsedLabel()
        }
        elapsedTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func updateElapsedLabel() {
        let text = statusElapsedText(for: item) ?? ""
        durationLabel.stringValue = text
        durationLabel.isHidden = text.isEmpty
        clockIconView.isHidden = text.isEmpty
    }

    private static let dismissRevealWidth: CGFloat = 86
    private static let dismissThreshold: CGFloat = 58
    private static let dismissIconSize: CGFloat = 16
    private static let actionIconGap: CGFloat = 7
    private static let dismissTrailingInset: CGFloat = 18
    private static let pinIconSize: CGFloat = 16
    private static let titlePinGap: CGFloat = 8
    private static let pinTrailingInset: CGFloat = 18
}

final class ThreadGroupView: NSView {
    private let rootView: ThreadRowView
    private let subtaskViews: [SubtaskRowView]
    private let isExpanded: Bool
    private let rootHeight: CGFloat
    private static let childHeight: CGFloat = 78
    private static let topGap: CGFloat = 6
    private static let bottomGap: CGFloat = 8

    init(
        root: CodexThreadItem,
        subtasks: [CodexThreadItem],
        isExpanded: Bool,
        showPlatformLabel: Bool,
        rowLayout: TaskRowLayoutStyle,
        onOpen: @escaping (String) -> Void,
        onDismiss: @escaping (String) -> Void,
        onTogglePin: @escaping (String) -> Void,
        onToggleSubtasks: @escaping (String) -> Void
    ) {
        self.isExpanded = isExpanded && !subtasks.isEmpty
        self.rootHeight = taskBarDisplayedRowHeight(for: rowLayout)
        self.rootView = ThreadRowView(
            item: root,
            showPlatformLabel: showPlatformLabel,
            rowLayout: rowLayout,
            onOpen: onOpen,
            onDismiss: onDismiss,
            onTogglePin: onTogglePin,
            subtaskCount: subtasks.count,
            isExpanded: isExpanded,
            onToggleSubtasks: onToggleSubtasks
        )
        self.subtaskViews = subtasks.map { SubtaskRowView(item: $0, onOpen: onOpen) }
        let childrenHeight = self.isExpanded
            ? Self.topGap + CGFloat(subtasks.count) * Self.childHeight + Self.bottomGap
            : 0
        super.init(frame: NSRect(x: 0, y: 0, width: menuPanelWidth, height: rootHeight + childrenHeight))
        wantsLayer = true
        addSubview(rootView)
        if self.isExpanded {
            subtaskViews.forEach(addSubview)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isExpanded, !subtaskViews.isEmpty else { return }
        if !TaskBarBuild.isBeta {
            let groupRect = NSRect(
                x: 45,
                y: rootHeight + Self.topGap,
                width: bounds.width - 57,
                height: CGFloat(subtaskViews.count) * Self.childHeight
            )
            NSColor.white.withAlphaComponent(0.025).setFill()
            NSBezierPath(roundedRect: groupRect, xRadius: 9, yRadius: 9).fill()
            NSColor.white.withAlphaComponent(0.10).setStroke()
            let border = NSBezierPath(roundedRect: groupRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
            border.lineWidth = 1
            border.stroke()
        }

        let treeX: CGFloat = 31
        let firstCenterY = rootHeight + Self.topGap + Self.childHeight / 2
        let lastCenterY = rootHeight + Self.topGap + CGFloat(subtaskViews.count - 1) * Self.childHeight + Self.childHeight / 2
        let tree = NSBezierPath()
        tree.move(to: NSPoint(x: treeX, y: rootHeight - 6))
        tree.line(to: NSPoint(x: treeX, y: lastCenterY))
        for index in subtaskViews.indices {
            let centerY = firstCenterY + CGFloat(index) * Self.childHeight
            tree.move(to: NSPoint(x: treeX, y: centerY))
            tree.line(to: NSPoint(x: 45, y: centerY))
        }
        NSColor.white.withAlphaComponent(TaskBarBuild.isBeta ? 0.14 : 0.24).setStroke()
        tree.lineWidth = 1
        tree.stroke()
    }

    override func layout() {
        super.layout()
        rootView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: rootHeight)
        guard isExpanded else { return }
        var y = rootHeight + Self.topGap
        for view in subtaskViews {
            view.frame = NSRect(x: 45, y: y, width: bounds.width - 57, height: Self.childHeight)
            y += Self.childHeight
        }
    }
}

final class SubtaskRowView: NSView {
    private let item: CodexThreadItem
    private let onOpen: (String) -> Void
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let previewLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "Subtask")
    private let statusIconView = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "")
    private var trackingAreaRef: NSTrackingArea?
    private var isHovering = false {
        didSet { needsDisplay = true }
    }

    init(item: CodexThreadItem, onOpen: @escaping (String) -> Void) {
        self.item = item
        self.onOpen = onOpen
        super.init(frame: NSRect(x: 0, y: 0, width: menuPanelWidth - 57, height: 78))
        wantsLayer = true
        setAccessibilityHelp(tooltipText(for: item))

        let iconConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        iconView.image = NSImage(systemSymbolName: "arrow.turn.down.right", accessibilityDescription: "Subtask")?
            .withSymbolConfiguration(iconConfig)
        iconView.contentTintColor = NSColor(calibratedWhite: 0.64, alpha: 1)
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        titleLabel.stringValue = subtaskDisplayTitle(item)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.94)
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        previewLabel.stringValue = item.preview ?? detailText(for: item)
        previewLabel.font = .systemFont(ofSize: 10.5, weight: .regular)
        previewLabel.textColor = NSColor(calibratedWhite: 0.64, alpha: 1)
        previewLabel.maximumNumberOfLines = 2
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.cell?.wraps = true
        previewLabel.cell?.isScrollable = false
        addSubview(previewLabel)

        subtitleLabel.font = .systemFont(ofSize: 10.5, weight: .regular)
        subtitleLabel.textColor = NSColor(calibratedWhite: 0.55, alpha: 1)
        addSubview(subtitleLabel)

        let statusSymbol = item.status == .unread ? "checkmark.circle.fill" : "circle.fill"
        let statusConfig = NSImage.SymbolConfiguration(pointSize: item.status == .unread ? 10 : 7, weight: .semibold)
        statusIconView.image = NSImage(systemSymbolName: statusSymbol, accessibilityDescription: rowStatusLabel(item.status))?
            .withSymbolConfiguration(statusConfig)
        statusIconView.contentTintColor = statusAccentColor(item.status)
        statusIconView.imageScaling = .scaleProportionallyDown
        addSubview(statusIconView)

        statusLabel.stringValue = rowStatusLabel(item.status)
        statusLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        statusLabel.textColor = statusAccentColor(item.status)
        statusLabel.alignment = .right
        addSubview(statusLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect], owner: self)
        trackingAreaRef = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        ThreadHoverPanel.shared.show(item: item, from: self, near: NSEvent.mouseLocation)
    }

    override func mouseMoved(with event: NSEvent) {
        guard isHovering else { return }
        ThreadHoverPanel.shared.show(item: item, from: self, near: NSEvent.mouseLocation)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        ThreadHoverPanel.shared.hide(owner: self)
    }

    override func mouseUp(with event: NSEvent) {
        ThreadHoverPanel.shared.hide(owner: self)
        onOpen(item.id)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isHovering {
            NSColor.controlAccentColor.withAlphaComponent(0.10).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 3), xRadius: 7, yRadius: 7).fill()
        }
        guard frame.minY > 0 else { return }
    }

    override func layout() {
        super.layout()
        let statusWidth: CGFloat = 66
        iconView.frame = NSRect(x: 14, y: 11, width: 16, height: 16)
        statusLabel.frame = NSRect(x: bounds.width - 15 - statusWidth, y: 10, width: statusWidth, height: 16)
        statusIconView.frame = NSRect(x: statusLabel.frame.minX - 17, y: 12, width: 12, height: 12)
        let textX: CGFloat = 42
        let textWidth = max(40, statusIconView.frame.minX - 10 - textX)
        titleLabel.frame = NSRect(x: textX, y: 7, width: textWidth, height: 18)
        previewLabel.frame = NSRect(x: textX, y: 28, width: bounds.width - textX - 15, height: 30)
        subtitleLabel.frame = NSRect(x: textX, y: 59, width: textWidth, height: 15)
    }

    private func subtaskDisplayTitle(_ item: CodexThreadItem) -> String {
        let pathName = item.agentPath.flatMap { path -> String? in
            let value = (path as NSString).lastPathComponent
            return value.isEmpty ? nil : value
        }
        switch (item.agentNickname, pathName) {
        case let (nickname?, path?): return "\(nickname) · \(path)"
        case let (nickname?, nil): return nickname
        case let (nil, path?): return path
        default: return "Subtask"
        }
    }
}

struct ThreadTooltipRow {
    let label: String
    let value: String
    let valueColor: NSColor
    let gapBefore: CGFloat
    let emphasized: Bool
    let isSeparator: Bool

    init(
        _ label: String,
        _ value: String,
        valueColor: NSColor = NSColor.white.withAlphaComponent(0.88),
        gapBefore: CGFloat = 0,
        emphasized: Bool = false
    ) {
        self.label = label
        self.value = value
        self.valueColor = valueColor
        self.gapBefore = gapBefore
        self.emphasized = emphasized
        self.isSeparator = false
    }

    static func separator(gapBefore: CGFloat = 4) -> ThreadTooltipRow {
        ThreadTooltipRow(label: "", value: "", gapBefore: gapBefore, isSeparator: true)
    }

    private init(label: String, value: String, gapBefore: CGFloat, isSeparator: Bool) {
        self.label = label
        self.value = value
        self.valueColor = NSColor.white.withAlphaComponent(0.88)
        self.gapBefore = gapBefore
        self.emphasized = false
        self.isSeparator = isSeparator
    }
}

final class ThreadHoverPanel {
    enum Content {
        case details
        case plan
    }

    static let shared = ThreadHoverPanel()

    private weak var owner: NSView?
    private let tooltipView = ThreadTooltipView()
    private let planTooltipView = TaskPlanTooltipView()
    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 132),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.contentView = tooltipView
        return panel
    }()

    func show(
        item: CodexThreadItem,
        from sourceView: NSView,
        near cursorLocation: NSPoint,
        content: Content = .details
    ) {
        owner = sourceView
        let size: NSSize
        if content == .plan, let plan = item.displayedPlan {
            planTooltipView.plan = plan
            size = planTooltipView.preferredSize
            planTooltipView.frame = NSRect(origin: .zero, size: size)
            panel.contentView = planTooltipView
        } else {
            let rows = tooltipRows(for: item)
            guard !rows.isEmpty else {
                panel.orderOut(nil)
                return
            }
            tooltipView.rows = rows
            size = tooltipView.preferredSize
            tooltipView.frame = NSRect(origin: .zero, size: size)
            panel.contentView = tooltipView
        }
        panel.setFrame(
            NSRect(origin: origin(for: size, near: cursorLocation), size: size),
            display: true
        )
        panel.orderFrontRegardless()
    }

    func hide(owner sourceView: NSView) {
        guard owner === sourceView else { return }
        owner = nil
        panel.orderOut(nil)
    }

    func hideAll() {
        owner = nil
        panel.orderOut(nil)
    }

    private func origin(for size: NSSize, near cursorLocation: NSPoint) -> NSPoint {
        let visibleFrame = NSScreen.screens.first { $0.frame.contains(cursorLocation) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let margin: CGFloat = 8
        let cursorGap: CGFloat = 14
        var x = cursorLocation.x + cursorGap
        var y = cursorLocation.y - size.height - cursorGap

        if x + size.width > visibleFrame.maxX - margin {
            x = cursorLocation.x - size.width - cursorGap
        }
        if y < visibleFrame.minY + margin {
            y = cursorLocation.y + cursorGap
        }

        x = min(max(x, visibleFrame.minX + margin), visibleFrame.maxX - size.width - margin)
        y = min(max(y, visibleFrame.minY + margin), visibleFrame.maxY - size.height - margin)
        return NSPoint(x: x, y: y)
    }
}

private final class TaskPlanTooltipView: NSView {
    var plan: TaskPlan? {
        didSet {
            needsDisplay = true
            updateAnimationTimer()
        }
    }

    private let cardInset: CGFloat = 10
    private let cardWidth: CGFloat = 360
    private let horizontalPadding: CGFloat = 16
    private let headerHeight: CGFloat = 16
    private let footerHeight: CGFloat = 42
    private let stepFont = NSFont.systemFont(ofSize: 12.5, weight: .medium)
    private let footerFont = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
    private var animationPhase: CGFloat = 0
    private var animationTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAnimationTimer()
    }

    deinit {
        animationTimer?.invalidate()
    }

    private func updateAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
        guard window != nil, plan?.steps.contains(where: { $0.status == .inProgress }) == true else {
            return
        }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.animationPhase = (self.animationPhase + 5).truncatingRemainder(dividingBy: 360)
            self.needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    var preferredSize: NSSize {
        let stepsHeight = plan?.steps.reduce(CGFloat(0)) {
            $0 + stepRowHeight(for: $1)
        } ?? 32
        return NSSize(
            width: cardInset + cardWidth,
            height: headerHeight + stepsHeight + footerHeight
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let plan else { return }
        let cardRect = NSRect(x: cardInset, y: 0, width: cardWidth, height: bounds.height)
            .insetBy(dx: 0.5, dy: 0.5)
        NSColor(calibratedWhite: 0.095, alpha: 0.985).setFill()
        NSBezierPath(roundedRect: cardRect, xRadius: 12, yRadius: 12).fill()
        NSColor.white.withAlphaComponent(0.17).setStroke()
        let border = NSBezierPath(roundedRect: cardRect, xRadius: 12, yRadius: 12)
        border.lineWidth = 1
        border.stroke()

        let pointerY = min(max(64, bounds.height * 0.42), bounds.height - 64)
        let pointer = NSBezierPath()
        pointer.move(to: NSPoint(x: cardInset + 0.5, y: pointerY - 11))
        pointer.line(to: NSPoint(x: 1.5, y: pointerY))
        pointer.line(to: NSPoint(x: cardInset + 0.5, y: pointerY + 11))
        pointer.close()
        NSColor(calibratedWhite: 0.095, alpha: 0.985).setFill()
        pointer.fill()
        NSColor.white.withAlphaComponent(0.17).setStroke()
        pointer.lineWidth = 1
        pointer.stroke()

        let markerX = cardInset + horizontalPadding + 8
        var y = headerHeight
        for (index, step) in plan.steps.enumerated() {
            let rowHeight = stepRowHeight(for: step)
            let centerY = y + rowHeight / 2
            if index < plan.steps.count - 1 {
                let nextRowHeight = stepRowHeight(for: plan.steps[index + 1])
                let nextCenterY = y + rowHeight + nextRowHeight / 2
                let connectorColor = step.status == .completed
                    ? NSColor.white.withAlphaComponent(0.32)
                    : NSColor.white.withAlphaComponent(0.17)
                connectorColor.setStroke()
                let connector = NSBezierPath()
                connector.move(to: NSPoint(x: markerX, y: centerY + 9))
                connector.line(to: NSPoint(x: markerX, y: nextCenterY - 9))
                connector.lineWidth = 1
                connector.setLineDash([2, 3], count: 2, phase: 0)
                connector.stroke()
            }
            drawStepMarker(step.status, center: NSPoint(x: markerX, y: centerY))
            let textColor: NSColor
            switch step.status {
            case .completed: textColor = NSColor.white.withAlphaComponent(0.42)
            case .inProgress: textColor = NSColor.white.withAlphaComponent(0.95)
            case .pending: textColor = NSColor.white.withAlphaComponent(0.38)
            }
            let textFont = stepFont(for: step)
            drawWrappedText(
                step.text,
                rect: NSRect(
                    x: markerX + 22,
                    y: y + 8,
                    width: cardWidth - horizontalPadding * 2 - 30,
                    height: rowHeight - 16
                ),
                font: textFont,
                color: textColor
            )
            y += rowHeight
        }

        NSColor.white.withAlphaComponent(0.14).setFill()
        NSRect(
            x: cardInset + horizontalPadding,
            y: y + 4,
            width: cardWidth - horizontalPadding * 2,
            height: 1
        ).fill()
        drawText(
            "Step \(plan.displayedStepNumber) / \(plan.steps.count)",
            rect: NSRect(
                x: cardInset + horizontalPadding,
                y: y + 14,
                width: cardWidth - horizontalPadding * 2,
                height: 16
            ),
            font: footerFont,
            color: NSColor.white.withAlphaComponent(0.48)
        )
    }

    private func drawStepMarker(_ status: TaskPlanStepStatus, center: NSPoint) {
        let radius: CGFloat = 8
        let rect = NSRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        switch status {
        case .completed:
            NSColor.white.withAlphaComponent(0.55).setFill()
            NSBezierPath(ovalIn: rect).fill()
            let check = NSBezierPath()
            check.move(to: NSPoint(x: center.x - 3.5, y: center.y))
            check.line(to: NSPoint(x: center.x - 0.5, y: center.y + 3))
            check.line(to: NSPoint(x: center.x + 4, y: center.y - 3.5))
            check.lineWidth = 1.6
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            NSColor(calibratedWhite: 0.10, alpha: 1).setStroke()
            check.stroke()
        case .inProgress:
            let color = NSColor(calibratedRed: 0.28, green: 0.61, blue: 1.0, alpha: 1)
            color.withAlphaComponent(0.22).setStroke()
            let track = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            track.lineWidth = 1.8
            track.stroke()
            color.setStroke()
            let arc = NSBezierPath()
            arc.appendArc(
                withCenter: center,
                radius: radius - 0.5,
                startAngle: 90 - animationPhase,
                endAngle: -80 - animationPhase,
                clockwise: true
            )
            arc.lineWidth = 2
            arc.lineCapStyle = .round
            arc.stroke()
        case .pending:
            NSColor.white.withAlphaComponent(0.40).setStroke()
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            ring.lineWidth = 1.4
            ring.stroke()
        }
    }

    private func stepFont(for step: TaskPlanStep) -> NSFont {
        step.status == .inProgress
            ? NSFont.systemFont(ofSize: 12.5, weight: .semibold)
            : stepFont
    }

    private func stepRowHeight(for step: TaskPlanStep) -> CGFloat {
        let width = cardWidth - horizontalPadding * 2 - 30
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let rect = (step.text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: stepFont(for: step),
                .paragraphStyle: paragraph
            ]
        )
        return max(36, ceil(rect.height) + 16)
    }

    private func drawWrappedText(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        (text as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }

    private func drawText(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }
}

func taskPlanPreviewView(for plan: TaskPlan) -> NSView {
    let view = TaskPlanTooltipView(frame: .zero)
    view.plan = plan
    view.frame = NSRect(origin: .zero, size: view.preferredSize)
    view.layoutSubtreeIfNeeded()
    return view
}

private final class ThreadTooltipView: NSView {
    var rows: [ThreadTooltipRow] = [] {
        didSet { needsDisplay = true }
    }

    private let horizontalPadding: CGFloat = 10
    private let verticalPadding: CGFloat = 5
    private let labelValueGap: CGFloat = 16
    private let rowHeight: CGFloat = 16
    private let separatorHeight: CGFloat = 9
    private let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
    private let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
    private let emphasizedValueFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)

    override var isFlipped: Bool { true }

    var preferredSize: NSSize {
        let labelWidth = measuredLabelWidth
        let valueWidth = min(max(measuredValueWidth, 86), 360)
        let gaps = rows.reduce(CGFloat(0)) { $0 + $1.gapBefore }
        let contentHeight = rows.reduce(CGFloat(0)) { total, row in
            total + (row.isSeparator ? separatorHeight : rowHeight)
        }
        let width = max(220, horizontalPadding * 2 + labelWidth + labelValueGap + valueWidth)
        let height = verticalPadding * 2 + contentHeight + gaps
        return NSSize(width: ceil(width), height: ceil(height))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        NSColor(calibratedWhite: 0.025, alpha: 0.96).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()

        NSColor.white.withAlphaComponent(0.16).setStroke()
        let border = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        border.lineWidth = 1
        border.stroke()

        let labelWidth = measuredLabelWidth
        let valueX = horizontalPadding + labelWidth + labelValueGap
        let valueWidth = bounds.width - valueX - horizontalPadding
        var y = verticalPadding

        for row in rows {
            y += row.gapBefore
            if row.isSeparator {
                NSColor.white.withAlphaComponent(0.14).setFill()
                NSRect(x: horizontalPadding, y: y + floor(separatorHeight / 2), width: bounds.width - horizontalPadding * 2, height: 1).fill()
                y += separatorHeight
                continue
            }
            drawText(
                row.label,
                rect: NSRect(x: horizontalPadding, y: y, width: labelWidth, height: rowHeight),
                font: labelFont,
                color: NSColor.white.withAlphaComponent(0.62)
            )
            drawText(
                row.value,
                rect: NSRect(x: valueX, y: y, width: valueWidth, height: rowHeight),
                font: row.emphasized ? emphasizedValueFont : valueFont,
                color: row.valueColor
            )
            y += rowHeight
        }
    }

    private var measuredLabelWidth: CGFloat {
        let width = rows
            .filter { !$0.isSeparator }
            .map { textWidth($0.label, font: labelFont) }
            .max() ?? 0
        return min(max(ceil(width), 56), 78)
    }

    private var measuredValueWidth: CGFloat {
        rows
            .filter { !$0.isSeparator }
            .map { textWidth($0.value, font: $0.emphasized ? emphasizedValueFont : valueFont) }
            .max() ?? 0
    }

    private func textWidth(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    private func drawText(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }
}

final class MenuSeparatorView: NSView {
    init(inset: CGFloat = 16) {
        self.inset = inset
        super.init(frame: NSRect(x: 0, y: 0, width: menuPanelWidth, height: 7))
        wantsLayer = true
        layer?.backgroundColor = (TaskBarBuild.isClassicPage ? menuPanelBackground : NSColor.clear).cgColor
    }

    private let inset: CGFloat

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        (TaskBarBuild.isClassicPage ? NSColor(calibratedWhite: 0.33, alpha: 0.72) : NSColor.white.withAlphaComponent(0.10)).setFill()
        NSRect(x: inset, y: floor(bounds.height / 2), width: bounds.width - inset * 2, height: 1).fill()
    }
}

final class CommandRowView: NSView {
    private let iconView = NSImageView(frame: .zero)
    private let titleLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let action: () -> Void
    private var trackingAreaRef: NSTrackingArea?
    private var isHovering = false {
        didSet { needsDisplay = true }
    }
    private let enabled: Bool

    init(title: String, symbolName: String, shortcut: String?, enabled: Bool = true, action: @escaping () -> Void) {
        self.action = action
        self.enabled = enabled
        super.init(frame: NSRect(x: 0, y: 0, width: menuPanelWidth, height: 27))
        wantsLayer = true
        layer?.backgroundColor = (TaskBarBuild.isClassicPage ? menuPanelBackground : NSColor.clear).cgColor

        let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        iconView.image = symbol?.withSymbolConfiguration(config)
        iconView.contentTintColor = enabled ? .labelColor : .disabledControlTextColor
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = enabled ? .labelColor : .disabledControlTextColor
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        shortcutLabel.stringValue = shortcut ?? ""
        shortcutLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        shortcutLabel.textColor = .secondaryLabelColor
        shortcutLabel.alignment = .right
        addSubview(shortcutLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        trackingAreaRef = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        guard enabled else { return }
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
    }

    override func mouseUp(with event: NSEvent) {
        guard enabled else { return }
        action()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isHovering else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 12, dy: 3), xRadius: 6, yRadius: 6).fill()
    }

    override func layout() {
        super.layout()
        iconView.frame = NSRect(x: 16, y: 6, width: 15, height: 15)
        shortcutLabel.frame = NSRect(x: bounds.width - 58, y: 5, width: 42, height: 16)
        titleLabel.frame = NSRect(x: 46, y: 4, width: bounds.width - 108, height: 18)
    }
}

final class CommandButtonBarView: NSView {
    private let settingsButton: TaskBarActionButton
    private let quitButton: TaskBarActionButton

    init(
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        settingsButton = CommandButtonBarView.makeButton(
            title: "Settings",
            symbolName: "gearshape",
            tint: NSColor(calibratedWhite: 0.78, alpha: 1),
            action: onOpenSettings
        )
        quitButton = CommandButtonBarView.makeButton(
            title: "Quit",
            symbolName: "power",
            tint: NSColor(calibratedRed: 0.94, green: 0.36, blue: 0.34, alpha: 1),
            action: onQuit
        )
        super.init(frame: NSRect(x: 0, y: 0, width: menuPanelWidth, height: 46))
        wantsLayer = true
        layer?.backgroundColor = (TaskBarBuild.isClassicPage ? menuPanelBackground : NSColor.clear).cgColor
        addSubview(settingsButton)
        addSubview(quitButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func makeButton(
        title: String,
        symbolName: String,
        tint: NSColor,
        action: @escaping () -> Void
    ) -> TaskBarActionButton {
        let button = TaskBarActionButton(title: title, action: action)
        button.isBordered = false
        button.wantsLayer = true
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = tint
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.toolTip = title
        button.attributedTitle = NSAttributedString(string: " " + title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: tint
        ])
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        image?.isTemplate = true
        button.image = image
        return button
    }

    override func layout() {
        super.layout()
        settingsButton.sizeToFit()
        var settingsFrame = settingsButton.frame
        settingsFrame.origin = NSPoint(x: 18, y: (bounds.height - settingsFrame.height) / 2)
        settingsButton.frame = settingsFrame

        quitButton.sizeToFit()
        var quitFrame = quitButton.frame
        quitFrame.origin = NSPoint(x: bounds.maxX - 18 - quitFrame.width, y: (bounds.height - quitFrame.height) / 2)
        quitButton.frame = quitFrame
    }
}

/// Centered "N of M tasks" summary strip below the list.
final class TaskCountView: NSView {
    private let label = NSTextField(labelWithString: "")

    init(shown: Int, total: Int) {
        super.init(frame: NSRect(x: 0, y: 0, width: menuPanelWidth, height: 26))
        wantsLayer = true
        layer?.backgroundColor = (TaskBarBuild.isBeta ? NSColor.clear : menuPanelBackground).cgColor
        label.font = .systemFont(ofSize: 10.5, weight: .medium)
        label.textColor = NSColor(calibratedWhite: 0.5, alpha: 1)
        label.alignment = .center
        addSubview(label)
        update(shown: shown, total: total)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(shown: Int, total: Int) {
        let noun = total == 1 ? "task" : "tasks"
        label.stringValue = "\(shown) of \(total) \(noun)"
    }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: 16, y: (bounds.height - 16) / 2, width: bounds.width - 32, height: 16)
    }
}

private final class TaskBarActionButton: NSButton {
    private let handler: () -> Void

    init(title: String, action: @escaping () -> Void) {
        handler = action
        super.init(frame: .zero)
        self.title = title
        target = self
        self.action = #selector(runAction)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func runAction() {
        handler()
    }
}

final class TaskBarRowsView: NSView {
    private let arrangedViews: [NSView]
    private let arrangedHeights: [CGFloat]

    init(rowViews: [NSView]) {
        arrangedViews = rowViews
        arrangedHeights = rowViews.map(\.frame.height)
        let height = arrangedHeights.reduce(CGFloat(0), +)
        super.init(frame: NSRect(x: 0, y: 0, width: menuPanelWidth, height: height))
        wantsLayer = true
        layer?.backgroundColor = menuPanelBackground.cgColor
        for view in rowViews {
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    func prepareForEntrance() {
        guard !TaskBarBuild.isClassicPage else { return }
        for view in arrangedViews {
            TaskBarMotion.prepareForReveal(view, offsetY: -8, scale: 0.99)
        }
    }

    func animateEntrance(startDelay: CFTimeInterval = 0.18) {
        guard !TaskBarBuild.isClassicPage else { return }
        for (index, view) in arrangedViews.prefix(8).enumerated() {
            TaskBarMotion.reveal(
                view,
                delay: startDelay + CFTimeInterval(index) * 0.045,
                offsetY: -8,
                scale: 0.99
            )
        }
    }

    func animateRefresh() {
        guard !TaskBarBuild.isClassicPage else { return }
        for (index, view) in arrangedViews.prefix(8).enumerated() {
            TaskBarMotion.prepareForReveal(view, offsetY: -5, scale: 0.995)
            TaskBarMotion.reveal(
                view,
                delay: CFTimeInterval(index) * 0.028,
                offsetY: -5,
                scale: 0.995
            )
        }
    }

    override func layout() {
        super.layout()
        var y: CGFloat = 0
        for (index, view) in arrangedViews.enumerated() {
            let height = arrangedHeights[index]
            view.frame = NSRect(x: 0, y: y, width: bounds.width, height: height)
            y += height
        }
    }
}
