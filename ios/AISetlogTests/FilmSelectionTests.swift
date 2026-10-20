import AVFoundation
import XCTest
@testable import AISetlog

/// Picking whose takes go into a room's film, and which stand still: the
/// choices themselves, where they're kept, and how a grid cell is filled.
final class FilmSelectionTests: XCTestCase {
    private func clip(_ id: String, day: Int, author: String?) -> DayClip {
        DayClip(
            day: day, url: URL(fileURLWithPath: "/tmp/\(id).mov"),
            authorName: author, authorID: author.map { "id-\($0)" }, key: id)
    }

    private lazy var room: [DayClip] = [
        clip("a1", day: 1, author: "Ann"),
        clip("b1", day: 1, author: "Bo"),
        clip("a2", day: 2, author: "Ann"),
        clip("c2", day: 2, author: "Cy"),
        clip("b3", day: 3, author: "Bo"),
    ]

    // MARK: - Who and which

    func testAnUntouchedSelectionKeepsEveryTake() {
        XCTAssertEqual(FilmSelection().applied(to: room).map(\.id), ["a1", "b1", "a2", "c2", "b3"])
    }

    func testLeavingAPersonOutDropsAllTheirTakesAndKeepsOrder() {
        var selection = FilmSelection()
        selection.set(person: "id-Bo", included: false)
        XCTAssertEqual(selection.applied(to: room).map(\.id), ["a1", "a2", "c2"])

        // A take they film later is out too: it's the person that's out.
        let later = room + [clip("b4", day: 4, author: "Bo")]
        XCTAssertFalse(selection.applied(to: later).contains { $0.id == "b4" })

        selection.set(person: "id-Bo", included: true)
        XCTAssertEqual(selection.applied(to: room).count, 5)
    }

    func testLeavingOneTakeOutKeepsTheRestOfThatPerson() {
        var selection = FilmSelection()
        selection.set(clip: "a2", included: false)
        XCTAssertEqual(selection.applied(to: room).map(\.id), ["a1", "b1", "c2", "b3"])
    }

    func testAPersonIsKeyedByAccountNotName() {
        // Two people who both typed "Sam" stay two people.
        let twins = [
            DayClip(day: 1, url: URL(fileURLWithPath: "/tmp/x.mov"),
                    authorName: "Sam", authorID: "one", key: "x"),
            DayClip(day: 1, url: URL(fileURLWithPath: "/tmp/y.mov"),
                    authorName: "Sam", authorID: "two", key: "y"),
        ]
        var selection = FilmSelection()
        selection.set(person: "one", included: false)
        XCTAssertEqual(selection.applied(to: twins).map(\.id), ["y"])
        XCTAssertEqual(FilmPerson.people(in: twins).count, 2)
    }

    func testASelectionThatLeavesNothingGivesEverythingBack() {
        // The room changed under a saved pick; the film page must still make
        // a film, or there is no way back to the sheet that would fix it.
        var selection = FilmSelection()
        for person in ["id-Ann", "id-Bo", "id-Cy"] { selection.set(person: person, included: false) }
        XCTAssertEqual(selection.applied(to: room).count, room.count)
    }

    func testPeopleComeInTheOrderTheyFirstAppear() {
        let people = FilmPerson.people(in: room)
        XCTAssertEqual(people.map(\.name), ["Ann", "Bo", "Cy"])
        XCTAssertEqual(people.map { $0.clips.map(\.id) }, [["a1", "a2"], ["b1", "b3"], ["c2"]])
    }

    // MARK: - Holds

    func testHoldsOnlyReachTheStitcherForTakesInTheFilm() {
        var selection = FilmSelection()
        selection.set(freeze: 0.5, for: "a1")
        selection.set(freeze: 0, for: "b1")
        selection.set(person: "id-Bo", included: false)
        XCTAssertEqual(selection.freezeFrames(for: room), ["a1": 0.5])

        selection.set(freeze: nil, for: "a1")
        XCTAssertEqual(selection.freezeFrames(for: room), [:])
    }

    func testANegativeHoldIsTheFirstFrame() {
        var selection = FilmSelection()
        selection.set(freeze: -2, for: "a1")
        XCTAssertEqual(selection.freeze(of: "a1"), 0)
    }

    func testPruningForgetsTakesThatLeftButKeepsPeople() {
        var selection = FilmSelection()
        selection.set(clip: "gone", included: false)
        selection.set(freeze: 1, for: "gone")
        selection.set(freeze: 1, for: "a1")
        selection.set(person: "id-Nobody", included: false)
        let pruned = selection.pruned(to: room)
        XCTAssertEqual(pruned.leftOutClips, [])
        XCTAssertEqual(pruned.freezes, ["a1": 1])
        XCTAssertEqual(pruned.leftOutPeople, ["id-Nobody"])
    }

    func testTheCacheKeyMovesWithEveryChoiceAndNotWithInsertionOrder() {
        var one = FilmSelection()
        one.set(clip: "a1", included: false)
        one.set(clip: "b1", included: false)
        var two = FilmSelection()
        two.set(clip: "b1", included: false)
        two.set(clip: "a1", included: false)
        XCTAssertEqual(one.cacheKey, two.cacheKey)

        let before = one.cacheKey
        one.set(freeze: 0, for: "c2")
        XCTAssertNotEqual(one.cacheKey, before)
        let held = one.cacheKey
        one.set(freeze: 0.4, for: "c2")
        XCTAssertNotEqual(one.cacheKey, held, "a different frame is a different film")
    }

    // MARK: - Kept on this phone

    func testTheSelectionIsKeptPerStory() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "FilmSelectionTests"))
        defaults.removePersistentDomain(forName: "FilmSelectionTests")
        defer { defaults.removePersistentDomain(forName: "FilmSelectionTests") }
        let story = UUID()
        let other = UUID()

        var selection = FilmSelection()
        selection.set(person: "id-Bo", included: false)
        selection.set(freeze: 0.75, for: "a1")
        FilmSelectionStore.save(selection, for: story, defaults: defaults)

        XCTAssertEqual(FilmSelectionStore.load(for: story, defaults: defaults), selection)
        XCTAssertEqual(FilmSelectionStore.load(for: other, defaults: defaults), FilmSelection())

        // Back to the default leaves nothing behind.
        FilmSelectionStore.save(FilmSelection(), for: story, defaults: defaults)
        XCTAssertNil(defaults.data(forKey: FilmSelectionStore.key(for: story)))
    }

    // MARK: - Filling a grid cell

    private func t(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 600) }

    func testAPlayingTakeLoopsUntilTheMomentEnds() {
        let segments = VideoStitcher.cellSegments(
            videoRange: CMTimeRange(start: .zero, duration: t(1)),
            momentDuration: t(2.5), freezeAt: nil, frameDuration: .invalid)
        XCTAssertEqual(segments.map { $0.offset.seconds }, [0, 1, 2])
        XCTAssertEqual(segments.map { $0.duration.seconds }, [1, 1, 0.5])
        // Never stretched: each piece lasts as long as the footage in it.
        XCTAssertTrue(segments.allSatisfy { $0.duration == $0.source.duration })
    }

    func testAHeldTakeIsOneFrameStretchedOverTheMoment() throws {
        let frame = CMTime(value: 1, timescale: 30)
        let segments = VideoStitcher.cellSegments(
            videoRange: CMTimeRange(start: t(0.1), duration: t(2)),
            momentDuration: t(3), freezeAt: 0.5, frameDuration: frame)
        let only = try XCTUnwrap(segments.first)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(only.offset, .zero)
        XCTAssertEqual(only.duration.seconds, 3, accuracy: 0.001)
        XCTAssertEqual(only.source.duration, frame)
        // Measured from the take's own start, not the file's.
        XCTAssertEqual(only.source.start.seconds, 0.6, accuracy: 0.001)
    }

    func testAHoldPastTheEndStopsOnTheLastFrame() throws {
        let segments = VideoStitcher.cellSegments(
            videoRange: CMTimeRange(start: .zero, duration: t(2)),
            momentDuration: t(2), freezeAt: 9, frameDuration: .invalid)
        let only = try XCTUnwrap(segments.first)
        // No frame duration from the track: one frame at 30 fps.
        XCTAssertEqual(only.source.duration.seconds, 1.0 / 30, accuracy: 0.001)
        XCTAssertEqual(only.source.end.seconds, 2, accuracy: 0.002)
        XCTAssertLessThanOrEqual(only.source.end, t(2))
    }

    func testNothingToFillGivesNoSegments() {
        XCTAssertTrue(VideoStitcher.cellSegments(
            videoRange: CMTimeRange(start: .zero, duration: .zero),
            momentDuration: t(2), freezeAt: nil, frameDuration: .invalid).isEmpty)
        XCTAssertTrue(VideoStitcher.cellSegments(
            videoRange: CMTimeRange(start: .zero, duration: t(2)),
            momentDuration: .zero, freezeAt: 0, frameDuration: .invalid).isEmpty)
    }

    func testKeptClipIDsFilterInOrderAndNilKeepsAll() {
        XCTAssertEqual(VideoStitcher.kept(room, ids: nil).count, 5)
        XCTAssertEqual(VideoStitcher.kept(room, ids: ["b3", "a1"]).map(\.id), ["a1", "b3"])
    }
}

/// The real stitch: a held cell stands still while its neighbour plays, and a
/// take left out is really gone from the film.
final class FilmHoldStitchTests: XCTestCase {
    private let ann = "1DAY-A"
    private let bo = "1DAY-B"

    private func moment(_ day: Int) async throws -> [DayClip] {
        var out: [DayClip] = []
        for author in [ann, bo] {
            let made = await DemoClipFactory.makeClip(
                moment: day, label: "Moment \(day)", author: author,
                seconds: 2, orientation: .portrait)
            out.append(DayClip(
                day: day, url: try XCTUnwrap(made),
                authorName: author, authorID: author, key: "\(author)-\(day)"))
        }
        return out
    }

    func testAHeldCellStandsStillWhileTheOtherPlays() async throws {
        let clips = try await moment(1)
        var options = VideoStitcher.Options()
        options.layout = .friendsTogether
        options.showDayCaptions = false
        options.freezeFrames = ["\(ann)-1": 0.2]

        let film = try await VideoStitcher.stitch(clips: clips, options: options)
        let duration = try await AVURLAsset(url: film).load(.duration).seconds
        XCTAssertEqual(duration, 2, accuracy: 0.2, "a hold fills the moment, no longer")

        let early = try await image(of: film, at: 0.4)
        let late = try await image(of: film, at: 1.6)
        // The demo takes print how far through they are ("MOMENT 1 · 10%")
        // just under the middle, so that band of a playing cell changes over
        // a second while a held one changes only by encoder noise.
        let held = band(early, x: 0.05..<0.45).diff(band(late, x: 0.05..<0.45))
        let playing = band(early, x: 0.55..<0.95).diff(band(late, x: 0.55..<0.95))
        XCTAssertGreaterThan(playing, held * 4, "held \(held) vs playing \(playing)")
    }

    func testATakeLeftOutIsNotInTheFilm() async throws {
        let clips = try await moment(1) + moment(2)
        var options = VideoStitcher.Options()
        options.layout = .friendsTogether
        options.showDayCaptions = false
        options.keptClipIDs = ["\(ann)-1", "\(bo)-1"]

        let film = try await VideoStitcher.stitch(clips: clips, options: options)
        let duration = try await AVURLAsset(url: film).load(.duration).seconds
        XCTAssertEqual(duration, 2, accuracy: 0.2, "moment 2 had nobody left in it")
    }

    private func image(of film: URL, at seconds: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: film))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(
            at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        // Into Caches, so a failure can be looked at rather than guessed at.
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
           let data = UIImage(cgImage: image).pngData() {
            try? data.write(to: caches.appendingPathComponent("film-hold-\(seconds).png"))
        }
        return image
    }

    /// Colours across the band where the demo take prints its progress,
    /// between the proportional `x` bounds.
    private func band(_ image: CGImage, x: Range<Double>) -> [Int] {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return [] }
        let step = image.bitsPerPixel / 8
        let rows = Int(Double(image.height) * 0.44)..<Int(Double(image.height) * 0.52)
        let columns = Int(Double(image.width) * x.lowerBound)..<Int(Double(image.width) * x.upperBound)
        return stride(from: rows.lowerBound, to: rows.upperBound, by: 2).flatMap { py in
            stride(from: columns.lowerBound, to: columns.upperBound, by: 2).flatMap { px in
                let offset = py * image.bytesPerRow + px * step
                return (0..<3).map { Int(bytes[offset + $0]) }
            }
        }
    }
}

private extension Array where Element == Int {
    func diff(_ other: [Int]) -> Int { zip(self, other).reduce(0) { $0 + abs($1.0 - $1.1) } }
}
