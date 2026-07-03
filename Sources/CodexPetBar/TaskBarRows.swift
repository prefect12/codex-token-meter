import Cocoa
import Foundation

final class ThreadRowView: NSView {
    private let item: CodexThreadItem
    private let onOpen: (String) -> Void
    private let onDismiss: (String) -> Void
    private let showPlatformLabel: Bool
    private let rowLayout: TaskRowLayoutStyle
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let clockIconView = NSImageView()
    private let durationLabel = NSTextField(labelWithString: "")
    private let metaDotView = NSView()
    private let metaStatusLabel = NSTextField(labelWithString: "")
    private let platformLabel = NSTextField(labelWithString: "")
    private var trackingAreaRef: NSTrackingArea?
    private var elapsedTimer: Timer?
    private var mouseDownPoint = NSPoint.zero
    private var dragStartOffset: CGFloat = 0
    private var swipeOffset: CGFloat = 0
    private var isSwipeTracking = false
    private var scrollSwipeSettleTimer: Timer?
    private var didDrag = false
    private var isHovering = false {
        didSet { needsDisplay = true }
    }

    init(
        item: CodexThreadItem,
        showPlatformLabel: Bool,
        rowLayout: TaskRowLayoutStyle,
        onOpen: @escaping (String) -> Void,
        onDismiss: @escaping (String) -> Void
    ) {
        self.item = item
        self.showPlatformLabel = showPlatformLabel
        self.rowLayout = rowLayout
        self.onOpen = onOpen
        self.onDismiss = onDismiss
        super.init(frame: NSRect(x: 0, y: 0, width: menuPanelWidth, height: rowLayout.rowHeight))
        wantsLayer = true
        let tooltip = tooltipText(for: item)
        setAccessibilityHelp(tooltip)

        let accent = statusAccentColor(item.status)

        titleLabel.stringValue = item.title
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
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
        ThreadHoverPanel.shared.show(item: item, from: self)
    }

    override func mouseMoved(with event: NSEvent) {
        guard isHovering else { return }
        ThreadHoverPanel.shared.show(item: item, from: self)
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
        guard isReadDismissible(item.status) else {
            didDrag = hypot(deltaX, deltaY) > 3
            return
        }

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
        onOpen(item.id)
    }

    override func scrollWheel(with event: NSEvent) {
        guard isReadDismissible(item.status), event.hasPreciseScrollingDeltas else {
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

        // Divider between rows.
        NSColor(calibratedWhite: 1.0, alpha: 0.06).setFill()
        NSRect(x: 20, y: 0, width: bounds.width - 40, height: 1).fill()

        // Colored status accent bar at the leading edge.
        if !isSwipeTracking || swipeOffset > -1 {
            let barRect = NSRect(x: 8 + swipeOffset, y: 14, width: 3.5, height: bounds.height - 28)
            statusAccentColor(item.status).setFill()
            NSBezierPath(roundedRect: barRect, xRadius: 1.75, yRadius: 1.75).fill()
        }

        if swipeOffset < -1, isReadDismissible(item.status) {
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
        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 4), xRadius: 12, yRadius: 12).fill()
    }

    override func layout() {
        super.layout()
        switch rowLayout {
        case .standard: layoutStandard()
        case .compact: layoutCompact()
        }
    }

    /// Title and detail stacked over a single metadata line (time · status · source).
    private func layoutStandard() {
        let offset = swipeOffset
        let contentX: CGFloat = 26
        let contentWidth = max(120, bounds.width - 18 - contentX)

        titleLabel.frame = NSRect(x: contentX + offset, y: bounds.height - 32, width: contentWidth, height: 20)
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
        let contentX: CGFloat = 26
        let railWidth: CGFloat = 66
        let railGap: CGFloat = 10
        let rightX = contentX + railWidth + railGap
        let rightWidth = max(80, bounds.width - 18 - rightX)

        titleLabel.frame = NSRect(x: rightX + offset, y: bounds.height - 30, width: rightWidth, height: 20)
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
    static let shared = ThreadHoverPanel()

    private weak var owner: NSView?
    private let tooltipView = ThreadTooltipView()
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

    func show(item: CodexThreadItem, from sourceView: NSView) {
        owner = sourceView
        let rows = tooltipRows(for: item)
        guard !rows.isEmpty else {
            panel.orderOut(nil)
            return
        }
        tooltipView.rows = rows
        let size = tooltipView.preferredSize
        tooltipView.frame = NSRect(origin: .zero, size: size)
        panel.setFrame(NSRect(origin: origin(for: size), size: size), display: true)
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

    private func origin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let visibleFrame = NSScreen.screens.first { $0.frame.contains(mouse) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let margin: CGFloat = 8
        var x = mouse.x + 16
        var y = mouse.y - size.height - 12

        if x + size.width > visibleFrame.maxX - margin {
            x = mouse.x - size.width - 16
        }
        if y < visibleFrame.minY + margin {
            y = mouse.y + 16
        }

        x = min(max(x, visibleFrame.minX + margin), visibleFrame.maxX - size.width - margin)
        y = min(max(y, visibleFrame.minY + margin), visibleFrame.maxY - size.height - margin)
        return NSPoint(x: x, y: y)
    }
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
        layer?.backgroundColor = menuPanelBackground.cgColor
    }

    private let inset: CGFloat

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor(calibratedWhite: 0.33, alpha: 0.72).setFill()
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
        layer?.backgroundColor = menuPanelBackground.cgColor

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
        layer?.backgroundColor = menuPanelBackground.cgColor
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
        layer?.backgroundColor = menuPanelBackground.cgColor
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
