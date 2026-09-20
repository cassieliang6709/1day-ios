import UIKit
import XCTest

@testable import AISetlog

/// The app's accent is the brand blue, and picking a colour only moves your
/// avatar. 1.3 wired the accent to the avatar pick; these tests pin the
/// unwiring, because the two are one property apart and easy to reconnect by
/// accident.
final class BrandAccentTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "brand-accent-tests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testTheAccentIsTheBrandBlue() {
        XCTAssertEqual(UIColor.oneDayBrand, UIColor.oneDayBlue)
    }

    /// The whole point of the revert: a warm avatar on a blue app, not a warm
    /// app. `oneDayBrand` reads no defaults at all now, so a real pick in the
    /// standard domain cannot reach it either.
    func testAPickMovesYourAvatarAndLeavesTheAccentAlone() {
        let wanted = Identity.paletteUIColors.count - 1
        Identity.chooseTint(wanted, forName: "Cassie", in: defaults)
        XCTAssertEqual(Identity.tintIndex(for: "Cassie", in: defaults), wanted)
        XCTAssertEqual(UIColor.oneDayBrand, UIColor.oneDayBlue)
    }

    /// Somebody else in the room keeps the colour their name hashes to — the
    /// pick is yours, not the room's.
    func testAPickDoesNotMoveSomebodyElsesAvatar() {
        let wanted = Identity.paletteUIColors.count - 1
        Identity.chooseTint(wanted, forName: "Cassie", in: defaults)
        XCTAssertEqual(
            Identity.tintIndex(for: "Blue", in: defaults),
            Identity.derivedIndex(for: "Blue"))
    }

    /// A pick with no name attached is not a pick — that pairing is what makes
    /// the avatar override safe.
    func testAHalfWrittenPickIsIgnored() {
        defaults.set(2, forKey: Identity.myTintKey)
        XCTAssertEqual(
            Identity.tintIndex(for: "Cassie", in: defaults),
            Identity.derivedIndex(for: "Cassie"))
        defaults.set("Cassie", forKey: Identity.myTintNameKey)
        XCTAssertEqual(Identity.tintIndex(for: "Cassie", in: defaults), 2)
    }

    func testAnOutOfRangePickIsIgnored() {
        defaults.set(99, forKey: Identity.myTintKey)
        defaults.set("Cassie", forKey: Identity.myTintNameKey)
        XCTAssertEqual(
            Identity.tintIndex(for: "Cassie", in: defaults),
            Identity.derivedIndex(for: "Cassie"))
    }

    /// Clearing the pick goes back to the derived colour rather than to blank.
    func testClearingThePickGoesBackToTheDerivedColour() {
        Identity.chooseTint(4, forName: "Cassie", in: defaults)
        Identity.chooseTint(nil, forName: nil, in: defaults)
        XCTAssertEqual(
            Identity.tintIndex(for: "Cassie", in: defaults),
            Identity.derivedIndex(for: "Cassie"))
    }

    // MARK: - The lighter end of the gradient

    private func hsb(_ color: UIColor) -> (h: CGFloat, s: CGFloat, b: CGFloat) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(color.getHue(&h, saturation: &s, brightness: &b, alpha: &a))
        return (h, s, b)
    }

    /// The gradient still needs a second colour, and it is still derived
    /// rather than listed — there is just only one accent to derive it from.
    func testTheGradientsSecondColourIsLighterAndLessSaturated() {
        let base = hsb(.oneDayBrand)
        let light = hsb(.oneDayBrandLight)
        XCTAssertLessThan(light.s, base.s)
        XCTAssertGreaterThanOrEqual(light.b, base.b)
    }

    func testTheGradientsSecondColourLandsNearTheBrandCyan() {
        let light = hsb(.oneDayBrandLight)
        let cyan = hsb(.oneDayCyan)
        XCTAssertEqual(light.h, cyan.h, accuracy: 0.05)
        XCTAssertEqual(light.b, cyan.b, accuracy: 0.1)
    }

    // MARK: - What must not follow the accent

    /// Caption colours are pinned hexes on purpose: they get burned into an
    /// exported film, and a caption somebody chose must not change colour
    /// because they later re-themed the app.
    func testCaptionColoursDoNotFollowTheAccent() {
        Identity.chooseTint(3, forName: "Cassie", in: defaults)
        XCTAssertEqual(
            CaptionSticker.Tint.blue.uiColor, UIColor(hex: 0x1677FF))
        XCTAssertEqual(CaptionSticker.Tint.white.uiColor, .white)
    }
}
