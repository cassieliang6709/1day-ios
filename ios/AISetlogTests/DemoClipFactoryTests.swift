import XCTest
import AVFoundation
@testable import AISetlog

/// The recorder's simulator escape hatch is the only way to get footage into a
/// shared room without a camera, so it has to produce something decodable —
/// and something that visibly differs per author, or a stitched film can't
/// show whose clip is whose.
final class DemoClipFactoryTests: XCTestCase {
    private func makeClip(author: String, moment: Int = 1) async throws -> URL {
        let url = await DemoClipFactory.makeClip(
            moment: moment, label: "Wake up", author: author,
            seconds: 2, orientation: .portrait)
        return try XCTUnwrap(url)
    }

    func testProducesADecodableClipOfTheRequestedLength() async throws {
        let url = try await makeClip(author: "1DAY-B")
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)

        let duration = try await asset.load(.duration).seconds
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(duration, 2, accuracy: 0.1)
        XCTAssertEqual(size, CGSize(width: 540, height: 960))
    }

    func testTwoAuthorsGetVisiblyDifferentFootage() async throws {
        let mine = try await makeClip(author: "iPhone 17 Pro Max")
        let theirs = try await makeClip(author: "1DAY-B")
        let minePixels = try await firstFramePixels(mine)
        let theirPixels = try await firstFramePixels(theirs)
        XCTAssertNotEqual(minePixels, theirPixels)
    }

    func testLandscapeRoomsGetLandscapeFootage() async throws {
        let made = await DemoClipFactory.makeClip(
            moment: 1, label: "Wake up", author: "1DAY-B",
            seconds: 2, orientation: .landscape)
        let url = try XCTUnwrap(made)
        let tracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .video)
        let size = try await XCTUnwrap(tracks.first).load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 960, height: 540))
    }

    private func firstFramePixels(_ url: URL) async throws -> Data {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        let image = try await generator.image(at: .zero).image
        let data = image.dataProvider?.data as Data?
        return try XCTUnwrap(data)
    }
}
