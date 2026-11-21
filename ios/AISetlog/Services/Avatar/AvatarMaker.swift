import CoreGraphics
import Foundation
import UIKit

struct AvatarHeadResult {
    let head: AvatarHead
    let path: AvatarPath
}

enum AvatarPath: Equatable {
    case cutout
    case sticker
}

/// 照片 → 抠出的人像。只用 Vision 抠图，不再让 Apple 的 ImageCreator 画卡通（2026-11-21 Cassie：效果不好）。
enum AvatarMaker {
    static func makeHead(from photo: CGImage) throws -> AvatarHeadResult {
        AvatarHeadResult(head: try AvatarHeadExtractor.extract(from: photo), path: .cutout)
    }
}

enum AvatarComposer {
    static let side: CGFloat = 768

    static func upright(_ image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cg = image.cgImage { return cg }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }.cgImage
    }

    static func layout(for head: AvatarHead) -> AvatarDecorLayout {
        AvatarDecorLayout.make(
            canvas: side,
            headSize: CGSize(width: head.image.width, height: head.image.height))
    }

    static func pngData(_ image: CGImage) -> Data? {
        UIImage(cgImage: image).pngData()
    }
}
