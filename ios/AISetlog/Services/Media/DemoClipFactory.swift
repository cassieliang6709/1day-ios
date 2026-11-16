#if DEBUG || LOCAL_ROOM_CHAT_DEMO
import AVFoundation
import UIKit

enum DemoClipFactory {
    private static let palette: [UIColor] = [
        .systemTeal, .systemIndigo, .systemOrange,
        .systemPink, .systemPurple, .systemBrown, .systemGreen,
    ]

    private static let frameRate: Int32 = 30

    static let standInSeconds: Double = 3

    private static func stableHash(_ text: String) -> Int {
        text.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0xFF_FFFF }
    }

    private static func tint(author: String, moment: Int) -> UIColor {
        let base = palette[stableHash(author) % palette.count]
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        else { return base }
        let step = CGFloat((moment - 1) % 4) * 0.09
        return UIColor(
            hue: hue, saturation: saturation,
            brightness: min(brightness + step, 1), alpha: alpha)
    }

    static func makeClip(
        moment: Int,
        label: String,
        author: String?,
        seconds: Double,
        orientation: Challenge.Orientation
    ) async -> URL? {
        let size: CGSize = switch orientation {
        case .landscape: CGSize(width: 960, height: 540)
        case .portrait: CGSize(width: 540, height: 960)
        case .square: CGSize(width: 720, height: 720)
        }
        let name = author ?? "Tester"
        let color = tint(author: name, moment: moment)

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
                guard !Task.isCancelled, writer.status == .writing else {
                    writer.cancelWriting()
                    try? FileManager.default.removeItem(at: url)
                    return nil
                }
                try? await Task.sleep(for: .milliseconds(5))
            }
            guard !Task.isCancelled else {
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: url)
                return nil
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
            draw("MOMENT \(moment) · \(Int(progress * 100))%", y: size.height * 0.46, size: size.width * 0.055, weight: .bold)
            draw(label, y: size.height * 0.53, size: size.width * 0.045, weight: .medium)
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
