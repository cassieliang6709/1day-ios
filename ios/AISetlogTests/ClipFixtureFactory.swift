import AVFoundation
import UIKit

/// Generates short video files for the stitcher tests.
///
/// These used to be seven `day*.mp4` files in the app bundle, which meant
/// every release shipped test fixtures to users. Fixtures belong to the tests
/// that need them, so they're built here instead.
enum ClipFixtureFactory {
    /// Portrait, matching what the camera actually produces, so seeded stories
    /// exercise the same layout paths as real ones.
    private static let size = CGSize(width: 540, height: 960)

    /// Distinct flat colours — a test only needs each clip to be
    /// distinguishable and decodable.
    private static let palette: [UIColor] = [
        .systemTeal, .systemGreen, .systemOrange,
        .systemPink, .systemPurple, .systemBlue, .systemYellow,
    ]

    /// Frames at 30fps. Two seconds, matching the app's default clip length so
    /// seeded stories and stitcher tests behave like the real thing.
    private static let frameCount = 60

    /// Writes a 2s clip and returns its URL, or nil on failure.
    static func makeClip(index: Int) async -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("demo_\(index)_\(UUID().uuidString).mov")

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return nil }
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
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        guard let buffer = pixelBuffer(color: palette[index % palette.count]) else { return nil }
        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try? await Task.sleep(for: .milliseconds(5))
            }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        return writer.status == .completed ? url : nil
    }

    private static func pixelBuffer(color: UIColor) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault, Int(size.width), Int(size.height),
            kCVPixelFormatType_32ARGB,
            [kCVPixelBufferCGImageCompatibilityKey: true] as CFDictionary,
            &buffer)
        guard let buffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        else { return nil }

        context.setFillColor(color.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        return buffer
    }
}
