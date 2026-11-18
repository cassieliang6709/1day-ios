import XCTest
import SwiftUI
@testable import AISetlog

@MainActor
final class ZoomControlRowTests: XCTestCase {
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

    func testTheEnglishRowFitsTheNarrowestControlBarToo() throws {
        for typeSize in DynamicTypeSize.allCases {
            let size = try idealSize(
                row(presets: [0.5, 1, 2], zoom: 1),
                language: .english,
                typeSize: typeSize)
            XCTAssertLessThanOrEqual(size.width, narrowestBar, "English row overflows at \(typeSize)")
        }
    }

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
