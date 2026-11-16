import Foundation

protocol ClipDraftFileStore {
    func storeDraft(from tempURL: URL, draftID: UUID) throws -> String
    func draftURL(fileName: String) -> URL
    func deleteDraft(fileName: String)
    func byteSize(fileName: String) -> Int64
}

enum ClipDraftFileStoreError: Error, Equatable {
    case sourceMissing
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
