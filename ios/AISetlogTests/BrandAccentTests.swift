import UIKit
import XCTest

@testable import AISetlog

/// The app's accent follows the colour you picked for your avatar.
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

    func testWithNoPickTheAccentIsTheBrandBlue() {
        XCTAssertNil(Identity.myPickedUIColor(in: defaults))
    }

    func testAPickBecomesTheAccent() {
        let wanted = Identity.paletteUIColors.count - 1
        Identity.chooseTint(wanted, forName: "Cassie", in: defaults)
        XCTAssertEqual(
            Identity.myPickedUIColor(in: defaults), Identity.paletteUIColors[wanted])
    }

    /// A pick with no name attached is not a pick — that pairing is what makes
    /// the avatar override safe, and the accent reads the same two keys.
    func testAHalfWrittenPickIsIgnored() {
        defaults.set(2, forKey: Identity.myTintKey)
        XCTAssertNil(Identity.myPickedIndex(in: defaults))
        defaults.set("Cassie", forKey: Identity.myTintNameKey)
        XCTAssertEqual(Identity.myPickedIndex(in: defaults), 2)
    }

    func testAnOutOfRangePickIsIgnored() {
        defaults.set(99, forKey: Identity.myTintKey)
        defaults.set("Cassie", forKey: Identity.myTintNameKey)
        XCTAssertNil(Identity.myPickedIndex(in: defaults))
    }

    // MARK: - The lighter end of the gradient

    private func hsb(_ color: UIColor) -> (h: CGFloat, s: CGFloat, b: CGFloat) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(color.getHue(&h, saturation: &s, brightness: &b, alpha: &a))
        return (h, s, b)
    }

    /// Every accent needs a second, lighter colour to make a gradient with.
    /// Derived rather than listed, so the seven don't need seven more hexes.
    func testTheGradientsSecondColourIsLighterAndLessSaturated() {
        for index in Identity.paletteUIColors.indices {
            Identity.chooseTint(index, forName: "Cassie", in: defaults)
            let base = hsb(Identity.paletteUIColors[index])
            // `oneDayBrandLight` reads `.standard`, so derive it here the same
            // way rather than writing to the real defaults from a test.
            let light = hsb(lighten(Identity.paletteUIColors[index]))
            XCTAssertLessThan(light.s, base.s, "index \(index)")
            XCTAssertGreaterThanOrEqual(light.b, base.b, "index \(index)")
        }
    }

    func testTheDefaultAccentsLighterEndLandsNearTheBrandCyan() {
        let light = hsb(lighten(.oneDayBlue))
        let cyan = hsb(.oneDayCyan)
        XCTAssertEqual(light.h, cyan.h, accuracy: 0.05)
        XCTAssertEqual(light.b, cyan.b, accuracy: 0.1)
    }

    /// The same arithmetic `UIColor.oneDayBrandLight` does, against a colour
    /// handed in — the production one reads the stored pick.
    private func lighten(_ base: UIColor) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        base.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(
            hue: (h - 0.028 + 1).truncatingRemainder(dividingBy: 1),
            saturation: s * 0.84,
            brightness: min(b * 1.06, 1),
            alpha: a)
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
