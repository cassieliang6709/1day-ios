import SwiftUI

/// Screen 4 — the story page. The heart of the app.
///
/// The page has exactly one next thing on it. Every moment used to be a tile
/// of the same size, weight and tappability, so a day asked seven questions at
/// once and answered none of them — and a film button floated over the bottom
/// of it asking an eighth. Now the day reads top to bottom: how far it has got,
/// the one moment to film next (or the film, once there's nothing left to
/// film), then what happened, then what hasn't.
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
        let myID = account.account?.id ?? RoomProgress.soloAuthorID
        let agenda = StoryAgenda(momentCount: challenge.cards.count, clips: clips, myID: myID)
        // Only ever built for a shared room. Everything it draws — the roster,
        // who filmed, who we're waiting on — is a sentence about other people,
        // and a solo story has none to write about.
        let cast = challenge.isShared
            ? RoomCast(
                members: members, clips: clips,
                momentCount: challenge.cards.count,
                myID: myID, myName: account.account?.displayName)
            : nil

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                TimelineHeader(
                    challenge: challenge,
                    cast: cast,
                    progress: RoomProgress(
                        momentCount: challenge.cards.count,
                        clips: clips,
                        myID: myID),
                    viewMode: $viewMode,
                    showsViewModeToggle: false,
                    isSyncing: store.syncing.contains(challenge.roomCode ?? ""))

                StoryProgressBar(filmed: agenda.filmedCount, total: agenda.total)

                nextCard(
                    challenge, agenda: agenda, clipCount: clips.count,
                    roomNote: cast?.filmedNote)

                if !agenda.filmed.isEmpty {
                    section(Strings.filmedHeader) {
                        StoryGridView(
                            challenge: challenge,
                            clips: clips,
                            members: members,
                            myID: myID,
                            slots: agenda.filmed,
                            // A moment in a story only you filmed is one clip,
                            // so it opens as a page in the day and you swipe
                            // on. In a shared room it is still the whole moment
                            // with everyone stacked in it, which isn't a page —
                            // that's what `.moment` is for.
                            onTap: { day in
                                sheet = challenge.isShared
                                    ? .moment(day: day)
                                    : .preview(day: day, authorID: nil)
                            })
                    }
                }

                if !agenda.later.isEmpty {
                    section(Strings.stillOpenHeader) {
                        quietList(challenge, agenda: agenda)
                    }
                }

                // One line about who the room is waiting on, at the bottom
                // where what's missing belongs. It replaced a card under every
                // moment naming the friends who hadn't filmed it — the same
                // fact, restated once per slot per person.
                //
                // Silent once the day is full: the room got there, and a page
                // that has just offered you the film shouldn't also be tapping
                // its watch.
                if !agenda.isComplete, let note = cast?.waitingNote {
                    RoomNote(note: note, isPending: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            navBar(challenge, agenda: agenda, clipCount: clips.count)
        }
        // The floating tab bar is drawn over the whole stack, so the scroll
        // view reserves its own clearance rather than inheriting one.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: OneDay.tabBarClearance)
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

    private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: title)
            content()
        }
    }

    /// The page's one loud thing.
    @ViewBuilder
    private func nextCard(
        _ challenge: Challenge, agenda: StoryAgenda, clipCount: Int,
        roomNote: RoomCast.Note?
    ) -> some View {
        switch agenda.next {
        case .film(let slot):
            NextSlotCard(
                kind: .film(
                    title: slotHeadline(challenge, slot: slot),
                    icon: slotIcon(challenge, slot: slot),
                    slot: slot,
                    total: max(agenda.total, slot)),
                durationLabel: challenge.resolvedClipLength.secondsLabel,
                roomNote: roomNote
            ) {
                sheet = .record(day: slot)
            }

        case .watchTheFilm:
            NextSlotCard(kind: .watch(clipCount: clipCount)) { showFilm = true }
        }
    }

    /// Everything still open to me except the one on the card, as a list of
    /// what's coming rather than a wall of equal buttons.
    private func quietList(_ challenge: Challenge, agenda: StoryAgenda) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(agenda.later.enumerated()), id: \.element) { index, slot in
                if index > 0 {
                    Divider().overlay(OneDay.hairline).padding(.leading, 56)
                }
                QuietSlotRow(
                    momentTitle: slotHeadline(challenge, slot: slot),
                    momentIcon: slotIcon(challenge, slot: slot),
                    awaitingMine: agenda.isAwaitingMine(slot: slot)
                ) {
                    sheet = .record(day: slot)
                }
            }
        }
        .glassSurface(radius: OneDay.Radius.card)
    }

    /// A story recorded by time has no prompts, so its moments are called by
    /// their place in the day. Falling back to the prompt title would print
    /// "Day 3" down a story that lasts one day.
    private func slotHeadline(_ challenge: Challenge, slot: Int) -> String {
        challenge.isTimeOnly
            ? Strings.lockedSlot(oneDay: challenge.isOneDay, day: slot)
            : ChallengePresenter(challenge: challenge).title(forSlot: slot)
    }

    private func slotIcon(_ challenge: Challenge, slot: Int) -> String {
        challenge.isTimeOnly
            ? "camera.fill"
            : MomentCatalog.icon(for: challenge.momentValue(forSlot: slot))
    }

    // MARK: - Chrome

    private func navBar(
        _ challenge: Challenge, agenda: StoryAgenda, clipCount: Int
    ) -> some View {
        let syncError = store.syncError(for: challengeID)

        return HStack(spacing: 12) {
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
                // Watching an unfinished day is a real thing to want — a friend
                // who joins late can see it before filming — but it isn't the
                // page's answer to "what now", so it stops being a button and
                // becomes a menu item. Once the day is full the next-up card
                // *is* the film, and a second entry would be the same action
                // twice.
                if clipCount > 0, !agenda.isComplete {
                    Button(Strings.previewTheFilm(clipCount), systemImage: "film.stack") {
                        showFilm = true
                    }
                }

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

                // A sync failure used to print itself in red under the story's
                // title, where it competed with the day for attention and could
                // do nothing about itself. It belongs next to the retry.
                if let syncError {
                    Section {
                        Button(Strings.retrySync, systemImage: "arrow.clockwise") {
                            Task { await store.syncRoom(challengeID) }
                        }
                    } header: {
                        Text(syncError)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(OneDay.ink)
                    .frame(width: 38, height: 38)
                    .background(.regularMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1))
                    // A quiet dot, so an error tucked into the menu is still
                    // discoverable without the page shouting it.
                    .overlay(alignment: .topTrailing) {
                        if syncError != nil {
                            Circle()
                                .fill(Color.oneDayButter)
                                .frame(width: 9, height: 9)
                                .overlay(Circle().strokeBorder(OneDay.canvas, lineWidth: 1.5))
                        }
                    }
                    .oneDaySoftShadow(strength: 0.5)
            }
            .accessibilityLabel(Text(syncError ?? Strings.moreLabel))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
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
