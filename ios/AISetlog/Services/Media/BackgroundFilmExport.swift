import AVFoundation
import BackgroundTasks
import CryptoKit
import Observation

@MainActor
@Observable
final class BackgroundFilmExport {
    static let shared = BackgroundFilmExport()

    private struct Signature: Encodable {
        let version = 1
        let clips: [DayClip]
        let options: VideoStitcher.Options
        let keptIDs: [String]?
        let modifications: [Date?]
    }

    @MainActor private final class Job {
        let id = UUID().uuidString
        var worker: Task<URL, Error>?
        var backgroundTask: BGTask?
        var expired = false
        var fraction: Double = 0
        var observers: [UUID: @MainActor (Double, Bool) -> Void] = [:]

        @MainActor func report(_ fraction: Double) {
            self.fraction = max(self.fraction, min(max(fraction, 0), 1))
            for observer in observers.values { observer(self.fraction, backgroundTask != nil) }
        }
    }

    private var jobs: [String: Job] = [:]
    private var resetTask: Task<Void, Never>?

    func resetForAccountChange() {
        let previous = resetTask
        let workers = jobs.values.compactMap(\.worker)
        workers.forEach { $0.cancel() }
        resetTask = Task {
            await previous?.value
            for worker in workers { _ = try? await worker.value }
            if let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
                try? FileManager.default.removeItem(at: root.appendingPathComponent("film-exports"))
            }
        }
    }

    func render(
        clips: [DayClip], options: VideoStitcher.Options,
        onProgress: @escaping @MainActor (Double, Bool) -> Void = { _, _ in }
    ) async throws -> URL {
        await resetTask?.value
        var signatureOptions = options
        signatureOptions.keptClipIDs = nil
        let signature = Signature(
            clips: clips, options: signatureOptions,
            keptIDs: options.keptClipIDs.map { $0.sorted() },
            modifications: clips.map {
                try? $0.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            })
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let key = SHA256.hash(data: try encoder.encode(signature))
            .map { String(format: "%02x", $0) }.joined()
        let root = try FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("film-exports", isDirectory: true)
        let directory = root.appendingPathComponent(key, isDirectory: true)
        let output = directory.appendingPathComponent("film.mp4")
        if FileManager.default.fileExists(atPath: output.path) { return output }
        let observerID = UUID()
        if let job = jobs[key], let worker = job.worker {
            job.observers[observerID] = onProgress
            onProgress(job.fraction, job.backgroundTask != nil)
            defer { job.observers[observerID] = nil }
            return try await worker.value
        }

        let job = Job()
        job.observers[observerID] = onProgress
        defer { job.observers[observerID] = nil }
        jobs[key] = job
        let worker = Task { () throws -> URL in
            defer {
                job.backgroundTask?.expirationHandler = nil
                job.backgroundTask = nil
                jobs[key] = nil
            }
            if #available(iOS 26.0, *) { await acquireBackgroundTask(for: job) }
            job.report(0)
            do {
                try Task.checkCancellation()
                if job.expired { throw CancellationError() }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let inputs = directory.appendingPathComponent("inputs", isDirectory: true)
                if FileManager.default.fileExists(atPath: inputs.path) {
                    try FileManager.default.removeItem(at: inputs)
                }
                try FileManager.default.createDirectory(at: inputs, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: inputs) }
                var snapshot: [DayClip] = []
                for (index, clip) in clips.enumerated() {
                    try Task.checkCancellation()
                    let copy = inputs.appendingPathComponent("\(index).\(clip.url.pathExtension)")
                    try FileManager.default.copyItem(at: clip.url, to: copy)
                    snapshot.append(clip.replacingURL(copy))
                }
                let rendered = try await VideoStitcher.stitch(clips: snapshot, options: options) { fraction in
                    Task { @MainActor in
                        job.report(fraction)
                        if #available(iOS 26.0, *),
                           let task = job.backgroundTask as? BGContinuedProcessingTask {
                            task.progress.completedUnitCount = Int64(1 + fraction * 999)
                        }
                    }
                }
                defer { try? FileManager.default.removeItem(at: rendered) }
                try Task.checkCancellation()
                try FileManager.default.moveItem(at: rendered, to: output)
                job.backgroundTask?.setTaskCompleted(success: true)
                trimCache(root, keeping: key)
                return output
            } catch {
                job.backgroundTask?.setTaskCompleted(success: false)
                try? FileManager.default.removeItem(at: directory)
                throw error
            }
        }
        job.worker = worker
        return try await worker.value
    }

    @available(iOS 26.0, *)
    private func acquireBackgroundTask(for job: Job) async {
        guard BGTaskScheduler.supportedResources.contains(.gpu),
              let bundleID = Bundle.main.bundleIdentifier else { return }
        let identifier = "\(bundleID).film-export.\(job.id)"
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let registered = BGTaskScheduler.shared.register(
                forTaskWithIdentifier: identifier, using: .main
            ) { [weak job] task in
                Task { @MainActor in
                    guard let job else {
                        task.setTaskCompleted(success: false)
                        continuation.resume()
                        return
                    }
                    job.backgroundTask = task
                    if let task = task as? BGContinuedProcessingTask {
                        task.progress.totalUnitCount = 1000
                        task.progress.completedUnitCount = 1
                    }
                    task.expirationHandler = { [weak job] in
                        Task { @MainActor in
                            guard let job else { return }
                            job.expired = true
                            job.worker?.cancel()
                        }
                    }
                    continuation.resume()
                }
            }
            guard registered else { continuation.resume(); return }
            let request = BGContinuedProcessingTaskRequest(
                identifier: identifier, title: Strings.backgroundFilmTitle,
                subtitle: Strings.backgroundFilmPreparing)
            request.strategy = .fail
            request.requiredResources = .gpu
            do {
                try BGTaskScheduler.shared.submit(request)
            } catch {
                continuation.resume()
            }
        }
    }

    private func trimCache(_ root: URL, keeping key: String) {
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let unused = directories.filter { $0.lastPathComponent != key && jobs[$0.lastPathComponent] == nil }
            .sorted {
                let lhs = try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                let rhs = try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                return (lhs ?? .distantPast) > (rhs ?? .distantPast)
            }
        for directory in unused.dropFirst(7) { try? FileManager.default.removeItem(at: directory) }
    }
}
