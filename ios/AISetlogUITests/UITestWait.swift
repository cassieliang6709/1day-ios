import Foundation

/// Wait budgets shared by the UI test suite.
///
/// Two kinds of wait live in these tests and they are not interchangeable. Most
/// of them are waiting on a view that is already computed and only has to
/// render; those stay at a literal 15s, because a SwiftUI transition that takes
/// longer than that really is broken. `media` is for the handful that are
/// waiting on AVFoundation to finish a stitch or a composition before the
/// element they want can exist at all.
///
/// That distinction matters because of where the tests run. A GitHub Actions
/// `macos-15` runner has no GPU to hand the compositing to, so it falls back to
/// software and is not marginally slower than a developer Mac — it is roughly
/// an order of magnitude slower. The same work, same suite, CI run 34968934397:
///
/// | Measurement                                            | Mac    | CI      |
/// | ------------------------------------------------------ | ------ | ------- |
/// | `VideoStitcherTests.testFriendsTogetherPlaysSameDay…`   | 13.9s  | 74.8s   |
/// | `LocalRoomRuntimeTests.testTwoAndThreeMembersUseReal…`  |        | 141.5s  |
/// | `DefaultFilmAspectTests.testDemoAutoUpdatesAfterFirst…` |        | 208.7s  |
///
/// The middle row is the two- and three-member compositor run that the room
/// waits below are literally waiting on, and it needs 141.5s on the runner with
/// no UI layer on top of it. The bottom row is the heaviest media work anywhere
/// in the suite at 208.7s. Both passed — they are not pathological, that is
/// simply what this costs without a GPU.
///
/// 90s was the previous value here, itself already raised from 20–25s for this
/// same reason, and it sat under all of the above. So the waits had stopped
/// measuring whether the app works and started measuring which machine ran
/// them: `LocalFormalRoomUITests` and `LocalFormalMomentUITests` each burned the
/// full 90s and failed, while `LocalRoomImportUITests` passed at 82.8s — seven
/// seconds of margin, one noisy run from failing too.
///
/// 240s clears the slowest media work observed on the runner with headroom for
/// a bad day. It is deliberately not adaptive and deliberately not tuned per
/// call site: `waitForExistence` returns the moment the element appears, so a
/// healthy run never spends this budget and a generous ceiling costs a passing
/// test exactly nothing. On this Mac the four waits in
/// `LocalFormalRoomUITests` measured 7.8s, 20.2s, 28.3s and 4.2s even with the
/// machine under heavy load. The only thing the size buys is a slower report
/// when a media wait genuinely breaks — four minutes instead of ninety seconds
/// — which is the right way round for a suite that was failing for no product
/// reason at all.
enum UITestWait {
    /// Ceiling for an element that cannot exist until a real render finishes.
    static let media: TimeInterval = 240
}
