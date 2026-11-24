import AVFoundation
import Vision

struct ClipTagInfo: Equatable, Sendable {
    var faces: Int
    var labels: [String]
}

enum ClipTags {
    private static let cache = Cache()
    private static let maxLabels = 3
    private static let minConfidence: Float = 0.3

    static func tags(for url: URL) async -> ClipTagInfo {
        await cache.tags(for: url)
    }

    private actor Cache {
        var known: [URL: ClipTagInfo] = [:]

        func tags(for url: URL) async -> ClipTagInfo {
            if let info = known[url] { return info }
            let info = await ClipTags.measure(url)
            known[url] = info
            return info
        }
    }

    private static func measure(_ url: URL) async -> ClipTagInfo {
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 512, height: 512)
        let middle = CMTime(seconds: duration.isFinite ? duration / 2 : 0.1, preferredTimescale: 600)
        guard let frame = try? await generator.image(at: middle).image else {
            return ClipTagInfo(faces: 0, labels: [])
        }

        let faces = VNDetectFaceRectanglesRequest()
        let scene = VNClassifyImageRequest()
        try? VNImageRequestHandler(cgImage: frame).perform([faces, scene])
        let labels = (scene.results ?? [])
            .filter { $0.confidence >= minConfidence }
            .prefix(maxLabels)
            .map(\.identifier)
        return ClipTagInfo(faces: faces.results?.count ?? 0, labels: Array(labels))
    }
}
