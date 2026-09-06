import AVFoundation
import CoreImage

/// Turns a `GentleLook` into pixels.
///
/// Two customers, and they need different things from the same chain:
///
/// - **Playback** hands over one frame at a time and wants an image back.
///   `AVPlayerItem.videoComposition` does this per frame, on the fly, so
///   nothing is written anywhere and changing the look is instant.
/// - **Export** needs a file. It can't share the film's own composition: that
///   one has hand-written instructions (crossfades, the friends-together grid)
///   and an `animationTool` carrying the title pill, the captions and the
///   stickers, while `AVMutableVideoComposition(asset:applyingCIFiltersWithHandler:)`
///   builds a whole instruction set of its own. The two can't be the same
///   object. Filtering the finished film instead would work and would also
///   blur the words. So the clips get filtered first, one at a time, and the
///   stitcher gets the filtered files.
enum GentleLookFilter {

    // MARK: - One frame

    /// The chain, in the order a face wants it: soften, lift, warm.
    ///
    /// Every step is cropped back to the frame it came in on. Gaussian blur
    /// grows an image's extent past its edges, and a video composition handed
    /// a frame bigger than the one it asked for renders a shifted picture.
    static func apply(_ look: GentleLook, to image: CIImage) -> CIImage {
        guard !look.isIdentity else { return image }
        let frame = image.extent
        var output = image

        let p = look.parameters

        if p.blurRadius > 0 {
            // Clamp first, or the blur reads transparent black from beyond the
            // edges and leaves a dark vignette all the way round.
            let blurred = image
                .clampedToExtent()
                .applyingGaussianBlur(sigma: p.blurRadius)
                .cropped(to: frame)

            // Two passes, because they do different jobs and only one of them
            // is safe to overdo. Mixing the blurred copy in is the pass that
            // removes texture — that's the one that turns a face to plastic, so
            // it gets the low ceiling. Soft light on top adds the glow without
            // moving an edge, and carries most of the effect.
            let softened = fade(blurred, onto: image, by: p.blurOpacity, in: frame)
            let glow = blurred.applyingFilter(
                "CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: softened])
            output = fade(glow, onto: softened, by: p.softLightOpacity, in: frame)
        }

        if p.brightnessDelta > 0 || p.saturation != 1 {
            output = output.applyingFilter(
                "CIColorControls",
                parameters: [
                    kCIInputBrightnessKey: p.brightnessDelta,
                    kCIInputSaturationKey: p.saturation,
                    kCIInputContrastKey: 1.0,
                ])
        }

        if look.warmth > 0 {
            output = output.applyingFilter(
                "CITemperatureAndTint",
                parameters: [
                    "inputNeutral": CIVector(x: GentleLook.neutralTemperature, y: 0),
                    "inputTargetNeutral": CIVector(x: p.temperature, y: p.tint),
                ])
        }

        return output.cropped(to: frame)
    }

    /// `top` laid over `bottom` at `opacity`. Alpha plus a source-over rather
    /// than a mix filter, which keeps this to two filters that have been in
    /// Core Image since iOS 6.
    private static func fade(
        _ top: CIImage, onto bottom: CIImage, by opacity: Double, in frame: CGRect
    ) -> CIImage {
        guard opacity > 0 else { return bottom }
        return top
            .applyingFilter(
                "CIColorMatrix",
                parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity)])
            .composited(over: bottom)
            .cropped(to: frame)
    }

    // MARK: - Playback

    /// A composition that filters every frame as it plays.
    ///
    /// Nil for the identity look, so playback with the filter off is the same
    /// code path it has always been rather than a no-op composition standing
    /// between the file and the screen.
    static func playbackComposition(
        _ look: GentleLook, for asset: AVAsset
    ) async -> AVVideoComposition? {
        guard !look.isIdentity else { return nil }
        return try? await AVMutableVideoComposition.videoComposition(
            with: asset,
            applyingCIFiltersWithHandler: { request in
                request.finish(with: apply(look, to: request.sourceImage), context: nil)
            })
    }

    // MARK: - Export

    /// Writes a filtered copy of one clip and returns where it went.
    ///
    /// Returns the original URL untouched when there's nothing to apply — the
    /// caller can then hand the same array to the stitcher either way, and
    /// nothing gets copied for the sake of it.
    static func filteredCopy(of url: URL, look: GentleLook) async throws -> URL {
        guard !look.isIdentity else { return url }

        let asset = AVURLAsset(url: url)
        guard let composition = await playbackComposition(look, for: asset) else { return url }

        guard let export = AVAssetExportSession(
            asset: asset, presetName: AVAssetExportPresetHighestQuality)
        else { throw ExportError.sessionUnavailable }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("look-\(UUID().uuidString).mov")
        export.outputURL = output
        export.outputFileType = .mov
        export.videoComposition = composition
        export.shouldOptimizeForNetworkUse = false

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { cont.resume() }
        }
        guard export.status == .completed else {
            throw ExportError.failed(export.error?.localizedDescription ?? "unknown")
        }
        return output
    }

    enum ExportError: LocalizedError {
        case sessionUnavailable
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .sessionUnavailable: "Could not start the look pass."
            case .failed(let reason): "Look pass failed: \(reason)"
            }
        }
    }
}
