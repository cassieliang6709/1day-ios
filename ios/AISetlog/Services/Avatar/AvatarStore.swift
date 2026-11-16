import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class AvatarStore {
    static let shared = AvatarStore()

    private(set) var image: UIImage?
    private(set) var version: Date?

    private(set) var history: [URL] = []

    let fileURL: URL?
    static let historyLimit = 12

    init(fileURL: URL? = AvatarStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    var savedFileURL: URL? {
        guard image != nil, let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return fileURL
    }

    func save(pngData: Data) {
        guard let image = UIImage(data: pngData) else { return }
        if let fileURL {
            keepInHistory(replacing: pngData)
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

    func restore(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        save(pngData: data)
    }

    func remove() {
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        if let historyDir { try? FileManager.default.removeItem(at: historyDir) }
        history = []
        image = nil
        version = nil
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    static let didChange = Notification.Name("AvatarStore.didChange")

    private var historyDir: URL? {
        fileURL?.deletingLastPathComponent().appendingPathComponent("history", isDirectory: true)
    }

    private func keepInHistory(replacing newData: Data) {
        let fm = FileManager.default
        guard let fileURL, let historyDir, let current = try? Data(contentsOf: fileURL),
              current != newData
        else { return }
        if !history.contains(where: { (try? Data(contentsOf: $0)) == current }) {
            try? fm.createDirectory(at: historyDir, withIntermediateDirectories: true)
            let name = "\(Int(Date.now.timeIntervalSince1970 * 1000)).png"
            try? current.write(to: historyDir.appendingPathComponent(name), options: .atomic)
        }
        for url in history where (try? Data(contentsOf: url)) == newData {
            try? fm.removeItem(at: url)
        }
        loadHistory()
        for url in history.dropFirst(Self.historyLimit) { try? fm.removeItem(at: url) }
        loadHistory()
    }

    private func loadHistory() {
        guard let historyDir,
              let names = try? FileManager.default.contentsOfDirectory(atPath: historyDir.path)
        else { history = []; return }
        history = names.filter { $0.hasSuffix(".png") }.sorted(by: >)
            .map { historyDir.appendingPathComponent($0) }
    }

    private func load() {
        loadHistory()
        guard let fileURL, let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) else { return }
        self.image = image
        version = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    nonisolated static var savedFileOnDisk: URL? {
        guard let url = defaultFileURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    nonisolated static var defaultFileURL: URL? {
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
