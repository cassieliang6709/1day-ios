import AVFoundation
import CoreGraphics

enum ClipQuality {
    private static let cache = Cache()
    private static let side = 96
    private static let minBrightness = 0.12
    private static let minSharpness = 12.0

    static func isUsable(_ url: URL) async -> Bool {
        await cache.isUsable(url)
    }

    private actor Cache {
        var known: [URL: Bool] = [:]

        func isUsable(_ url: URL) async -> Bool {
            if let usable = known[url] { return usable }
            let usable = await ClipQuality.measure(url).map {
                $0.brightness >= ClipQuality.minBrightness && $0.sharpness >= ClipQuality.minSharpness
            } ?? true
            known[url] = usable
            return usable
        }
    }

    private static func measure(_ url: URL) async -> (brightness: Double, sharpness: Double)? {
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: side, height: side)
        let middle = CMTime(seconds: duration.isFinite ? duration / 2 : 0.1, preferredTimescale: 600)
        guard let frame = try? await generator.image(at: middle).image else { return nil }
        return stats(frame)
    }

    private static func stats(_ image: CGImage) -> (brightness: Double, sharpness: Double)? {
        let width = image.width, height = image.height
        guard width > 2, height > 2 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        let total = pixels.reduce(0.0) { $0 + Double($1) }
        let brightness = total / Double(pixels.count) / 255

        var sum = 0.0, sumSquares = 0.0, count = 0.0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let i = y * width + x
                let laplacian = 4 * Double(pixels[i]) - Double(pixels[i - 1]) - Double(pixels[i + 1])
                    - Double(pixels[i - width]) - Double(pixels[i + width])
                sum += laplacian
                sumSquares += laplacian * laplacian
                count += 1
            }
        }
        let mean = sum / count
        let sharpness = sumSquares / count - mean * mean
        return (brightness, sharpness)
    }
}
