import Foundation
import Observation
import UIKit

/// My avatar, on this phone. Only the finished avatar is ever kept or sent
/// anywhere — the photo it was drawn from is dropped as soon as the confirm
/// screen closes, and never leaves the phone.
///
/// One file, overwritten on 「就是这样」: no history of earlier tries.
@MainActor
@Observable
final class AvatarStore {
    static let shared = AvatarStore()

    /// Nil until someone makes one (or after they skipped).
    private(set) var image: UIImage?
    /// Bumped on every save, so a sync can tell a new avatar from the old one.
    private(set) var version: Date?

    let fileURL: URL?

    init(fileURL: URL? = AvatarStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    /// The saved file, when there is one — what goes up as the `avatar` asset.
    var savedFileURL: URL? {
        guard image != nil, let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return fileURL
    }

    func save(pngData: Data) {
        guard let image = UIImage(data: pngData) else { return }
        if let fileURL {
            do {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try pngData.write(to: fileURL, options: .atomic)
            } catch {
                print("[avatar] save failed: \(error)")
            }
        }
        self.image = image
        version = .now
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    /// Account deletion and sign-out take the avatar with them.
    func remove() {
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        image = nil
        version = nil
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    static let didChange = Notification.Name("AvatarStore.didChange")

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) else { return }
        self.image = image
        version = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// My saved avatar file, if there is one. Readable off the main actor, for
    /// the invite card, which is rendered wherever the share sheet asks.
    nonisolated static var savedFileOnDisk: URL? {
        guard let url = defaultFileURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    nonisolated static var defaultFileURL: URL? {
        // Tests run in the app's container; keep them off the real file.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("avatar-tests-\(ProcessInfo.processInfo.processIdentifier)")
                .appendingPathComponent("me.png")
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Avatar", isDirectory: true)
            .appendingPathComponent("me.png")
    }
}

/// Friends' avatars, decoded once. A room page redraws every few seconds while
/// it syncs; decoding a PNG on every pass would be wasted work.
@MainActor
enum AvatarImageCache {
    private static var images: [URL: (UIImage, Date?)] = [:]

    static func image(at url: URL?) -> UIImage? {
        guard let url else { return nil }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let (image, at) = images[url], at == modified { return image }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        images[url] = (image, modified)
        return image
    }
}
