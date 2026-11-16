import AVFoundation
import CoreImage

enum PersonalEffectFilter {


    static func apply(_ parameters: PersonalEffectParameters, to image: CIImage) -> CIImage {
        guard !parameters.isIdentity else { return image }
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


    static func filteredCopy(
        of url: URL, parameters: PersonalEffectParameters, timeout: TimeInterval = 180
    ) async throws -> URL {
        guard !parameters.isIdentity else { return url }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout

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

        try await VideoExportOperation.run(export, timeout: VideoExportOperation.remainingTime(until: deadline))
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
