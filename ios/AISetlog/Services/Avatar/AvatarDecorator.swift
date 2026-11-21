import CoreGraphics
import UIKit

enum AvatarDecorator {
    static func render(head: CGImage, layout: AvatarDecorLayout, progress: CGFloat = 1) -> CGImage? {
        let side = Int(layout.canvas.rounded())
        guard let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(side))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high

        // 动画：白边沿着一圈逐渐画满，最后盖上人像
        let p = min(max(progress, 0), 1)
        let offsets = layout.outlineOffsets
        let shown = Int((CGFloat(offsets.count) * p).rounded(.up))
        if shown > 0, let silhouette = Self.silhouette(of: head, color: Self.cgColor(AvatarDecorLayout.white)) {
            for offset in offsets.prefix(shown) {
                Self.draw(silhouette, in: layout.headRect.offsetBy(dx: offset.x, dy: offset.y), ctx: ctx)
            }
        }

        Self.draw(head, in: layout.headRect, ctx: ctx)

        return ctx.makeImage()
    }


    static func cgColor(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
    }

    private static func draw(_ image: CGImage, in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    private static func silhouette(of head: CGImage, color: CGColor) -> CGImage? {
        let scale = min(1, 256 / CGFloat(max(head.width, head.height)))
        let w = max(1, Int(CGFloat(head.width) * scale)), h = max(1, Int(CGFloat(head.height) * scale))
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(head, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setBlendMode(.sourceIn)
        ctx.setFillColor(color)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }
}
