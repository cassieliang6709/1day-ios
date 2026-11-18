import Foundation
import Observation

protocol ClipDraftRepository {
    func loadDrafts() -> [ClipDraft]
    func saveDrafts(_ drafts: [ClipDraft])
}

final class UserDefaultsClipDraftRepository: ClipDraftRepository {
    static let defaultsKey = "clipDrafts.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadDrafts() -> [ClipDraft] {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let saved = try? JSONDecoder().decode([ClipDraft].self, from: data)
        else { return [] }
        return saved
    }

    func saveDrafts(_ drafts: [ClipDraft]) {
        if let data = try? JSONEncoder().encode(drafts) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}

@Observable
final class ClipDraftStore {
    private(set) var drafts: [ClipDraft] = [] {
        didSet { repository.saveDrafts(drafts) }
    }

    private let repository: ClipDraftRepository
    private let fileStore: ClipDraftFileStore

    init(
        repository: ClipDraftRepository = UserDefaultsClipDraftRepository(),
        fileStore: ClipDraftFileStore = DiskClipDraftFileStore()
    ) {
        self.repository = repository
        self.fileStore = fileStore
        drafts = repository.loadDrafts()
    }

    var isEmpty: Bool { drafts.isEmpty }
    var count: Int { drafts.count }

    var sortedDrafts: [ClipDraft] {
        drafts.sorted { $0.recordedAt > $1.recordedAt }
    }

    func url(for draft: ClipDraft) -> URL {
        fileStore.draftURL(fileName: draft.fileName)
    }

    @discardableResult
    func keep(
        tempURL: URL,
        orientation: Challenge.Orientation,
        overlayText: String? = nil,
        recordedAt: Date = .now,
        id: UUID = UUID()
    ) throws -> ClipDraft {
        if let existing = drafts.first(where: { $0.id == id }) { return existing }
        let fileName = try fileStore.storeDraft(from: tempURL, draftID: id)
        let draft = ClipDraft(
            id: id,
            fileName: fileName,
            recordedAt: recordedAt,
            orientation: orientation,
            overlayText: overlayText,
            byteSize: fileStore.byteSize(fileName: fileName))
        drafts.append(draft)
        return draft
    }

    func remove(_ draft: ClipDraft) {
        fileStore.deleteDraft(fileName: draft.fileName)
        drafts.removeAll { $0.id == draft.id }
    }

    func updateOverlayText(_ text: String?, draftID: UUID) {
        guard let i = drafts.firstIndex(where: { $0.id == draftID }) else { return }
        drafts[i].overlayText = text
    }

    func updateCaptions(_ captions: [Caption], draftID: UUID) {
        guard let i = drafts.firstIndex(where: { $0.id == draftID }) else { return }
        drafts[i].captions = captions.drawable
    }

    var totalByteSize: Int64 {
        drafts.reduce(0) { $0 + $1.byteSize }
    }
}
