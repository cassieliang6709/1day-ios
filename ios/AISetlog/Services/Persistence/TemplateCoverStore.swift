import Foundation

/// Disk boundary for template cover images, the same shape as `ClipFileStore`:
/// the store asks for file names and URLs and never touches FileManager itself.
protocol TemplateCoverStore {
    /// File a cover the user picked from their photo library. Returns the
    /// stored file name, or nil if the write failed — in which case the
    /// template keeps whatever cover it already had.
    @discardableResult
    func storeCover(_ imageData: Data, templateID: UUID) -> String?
    /// Nil when the file is gone, so a cover deleted out from under us falls
    /// back to matched artwork instead of leaving a hole in the card.
    func coverURL(fileName: String) -> URL?
    func deleteCover(fileName: String)
}

final class DiskTemplateCoverStore: TemplateCoverStore {
    private var coversRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("templateCovers", isDirectory: true)
    }

    @discardableResult
    func storeCover(_ imageData: Data, templateID: UUID) -> String? {
        let dir = coversRoot
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // A fresh name every time rather than overwriting: SwiftUI caches by
        // URL, so re-picking a cover under the same path would keep showing
        // the old picture. The caller deletes the one it replaced.
        let fileName = "\(templateID.uuidString)-\(UUID().uuidString.prefix(8)).coverimg"
        do {
            try imageData.write(to: dir.appendingPathComponent(fileName), options: .atomic)
            return fileName
        } catch {
            return nil
        }
    }

    func coverURL(fileName: String) -> URL? {
        let url = coversRoot.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func deleteCover(fileName: String) {
        try? FileManager.default.removeItem(at: coversRoot.appendingPathComponent(fileName))
    }
}
