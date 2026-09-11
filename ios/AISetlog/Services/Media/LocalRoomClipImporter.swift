#if DEBUG || LOCAL_ROOM_CHAT_DEMO
import AVFoundation
import Foundation

/// Reads a picker-owned copy (or test fixture); never deletes or modifies it.
/// The caller owns the returned trimmed file. Failed/cancelled outputs are removed.
enum LocalRoomClipImporter {
    static func trim(_ source: URL) async throws -> URL {
        try Task.checkCancellation()
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("local-room-import-\(UUID()).mov")
        do {
            let asset = AVURLAsset(url: source)
            let duration = try await asset.load(.duration).seconds
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard duration.isFinite, duration > 0, !tracks.isEmpty,
                  let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset960x540) else {
                throw LocalRoomRuntime.Failure.media
            }
            exporter.outputURL = output
            exporter.outputFileType = .mov
            exporter.timeRange = CMTimeRange(start: .zero,
                duration: CMTime(seconds: min(duration, 3), preferredTimescale: 600))
            await exporter.export()
            try Task.checkCancellation()
            guard exporter.status == .completed else { throw LocalRoomRuntime.Failure.media }
            return output
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }
}
#endif
