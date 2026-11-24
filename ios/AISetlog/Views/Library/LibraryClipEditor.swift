import SwiftUI

struct LibraryClipEditor: View {
    let clip: LibraryClip
    let draft: ClipDraft?
    let onOpenStory: (UUID) -> Void
    let onSend: (ClipDraft) -> Void
    let onDelete: (ClipDraft) -> Void

    @Environment(ClipDraftStore.self) private var draftStore

    var body: some View {
        switch clip.source {
        case .story(let id, _, _):
            ClipPreviewView(
                day: clip.clip.day,
                slotTitle: clip.clip.label,
                authorName: clip.authorName,
                captions: clip.clip.captions,
                showsPrompt: clip.clip.label != nil,
                url: clip.url,
                recordedAt: clip.recordedAt,
                challengeID: id,
                targetAuthorID: clip.clip.authorID,
                takeID: clip.clip.takeID,
                onReRecord: nil,
                extraActions: [.init(
                    id: "library-day-open-story", symbol: "rectangle.stack",
                    title: Strings.libraryOpenStory) { onOpenStory(id) }])
        case .draft(let id):
            ClipPreviewView(
                day: 1,
                captions: draft?.captions ?? clip.clip.captions,
                showsPrompt: false,
                url: clip.url,
                recordedAt: clip.recordedAt,
                onReRecord: nil,
                onDraftCaptions: { draftStore.updateCaptions($0, draftID: id) },
                extraActions: draftActions)
        }
    }

    private var draftActions: [ClipPreviewView.ExtraAction] {
        guard let draft else { return [] }
        return [
            .init(
                id: "library-day-send", symbol: "tray.and.arrow.down",
                title: Strings.libraryFileIntoStory) { onSend(draft) },
            .init(
                id: "library-day-delete", symbol: "trash",
                title: Strings.deleteDraft, isDestructive: true) { onDelete(draft) },
        ]
    }
}
