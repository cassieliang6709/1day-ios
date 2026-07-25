import SwiftUI

struct ChallengeBoardView: View {
    let challengeID: UUID

    @Environment(ChallengeStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var sheet: BoardSheet?
    @State private var showFinalReel = false
    /// Brief "your film is here" beat between the last clip and the reel.
    @State private var celebrate = false

    /// Bound only so a language change re-renders the view.
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var challenge: Challenge? { store.challenge(challengeID) }

    enum BoardSheet: Identifiable {
        case record(day: Int)
        case preview(day: Int)

        var id: String {
            switch self {
            case .record(let day): "record-\(day)"
            case .preview(let day): "preview-\(day)"
            }
        }
    }

    var body: some View {
        Group {
            if let challenge {
                board(for: challenge)
            }
        }
        .navigationTitle(challenge?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .tint(BoardTheme.primary)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    #if DEBUG
                    Button(Strings.fillDemoClips) {
                        store.fillWithDemoClips(challengeID: challengeID)
                    }
                    #endif
                    Button(Strings.deleteChallenge, role: .destructive) {
                        store.delete(challengeID)
                        dismiss()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .fullScreenCover(item: $sheet) { presented in
            switch presented {
            case .record(let day):
                RecordClipView(
                    day: day,
                    slotTitle: slotTitle(for: day),
                    clipLength: challenge?.resolvedClipLength ?? .tiny
                ) { url, overlayText in
                    store.saveClip(
                        from: url,
                        day: day,
                        challengeID: challengeID,
                        overlayText: overlayText)
                }
            case .preview(let day):
                if let card = challenge?.cards.first(where: { $0.day == day }),
                   let url = store.clipURL(for: card, in: challengeID) {
                    ClipPreviewView(
                        day: day,
                        slotTitle: slotTitle(for: day),
                        authorName: account.account?.displayName,
                        overlayText: card.overlayText,
                        clipLength: challenge?.resolvedClipLength ?? .tiny,
                        url: url,
                        recordedAt: card.recordedAt,
                        challengeID: challengeID
                    ) {
                        sheet = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                            sheet = .record(day: day)
                        }
                    }
                }
            }
        }
        .navigationDestination(isPresented: $showFinalReel) {
            if let challenge {
                FinalReelView(
                    challenge: challenge,
                    clips: store.recordedClips(for: challengeID))
            }
        }
        // The magic moment: the last slot lands → a tiny celebration → the
        // film assembles itself. No button to discover, no thought required.
        .onChange(of: challenge?.isComplete) { wasComplete, isComplete in
            guard wasComplete == false, isComplete == true else { return }
            withAnimation(.snappy(duration: 0.25)) { celebrate = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                celebrate = false
                showFinalReel = true
            }
        }
        .overlay {
            if celebrate {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.white)
                    Text(Strings.yourFilmIsHere)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.oneDayBlue.opacity(0.92).ignoresSafeArea())
                .transition(.opacity)
            }
        }
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-demoReel") {
                store.fillWithDemoClips(challengeID: challengeID)
                showFinalReel = true
            }
            if ProcessInfo.processInfo.arguments.contains("-demoPreview") {
                store.fillWithDemoClips(challengeID: challengeID)
                sheet = .preview(day: 2)
            }
        }
        #endif
    }

    // MARK: - Board

    private func slotTitle(for day: Int) -> String? {
        challenge.map { ChallengePresenter(challenge: $0).title(forSlot: day) }
    }

    private func board(for challenge: Challenge) -> some View {
        let presenter = ChallengePresenter(challenge: challenge)
        return ScrollView {
            VStack(spacing: 20) {
                progressHeader(challenge)

                if challenge.isShared {
                    rosterHeader(challenge)
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                    spacing: 8
                ) {
                    ForEach(challenge.cards) { card in
                        DayCardView(
                            card: card,
                            status: challenge.cardStatus(card),
                            title: presenter.title(forSlot: card.day),
                            isOneDay: challenge.isOneDay,
                            clipURL: store.clipURL(for: card, in: challengeID)
                        )
                        .onTapGesture { handleTap(card, challenge: challenge) }
                    }
                }

                // Show for a shared room as soon as anyone has contributed, so a
                // freshly-joined member can watch before recording their own.
                if challenge.recordedCount > 0 || !store.recordedClips(for: challengeID).isEmpty {
                    Button {
                        showFinalReel = true
                    } label: {
                        Label(
                            challenge.isComplete
                                ? Strings.createFilm(oneDay: challenge.isOneDay)
                                : Strings.previewFilm(
                                    challenge.recordedCount, challenge.cards.count,
                                    unitPlural: presenter.unitNamePlural),
                            systemImage: "film.stack.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BoardTheme.primary)
                    .controlSize(.large)
                    .shadow(color: BoardTheme.deep.opacity(0.28), radius: 12, y: 6)
                }
            }
            .padding()
        }
        .background(BoardBackground())
        .sensoryFeedback(.success, trigger: challenge.recordedCount)
        .refreshable {
            if challenge.isShared { await store.syncRoom(challengeID) }
        }
        .task(id: challengeID) {
            if challenge.isShared { await store.syncRoom(challengeID) }
        }
    }

    /// Member chips + a "share code" pill for a shared room.
    private func rosterHeader(_ challenge: Challenge) -> some View {
        let members = store.members(for: challengeID)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(Strings.membersInRoom(members.count), systemImage: "person.2.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(BoardTheme.primaryText)
                Spacer()
                if store.syncing.contains(challenge.roomCode ?? "") {
                    ProgressView()
                        .controlSize(.small)
                        .tint(BoardTheme.primary)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(members, id: \.id) { member in
                        MemberChip(name: member.name)
                    }
                }
            }
            if let code = challenge.roomCode {
                ShareLink(item: shareText(code: code, challenge: challenge)) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text(Strings.invitePill(hasClips: challenge.recordedCount > 0))
                            + Text(code).font(.subheadline.bold().monospaced())
                        Spacer()
                    }
                    .font(.subheadline)
                    .foregroundStyle(BoardTheme.primaryText)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(BoardTheme.cardStrong, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(BoardTheme.stroke, lineWidth: 1)
                    )
                }
            }
        }
        .padding(16)
        .background(BoardTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(BoardTheme.stroke, lineWidth: 1)
        )
    }

    private func shareText(code: String, challenge: Challenge) -> String {
        if challenge.recordedCount > 0 {
            return Strings.shareMessageCaptured(
                first: ChallengePresenter(challenge: challenge).title(forSlot: 1),
                title: challenge.title, code: code)
        }
        return Strings.shareMessageInvite(title: challenge.title, code: code)
    }

    private func progressHeader(_ challenge: Challenge) -> some View {
        let presenter = ChallengePresenter(challenge: challenge)
        return HStack(spacing: 16) {
            ProgressRing(recorded: challenge.recordedCount, total: challenge.cards.count)

            VStack(alignment: .leading, spacing: 4) {
                Text(progressTitle(challenge))
                    .font(.headline)
                    .foregroundStyle(BoardTheme.primaryText)
                Text(challenge.recordedCount == 7
                    ? Strings.allClipsIn
                    : Strings.recordedProgress(
                        challenge.recordedCount,
                        secondsLabel: challenge.resolvedClipLength.secondsLabel,
                        unitPlural: presenter.unitNamePlural))
                    .font(.subheadline)
                    .foregroundStyle(BoardTheme.secondaryText)
            }
            Spacer()
        }
        .padding(16)
        .background(BoardTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(BoardTheme.stroke, lineWidth: 1)
        )
        .shadow(color: BoardTheme.deep.opacity(0.18), radius: 16, y: 8)
    }

    private func progressTitle(_ challenge: Challenge) -> String {
        if challenge.isOneDay {
            return challenge.isComplete ? Strings.oneDayComplete : Strings.sevenMoments
        }
        if challenge.isComplete { return Strings.weekComplete }
        return challenge.currentDay > 7 ? Strings.weekComplete : Strings.dayOf(challenge.currentDay)
    }

    private func handleTap(_ card: DayCard, challenge: Challenge) {
        switch challenge.cardStatus(card) {
        case .today, .missed:
            sheet = .record(day: card.day)
        case .done:
            sheet = .preview(day: card.day)
        case .locked:
            break
        }
    }
}

