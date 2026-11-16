import XCTest

@testable import AISetlog

final class IdentityTintChoiceTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "identity-tint-tests")
        defaults.removePersistentDomain(forName: "identity-tint-tests")
    }


    func testTheDerivedColourIsStableForTheSameName() {
        XCTAssertEqual(
            Identity.derivedIndex(for: "Cassie"), Identity.derivedIndex(for: "Cassie"))
    }

    func testAMissingNameFallsBackToTheBrandColour() {
        XCTAssertEqual(Identity.uiColor(for: nil), .oneDayBrand)
        XCTAssertEqual(Identity.uiColor(for: ""), .oneDayBrand)
    }

    func testEveryDerivedIndexIsInThePalette() {
        for name in ["Cassie", "周悦林", "A", "a very long display name indeed", "🙂"] {
            XCTAssertTrue(
                Identity.paletteUIColors.indices.contains(Identity.derivedIndex(for: name)),
                name)
        }
    }


    func testPickingAColourOverridesTheDerivedOneForThatNameOnly() {
        let mine = "Cassie"
        let theirs = "Sam"
        let wanted = (Identity.derivedIndex(for: mine) + 3) % Identity.paletteUIColors.count

        Identity.chooseTint(wanted, forName: mine, in: defaults)

        XCTAssertEqual(Identity.tintIndex(for: mine, in: defaults), wanted)
        XCTAssertEqual(
            Identity.tintIndex(for: theirs, in: defaults),
            Identity.derivedIndex(for: theirs),
            "somebody else's colour is not mine to change")
    }

    func testACollisionWithSomebodyElsesColourIsAllowed() {
        let theirs = "Sam"
        let collision = Identity.derivedIndex(for: theirs)
        Identity.chooseTint(collision, forName: "Cassie", in: defaults)
        XCTAssertEqual(Identity.tintIndex(for: "Cassie", in: defaults), collision)
        XCTAssertEqual(Identity.tintIndex(for: theirs, in: defaults), collision)
    }

    func testRenamingYourselfDoesNotHandYourColourToTheNextPerson() {
        Identity.chooseTint(0, forName: "Cassie", in: defaults)
        XCTAssertEqual(
            Identity.tintIndex(for: "Cassandra", in: defaults),
            Identity.derivedIndex(for: "Cassandra"))
    }

    func testClearingThePickGoesBackToTheDerivedColour() {
        Identity.chooseTint(0, forName: "Cassie", in: defaults)
        Identity.chooseTint(nil, forName: "Cassie", in: defaults)
        XCTAssertEqual(
            Identity.tintIndex(for: "Cassie", in: defaults),
            Identity.derivedIndex(for: "Cassie"))
    }

    func testAnOutOfRangePickIsIgnoredRatherThanCrashing() {
        Identity.chooseTint(99, forName: "Cassie", in: defaults)
        XCTAssertEqual(
            Identity.tintIndex(for: "Cassie", in: defaults),
            Identity.derivedIndex(for: "Cassie"))
        defaults.set(99, forKey: Identity.myTintKey)
        defaults.set("Cassie", forKey: Identity.myTintNameKey)
        XCTAssertEqual(
            Identity.tintIndex(for: "Cassie", in: defaults),
            Identity.derivedIndex(for: "Cassie"))
    }

    func testPickingWithNoNameStoresNothing() {
        Identity.chooseTint(2, forName: nil, in: defaults)
        XCTAssertNil(defaults.object(forKey: Identity.myTintKey))
        Identity.chooseTint(2, forName: "", in: defaults)
        XCTAssertNil(defaults.object(forKey: Identity.myTintKey))
    }
}
