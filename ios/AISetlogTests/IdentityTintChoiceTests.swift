import XCTest

@testable import AISetlog

/// Picking your own avatar colour, and everybody else keeping the derived one.
final class IdentityTintChoiceTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        // A suite of its own: these tests write the same keys the app does.
        defaults = UserDefaults(suiteName: "identity-tint-tests")
        defaults.removePersistentDomain(forName: "identity-tint-tests")
    }

    // MARK: - The old rule still draws everybody

    func testTheDerivedColourIsStableForTheSameName() {
        XCTAssertEqual(
            Identity.derivedIndex(for: "Cassie"), Identity.derivedIndex(for: "Cassie"))
    }

    func testAMissingNameFallsBackToTheBrandBlue() {
        XCTAssertEqual(Identity.uiColor(for: nil), .oneDayBlue)
        XCTAssertEqual(Identity.uiColor(for: ""), .oneDayBlue)
    }

    func testEveryDerivedIndexIsInThePalette() {
        for name in ["Cassie", "周悦林", "A", "a very long display name indeed", "🙂"] {
            XCTAssertTrue(
                Identity.paletteUIColors.indices.contains(Identity.derivedIndex(for: name)),
                name)
        }
    }

    // MARK: - Your own pick

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

    /// The point of option A: your pick stands even when it collides with the
    /// colour a friend in the room was given.
    func testACollisionWithSomebodyElsesColourIsAllowed() {
        let theirs = "Sam"
        let collision = Identity.derivedIndex(for: theirs)
        Identity.chooseTint(collision, forName: "Cassie", in: defaults)
        XCTAssertEqual(Identity.tintIndex(for: "Cassie", in: defaults), collision)
        XCTAssertEqual(Identity.tintIndex(for: theirs, in: defaults), collision)
    }

    func testRenamingYourselfDoesNotHandYourColourToTheNextPerson() {
        Identity.chooseTint(0, forName: "Cassie", in: defaults)
        // The stored choice belongs to "Cassie"; a differently-named account
        // reading the same device gets the derived colour.
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

    /// A value from a build with a longer palette, or a corrupted one, must not
    /// index past the end of the array.
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
