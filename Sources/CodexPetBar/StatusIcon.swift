import Cocoa
import Foundation

final class PetStatusIcon {
    private var frame = 0

    func image(status: ThreadRunStatus?, showsRedDot: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        let color: NSColor
        switch status {
        case .running:
            color = NSColor.systemGreen
        case .stale:
            color = NSColor.systemYellow
        case .waiting:
            color = NSColor.systemYellow
        case .unread:
            color = NSColor.systemBlue
        case nil:
            color = NSColor.white.withAlphaComponent(0.58)
        }

        let bob = status == .running ? CGFloat((frame % 2 == 0) ? 0 : -1) : 0
        let head = NSRect(x: 2, y: 3 + bob, width: 14, height: 12)
        color.withAlphaComponent(0.95).setFill()
        NSBezierPath(roundedRect: head, xRadius: 5, yRadius: 5).fill()

        color.withAlphaComponent(0.88).setStroke()
        let antenna = NSBezierPath()
        antenna.lineWidth = 1.4
        antenna.move(to: NSPoint(x: 9, y: 3 + bob))
        antenna.line(to: NSPoint(x: 9, y: 1 + bob))
        antenna.stroke()

        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(ovalIn: NSRect(x: 5, y: 8 + bob, width: 2.2, height: 2.2)).fill()
        NSBezierPath(ovalIn: NSRect(x: 10.8, y: 8 + bob, width: 2.2, height: 2.2)).fill()

        if showsRedDot {
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: NSRect(x: 11.5, y: 1.5, width: 6, height: 6)).fill()
        }

        image.unlockFocus()
        image.isTemplate = false
        frame += 1
        return image
    }
}
