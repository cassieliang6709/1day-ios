import SwiftUI

struct ClipDeckReview: View {
    let deck: ClipDeck
    var challengeID: UUID?
    var momentCount = 0
    var clipLength: Challenge.ClipLength = .tiny
    var showsPrompt = true
    let startIndex: Int
    let onRecord: (Int, TakeTarget) -> Void

    init(
        deck: ClipDeck,
        challengeID: UUID? = nil,
        momentCount: Int = 0,
        clipLength: Challenge.ClipLength = .tiny,
        showsPrompt: Bool = true,
        startIndex: Int,
        onRecord: @escaping (Int, TakeTarget) -> Void
    ) {
        self.deck = deck
        self.challengeID = challengeID
        self.momentCount = momentCount
        self.clipLength = clipLength
        self.showsPrompt = showsPrompt
        self.startIndex = startIndex
        self.onRecord = onRecord
    }

    var body: some View {
        Group {
            if let clip = deck.clips.indices.contains(startIndex)
                ? deck.clips[startIndex] : nil {
                page(clip, isLive: true)
            } else {
                Color.black
            }
        }
        .ignoresSafeArea()
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
    }

    private func page(_ clip: DayClip, isLive: Bool) -> some View {
        ClipPreviewView(
            day: clip.day,
            slotTitle: clip.label,
            momentCount: momentCount,
            authorName: clip.authorName,
            captions: clip.captions,
            clipLength: clipLength,
            showsPrompt: showsPrompt,
            isLive: isLive,
            url: clip.url,
            recordedAt: clip.recordedAt,
            challengeID: challengeID,
            targetAuthorID: clip.authorID,
            takeID: clip.takeID,
            onReRecord: { onRecord(clip.day, .replace(clip.takeID)) },
            onAddTake: { onRecord(clip.day, .append) })
    }
}
