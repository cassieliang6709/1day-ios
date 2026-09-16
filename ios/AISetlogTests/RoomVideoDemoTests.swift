import XCTest
import AVFoundation
@testable import AISetlog

@MainActor
final class RoomVideoDemoTests: XCTestCase {
    func testTwoAndThreeMembersProduceActualPortraitAndLandscapeFilms() async throws {
        let model = RoomVideoDemoModel()
        defer { model.close() }
        await model.prepare(count: 2, landscape: false, chinese: true)
        XCTAssertFalse(model.failed)
        XCTAssertEqual(model.clips.count, 3)
        XCTAssertEqual(Set(model.clips.compactMap(\.authorID)).count, 3)
        let portrait = try XCTUnwrap(model.film)
        let firstAsset = AVURLAsset(url: portrait)
        let firstDuration = try await firstAsset.load(.duration).seconds
        XCTAssertEqual(firstDuration, 3, accuracy: 0.2)
        let firstTracks = try await firstAsset.loadTracks(withMediaType: .video)
        let firstSize = try await XCTUnwrap(firstTracks.first).load(.naturalSize)
        XCTAssertGreaterThan(firstSize.height, firstSize.width)

        await model.prepare(count: 3, landscape: true, chinese: true)
        XCTAssertFalse(model.failed)
        let landscape = try XCTUnwrap(model.film)
        XCTAssertNotEqual(portrait, landscape)
        let nextAsset = AVURLAsset(url: landscape)
        let nextDuration = try await nextAsset.load(.duration).seconds
        XCTAssertEqual(nextDuration, 3, accuracy: 0.2)
        let tracks = try await nextAsset.loadTracks(withMediaType: .video)
        let size = try await XCTUnwrap(tracks.first).load(.naturalSize)
        XCTAssertGreaterThan(size.width, size.height)
        model.close()
        XCTAssertFalse(FileManager.default.fileExists(atPath: portrait.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: landscape.path))
    }

    func testImportedCopyReplacesOnlySelectedMemberAndIsCleanedUp() async throws {
        let model = RoomVideoDemoModel()
        defer { model.close() }
        await model.prepare(count: 2, landscape: false, chinese: false)
        let original = try XCTUnwrap(model.clips.first?.url)
        let unaffected = model.clips[1].url
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("import-test-\(UUID()).mov")
        try FileManager.default.copyItem(at: original, to: copy)
        await model.replace(index: 0, source: copy, count: 2, landscape: false, chinese: false)
        XCTAssertFalse(model.failed)
        XCTAssertNotEqual(model.clips[0].url, original)
        XCTAssertEqual(model.clips[1].url, unaffected)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
        let imported = model.clips[0].url
        model.close()
        XCTAssertFalse(FileManager.default.fileExists(atPath: imported.path))
    }

    func testClosedDemoDoesNotRegenerateMedia() async {
        let model = RoomVideoDemoModel()
        model.close()
        await model.prepare(count: 3, landscape: false, chinese: true)
        XCTAssertTrue(model.clips.isEmpty)
        XCTAssertNil(model.film)
    }
}
