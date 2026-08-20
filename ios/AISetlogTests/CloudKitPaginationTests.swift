import CloudKit
import XCTest
@testable import AISetlog

/// A busy room accumulates interactions fast — seven moments, a few friends,
/// a handful of emoji each. `fetchInteractions` runs a CKQuery and CloudKit
/// caps how many records one query returns, handing back a cursor for the
/// rest. This checks the fetch follows that cursor instead of silently
/// returning a truncated room.
///
/// Slow (it writes a few hundred records and cleans them up) and needs iCloud.
final class CloudKitPaginationTests: XCTestCase {
    private let authorID = "test-paging-\(UUID().uuidString)"
    private var code: String?
    private var written: [CKRecord.ID] = []

    private var db: CKDatabase {
        CKContainer(identifier: CloudKitService.containerID).publicCloudDatabase
    }

    override func setUp() async throws {
        try await super.setUp()
        do {
            try await CloudKitService.ensureAccountAvailable()
        } catch {
            throw XCTSkip("Needs a simulator or device signed into iCloud: \(error)")
        }
        code = try await CloudKitService.createRoom(
            title: "Paging test", ownerID: authorID, ownerName: "Tester").code
    }

    override func tearDown() async throws {
        for chunk in stride(from: 0, to: written.count, by: 200).map({
            Array(written[$0..<min($0 + 200, written.count)])
        }) {
            _ = try? await db.modifyRecords(saving: [], deleting: chunk)
        }
        if let code {
            try? await CloudKitService.deleteMyRoomData(
                authorID: authorID, clips: [], reactions: [],
                commentIDs: [], roomCodes: [code])
        }
        try await super.tearDown()
    }

    func testEveryCommentInABusyRoomComesBack() async throws {
        let code = try XCTUnwrap(self.code)
        let total = 220

        var records: [CKRecord] = []
        for index in 0..<total {
            let record = CKRecord(
                recordType: "Comment", recordID: .init(recordName: UUID().uuidString))
            record["roomCode"] = code as CKRecordValue
            record["day"] = (index % 7 + 1) as CKRecordValue
            record["text"] = "comment \(index)" as CKRecordValue
            record["authorID"] = authorID as CKRecordValue
            record["authorName"] = "Tester" as CKRecordValue
            record["targetAuthorID"] = authorID as CKRecordValue
            record["createdAt"] = Date.now as CKRecordValue
            records.append(record)
            written.append(record.recordID)
        }
        for chunk in stride(from: 0, to: records.count, by: 100).map({
            Array(records[$0..<min($0 + 100, records.count)])
        }) {
            _ = try await db.modifyRecords(saving: chunk, deleting: [])
        }

        // The query index is eventually consistent, so wait for the count to
        // settle rather than reading once.
        var lastCount = -1
        var comments: [CloudKitService.RemoteComment] = []
        for _ in 0..<12 {
            comments = (try await CloudKitService.fetchInteractions(code: code)).comments
            if comments.count == total { break }
            if comments.count == lastCount, comments.count > 0 { break }
            lastCount = comments.count
            try? await Task.sleep(for: .seconds(5))
        }

        XCTAssertEqual(comments.count, total, "the fetch stopped at one page")
    }
}
