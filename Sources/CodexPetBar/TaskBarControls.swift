import Cocoa
import Foundation

enum TaskBarTab: Int, CaseIterable {
    case all
    case running
    case waiting
    case done

    var title: String {
        switch self {
        case .all: return "All"
        case .running: return "Running"
        case .waiting: return "Waiting"
        case .done: return "Done"
        }
    }

    func matches(_ status: ThreadRunStatus) -> Bool {
        switch self {
        case .all: return true
        case .running: return status == .running
        case .waiting: return status == .waiting
        case .done: return status == .unread
        }
    }

    var emptyMessage: String {
        switch self {
        case .all: return "No active Codex, Claude, or OpenCode tasks"
        case .running: return "Nothing running right now"
        case .waiting: return "Nothing waiting on you"
        case .done: return "No finished tasks to review"
        }
    }
}

/// The three user-facing status groups shown in the list. A `.stale` task remains
/// visible in All so it can be inspected, but is never presented as running.
/// Their relative order in the "All" tab is user-configurable (drag-to-reorder in
/// settings).
enum TaskStatusGroup: String, CaseIterable {
    case running
    case waiting
    case done

    /// Preserves the historical "All" ordering: waiting, then done, then running.
    static let defaultOrder: [TaskStatusGroup] = [.waiting, .done, .running]

    static func group(for status: ThreadRunStatus) -> TaskStatusGroup {
        switch status {
        case .running: return .running
        case .stale: return .done
        case .waiting: return .waiting
        case .unread: return .done
        }
    }

    var badge: String {
        switch self {
        case .running: return "RUN"
        case .waiting: return "WAIT"
        case .done: return "DONE"
        }
    }

    var displayName: String {
        switch self {
        case .running: return "运行中"
        case .waiting: return "待输入"
        case .done: return "已完成"
        }
    }

    var accentColor: NSColor {
        switch self {
        case .running: return statusAccentColor(.running)
        case .waiting: return statusAccentColor(.waiting)
        case .done: return statusAccentColor(.unread)
        }
    }
}

/// App-style rounded icon drawn to echo a checklist, matching the Task Bar mark.
final class TaskBarAppIconView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds
        let radius = rect.width * 0.28
        let background = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        let classic = TaskBarBuild.isClassicPage
        if let gradient = NSGradient(
            starting: classic ? NSColor(calibratedWhite: 1.0, alpha: 1.0) : NSColor(calibratedRed: 1.0, green: 0.69, blue: 0.35, alpha: 1.0),
            ending: classic ? NSColor(calibratedWhite: 0.85, alpha: 1.0) : NSColor(calibratedRed: 0.90, green: 0.30, blue: 0.22, alpha: 1.0)
        ) {
            gradient.draw(in: background, angle: 90)
        } else {
            (classic ? NSColor.white : taskBarWarmAccent).setFill()
            background.fill()
        }

        let bulletColors = classic
            ? [NSColor(calibratedRed: 0.96, green: 0.52, blue: 0.22, alpha: 1), NSColor(calibratedRed: 0.29, green: 0.55, blue: 0.96, alpha: 1), NSColor(calibratedRed: 0.96, green: 0.52, blue: 0.22, alpha: 1)]
            : [NSColor.white.withAlphaComponent(0.94), NSColor.white.withAlphaComponent(0.78), NSColor.white.withAlphaComponent(0.94)]
        let leftX = rect.width * 0.24
        let lineX = rect.width * 0.44
        let lineRight = rect.width * 0.76
        let bulletSize = rect.width * 0.13
        let lineHeight = rect.width * 0.085
        let rowSpacing = rect.height * 0.21
        let firstY = rect.height * 0.31
        for index in 0..<3 {
            let centerY = firstY + CGFloat(index) * rowSpacing
            let bulletRect = NSRect(x: leftX, y: centerY - bulletSize / 2, width: bulletSize, height: bulletSize)
            bulletColors[index].setFill()
            NSBezierPath(roundedRect: bulletRect, xRadius: bulletSize * 0.3, yRadius: bulletSize * 0.3).fill()
            let lineRect = NSRect(x: lineX, y: centerY - lineHeight / 2, width: lineRight - lineX, height: lineHeight)
            (classic ? NSColor(calibratedWhite: 0.52, alpha: 0.9) : NSColor.white.withAlphaComponent(0.62)).setFill()
            NSBezierPath(roundedRect: lineRect, xRadius: lineHeight / 2, yRadius: lineHeight / 2).fill()
        }
    }
}

extension TaskBarTab {
    var symbolName: String {
        switch self {
        case .all: return "list.bullet"
        case .running: return "play.circle.fill"
        case .waiting: return "clock.fill"
        case .done: return "checkmark.circle.fill"
        }
    }

    var tintColor: NSColor {
        switch self {
        case .all: return NSColor(calibratedWhite: 0.85, alpha: 1)
        case .running: return statusAccentColor(.running)
        case .waiting: return statusAccentColor(.waiting)
        case .done: return statusAccentColor(.unread)
        }
    }
}

/// Compact header chip such as "Running 3": muted label + colored count, optional leading dot.
final class CountChipView: NSView {
    private let dotView = NSView()
    private let titleLabel = NSTextField(labelWithString: TaskBarBuild.displayName)
    private let countLabel = NSTextField(labelWithString: "")
    private let showsDot: Bool

    init(title: String, count: Int, color: NSColor, showsDot: Bool) {
        self.showsDot = showsDot
        super.init(frame: .zero)
        wantsLayer = true

        if showsDot {
            dotView.wantsLayer = true
            dotView.layer?.backgroundColor = color.cgColor
            dotView.layer?.cornerRadius = 3
            addSubview(dotView)
            if count > 0, !TaskBarBuild.isClassicPage {
                TaskBarMotion.startLivePulse(on: dotView)
            }
        }

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = NSColor(calibratedWhite: 0.72, alpha: 1)
        addSubview(titleLabel)

        countLabel.stringValue = "\(count)"
        countLabel.font = .systemFont(ofSize: 11.5, weight: .bold)
        countLabel.textColor = count > 0 ? color : color.withAlphaComponent(0.45)
        addSubview(countLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func textWidth(_ field: NSTextField) -> CGFloat {
        let font = field.font ?? NSFont.systemFont(ofSize: 12)
        return ceil((field.stringValue as NSString).size(withAttributes: [.font: font]).width)
    }

    var preferredWidth: CGFloat {
        let dotWidth: CGFloat = showsDot ? 6 + 6 : 0
        return 11 + dotWidth + textWidth(titleLabel) + 6 + textWidth(countLabel) + 12
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor(calibratedWhite: 1.0, alpha: 0.05).setFill()
        path.fill()
        path.lineWidth = 1
        NSColor(calibratedWhite: 1.0, alpha: 0.12).setStroke()
        path.stroke()
    }

    override func layout() {
        super.layout()
        let midY = bounds.midY
        var x: CGFloat = 11
        if showsDot {
            dotView.frame = NSRect(x: x, y: midY - 3, width: 6, height: 6)
            x += 6 + 6
        }
        let titleW = textWidth(titleLabel)
        titleLabel.frame = NSRect(x: x, y: midY - 8, width: titleW, height: 16)
        x += titleW + 6
        countLabel.frame = NSRect(x: x, y: midY - 8, width: textWidth(countLabel) + 2, height: 16)
    }
}

final class PanelHeaderView: NSView {
    private let iconView = TaskBarAppIconView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let eyebrowLabel = NSTextField(labelWithString: TaskBarBuild.liveWorkspaceLabel)
    private let summaryLabel = NSTextField(labelWithString: "")
    private var chips: [CountChipView] = []

    init(runningCount: Int, waitingCount: Int, unreadCount: Int) {
        let classic = TaskBarBuild.isClassicPage
        super.init(frame: NSRect(x: 0, y: 0, width: menuPanelWidth, height: classic ? 56 : 76))
        wantsLayer = true

        addSubview(iconView)

        eyebrowLabel.isHidden = classic
        eyebrowLabel.font = .monospacedSystemFont(ofSize: 9.5, weight: .bold)
        eyebrowLabel.textColor = taskBarWarmAccent
        eyebrowLabel.lineBreakMode = .byClipping
        addSubview(eyebrowLabel)

        titleLabel.font = .systemFont(ofSize: classic ? 15 : 18, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        summaryLabel.isHidden = classic
        summaryLabel.stringValue = PanelHeaderView.activitySummary(
            runningCount: runningCount,
            waitingCount: waitingCount,
            unreadCount: unreadCount
        )
        summaryLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        summaryLabel.textColor = NSColor(calibratedWhite: 0.54, alpha: 1)
        summaryLabel.alignment = .right
        summaryLabel.lineBreakMode = .byTruncatingTail
        addSubview(summaryLabel)

        chips = [
            CountChipView(title: "Running", count: runningCount, color: statusAccentColor(.running), showsDot: true),
            CountChipView(title: "Waiting", count: waitingCount, color: statusAccentColor(.waiting), showsDot: false),
            CountChipView(title: "Done", count: unreadCount, color: statusAccentColor(.unread), showsDot: false)
        ]
        chips.forEach { addSubview($0) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func activitySummary(runningCount: Int, waitingCount: Int, unreadCount: Int) -> String {
        if runningCount == 0 && waitingCount == 0 && unreadCount == 0 {
            return "All caught up"
        }
        var parts: [String] = []
        if runningCount > 0 { parts.append("\(runningCount) running") }
        if waitingCount > 0 { parts.append("\(waitingCount) waiting") }
        if unreadCount > 0 { parts.append("\(unreadCount) unread") }
        return parts.joined(separator: "  ·  ")
    }

    override func layout() {
        super.layout()
        let classic = TaskBarBuild.isClassicPage
        let iconSize: CGFloat = classic ? 26 : 38
        iconView.frame = classic ? NSRect(x: 18, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize) : NSRect(x: 20, y: 19, width: iconSize, height: iconSize)

        let chipHeight: CGFloat = classic ? 24 : 22
        let spacing: CGFloat = classic ? 7 : 6
        var rightEdge = bounds.maxX - (classic ? 18 : 20)
        for chip in chips.reversed() {
            let width = chip.preferredWidth
            chip.frame = NSRect(x: rightEdge - width, y: classic ? (bounds.height - chipHeight) / 2 : 27, width: width, height: chipHeight)
            rightEdge -= (width + spacing)
        }

        let titleX = iconView.frame.maxX + 11
        let chipsLeft = chips.first?.frame.minX ?? bounds.maxX
        eyebrowLabel.frame = NSRect(x: titleX, y: 17, width: 160, height: 13)
        titleLabel.frame = classic ? NSRect(x: titleX, y: (bounds.height - 24) / 2, width: max(0, chipsLeft - 10 - titleX), height: 24) : NSRect(x: titleX, y: 32, width: 130, height: 24)
        summaryLabel.frame = NSRect(x: titleX + 140, y: 48, width: max(0, chipsLeft - 10 - (titleX + 140)), height: 14)
    }
}

/// Segmented control with icons (All / Running / Waiting / Done) for filtering tasks.
final class TaskBarTabsView: NSView {
    private let tabs: [TaskBarTab]
    private var selectedIndex: Int
    var onSelect: (TaskBarTab) -> Void
    private let selectionHighlight = NSView()
    private var iconViews: [NSImageView] = []
    private var labelViews: [NSTextField] = []

    init(tabs: [TaskBarTab], selected: TaskBarTab, allTaskCount: Int, onSelect: @escaping (TaskBarTab) -> Void) {
        self.tabs = tabs
        self.selectedIndex = tabs.firstIndex(of: selected) ?? 0
        self.onSelect = onSelect
        super.init(frame: NSRect(x: 0, y: 0, width: menuPanelWidth, height: TaskBarBuild.isClassicPage ? 42 : 48))
        wantsLayer = true

        selectionHighlight.wantsLayer = true
        selectionHighlight.layer?.cornerRadius = 7
        selectionHighlight.layer?.backgroundColor = (TaskBarBuild.isClassicPage ? NSColor(calibratedWhite: 1.0, alpha: 0.16) : taskBarWarmAccent.withAlphaComponent(0.18)).cgColor
        selectionHighlight.layer?.borderWidth = 1
        selectionHighlight.layer?.borderColor = (TaskBarBuild.isClassicPage ? NSColor(calibratedWhite: 1.0, alpha: 0.08) : taskBarWarmAccent.withAlphaComponent(0.34)).cgColor
        addSubview(selectionHighlight)

        for (index, tab) in tabs.enumerated() {
            let isSelected = index == selectedIndex
            let icon = NSImageView()
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            icon.image = NSImage(systemSymbolName: tab.symbolName, accessibilityDescription: tab.title)?
                .withSymbolConfiguration(config)
            icon.contentTintColor = tab.tintColor
            icon.imageScaling = .scaleProportionallyDown
            addSubview(icon)
            iconViews.append(icon)

            let labelText = tab == .all ? "\(tab.title) \(allTaskCount)" : tab.title
            let label = NSTextField(labelWithString: labelText)
            label.font = .systemFont(ofSize: 11.5, weight: isSelected ? .semibold : .medium)
            label.textColor = isSelected ? .white : NSColor(calibratedWhite: 0.6, alpha: 1)
            label.lineBreakMode = .byClipping
            label.setAccessibilityLabel(tab == .all ? "All, \(allTaskCount) tasks" : tab.title)
            addSubview(label)
            labelViews.append(label)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var containerRect: NSRect {
        TaskBarBuild.isClassicPage ? NSRect(x: 14, y: 6, width: bounds.width - 28, height: 30) : NSRect(x: 18, y: 7, width: bounds.width - 36, height: 34)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let container = containerRect
        (TaskBarBuild.isClassicPage ? NSColor(calibratedWhite: 1.0, alpha: 0.08) : NSColor.white.withAlphaComponent(0.045)).setFill()
        NSBezierPath(roundedRect: container, xRadius: 9, yRadius: 9).fill()
        if !TaskBarBuild.isClassicPage {
            taskBarPanelBorder.withAlphaComponent(0.62).setStroke()
            NSBezierPath(roundedRect: container.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9).stroke()
        }

        let segmentWidth = container.width / CGFloat(tabs.count)
        let cell = NSRect(
            x: container.minX + CGFloat(selectedIndex) * segmentWidth,
            y: container.minY,
            width: segmentWidth,
            height: container.height
        ).insetBy(dx: 3, dy: 3)
        _ = cell
    }

    private func labelWidth(_ field: NSTextField) -> CGFloat {
        let font = field.font ?? NSFont.systemFont(ofSize: 12.5)
        return ceil((field.stringValue as NSString).size(withAttributes: [.font: font]).width)
    }

    override func layout() {
        super.layout()
        let container = containerRect
        let segmentWidth = container.width / CGFloat(tabs.count)
        selectionHighlight.frame = selectionFrame(in: container, segmentWidth: segmentWidth)
        let iconWidth: CGFloat = 14
        let gap: CGFloat = 6
        for index in tabs.indices {
            let cell = NSRect(
                x: container.minX + CGFloat(index) * segmentWidth,
                y: container.minY,
                width: segmentWidth,
                height: container.height
            )
            let label = labelViews[index]
            let icon = iconViews[index]
            let width = labelWidth(label)
            let groupWidth = iconWidth + gap + width
            let startX = cell.midX - groupWidth / 2
            icon.frame = NSRect(x: startX, y: cell.midY - 7, width: iconWidth, height: 14)
            label.frame = NSRect(x: startX + iconWidth + gap, y: cell.midY - 8, width: width + 1, height: 16)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let container = containerRect
        guard container.insetBy(dx: 0, dy: -6).contains(point) else { return }
        let segmentWidth = container.width / CGFloat(tabs.count)
        let index = min(tabs.count - 1, max(0, Int((point.x - container.minX) / segmentWidth)))
        guard index != selectedIndex else { return }
        let previousFrame = selectionHighlight.frame
        selectedIndex = index
        for (labelIndex, label) in labelViews.enumerated() {
            let selected = labelIndex == selectedIndex
            label.font = .systemFont(ofSize: 11.5, weight: selected ? .semibold : .medium)
            label.textColor = selected ? .white : NSColor(calibratedWhite: 0.6, alpha: 1)
        }
        needsDisplay = true
        needsLayout = true
        layoutSubtreeIfNeeded()
        let nextFrame = selectionHighlight.frame
        guard !TaskBarBuild.isClassicPage else {
            selectionHighlight.frame = nextFrame
            onSelect(tabs[index])
            return
        }
        selectionHighlight.frame = previousFrame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.30, 1)
            selectionHighlight.animator().frame = nextFrame
        }
        onSelect(tabs[index])
    }

    private func selectionFrame(in container: NSRect, segmentWidth: CGFloat) -> NSRect {
        NSRect(
            x: container.minX + CGFloat(selectedIndex) * segmentWidth,
            y: container.minY,
            width: segmentWidth,
            height: container.height
        ).insetBy(dx: 3, dy: 3)
    }
}

final class EmptyStateView: NSView {
    private let label = NSTextField(labelWithString: "")

    init(message: String = "") {
        super.init(frame: NSRect(x: 0, y: 0, width: menuPanelWidth, height: taskBarEmptyStateHeight))
        label.stringValue = message
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = NSColor(calibratedWhite: 0.55, alpha: 1)
        label.alignment = .center
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 2
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: 20, y: (bounds.height - 34) / 2, width: bounds.width - 40, height: 34)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !TaskBarBuild.isClassicPage else { return }
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 18, dy: 10), xRadius: 14, yRadius: 14)
        taskBarCardBackground.setFill()
        card.fill()
        taskBarPanelBorder.withAlphaComponent(0.65).setStroke()
        card.lineWidth = 1
        card.stroke()
    }
}
