import AVFoundation
import LockedCameraCapture

enum LockedCaptureImporter {
    @MainActor private static var receiving: Set<URL> = []

    @MainActor
    static func importDirectory(
        _ directory: URL, into drafts: ClipDraftStore, receipts: UserDefaults = .standard
    ) async throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        let manifestFiles = files.filter { $0.pathExtension == "json" }
        var imported = Set(receipts.stringArray(forKey: "capture.importedIDs.v1") ?? [])
        var manifests: [LockedCaptureManifest] = []
        for file in manifestFiles {
            try Task.checkCancellation()
            let manifestValues = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard manifestValues.isRegularFile == true, manifestValues.isSymbolicLink != true else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let manifest = try JSONDecoder().decode(LockedCaptureManifest.self, from: Data(contentsOf: file))
            guard file.lastPathComponent == manifest.manifestName else {
                throw CocoaError(.fileReadCorruptFile)
            }
            manifests.append(manifest)
        }
        for movie in files where movie.pathExtension == "mov" {
            guard let id = UUID(uuidString: movie.deletingPathExtension().lastPathComponent),
                  !manifests.contains(where: { $0.id == id }), !imported.contains(id.uuidString)
            else { continue }
            let values = try movie.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let asset = AVURLAsset(url: movie)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let size = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let oriented = size.applying(transform)
            manifests.append(LockedCaptureManifest(
                id: id, recordedAt: values.contentModificationDate ?? .now,
                landscape: abs(oriented.width) > abs(oriented.height)))
        }
        for manifest in manifests {
            try Task.checkCancellation()
            if imported.contains(manifest.id.uuidString) { continue }
            let movie = directory.appendingPathComponent(manifest.movieName)
            let values = try movie.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let asset = AVURLAsset(url: movie)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let duration = try await asset.load(.duration).seconds
            guard !tracks.isEmpty, duration.isFinite, duration > 0, duration <= 2.5 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try Task.checkCancellation()
            try drafts.keep(
                tempURL: movie, orientation: manifest.landscape ? .landscape : .portrait,
                recordedAt: manifest.recordedAt, id: manifest.id)
            imported.insert(manifest.id.uuidString)
            receipts.set(imported.sorted(), forKey: "capture.importedIDs.v1")
        }
    }

    @available(iOS 18.0, *)
    @MainActor
    static func receive(_ directory: URL, into drafts: ClipDraftStore) async throws {
        guard receiving.insert(directory).inserted else { return }
        defer { receiving.remove(directory) }
        try await importDirectory(directory, into: drafts)
        try await LockedCameraCaptureManager.shared.invalidateSessionContent(at: directory)
    }
}
