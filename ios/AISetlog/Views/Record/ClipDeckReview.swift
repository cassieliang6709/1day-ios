import SwiftUI

/// The whole story, one clip per page, swiped left and right.
///
/// Tapping a tile used to open that clip and nothing else: to see the next
/// moment you closed the screen, found the next tile, and opened it again.
/// Three taps and two dissolves to move from 2pm to 3pm in your own day.
/// The clips are already a sequence — that's what a story is — so they get the
/// gesture a sequence gets.
///
/// The order comes from `ClipDeck` rather than from this view, because the
/// story page lays the same clips out as tiles and the two have to agree: if
/// each sorted its own way, tapping the third tile would open the fifth page.
struct ClipDeckReview: View {
    let deck: ClipDeck
    var challengeID: UUID?
    var momentCount = 0
    var clipLength: Challenge.ClipLength = .tiny
    var showsPrompt = true
    /// Which day to start on — whichever tile was tapped.
    let startIndex: Int
    /// Re-record a day. Takes the day rather than closing over one, because by
    /// the time it fires you may have swiped three moments away from where you
    /// came in.
    let onReRecord: (Int) -> Void

    @State private var index: Int

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
        _index = State(initialValue: startIndex)
    }

    /// The pages whose players exist. Three people filming five moments is
    /// fifteen clips, and fifteen looping `AVPlayer`s is not something to ask a
    /// phone to hold at once — so a page that isn't next to you is black.
    private var live: Set<Int> { deck.liveIndices(around: index) }

    var body: some View {
        TabView(selection: $index) {
            ForEach(Array(deck.clips.enumerated()), id: \.element.id) { position, clip in
                page(clip, isLive: live.contains(position))
                    .tag(position)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        .background(Color.black.ignoresSafeArea())
        // Again out here: a page's own preference doesn't reach the window
        // through the paging container, so without this the clock sits on the
        // video and the close button gets pushed 20 points down the frame.
        .statusBarHidden()
    }

    private func page(_ clip: DayClip, isLive: Bool) -> some View {
        ClipPreviewView(
            day: clip.day,
            slotTitle: clip.label,
            momentCount: momentCount,
            authorName: clip.authorName,
            overlayText: clip.overlayText,
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
