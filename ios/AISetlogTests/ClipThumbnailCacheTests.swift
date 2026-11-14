import XCTest
@testable import AISetlog

/// First-frame stills must survive a view being torn down and built again
/// (flipping 我的 to the calendar and back, leaving a room and opening it)
/// without reopening the video. Re-records reuse the file name, so a new
/// `recordedAt` has to miss.
final class ClipThumbnailCacheTests: XCTestCase {
    private var urls: [URL] = []

    override func setUp() {
        super.setUp()
        ClipThumbnailCache.removeAll()
    }

    override func tearDown() {
        ClipThumbnailCache.removeAll()
        for url in urls { try? FileManager.default.removeItem(at: url) }
        urls = []
        super.tearDown()
    }

    private func makeClip(index: Int = 0) async throws -> URL {
        let made = await ClipFixtureFactory.makeClip(index: index)
        let url = try XCTUnwrap(made)
        urls.append(url)
        return url
    }

    func testMissThenHitReturnsTheSameImage() async throws {
        let url = try await makeClip()
        let token = Date(timeIntervalSince1970: 1_000)

        XCTAssertNil(ClipThumbnailCache.imageIfCached(url: url, refreshToken: token))

        let loaded = await ClipThumbnailCache.image(url: url, refreshToken: token)
        let first = try XCTUnwrap(loaded)
        let cached = try XCTUnwrap(ClipThumbnailCache.imageIfCached(url: url, refreshToken: token))
        XCTAssertTrue(first === cached)

        let reloaded = await ClipThumbnailCache.image(url: url, refreshToken: token)
        let second = try XCTUnwrap(reloaded)
        XCTAssertTrue(first === second)
    }

    func testRefreshTokenBustsTheCache() async throws {
        let url = try await makeClip()
        let firstTake = Date(timeIntervalSince1970: 1)
        let rerecorded = Date(timeIntervalSince1970: 2)

        let loaded = await ClipThumbnailCache.image(url: url, refreshToken: firstTake)
        _ = try XCTUnwrap(loaded)
        XCTAssertNotNil(ClipThumbnailCache.imageIfCached(url: url, refreshToken: firstTake))
        XCTAssertNil(ClipThumbnailCache.imageIfCached(url: url, refreshToken: rerecorded))
    }

    func testMaxSizeAndTimeArePartOfTheKey() async throws {
        let url = try await makeClip()
        let token = Date(timeIntervalSince1970: 1_000)
        let preview = ClipThumbnailCache.defaultMaxSize

        let loaded = await ClipThumbnailCache.image(
            url: url, refreshToken: token, maxSize: preview)
        _ = try XCTUnwrap(loaded)
        XCTAssertNotNil(ClipThumbnailCache.imageIfCached(
            url: url, refreshToken: token, maxSize: preview))
        XCTAssertNil(ClipThumbnailCache.imageIfCached(
            url: url, refreshToken: token, maxSize: CGSize(width: 300, height: 300)))
        XCTAssertNil(ClipThumbnailCache.imageIfCached(
            url: url, refreshToken: token, seconds: 1, maxSize: preview))
    }

    func testMissingFileReturnsNil() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip-thumb-missing-\(UUID().uuidString).mov")
        let image = await ClipThumbnailCache.image(url: url, refreshToken: nil)
        XCTAssertNil(image)
        XCTAssertNil(ClipThumbnailCache.imageIfCached(url: url, refreshToken: nil))
    }
}
