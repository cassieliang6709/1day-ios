import UIKit
import XCTest
@testable import AISetlog

@MainActor
final class ClipThumbnailCacheTests: XCTestCase {
    private var root: URL!
    private var thumbnailDirectory: URL { root.appendingPathComponent("cache") }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("thumbnail-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        root = nil
        super.tearDown()
    }

    private func source(_ name: String = "clip.mov") throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: url)
        return url
    }

    private var image: UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 24, height: 16)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 16))
        }
    }

    func testRealVideoThumbnailSurvivesNewCacheInstanceWithoutRegeneration() async throws {
        let generated = await ClipFixtureFactory.makeClip(index: 1)
        let fixture = try XCTUnwrap(generated)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let url = root.appendingPathComponent("video.mov")
        try FileManager.default.copyItem(at: fixture, to: url)
        let first = await ClipThumbnailCache(directory: thumbnailDirectory).image(for: url)
        let thumbnail = try XCTUnwrap(first)
        XCTAssertGreaterThan(thumbnail.size.height, thumbnail.size.width)
        XCTAssertLessThanOrEqual(max(thumbnail.size.width, thumbnail.size.height), 600)
        let reopened = ClipThumbnailCache(directory: thumbnailDirectory, generate: { _ in XCTFail("A persisted thumbnail must not decode the video again"); return nil })
        let restored = await reopened.image(for: url)
        XCTAssertEqual(restored?.size, thumbnail.size)
    }

    func testConcurrentRequestsGenerateOnlyOnce() async throws {
        let url = try source()
        let probe = ThumbnailProbe(image: image)
        let cache = ClipThumbnailCache(directory: thumbnailDirectory, generate: { await probe.generate($0) })
        async let first = cache.image(for: url)
        async let second = cache.image(for: url)
        let images = await [first, second]
        XCTAssertTrue(images.allSatisfy { $0 != nil })
        let calls = await probe.calls
        XCTAssertEqual(calls, 1)
    }

    func testReplacingSamePathInvalidatesAndRemovesOldThumbnail() async throws {
        let url = try source()
        let probe = ThumbnailProbe(image: image)
        let cache = ClipThumbnailCache(directory: thumbnailDirectory, generate: { await probe.generate($0) })
        _ = await cache.image(for: url)
        try Data([4, 5, 6, 7]).write(to: url, options: .atomic)
        _ = await cache.image(for: url)
        let calls = await probe.calls
        XCTAssertEqual(calls, 2)
        let files = try FileManager.default.contentsOfDirectory(atPath: thumbnailDirectory.path)
        XCTAssertEqual(files.count, 1)
    }

    func testRefreshTokenAlsoInvalidatesAndCacheHasABoundedSize() async throws {
        let probe = ThumbnailProbe(image: image)
        let cache = ClipThumbnailCache(directory: thumbnailDirectory, limit: 2, generate: { await probe.generate($0) })
        let url = try source()
        _ = await cache.image(for: url, refreshToken: Date(timeIntervalSince1970: 1))
        _ = await cache.image(for: url, refreshToken: Date(timeIntervalSince1970: 2))
        for index in 0..<3 { _ = await cache.image(for: try source("room-\(index)/clip.mov")) }
        let calls = await probe.calls
        XCTAssertEqual(calls, 5)
        let files = try FileManager.default.contentsOfDirectory(atPath: thumbnailDirectory.path)
        XCTAssertLessThanOrEqual(files.count, 2)
    }

    func testCorruptThumbnailRegeneratesAndMissingVideoDoesNotReturnStaleImage() async throws {
        let url = try source()
        let probe = ThumbnailProbe(image: image)
        let cache = ClipThumbnailCache(directory: thumbnailDirectory, generate: { await probe.generate($0) })
        _ = await cache.image(for: url)
        let directory = thumbnailDirectory
        let thumbnail = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        try Data("broken".utf8).write(to: thumbnail)
        let regenerated = await cache.image(for: url)
        XCTAssertNotNil(regenerated)
        let calls = await probe.calls
        XCTAssertEqual(calls, 2)
        try FileManager.default.removeItem(at: url)
        let missing = await cache.image(for: url)
        XCTAssertNil(missing)
    }

    func testInFlightGenerationDoesNotResurrectDeletedRoom() async throws {
        let url = try source()
        let probe = ThumbnailProbe(image: image)
        let cache = ClipThumbnailCache(directory: thumbnailDirectory, generate: { await probe.generate($0) })
        let request = Task { await cache.image(for: url) }
        while await probe.calls == 0 { await Task.yield() }
        try FileManager.default.removeItem(at: root)
        let result = await request.value
        XCTAssertNil(result)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testRemovingOneRoomsImagesDoesNotEvictAnotherRoom() async throws {
        let first = try source("room-a/clip.mov")
        let second = try source("room-b/clip.mov")
        let probe = ThumbnailProbe(image: image)
        let cache = ClipThumbnailCache(directory: thumbnailDirectory, generate: { await probe.generate($0) })
        _ = await cache.image(for: first)
        _ = await cache.image(for: second)
        cache.removeImages(in: first.deletingLastPathComponent())
        let reopened = ClipThumbnailCache(directory: thumbnailDirectory, generate: { _ in
            XCTFail("Another room's persisted thumbnail must remain available")
            return nil
        })
        let retained = await reopened.image(for: second)
        XCTAssertNotNil(retained)
        _ = await cache.image(for: first)
        let calls = await probe.calls
        XCTAssertEqual(calls, 3)
    }

    func testSynchronousInvalidationRejectsLateGenerationAndAllowsImmediateReuse() async throws {
        let url = try source()
        let probe = ThumbnailProbe(image: image)
        let cache = ClipThumbnailCache(directory: thumbnailDirectory, generate: { await probe.generate($0) })
        let old = Task { await cache.image(for: url) }
        while await probe.calls == 0 { await Task.yield() }
        cache.removeImages(in: url.deletingLastPathComponent())
        let refreshed = await cache.image(for: url)
        let discarded = await old.value
        XCTAssertNil(discarded)
        XCTAssertNotNil(refreshed)
        let calls = await probe.calls
        XCTAssertEqual(calls, 2)
    }

    func testProductionRoomAndStoryDeletionRemoveThumbnailsBeforeReturning() async throws {
        let files = DiskClipFileStore()
        let code = "thumbnail-test-\(UUID())"
        let storyID = UUID()
        let sync = RoomSyncService(fileStore: files)
        let roomDirectory = files.remoteCacheDir(roomCode: code)
        let storyDirectory = files.clipURL(fileName: "clip.mov", challengeID: storyID).deletingLastPathComponent()
        let scopes: [(URL, () -> Void)] = [
            (roomDirectory, { sync.clearRoom(code) }),
            (storyDirectory, { files.deleteClips(challengeID: storyID) }),
        ]
        let thumbnail = image
        let cache = ClipThumbnailCache(generate: { _ in thumbnail })
        func cachedFiles() -> Set<URL> {
            Set((try? FileManager.default.contentsOfDirectory(
                at: ClipThumbnailCache.defaultDirectory, includingPropertiesForKeys: nil)) ?? [])
        }
        for (directory, cleanup) in scopes {
            defer { cleanup() }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("clip.mov")
            try Data([1, 2, 3]).write(to: url)
            let before = cachedFiles()
            let generated = await cache.image(for: url)
            XCTAssertNotNil(generated)
            let added = cachedFiles().subtracting(before)
            XCTAssertEqual(added.count, 1)
            cleanup()
            XCTAssertTrue(cachedFiles().isDisjoint(with: added))
        }
    }
}

private actor ThumbnailProbe {
    private(set) var calls = 0
    let image: UIImage
    init(image: UIImage) { self.image = image }
    func generate(_ url: URL) async -> UIImage? {
        calls += 1
        try? await Task.sleep(for: .milliseconds(30))
        return image
    }
}
