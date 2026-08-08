import Cocoa
import QuartzCore

/// Small, native motion primitives shared by Task Bar's popover surfaces.
/// They deliberately animate state changes instead of replaying a decorative loop.
enum TaskBarMotion {
    private static let entranceCurve = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.30, 1.0)

    static func prepareForReveal(_ view: NSView, offsetY: CGFloat = -10, scale: CGFloat = 0.985) {
        guard let layer = preparedLayer(for: view) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 0
        layer.transform = startingTransform(offsetY: offsetY, scale: scale)
        CATransaction.commit()
    }

    static func reveal(
        _ view: NSView,
        delay: CFTimeInterval,
        offsetY: CGFloat = -10,
        scale: CGFloat = 0.985
    ) {
        guard let layer = preparedLayer(for: view) else { return }
        let transform = CABasicAnimation(keyPath: "transform")
        transform.fromValue = startingTransform(offsetY: offsetY, scale: scale)
        transform.toValue = CATransform3DIdentity

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0
        opacity.toValue = 1

        let group = CAAnimationGroup()
        group.animations = [transform, opacity]
        group.duration = 0.34
        group.beginTime = CACurrentMediaTime() + delay
        group.timingFunction = entranceCurve
        group.fillMode = .both
        group.isRemovedOnCompletion = true

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 1
        layer.transform = CATransform3DIdentity
        CATransaction.commit()
        layer.add(group, forKey: "taskBarReveal")
    }

    static func startLivePulse(on view: NSView) {
        guard let layer = preparedLayer(for: view), layer.animation(forKey: "taskBarLivePulse") == nil else { return }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = 1.55

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 1
        opacity.toValue = 0.42

        let group = CAAnimationGroup()
        group.animations = [scale, opacity]
        group.duration = 0.92
        group.autoreverses = true
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(group, forKey: "taskBarLivePulse")
    }

    private static func preparedLayer(for view: NSView) -> CALayer? {
        view.wantsLayer = true
        return view.layer
    }

    private static func startingTransform(offsetY: CGFloat, scale: CGFloat) -> CATransform3D {
        CATransform3DTranslate(CATransform3DMakeScale(scale, scale, 1), 0, offsetY, 0)
    }
}
