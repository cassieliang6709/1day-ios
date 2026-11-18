import CoreGraphics
import Foundation

enum CaptionGestureMath {
    static func cornerDrag(
        centre: CGPoint, start: CGPoint, current: CGPoint
    ) -> (scale: Double, angleDelta: Double)? {
        let from = CGVector(dx: start.x - centre.x, dy: start.y - centre.y)
        let to = CGVector(dx: current.x - centre.x, dy: current.y - centre.y)
        let fromLength = hypot(from.dx, from.dy)
        let toLength = hypot(to.dx, to.dy)
        guard fromLength > 8, toLength > 0 else { return nil }
        let turn = atan2(to.dy, to.dx) - atan2(from.dy, from.dx)
        return (toLength / fromLength, Angle.degrees(from: turn))
    }

    static func snapToCentre(_ fraction: Double, threshold: Double = 0.028) -> Double? {
        abs(fraction - 0.5) <= threshold ? 0.5 : nil
    }
}

private enum Angle {
    static func degrees(from radians: Double) -> Double {
        var turn = radians * 180 / .pi
        while turn > 180 { turn -= 360 }
        while turn < -180 { turn += 360 }
        return turn
    }
}
