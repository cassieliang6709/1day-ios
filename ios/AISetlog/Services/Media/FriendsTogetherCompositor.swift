import AVFoundation
import CoreImage
import UIKit

/// Where one person's take sits inside a shared-room frame, and which way up it
/// was filmed.
///
/// `cell` is in render space with the origin at the top left, the same space
/// `VideoStitcher.grid` already works in. Core Image counts from the bottom, so
/// the flip happens once, inside the compositor, rather than in the layout maths
/// that has tests against it.
struct FriendsTogetherPlacement {
    let trackID: CMPersistentTrackID
    let cell: CGRect
    let orientation: CGImagePropertyOrientation

    /// Which way a track has to be turned to be upright.
    ///
    /// `preferredTransform` is a display transform in a top-left coordinate
    /// space; handing it straight to a `CIImage` (which counts from the bottom)
    /// mirrors every rotation. `CIImage.oriented` takes the same four rotations
    /// in a form that already knows about that difference, and fixes the extent
    /// with them, so this reduces the transform to one of those four instead of
    /// re-deriving the affine maths in the other space.
    static func orientation(for transform: CGAffineTransform) -> CGImagePropertyOrientation {
        // Rounded, because a transform that came off a file is rarely exactly
        // integral and the four cases are 90° apart — there is nothing in
        // between for a tolerance to accidentally land on.
        let a = transform.a.rounded(), b = transform.b.rounded()
        let c = transform.c.rounded(), d = transform.d.rounded()
        switch (a, b, c, d) {
        case (0, 1, -1, 0): return .right
        case (0, -1, 1, 0): return .left
        case (-1, 0, 0, -1): return .down
        default: return .up
        }
    }
}

/// One moment of the shared-room grid: everybody who filmed it, placed.
///
/// A custom instruction rather than `AVMutableVideoCompositionInstruction`
/// because the layer instructions that class carries can only translate, scale,
/// crop and fade. None of those can blur, and a blurred bed is the whole point
/// of filling a cell without cutting anyone's head off.
final class FriendsTogetherInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = false
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let placements: [FriendsTogetherPlacement]

    init(timeRange: CMTimeRange, placements: [FriendsTogetherPlacement]) {
        self.timeRange = timeRange
        self.placements = placements
        self.requiredSourceTrackIDs = placements.map { NSNumber(value: $0.trackID) }
    }
}

/// Draws the shared-room grid without cropping anybody.
///
/// Each cell gets two copies of the same take: one scaled up until it covers the
/// cell and blurred, and the original scaled down until all of it fits, centred
/// on top. So the take is complete — the top of a head, the edge of a room — and
/// the leftover space is that person's own colours rather than a black bar.
///
/// The alternative, and what this replaces, was a centred crop: it filled the
/// cell exactly and threw away whatever the cell's aspect ratio disagreed with,
/// which for a 9:16 take in a landscape cell is most of the person.
final class FriendsTogetherCompositor: NSObject, AVVideoCompositing {
    /// Deep enough to soften a face past recognition, shallow enough that the
    /// bed still reads as the same room. Proportional to the cell so it looks
    /// the same in a preview render and a full-size export.
    private static let blurFraction = 0.05
    /// The bed sits back a little, so two adjacent cells don't bleed into each
    /// other and the sharp copy is clearly the subject.
    private static let backgroundDim = -0.08

    private let context = CIContext(options: [.cacheIntermediates: false])
    private let queue = DispatchQueue(label: "1day.friends-together-compositor")
    private var renderSize: CGSize = .zero

    let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ]

    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ]

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        queue.sync { renderSize = newRenderContext.size }
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        queue.async { [weak self] in
            guard let self else {
                request.finish(with: CompositorError.cancelled)
                return
            }
            guard let buffer = request.renderContext.newPixelBuffer() else {
                request.finish(with: CompositorError.noBuffer)
                return
            }
            let size = self.renderSize == .zero ? request.renderContext.size : self.renderSize
            let frame = CGRect(origin: .zero, size: size)

            // Anything that isn't ours — the title card's source-less black
            // segment — still comes through here, because a custom compositor
            // replaces AVFoundation's, it doesn't sit beside it.
            let instruction = request.videoCompositionInstruction as? FriendsTogetherInstruction
            var image = CIImage(color: .black).cropped(to: frame)

            for placement in instruction?.placements ?? [] {
                guard let source = request.sourceFrame(byTrackID: placement.trackID),
                      let cell = self.cell(source, placement: placement, in: size)
                else { continue }
                image = cell.composited(over: image)
            }

            self.context.render(image, to: buffer)
            request.finish(withComposedVideoFrame: buffer)
        }
    }

    /// One person's cell: blurred bed, whole take centred on it.
    private func cell(
        _ source: CVPixelBuffer, placement: FriendsTogetherPlacement, in renderSize: CGSize
    ) -> CIImage? {
        var image = CIImage(cvPixelBuffer: source).oriented(placement.orientation)
        let extent = image.extent
        // A CIImage can carry an infinite extent (a clamp, a solid colour).
        // Scaling one is meaningless and crashes the render, so it is rejected
        // before any of the geometry below runs.
        guard extent.width.isFinite, extent.height.isFinite,
              extent.width > 0, extent.height > 0
        else { return nil }
        // `oriented` can leave the extent somewhere other than the origin, and
        // every scale below assumes it starts there.
        image = image.transformed(
            by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        let oriented = CGSize(width: extent.width, height: extent.height)

        let cell = CGRect(
            x: placement.cell.minX,
            y: renderSize.height - placement.cell.maxY,
            width: placement.cell.width,
            height: placement.cell.height)
        guard cell.width > 0, cell.height > 0 else { return nil }

        let fill = max(cell.width / oriented.width, cell.height / oriented.height)
        let fit = min(cell.width / oriented.width, cell.height / oriented.height)

        let bed = scaled(image, by: fill, from: oriented, into: cell)
            // Clamp before the blur, or it reads transparent black from past the
            // edge of the scaled copy and rings the cell in shadow.
            .clampedToExtent()
            .applyingGaussianBlur(sigma: min(cell.width, cell.height) * Self.blurFraction)
            .applyingFilter(
                "CIColorControls", parameters: [kCIInputBrightnessKey: Self.backgroundDim])
            .cropped(to: cell)

        let subject = scaled(image, by: fit, from: oriented, into: cell).cropped(to: cell)
        return subject.composited(over: bed)
    }

    private func scaled(
        _ image: CIImage, by scale: CGFloat, from oriented: CGSize, into cell: CGRect
    ) -> CIImage {
        let size = CGSize(width: oriented.width * scale, height: oriented.height * scale)
        return image.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
                .concatenating(CGAffineTransform(
                    translationX: cell.midX - size.width / 2,
                    y: cell.midY - size.height / 2)))
    }

    func cancelAllPendingVideoCompositionRequests() {}

    enum CompositorError: LocalizedError {
        case noBuffer
        case cancelled

        var errorDescription: String? {
            switch self {
            case .noBuffer: "The renderer ran out of frame buffers."
            case .cancelled: "The render was cancelled."
            }
        }
    }
}
