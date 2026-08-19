#if DEBUG
import AVFoundation
import UIKit

/// Stand-in footage for the simulator, which has no camera.
///
/// The recorder's debug escape hatch used to load one of seven `day*.mp4`
/// fixtures from the app bundle. Those left the bundle when the stitcher tests
/// got their own generator (`ClipFixtureFactory`) — shipping test footage to
/// users was the thing being fixed — and the button has been silently doing
/// nothing ever since. It draws its clip on the spot now.
///
/// Each clip is stamped with who recorded it and which moment it fills, and
/// tinted per author, so two simulators in the same room contribute visibly
/// different footage and a stitched film shows at a glance whose clip is whose.
enum DemoClipFactory {
    /// One flat colour per author. Seven is enough to keep two or three
    /// testers apart without the palette drifting into "real footage" territory.
    private static let palette: [UIColor] = [
        .systemTeal, .systemIndigo, .systemOrange,
        .systemPink, .systemPurple, .systemBrown, .systemGreen,
    ]

    private static let frameRate: Int32 = 30

    /// `String.hashValue` is seeded per process, so two simulators would pick
    /// unrelated colours for the same name — and could collide on the same one.
    private static func stableHash(_ text: String) -> Int {
        text.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0xFF_FFFF }
    }

    static func makeClip(
        moment: Int,
        label: String,
        author: String?,
        seconds: Double,
        orientation: Challenge.Orientation
    ) async -> URL? {
        let size: CGSize = orientation == .landscape
            ? CGSize(width: 960, height: 540)
            : CGSize(width: 540, height: 960)
        let name = author ?? "Tester"
        // Shift by the moment too, so one author's seven clips don't all look
        // identical in the finished film.
        let color = palette[(stableHash(name) + moment) % palette.count]

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("demo_\(moment)_\(UUID().uuidString).mov")

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

        let frameCount = max(Int(seconds * Double(frameRate)), 1)
        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try? await Task.sleep(for: .milliseconds(5))
            }
            let image = render(
                size: size, color: color, author: name, moment: moment,
                label: label, progress: Double(frame) / Double(frameCount))
            guard let buffer = pixelBuffer(from: image, size: size) else { continue }
            adaptor.append(
                buffer,
                withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: frameRate))
        }
        input.markAsFinished()
        await writer.finishWriting()
        return writer.status == .completed ? url : nil
    }

    /// A flat card: who, which moment, and a sweeping bar so it's obvious the
    /// clip is playing rather than frozen on its first frame.
    private static func render(
        size: CGSize,
        color: UIColor,
        author: String,
        moment: Int,
        label: String,
        progress: Double
    ) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center

            func draw(_ text: String, y: CGFloat, size fontSize: CGFloat, weight: UIFont.Weight) {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: fontSize, weight: weight),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraph,
                ]
                let bounds = CGRect(x: 0, y: y, width: size.width, height: fontSize * 1.4)
                (text as NSString).draw(in: bounds, withAttributes: attributes)
            }

            draw(author, y: size.height * 0.36, size: size.width * 0.09, weight: .heavy)
            draw("MOMENT \(moment)", y: size.height * 0.46, size: size.width * 0.055, weight: .bold)
            draw(label, y: size.height * 0.53, size: size.width * 0.045, weight: .medium)

            let barHeight = size.height * 0.012
            let barY = size.height * 0.82
            UIColor.white.withAlphaComponent(0.3).setFill()
            ctx.fill(CGRect(x: 0, y: barY, width: size.width, height: barHeight))
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: barY, width: size.width * progress, height: barHeight))
        }
    }

    private static func pixelBuffer(from image: UIImage, size: CGSize) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault, Int(size.width), Int(size.height),
            kCVPixelFormatType_32ARGB,
            [kCVPixelBufferCGImageCompatibilityKey: true] as CFDictionary,
            &buffer)
        guard let buffer, let cgImage = image.cgImage else { return nil }

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

        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        return buffer
    }
}
#endif
