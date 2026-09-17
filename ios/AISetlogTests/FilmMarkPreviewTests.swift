import AVFoundation
import UIKit
import XCTest

@testable import AISetlog

/// The mascot on the opening card and in the corner of every frame.
///
/// These are the layers the exporter builds, drawn into a bitmap here. The
/// export path that shows them is device-only — `AVVideoCompositionCoreAnimationTool`
/// takes the simulator's software renderer down with it — so this is the only
/// place the mark can be both asserted *and* looked at without a phone.
final class FilmMarkPreviewTests: XCTestCase {
    private let renderSize = CGSize(width: 720, height: 1280)

    /// Where the pictures land, for a human to open. Not an assertion — the
    /// assertions are below; this is so "let me see it" doesn't need a device.
    private var outputDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("1day-film-marks", isDirectory: true)
    }

    private func container(_ background: UIColor) -> CALayer {
        let layer = CALayer()
        layer.frame = CGRect(origin: .zero, size: renderSize)
        layer.backgroundColor = background.cgColor
        return layer
    }

    private func write(_ layer: CALayer, named name: String) throws -> URL {
        try FileManager.default.createDirectory(
            at: outputDirectory, withIntermediateDirectories: true)
        prepareForStill(layer)
        let renderer = UIGraphicsImageRenderer(size: renderSize)
        let image = renderer.image { context in
            // `render(in:)` rather than the presentation tree: these layers are
            // never added to a window, and their animations are what the
            // exporter drives, not what a still needs.
            layer.render(in: context.cgContext)
        }
        let url = outputDirectory.appendingPathComponent("\(name).png")
        try XCTUnwrap(image.pngData()).write(to: url)
        return url
    }

    /// Two differences between "the layers the exporter builds" and "a picture
    /// a person can look at", both of them the preview's problem and not the
    /// exporter's:
    ///
    /// 1. The title card's layers start at `opacity = 0` and are faded in by a
    ///    keyframe animation that only `AVVideoCompositionCoreAnimationTool`
    ///    drives. A still of the un-animated tree is a black frame. This shows
    ///    them mid-window, which is what a viewer sees for ~1.5s of the 2.2.
    /// 2. AVFoundation's overlay tree has its origin at the *bottom* left;
    ///    `CALayer.render(in:)` into a UIKit context has it at the top. Without
    ///    flipping each frame, the corner mark that sits at the bottom of the
    ///    exported film appears at the top of this PNG.
    /// What this still cannot settle: which way up the mascot comes out. Image
    /// `contents` drawn by `CALayer.render(in:)` into a UIKit context are
    /// inverted relative to Core Graphics, and the export tree is neither of
    /// those two contexts — so a flip here proves nothing about the film. The
    /// layout, size and position below are what these tests pin; the mascot's
    /// orientation is confirmed by exporting one film on a device, and costs
    /// `CATransform3DMakeScale(1, -1, 1)` on the layer if it is wrong.
    private func prepareForStill(_ layer: CALayer) {
        for sublayer in layer.sublayers ?? [] {
            sublayer.opacity = 1
            sublayer.frame.origin.y =
                renderSize.height - sublayer.frame.origin.y - sublayer.frame.height
        }
    }

    // MARK: - The opening card

    func testTheOpeningCardCarriesTheMascotAboveTheTitle() throws {
        let layer = container(UIColor(hex: 0x101828))
        VideoStitcher.addTitleCard(
            .init(title: "搬家这一天", subtitle: "9月17日 · 3 个瞬间 · 每段 2 秒"),
            to: layer, renderSize: renderSize, duration: 2.2)

        // Two text layers and one image layer: title, subtitle, mascot.
        let images = layer.sublayers?.filter { $0.contents != nil && !($0 is CATextLayer) } ?? []
        XCTAssertEqual(images.count, 1, "the mascot should be the only picture on the card")
        let mark = try XCTUnwrap(images.first)
        XCTAssertEqual(mark.frame.midX, renderSize.width / 2, accuracy: 1)
        XCTAssertGreaterThan(
            mark.frame.minY, renderSize.height * 0.52,
            "above the title, which sits at 52%")
        XCTAssertEqual(
            mark.frame.width, renderSize.height * 0.115, accuracy: 1)

        let url = try write(layer, named: "title-card")
        print("[film-mark] opening card → \(url.path)")
    }

    // MARK: - The corner mark

    func testTheCornerMarkIsAMascotAndOneWord() throws {
        let layer = container(UIColor(hex: 0x2A3F63))
        VideoStitcher.addWatermark(to: layer, renderSize: renderSize)

        let sublayers = layer.sublayers ?? []
        let text = sublayers.compactMap { $0 as? CATextLayer }
        let images = sublayers.filter { $0.contents != nil && !($0 is CATextLayer) }
        XCTAssertEqual(images.count, 1, "the mascot")
        XCTAssertEqual(text.count, 1, "one word beside it")

        // "made with 1Day" was three words of small print; the mark people
        // recognise is the face, so the face leads and the name is one word.
        let words = try XCTUnwrap(text.first?.string as? NSAttributedString)
        XCTAssertEqual(words.string, "1Day")

        let mascot = try XCTUnwrap(images.first)
        let label = try XCTUnwrap(text.first)
        XCTAssertLessThan(mascot.frame.minX, label.frame.minX, "face first")
        XCTAssertLessThan(
            mascot.frame.minY, renderSize.height * 0.1, "bottom corner, not floating")
        XCTAssertLessThan(
            mascot.frame.width, renderSize.width * 0.08, "a mark, not a sticker")

        let url = try write(layer, named: "watermark")
        print("[film-mark] corner mark → \(url.path)")
    }

    /// Both marks on one frame, which is what a viewer actually sees in the
    /// first two seconds of a shared film.
    func testTheFirstFrameOfAFilmCarriesBoth() throws {
        let layer = container(UIColor(hex: 0x101828))
        VideoStitcher.addTitleCard(
            .init(title: "普通的周三", subtitle: "9月17日 – 9月23日"),
            to: layer, renderSize: renderSize, duration: 2.2)
        VideoStitcher.addWatermark(to: layer, renderSize: renderSize)
        let url = try write(layer, named: "first-frame")
        print("[film-mark] first frame → \(url.path)")
        XCTAssertGreaterThanOrEqual((layer.sublayers ?? []).count, 5)
    }

    // MARK: - The reaction palette that moved into chat

    func testTheDefaultReactionsAreTheCuteSix() {
        XCTAssertEqual(ClipReaction.palette, ["🩵", "🥹", "😭", "🫶", "✨", "🐣"])
        XCTAssertEqual(Set(ClipReaction.palette).count, 6, "no duplicates")
    }

    /// Changing the defaults must not disturb what somebody actually reaches
    /// for: their own history still leads the picker.
    func testYourOwnHistoryStillComesFirst() {
        let suggestions = ClipReactionRecents.suggestions(recents: ["😂", "🫶"])
        XCTAssertEqual(Array(suggestions.prefix(2)), ["😂", "🫶"])
        XCTAssertTrue(suggestions.contains("🐣"))
        XCTAssertEqual(Set(suggestions).count, suggestions.count, "no emoji twice")
    }
}
