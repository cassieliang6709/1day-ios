import UIKit
import XCTest

@testable import AISetlog

final class BrandAccentTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "brand-accent-tests"

    private var savedSkin: Any?

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        savedSkin = UserDefaults.standard.object(forKey: AppSkin.storageKey)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        UserDefaults.standard.set(savedSkin, forKey: AppSkin.storageKey)
        super.tearDown()
    }

    func testTheAccentFollowsTheSkin() {
        UserDefaults.standard.set(AppSkin.cream.rawValue, forKey: AppSkin.storageKey)
        XCTAssertEqual(UIColor.oneDayBrand, UIColor.oneDayCream)
        UserDefaults.standard.set(AppSkin.blue.rawValue, forKey: AppSkin.storageKey)
        XCTAssertEqual(UIColor.oneDayBrand, UIColor.oneDayBlue)
    }

    func testCreamIsTheDefaultSkin() {
        UserDefaults.standard.removeObject(forKey: AppSkin.storageKey)
        XCTAssertEqual(AppSkin.current, .cream)
    }

    func testAPickMovesYourAvatarAndLeavesTheAccentAlone() {
        let before = UIColor.oneDayBrand
        let wanted = Identity.paletteUIColors.count - 1
        Identity.chooseTint(wanted, forName: "Cassie", in: defaults)
        XCTAssertEqual(Identity.tintIndex(for: "Cassie", in: defaults), wanted)
        XCTAssertEqual(UIColor.oneDayBrand, before)
    }

    func testAPickDoesNotMoveSomebodyElsesAvatar() {
        let wanted = Identity.paletteUIColors.count - 1
        Identity.chooseTint(wanted, forName: "Cassie", in: defaults)
        XCTAssertEqual(
            Identity.tintIndex(for: "Blue", in: defaults),
            Identity.derivedIndex(for: "Blue"))
    }

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

    func testClearingThePickGoesBackToTheDerivedColour() {
        Identity.chooseTint(4, forName: "Cassie", in: defaults)
        Identity.chooseTint(nil, forName: nil, in: defaults)
        XCTAssertEqual(
            Identity.tintIndex(for: "Cassie", in: defaults),
            Identity.derivedIndex(for: "Cassie"))
    }


    private func hsb(_ color: UIColor) -> (h: CGFloat, s: CGFloat, b: CGFloat) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(color.getHue(&h, saturation: &s, brightness: &b, alpha: &a))
        return (h, s, b)
    }

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


    func testCaptionColoursDoNotFollowTheAccent() {
        Identity.chooseTint(3, forName: "Cassie", in: defaults)
        XCTAssertEqual(
            CaptionSticker.Tint.blue.uiColor, UIColor(hex: 0x1677FF))
        XCTAssertEqual(CaptionSticker.Tint.white.uiColor, .white)
    }
}
