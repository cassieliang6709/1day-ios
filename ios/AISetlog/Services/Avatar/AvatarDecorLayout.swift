import CoreGraphics
import Foundation

/// 头像的版式：人像居中，外面一圈白边，像贴纸。不再加彩虹、腮红、小贴纸（2026-11-21 Cassie 决定）。
struct AvatarDecorLayout: Equatable {
    var canvas: CGFloat
    var safeMargin: CGFloat
    var headRect: CGRect
    /// 白边的宽度（画布像素）
    var outline: CGFloat

    static let safeMarginFraction: CGFloat = 0.06
    static let outlineFraction: CGFloat = 0.04
    static let white: UInt32 = 0xFFFFFF
    /// 白边由人像剪影沿一圈平移叠出来，取这么多个方向
    static let samples = 40

    static func make(canvas: CGFloat, headSize: CGSize) -> AvatarDecorLayout {
        let margin = (canvas * safeMarginFraction).rounded()
        let outline = canvas * outlineFraction

        let room = canvas - 2 * margin - 2 * outline
        let aspect = headSize.height > 0 ? headSize.width / headSize.height : 1
        let size = aspect >= 1
            ? CGSize(width: room, height: room / aspect)
            : CGSize(width: room * aspect, height: room)
        let headRect = CGRect(
            x: (canvas - size.width) / 2, y: (canvas - size.height) / 2,
            width: size.width, height: size.height)

        return AvatarDecorLayout(canvas: canvas, safeMargin: margin, headRect: headRect, outline: outline)
    }

    var outlineOffsets: [CGPoint] {
        (0..<Self.samples).map {
            let angle = CGFloat($0) / CGFloat(Self.samples) * .pi * 2
            return CGPoint(x: cos(angle) * outline, y: sin(angle) * outline)
        }
    }
}
