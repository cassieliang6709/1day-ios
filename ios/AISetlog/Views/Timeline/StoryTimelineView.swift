import SwiftUI

/// Screen 4 — the story page. The heart of the app.
///
/// The day reads top to bottom: how far it has got, what's still yours to
/// take, then what happened — and once nothing is left open, the film.
///
/// "What's still yours to take" is a list of equals on purpose. The page began
/// as a wall of identical tiles that asked seven questions and answered none;
/// the answer to that was a single "next up" card carrying the loudest pixels
/// on the screen, which overcorrected into a different lie. A story is filmed
/// in whatever order the day happens in — you shoot the walk while you're on
/// the walk — and a queue of one told people the rest were waiting their turn.
/// So the open moments are back to being peers, sitting where the loud card
/// used to sit, and the only thing left of "next" is one row wearing a tint
/// and a question mark.
struct StoryTimelineView: View {
    let challengeID: UUID

    @Environment(ChallengeStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomPreviewMediaScope) private var previewMedia

    @State private var sheet: TimelineSheet?
    @State private var showFilm = false
    @State private var showEditPlan = false
    /// Changing the picture that stands for this story — see `StoryCoverSheet`.
    @State private var showCoverPicker = false
    /// Held between the menu tap and the confirmation.
    @State private var askBeforeDeleting = false
    @State private var showRoomChat = false
    @State private var showRoomDemo = false
    /// The beat between the last moment landing and the film assembling.
    @State private var celebrate = false

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system
    /// Timeline or contact sheet. Persisted, so the choice sticks.

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
        .sheet(isPresented: $showRoomChat) {
            // The timeline can reach any moment, so a quoted one is a link
            // from here: close the chat and open that moment.
            RoomChatView(challengeID: challengeID) { day in
                showRoomChat = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    sheet = .moment(day: day)
                }
            }
        }
        .sheet(isPresented: $showRoomDemo) {
            #if DEBUG || LOCAL_ROOM_CHAT_DEMO
            RoomChatDemoView(chinese: appLanguage.resolved == .chinese)
            #endif
        }
        .sheet(isPresented: $showEditPlan) {
            if let challenge {
                EditPlanSheet(challenge: challenge) { title, moments in
                    store.updatePlan(challengeID, title: title, momentTitles: moments)
                }
            }
        }
        .sheet(isPresented: $showCoverPicker) {
            if let challenge {
                // Newest first: the frame somebody wants for a cover is almost
                // always the one they just filmed.
                let clips = store.recordedClips(for: challengeID).sorted {
                    ($0.recordedAt ?? .distantPast, $0.day)
                        > ($1.recordedAt ?? .distantPast, $1.day)
                }
                StoryCoverSheet(
                    challenge: challenge,
                    clips: clips,
                    currentCoverURL: store.storyCoverURL(
                        for: challenge, latestClipURL: clips.first?.url)
                ) { choice in
                    store.setStoryCover(choice, for: challengeID)
                }
            }
        }
        // Same question, same words as the long press on the home list. Two
        // entry points to one irreversible action, so they say one thing.
        .confirmationDialog(
            challenge.map {
                $0.isShared
                    ? Strings.leaveRoomTitle($0.title)
                    : Strings.deleteStoryTitle($0.title)
            } ?? "",
            isPresented: $askBeforeDeleting,
            titleVisibility: .visible
        ) {
            if let challenge {
                Button(
                    challenge.isShared ? Strings.leaveRoom : Strings.deleteChallenge,
                    role: .destructive
                ) {
                    store.delete(challengeID)
                    dismiss()
                }
            }
            Button(Strings.cancel, role: .cancel) {}
        } message: {
            if let challenge {
                Text(
                    challenge.isShared
                        ? Strings.leaveRoomWarning
                        : Strings.deleteStoryWarning(challenge.recordedCount))
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
                    isSyncing: store.syncing.contains(challenge.roomCode ?? ""))

                StoryProgressBar(filmed: agenda.filmedCount, total: agenda.total)

                // Only once, and only when it's the whole answer.
                if agenda.isComplete {
                    FilmReadyCard(clipCount: clips.count) { showFilm = true }
                }

                // One list, in the order the day happens. It was two — 还没拍的
                // as a card of rows, then 拍过的 as a contact sheet — which cut
                // the day in half and re-sorted each half by state, so a moment
                // that is second in the plan and filmed sat below one that is
                // fifth and empty. See `MomentTimeline`.
                MomentTimeline(
                    challenge: challenge,
                    clips: clips,
                    members: members,
                    myID: myID,
                    agenda: agenda,
                    // A moment in a story only you filmed is one clip, so it
                    // opens as a page in the day and you swipe on. In a shared
                    // room it is still the whole moment with everyone stacked
                    // in it, which isn't a page — that's what `.moment` is for.
                    onPlay: { day in
                        sheet = challenge.isShared
                            ? .moment(day: day)
                            : .preview(day: day, authorID: nil)
                    },
                    onFilm: { day in sheet = .record(day: day) })

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

    /// A header, and optionally the one sentence the section needs to be read
    /// correctly. "还没拍的" is a list of choices, not a running order, and
    /// nothing in a list of rows says that on its own.
    private func section<Content: View>(
        _ title: String, note: String? = nil, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                SectionLabel(text: title)
                if let note {
                    Text(note)
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(OneDay.inkSoft)
                        .lineLimit(2)
                }
            }
            content()
        }
    }

    /// Every moment still open to me, all of them, all the same.
    ///
    /// Nothing is held back for a card above and nothing is skipped: the list
    /// *is* the offer, so whichever moment is actually happening right now is
    /// one tap away instead of three rows into a queue.

    /// A story recorded by time has no prompts, so its moments are called by
    /// their place in the day. Falling back to the prompt title would print
    /// "Day 3" down a story that lasts one day.

    // MARK: - Chrome

    private func navBar(
        _ challenge: Challenge, agenda: StoryAgenda, clipCount: Int
    ) -> some View {
        let syncError = store.syncError(for: challengeID)

        return HStack(spacing: 12) {
            IconBubble(systemName: "chevron.left") { dismiss() }
                .accessibilityIdentifier("room-back")

            Spacer()

            if challenge.isShared, let code = challenge.roomCode {
                Button {
                    showRoomChat = true
                } label: {
                    Label(appLanguage.resolved == .chinese ? "聊天" : "Chat", systemImage: "bubble.left.and.bubble.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                }
                if previewMedia == nil {
                ShareLink(item: shareText(code: code, challenge: challenge)) {
                    Label(Strings.inviteLabel, systemImage: "person.badge.plus")
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.oneDayBrand)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                        .oneDaySoftShadow(strength: 0.5)
                }
                }
            }

            Menu {
                #if DEBUG || LOCAL_ROOM_CHAT_DEMO
                if challenge.isShared, previewMedia == nil {
                    Button(appLanguage.resolved == .chinese ? "房间演示" : "Room demo", systemImage: "person.3.sequence") {
                        showRoomDemo = true
                    }
                }
                #endif
                // Watching an unfinished day is a real thing to want — a friend
                // who joins late can see it before filming — but it isn't the
                // page's answer to "what now", so it stops being a button and
                // becomes a menu item. Once the day is full the page shows the
                // film card itself, and a second entry would be the same
                // action twice.
                if clipCount > 0, !agenda.isComplete {
                    Button(Strings.previewTheFilm(clipCount), systemImage: "film.stack") {
                        showFilm = true
                    }
                }

                if !challenge.isTimeOnly {
                    Button(Strings.editPlan, systemImage: "pencil") { showEditPlan = true }
                }

                // Next to 编辑计划 because it is the same kind of thing: what
                // this story *is*, rather than what to do in it.
                Button(Strings.storyCoverTitle, systemImage: "photo") {
                    showCoverPicker = true
                }

                Button(
                    challenge.isShared ? Strings.leaveRoom : Strings.deleteChallenge,
                    systemImage: "trash",
                    role: .destructive
                ) {
                    askBeforeDeleting = true
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
                momentCount: challenge?.cards.count ?? 0,
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
