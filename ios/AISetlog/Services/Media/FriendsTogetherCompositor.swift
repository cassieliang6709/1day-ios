import AVFoundation
import CoreImage
import UIKit

struct FriendsTogetherPlacement {
    let trackID: CMPersistentTrackID
    let cell: CGRect
    let orientation: CGImagePropertyOrientation

    static func orientation(for transform: CGAffineTransform) -> CGImagePropertyOrientation {
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

final class FriendsTogetherCompositor: NSObject, AVVideoCompositing {
    private static let blurFraction = 0.05
    private static let backgroundDim = -0.08
    static let cropAllowance: CGFloat = 0.125

    static func coversByCropping(oriented: CGSize, cell: CGSize) -> Bool {
        guard oriented.width > 0, oriented.height > 0 else { return true }
        let fill = max(cell.width / oriented.width, cell.height / oriented.height)
        let fit = min(cell.width / oriented.width, cell.height / oriented.height)
        return fill > 0 && 1 - fit / fill <= cropAllowance
    }

    static func frame(
        of oriented: CGSize, scaledBy scale: CGFloat, centredIn cell: CGRect
    ) -> CGRect {
        let size = CGSize(width: oriented.width * scale, height: oriented.height * scale)
        return CGRect(
            x: cell.midX - size.width / 2, y: cell.midY - size.height / 2,
            width: size.width, height: size.height)
    }

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

    private func cell(
        _ source: CVPixelBuffer, placement: FriendsTogetherPlacement, in renderSize: CGSize
    ) -> CIImage? {
        var image = CIImage(cvPixelBuffer: source).oriented(placement.orientation)
        let extent = image.extent
        guard extent.width.isFinite, extent.height.isFinite,
              extent.width > 0, extent.height > 0
        else { return nil }
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

        if Self.coversByCropping(oriented: oriented, cell: cell.size) {
            return scaled(image, by: fill, from: oriented, into: cell).cropped(to: cell)
        }

        let bed = scaled(image, by: fill, from: oriented, into: cell)
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
        let placed = Self.frame(of: oriented, scaledBy: scale, centredIn: cell)
        return image.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
                .concatenating(CGAffineTransform(
                    translationX: placed.minX, y: placed.minY)))
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
