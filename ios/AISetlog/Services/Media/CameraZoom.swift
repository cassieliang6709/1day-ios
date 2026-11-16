import AVFoundation
import CoreGraphics
import Foundation

struct CameraZoom: Equatable {
    let base: CGFloat
    let minFactor: CGFloat
    let maxFactor: CGFloat

    static let unavailable = CameraZoom(base: 1, minFactor: 1, maxFactor: 1)

    static let defaultPresets: [CGFloat] = [0.5, 1, 2]

    static let interactiveCeiling: CGFloat = 10

    static let matchTolerance: CGFloat = 0.01

    static let pointsPerDoubling: CGFloat = 130

    static func zoom(draggedBy translation: CGFloat, from start: CGFloat) -> CGFloat {
        start * pow(2, translation / pointsPerDoubling)
    }

    init(base: CGFloat, minFactor: CGFloat, maxFactor: CGFloat) {
        self.base = max(base, 1)
        self.minFactor = max(minFactor, 0.01)
        self.maxFactor = max(maxFactor, max(minFactor, 0.01))
    }

    init(device: AVCaptureDevice) {
        let constituents = device.constituentDevices
        self.init(
            base: Self.wideBase(
                wideIndex: constituents.firstIndex { $0.deviceType == .builtInWideAngleCamera },
                switchOverFactors: device.virtualDeviceSwitchOverVideoZoomFactors.map {
                    CGFloat(truncating: $0)
                }),
            minFactor: device.minAvailableVideoZoomFactor,
            maxFactor: device.maxAvailableVideoZoomFactor)
    }


    var minDisplay: CGFloat { minFactor / base }
    var maxDisplay: CGFloat { min(maxFactor / base, Self.interactiveCeiling) }

    func display(forFactor factor: CGFloat) -> CGFloat { factor / base }

    func factor(forDisplay display: CGFloat) -> CGFloat {
        clampedDisplay(display) * base
    }

    func clampedDisplay(_ display: CGFloat) -> CGFloat {
        guard display.isFinite else { return 1 }
        return min(max(display, minDisplay), maxDisplay)
    }


    func presets(from candidates: [CGFloat] = CameraZoom.defaultPresets) -> [CGFloat] {
        let kept = candidates.filter {
            $0 >= minDisplay - Self.matchTolerance && $0 <= maxDisplay + Self.matchTolerance
        }
        return kept.isEmpty ? [clampedDisplay(1)] : kept
    }

    static func wideBase(wideIndex: Int?, switchOverFactors: [CGFloat]) -> CGFloat {
        guard let wideIndex, wideIndex > 0, wideIndex - 1 < switchOverFactors.count
        else { return 1 }
        return max(switchOverFactors[wideIndex - 1], 1)
    }

    static func isSame(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) < matchTolerance
    }

    static func label(_ display: CGFloat) -> String {
        let rounded = (display * 10).rounded() / 10
        if abs(rounded - rounded.rounded()) < 0.05 {
            return "\(Int(rounded.rounded()))x"
        }
        return String(format: "%.1fx", rounded)
    }
}
