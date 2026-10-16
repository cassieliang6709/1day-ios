import CoreGraphics
import Foundation

/// Where the dual-camera inset sits, and how it is framed — the one set of
/// numbers both the viewfinder (`DualCameraStage`) and the file
/// (`PiPComposer`) read, so what is framed is what gets filmed.
///
/// The position is a normalized rect: x and width are shares of the canvas
/// width, y and height shares of its height. Width and height are always the
/// same share, which keeps the inset the canvas's own shape whatever the
/// canvas is — the same rect works on a 9:16 preview, a 1080×1920 file and a
/// square crop.
///
/// The look is a white-bordered snapshot: a white rounded frame inside the
/// box, the picture inside the frame. Border and corner are shares of the
/// canvas width rather than points, so the 4pt border on a ~350pt preview is
/// the same proportion of a 1080px file.
enum PiPInsetLayout {
    /// Inset width as a share of the canvas width, when nobody has moved it.
    static let defaultShare: CGFloat = 0.3
    /// Pinch limits. Under ~22% the inset is a stamp you can't see a face in;
    /// over ~45% it covers the picture it is meant to sit on.
    static let minShare: CGFloat = 0.22
    static let maxShare: CGFloat = 0.45
    /// Gap from the frame's edge for the default top-right spot.
    static let marginShare: CGFloat = 0.04
    /// White border width, as a share of the canvas width (~4pt on a phone
    /// preview).
    static let borderShare: CGFloat = 0.012
    /// Outer corner radius, as a share of the canvas width. The inner radius
    /// (this minus the border) must stay at or under `(1 + √2) × border` —
    /// so this at or under `(2 + √2) × borderShare`: the picture under the
    /// frame is a plain rectangle in the export, and past that its square
    /// corners poke out beyond the frame's rounded outer edge.
    static let cornerShare: CGFloat = 0.035

    static let storageKey = "pipInsetRect"

    /// Top-right, `defaultShare` wide — where the inset sat before it could
    /// be moved.
    static func defaultRect(aspect: CGFloat = 9.0 / 16.0) -> CGRect {
        let share = defaultShare
        // The margin is the same distance in points on both edges, so its
        // height share depends on the canvas shape.
        let marginY = marginShare * aspect
        return CGRect(x: 1 - marginShare - share, y: marginY, width: share, height: share)
    }

    /// Keeps a rect the canvas's shape, inside the size limits and fully
    /// inside the frame. Anything not finite falls back to the default.
    static func clamped(_ rect: CGRect) -> CGRect {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.width > 0
        else { return defaultRect() }
        let share = min(max(rect.width, minShare), maxShare)
        let x = min(max(rect.origin.x, 0), 1 - share)
        let y = min(max(rect.origin.y, 0), 1 - share)
        return CGRect(x: x, y: y, width: share, height: share)
    }

    /// The rect after a drag of `translation` points on a `canvas`-sized
    /// viewfinder, clamped.
    static func moved(_ rect: CGRect, by translation: CGSize, in canvas: CGSize) -> CGRect {
        guard canvas.width > 0, canvas.height > 0 else { return clamped(rect) }
        return clamped(rect.offsetBy(
            dx: translation.width / canvas.width,
            dy: translation.height / canvas.height))
    }

    /// The rect after a pinch of `scale`, grown or shrunk around its centre,
    /// clamped.
    static func resized(_ rect: CGRect, by scale: CGFloat) -> CGRect {
        guard scale.isFinite, scale > 0 else { return clamped(rect) }
        let share = min(max(rect.width * scale, minShare), maxShare)
        return clamped(CGRect(
            x: rect.midX - share / 2, y: rect.midY - share / 2,
            width: share, height: share))
    }

    /// The box on a real canvas, in its points or pixels.
    static func box(_ rect: CGRect, in canvas: CGSize) -> CGRect {
        let rect = clamped(rect)
        return CGRect(
            x: rect.minX * canvas.width, y: rect.minY * canvas.height,
            width: rect.width * canvas.width, height: rect.height * canvas.height)
    }

    static func border(in canvas: CGSize) -> CGFloat { canvas.width * borderShare }
    static func cornerRadius(in canvas: CGSize) -> CGFloat { canvas.width * cornerShare }

    /// Where the picture itself goes: the box minus the white border.
    static func pictureBox(_ rect: CGRect, in canvas: CGSize) -> CGRect {
        let inset = border(in: canvas)
        return box(rect, in: canvas).insetBy(dx: inset, dy: inset)
    }

    // MARK: Persistence

    /// The last place someone put the inset, or the default.
    static func load(from defaults: UserDefaults = .standard) -> CGRect {
        guard let values = defaults.array(forKey: storageKey) as? [Double], values.count == 4
        else { return defaultRect() }
        return clamped(CGRect(x: values[0], y: values[1], width: values[2], height: values[3]))
    }

    static func save(_ rect: CGRect, to defaults: UserDefaults = .standard) {
        let rect = clamped(rect)
        defaults.set(
            [rect.minX, rect.minY, rect.width, rect.height].map(Double.init),
            forKey: storageKey)
    }
}
