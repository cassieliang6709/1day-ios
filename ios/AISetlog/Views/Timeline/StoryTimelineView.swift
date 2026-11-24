import SwiftUI

struct StoryTimelineView: View {
    let challengeID: UUID

    @Environment(ChallengeStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomPreviewMediaScope) private var previewMedia
    @Environment(\.reservesTabBarClearance) private var reservesTabBarClearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var sheet: TimelineSheet?
    @State private var showFilm = false
    @State private var showEditPlan = false
    @State private var askBeforeDeleting = false
    @State private var showRoomChat = false
    @State private var showRoomCalendar = false
    @State private var showSignIn = false
    @AppStorage("roomLayout.v3") private var roomLayout: RoomLayout = .automatic
    @State private var roomDay: Date?
    @State private var roomMonth = Calendar.current.startOfMonth(for: .now)
    @State private var roomCalendarHeight: CGFloat = 420
    @State private var roomPerson: String?
    @State private var personPage: String?
    @State private var nudgeShareCode: String?
    @State private var celebrate = false

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var challenge: Challenge? { store.challenge(challengeID) }

    enum TimelineSheet: Identifiable, Equatable {
        case record(day: Int, take: TakeTarget = .replace(nil))
        case preview(day: Int, authorID: String?)
        case clip(day: Int, authorID: String?, takeID: UUID?)

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
        .sheet(isPresented: $showSignIn) {
            SignInView { showSignIn = false }
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showRoomChat) {
            RoomChatView(challengeID: challengeID) { day in
                showRoomChat = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    sheet = .clip(day: day, authorID: nil, takeID: nil)
                }
            }
        }
        .sheet(isPresented: $showRoomCalendar) {
            NavigationStack {
                ScrollView {
                    LibraryCalendar(
                        month: $roomMonth,
                        covers: roomCalendarCovers,
                        selectedDay: Binding(
                            get: { roomDay },
                            set: { day in
                                roomDay = day.map { Calendar.current.startOfDay(for: $0) }
                                roomPerson = nil
                                if day != nil { showRoomCalendar = false }
                            }))
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            roomCalendarHeight = $0
                        }
                }
                .scrollBounceBehavior(.basedOnSize)
                    .navigationTitle(Strings.libraryCalendar)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(Strings.done) { showRoomCalendar = false }
                        }
                        if roomDay != nil {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(Strings.libraryAllDays) {
                                    roomDay = nil
                                    roomPerson = nil
                                    showRoomCalendar = false
                                }
                                .accessibilityIdentifier("room-calendar-all")
                            }
                        }
                    }
            }
            // Sheet fits the calendar (5- or 6-week months) plus the nav bar.
            .presentationDetents([.height(roomCalendarHeight + 90)])
        }
        .sheet(isPresented: $showEditPlan) {
            if let challenge {
                GuidedMomentsView(
                    initialMoments: challenge.cards.map {
                        challenge.momentValue(forSlot: $0.day) ?? Strings.dayN($0.day)
                    },
                    initialSlots: challenge.cards.map(\.day),
                    filmedSlots: Set(challenge.cards.filter { $0.clipFileName != nil }.map(\.day)),
                    saveLabel: Strings.save
                ) { draft in
                    store.replacePlan(
                        challengeID,
                        items: zip(draft.moments, draft.slots).map { (title: $0, fromSlot: $1) })
                }
            }
        }
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
        .environment(\.memberProfiles, store.memberProfiles(for: challengeID))
    }

    private var dayIsComplete: Bool {
        guard let challenge else { return false }
        return StoryAgenda(
            momentCount: challenge.cards.count,
            clips: store.recordedClips(for: challengeID),
            myID: account.account?.id ?? RoomProgress.soloAuthorID
        ).isComplete
    }

    private func celebrateMyFinish() {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : OneDay.Motion.pop) {
            celebrate = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            celebrate = false
            showFilm = true
        }
    }


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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: reservesTabBarClearance ? OneDay.tabBarClearance : 0)
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

    private var signedOutLine: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(OneDay.inkFaint)
            Text(Strings.signedOutRoomBody)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(OneDay.ink)
            Spacer(minLength: 6)
            Button(Strings.signIn) { showSignIn = true }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.black, in: Capsule())
                .accessibilityIdentifier("room-sign-in")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassSurface(radius: 16)
    }

    private func roomPage(
        _ challenge: Challenge, clips: [DayClip], members: [(id: String, name: String)],
        myID: String, agenda: StoryAgenda
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            let dayClips = roomDay.map { day in clips.filter { Self.isClip($0, on: day) } } ?? clips
            let dayColumns = RoomFeed.columns(clips: dayClips, members: members, myID: myID)
            let signedOut = challenge.isShared && !account.isSignedIn

            if signedOut { signedOutLine }

            RoomStoriesRow(columns: dayColumns, selected: roomPerson) { id in
                withAnimation(OneDay.Motion.soft) { roomPerson = roomPerson == id ? nil : id }
            }
            let shownMembers = roomPerson.map { id in members.filter { $0.id == id } } ?? members
            let shownClips = roomPerson.map { id in dayColumns.first { $0.id == id }?.clips ?? [] } ?? dayClips
            switch roomLayout {
            case .automatic:
                RoomFrames(
                    clips: shownClips,
                    members: shownMembers.isEmpty ? members : shownMembers,
                    myID: myID,
                    nextToFilm: agenda.suggested ?? agenda.openToMe.first,
                    slotTitle: { slotTitle(for: $0) },
                    onPlay: { clip in sheet = .open(clip) },
                    onFilm: { day in sheet = .record(day: day) },
                    onOpenPerson: { column in personPage = column.id },
                    hasPoked: { id in
                        store.hasPokedToday(challengeID: challengeID, targetAuthorID: id)
                    },
                    onPoke: { id in
                        store.poke(challengeID: challengeID, targetAuthorID: id)
                    },
                    orientation: challenge.resolvedOrientation,
                    latestComment: { clip in
                        store.interactions(
                            for: challengeID, day: clip.day,
                            targetAuthorID: clip.authorID ?? myID
                        ).comments.max { $0.createdAt < $1.createdAt }
                    },
                    reactions: { clip in
                        store.interactions(
                            for: challengeID, day: clip.day,
                            targetAuthorID: clip.authorID ?? myID
                        ).reactions
                    },
                    onReact: { clip, key in
                        store.toggleReaction(
                            key, day: clip.day, challengeID: challengeID,
                            targetAuthorID: clip.authorID ?? myID)
                    },
                    signedOut: signedOut,
                    onSignIn: { showSignIn = true })
            case .columns:
                ScrollView {
                    RoomFeed(
                        challenge: challenge,
                        clips: shownClips,
                        members: shownMembers.isEmpty ? members : shownMembers,
                        myID: myID,
                        nextToFilm: nil,
                        slotTitle: { slotTitle(for: $0) },
                        onPlay: { clip in sheet = .open(clip) },
                        onFilm: { day in sheet = .record(day: day) },
                        hasPoked: { id in
                            store.hasPokedToday(challengeID: challengeID, targetAuthorID: id)
                        },
                        onPoke: { id in
                            store.poke(challengeID: challengeID, targetAuthorID: id)
                        },
                        showsCalendarControls: false)
                }
                .scrollIndicators(.hidden)
            case .byDay:
                ScrollView {
                    RoomDayList(
                        clips: shownClips,
                        members: shownMembers.isEmpty ? members : shownMembers,
                        myID: myID,
                        onPlay: { clip in sheet = .open(clip) })
                }
                .scrollIndicators(.hidden)
            }
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
                    isSyncing: store.syncing.contains(challenge.roomCode ?? ""),
                    onRename: { name in
                        store.updatePlan(
                            challengeID, title: name, momentTitles: challenge.momentTitles ?? [])
                    })

                if agenda.isComplete {
                    FilmReadyCard(momentCount: agenda.total) { showFilm = true }
                }

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

    private func offerShareIfRoomIsStillEmpty() {
        guard let challenge, challenge.isShared, previewMedia == nil,
              let code = challenge.roomCode,
              store.members(for: challengeID).count <= 1,
              RoomShareNudge.shouldOffer(code: code, isEmptyRoom: true)
        else { return }
        RoomShareNudge.markOffered(code: code)
        nudgeShareCode = code
    }


    private func navBar(
        _ challenge: Challenge, agenda: StoryAgenda, clipCount: Int
    ) -> some View {
        let syncError = store.syncError(for: challengeID)

        return VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 8) {
            IconBubble(systemName: "chevron.left") { dismiss() }
                .accessibilityLabel(Text(Strings.back))
                .accessibilityIdentifier("room-back")

            Spacer(minLength: 4)

            if challenge.isShared {
                roomToolCapsule
                IconBubble(systemName: "film.stack.fill", label: Strings.makeRoomVlog) { showFilm = true }
                    .disabled(clipCount == 0)
                    .accessibilityIdentifier("room-make-vlog")
            }

            Menu {
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
                    .overlay(alignment: .topTrailing) {
                        if syncError != nil {
                            Circle()
                                .fill(Color.oneDayButter)
                                .frame(width: 9, height: 9)
                                .overlay(Circle().strokeBorder(OneDay.canvas, lineWidth: 1.5))
                        }
                    }
                    .oneDaySoftShadow(strength: 0.5)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text(syncError ?? Strings.moreLabel))
            .accessibilityIdentifier("room-more")
        }
        if challenge.isShared {
            roomTitleRow(challenge)
        }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    /// Second header row: the room name gets the full width (small phones
    /// squeezed it to one letter next to the tool buttons), with invite beside it.
    private func roomTitleRow(_ challenge: Challenge) -> some View {
        HStack(spacing: 8) {
            TimelineHeader(
                challenge: challenge,
                isSyncing: store.syncing.contains(challenge.roomCode ?? ""),
                onRename: { name in
                    Task { await store.renameRoom(challengeID, to: name) }
                },
                fontSize: 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let code = challenge.roomCode, previewMedia == nil {
                RoomInviteShareLink(
                    content: RoomInviteCardContent(
                        challenge: challenge, inviter: account.account?.displayName),
                    message: shareText(code: code, challenge: challenge)
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(OneDay.ink)
                        .frame(width: 38, height: 38)
                        .background(.regularMaterial, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text(Strings.inviteLabel))
                .accessibilityIdentifier("room-invite")
            }
        }
        .padding(.leading, 4)
    }

    /// Cover thumbnail per day, so the room calendar shows which days have clips.
    private var roomCalendarCovers: [Date: LibraryClip] {
        guard let challenge else { return [:] }
        let myID = account.account?.id ?? "local"
        let library = ClipLibrary(
            stories: [(challenge, store.recordedClips(for: challengeID))], drafts: [], myIDs: [myID])
        return library.coverByDay(library.clips)
    }

    private var roomToolCapsule: some View {
        HStack(spacing: 0) {
            Menu {
                Picker(Strings.roomLayoutMenu, selection: $roomLayout) {
                    ForEach(RoomLayout.allCases, id: \.self) { layout in
                        Label(layout.title, systemImage: layout.systemImage).tag(layout)
                    }
                }
            } label: {
                Image(systemName: roomLayout.systemImage)
                    .foregroundStyle(OneDay.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("\(Strings.roomLayoutMenu): \(roomLayout.title)"))
            .accessibilityIdentifier("room-layout")
            Button { showRoomCalendar = true } label: {
                Image(systemName: "calendar")
                    .foregroundStyle(roomDay == nil ? OneDay.ink : Color.oneDayBrand)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text(Strings.libraryCalendar))
            .accessibilityIdentifier("room-calendar")
            Button { showRoomChat = true } label: {
                Image(systemName: "bubble.left")
                    .foregroundStyle(OneDay.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text(Strings.chatLabel))
            .accessibilityIdentifier("room-chat")
        }
        .font(.system(size: 15, weight: .semibold))
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .background(.regularMaterial, in: Capsule())
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
            Color.black.ignoresSafeArea().onTapGesture { sheet = nil }
        }
    }

    private func slotTitle(for day: Int) -> String? {
        guard let challenge, !challenge.isTimeOnly else { return nil }
        return ChallengePresenter(challenge: challenge).slotLabel(forSlot: day)
    }

    private func showsPrompt(for day: Int) -> Bool {
        guard let challenge, !challenge.isTimeOnly else { return false }
        return !challenge.isShared || slotTitle(for: day) != nil
    }

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

extension StoryTimelineView {
    static func isClip(_ clip: DayClip, on day: Date) -> Bool {
        clip.recordedAt.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false
    }
}

private struct ReservesTabBarClearanceKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var reservesTabBarClearance: Bool {
        get { self[ReservesTabBarClearanceKey.self] }
        set { self[ReservesTabBarClearanceKey.self] = newValue }
    }
}

enum RoomLayout: String, CaseIterable {
    case automatic, columns, byDay

    var title: String {
        switch self {
        case .automatic: Strings.roomLayoutDefault
        case .columns: Strings.roomLayoutWaterfall
        case .byDay: Strings.roomLayoutByDay
        }
    }

    var systemImage: String {
        switch self {
        case .automatic: "rectangle.grid.1x2"
        case .columns: "rectangle.split.3x1"
        case .byDay: "square.grid.3x3"
        }
    }
}
