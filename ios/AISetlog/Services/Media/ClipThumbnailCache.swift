import AVFoundation
import CryptoKit
import UIKit

actor ClipThumbnailCache {
    static let defaultDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ClipThumbnails", isDirectory: true)
    static let shared = ClipThumbnailCache()
    private static let storageLock = NSLock()
    private static var epochs: [Scope: UUID] = [:]
    private let generate: (URL) async -> UIImage?
    private let limit: Int
    private nonisolated let directory: URL
    private var pending: [Request: Task<UIImage?, Never>] = [:]

    init(directory: URL = ClipThumbnailCache.defaultDirectory, limit: Int = 128,
         generate: @escaping (URL) async -> UIImage? = ClipThumbnailCache.generateImage) {
        self.limit = max(1, limit)
        self.generate = generate
        self.directory = directory
    }

    private struct Scope: Hashable {
        let cacheDirectory: String
        let sourceDirectory: String
        init(cacheDirectory: URL, sourceDirectory: URL) {
            self.cacheDirectory = cacheDirectory.standardizedFileURL.path
            self.sourceDirectory = sourceDirectory.standardizedFileURL.path
        }
    }

    private struct Request: Hashable {
        let source: URL
        let refreshToken: Date?
        let modifiedAt: Date
        let size: Int
        let epoch: UUID?
        let prefix: String
        let destination: URL
    }

    func image(for url: URL, refreshToken: Date? = nil) async -> UIImage? {
        let request = Self.storageLock.withLock { makeRequest(for: url, refreshToken: refreshToken) }
        guard let request else { return nil }
        let stored = Self.storageLock.withLock { () -> UIImage? in
            guard makeRequest(for: url, refreshToken: refreshToken) == request,
                  let data = try? Data(contentsOf: request.destination) else { return nil }
            return UIImage(data: data)
        }
        if let stored { return stored }
        if let running = pending[request] { return await running.value }
        let task = Task { await self.generateAndStore(request) }
        pending[request] = task
        let image = await task.value
        pending[request] = nil
        return image
    }

    private func generateAndStore(_ request: Request) async -> UIImage? {
        guard let image = await generate(request.source), !Task.isCancelled else { return nil }
        return Self.storageLock.withLock {
            guard makeRequest(for: request.source, refreshToken: request.refreshToken) == request else { return nil }
            if let data = image.jpegData(compressionQuality: 0.82) {
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try data.write(to: request.destination, options: .atomic)
                    prune(keeping: request)
                } catch { return image }
            }
            return image
        }
    }

    private func makeRequest(for url: URL, refreshToken: Date?) -> Request? {
        var source = url
        source.removeAllCachedResourceValues()
        guard source.isFileURL,
              let values = try? source.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize, size > 0, let modifiedAt = values.contentModificationDate else { return nil }
        let sourceDirectory = url.deletingLastPathComponent().standardizedFileURL
        let prefix = Self.hash(sourceDirectory.path) + "_" + Self.hash(url.lastPathComponent)
        let version = Self.hash("v1|\(size)|\(modifiedAt.timeIntervalSince1970)|\(refreshToken?.timeIntervalSince1970.description ?? "-")")
        let destination = directory.appendingPathComponent("\(prefix)-\(version).jpg")
        let scope = Scope(cacheDirectory: directory.standardizedFileURL, sourceDirectory: sourceDirectory)
        return Request(source: url, refreshToken: refreshToken, modifiedAt: modifiedAt, size: size,
                       epoch: Self.epochs[scope], prefix: prefix, destination: destination)
    }

    nonisolated func removeImages(in sourceDirectory: URL) {
        Self.storageLock.withLock {
            let scope = Scope(cacheDirectory: directory.standardizedFileURL, sourceDirectory: sourceDirectory.standardizedFileURL)
            Self.epochs[scope] = UUID()
            let prefix = Self.hash(scope.sourceDirectory) + "_"
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.lastPathComponent.hasPrefix(prefix) { try? FileManager.default.removeItem(at: file) }
        }
    }

    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func prune(keeping request: Request) {
        let manager = FileManager.default
        let files = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where file.lastPathComponent.hasPrefix(request.prefix + "-") && file != request.destination {
            try? manager.removeItem(at: file)
        }
        let kept = files.filter {
            $0 != request.destination && manager.fileExists(atPath: $0.path) && $0.pathExtension == "jpg"
        }.sorted {
            ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
        for file in kept.dropFirst(limit - 1) { try? manager.removeItem(at: file) }
    }

    private static func generateImage(_ url: URL) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 600)
        guard let cgImage = try? await generator.image(at: CMTime(seconds: 0.1, preferredTimescale: 600)).image else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
