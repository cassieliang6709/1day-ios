import XCTest
@testable import AISetlog

/// The film screen used to have a spinner that could never finish.
///
/// `FilmView.render()` had three paths that returned without setting either
/// `exportURL` or `errorMessage`, so the view stayed on `GeneratingFilm`
/// forever — no film, no error, no way out but the back button. CI caught it as
/// `LocalFormalRoomUITests` burning its whole 240-second media budget waiting
/// for a 「调整」 button that was never coming; a person hit it by tapping
/// 退出演示 and then opening the film again.
///
/// So the thing worth testing is not any single branch, it is the absence:
/// every outcome except `.superseded` has to put something on screen, and
/// `.superseded` is only reachable when another render is already running.
final class FilmRenderOutcomeTests: XCTestCase {
    func testAFinishedStitchWithAnOpenScopeShowsTheFilm() {
        XCTAssertEqual(
            FilmRenderOutcome.of(
                stitchFailed: false, superseded: false,
                scopeRejected: false, scopeClosed: false),
            .film)
    }

    /// The exact shape of the bug: the stitch worked, and the demo's media
    /// scope threw the file away because 退出演示 had closed it.
    func testAClosedDemoScopeRejectingTheFilmSaysSoInsteadOfSpinning() {
        let outcome = FilmRenderOutcome.of(
            stitchFailed: false, superseded: false,
            scopeRejected: true, scopeClosed: true)
        XCTAssertEqual(outcome, .sessionEnded)
        XCTAssertTrue(outcome.showsSomething)
    }

    /// A rejection is a rejection even if `isClosed` hasn't flipped yet — the
    /// scope is the authority on whether it took the file.
    func testRejectionAloneIsEnoughToReportSomething() {
        let outcome = FilmRenderOutcome.of(
            stitchFailed: false, superseded: false,
            scopeRejected: true, scopeClosed: false)
        XCTAssertEqual(outcome, .sessionEnded)
    }

    func testAFailedStitchReportsTheStitchersOwnReason() {
        XCTAssertEqual(
            FilmRenderOutcome.of(
                stitchFailed: true, superseded: false,
                scopeRejected: false, scopeClosed: false),
            .failed)
    }

    /// A stitch that fails inside a closed demo gets the demo's wording, not
    /// an AVFoundation error code about a file that was deleted on purpose.
    func testAFailedStitchInAClosedDemoBlamesTheDemo() {
        XCTAssertEqual(
            FilmRenderOutcome.of(
                stitchFailed: true, superseded: false,
                scopeRejected: false, scopeClosed: true),
            .sessionEnded)
    }

    /// The only case allowed to draw nothing, and it outranks every other
    /// signal: a newer render is on screen and owns the result.
    func testOnlyASupersedingRenderMayShowNothing() {
        for failed in [true, false] {
            for rejected in [true, false] {
                for closed in [true, false] {
                    XCTAssertEqual(
                        FilmRenderOutcome.of(
                            stitchFailed: failed, superseded: true,
                            scopeRejected: rejected, scopeClosed: closed),
                        .superseded,
                        "superseded must win over failed:\(failed) rejected:\(rejected) closed:\(closed)")
                }
            }
        }
    }

    /// The invariant, stated over the whole input space: if no newer render has
    /// started, the screen changes. This is the assertion that would have
    /// failed before the fix.
    func testEveryNonSupersededOutcomePutsSomethingOnScreen() {
        for failed in [true, false] {
            for rejected in [true, false] {
                for closed in [true, false] {
                    let outcome = FilmRenderOutcome.of(
                        stitchFailed: failed, superseded: false,
                        scopeRejected: rejected, scopeClosed: closed)
                    XCTAssertTrue(
                        outcome.showsSomething,
                        "failed:\(failed) rejected:\(rejected) closed:\(closed) left the spinner running")
                }
            }
        }
    }
}
