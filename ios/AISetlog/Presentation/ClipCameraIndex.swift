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

    func load(_ clips: [LibraryClip]) {
        let missing = clips.filter { cameras[$0.cameraKey] == nil && !inFlight.contains($0.cameraKey) }
        guard !missing.isEmpty else { return }
        let jobs = missing.map { (key: $0.cameraKey, url: $0.url) }
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
