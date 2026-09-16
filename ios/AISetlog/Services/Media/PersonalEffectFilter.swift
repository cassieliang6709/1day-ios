import AVFoundation
import CoreImage

/// Turns `PersonalEffectParameters` into pixels.
///
/// Three of Apple's own filters, in the order a picture wants them: get the
/// exposure right, then the colour of the light, then how hard the picture is.
/// Doing contrast before exposure would push highlights up and then clip them.
///
/// Two customers, and they need different things from the same chain:
///
/// - **Playback** hands over one frame at a time and wants an image back.
///   `AVPlayerItem.videoComposition` does this per frame, on the fly, so
///   nothing is written anywhere and moving a dial is instant.
/// - **Export** needs a file. It can't share the film's own composition: that
///   one has hand-written instructions (crossfades, the friends-together grid)
///   and an `animationTool` carrying the title pill, the captions and the
///   stickers, while `AVMutableVideoComposition(asset:applyingCIFiltersWithHandler:)`
///   builds a whole instruction set of its own. The two can't be the same
///   object. Grading the finished film instead would work and would also grade
///   the words. So the clips get graded first, one at a time, and the stitcher
///   gets the graded files.
enum PersonalEffectFilter {

    // MARK: - One frame

    static func apply(_ parameters: PersonalEffectParameters, to image: CIImage) -> CIImage {
        guard !parameters.isIdentity else { return image }
        // Every step is cropped back to the frame it came in on: a video
        // composition handed a frame bigger than the one it asked for renders a
        // shifted picture.
        let frame = image.extent
        var output = image

        if parameters.exposure != 0 {
            output = output.applyingFilter(
                "CIExposureAdjust", parameters: [kCIInputEVKey: parameters.exposureEV])
        }

        if parameters.temperature != 0 {
            output = output.applyingFilter(
                "CITemperatureAndTint",
                parameters: [
                    "inputNeutral": CIVector(
                        x: PersonalEffectParameters.neutralTemperature, y: 0),
                    "inputTargetNeutral": CIVector(x: parameters.targetTemperature, y: 0),
                ])
        }

        if parameters.contrast != 0 {
            output = output.applyingFilter(
                "CIColorControls",
                parameters: [kCIInputContrastKey: parameters.contrastMultiplier])
        }

        return output.cropped(to: frame)
    }

    // MARK: - Playback

    /// A composition that grades every frame as it plays.
    ///
    /// Nil when every dial is centred, so playback with the grade off is the
    /// same code path it has always been rather than a no-op composition
    /// standing between the file and the screen.
    static func playbackComposition(
        _ parameters: PersonalEffectParameters, for asset: AVAsset
    ) async -> AVVideoComposition? {
        guard !parameters.isIdentity else { return nil }
        return try? await AVMutableVideoComposition.videoComposition(
            with: asset,
            applyingCIFiltersWithHandler: { request in
                request.finish(with: apply(parameters, to: request.sourceImage), context: nil)
            })
    }

    // MARK: - Export

    /// Writes a graded copy of one clip and returns where it went.
    ///
    /// Returns the original URL untouched when there's nothing to apply — the
    /// caller can then hand the same array to the stitcher either way, and
    /// nothing gets copied for the sake of it.
    static func filteredCopy(
        of url: URL, parameters: PersonalEffectParameters
    ) async throws -> URL {
        guard !parameters.isIdentity else { return url }

        let asset = AVURLAsset(url: url)
        guard let composition = await playbackComposition(parameters, for: asset) else { return url }

        guard let export = AVAssetExportSession(
            asset: asset, presetName: AVAssetExportPresetHighestQuality)
        else { throw ExportError.sessionUnavailable }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("graded-\(UUID().uuidString).mov")
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
            case .sessionUnavailable: "Could not start the grading pass."
            case .failed(let reason): "Grading pass failed: \(reason)"
            }
        }
    }
}
