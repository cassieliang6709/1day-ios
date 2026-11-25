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
