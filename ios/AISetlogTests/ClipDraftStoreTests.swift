import XCTest
@testable import AISetlog

final class ClipDraftStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }


    func testKeepingADraftCopiesTheClipOutOfTemp() throws {
        let store = makeStore()
        let source = try makeTempClip(named: "rolled.mov", bytes: 512)

        let draft = try store.keep(tempURL: source, orientation: .portrait)

        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(draft.orientation, .portrait)
        XCTAssertNotEqual(store.url(for: draft), source)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: draft).path))
    }

    func testDraftRemembersItsSizeSoThePersonCanDecideWhatToDelete() throws {
        let store = makeStore()
        let source = try makeTempClip(named: "big.mov", bytes: 4096)

        let draft = try store.keep(tempURL: source, orientation: .landscape)

        XCTAssertEqual(draft.byteSize, 4096)
        XCTAssertEqual(store.totalByteSize, 4096)
    }

    func testOverlayTextSurvivesBeingKept() throws {
        let store = makeStore()
        let source = try makeTempClip(named: "captioned.mov", bytes: 64)

        let draft = try store.keep(
            tempURL: source, orientation: .portrait, overlayText: "傍晚的光")

        XCTAssertEqual(draft.overlayText, "傍晚的光")
    }


    func testKeepingThrowsWhenTheRecordedFileIsGone() {
        let store = makeStore()
        let missing = tempDir.appendingPathComponent("never-written.mov")

        XCTAssertThrowsError(try store.keep(tempURL: missing, orientation: .portrait)) { error in
            XCTAssertEqual(error as? ClipDraftFileStoreError, .sourceMissing)
        }
        XCTAssertTrue(store.isEmpty)
    }

    func testAFailedCopyLeavesNoDraftBehind() throws {
        let store = ClipDraftStore(
            repository: InMemoryDraftRepository(),
            fileStore: FailingDraftFileStore())
        let source = try makeTempClip(named: "doomed.mov", bytes: 32)

        XCTAssertThrowsError(try store.keep(tempURL: source, orientation: .portrait))
        XCTAssertTrue(store.isEmpty)
    }


    func testRemovingADraftTakesItsFileWithIt() throws {
        let store = makeStore()
        let source = try makeTempClip(named: "filed.mov", bytes: 128)
        let draft = try store.keep(tempURL: source, orientation: .portrait)
        let stored = store.url(for: draft)

        store.remove(draft)

        XCTAssertTrue(store.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stored.path))
    }


    func testDraftsComeBackAfterRelaunch() throws {
        let repository = InMemoryDraftRepository()
        let fileStore = DiskClipDraftFileStore()
        let first = ClipDraftStore(repository: repository, fileStore: fileStore)
        let source = try makeTempClip(named: "kept.mov", bytes: 256)
        let draft = try first.keep(tempURL: source, orientation: .landscape)
        defer { first.remove(draft) }

        let relaunched = ClipDraftStore(repository: repository, fileStore: fileStore)

        XCTAssertEqual(relaunched.count, 1)
        XCTAssertEqual(relaunched.drafts.first?.id, draft.id)
        XCTAssertEqual(relaunched.drafts.first?.orientation, .landscape)
    }

    func testNewestDraftComesFirst() throws {
        let store = makeStore()
        let older = try store.keep(
            tempURL: try makeTempClip(named: "a.mov", bytes: 16),
            orientation: .portrait,
            recordedAt: Date(timeIntervalSince1970: 1_000))
        let newer = try store.keep(
            tempURL: try makeTempClip(named: "b.mov", bytes: 16),
            orientation: .portrait,
            recordedAt: Date(timeIntervalSince1970: 9_000))
        defer { store.remove(older); store.remove(newer) }

        XCTAssertEqual(store.sortedDrafts.map(\.id), [newer.id, older.id])
    }


    private func makeStore() -> ClipDraftStore {
        ClipDraftStore(
            repository: InMemoryDraftRepository(),
            fileStore: TempRootDraftFileStore(root: tempDir.appendingPathComponent("drafts")))
    }

    private func makeTempClip(named name: String, bytes: Int) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try Data(repeating: 7, count: bytes).write(to: url)
        return url
    }


    func testOneClipFilesIntoSeveralStoriesAndLeavesTheSourceAlone() throws {
        let suiteName = "ClipDraftStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let fileStore = DiskClipFileStore()
        let store = ChallengeStore(
            repository: UserDefaultsChallengeRepository(
                defaults: defaults, fileStore: fileStore),
            fileStore: fileStore)

        let targets = ["Mine", "The room", "Third"].map {
            store.create(
                title: $0,
                mode: .oneDay,
                clipLength: .tiny,
                orientation: .portrait,
                templateName: nil,
                momentTitles: ["one", "two"])
        }
        defer { targets.forEach { fileStore.deleteClips(challengeID: $0.id) } }

        let source = try makeTempClip(named: "shared.mov", bytes: 256)

        for challenge in targets {
            let day = try XCTUnwrap(
                ClipFiling.targetDay(in: try XCTUnwrap(store.challenge(challenge.id))),
                "every fresh story has an open slot")
            store.saveClip(from: source, day: day, challengeID: challenge.id)
        }

        for challenge in targets {
            let saved = try XCTUnwrap(store.challenge(challenge.id))
            let filled = saved.cards.filter { $0.clipFileName != nil }
            XCTAssertEqual(
                filled.count, 1,
                "\(saved.title) should hold exactly the one clip it was filed")
            XCTAssertEqual(filled.first?.day, 1, "it lands in the first open slot")
        }

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: source.path),
            "filing copies; the take is still there to file again")
    }

    @MainActor
    func testFilingADraftKeepsTheDraftsTime() throws {
        let suiteName = "ClipDraftStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let fileStore = DiskClipFileStore()
        let store = ChallengeStore(
            repository: UserDefaultsChallengeRepository(
                defaults: defaults, fileStore: fileStore),
            fileStore: fileStore)
        let story = store.create(
            title: "Filed later",
            mode: .oneDay,
            clipLength: .tiny,
            orientation: .portrait,
            templateName: nil,
            momentTitles: ["one", "two"])
        defer { fileStore.deleteClips(challengeID: story.id) }

        let drafts = makeStore()
        let filmedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let draft = try drafts.keep(
            tempURL: try makeTempClip(named: "kept-earlier.mov", bytes: 64),
            orientation: .portrait,
            recordedAt: filmedAt)

        _ = DraftFiler.archive(
            draft, to: [try XCTUnwrap(store.challenge(story.id))],
            store: store, drafts: drafts)

        let card = try XCTUnwrap(store.challenge(story.id)?.cards.first { $0.day == 1 })
        XCTAssertNotNil(card.clipFileName, "the draft landed")
        XCTAssertEqual(card.recordedAt, filmedAt)
    }

    func testAFullStoryIsNotOfferedAsSomewhereToFileTo() throws {
        let suiteName = "ClipDraftStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let fileStore = DiskClipFileStore()
        let store = ChallengeStore(
            repository: UserDefaultsChallengeRepository(
                defaults: defaults, fileStore: fileStore),
            fileStore: fileStore)

        let challenge = store.create(
            title: "One slot only",
            mode: .oneDay,
            clipLength: .tiny,
            orientation: .portrait,
            templateName: nil,
            momentTitles: ["only"])
        defer { fileStore.deleteClips(challengeID: challenge.id) }

        let source = try makeTempClip(named: "fills-it.mov", bytes: 128)
        store.saveClip(from: source, day: 1, challengeID: challenge.id)

        let full = try XCTUnwrap(store.challenge(challenge.id))
        XCTAssertNil(ClipFiling.targetDay(in: full))
        XCTAssertTrue(
            ClipFiling.candidates(in: [full], orientation: .portrait).isEmpty,
            "a full story is not somewhere a clip can go")
    }

    @MainActor
    func testARoomIsNeverFullASecondClipIsAnotherTake() throws {
        let suiteName = "ClipDraftStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let fileStore = DiskClipFileStore()
        let store = ChallengeStore(
            repository: UserDefaultsChallengeRepository(defaults: defaults, fileStore: fileStore),
            fileStore: fileStore, effects: .isolated)
        let room = Challenge(id: UUID(), title: "房间", startDate: .now, cards: [DayCard(day: 1)],
                             roomCode: "ABCDEF", ownerName: "Leo", ownerID: "owner-1")
        store.challenges = [room]
        defer { fileStore.deleteClips(challengeID: room.id) }

        XCTAssertTrue(store.sendToRoom(from: try makeTempClip(named: "a.mov", bytes: 64), roomID: room.id))
        XCTAssertTrue(store.sendToRoom(from: try makeTempClip(named: "b.mov", bytes: 64), roomID: room.id))

        let card = try XCTUnwrap(store.challenge(room.id)?.cards.first)
        XCTAssertNotNil(card.clipFileName)
        XCTAssertEqual(card.moreTakes.count, 1, "the second clip is a second take, not an overwrite")
        XCTAssertEqual(ClipFiling.rooms(in: store.challenges, orientation: .portrait).map(\.id), [room.id])
    }
}


private final class InMemoryDraftRepository: ClipDraftRepository {
    private var stored: [ClipDraft] = []
    func loadDrafts() -> [ClipDraft] { stored }
    func saveDrafts(_ drafts: [ClipDraft]) { stored = drafts }
}

private final class TempRootDraftFileStore: ClipDraftFileStore {
    private let root: URL

    init(root: URL) { self.root = root }

    func storeDraft(from tempURL: URL, draftID: UUID) throws -> String {
        guard FileManager.default.fileExists(atPath: tempURL.path) else {
            throw ClipDraftFileStoreError.sourceMissing
        }
        let name = "\(draftID.uuidString).\(tempURL.pathExtension)"
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: tempURL, to: root.appendingPathComponent(name))
        } catch {
            throw ClipDraftFileStoreError.copyFailed(error.localizedDescription)
        }
        return name
    }

    func draftURL(fileName: String) -> URL { root.appendingPathComponent(fileName) }

    func deleteDraft(fileName: String) {
        try? FileManager.default.removeItem(at: draftURL(fileName: fileName))
    }

    func byteSize(fileName: String) -> Int64 {
        let values = try? draftURL(fileName: fileName).resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }
}

private final class FailingDraftFileStore: ClipDraftFileStore {
    func storeDraft(from tempURL: URL, draftID: UUID) throws -> String {
        throw ClipDraftFileStoreError.copyFailed("no space left on device")
    }
    func draftURL(fileName: String) -> URL { URL(fileURLWithPath: "/dev/null") }
    func deleteDraft(fileName: String) {}
    func byteSize(fileName: String) -> Int64 { 0 }
}
