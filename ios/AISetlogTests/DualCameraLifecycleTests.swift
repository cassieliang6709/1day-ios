import AVFoundation
import XCTest
@testable import AISetlog

@MainActor
final class DualCameraLifecycleTests: XCTestCase {
    func testDisablingDualCameraAfterPreviewDisconnects() async throws {
        let recorder = ClipRecorder()
        try XCTSkipUnless(recorder.supportsDualCamera, "Requires a physical MultiCam device")
        await recorder.configure()
        XCTAssertEqual(recorder.state, .ready)
        guard recorder.state == .ready else { return }
        defer { recorder.teardown() }

        recorder.setDualCamera(true)
        try await waitUntil { recorder.isDualCamera }
        let layer = AVCaptureVideoPreviewLayer()
        layer.setSessionWithNoConnection(recorder.session)
        recorder.attachSecondaryPreview(layer)
        try await waitUntil { layer.connection != nil }
        let connection = try XCTUnwrap(layer.connection)
        XCTAssertTrue(recorder.session.connections.contains { $0 === connection })

        layer.session = nil
        XCTAssertFalse(recorder.session.connections.contains { $0 === connection })
        recorder.setDualCamera(false)
        try await waitUntil { !recorder.isDualCamera }
        XCTAssertNil(layer.connection)

        recorder.setDualCamera(true)
        try await waitUntil { recorder.isDualCamera }
        recorder.setDualCamera(false)
        try await waitUntil { !recorder.isDualCamera }
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Camera configuration did not reach the expected state")
        throw NSError(domain: "DualCameraLifecycleTests", code: 1)
    }
}
