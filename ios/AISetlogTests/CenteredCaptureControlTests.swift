import XCTest
import SwiftUI
@testable import AISetlog

@MainActor
final class CenteredCaptureControlTests: XCTestCase {
    func testActionPixelsStayCenteredAcrossWidthsLanguagesAndTypeSizes() throws {
        for width in [240, 320, 640] {
            for instruction in ["轻点停止", "Tap to stop", "Tap to stop recording this moment"] {
                for typeSize in [DynamicTypeSize.large, .accessibility3] {
                    let view = CenteredCaptureControl(instruction: instruction) {
                        Circle().fill(.red).frame(width: 68, height: 68)
                    }
                    .frame(width: CGFloat(width))
                    .padding(.vertical, 4)
                    .background(.white)
                    .environment(\.dynamicTypeSize, typeSize)
                    .environment(\.colorScheme, .light)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 1
                    let image = try XCTUnwrap(renderer.cgImage)
                    let bytesPerRow = image.width * 4
                    var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
                    let context = try XCTUnwrap(CGContext(
                        data: &pixels, width: image.width, height: image.height,
                        bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                    var xs: [Int] = []
                    var ys: [Int] = []
                    for y in 0..<image.height {
                        for x in 0..<image.width {
                            let i = y * bytesPerRow + x * 4
                            if pixels[i] > 200 && pixels[i + 1] < 80 && pixels[i + 2] < 80 {
                                xs.append(x)
                                ys.append(y)
                            }
                        }
                    }
                    let minX = try XCTUnwrap(xs.min())
                    let maxX = try XCTUnwrap(xs.max())
                    XCTAssertEqual(Double(minX + maxX) / 2, Double(image.width - 1) / 2, accuracy: 1,
                                   "width=\(width), text=\(instruction), size=\(typeSize)")
                    XCTAssertGreaterThan(maxX - minX, 64, "Action must not be squeezed")
                    XCTAssertGreaterThan(try XCTUnwrap(ys.max()) - XCTUnwrap(ys.min()), 64)
                    XCTAssertGreaterThan(image.height, 80, "Instruction needs its own space")
                }
            }
        }
    }
}
