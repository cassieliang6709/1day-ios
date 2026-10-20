import CoreGraphics
import Foundation

/// Where the avatar's decorations go: blush, stickers, and the rainbow
/// outline. Pure geometry, no drawing, so the rules in the avatar spec (§3.4)
/// can be pinned by tests — at most three stickers, never on the cheeks,
/// everything inside the transparent safe margin.
///
/// This is the second of the avatar's two layers. The first
/// (`AvatarHeadMaking`) only has to hand over a head on a transparent
/// background; whatever made it — Apple's on-device model, the Vision
/// cut-out, a cloud model one day — the decorations are always ours, so a
/// model can never add a slimmer face or bigger eyes.
///
/// Coordinates are top-left origin, in canvas points.
struct AvatarDecorLayout: Equatable {
    struct Cheek: Equatable {
        var center: CGPoint
        /// Half-width and half-height of the blush ellipse.
        var radius: CGSize
    }

    enum StickerKind: String, CaseIterable, Equatable {
        case star, heart, dots
    }

    struct Sticker: Equatable {
        var kind: StickerKind
        var center: CGPoint
        /// Side of the square the sticker is drawn in.
        var size: CGFloat
        /// Radians.
        var rotation: CGFloat
        /// Index into `AvatarDecorLayout.stickerColors`.
        var colorIndex: Int
    }

    /// One coloured band of the outline. The band is the head's silhouette
    /// grown outward by `offsets` — one shifted copy per sample, which is how
    /// the outline follows the cut-out's own contour instead of being a circle.
    struct Band: Equatable {
        /// 0xRRGGBB.
        var color: UInt32
        /// Shifts of the silhouette, each roughly `reach` from the origin with
        /// a little wobble, so the edge looks drawn in crayon rather than ruled.
        var offsets: [CGPoint]
        /// The nominal distance from the head's edge to this band's outer edge.
        var reach: CGFloat
    }

    var canvas: CGFloat
    /// Transparent border on every side; nothing is drawn in it.
    var safeMargin: CGFloat
    /// Where the head image is drawn.
    var headRect: CGRect
    var cheeks: [Cheek]
    var stickers: [Sticker]
    /// Outermost first, which is the order they are painted in.
    var bands: [Band]

    // MARK: - Constants

    static let maxStickers = 3
    static let minStickers = 2
    /// Fraction of the canvas left transparent on each side.
    static let safeMarginFraction: CGFloat = 0.06
    /// Macaron rainbow, outside in. The last band is the white one between the
    /// rainbow and the face — the "白底" of a die-cut sticker.
    static let rainbow: [UInt32] = [0xFFB3C7, 0xFFD6A5, 0xFDF1A8, 0xBDE8C3, 0xA9D6F5, 0xCDB8F2]
    static let white: UInt32 = 0xFFFFFF
    static let blush: UInt32 = 0xFF8FA8
    static let stickerColors: [UInt32] = [0xFFC93C, 0xFF7DA0, 0x7CC6F2, 0x8FD9A8, 0xB79BF2]
    /// Wobble on each outline sample, as a fraction of a band's width.
    static let wobble: CGFloat = 0.28
    /// Samples around each band. Enough that adjacent shifted copies overlap.
    static let samples = 40

    /// Where the stickers may go, in the face's own unit square (top-left
    /// origin): the forehead corners, the temples and the jaw corners. None of
    /// them is on an eye, the mouth or a cheek.
    static let stickerAnchors: [CGPoint] = [
        CGPoint(x: 0.14, y: 0.10), CGPoint(x: 0.86, y: 0.08),
        CGPoint(x: 0.02, y: 0.40), CGPoint(x: 0.98, y: 0.36),
        CGPoint(x: 0.50, y: -0.06),
        CGPoint(x: 0.10, y: 0.90), CGPoint(x: 0.90, y: 0.92),
    ]

    // MARK: - Building

    /// - Parameters:
    ///   - canvas: side of the square output.
    ///   - headSize: pixel size of the cut-out head image (only its aspect matters).
    ///   - face: the face inside the head image, in the image's unit square
    ///     (top-left origin). Nil when no face was found — then the head's own
    ///     box stands in.
    ///   - cheeks: cheek centres found from facial landmarks, same unit square.
    ///   - seed: what 「重画一张」 changes.
    static func make(
        canvas: CGFloat,
        headSize: CGSize,
        face: CGRect?,
        cheeks cheekHints: [CGPoint]?,
        seed: UInt64
    ) -> AvatarDecorLayout {
        var rng = SplitMix64(seed: seed)
        let margin = (canvas * safeMarginFraction).rounded()
        let bandWidth = canvas * 0.016
        let whiteWidth = canvas * 0.03
        let outline = whiteWidth + bandWidth * CGFloat(rainbow.count)
        // A wobbling sample can reach a little past its band.
        let reachMax = outline + bandWidth * wobble

        // The head, aspect-fit inside what the margin and the outline leave.
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
                // No face: the middle of the head, a little high.
                return CGRect(x: headRect.minX + headRect.width * 0.18,
                              y: headRect.minY + headRect.height * 0.25,
                              width: headRect.width * 0.64, height: headRect.height * 0.62)
            }
            let origin = toCanvas(face.origin)
            return CGRect(x: origin.x, y: origin.y,
                          width: face.width * headRect.width, height: face.height * headRect.height)
        }()

        // Blush.
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

        // Stickers: two or three, each on its own anchor, none on a cheek.
        let count = minStickers + Int(rng.next() % UInt64(maxStickers - minStickers + 1))
        var anchors = stickerAnchors
        rng.shuffle(&anchors)
        var stickers: [Sticker] = []
        let lo = margin, hi = canvas - margin
        for anchor in anchors where stickers.count < count {
            let side = faceRect.width * (0.13 + 0.05 * rng.unit())
            var c = CGPoint(x: faceRect.minX + anchor.x * faceRect.width,
                            y: faceRect.minY + anchor.y * faceRect.height)
            // Kept inside the safe area even when the face is near an edge.
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

        // Outline, outermost band first. The white band sits inside the rainbow.
        var bands: [Band] = []
        let colors = rainbow + [white]
        for (i, color) in colors.enumerated() {
            let isWhite = i == colors.count - 1
            let reach = isWhite ? whiteWidth : whiteWidth + bandWidth * CGFloat(colors.count - 1 - i)
            let phase = rng.unit() * .pi * 2
            var offsets: [CGPoint] = []
            for s in 0..<samples {
                let angle = CGFloat(s) / CGFloat(samples) * .pi * 2
                // Two slow waves plus noise: wavy like a hand, not jagged.
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

    /// The furthest any part of the outline reaches past the head's box.
    var outlineReach: CGFloat {
        bands.flatMap(\.offsets).map { hypot($0.x, $0.y) }.max() ?? 0
    }
}

/// Small, seedable, deterministic: the same seed draws the same avatar, which
/// is what lets a test pin a layout.
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

    /// Uniform in [0, 1).
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
