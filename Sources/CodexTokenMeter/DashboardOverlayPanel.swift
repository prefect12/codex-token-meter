import Cocoa

/// A compact, top-of-screen dashboard surface. Unlike an NSPopover it has no
/// attachment arrow, so the dashboard reads as one deliberate floating panel.
final class DashboardOverlayPanel: NSPanel {
    private weak var anchorButton: NSStatusBarButton?

    init(contentViewController: NSViewController) {
        super.init(
            contentRect: NSRect(origin: .zero, size: DashboardView.idealSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.contentViewController = contentViewController
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = true
        isMovable = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func show(anchoredTo button: NSStatusBarButton, size: NSSize) {
        anchorButton = button
        setContentSize(size)
        position(on: button.window?.screen ?? NSScreen.main)
        makeKeyAndOrderFront(nil)
    }

    func resize(to size: NSSize) {
        setContentSize(size)
        if isVisible {
            position(on: anchorButton?.window?.screen ?? screen ?? NSScreen.main)
        }
    }

    private func position(on screen: NSScreen?) {
        guard let screen else { return }
        let visibleFrame = screen.visibleFrame
        let size = frame.size
        let topInset: CGFloat = 16
        let x = visibleFrame.midX - size.width / 2
        let y = visibleFrame.maxY - size.height - topInset
        setFrameOrigin(NSPoint(x: round(x), y: round(y)))
    }
}
