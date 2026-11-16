import Foundation
import Observation

@MainActor
@Observable
final class ClipCameraIndex {
    static let shared = ClipCameraIndex()

    private(set) var cameras: [String: CameraStyle] = [:]

    @ObservationIgnored private var inFlight: Set<String> = []

    nonisolated static func key(url: URL, recordedAt: Date) -> String {
        "\(url.path)|\(recordedAt.timeIntervalSince1970)"
    }

    func load(_ clips: [LibraryClip]) {
        load(clips.map { (key: $0.cameraKey, url: $0.url) })
    }

    func load(_ files: [(key: String, url: URL)]) {
        let jobs = files.filter { cameras[$0.key] == nil && !inFlight.contains($0.key) }
        guard !jobs.isEmpty else { return }
        inFlight.formUnion(jobs.map(\.key))

        Task.detached(priority: .utility) { [weak self] in
            var batch: [String: CameraStyle] = [:]
            for (index, job) in jobs.enumerated() {
                batch[job.key] = await CameraStyleBaker.cameraStyle(of: job.url) ?? .standard
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
