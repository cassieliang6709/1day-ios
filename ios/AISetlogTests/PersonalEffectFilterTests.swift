import AVFoundation
import CoreImage
import XCTest
@testable import AISetlog

final class PersonalEffectFilterTests: XCTestCase {

    private let context = CIContext(options: [.useSoftwareRenderer: true])
    private let frame = CGRect(x: 0, y: 0, width: 32, height: 32)

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
        let contrast: Double
        var luminance: Double { 0.299 * red + 0.587 * green + 0.114 * blue }
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


    func testCentredDialsReturnTheVerySameImage() {
        let input = subject()
        XCTAssertTrue(PersonalEffectFilter.apply(.none, to: input) === input)
    }


    func testEveryDialKeepsTheFrameItWasGiven() {
        let settings: [PersonalEffectParameters] = [
            .init(exposure: 50), .init(exposure: -50),
            .init(temperature: 50), .init(temperature: -50),
            .init(contrast: 50), .init(contrast: -50),
            .init(exposure: 30, temperature: -25, contrast: 15),
        ]
        for parameters in settings {
            XCTAssertEqual(
                PersonalEffectFilter.apply(parameters, to: subject()).extent, frame,
                "\(parameters)")
        }
    }

    func testAFrameAwayFromTheOriginKeepsItsPosition() {
        let offset = subject().transformed(by: CGAffineTransform(translationX: 100, y: 40))
        XCTAssertEqual(
            PersonalEffectFilter.apply(.init(exposure: 40), to: offset).extent, offset.extent)
    }


    func testExposureLiftsAndItsOppositeDarkens() throws {
        let before = try read(subject())
        let up = try read(PersonalEffectFilter.apply(.init(exposure: 50), to: subject()))
        let down = try read(PersonalEffectFilter.apply(.init(exposure: -50), to: subject()))
        XCTAssertGreaterThan(up.luminance, before.luminance)
        XCTAssertLessThan(down.luminance, before.luminance)
    }

    func testWarmthGoesWarmNotBlue() throws {
        let before = try read(subject())
        let warm = try read(PersonalEffectFilter.apply(.init(temperature: 50), to: subject()))
        let cool = try read(PersonalEffectFilter.apply(.init(temperature: -50), to: subject()))
        XCTAssertGreaterThan(warm.warmth, before.warmth)
        XCTAssertLessThan(cool.warmth, before.warmth)
    }

    func testContrastHardensEdgesAndItsOppositeFlattensThem() throws {
        let before = try read(subject())
        let hard = try read(PersonalEffectFilter.apply(.init(contrast: 50), to: subject()))
        let flat = try read(PersonalEffectFilter.apply(.init(contrast: -50), to: subject()))
        XCTAssertGreaterThan(hard.contrast, before.contrast)
        XCTAssertLessThan(flat.contrast, before.contrast)
    }

    func testAFullGradeChangesTheImageWithoutBlowingItOut() throws {
        let graded = try read(PersonalEffectFilter.apply(
            .init(exposure: 40, temperature: 30, contrast: 25), to: subject()))
        let before = try read(subject())
        XCTAssertGreaterThan(graded.luminance, before.luminance)
        XCTAssertLessThan(graded.luminance, 1)
        XCTAssertGreaterThan(graded.contrast, 0)
    }


    func testPlaybackIsLeftAloneEntirelyWhenTheDialsAreCentred() async throws {
        let made = await ClipFixtureFactory.makeClip(index: 0)
        let url = try XCTUnwrap(made)
        defer { try? FileManager.default.removeItem(at: url) }
        let composition = await PersonalEffectFilter.playbackComposition(
            .none, for: AVURLAsset(url: url))
        XCTAssertNil(composition)
    }

    func testPlaybackGetsACompositionOnceADialMoves() async throws {
        let made = await ClipFixtureFactory.makeClip(index: 1)
        let url = try XCTUnwrap(made)
        defer { try? FileManager.default.removeItem(at: url) }
        let composition = await PersonalEffectFilter.playbackComposition(
            .init(exposure: 30), for: AVURLAsset(url: url))
        XCTAssertNotNil(composition)
    }

    func testExportSkipsTheCopyWhenThereIsNothingToApply() async throws {
        let made = await ClipFixtureFactory.makeClip(index: 2)
        let url = try XCTUnwrap(made)
        defer { try? FileManager.default.removeItem(at: url) }
        let copy = try await PersonalEffectFilter.filteredCopy(of: url, parameters: .none)
        XCTAssertEqual(copy, url)
    }

    func testExportWritesAPlayableCopyAndLeavesTheRecordingAlone() async throws {
        let made = await ClipFixtureFactory.makeClip(index: 3)
        let url = try XCTUnwrap(made)
        defer { try? FileManager.default.removeItem(at: url) }
        let before = try Data(contentsOf: url)

        let copy = try await PersonalEffectFilter.filteredCopy(
            of: url, parameters: .init(exposure: 40, contrast: 20))
        defer { try? FileManager.default.removeItem(at: copy) }
        XCTAssertNotEqual(copy, url)

        let tracks = try await AVURLAsset(url: copy).loadTracks(withMediaType: .video)
        XCTAssertFalse(tracks.isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }
}
