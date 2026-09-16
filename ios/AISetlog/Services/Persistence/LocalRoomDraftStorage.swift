#if DEBUG || LOCAL_ROOM_CHAT_DEMO
import Foundation

/// Reuses the preview's file owner; no Documents directory or defaults access.
final class LocalRoomDraftStorage: ClipDraftRepository, ClipDraftFileStore {
    private let files: LocalRoomDemoStorage
    private let namespace = UUID()
    private var drafts: [ClipDraft] = []

    init(files: LocalRoomDemoStorage) { self.files = files }

    func loadDrafts() -> [ClipDraft] { files.isClosed ? [] : drafts }
    func saveDrafts(_ drafts: [ClipDraft]) { if !files.isClosed { self.drafts = drafts } }

    func storeDraft(from tempURL: URL, draftID: UUID) throws -> String {
        guard let name = files.storeClip(from: tempURL, day: 1, challengeID: namespace) else {
            throw ClipDraftFileStoreError.copyFailed("Local preview is closed or the copy failed")
        }
        return name
    }

    func draftURL(fileName: String) -> URL { files.clipURL(fileName: fileName, challengeID: namespace) }
    func deleteDraft(fileName: String) { try? FileManager.default.removeItem(at: draftURL(fileName: fileName)) }
    func byteSize(fileName: String) -> Int64 {
        let values = try? draftURL(fileName: fileName).resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }
}
#endif
