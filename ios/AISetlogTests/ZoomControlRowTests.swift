import XCTest
import SwiftUI
@testable import AISetlog

/// The zoom row has to fit the narrowest phone this app runs on, in both
/// languages, at every type size somebody might have set.
///
/// The width it has: iPhone SE is 375pt, `RecordClipView` insets by 12 and the
/// control bar by another 14, so the row gets 323. It sits above the shutter in
/// a fixed bar, so a row that grows past that pushes nothing and warns nobody
/// — it just draws its last chip off the edge of the screen.
@MainActor
final class ZoomControlRowTests: XCTestCase {
    /// iPhone SE, minus `RecordClipView`'s and the control bar's insets.
    private let narrowestBar: CGFloat = 323

    private let backCamera = CameraZoom(base: 2, minFactor: 1, maxFactor: 123)

    private func row(
        presets: [CGFloat],
        zoom: CGFloat,
        showsSlider: Bool = false
    ) -> ZoomControlRow {
        ZoomControlRow(
            presets: presets,
            capabilities: backCamera,
            tint: .cyan,
            zoom: .constant(zoom),
            showsSlider: .constant(showsSlider))
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
        super.tearDown()
    }

    /// Rendered with no width proposed, so the image comes back at the row's
    /// own ideal size — which is the number that has to fit.
    ///
    /// `Strings` reads the language out of `UserDefaults`, not the
    /// environment, so the language is set there before the render.
    private func idealSize(
        _ view: some View,
        language: AppLanguage,
        typeSize: DynamicTypeSize
    ) throws -> CGSize {
        UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.storageKey)
        let renderer = ImageRenderer(
            content: view
                .environment(\.dynamicTypeSize, typeSize)
                .environment(\.colorScheme, .light))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        return CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
    }

    func testThreeChipsFitTheNarrowestControlBarAtEveryTypeSize() throws {
        for typeSize in DynamicTypeSize.allCases {
            let size = try idealSize(
                row(presets: [0.5, 1, 2], zoom: 1),
                language: .chinese,
                typeSize: typeSize)
            XCTAssertLessThanOrEqual(
                size.width, narrowestBar,
                "0.5x/1x/2x + 自定义 runs off an iPhone SE at \(typeSize)")
            XCTAssertGreaterThan(size.height, 20, "chips collapsed at \(typeSize)")
        }
    }

    /// "自定义" is three characters and "Custom" is six, so English is the
    /// wider of the two and is the one that decides whether the row fits.
    func testTheEnglishRowFitsTheNarrowestControlBarToo() throws {
        for typeSize in DynamicTypeSize.allCases {
            let size = try idealSize(
                row(presets: [0.5, 1, 2], zoom: 1),
                language: .english,
                typeSize: typeSize)
            XCTAssertLessThanOrEqual(size.width, narrowestBar, "English row overflows at \(typeSize)")
        }
    }

    /// A pinch parks the zoom between the chips, and then the custom chip
    /// carries a number instead of a word — the widest of which is "9.9x".
    func testTheOffPresetRowStillFits() throws {
        for typeSize in DynamicTypeSize.allCases {
            let size = try idealSize(
                row(presets: [0.5, 1, 2], zoom: 9.9),
                language: .chinese,
                typeSize: typeSize)
            XCTAssertLessThanOrEqual(size.width, narrowestBar, "off-preset row overflows at \(typeSize)")
        }
    }

    func testTheFrontCamerasTwoChipRowRenders() throws {
        let size = try idealSize(
            row(presets: [1, 2], zoom: 1),
            language: .chinese,
            typeSize: .large)
        XCTAssertLessThanOrEqual(size.width, narrowestBar)
        XCTAssertGreaterThan(size.width, 60)
    }

    /// The slider row has to be *given* a width — a `Slider` has no ideal one
    /// — so this checks it survives the narrowest bar rather than measuring it.
    ///
    /// It is also as far as a renderer can go here: `ImageRenderer` cannot
    /// draw a UIKit-backed `Slider` and substitutes a placeholder block, so
    /// this proves the row's geometry and nothing about the slider's own
    /// appearance. That part needs a running app.
    func testTheSliderRowRendersInsideTheNarrowestBar() throws {
        for typeSize in [DynamicTypeSize.large, .accessibility3] {
            let size = try idealSize(
                row(presets: [0.5, 1, 2], zoom: 1.8, showsSlider: true)
                    .frame(width: narrowestBar),
                language: .chinese,
                typeSize: typeSize)
            XCTAssertEqual(size.width, narrowestBar, accuracy: 1)
            XCTAssertGreaterThan(size.height, 20, "slider row collapsed at \(typeSize)")
        }
    }
}
