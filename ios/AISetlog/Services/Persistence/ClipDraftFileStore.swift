import Foundation

/// Disk boundary for draft clip files, under Documents/drafts/.
///
/// Deliberately separate from `ClipFileStore`, and deliberately throwing:
/// `storeClip` returns an optional and swallows the reason it failed, which is
/// tolerable when there's a story on screen to fall back to. A draft is the
/// last copy of something that isn't anywhere else yet, so a failure here has
/// to be loud enough to stop the flow and let the person try again.
protocol ClipDraftFileStore {
    /// Copy a freshly recorded clip out of the temp directory and into drafts.
    /// Returns the stored file name. Throws if the copy didn't happen.
    func storeDraft(from tempURL: URL, draftID: UUID) throws -> String
    func draftURL(fileName: String) -> URL
    func deleteDraft(fileName: String)
    /// Bytes on disk, or 0 when the file is missing.
    func byteSize(fileName: String) -> Int64
}

enum ClipDraftFileStoreError: Error, Equatable {
    /// The recorded file wasn't where the recorder said it was.
    case sourceMissing
    /// The copy itself failed — out of space, permissions, a stale temp file.
    case copyFailed(String)
}

final class DiskClipDraftFileStore: ClipDraftFileStore {
    private var draftsRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("drafts", isDirectory: true)
    }

    func storeDraft(from tempURL: URL, draftID: UUID) throws -> String {
        guard FileManager.default.fileExists(atPath: tempURL.path) else {
            throw ClipDraftFileStoreError.sourceMissing
        }
        let dir = draftsRoot
        let name = "\(draftID.uuidString).\(tempURL.pathExtension)"
        let dest = dir.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // A retried save shouldn't fail just because the first attempt got
            // halfway; the draft id is unique, so anything here is ours.
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: tempURL, to: dest)
        } catch {
            throw ClipDraftFileStoreError.copyFailed(error.localizedDescription)
        }
        return name
    }

    func draftURL(fileName: String) -> URL {
        draftsRoot.appendingPathComponent(fileName)
    }

    func deleteDraft(fileName: String) {
        try? FileManager.default.removeItem(at: draftURL(fileName: fileName))
    }

    func byteSize(fileName: String) -> Int64 {
        let values = try? draftURL(fileName: fileName)
            .resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }
}
