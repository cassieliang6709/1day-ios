import SwiftUI

extension StoryTimelineView {
    @ViewBuilder
    func sheetContent(_ presented: TimelineSheet) -> some View {
        switch presented {
        case .record(let day, let take):
            RecordClipView(
                day: day,
                slotTitle: slotTitle(for: day),
                momentCount: momentCountOnScreen,
                clipLength: challenge?.resolvedClipLength ?? .tiny,
                showsPrompt: showsPrompt(for: day),
                orientation: challenge?.resolvedOrientation ?? .portrait,
                lockedCamera: challenge?.cameraStyle
            ) { url, overlayText in
                let wasComplete = dayIsComplete
                store.saveClip(
                    from: url, day: day, challengeID: challengeID, overlayText: overlayText,
                    take: take)
                if !wasComplete, dayIsComplete { celebrateMyFinish() }
            }

        case .clip(let day, let targetAuthorID, let takeID):
            clipReview(day: day, authorID: targetAuthorID, takeID: takeID)

        case .preview(let day, let targetAuthorID):
            let deck = ClipDeck(
                clips: store.recordedClips(for: challengeID),
                momentCount: challenge?.cards.count ?? 0,
                myID: account.account?.id ?? RoomProgress.soloAuthorID)
            if let start = deck.index(ofDay: day, authorID: targetAuthorID) {
                ClipDeckReview(
                    deck: deck,
                    challengeID: challengeID,
                    momentCount: challenge?.cards.count ?? 0,
                    clipLength: challenge?.resolvedClipLength ?? .tiny,
                    showsPrompt: challenge?.isTimeOnly != true,
                    startIndex: start
                ) { retakeDay, take in
                    sheet = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        sheet = .record(day: retakeDay, take: take)
                    }
                }
            }
        }
    }

    @ViewBuilder
    func clipReview(day: Int, authorID: String?, takeID: UUID?) -> some View {
        let deck = ClipDeck(
            clips: store.recordedClips(for: challengeID),
            momentCount: challenge?.cards.count ?? 0,
            myID: account.account?.id ?? RoomProgress.soloAuthorID)
        if let start = deck.index(ofDay: day, authorID: authorID, takeID: takeID) {
            ClipDeckReview(
                deck: deck,
                challengeID: challengeID,
                momentCount: momentCountOnScreen,
                clipLength: challenge?.resolvedClipLength ?? .tiny,
                showsPrompt: showsPrompt(for: day),
                startIndex: start
            ) { retakeDay, take in
                sheet = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    sheet = .record(day: retakeDay, take: take)
                }
            }
        } else {
            Color.black.ignoresSafeArea().onTapGesture { sheet = nil }
        }
    }

    func slotTitle(for day: Int) -> String? {
        guard let challenge, !challenge.isTimeOnly else { return nil }
        return ChallengePresenter(challenge: challenge).slotLabel(forSlot: day)
    }

    func showsPrompt(for day: Int) -> Bool {
        guard let challenge, !challenge.isTimeOnly else { return false }
        return !challenge.isShared || slotTitle(for: day) != nil
    }

    var momentCountOnScreen: Int {
        guard let challenge else { return 0 }
        return challenge.isShared ? 0 : challenge.cards.count
    }

    func shareText(code: String, challenge: Challenge) -> String {
        let presenter = ChallengePresenter(challenge: challenge)
        if challenge.recordedCount > 0 {
            return Strings.shareMessageCaptured(
                first: presenter.title(forSlot: 1),
                title: presenter.displayTitle, code: code)
        }
        return Strings.shareMessageInvite(title: presenter.displayTitle, code: code)
    }
}
