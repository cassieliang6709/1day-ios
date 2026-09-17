import XCTest

@testable import AISetlog

/// A story's own cover: what wins, what gets deleted, and what a story saved
/// before covers existed still looks like.
@MainActor
final class StoryCoverTests: XCTestCase {
    private var covers: MemoryCoverStore!
    private var store: ChallengeStore!
    private var challengeID: UUID!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        covers = MemoryCoverStore()
        suiteName = "StoryCoverTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        store = ChallengeStore(
            repository: UserDefaultsChallengeRepository(
                defaults: defaults, fileStore: NoFilesClipStore()),
            fileStore: NoFilesClipStore(),
            coverStore: covers,
            effects: .isolated)
        challengeID = store.create(
            title: "搬家这一天", mode: .oneDay, clipLength: .tiny,
            orientation: .portrait, templateName: nil,
            momentTitles: ["第一个箱子", "路上", "新家第一眼"]).id
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private var challenge: Challenge {
        store.challenge(challengeID)!
    }

    private var clip: URL { URL(fileURLWithPath: "/tmp/newest.mov") }

    // MARK: - What a story without a chosen cover shows

    func testWithoutAChoiceTheNewestClipIsStillTheCover() {
        XCTAssertEqual(
            store.storyCoverURL(for: challenge, latestClipURL: clip), clip,
            "the behaviour every story saved before this has")
    }

    func testWithoutAChoiceAndWithoutClipsThereIsNoPicture() {
        XCTAssertNil(store.storyCoverURL(for: challenge, latestClipURL: nil))
        // …and the card falls back to artwork, which the presenter picks.
        XCTAssertFalse(ChallengePresenter(challenge: challenge).coverAssetName.isEmpty)
    }

    // MARK: - A picked picture

    func testAPickedPictureOutranksTheNewestClip() throws {
        store.setStoryCover(.picked(Data([1, 2, 3])), for: challengeID)
        let url = try XCTUnwrap(store.storyCoverURL(for: challenge, latestClipURL: clip))
        XCTAssertNotEqual(url, clip)
        XCTAssertEqual(covers.written.count, 1)
    }

    func testReplacingAPictureDeletesTheOneItReplaced() throws {
        store.setStoryCover(.picked(Data([1])), for: challengeID)
        let first = try XCTUnwrap(challenge.coverFileName)
        store.setStoryCover(.picked(Data([2])), for: challengeID)
        XCTAssertEqual(covers.deleted, [first])
        XCTAssertNotEqual(challenge.coverFileName, first)
    }

    /// A write that fails must not blank the cover the story already had.
    func testAFailedWriteLeavesTheOldCoverAlone() throws {
        store.setStoryCover(.picked(Data([1])), for: challengeID)
        let kept = try XCTUnwrap(challenge.coverFileName)
        covers.failsWrites = true
        store.setStoryCover(.picked(Data([2])), for: challengeID)
        XCTAssertEqual(challenge.coverFileName, kept)
        XCTAssertTrue(covers.deleted.isEmpty)
    }

    // MARK: - A bundled scene

    func testABundledSceneIsDrawnByNameAndHasNoFile() {
        store.setStoryCover(.preset("PresetCoverCity"), for: challengeID)
        XCTAssertEqual(challenge.presetCoverAssetName, "PresetCoverCity")
        XCTAssertNil(challenge.coverFileName)
        // No URL on purpose: it's artwork the app ships, so the card draws it
        // by name rather than through a file. A clip must not slip back in.
        XCTAssertNil(store.storyCoverURL(for: challenge, latestClipURL: clip))
        XCTAssertEqual(
            ChallengePresenter(challenge: challenge).coverAssetName, "PresetCoverCity")
    }

    func testPickingASceneAfterAPictureDeletesThePicture() throws {
        store.setStoryCover(.picked(Data([1])), for: challengeID)
        let file = try XCTUnwrap(challenge.coverFileName)
        store.setStoryCover(.preset("PresetCoverFood"), for: challengeID)
        XCTAssertNil(challenge.coverFileName)
        XCTAssertEqual(covers.deleted, [file])
    }

    // MARK: - Back to automatic

    func testKeepFilmingClearsBothAndGoesBackToTheNewestClip() throws {
        store.setStoryCover(.picked(Data([1])), for: challengeID)
        let file = try XCTUnwrap(challenge.coverFileName)
        store.setStoryCover(.keepFilming, for: challengeID)
        XCTAssertNil(challenge.coverFileName)
        XCTAssertNil(challenge.presetCoverAssetName)
        XCTAssertEqual(covers.deleted, [file])
        XCTAssertEqual(store.storyCoverURL(for: challenge, latestClipURL: clip), clip)
    }

    func testSettingACoverOnAStoryThatIsNotThereDoesNothing() {
        store.setStoryCover(.picked(Data([1])), for: UUID())
        XCTAssertTrue(covers.written.isEmpty)
        XCTAssertNil(challenge.coverFileName)
    }

    // MARK: - Old saved data

    /// Two keys added to a model that decodes with synthesised `Codable`: a
    /// story saved before them has neither, and has to come back unchanged.
    func testAStorySavedBeforeCoversExistedStillDecodes() throws {
        let json = """
        {"id":"\(UUID().uuidString)","title":"旧故事",
         "startDate":0,"cards":[],"mode":"oneDay"}
        """
        let decoded = try JSONDecoder().decode(Challenge.self, from: Data(json.utf8))
        XCTAssertNil(decoded.coverFileName)
        XCTAssertNil(decoded.presetCoverAssetName)
        XCTAssertEqual(decoded.title, "旧故事")
    }
}

// MARK: - Doubles

/// Stories in these tests never have real files behind them: the cover rules
/// are about which *choice* wins, and a clip URL is handed in by the caller.
private struct NoFilesClipStore: ClipFileStore {
    func storeClip(from tempURL: URL, day: Int, challengeID: UUID) -> String? { nil }
    func clipURL(fileName: String, challengeID: UUID) -> URL {
        URL(fileURLWithPath: "/dev/null")
    }
    func deleteClips(challengeID: UUID) {}
    func remoteCacheDir(roomCode: String) -> URL { URL(fileURLWithPath: "/dev/null") }
    func deleteRemoteCache(roomCode: String) {}
    func migrateLegacyClips(_ fileNames: [String], into challengeID: UUID) {}
}

private final class MemoryCoverStore: TemplateCoverStore {
    private(set) var written: [String: Data] = [:]
    private(set) var deleted: [String] = []
    var failsWrites = false

    func storeCover(_ imageData: Data, ownerID: UUID) -> String? {
        guard !failsWrites else { return nil }
        let fileName = "\(ownerID.uuidString)-\(written.count).coverimg"
        written[fileName] = imageData
        return fileName
    }

    func coverURL(fileName: String) -> URL? {
        guard written[fileName] != nil else { return nil }
        return URL(fileURLWithPath: "/tmp/covers").appendingPathComponent(fileName)
    }

    func deleteCover(fileName: String) {
        deleted.append(fileName)
        written[fileName] = nil
    }
}
