import SwiftUI

/// One clip, full screen. The tapped one.
///
/// It was a paged `TabView` — the whole story, one clip per page, swiped left
/// and right — and it is not any more: taken out in 1.3 rather than improved.
///
/// The gesture was invisible. A black full-bleed pager has no peeking edge and
/// no arrows, so the only people who found the other takes were the ones who
/// swiped by accident; the fix on the table was a page-dot row, which is a
/// signal for a gesture nobody was looking for in the first place. The story
/// page now lays the same clips out as a timeline you scroll, so "see the next
/// moment" already has an answer that is on screen and labelled. Two ways to
/// walk the same sequence, one of them hidden, is one too many.
///
/// `ClipDeck` stays: the story page and this screen have to agree on which
/// clip is which, and the deck is where that ordering lives.
struct ClipDeckReview: View {
    let deck: ClipDeck
    var challengeID: UUID?
    var momentCount = 0
    var clipLength: Challenge.ClipLength = .tiny
    var showsPrompt = true
    /// Which clip to show — whichever one was tapped. Named `startIndex` from
    /// when it was the first page of a pager; it is now the only one.
    let startIndex: Int
    /// Re-record a day. Takes the day rather than closing over one, because by
    /// the time it fires you may have swiped three moments away from where you
    /// came in.
    let onReRecord: (Int) -> Void

    init(
        deck: ClipDeck,
        challengeID: UUID? = nil,
        momentCount: Int = 0,
        clipLength: Challenge.ClipLength = .tiny,
        showsPrompt: Bool = true,
        startIndex: Int,
        onReRecord: @escaping (Int) -> Void
    ) {
        self.deck = deck
        self.challengeID = challengeID
        self.momentCount = momentCount
        self.clipLength = clipLength
        self.showsPrompt = showsPrompt
        self.startIndex = startIndex
        self.onReRecord = onReRecord
    }

    var body: some View {
        Group {
            if let clip = deck.clips.indices.contains(startIndex)
                ? deck.clips[startIndex] : nil {
                // Always live: one clip, one player. The pager needed a
                // three-page window to keep fifteen looping `AVPlayer`s off the
                // phone at once (three people, five moments); with the swipe
                // gone that budget went too, and `ClipDeck.liveIndices` with it.
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
            overlayText: clip.overlayText,
            captionSticker: clip.captionSticker,
            clipLength: clipLength,
            showsPrompt: showsPrompt,
            isLive: isLive,
            url: clip.url,
            recordedAt: clip.recordedAt,
            challengeID: challengeID,
            targetAuthorID: clip.authorID,
            onReRecord: { onReRecord(clip.day) })
    }
}
