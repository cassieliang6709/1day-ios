import AVFoundation
import XCTest
@testable import AISetlog

@MainActor
final class LockedCaptureImporterTests: XCTestCase {
    func testHandoffSurvivesRelaunchAndDoesNotResurrectDeletedDrafts() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "LockedCaptureImporterTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manifest = LockedCaptureManifest(id: UUID(), recordedAt: Date(timeIntervalSince1970: 100), landscape: false)
        let generated = await ClipFixtureFactory.makeClip(index: 0)
        let movie = try XCTUnwrap(generated)
        defer { try? FileManager.default.removeItem(at: movie) }
        try FileManager.default.copyItem(at: movie, to: directory.appendingPathComponent(manifest.movieName))
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent(manifest.manifestName))
        let repository = UserDefaultsClipDraftRepository(defaults: defaults)
        let store = ClipDraftStore(repository: repository)
        try await LockedCaptureImporter.importDirectory(directory, into: store, receipts: defaults)
        let draft = try XCTUnwrap(store.drafts.first)
        defer { store.remove(draft) }
        XCTAssertEqual(draft.id, manifest.id)
        XCTAssertEqual(draft.recordedAt, manifest.recordedAt)
        XCTAssertEqual(draft.orientation, .portrait)
        let restored = ClipDraftStore(repository: repository)
        XCTAssertEqual(restored.drafts.map(\.id), [manifest.id])
        let tracks = try await AVURLAsset(url: restored.url(for: draft)).loadTracks(withMediaType: .video)
        XCTAssertFalse(tracks.isEmpty)
        try await LockedCaptureImporter.importDirectory(directory, into: restored, receipts: defaults)
        XCTAssertEqual(restored.count, 1)
        restored.remove(draft)
        try await LockedCaptureImporter.importDirectory(directory, into: restored, receipts: defaults)
        XCTAssertTrue(restored.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(manifest.movieName).path))
    }

    func testCorruptHandoffIsKeptForRetryWithoutCreatingADraft() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "LockedCaptureImporterTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ClipDraftStore(repository: UserDefaultsClipDraftRepository(defaults: defaults))
        let manifest = LockedCaptureManifest(id: UUID(), recordedAt: .now, landscape: false)
        let movie = directory.appendingPathComponent(manifest.movieName)
        try Data([0, 1, 2]).write(to: movie)
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent(manifest.manifestName))
        do {
            try await LockedCaptureImporter.importDirectory(directory, into: store, receipts: defaults)
            XCTFail("Invalid movie was imported")
        } catch {
            XCTAssertTrue(store.isEmpty)
            XCTAssertTrue(FileManager.default.fileExists(atPath: movie.path))
            XCTAssertNil(defaults.stringArray(forKey: "capture.importedIDs.v1"))
        }
    }

    func testCompletedMovieIsRecoveredWhenExtensionStopsBeforeWritingManifest() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "LockedCaptureImporterTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ClipDraftStore(repository: UserDefaultsClipDraftRepository(defaults: defaults))
        let id = UUID()
        let generated = await ClipFixtureFactory.makeClip(index: 3)
        let source = try XCTUnwrap(generated)
        defer { try? FileManager.default.removeItem(at: source) }
        try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent("\(id).mov"))
        try await LockedCaptureImporter.importDirectory(directory, into: store, receipts: defaults)
        let draft = try XCTUnwrap(store.drafts.first)
        defer { store.remove(draft) }
        XCTAssertEqual(draft.id, id)
        XCTAssertEqual(draft.orientation, .portrait)
        try await LockedCaptureImporter.importDirectory(directory, into: store, receipts: defaults)
        XCTAssertEqual(store.count, 1)
    }
}
