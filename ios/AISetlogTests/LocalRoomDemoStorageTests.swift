import XCTest
@testable import AISetlog

final class LocalRoomDemoStorageTests: XCTestCase {
    func testSessionsKeepIndependentMemoryAndFilesWithoutChangingOriginal() throws {
        let a = try LocalRoomDemoStorage()
        let b = try LocalRoomDemoStorage()
        defer { a.close(); b.close() }
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("demo-storage-test-\(UUID()).mov")
        let bytes = Data("fixture bytes, not a playable video".utf8)
        try bytes.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let challenge = Challenge(id: UUID(), title: "Demo", startDate: .now, cards: [DayCard(day: 1)])
        a.saveChallenges([challenge])
        XCTAssertEqual(a.loadChallenges().count, 1)
        XCTAssertTrue(b.loadChallenges().isEmpty)
        let name = try XCTUnwrap(a.storeClip(from: source, day: 1, challengeID: challenge.id))
        let copy = a.clipURL(fileName: name, challengeID: challenge.id)
        XCTAssertEqual(try Data(contentsOf: copy), bytes)
        a.close()
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.root.path))
    }

    func testClosedStorageDoesNotRecreateFilesOrMemory() throws {
        let storage = try LocalRoomDemoStorage()
        storage.close()
        storage.saveChallenges([Challenge(id: UUID(), title: "Late", startDate: .now, cards: [])])
        XCTAssertTrue(storage.loadChallenges().isEmpty)
        XCTAssertNil(storage.storeCover(Data([1, 2, 3]), templateID: UUID()))
        XCTAssertNil(storage.storeClip(from: URL(fileURLWithPath: "/missing.mov"), day: 1, challengeID: UUID()))
        storage.close()
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.root.path))
    }

    func testUntrustedNamesStayInsidePrivateDirectory() throws {
        let storage = try LocalRoomDemoStorage()
        defer { storage.close() }
        for name in ["../outside", "/absolute/path", "..", "LOCAL-DEMO"] {
            for url in [storage.remoteCacheDir(roomCode: name),
                        storage.clipURL(fileName: name, challengeID: UUID())] {
                XCTAssertTrue(url.standardizedFileURL.path.hasPrefix(storage.root.standardizedFileURL.path + "/"))
            }
        }
        let cover = try XCTUnwrap(storage.storeCover(Data([1, 2, 3]), templateID: UUID()))
        XCTAssertNotNil(storage.coverURL(fileName: cover))
        storage.deleteCover(fileName: cover)
        XCTAssertNil(storage.coverURL(fileName: cover))
    }
}
