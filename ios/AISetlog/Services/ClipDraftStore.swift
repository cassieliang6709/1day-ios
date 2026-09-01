import Foundation
import Observation

/// Persistence boundary for draft metadata. Mirrors `ChallengeRepository`:
/// the store keeps drafts in memory, this owns reading and writing them.
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

/// Holds unfiled clips. Same shape as `ChallengeStore` — state in memory,
/// `didSet` writes it through — so there's one persistence pattern in the app
/// rather than two.
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

    /// Newest first — the clip someone just kept is the one they'll look for.
    var sortedDrafts: [ClipDraft] {
        drafts.sorted { $0.recordedAt > $1.recordedAt }
    }

    func url(for draft: ClipDraft) -> URL {
        fileStore.draftURL(fileName: draft.fileName)
    }

    /// Copy a recorded clip out of the temp directory and remember it.
    ///
    /// Throws rather than returning nil on purpose: the caller has to decide
    /// what to tell the person, because "we couldn't keep it" is the one
    /// outcome they must not learn about by finding the clip gone later.
    @discardableResult
    func keep(
        tempURL: URL,
        orientation: Challenge.Orientation,
        overlayText: String? = nil,
        recordedAt: Date = .now
    ) throws -> ClipDraft {
        let id = UUID()
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

    /// Forget a draft once it's been filed into a story, and take its file with
    /// it — a draft whose clip now lives in a story is just a duplicate.
    func remove(_ draft: ClipDraft) {
        fileStore.deleteDraft(fileName: draft.fileName)
        drafts.removeAll { $0.id == draft.id }
    }

    /// Total bytes drafts are holding, for the "this is what it costs" line.
    var totalByteSize: Int64 {
        drafts.reduce(0) { $0 + $1.byteSize }
    }
}
