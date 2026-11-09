import CoreGraphics
import UIKit

/// Paints an `AvatarDecorLayout` around a cut-out head.
///
/// Order, back to front: the rainbow bands and the white band (the head's
/// silhouette, shifted around each band's offsets and filled flat), the head
/// itself, the blush, the stickers. Nothing touches the face's shape: no
/// smoothing, no slimming, no eye enlarging — the head is drawn exactly as the
/// first layer handed it over.
///
/// `progress` is for the 「正在画你」 screen, which shows the outline and the
/// stickers growing in: 0 is the bare head, 1 the finished avatar.
enum AvatarDecorator {
    static func render(head: CGImage, layout: AvatarDecorLayout, progress: CGFloat = 1) -> CGImage? {
        let side = Int(layout.canvas.rounded())
        guard let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Top-left origin, like the layout.
        ctx.translateBy(x: 0, y: CGFloat(side))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high

        let p = min(max(progress, 0), 1)

        // Outline: the white band first in time (it is the "white background"),
        // then the rainbow from the inside out, all within the first 60%.
        let bands = layout.bands
        for (index, band) in bands.enumerated() {
            let order = bands.count - 1 - index // white = 0, innermost colour = 1…
            let start = CGFloat(order) / CGFloat(bands.count) * 0.6
            let share = Self.ramp(p, from: start, to: start + 0.6 / CGFloat(bands.count))
            guard share > 0, let silhouette = Self.silhouette(of: head, color: Self.cgColor(band.color))
            else { continue }
            // A band that is still growing draws only part of the way round.
            let shown = max(1, Int((CGFloat(band.offsets.count) * share).rounded(.up)))
            for offset in band.offsets.prefix(shown) {
                Self.draw(silhouette, in: layout.headRect.offsetBy(dx: offset.x, dy: offset.y), ctx: ctx)
            }
            // The silhouette itself, so the band has no hole in the middle.
            Self.draw(silhouette, in: layout.headRect, ctx: ctx)
        }

        Self.draw(head, in: layout.headRect, ctx: ctx)

        // Blush.
        let blush = Self.ramp(p, from: 0.6, to: 0.7)
        if blush > 0 {
            for cheek in layout.cheeks { Self.drawBlush(cheek, alpha: blush, ctx: ctx) }
        }

        // Stickers pop in one after another over the last 30%.
        for (i, sticker) in layout.stickers.enumerated() {
            let start = 0.7 + 0.3 * CGFloat(i) / CGFloat(max(layout.stickers.count, 1))
            let grow = Self.ramp(p, from: start, to: start + 0.3 / CGFloat(max(layout.stickers.count, 1)))
            guard grow > 0 else { continue }
            Self.drawSticker(sticker, scale: grow, ctx: ctx)
        }

        return ctx.makeImage()
    }

    // MARK: - Pieces

    private static func ramp(_ p: CGFloat, from a: CGFloat, to b: CGFloat) -> CGFloat {
        guard b > a else { return p >= a ? 1 : 0 }
        return min(max((p - a) / (b - a), 0), 1)
    }

    static func cgColor(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
    }

    /// Draws an image in a top-left-origin context the right way up.
    private static func draw(_ image: CGImage, in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    /// The head's shape filled flat with one colour. One per band per render.
    private static func silhouette(of head: CGImage, color: CGColor) -> CGImage? {
        // A small copy is plenty for the outline and makes the 280 shifted
        // draws cheap.
        let scale = min(1, 256 / CGFloat(max(head.width, head.height)))
        let w = max(1, Int(CGFloat(head.width) * scale)), h = max(1, Int(CGFloat(head.height) * scale))
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(head, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Keep the alpha, replace the colour.
        ctx.setBlendMode(.sourceIn)
        ctx.setFillColor(color)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    private static func drawBlush(_ cheek: AvatarDecorLayout.Cheek, alpha: CGFloat, ctx: CGContext) {
        let rect = CGRect(
            x: cheek.center.x - cheek.radius.width, y: cheek.center.y - cheek.radius.height,
            width: cheek.radius.width * 2, height: cheek.radius.height * 2)
        ctx.saveGState()
        ctx.addEllipse(in: rect)
        ctx.clip()
        // Soft from the middle out, so it reads as blush and not a sticker.
        let colors = [cgColor(AvatarDecorLayout.blush, alpha: 0.55 * alpha),
                      cgColor(AvatarDecorLayout.blush, alpha: 0)] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                     colors: colors, locations: [0, 1]) {
            ctx.translateBy(x: cheek.center.x, y: cheek.center.y)
            ctx.scaleBy(x: 1, y: cheek.radius.height / max(cheek.radius.width, 1))
            ctx.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0,
                                   endCenter: .zero, endRadius: cheek.radius.width, options: [])
        }
        ctx.restoreGState()
    }

    private static func drawSticker(_ sticker: AvatarDecorLayout.Sticker, scale: CGFloat, ctx: CGContext) {
        let color = cgColor(AvatarDecorLayout.stickerColors[sticker.colorIndex % AvatarDecorLayout.stickerColors.count])
        let s = sticker.size * scale
        ctx.saveGState()
        ctx.translateBy(x: sticker.center.x, y: sticker.center.y)
        ctx.rotate(by: sticker.rotation)
        let path = CGMutablePath()
        switch sticker.kind {
        case .star:
            let outer = s / 2, inner = s * 0.22
            for i in 0..<10 {
                let r = i.isMultiple(of: 2) ? outer : inner
                let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
                let pt = CGPoint(x: cos(a) * r, y: sin(a) * r)
                i == 0 ? path.move(to: pt) : path.addLine(to: pt)
            }
            path.closeSubpath()
        case .heart:
            let w = s / 2
            path.move(to: CGPoint(x: 0, y: w * 0.9))
            path.addCurve(to: CGPoint(x: -w, y: -w * 0.25),
                          control1: CGPoint(x: -w * 0.6, y: w * 0.45),
                          control2: CGPoint(x: -w, y: w * 0.2))
            path.addArc(center: CGPoint(x: -w / 2, y: -w * 0.3), radius: w / 2,
                        startAngle: .pi, endAngle: 0, clockwise: false)
            path.addArc(center: CGPoint(x: w / 2, y: -w * 0.3), radius: w / 2,
                        startAngle: .pi, endAngle: 0, clockwise: false)
            path.addCurve(to: CGPoint(x: 0, y: w * 0.9),
                          control1: CGPoint(x: w, y: w * 0.2),
                          control2: CGPoint(x: w * 0.6, y: w * 0.45))
            path.closeSubpath()
        case .dots:
            // Three polka dots in three colours.
            let dots: [(CGPoint, CGFloat)] = [
                (CGPoint(x: -s * 0.22, y: -s * 0.12), s * 0.2),
                (CGPoint(x: s * 0.22, y: -s * 0.2), s * 0.15),
                (CGPoint(x: s * 0.05, y: s * 0.24), s * 0.17),
            ]
            for (i, dot) in dots.enumerated() {
                let c = cgColor(AvatarDecorLayout.stickerColors[(sticker.colorIndex + i) % AvatarDecorLayout.stickerColors.count])
                ctx.setFillColor(c)
                ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
                ctx.setLineWidth(max(s * 0.05, 1))
                let rect = CGRect(x: dot.0.x - dot.1, y: dot.0.y - dot.1, width: dot.1 * 2, height: dot.1 * 2)
                ctx.addEllipse(in: rect)
                ctx.drawPath(using: .fillStroke)
            }
            ctx.restoreGState()
            return
        }
        ctx.addPath(path)
        ctx.setFillColor(color)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
        ctx.setLineWidth(max(s * 0.07, 1))
        ctx.setLineJoin(.round)
        ctx.drawPath(using: .fillStroke)
        ctx.restoreGState()
    }
}
