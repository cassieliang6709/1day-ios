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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var sheet: TimelineSheet?
    @State private var showFilm = false
    @State private var showEditPlan = false
    /// Changing the picture that stands for this story — see `StoryCoverSheet`.
    /// Held between the menu tap and the confirmation.
    @State private var askBeforeDeleting = false
    @State private var showRoomChat = false
    /// The person whose page is open, from the face on their frame.
    @State private var personPage: String?
    /// The room whose code is being offered for sharing, once, right after it
    /// was made. See `RoomShareNudge`.
    @State private var nudgeShareCode: String?
    /// The beat between the last moment landing and the film assembling.
    @State private var celebrate = false

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var challenge: Challenge? { store.challenge(challengeID) }

    enum TimelineSheet: Identifiable, Equatable {
        /// `take` is what the new clip does to one already there: 重拍
        /// (`.replace`, the default) or 再拍一段 (`.append`).
        case record(day: Int, take: TakeTarget = .replace(nil))
        case preview(day: Int, authorID: String?)
        /// One person's one take, full screen, where its captions are edited.
        /// Every tap on a clip in a room opens this. It replaced `.moment`,
        /// which opened everybody's takes stitched together — a preview of
        /// the film, where nothing could be changed.
        case clip(day: Int, authorID: String?, takeID: UUID?)

        /// The take a tile stands for.
        static func open(_ clip: DayClip) -> TimelineSheet {
            .clip(day: clip.day, authorID: clip.authorID, takeID: clip.takeID)
        }

        var id: String {
            switch self {
            case .record(let day, _): "record-\(day)"
            case .preview(let day, let authorID): "preview-\(day)-\(authorID ?? "local")"
            case .clip(let day, let authorID, let takeID):
                "clip-\(day)-\(authorID ?? "local")-\(takeID?.uuidString ?? "1")"
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
                    .environment(\.memberProfiles, store.memberProfiles(for: challengeID))
            }
        }
        .sheet(isPresented: $showRoomChat) {
            // The timeline can reach any moment, so a quoted one is a link
            // from here: close the chat and open that moment.
            RoomChatView(challengeID: challengeID) { day in
                showRoomChat = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    sheet = .clip(day: day, authorID: nil, takeID: nil)
                }
            }
        }
        .sheet(isPresented: $showEditPlan) {
            if let challenge {
                EditPlanSheet(challenge: challenge) { title, moments in
                    store.updatePlan(challengeID, title: title, momentTitles: moments)
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
        // Friends' avatars and today's moods, for every face on this page and
        // in the sheets it opens (`MemberFace`).
        .environment(\.memberProfiles, store.memberProfiles(for: challengeID))
    }

    /// Every moment holds footage from somebody — the same rule the
    /// `FilmReadyCard` appears by.
    private var dayIsComplete: Bool {
        guard let challenge else { return false }
        return StoryAgenda(
            momentCount: challenge.cards.count,
            clips: store.recordedClips(for: challengeID),
            myID: account.account?.id ?? RoomProgress.soloAuthorID
        ).isComplete
    }

    /// The magic moment: the last slot lands → a tiny celebration → the film
    /// assembles itself. No button to discover.
    ///
    /// Only for a save of *mine*. This used to hang off `onChange` of the
    /// story's completeness, which also fires when the 10-second room sync
    /// brings in a friend's last clip — so somebody reading the chat or
    /// scrolling their own day got yanked onto the film screen by a thing
    /// that happened on another phone. A day finished by someone else just
    /// grows the `FilmReadyCard`, and the page stays where you left it.
    ///
    /// Reduce Motion keeps the beat but drops the movement: a plain fade, and
    /// the mascot holds still.
    private func celebrateMyFinish() {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : OneDay.Motion.pop) {
            celebrate = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            celebrate = false
            showFilm = true
        }
    }

    // MARK: - Layout

    private func timeline(_ challenge: Challenge) -> some View {
        let clips = store.recordedClips(for: challengeID)
        let members = store.members(for: challengeID)
        let myID = account.account?.id ?? RoomProgress.soloAuthorID
        let agenda = StoryAgenda(momentCount: challenge.cards.count, clips: clips, myID: myID)

        return Group {
            if challenge.isShared {
                roomPage(challenge, clips: clips, members: members, myID: myID, agenda: agenda)
            } else {
                storyPage(challenge, clips: clips, members: members, myID: myID, agenda: agenda)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            navBar(challenge, agenda: agenda, clipCount: clips.count)
        }
        // The floating tab bar is drawn over the whole stack, so the page
        // reserves its own clearance rather than inheriting one.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: OneDay.tabBarClearance)
        }
        .sensoryFeedback(.success, trigger: challenge.recordedCount)
        .refreshable {
            if challenge.isShared { await store.syncRoom(challengeID) }
        }
        .task(id: challengeID) {
            offerShareIfRoomIsStillEmpty()
            guard challenge.isShared else { return }
            while !Task.isCancelled {
                await store.syncRoom(challengeID)
                do { try await Task.sleep(for: .seconds(10)) } catch { break }
            }
        }
        .navigationDestination(item: $personPage) { id in
            if let column = RoomFeed.columns(clips: clips, members: members, myID: myID)
                .first(where: { $0.id == id }) {
                RoomPersonPage(
                    column: column,
                    slotTitle: { slotTitle(for: $0) },
                    onPlay: { clip in sheet = .open(clip) })
                    .environment(\.memberProfiles, store.memberProfiles(for: challengeID))
            }
        }
        .confirmationDialog(
            Strings.sendTheCodeTitle,
            isPresented: Binding(
                get: { nudgeShareCode != nil },
                set: { if !$0 { nudgeShareCode = nil } }),
            titleVisibility: .visible
        ) {
            if let code = nudgeShareCode {
                // A `ShareLink` inside the dialog rather than a button that
                // opens a second sheet: one tap from "yes" to the share sheet.
                // A bare `ShareLink`, not `RoomInviteShareLink`: a dialog's
                // actions are matched by type, and a wrapper view risks being
                // dropped. Same card, same message.
                let card = RoomInviteCardImage(content: RoomInviteCardContent(
                    challenge: challenge, inviter: account.account?.displayName))
                ShareLink(
                    item: card,
                    subject: Text(card.content.headline),
                    message: Text(shareText(code: code, challenge: challenge)),
                    preview: SharePreview(card.content.headline, image: card),
                    label: { Text(Strings.sendTheCodeNow) })
            }
            Button(Strings.sendTheCodeLater, role: .cancel) {}
        }
    }

    /// A shared room (1.5): the name, then one big frame per person filling
    /// the rest of the screen — see `RoomFrames`. The column layout,
    /// `RoomFeed`, is kept but not drawn. 生成 vlog and 聊天 are icons in the
    /// nav bar now, so the frames get the height.
    private func roomPage(
        _ challenge: Challenge, clips: [DayClip], members: [(id: String, name: String)],
        myID: String, agenda: StoryAgenda
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            TimelineHeader(
                challenge: challenge,
                isSyncing: store.syncing.contains(challenge.roomCode ?? ""))

            RoomFrames(
                clips: clips,
                members: members,
                myID: myID,
                nextToFilm: agenda.suggested ?? agenda.openToMe.first,
                slotTitle: { slotTitle(for: $0) },
                // Opens the tapped take alone, full screen, where its
                // captions are edited.
                onPlay: { clip in sheet = .open(clip) },
                onFilm: { day in sheet = .record(day: day) },
                onOpenPerson: { column in personPage = column.id },
                hasPoked: { id in
                    store.hasPokedToday(challengeID: challengeID, targetAuthorID: id)
                },
                onPoke: { id in
                    store.poke(challengeID: challengeID, targetAuthorID: id)
                })
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    private func storyPage(
        _ challenge: Challenge, clips: [DayClip], members: [(id: String, name: String)],
        myID: String, agenda: StoryAgenda
    ) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                TimelineHeader(
                    challenge: challenge,
                    isSyncing: store.syncing.contains(challenge.roomCode ?? ""))

                // A solo story keeps the film card, once, when it's the whole
                // answer.
                if agenda.isComplete {
                    FilmReadyCard(momentCount: agenda.total) { showFilm = true }
                }

                // One list, in the order the day happens. It was two — 还没拍的
                // as a card of rows, then 拍过的 as a contact sheet — which cut
                // the day in half and re-sorted each half by state, so a moment
                // that is second in the plan and filmed sat below one that is
                // fifth and empty.
                //
                // Two shapes, chosen by whether the moments have names. A rail
                // gives each name its own line and keeps seven readable; a
                // 按时间 story has no names — its slots are 「第 N 个瞬间」,
                // the numbering 1.3 deleted — so a vertical list of them is a
                // list of nothing, one per line. That story gets a diary
                // instead — one row per clip, headed by the time it was
                // filmed — which is the only real fact it has and the reason
                // somebody picked 按时间.
                // See `MomentTimeline` and `MomentFilmstrip`.
                //
                // A moment in a story only you filmed is one clip, so it opens
                // as a page in the day.
                if challenge.isTimeOnly {
                    MomentFilmstrip(
                        challenge: challenge,
                        clips: clips,
                        members: members,
                        myID: myID,
                        agenda: agenda,
                        onPlay: { day in
                            sheet = challenge.isShared
                                ? .clip(day: day, authorID: nil, takeID: nil)
                                : .preview(day: day, authorID: nil)
                        },
                        onFilm: { day in sheet = .record(day: day) })
                } else {
                    MomentTimeline(
                        challenge: challenge,
                        clips: clips,
                        members: members,
                        myID: myID,
                        agenda: agenda,
                        onPlay: { day in
                            sheet = challenge.isShared
                                ? .clip(day: day, authorID: nil, takeID: nil)
                                : .preview(day: day, authorID: nil)
                        },
                        onFilm: { day in sheet = .record(day: day) })
                }

            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    /// Offer the code once, the first time you land on a room you own that
    /// nobody has joined.
    ///
    /// Not on `onAppear`: this page is rebuilt on every navigation back to it,
    /// and `RoomShareNudge` is what stops the offer returning — but reading the
    /// member list before the first sync would call every room empty, so the
    /// guard is "no members yet" *and* "never offered", and the flag is written
    /// the moment it is asked rather than when it is answered.
    private func offerShareIfRoomIsStillEmpty() {
        guard let challenge, challenge.isShared, previewMedia == nil,
              let code = challenge.roomCode,
              store.members(for: challengeID).count <= 1,
              RoomShareNudge.shouldOffer(code: code, isEmptyRoom: true)
        else { return }
        RoomShareNudge.markOffered(code: code)
        nudgeShareCode = code
    }

    // MARK: - Chrome

    private func navBar(
        _ challenge: Challenge, agenda: StoryAgenda, clipCount: Int
    ) -> some View {
        let syncError = store.syncError(for: challengeID)

        return HStack(spacing: 12) {
            IconBubble(systemName: "chevron.left") { dismiss() }
                .accessibilityLabel(Text(Strings.back))
                .accessibilityIdentifier("room-back")

            Spacer()

            // A room's two actions are icons up here (1.5), beside 邀请, so
            // the frames below get the whole screen. Their identifiers are
            // what the UI tests find them by.
            if challenge.isShared {
                IconBubble(systemName: "film.stack.fill", label: Strings.makeRoomVlog) {
                    showFilm = true
                }
                .disabled(clipCount == 0)
                .opacity(clipCount == 0 ? 0.5 : 1)
                .accessibilityIdentifier("room-make-vlog")

                IconBubble(systemName: "bubble.left.and.bubble.right.fill",
                           label: Strings.chatLabel) {
                    showRoomChat = true
                }
                .accessibilityIdentifier("room-chat")
            }

            if challenge.isShared, let code = challenge.roomCode {
                if previewMedia == nil {
                    RoomInviteShareLink(
                        content: RoomInviteCardContent(
                            challenge: challenge, inviter: account.account?.displayName),
                        message: shareText(code: code, challenge: challenge)
                    ) {
                        roomCapsule(Strings.inviteLabel, systemImage: "person.badge.plus")
                    }
                    .accessibilityIdentifier("room-invite")
                }
            }

            // The 房间演示 item that used to open this menu is gone with the
            // chat's 演示 button: both were a second door into the same local
            // sample room, from inside a real one. The sample is still on the
            // home screen behind `-demoEntries` (`PlansHomeView`).
            Menu {
                // Watching an unfinished day is a real thing to want — a friend
                // who joins late can see it before filming — but it isn't the
                // page's answer to "what now", so it stops being a button and
                // becomes a menu item. Once the day is full the page shows the
                // film card itself, and a second entry would be the same
                // action twice.
                if !challenge.isShared, clipCount > 0, !agenda.isComplete {
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
                    // Drawn at 38, tapped at 44: the circle matches the back
                    // bubble, the target meets the minimum.
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text(syncError ?? Strings.moreLabel))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    /// The glass pill 邀请 is drawn in. At least 44pt tall, so it isn't a
    /// smaller target than the bubbles beside it.
    private func roomCapsule(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 13.5, weight: .bold, design: .rounded))
            .foregroundStyle(OneDay.brandText)
            .lineLimit(1)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1))
            .oneDaySoftShadow(strength: 0.5)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }

    private var celebration: some View {
        VStack(spacing: 14) {
            OneDayBuddy(size: 78, isWorking: !reduceMotion)
            Text(Strings.yourFilmIsHere)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(OneDay.onBrand)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OneDay.brand.opacity(0.96).ignoresSafeArea())
        .transition(.opacity)
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetContent(_ presented: TimelineSheet) -> some View {
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
            // The tapped clip, on its own. The swipe that used to reach the
            // rest of the story from here is gone — see `ClipDeckReview`; the
            // timeline on the page behind is how you get to the next moment.
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

    /// The full-screen editor on one take, with 重拍 and 再拍一段 wired back
    /// to the camera.
    @ViewBuilder
    private func clipReview(day: Int, authorID: String?, takeID: UUID?) -> some View {
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
            // The take went away between the tap and the sheet (a sync, a
            // delete). Something has to be on screen to close.
            Color.black.ignoresSafeArea().onTapGesture { sheet = nil }
        }
    }

    /// The slot's name as the camera and the player print it. In a shared
    /// room that is a real name or nothing — a room doesn't number its days on
    /// screen (1.5), and every one of these used to fall back to 「第 N 天」.
    private func slotTitle(for day: Int) -> String? {
        guard let challenge, !challenge.isTimeOnly else { return nil }
        return ChallengePresenter(challenge: challenge).slotLabel(forSlot: day)
    }

    /// Whether the camera and the player put the moment's name on the frame.
    /// A room slot with no name has nothing to print; without this the camera
    /// stamped its fallback, 「这个瞬间」, over the picture.
    private func showsPrompt(for day: Int) -> Bool {
        guard let challenge, !challenge.isTimeOnly else { return false }
        return !challenge.isShared || slotTitle(for: day) != nil
    }

    /// How many slots the camera's bars and the player's 「3 / 7」 chip count
    /// out of. Zero in a room, which hides both: "3 of 7" is a day number by
    /// another name.
    private var momentCountOnScreen: Int {
        guard let challenge else { return 0 }
        return challenge.isShared ? 0 : challenge.cards.count
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
