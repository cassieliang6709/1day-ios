import CoreGraphics
import Foundation

enum PiPInsetLayout {
    static let defaultShare: CGFloat = 0.3
    static let minShare: CGFloat = 0.22
    static let maxShare: CGFloat = 0.45
    static let marginShare: CGFloat = 0.04
    static let borderShare: CGFloat = 0.012
    static let cornerShare: CGFloat = 0.035

    static let storageKey = "pipInsetRect"

    static func defaultRect(aspect: CGFloat = 9.0 / 16.0) -> CGRect {
        let share = defaultShare
        let marginY = marginShare * aspect
        return CGRect(x: 1 - marginShare - share, y: marginY, width: share, height: share)
    }

    static func clamped(_ rect: CGRect) -> CGRect {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.width > 0
        else { return defaultRect() }
        let share = min(max(rect.width, minShare), maxShare)
        let x = min(max(rect.origin.x, 0), 1 - share)
        let y = min(max(rect.origin.y, 0), 1 - share)
        return CGRect(x: x, y: y, width: share, height: share)
    }

    static func moved(_ rect: CGRect, by translation: CGSize, in canvas: CGSize) -> CGRect {
        guard canvas.width > 0, canvas.height > 0 else { return clamped(rect) }
        return clamped(rect.offsetBy(
            dx: translation.width / canvas.width,
            dy: translation.height / canvas.height))
    }

    static func resized(_ rect: CGRect, by scale: CGFloat) -> CGRect {
        guard scale.isFinite, scale > 0 else { return clamped(rect) }
        let share = min(max(rect.width * scale, minShare), maxShare)
        return clamped(CGRect(
            x: rect.midX - share / 2, y: rect.midY - share / 2,
            width: share, height: share))
    }

    static func adjusted(
        _ start: CGRect, scale: CGFloat, translation: CGSize, in canvas: CGSize
    ) -> CGRect {
        moved(resized(start, by: scale), by: translation, in: canvas)
    }

    static func box(_ rect: CGRect, in canvas: CGSize) -> CGRect {
        let rect = clamped(rect)
        return CGRect(
            x: rect.minX * canvas.width, y: rect.minY * canvas.height,
            width: rect.width * canvas.width, height: rect.height * canvas.height)
    }

    static func border(in canvas: CGSize) -> CGFloat { canvas.width * borderShare }
    static func cornerRadius(in canvas: CGSize) -> CGFloat { canvas.width * cornerShare }

    static func pictureBox(_ rect: CGRect, in canvas: CGSize) -> CGRect {
        let inset = border(in: canvas)
        return box(rect, in: canvas).insetBy(dx: inset, dy: inset)
    }


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
