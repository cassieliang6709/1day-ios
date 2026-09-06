import Foundation

/// A clip that was recorded but not filed into a story yet.
///
/// Free-form recording writes into the system temp directory, so a clip only
/// survives if something copies it somewhere permanent. Before drafts existed,
/// the two paths that couldn't file a clip (no stories yet, or no story with a
/// matching frame) just showed a toast — and the clip died with the screen.
/// A draft is that missing destination: somewhere a clip can wait until there
/// is a story to put it in.
struct ClipDraft: Codable, Identifiable, Equatable {
    let id: UUID
    /// File name inside the drafts directory — never a temp path, because a
    /// temp path is exactly what a draft exists to escape.
    var fileName: String
    var recordedAt: Date
    var orientation: Challenge.Orientation
    var overlayText: String?
    /// Cached at save time so the drafts list can show what it costs to keep.
    /// Drafts have no expiry yet, so the only thing stopping them from filling
    /// the phone is the person looking at that number.
    var byteSize: Int64

    init(
        id: UUID = UUID(),
        fileName: String,
        recordedAt: Date = .now,
        orientation: Challenge.Orientation,
        overlayText: String? = nil,
        byteSize: Int64 = 0
    ) {
        self.id = id
        self.fileName = fileName
        self.recordedAt = recordedAt
        self.orientation = orientation
        self.overlayText = overlayText
        self.byteSize = byteSize
    }
}
