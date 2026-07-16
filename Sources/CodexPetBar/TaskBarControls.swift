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
        case .all: return "No active Codex or Claude tasks"
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
        if let gradient = NSGradient(
            starting: NSColor(calibratedWhite: 1.0, alpha: 1.0),
            ending: NSColor(calibratedWhite: 0.85, alpha: 1.0)
        ) {
            gradient.draw(in: background, angle: 90)
        } else {
            NSColor.white.setFill()
            background.fill()
        }

        let bulletColors = [
            NSColor(calibratedRed: 0.96, green: 0.52, blue: 0.22, alpha: 1),
            NSColor(calibratedRed: 0.29, green: 0.55, blue: 0.96, alpha: 1),
            NSColor(calibratedRed: 0.96, green: 0.52, blue: 0.22, alpha: 1)
        ]
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
            NSColor(calibratedWhite: 0.52, alpha: 0.9).setFill()
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
    private let titleLabel = NSTextField(labelWithString: "")
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
    private let titleLabel = NSTextField(labelWithString: "Task Bar")
    private var chips: [CountChipView] = []

    init(runningCount: Int, waitingCount: Int, unreadCount: Int) {
        super.init(frame: NSRect(x: 0, y: 0, width: menuPanelWidth, height: 56))
        wantsLayer = true

        addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

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

    override func layout() {
        super.layout()
        let iconSize: CGFloat = 26
        iconView.frame = NSRect(x: 18, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)

        let chipHeight: CGFloat = 24
        let spacing: CGFloat = 7
        var rightEdge = bounds.maxX - 18
        for chip in chips.reversed() {
            let width = chip.preferredWidth
            chip.frame = NSRect(x: rightEdge - width, y: (bounds.height - chipHeight) / 2, width: width, height: chipHeight)
            rightEdge -= (width + spacing)
        }

        let titleX = iconView.frame.maxX + 11
        let chipsLeft = chips.first?.frame.minX ?? bounds.maxX
        titleLabel.frame = NSRect(x: titleX, y: (bounds.height - 24) / 2, width: max(0, chipsLeft - 10 - titleX), height: 24)
    }
}

/// Segmented control with icons (All / Running / Waiting / Done) for filtering tasks.
final class TaskBarTabsView: NSView {
    private let tabs: [TaskBarTab]
    private var selectedIndex: Int
    var onSelect: (TaskBarTab) -> Void
    private var iconViews: [NSImageView] = []
    private var labelViews: [NSTextField] = []

    init(tabs: [TaskBarTab], selected: TaskBarTab, onSelect: @escaping (TaskBarTab) -> Void) {
        self.tabs = tabs
        self.selectedIndex = tabs.firstIndex(of: selected) ?? 0
        self.onSelect = onSelect
        super.init(frame: NSRect(x: 0, y: 0, width: menuPanelWidth, height: 42))
        wantsLayer = true

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

            let label = NSTextField(labelWithString: tab.title)
            label.font = .systemFont(ofSize: 11.5, weight: isSelected ? .semibold : .medium)
            label.textColor = isSelected ? .white : NSColor(calibratedWhite: 0.6, alpha: 1)
            label.lineBreakMode = .byClipping
            addSubview(label)
            labelViews.append(label)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var containerRect: NSRect {
        NSRect(x: 14, y: 6, width: bounds.width - 28, height: 30)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let container = containerRect
        NSColor(calibratedWhite: 1.0, alpha: 0.08).setFill()
        NSBezierPath(roundedRect: container, xRadius: 9, yRadius: 9).fill()

        let segmentWidth = container.width / CGFloat(tabs.count)
        let cell = NSRect(
            x: container.minX + CGFloat(selectedIndex) * segmentWidth,
            y: container.minY,
            width: segmentWidth,
            height: container.height
        ).insetBy(dx: 3, dy: 3)
        let selection = NSBezierPath(roundedRect: cell, xRadius: 7, yRadius: 7)
        NSColor(calibratedWhite: 1.0, alpha: 0.16).setFill()
        selection.fill()
        selection.lineWidth = 1
        NSColor(calibratedWhite: 1.0, alpha: 0.08).setStroke()
        selection.stroke()
    }

    private func labelWidth(_ field: NSTextField) -> CGFloat {
        let font = field.font ?? NSFont.systemFont(ofSize: 12.5)
        return ceil((field.stringValue as NSString).size(withAttributes: [.font: font]).width)
    }

    override func layout() {
        super.layout()
        let container = containerRect
        let segmentWidth = container.width / CGFloat(tabs.count)
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
        selectedIndex = index
        needsDisplay = true
        onSelect(tabs[index])
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
}
