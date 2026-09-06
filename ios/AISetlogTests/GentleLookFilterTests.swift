import AVFoundation
import CoreImage
import XCTest
@testable import AISetlog

/// The chain, run on real pixels.
///
/// `GentleLookTests` covers the arithmetic; this covers the thing the
/// arithmetic is for. A filter chain fails in ways a value type can't: a blur
/// that grows the frame and shifts the picture, a blend that darkens instead of
/// softening, a temperature filter wired backwards so "warm" comes out blue.
/// All three are visible in a 32×32 image, so none of them need a video.
final class GentleLookFilterTests: XCTestCase {

    private let context = CIContext(options: [.useSoftwareRenderer: true])
    private let frame = CGRect(x: 0, y: 0, width: 32, height: 32)

    /// A checkerboard on a mid-grey card: something with edges to soften and a
    /// known average to lift.
    private func subject() -> CIImage {
        let grey = CIImage(color: CIColor(red: 0.5, green: 0.45, blue: 0.42))
            .cropped(to: frame)
        let checks = CIFilter(name: "CICheckerboardGenerator", parameters: [
            "inputCenter": CIVector(x: 0, y: 0),
            "inputColor0": CIColor(red: 0.75, green: 0.7, blue: 0.66),
            "inputColor1": CIColor(red: 0.3, green: 0.26, blue: 0.24),
            "inputWidth": 4.0,
        ])!.outputImage!.cropped(to: frame)
        return checks.applyingFilter("CISourceOverCompositing", parameters: [
            kCIInputBackgroundImageKey: grey,
        ]).cropped(to: frame)
    }

    private struct Readout {
        let red: Double
        let green: Double
        let blue: Double
        /// Mean absolute difference between neighbouring pixels — how much edge
        /// the picture still has.
        let contrast: Double
        var luminance: Double { 0.299 * red + 0.587 * green + 0.114 * blue }
        /// Above 1 is warm, below 1 is cold.
        var warmth: Double { red / blue }
    }

    private func read(_ image: CIImage, in bounds: CGRect? = nil) throws -> Readout {
        let frame = bounds ?? self.frame
        let width = Int(frame.width), height = Int(frame.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            context.render(
                image, toBitmap: raw.baseAddress!, rowBytes: width * 4,
                bounds: frame, format: .RGBA8, colorSpace: nil)
        }
        var sum = (r: 0.0, g: 0.0, b: 0.0)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            sum.r += Double(bytes[i]) / 255
            sum.g += Double(bytes[i + 1]) / 255
            sum.b += Double(bytes[i + 2]) / 255
        }
        let count = Double(width * height)

        var edge = 0.0
        for y in 0..<height {
            for x in 1..<width {
                let here = Double(bytes[(y * width + x) * 4]) / 255
                let left = Double(bytes[(y * width + x - 1) * 4]) / 255
                edge += abs(here - left)
            }
        }

        return Readout(
            red: sum.r / count, green: sum.g / count, blue: sum.b / count,
            contrast: edge / (count - Double(height)))
    }

    // MARK: Off

    func testOffReturnsTheVerySameImage() {
        let input = subject()
        XCTAssertTrue(GentleLookFilter.apply(.none, to: input) === input)
    }

    // MARK: The frame

    /// The one that bites: `applyingGaussianBlur` grows an image's extent past
    /// its edges, and a video composition handed a frame bigger than the one it
    /// asked for renders the picture shifted. Every preset has to come back the
    /// same size it went in.
    func testEveryPresetKeepsTheFrameItWasGiven() {
        for (key, look) in GentleLook.presets {
            XCTAssertEqual(
                GentleLookFilter.apply(look, to: subject()).extent, frame, "\(key)")
        }
        XCTAssertEqual(
            GentleLookFilter.apply(
                GentleLook(smoothing: 1, brightness: 1, warmth: 1), to: subject()).extent,
            frame)
    }

    /// A frame that doesn't start at the origin — video frames often don't.
    func testAnOffsetFrameStaysWhereItWas() {
        let offset = subject().transformed(by: CGAffineTransform(translationX: 100, y: 40))
        XCTAssertEqual(
            GentleLookFilter.apply(.soft, to: offset).extent, offset.extent)
    }

    // MARK: What it does to the picture

    func testSmoothingTakesEdgesDownWithoutDarkeningThePicture() throws {
        let before = try read(subject())
        let after = try read(
            GentleLookFilter.apply(GentleLook(smoothing: 1), to: subject()))

        XCTAssertLessThan(after.contrast, before.contrast * 0.9)
        // Softening must not be a synonym for dimming — the soft-light blend
        // is capable of both, and only one of them is wanted.
        XCTAssertEqual(after.luminance, before.luminance, accuracy: 0.06)
    }

    func testBrightnessLifts() throws {
        let before = try read(subject())
        let after = try read(
            GentleLookFilter.apply(GentleLook(brightness: 1), to: subject()))
        XCTAssertGreaterThan(after.luminance, before.luminance)
    }

    func testWarmthWarms() throws {
        let before = try read(subject())
        let after = try read(GentleLookFilter.apply(GentleLook(warmth: 1), to: subject()))
        XCTAssertGreaterThan(after.warmth, before.warmth)
        XCTAssertGreaterThan(after.red, before.red)
        XCTAssertLessThan(after.blue, before.blue)
    }

    /// The promise: gentler than a filter, not a different face. A preset that
    /// moved the average pixel by a quarter would be the wrong feature.
    func testNoPresetMovesThePictureFar() throws {
        let before = try read(subject())
        for (key, look) in GentleLook.presets {
            let after = try read(GentleLookFilter.apply(look, to: subject()))
            XCTAssertLessThan(
                abs(after.luminance - before.luminance), 0.1,
                "\(key) changed the exposure more than a stop's worth")
            XCTAssertGreaterThan(
                after.contrast, before.contrast * 0.5,
                "\(key) smeared the picture")
        }
    }

    func testTheThreeDialsCompose() throws {
        let plain = try read(subject())
        let all = try read(GentleLookFilter.apply(.soft, to: subject()))
        XCTAssertLessThan(all.contrast, plain.contrast)
        XCTAssertGreaterThan(all.luminance, plain.luminance - 0.02)
        XCTAssertGreaterThan(all.warmth, plain.warmth)
    }

    // MARK: Playback

    func testNoCompositionIsBuiltForOff() async {
        let asset = AVURLAsset(url: URL(fileURLWithPath: "/dev/null"))
        let composition = await GentleLookFilter.playbackComposition(.none, for: asset)
        XCTAssertNil(composition)
    }

    /// Off must not copy the file, or every save-to-Photos with no look on
    /// would still spend an export pass per clip.
    func testOffCopiesNothing() async throws {
        let original = URL(fileURLWithPath: "/tmp/does-not-need-to-exist.mov")
        let result = try await GentleLookFilter.filteredCopy(of: original, look: .none)
        XCTAssertEqual(result, original)
    }

    // MARK: On real footage

    private func demoClip() async throws -> URL {
        let url = await DemoClipFactory.makeClip(
            moment: 1, label: "Morning light", author: "Tester",
            seconds: 1.0, orientation: .portrait)
        return try XCTUnwrap(url)
    }

    private func firstFrame(of url: URL, look: GentleLook) async throws -> Readout {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.videoComposition = await GentleLookFilter.playbackComposition(
            look, for: asset)
        let cgImage = try await generator.image(
            at: CMTime(seconds: 0.3, preferredTimescale: 600)).image
        return try read(CIImage(cgImage: cgImage), in: CGRect(
            x: 0, y: 0, width: cgImage.width, height: cgImage.height))
    }

    /// The composition path end to end: a real file, a real decode, a real
    /// frame. This is the one that would have caught a shifted picture, and the
    /// one that proves the frame arrives at all — the player builds the
    /// composition before it starts, so a composition that fails to build is a
    /// clip that never plays rather than a clip that plays unfiltered.
    func testAPlayedFrameComesBackFilteredAndNotBlack() async throws {
        let url = try await demoClip()
        defer { try? FileManager.default.removeItem(at: url) }

        let plain = try await firstFrame(of: url, look: .none)
        let looked = try await firstFrame(of: url, look: .warm)

        XCTAssertGreaterThan(plain.luminance, 0.02, "the demo clip decoded black")
        XCTAssertGreaterThan(looked.luminance, 0.02, "the filtered frame came back black")
        XCTAssertGreaterThan(looked.warmth, plain.warmth)
    }

    /// The export pre-pass: a new file, still the same clip.
    func testAFilteredCopyIsANewFileOfTheSameLength() async throws {
        let url = try await demoClip()
        defer { try? FileManager.default.removeItem(at: url) }

        let copy = try await GentleLookFilter.filteredCopy(of: url, look: .soft)
        defer { try? FileManager.default.removeItem(at: copy) }

        XCTAssertNotEqual(copy, url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))

        let before = try await AVURLAsset(url: url).load(.duration).seconds
        let after = try await AVURLAsset(url: copy).load(.duration).seconds
        XCTAssertEqual(after, before, accuracy: 0.1)

        // And it's actually filtered, not just re-encoded.
        let plain = try await firstFrame(of: url, look: .none)
        let baked = try await firstFrame(of: copy, look: .none)
        XCTAssertGreaterThan(baked.luminance, plain.luminance)
    }
}
