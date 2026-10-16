import Foundation
import Observation

/// Which camera each library clip was filmed with, read from the file's own
/// metadata (`CameraStyleBaker.cameraStyle(of:)`).
///
/// Reading metadata opens the file, so it is done once per clip, off the main
/// actor, and remembered for the life of the app. A clip that has not been read
/// yet simply isn't in `cameras`: it shows under 全部 and under no camera chip
/// until its read lands.
@MainActor
@Observable
final class ClipCameraIndex {
    static let shared = ClipCameraIndex()

    /// Keyed by `LibraryClip.cameraKey`. `.standard` means "read, no camera".
    private(set) var cameras: [String: CameraStyle] = [:]

    @ObservationIgnored private var inFlight: Set<String> = []

    /// A file plus its date, so a re-recorded take at the same path is read again.
    nonisolated static func key(url: URL, recordedAt: Date) -> String {
        "\(url.path)|\(recordedAt.timeIntervalSince1970)"
    }

    func load(_ clips: [LibraryClip]) {
        load(clips.map { (key: $0.cameraKey, url: $0.url) })
    }

    /// For files that aren't `LibraryClip`s — the drafts list.
    func load(_ files: [(key: String, url: URL)]) {
        let jobs = files.filter { cameras[$0.key] == nil && !inFlight.contains($0.key) }
        guard !jobs.isEmpty else { return }
        inFlight.formUnion(jobs.map(\.key))

        Task.detached(priority: .utility) { [weak self] in
            var batch: [String: CameraStyle] = [:]
            for (index, job) in jobs.enumerated() {
                batch[job.key] = await CameraStyleBaker.cameraStyle(of: job.url) ?? .standard
                // Publish in chunks so a long archive fills in progressively
                // without re-rendering the page once per clip.
                if batch.count >= 24 || index == jobs.count - 1 {
                    let ready = batch
                    batch = [:]
                    await self?.store(ready)
                }
            }
        }
    }

    private func store(_ ready: [String: CameraStyle]) {
        cameras.merge(ready) { _, new in new }
        inFlight.subtract(ready.keys)
    }
}
