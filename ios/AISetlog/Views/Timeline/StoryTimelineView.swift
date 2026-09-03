import SwiftUI

/// Screen 4 — the vertical timeline. The heart of the app.
///
/// Every moment, from everyone, hangs off one line in the order the day
/// happened. A grid would say "here are seven tiles you filled in"; a line
/// says "here is a day, and here is where you and your friends were in it".
/// Empty positions stay on the line rather than disappearing, because the
/// shape of the day is the point — the gaps are part of the story.
struct StoryTimelineView: View {
    let challengeID: UUID

    @Environment(ChallengeStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    @State private var sheet: TimelineSheet?
    @State private var showFilm = false
    @State private var showEditPlan = false
    /// The beat between the last moment landing and the film assembling.
    @State private var celebrate = false

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system
    /// Timeline or contact sheet. Persisted, so the choice sticks.
    @AppStorage(StoryViewMode.storageKey) private var viewMode: StoryViewMode = .timeline

    private var challenge: Challenge? { store.challenge(challengeID) }

    enum TimelineSheet: Identifiable, Equatable {
        case record(day: Int)
        case preview(day: Int, authorID: String?)
        /// The whole moment rather than one person's take — everyone who
        /// filmed it, stacked. The grid opens this: a tile stands for the
        /// moment, so it should show what the moment ends up looking like.
        case moment(day: Int)

        var id: String {
            switch self {
            case .record(let day): "record-\(day)"
            case .preview(let day, let authorID): "preview-\(day)-\(authorID ?? "local")"
            case .moment(let day): "moment-\(day)"
            }
        }
    }

    var body: some View {
        ZStack {
            OneDayCanvas(seed: 2)

            if let challenge {
                timeline(challenge)
            }

            if celebrate { celebration }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(item: $sheet, content: sheetContent)
        .navigationDestination(isPresented: $showFilm) {
            if let challenge {
                FilmView(
                    challenge: challenge,
                    clips: store.recordedClips(for: challengeID))
            }
        }
        .sheet(isPresented: $showEditPlan) {
            if let challenge {
                EditPlanSheet(challenge: challenge) { title, moments in
                    store.updatePlan(challengeID, title: title, momentTitles: moments)
                }
            }
        }
        // The magic moment: the last slot lands → a tiny celebration → the
        // film assembles itself. No button to discover.
        .onChange(of: challenge?.isComplete) { wasComplete, isComplete in
            guard wasComplete == false, isComplete == true else { return }
            withAnimation(OneDay.Motion.pop) { celebrate = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                celebrate = false
                showFilm = true
            }
        }
    }

    // MARK: - Layout

    private func timeline(_ challenge: Challenge) -> some View {
        let clips = store.recordedClips(for: challengeID)
        let members = store.members(for: challengeID)

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                TimelineHeader(
                    challenge: challenge,
                    memberNames: members.map(\.name),
                    myName: account.account?.displayName,
                    progress: RoomProgress(
                        momentCount: challenge.cards.count,
                        clips: clips,
                        myID: account.account?.id ?? RoomProgress.soloAuthorID),
                    viewMode: $viewMode,
                    showsViewModeToggle: false,
                    isSyncing: store.syncing.contains(challenge.roomCode ?? ""),
                    syncError: store.syncError(for: challengeID))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)

                if challenge.isTimeOnly {
                    ForEach(challenge.cards) { card in
                        row(for: card, in: challenge, clips: clips, members: members)
                    }
                } else {
                    StoryGridView(
                        challenge: challenge,
                        clips: clips,
                        members: members,
                        myID: account.account?.id ?? "local",
                        // A tile in a story only you filmed is one clip, so it
                        // opens as a page in the day and you swipe on. In a
                        // shared room a tile is still the whole moment with
                        // everyone stacked in it, which isn't a page — that's
                        // what `.moment` is for, until the grid stops
                        // collapsing people into one tile.
                        onTapFilmed: { day, _ in
                            sheet = challenge.isShared
                                ? .moment(day: day)
                                : .preview(day: day, authorID: nil)
                        },
                        onTapEmpty: { day in sheet = .record(day: day) })
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) { navBar(challenge) }
        // A safe-area inset rather than an overlay, so the button stacks above
        // the shell's floating tab bar instead of hiding behind it, and the
        // scroll content insets itself by exactly the right amount.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            filmButton(challenge, clipCount: clips.count)
        }
        .sensoryFeedback(.success, trigger: challenge.recordedCount)
        .refreshable {
            if challenge.isShared { await store.syncRoom(challengeID) }
        }
        .task(id: challengeID) {
            guard challenge.isShared else { return }
            while !Task.isCancelled {
                await store.syncRoom(challengeID)
                do { try await Task.sleep(for: .seconds(10)) } catch { break }
            }
        }
    }

    /// One position in the day. In a shared room several friends can land on
    /// the same slot, so a row can hold more than one clip.
    @ViewBuilder
    private func row(
        for card: DayCard,
        in challenge: Challenge,
        clips: [DayClip],
        members: [(id: String, name: String)]
    ) -> some View {
        let schedule = StorySchedule(challenge)
        let presenter = ChallengePresenter(challenge: challenge)
        let slotClips = clips.filter { $0.day == card.day }
        let momentTitle = challenge.isTimeOnly ? "" : presenter.title(forSlot: card.day)
        let momentIcon = challenge.isTimeOnly
            ? "camera.fill"
            : MomentCatalog.icon(for: challenge.momentValue(forSlot: card.day))
        let isNext = card.day == nextSlot(in: challenge)
        let myID = account.account?.id ?? "local"
        let iHaveFilmed = slotClips.contains { $0.authorID == myID || $0.authorID == "local" }

        TimelineRow(
            stamp: TimelineStamp(
                label: schedule.railLabel(
                    forSlot: card.day, recordedAt: slotClips.first?.recordedAt),
                caption: schedule.railCaption(
                    forSlot: card.day, recordedAt: slotClips.first?.recordedAt),
                icon: challenge.isOneDay
                    ? schedule.dayPartIcon(recordedAt: slotClips.first?.recordedAt)
                    : nil,
                isEmphasized: isNext || !slotClips.isEmpty),
            isFirst: card.day == challenge.cards.first?.day,
            isLast: card.day == challenge.cards.last?.day,
            isFilled: !slotClips.isEmpty,
            isNext: isNext
        ) {
            ForEach(slotClips) { clip in
                TimelineClip(
                    momentTitle: momentTitle,
                    momentIcon: momentIcon,
                    state: .filmed(url: clip.url, recordedAt: clip.recordedAt),
                    authorName: clip.authorName ?? account.account?.displayName,
                    durationLabel: challenge.resolvedClipLength.secondsLabel,
                    reactions: clip.emoji,
                    mediaHeight: mediaHeight(for: challenge),
                    showsMomentTitle: !challenge.isTimeOnly,
                    onTap: { sheet = .preview(day: card.day, authorID: clip.authorID) })
            }

            // My own empty slots. Every one is tappable — a 1-day story never
            // locks a moment — but only the next one gets the loud treatment,
            // or the whole day reads as seven equally urgent to-dos.
            if !iHaveFilmed {
                TimelineClip(
                    momentTitle: momentTitle,
                    momentIcon: momentIcon,
                    state: isNext ? .mine : .upcoming,
                    authorName: account.account?.displayName,
                    durationLabel: challenge.resolvedClipLength.secondsLabel,
                    showsMomentTitle: !challenge.isTimeOnly,
                    onTap: { sheet = .record(day: card.day) })
            }

            // Friends who haven't filmed this slot yet.
            ForEach(pendingMembers(members, slotClips: slotClips, myID: myID), id: \.id) { member in
                TimelineClip(
                    momentTitle: momentTitle,
                    momentIcon: momentIcon,
                    state: .waiting(friend: member.name))
            }
        }
        .padding(.horizontal, 18)
    }

    /// Clips are cropped to a consistent band rather than shown at their true
    /// aspect. A day of full-height portrait frames turns the timeline into a
    /// feed you scroll forever; the point is to see the shape of a whole day
    /// in a few flicks.
    private func mediaHeight(for challenge: Challenge) -> CGFloat {
        challenge.resolvedOrientation == .landscape ? 104 : 124
    }

    private func pendingMembers(
        _ members: [(id: String, name: String)],
        slotClips: [DayClip],
        myID: String
    ) -> [(id: String, name: String)] {
        let filmed = Set(slotClips.compactMap(\.authorID))
        return members.filter { $0.id != myID && !filmed.contains($0.id) }
    }

    private func nextSlot(in challenge: Challenge) -> Int? {
        challenge.cards.first { $0.clipFileName == nil }?.day
    }

    // MARK: - Chrome

    private func navBar(_ challenge: Challenge) -> some View {
        HStack(spacing: 12) {
            IconBubble(systemName: "chevron.left") { dismiss() }

            Spacer()

            if challenge.isShared, let code = challenge.roomCode {
                ShareLink(item: shareText(code: code, challenge: challenge)) {
                    Label(Strings.inviteLabel, systemImage: "person.badge.plus")
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.oneDayBlue)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                        .oneDaySoftShadow(strength: 0.5)
                }
            }

            Menu {
                if !challenge.isTimeOnly {
                    Button(Strings.editPlan, systemImage: "pencil") { showEditPlan = true }
                }
                Button(
                    challenge.isShared ? Strings.leaveRoom : Strings.deleteChallenge,
                    systemImage: "trash",
                    role: .destructive
                ) {
                    store.delete(challengeID)
                    dismiss()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(OneDay.ink)
                    .frame(width: 38, height: 38)
                    .background(.regularMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1))
                    .oneDaySoftShadow(strength: 0.5)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    /// Floats over the timeline once there's anything to watch — a friend who
    /// joins late can see the film before filming their own moment. With
    /// nothing to watch it collapses to bare tab-bar clearance.
    @ViewBuilder
    private func filmButton(_ challenge: Challenge, clipCount: Int) -> some View {
        if clipCount == 0 {
            // Nothing to watch yet — still reserve room for the tab bar.
            Color.clear.frame(height: OneDay.tabBarClearance)
        } else {
            Button { showFilm = true } label: {
                Label(
                    challenge.isComplete
                        ? Strings.makeTheFilm
                        : Strings.previewTheFilm(clipCount),
                    systemImage: "film.stack.fill")
            }
            .buttonStyle(.primaryAction)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            // The clearance sits *inside* the scrim, so timeline cards scrolling
            // past fade out under the button instead of reappearing beside the
            // tab bar.
            .padding(.bottom, OneDay.tabBarClearance)
            .background {
                LinearGradient(
                    colors: [OneDay.canvas.opacity(0), OneDay.canvas.opacity(0.96), OneDay.canvas],
                    startPoint: .top, endPoint: .center)
                    // Run past the home indicator, or clips scrolling out the
                    // bottom peek through under the tab bar.
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)
            }
        }
    }

    private var celebration: some View {
        VStack(spacing: 14) {
            OneDayBuddy(size: 78, isWorking: true)
            Text(Strings.yourFilmIsHere)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OneDay.brand.opacity(0.96).ignoresSafeArea())
        .transition(.opacity)
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetContent(_ presented: TimelineSheet) -> some View {
        switch presented {
        case .record(let day):
            RecordClipView(
                day: day,
                slotTitle: slotTitle(for: day),
                clipLength: challenge?.resolvedClipLength ?? .tiny,
                showsPrompt: challenge?.isTimeOnly != true,
                orientation: challenge?.resolvedOrientation ?? .portrait
            ) { url, overlayText in
                store.saveClip(
                    from: url, day: day, challengeID: challengeID, overlayText: overlayText)
            }

        case .moment(let day):
            let slotClips = store.recordedClips(for: challengeID).filter { $0.day == day }
            StitchedMomentPreview(
                clips: slotClips,
                day: day,
                slotTitle: slotTitle(for: day),
                momentCount: challenge?.cards.count ?? 0,
                clipLength: challenge?.resolvedClipLength ?? .tiny,
                challengeID: challengeID,
                showsPrompt: challenge?.isTimeOnly != true,
                myID: account.account?.id ?? "local"
            ) {
                sheet = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    sheet = .record(day: day)
                }
            }

        case .preview(let day, let targetAuthorID):
            // The tapped clip opens, and the rest of the story is a swipe away
            // either side of it.
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
                ) { retakeDay in
                    sheet = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        sheet = .record(day: retakeDay)
                    }
                }
            }
        }
    }

    private func slotTitle(for day: Int) -> String? {
        guard let challenge, !challenge.isTimeOnly else { return nil }
        return ChallengePresenter(challenge: challenge).title(forSlot: day)
    }

    private func shareText(code: String, challenge: Challenge) -> String {
        let presenter = ChallengePresenter(challenge: challenge)
        if challenge.recordedCount > 0 {
            return Strings.shareMessageCaptured(
                first: presenter.title(forSlot: 1),
                title: presenter.displayTitle, code: code)
        }
        return Strings.shareMessageInvite(title: presenter.displayTitle, code: code)
    }
}
