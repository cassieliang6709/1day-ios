import AVFoundation

enum VideoExportSession {
    private final class Operation: @unchecked Sendable {
        let session: AVAssetExportSession
        let lock = NSLock()
        var cancelled = false

        init(_ session: AVAssetExportSession) { self.session = session }

        func start(_ completion: @escaping @Sendable () -> Void) {
            let started = lock.withLock {
                guard !cancelled else { return false }
                session.exportAsynchronously(completionHandler: completion)
                return true
            }
            if !started { completion() }
        }

        func cancel() {
            lock.withLock {
                cancelled = true
                session.cancelExport()
            }
        }
    }

    static func run(
        _ session: AVAssetExportSession,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        try Task.checkCancellation()
        var completed = false
        defer {
            if !completed, let url = session.outputURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
        let monitor = Task {
            while !Task.isCancelled {
                progress?(Double(session.progress))
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        let operation = Operation(session)
        defer { monitor.cancel() }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                operation.start { continuation.resume() }
            }
        } onCancel: {
            operation.cancel()
        }
        try Task.checkCancellation()
        guard session.status == .completed else {
            throw session.error ?? VideoStitcher.StitchError.exportFailed("Export did not complete")
        }
        completed = true
        progress?(1)
    }
}
