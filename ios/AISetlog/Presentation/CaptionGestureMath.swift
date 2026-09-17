import CoreGraphics
import Foundation

/// The arithmetic behind the caption's handles, kept out of the view.
///
/// Both of these are the kind of thing that is wrong by a factor of two or a
/// sign for weeks without anybody noticing — a corner handle that shrinks when
/// you pull outwards still "works" — so they are plain functions with tests
/// rather than closures inside a gesture.
enum CaptionGestureMath {
    /// How far a one-finger corner drag has scaled and turned the sticker.
    ///
    /// Everything is measured from the sticker's centre: the finger's distance
    /// from it against where the handle started gives the scale, and the angle
    /// between those two vectors gives the rotation. That is the behaviour of
    /// the corner handle in Instagram Stories and 剪映 — one finger does both at
    /// once, which is the only way to resize a sticker while holding the phone
    /// in the same hand.
    ///
    /// - Returns: multipliers to apply to the saved scale and angle, or `nil`
    ///   when the gesture started on top of the centre, where there is no
    ///   vector to compare against and the scale would divide by ~zero.
    static func cornerDrag(
        centre: CGPoint, start: CGPoint, current: CGPoint
    ) -> (scale: Double, angleDelta: Double)? {
        let from = CGVector(dx: start.x - centre.x, dy: start.y - centre.y)
        let to = CGVector(dx: current.x - centre.x, dy: current.y - centre.y)
        let fromLength = hypot(from.dx, from.dy)
        let toLength = hypot(to.dx, to.dy)
        // 8pt, not zero: within a finger's width of the centre the angle
        // between the two vectors is noise, and the sticker spins.
        guard fromLength > 8, toLength > 0 else { return nil }
        let turn = atan2(to.dy, to.dx) - atan2(from.dy, from.dx)
        return (toLength / fromLength, Angle.degrees(from: turn))
    }

    /// Where a dragged sticker should actually land on one axis.
    ///
    /// Inside the threshold it lands exactly on the middle. Placing a caption
    /// visually centred by hand lands at 0.497 or 0.508, which is invisible on
    /// the phone and visible in the exported film next to a second clip whose
    /// caption is at 0.502.
    ///
    /// - Returns: the snapped fraction, or `nil` when the finger is too far out
    ///   for the guide to apply — the caller then uses the raw position, and
    ///   `nil` is also what tells it to hide the guide line.
    static func snapToCentre(_ fraction: Double, threshold: Double = 0.028) -> Double? {
        abs(fraction - 0.5) <= threshold ? 0.5 : nil
    }
}

private enum Angle {
    /// Radians to degrees, and never a whole turn's worth: two vectors an inch
    /// apart can read as +359° when the drag crosses the negative x axis, and
    /// added to a saved angle that clamps at ±35° it would slam the sticker
    /// to the stop instead of nudging it.
    static func degrees(from radians: Double) -> Double {
        var turn = radians * 180 / .pi
        while turn > 180 { turn -= 360 }
        while turn < -180 { turn += 360 }
        return turn
    }
}
