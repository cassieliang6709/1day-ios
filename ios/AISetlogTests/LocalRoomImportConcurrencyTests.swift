import XCTest
@testable import AISetlog

@MainActor
final class LocalRoomImportConcurrencyTests: XCTestCase {
    private final class Gate {
        var continuation: CheckedContinuation<URL, Never>?
        func prepare(_ input: URL) async -> URL {
            await withCheckedContinuation { continuation = $0 }
        }
        func waitUntilStarted() async {
            while continuation == nil { await Task.yield() }
        }
        func finish(_ output: URL) { continuation?.resume(returning: output); continuation = nil }
    }

    func testCancellationAfterPreparationAndConcurrentReplacementAreFailClosed() async throws {
        let runtime = try await LocalRoomRuntime.make(memberCount: 2, chinese: false)
        defer { runtime.close() }
        let clips = runtime.store.recordedClips(for: runtime.challengeID)
        let target = try XCTUnwrap(clips.first?.authorID)
        let input = try XCTUnwrap(clips.first?.url)
        let gate = Gate()
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("import-cancel-\(UUID()).mov")
        try Data("mock prepared output".utf8).write(to: output)
        defer { try? FileManager.default.removeItem(at: output) }
        let task = Task { try await runtime.replaceClip(authorID: target, from: input, prepare: gate.prepare) }
        await gate.waitUntilStarted()
        var secondPreparationCalled = false
        do {
            try await runtime.replaceClip(authorID: target, from: input, prepare: { _ in
                secondPreparationCalled = true
                return input
            })
            XCTFail("overlapping import accepted")
        } catch {}
        XCTAssertFalse(secondPreparationCalled)
        task.cancel()
        gate.finish(output)
        do { try await task.value; XCTFail("cancelled import committed") } catch {}
        XCTAssertEqual(runtime.store.recordedClips(for: runtime.challengeID).map(\.url), clips.map(\.url))
        XCTAssertTrue(FileManager.default.fileExists(atPath: input.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        // Failure releases the busy guard; a later real import remains usable.
        try await runtime.replaceClip(authorID: target, from: input)
        XCTAssertNotEqual(runtime.store.recordedClips(for: runtime.challengeID).first?.url, input)
    }

    func testCloseDuringSuspendedPreparationDoesNotAffectAnotherRuntime() async throws {
        let first = try await LocalRoomRuntime.make(memberCount: 2, chinese: false)
        let second = try await LocalRoomRuntime.make(memberCount: 2, chinese: false)
        defer { first.close(); second.close() }
        let firstClip = try XCTUnwrap(first.store.recordedClips(for: first.challengeID).first)
        let secondClips = second.store.recordedClips(for: second.challengeID)
        let input = try XCTUnwrap(secondClips.first?.url)
        let gate = Gate()
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("import-close-\(UUID()).mov")
        try Data("mock prepared output".utf8).write(to: output)
        defer { try? FileManager.default.removeItem(at: output) }
        let task = Task { try await first.replaceClip(authorID: try XCTUnwrap(firstClip.authorID), from: input, prepare: gate.prepare) }
        await gate.waitUntilStarted()
        first.close()
        gate.finish(output)
        do { try await task.value; XCTFail("closed runtime committed") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.storage.root.path))
        XCTAssertEqual(second.store.recordedClips(for: second.challengeID).map(\.url), secondClips.map(\.url))
        XCTAssertTrue(FileManager.default.fileExists(atPath: input.path))
    }
}
