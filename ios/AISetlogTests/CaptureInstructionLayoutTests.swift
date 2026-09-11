import XCTest
import SwiftUI
@testable import AISetlog

@MainActor
final class CaptureInstructionLayoutTests: XCTestCase {
    func testIdleAndRecordingInstructionsGrowWithoutSqueezingAction() throws {
        // Includes a narrow landscape control-column candidate, not a claim
        // that the full camera page has adopted that layout.
        for width: CGFloat in [160, 240, 320, 640] {
            for text in ["轻点拍摄 · 3 秒", "Tap to record · 3 seconds", "Tap to stop"] {
                func render(_ size: DynamicTypeSize) throws -> CGImage {
                    let renderer = ImageRenderer(content:
                        CenteredCaptureControl(instruction: text) {
                            Circle().fill(.blue).frame(width: 66, height: 66)
                        }
                        .frame(width: width)
                        .background(.white)
                        .environment(\.dynamicTypeSize, size)
                    )
                    renderer.scale = 1
                    return try XCTUnwrap(renderer.cgImage)
                }
                let standard = try render(.large)
                let accessible = try render(.accessibility5)
                XCTAssertEqual(standard.width, Int(width))
                XCTAssertEqual(accessible.width, Int(width))
                XCTAssertGreaterThan(accessible.height, standard.height,
                                     "Large text must get space, not be scaled to one line: \(text)")
                XCTAssertGreaterThan(standard.height, 66)
            }
        }
    }
}
