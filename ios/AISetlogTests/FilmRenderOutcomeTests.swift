import XCTest
@testable import AISetlog

final class FilmRenderOutcomeTests: XCTestCase {
    func testAFinishedStitchWithAnOpenScopeShowsTheFilm() {
        XCTAssertEqual(
            FilmRenderOutcome.of(
                stitchFailed: false, superseded: false,
                scopeRejected: false, scopeClosed: false),
            .film)
    }

    func testAClosedDemoScopeRejectingTheFilmSaysSoInsteadOfSpinning() {
        let outcome = FilmRenderOutcome.of(
            stitchFailed: false, superseded: false,
            scopeRejected: true, scopeClosed: true)
        XCTAssertEqual(outcome, .sessionEnded)
        XCTAssertTrue(outcome.showsSomething)
    }

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

    func testAFailedStitchInAClosedDemoBlamesTheDemo() {
        XCTAssertEqual(
            FilmRenderOutcome.of(
                stitchFailed: true, superseded: false,
                scopeRejected: false, scopeClosed: true),
            .sessionEnded)
    }

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
