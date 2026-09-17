import AVFoundation
import CoreGraphics
import Foundation

/// The zoom a person reads ("0.5x") against the zoom the camera takes
/// (`AVCaptureDevice.videoZoomFactor`), which are not the same number.
///
/// On a phone with an ultra-wide lens the device handed to the session is a
/// *virtual* one — `.builtInTripleCamera` and friends — and its zoom factor
/// 1.0 is its widest constituent lens, the ultra-wide. So the number everybody
/// calls "1x" is the factor at which the plain wide lens takes over: 2.0 on
/// every current phone, but read off the device here rather than assumed.
///
/// Everything above this type — the chips, the slider, the pinch — speaks in
/// display values. `factor(forDisplay:)` is the only place the two meet.
struct CameraZoom: Equatable {
    /// The `videoZoomFactor` that shows the wide lens: the one people call 1x.
    let base: CGFloat
    let minFactor: CGFloat
    let maxFactor: CGFloat

    /// A camera with nothing to offer — one lens, no zoom. What the recorder
    /// reports before it has a device, and what the Simulator's borrowed Mac
    /// webcam reports. `presets()` returns a single entry for it, which is the
    /// UI's cue to draw no chips at all.
    static let unavailable = CameraZoom(base: 1, minFactor: 1, maxFactor: 1)

    /// The display values offered as chips, when the lens can reach them.
    static let defaultPresets: [CGFloat] = [0.5, 1, 2]

    /// Where the slider and the pinch stop, regardless of hardware.
    ///
    /// `maxAvailableVideoZoomFactor` runs past 100x on a recent phone, all of
    /// it digital past the telephoto. A pinch that can reach 60x is a pinch
    /// that lands there by accident, on a picture made of four real pixels.
    static let interactiveCeiling: CGFloat = 10

    /// Two display values that mean the same lens position. Presets are
    /// matched with this rather than `==`: the value coming back has been
    /// through a divide and a clamp.
    static let matchTolerance: CGFloat = 0.01

    /// How far a finger travels along the zoom track to double the zoom.
    static let pointsPerDoubling: CGFloat = 130

    /// Where a drag along the zoom track lands, relative to where it started.
    ///
    /// Multiplicative, the same shape as the pinch on the picture: 1x→2x and
    /// 4x→8x cost the same travel. A linear mapping over a 0.5–10 range spends
    /// the first sixth of the capsule getting from 1x to 2x — the part people
    /// actually use — and the rest in digital crop nobody asked for.
    ///
    /// Unclamped on purpose. `ClipRecorder.setZoom` is the only thing that
    /// knows what this particular lens can reach, and it clamps; a second,
    /// guessed clamp here is how a control ends up disagreeing with the camera.
    static func zoom(draggedBy translation: CGFloat, from start: CGFloat) -> CGFloat {
        start * pow(2, translation / pointsPerDoubling)
    }

    init(base: CGFloat, minFactor: CGFloat, maxFactor: CGFloat) {
        // A zero base would divide every display value by nothing. Nothing
        // reports one, but it arrives from `virtualDeviceSwitchOverVideoZoomFactors`
        // by way of an NSNumber, so it is guarded rather than trusted.
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

    // MARK: - Range

    var minDisplay: CGFloat { minFactor / base }
    var maxDisplay: CGFloat { min(maxFactor / base, Self.interactiveCeiling) }

    func display(forFactor factor: CGFloat) -> CGFloat { factor / base }

    /// The `videoZoomFactor` for a display value, clamped on the way through.
    func factor(forDisplay display: CGFloat) -> CGFloat {
        clampedDisplay(display) * base
    }

    /// Callers hand over raw pinch and slider values; this is what keeps them
    /// from having to know the lens's limits.
    func clampedDisplay(_ display: CGFloat) -> CGFloat {
        guard display.isFinite else { return 1 }
        return min(max(display, minDisplay), maxDisplay)
    }

    // MARK: - Presets

    /// The candidates this lens can actually reach.
    ///
    /// A front camera has no ultra-wide, so its range starts at 1x and 0.5x
    /// drops out — showing a 0.5x chip that silently clamps to 1x would be a
    /// chip that lies about the picture.
    func presets(from candidates: [CGFloat] = CameraZoom.defaultPresets) -> [CGFloat] {
        let kept = candidates.filter {
            $0 >= minDisplay - Self.matchTolerance && $0 <= maxDisplay + Self.matchTolerance
        }
        // 1x always exists — a camera that reported a range excluding it would
        // otherwise leave the UI with no chip to call home.
        return kept.isEmpty ? [clampedDisplay(1)] : kept
    }

    /// Whether the wide lens's base was derived, or fallen back to.
    ///
    /// The constituents of a virtual device run widest-first, and
    /// `virtualDeviceSwitchOverVideoZoomFactors[i]` is the factor at which
    /// constituent `i + 1` takes over. The wide lens's base is therefore the
    /// switch-over factor just before it, and 1.0 when the wide lens *is* the
    /// widest one.
    ///
    /// That last case is why this reads the constituents instead of taking
    /// `switchOverFactors.first`: on `.builtInDualCamera` (wide + telephoto,
    /// no ultra-wide) the single switch-over factor of 2.0 belongs to the
    /// telephoto, and treating it as the base would label every real 1x as
    /// 0.5x and cap the whole UI at half the truth.
    static func wideBase(wideIndex: Int?, switchOverFactors: [CGFloat]) -> CGFloat {
        guard let wideIndex, wideIndex > 0, wideIndex - 1 < switchOverFactors.count
        else { return 1 }
        return max(switchOverFactors[wideIndex - 1], 1)
    }

    static func isSame(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) < matchTolerance
    }

    /// "0.5x", "1x", "1.8x" — one decimal, and none when it would be a zero.
    ///
    /// Not in `Strings`: the same in both languages, and the app's Chinese
    /// copy sweep reads a bare "2x" as an untranslated English string.
    static func label(_ display: CGFloat) -> String {
        let rounded = (display * 10).rounded() / 10
        if abs(rounded - rounded.rounded()) < 0.05 {
            return "\(Int(rounded.rounded()))x"
        }
        return String(format: "%.1fx", rounded)
    }
}
