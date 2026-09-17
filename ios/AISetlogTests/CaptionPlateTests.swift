import UIKit
import XCTest

@testable import AISetlog

/// The four backings and the twelve colours — the part that has to look the
/// same on the review screen and in the exported film.
final class CaptionPlateTests: XCTestCase {

    // MARK: - What the picker offers

    func testThePickerOffersFourBackingsAndNotTheRetiredOne() {
        XCTAssertEqual(
            CaptionSticker.Style.picker, [.outline, .band, .solid, .light])
        XCTAssertFalse(CaptionSticker.Style.picker.contains(.headline))
    }

    /// A card saved when 大 was a style still draws big, and the picker shows
    /// it as 不加底 rather than showing nothing selected.
    func testHeadlineStillDecodesAndLightsUpTheNoBackingSquare() throws {
        let json = #"{"x":0.5,"y":0.43,"style":"headline","scale":1,"angle":0,"tint":"white"}"#
        let sticker = try JSONDecoder().decode(
            CaptionSticker.self, from: Data(json.utf8))
        XCTAssertEqual(sticker.style, .headline)
        XCTAssertEqual(sticker.style.pickerEquivalent, .outline)
        XCTAssertNil(sticker.style.plate)
    }

    // MARK: - The backings themselves

    func testOnlyTwoStylesHaveNoBacking() {
        XCTAssertNil(CaptionSticker.Style.outline.plate)
        XCTAssertNil(CaptionSticker.Style.headline.plate)
        XCTAssertNotNil(CaptionSticker.Style.band.plate)
        XCTAssertNotNil(CaptionSticker.Style.solid.plate)
        XCTAssertNotNil(CaptionSticker.Style.light.plate)
    }

    /// The dimmed band is the round one; the two bars are square-ish. That
    /// difference is the only thing telling them apart at a glance.
    func testTheBandIsRounderThanTheBars() throws {
        let band = try XCTUnwrap(CaptionSticker.Style.band.plate)
        let solid = try XCTUnwrap(CaptionSticker.Style.solid.plate)
        let light = try XCTUnwrap(CaptionSticker.Style.light.plate)
        XCTAssertGreaterThan(band.radius, solid.radius)
        XCTAssertEqual(solid.radius, light.radius)
        XCTAssertEqual(solid.padH, light.padH)
    }

    func testTheSolidBarIsOpaqueAndTheBandIsNot() throws {
        let band = try XCTUnwrap(CaptionSticker.Style.band.plate)
        let solid = try XCTUnwrap(CaptionSticker.Style.solid.plate)
        XCTAssertLessThan(band.opacity, 0.6)
        XCTAssertEqual(solid.opacity, 1)
        XCTAssertFalse(band.isWhite)
        XCTAssertFalse(solid.isWhite)
        XCTAssertTrue(try XCTUnwrap(CaptionSticker.Style.light.plate).isWhite)
    }

    // MARK: - The bar is the colour it says it is

    private func isLight(_ color: UIColor) -> Bool {
        var white: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(color.getWhite(&white, alpha: &alpha))
        return white > 0.5
    }

    /// The bar never second-guesses the square that was tapped. 白底 draws
    /// white whatever colour the words are — the correction happens to the
    /// words, where it can be seen.
    func testTheBarIsWhateverTheStyleSaid() throws {
        for tint in CaptionSticker.Tint.allCases {
            let light = CaptionSticker(x: 0.5, y: 0.5, style: .light, tint: tint)
            XCTAssertTrue(isLight(try XCTUnwrap(light.plateUIColor)), tint.rawValue)
            for style in [CaptionSticker.Style.band, .solid] {
                let dark = CaptionSticker(x: 0.5, y: 0.5, style: style, tint: tint)
                XCTAssertFalse(isLight(try XCTUnwrap(dark.plateUIColor)), tint.rawValue)
            }
        }
    }

    func testStylesWithoutABarHaveNoBarColour() {
        XCTAssertNil(CaptionSticker(x: 0.5, y: 0.5, style: .outline, tint: .blue).plateUIColor)
        XCTAssertNil(CaptionSticker(x: 0.5, y: 0.5, style: .headline, tint: .blue).plateUIColor)
    }

    // MARK: - Picking one moves the other, rather than drawing a lie

    func testPickingTheWhiteBarUnderWhiteWordsTurnsTheWordsBlack() {
        XCTAssertEqual(
            CaptionSticker.legibleTint(picking: .light, keeping: .white), .black)
    }

    func testPickingADarkBarUnderDarkWordsTurnsTheWordsWhite() {
        for style in [CaptionSticker.Style.band, .solid] {
            for tint in [CaptionSticker.Tint.black, .ink] {
                XCTAssertEqual(
                    CaptionSticker.legibleTint(picking: style, keeping: tint), .white,
                    "\(style.rawValue) + \(tint.rawValue)")
            }
        }
    }

    func testAPairThatAlreadyReadsIsLeftAlone() {
        XCTAssertEqual(
            CaptionSticker.legibleTint(picking: .solid, keeping: .butter), .butter)
        XCTAssertEqual(
            CaptionSticker.legibleTint(picking: .light, keeping: .blue), .blue)
        // No bar, nothing to clash with: black words with no backing are the
        // point of having black at all.
        XCTAssertEqual(
            CaptionSticker.legibleTint(picking: .outline, keeping: .black), .black)
    }

    /// The mirror: tapping a colour swaps the bar, and swaps it for the other
    /// bar rather than for no bar — somebody who chose a bar wants a bar.
    func testPickingWhiteWordsOnTheWhiteBarSwapsToTheBlackBar() {
        XCTAssertEqual(
            CaptionSticker.legibleStyle(picking: .white, keeping: .light), .solid)
    }

    func testPickingBlackWordsOnADarkBarSwapsToTheWhiteBar() {
        XCTAssertEqual(
            CaptionSticker.legibleStyle(picking: .black, keeping: .band), .light)
        XCTAssertEqual(
            CaptionSticker.legibleStyle(picking: .ink, keeping: .solid), .light)
    }

    func testPickingAColourNeverAddsABarToAStyleThatHasNone() {
        XCTAssertEqual(
            CaptionSticker.legibleStyle(picking: .white, keeping: .outline), .outline)
        XCTAssertEqual(
            CaptionSticker.legibleStyle(picking: .black, keeping: .headline), .headline)
    }

    /// Whatever route it took, what gets saved has to be readable — this is the
    /// property the two functions exist for.
    func testEveryPickEndsUpReadable() {
        for style in CaptionSticker.Style.picker {
            for tint in CaptionSticker.Tint.allCases {
                let byStyle = CaptionSticker(
                    x: 0.5, y: 0.5, style: style,
                    tint: CaptionSticker.legibleTint(picking: style, keeping: tint))
                let byTint = CaptionSticker(
                    x: 0.5, y: 0.5,
                    style: CaptionSticker.legibleStyle(picking: tint, keeping: style),
                    tint: tint)
                for sticker in [byStyle, byTint] {
                    guard let plate = sticker.style.plate else { continue }
                    XCTAssertFalse(
                        plate.isWhite && sticker.tint == .white,
                        "white on white: \(style.rawValue) + \(tint.rawValue)")
                    XCTAssertFalse(
                        !plate.isWhite && sticker.tint.isDark,
                        "dark on dark: \(style.rawValue) + \(tint.rawValue)")
                }
            }
        }
    }

    // MARK: - Twelve colours

    func testTwelveColoursInTwoRowsOfSix() {
        XCTAssertEqual(CaptionSticker.Tint.allCases.count, 12)
        XCTAssertEqual(CaptionSticker.Tint.allCases.first, .white)
        // The picker draws `allCases` six at a time, so the declaration order
        // *is* the layout: white and black lead the first row.
        XCTAssertEqual(CaptionSticker.Tint.allCases[1], .black)
    }

    func testEveryColourHasItsOwnValue() {
        let values = Set(CaptionSticker.Tint.allCases.map { $0.uiColor.description })
        XCTAssertEqual(values.count, CaptionSticker.Tint.allCases.count)
    }

    /// The six that shipped keep their names, so a card written before this
    /// change still comes back the colour it was.
    func testTheOriginalSixStillDecodeByName() {
        for raw in ["white", "blue", "cyan", "lavender", "mint", "ink"] {
            XCTAssertNotNil(CaptionSticker.Tint(rawValue: raw), raw)
        }
    }

    /// A colour from a newer phone, read by this one, falls back to white
    /// rather than dropping the whole caption.
    func testAnUnknownColourFallsBackToWhite() throws {
        let sticker = try XCTUnwrap(
            CaptionSticker(cloudValue: "0.4,0.6,solid,1.2,10,tangerine"))
        XCTAssertEqual(sticker.tint, .white)
        XCTAssertEqual(sticker.style, .solid)
        XCTAssertEqual(sticker.scale, 1.2, accuracy: 0.001)
    }

    func testANewBackingAndColourSurviveTheRoundTripThroughCloudKit() throws {
        let sent = CaptionSticker(
            x: 0.31, y: 0.72, style: .light, scale: 1.4, angle: -8, tint: .coral)
        let back = try XCTUnwrap(CaptionSticker(cloudValue: sent.cloudValue))
        XCTAssertEqual(back, sent)
    }
}
