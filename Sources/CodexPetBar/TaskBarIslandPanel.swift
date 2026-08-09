import Cocoa
import QuartzCore

/// Borderless top-edge presenter for the Beta build. Unlike NSPopover it has no
/// pointer arrow: the shell grows down from the screen edge like a compact island.
final class TaskBarIslandPanel: NSPanel {
    private let hostView: TaskBarIslandHostView
    private var presentedContent: TaskBarPopoverContentView
    private var isDismissing = false

    init(content: TaskBarPopoverContentView) {
        presentedContent = content
        hostView = TaskBarIslandHostView(content: content)
        super.init(
            contentRect: NSRect(origin: .zero, size: content.frame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = true
        animationBehavior = .none
        contentView = hostView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func presentAnimated() {
        let expanded = expandedFrame(for: presentedContent.frame.size)
        let collapsed = collapsedFrame(for: expanded)
        setFrame(collapsed, display: false)
        presentedContent.alphaValue = 0
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.34
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.30, 1)
            animator().setFrame(expanded, display: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
            guard let self, self.isVisible, !self.isDismissing else { return }
            self.presentedContent.alphaValue = 1
            self.presentedContent.playEntranceMotion()
        }
    }

    func dismissAnimated() {
        guard isVisible, !isDismissing else { return }
        isDismissing = true
        let collapsed = collapsedFrame(for: frame)
        presentedContent.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.20
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.55, 0, 1, 0.45)
            animator().setFrame(collapsed, display: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            self?.orderOut(nil)
            self?.isDismissing = false
        }
    }

    func replaceContent(_ content: TaskBarPopoverContentView) {
        presentedContent = content
        hostView.replaceContent(content)
        guard isVisible else { return }
        setFrame(expandedFrame(for: content.frame.size), display: true)
    }

    func resizeContent(to size: NSSize) {
        guard isVisible else { return }
        setFrame(expandedFrame(for: size), display: true)
    }

    private func expandedFrame(for size: NSSize) -> NSRect {
        let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first
        let visible = targetScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: size.width, height: size.height)
        let width = min(size.width, visible.width - 24)
        return NSRect(
            x: visible.midX - width / 2,
            y: visible.maxY - size.height,
            width: width,
            height: size.height
        )
    }

    private func collapsedFrame(for expanded: NSRect) -> NSRect {
        let size = NSSize(width: 176, height: 32)
        return NSRect(
            x: expanded.midX - size.width / 2,
            y: expanded.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}

private final class TaskBarIslandHostView: NSView {
    private var content: TaskBarPopoverContentView

    init(content: TaskBarPopoverContentView) {
        self.content = content
        super.init(frame: NSRect(origin: .zero, size: content.frame.size))
        wantsLayer = true
        layer?.masksToBounds = true
        addSubview(content)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    func replaceContent(_ next: TaskBarPopoverContentView) {
        content.removeFromSuperview()
        content = next
        addSubview(content)
        needsLayout = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let radius = min(CGFloat(20), bounds.height / 2)
        let shell = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        if let gradient = NSGradient(
            starting: NSColor(calibratedRed: 0.065, green: 0.060, blue: 0.075, alpha: 0.995),
            ending: menuPanelBackground
        ) {
            gradient.draw(in: shell, angle: 90)
        } else {
            menuPanelBackground.setFill()
            shell.fill()
        }
        taskBarPanelBorder.setStroke()
        shell.lineWidth = 1
        shell.stroke()
    }

    override func layout() {
        super.layout()
        content.frame = bounds
    }
}
