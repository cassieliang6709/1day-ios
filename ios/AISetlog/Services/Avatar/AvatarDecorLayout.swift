import CoreGraphics
import Foundation

struct AvatarDecorLayout: Equatable {
    struct Cheek: Equatable {
        var center: CGPoint
        var radius: CGSize
    }

    enum StickerKind: String, CaseIterable, Equatable {
        case star, heart, dots
    }

    struct Sticker: Equatable {
        var kind: StickerKind
        var center: CGPoint
        var size: CGFloat
        var rotation: CGFloat
        var colorIndex: Int
    }

    struct Band: Equatable {
        var color: UInt32
        var offsets: [CGPoint]
        var reach: CGFloat
    }

    var canvas: CGFloat
    var safeMargin: CGFloat
    var headRect: CGRect
    var cheeks: [Cheek]
    var stickers: [Sticker]
    var bands: [Band]


    static let maxStickers = 3
    static let minStickers = 2
    static let safeMarginFraction: CGFloat = 0.06
    static let rainbow: [UInt32] = [0xFFB3C7, 0xFFD6A5, 0xFDF1A8, 0xBDE8C3, 0xA9D6F5, 0xCDB8F2]
    static let white: UInt32 = 0xFFFFFF
    static let blush: UInt32 = 0xFF8FA8
    static let stickerColors: [UInt32] = [0xFFC93C, 0xFF7DA0, 0x7CC6F2, 0x8FD9A8, 0xB79BF2]
    static let wobble: CGFloat = 0.28
    static let samples = 40

    static let stickerAnchors: [CGPoint] = [
        CGPoint(x: 0.14, y: 0.10), CGPoint(x: 0.86, y: 0.08),
        CGPoint(x: 0.02, y: 0.40), CGPoint(x: 0.98, y: 0.36),
        CGPoint(x: 0.50, y: -0.06),
        CGPoint(x: 0.10, y: 0.90), CGPoint(x: 0.90, y: 0.92),
    ]


    static func make(
        canvas: CGFloat,
        headSize: CGSize,
        face: CGRect?,
        cheeks cheekHints: [CGPoint]?,
        seed: UInt64
    ) -> AvatarDecorLayout {
        var rng = SplitMix64(seed: seed)
        let margin = (canvas * safeMarginFraction).rounded()
        let bandWidth = canvas * 0.008
        let whiteWidth = canvas * 0.03
        let outline = whiteWidth + bandWidth * CGFloat(rainbow.count)
        let reachMax = outline + bandWidth * wobble

        let room = canvas - 2 * margin - 2 * reachMax
        let aspect = headSize.height > 0 ? headSize.width / headSize.height : 1
        let size = aspect >= 1
            ? CGSize(width: room, height: room / aspect)
            : CGSize(width: room * aspect, height: room)
        let headRect = CGRect(
            x: (canvas - size.width) / 2, y: (canvas - size.height) / 2,
            width: size.width, height: size.height)

        func toCanvas(_ p: CGPoint) -> CGPoint {
            CGPoint(x: headRect.minX + p.x * headRect.width, y: headRect.minY + p.y * headRect.height)
        }
        let faceRect: CGRect = {
            guard let face else {
                return CGRect(x: headRect.minX + headRect.width * 0.18,
                              y: headRect.minY + headRect.height * 0.25,
                              width: headRect.width * 0.64, height: headRect.height * 0.62)
            }
            let origin = toCanvas(face.origin)
            return CGRect(x: origin.x, y: origin.y,
                          width: face.width * headRect.width, height: face.height * headRect.height)
        }()

        let cheekRadius = CGSize(width: faceRect.width * 0.12, height: faceRect.width * 0.08)
        let cheekCenters: [CGPoint]
        if let cheekHints, cheekHints.count == 2 {
            cheekCenters = cheekHints.map(toCanvas)
        } else {
            cheekCenters = [
                CGPoint(x: faceRect.minX + faceRect.width * 0.24, y: faceRect.minY + faceRect.height * 0.64),
                CGPoint(x: faceRect.minX + faceRect.width * 0.76, y: faceRect.minY + faceRect.height * 0.64),
            ]
        }
        let cheeks = cheekCenters.map { Cheek(center: $0, radius: cheekRadius) }

        let count = minStickers + Int(rng.next() % UInt64(maxStickers - minStickers + 1))
        var anchors = stickerAnchors
        rng.shuffle(&anchors)
        var stickers: [Sticker] = []
        let lo = margin, hi = canvas - margin
        for anchor in anchors where stickers.count < count {
            let side = faceRect.width * (0.13 + 0.05 * rng.unit())
            var c = CGPoint(x: faceRect.minX + anchor.x * faceRect.width,
                            y: faceRect.minY + anchor.y * faceRect.height)
            c.x = min(max(c.x, lo + side / 2), hi - side / 2)
            c.y = min(max(c.y, lo + side / 2), hi - side / 2)
            let clearOfCheeks = cheeks.allSatisfy {
                hypot(c.x - $0.center.x, c.y - $0.center.y) > $0.radius.width + side / 2
            }
            let clearOfOthers = stickers.allSatisfy {
                hypot(c.x - $0.center.x, c.y - $0.center.y) > ($0.size + side) / 2
            }
            guard clearOfCheeks, clearOfOthers else { continue }
            let kind = StickerKind.allCases[Int(rng.next() % UInt64(StickerKind.allCases.count))]
            stickers.append(Sticker(
                kind: kind, center: c, size: side,
                rotation: (rng.unit() - 0.5) * 0.8,
                colorIndex: Int(rng.next() % UInt64(stickerColors.count))))
        }

        var bands: [Band] = []
        let colors = rainbow + [white]
        for (i, color) in colors.enumerated() {
            let isWhite = i == colors.count - 1
            let reach = isWhite ? whiteWidth : whiteWidth + bandWidth * CGFloat(colors.count - 1 - i)
            let phase = rng.unit() * .pi * 2
            var offsets: [CGPoint] = []
            for s in 0..<samples {
                let angle = CGFloat(s) / CGFloat(samples) * .pi * 2
                let wave = sin(angle * 3 + phase) * 0.6 + sin(angle * 7 + phase * 2) * 0.4
                let jitter = (wave * 0.7 + (rng.unit() - 0.5) * 0.6) * bandWidth * wobble
                let r = max(reach + (isWhite ? 0 : jitter), 0)
                offsets.append(CGPoint(x: cos(angle) * r, y: sin(angle) * r))
            }
            bands.append(Band(color: color, offsets: offsets, reach: reach))
        }

        return AvatarDecorLayout(
            canvas: canvas, safeMargin: margin, headRect: headRect,
            cheeks: cheeks, stickers: stickers, bands: bands)
    }

    var outlineReach: CGFloat {
        bands.flatMap(\.offsets).map { hypot($0.x, $0.y) }.max() ?? 0
    }
}

struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> CGFloat {
        CGFloat(next() >> 11) / CGFloat(1 << 53)
    }

    mutating func shuffle<T>(_ array: inout [T]) {
        guard array.count > 1 else { return }
        for i in stride(from: array.count - 1, to: 0, by: -1) {
            let j = Int(next() % UInt64(i + 1))
            array.swapAt(i, j)
        }
    }
}
