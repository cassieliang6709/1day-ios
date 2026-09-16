import AVFoundation
import XCTest
@testable import AISetlog

/// Your dials are yours.
///
/// A shared film is stitched on your phone out of everybody's takes. Before
/// `lookAuthorID` existed the grade you set for your own face was baked onto
/// your friends' footage on the way through — they filmed in their light, not
/// yours, and they never agreed to it. These tests film two clips under
/// different authors and check which of them came out changed.
final class PersonalEffectScopeTests: XCTestCase {
    private var owned: [URL] = []

    override func tearDown() {
        owned.forEach { try? FileManager.default.removeItem(at: $0) }
        owned = []
        super.tearDown()
    }

    func testAGradeInASharedRoomStopsAtYourOwnTakes() async throws {
        let mine = try await fixture(index: 0)
        let theirs = try await fixture(index: 1)

        let ungraded = try await luminances(
            mine: mine, theirs: theirs, look: .none, authorID: "me")
        let graded = try await luminances(
            mine: mine, theirs: theirs, look: .init(exposure: 50), authorID: "me")

        XCTAssertGreaterThan(
            graded.mine, ungraded.mine + 0.02,
            "Your own take should have taken the grade")
        XCTAssertEqual(
            graded.theirs, ungraded.theirs, accuracy: 0.02,
            "A friend's take must come out as they filmed it")
    }

    func testASoloFilmGradesEverythingBecauseItIsAllYours() async throws {
        let first = try await fixture(index: 2)
        let second = try await fixture(index: 3)

        let ungraded = try await luminances(
            mine: first, theirs: second, look: .none, authorID: nil)
        let graded = try await luminances(
            mine: first, theirs: second, look: .init(exposure: 50), authorID: nil)

        XCTAssertGreaterThan(graded.mine, ungraded.mine + 0.02)
        XCTAssertGreaterThan(graded.theirs, ungraded.theirs + 0.02)
    }

    // MARK: - Helpers

    /// Stitches the two clips side by side and reads back how bright each half
    /// came out. Sequential would overwrite one with the other; the grid keeps
    /// both on screen at once, which is also the layout a shared room uses.
    private func luminances(
        mine: URL, theirs: URL, look: PersonalEffectParameters, authorID: String?
    ) async throws -> (mine: Double, theirs: Double) {
        var options = VideoStitcher.Options()
        options.layout = .friendsTogether
        options.aspect = .square
        options.showDayCaptions = false
        options.crossfadeSeconds = 0
        options.look = look
        options.lookAuthorID = authorID

        let clips = [
            DayClip(day: 1, url: mine, authorName: "Me", authorID: "me", key: "me"),
            DayClip(day: 1, url: theirs, authorName: "Them", authorID: "them", key: "them"),
        ]
        let film = try await VideoStitcher.stitch(clips: clips, options: options)
        owned.append(film)

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: film))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.2, preferredTimescale: 600)
        let image = try await generator.image(
            at: CMTime(seconds: 0.2, preferredTimescale: 600)).image

        // A square canvas with two clips stacks them, so "mine" is the top half.
        let height = CGFloat(image.height), width = CGFloat(image.width)
        return (
            mine: try luminance(of: image, in: CGRect(
                x: width * 0.3, y: height * 0.15, width: width * 0.4, height: height * 0.1)),
            theirs: try luminance(of: image, in: CGRect(
                x: width * 0.3, y: height * 0.75, width: width * 0.4, height: height * 0.1)))
    }

    private func luminance(of image: CGImage, in rect: CGRect) throws -> Double {
        let cropped = try XCTUnwrap(image.cropping(to: rect))
        let width = cropped.width, height = cropped.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(bytes.withUnsafeMutableBytes { raw in
            CGContext(
                data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        })
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))

        var total = 0.0
        for i in stride(from: 0, to: bytes.count, by: 4) {
            total += 0.299 * Double(bytes[i]) / 255
                + 0.587 * Double(bytes[i + 1]) / 255
                + 0.114 * Double(bytes[i + 2]) / 255
        }
        return total / Double(width * height)
    }

    /// A mid-grey clip, so a brightness change is unambiguous in either
    /// direction — a clip that is already near white cannot get lifted.
    private func fixture(index: Int) async throws -> URL {
        let size = CGSize(width: 480, height: 480)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scope-\(index)-\(UUID().uuidString).mov")
        owned.append(url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: size.width,
                AVVideoHeightKey: size.height,
            ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input, sourcePixelBufferAttributes: nil)
        guard writer.canAdd(input) else { throw Failure.writer }
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault, Int(size.width), Int(size.height),
            kCVPixelFormatType_32ARGB,
            [kCVPixelBufferCGImageCompatibilityKey: true] as CFDictionary, &buffer)
        let pixels = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        let context = try XCTUnwrap(CGContext(
            data: CVPixelBufferGetBaseAddress(pixels),
            width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixels),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue))
        context.setFillColor(gray: 0.45, alpha: 1)
        context.fill(CGRect(origin: .zero, size: size))
        CVPixelBufferUnlockBaseAddress(pixels, [])

        for frame in 0..<15 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            adaptor.append(
                pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw Failure.writer }
        return url
    }

    private enum Failure: Error { case writer }
}
