import SwiftUI

struct PlansHomeView: View {
    @Environment(ChallengeStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(ClipDraftStore.self) private var drafts
    @Environment(MoodStore.self) private var moods: MoodStore?
    @Binding var pendingJoinCode: String?
    @Binding var launchAction: HomeLaunchAction?
    let stories: HomeStories
    var scope: Scope = .stories
    enum Scope { case stories, friends }
    var draftsRequest = 0
    var isActive = true
    var onActivate: (() -> Bool)? = nil
    var onBackToRooms: (() -> Void)? = nil
    var onOpenPersonal: (() -> Void)? = nil
    let onCompose: () -> Void

    @State private var path: [UUID] = []
    @State private var roomSeenAt: [String: Double] =
        UserDefaults.standard.dictionary(forKey: PlansHomeView.roomSeenKey) as? [String: Double] ?? [:]
    @State private var showJoin = false
    @State private var showSettings = false
    @State private var showRoomDemo = false
    @State private var showDrafts = false
    @State private var joinCode = ""
    @State private var joining = false
    @State private var joinAttempt = 0
    @State private var joinTask: Task<Void, Never>?
    @State private var errorText: String?
    @State private var recordChallenge: Challenge?
    @State private var recordPlanSlot: PlanSlot?
    @State private var pendingDeletion: Challenge?
    @State private var notificationRecordRoute: NotificationRecordRoute?
    @State private var afterSignIn: (() -> Void)?
    @State private var isSelectingClips = false
    @State private var pickedClips: [LibraryClip] = []
    @State private var vlogRequest: VlogRequest?
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var planningAhead = false
    @State private var inviteRequest: InviteRequest?
    @State private var debugAlert: DebugAlert?

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var timeline: StoryTimeline { stories.timeline }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                OneDayCanvas()
                content
            }
            .accessibilityHidden(!isActive)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                StoryTimelineView(challengeID: id)
                    .onAppear { markSeen(id) }
                    .onDisappear { markSeen(id) }
            }
        }
        .fullScreenCover(item: $recordChallenge) { challenge in
            recorder(for: challenge)
        }
        .fullScreenCover(item: $recordPlanSlot) { item in
            if let challenge = store.challenge(item.challengeID) {
                recorder(for: challenge, preferredDay: item.slot)
            }
        }
        .fullScreenCover(item: $notificationRecordRoute) { route in
            if let challenge = store.challenge(route.challengeID) {
                recorder(for: challenge, preferredDay: route.day)
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showDrafts) { ClipDraftsView() }
        .confirmationDialog(
            pendingDeletion.map {
                $0.isShared
                    ? Strings.leaveRoomTitle($0.title)
                    : Strings.deleteStoryTitle($0.title)
            } ?? "",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            if let challenge = pendingDeletion {
                Button(
                    challenge.isShared ? Strings.leaveRoom : Strings.deleteChallenge,
                    role: .destructive
                ) {
                    store.delete(challenge.id)
                    pendingDeletion = nil
                }
            }
            Button(Strings.cancel, role: .cancel) { pendingDeletion = nil }
        } message: {
            if let challenge = pendingDeletion {
                Text(
                    challenge.isShared
                        ? Strings.leaveRoomWarning
                        : Strings.deleteStoryWarning(challenge.recordedCount))
            }
        }
        .sheet(isPresented: $showRoomDemo) {
            #if DEBUG || LOCAL_ROOM_CHAT_DEMO
            LocalRoomDemoView(chinese: appLanguage.resolved == .chinese)
            #endif
        }
        .sheet(isPresented: $showJoin) {
            JoinInviteSheet(
                code: $joinCode,
                onCancel: { showJoin = false },
                onJoin: {
                    showJoin = false
                    startJoin(joinCode)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: Binding(
            get: { afterSignIn != nil },
            set: { if !$0 { afterSignIn = nil } }
        )) {
            SignInView { afterSignIn?() }
                .presentationDetents([.medium])
                .onDisappear {
                    guard afterSignIn == nil, !joinCode.isEmpty,
                          !account.isSignedIn
                    else { return }
                    showJoin = true
                }
        }
        .alert(Strings.couldntJoin, isPresented: Binding(
            get: { errorText != nil }, set: { if !$0 { errorText = nil } }
        )) {
            Button(Strings.ok, role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
        .onAppear {
            consumePendingJoinCode()
            consumeLaunchAction()
            openPendingNotificationRoute()
            guard scope == .stories else { return }
            if UserDefaults.standard.bool(forKey: AppSkin.reopenSettingsKey) {
                UserDefaults.standard.removeObject(forKey: AppSkin.reopenSettingsKey)
                _ = onActivate?()
                showSettings = true
            }
            #if DEBUG
            createDebugTestRoomIfAsked()
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .oneDayNotificationRoutePending
        )) { _ in
            openPendingNotificationRoute()
        }
        .onChange(of: isActive) { _, active in
            guard active else { return }
            consumePendingJoinCode()
            consumeLaunchAction()
            openPendingNotificationRoute()
        }
        .onChange(of: pendingJoinCode) { _, _ in consumePendingJoinCode() }
        .onChange(of: launchAction) { _, _ in consumeLaunchAction() }
        .sheet(item: $inviteRequest) { inviteSheet($0) }
        .alert(debugAlert?.title ?? "", isPresented: Binding(
            get: { debugAlert != nil }, set: { if !$0 { debugAlert = nil } }
        )) {
            Button(Strings.ok, role: .cancel) {}
        } message: {
            Text(debugAlert?.message ?? "")
        }
    }


    @ViewBuilder
    private var content: some View {
        switch scope {
        case .stories: storiesContent
        case .friends: friendsContent
        }
    }

    private var storiesContent: some View {
        ScrollViewReader { proxy in
            storiesScroll
                .onChange(of: draftsRequest) { _, _ in
                    withAnimation(OneDay.Motion.soft) {
                        proxy.scrollTo(Self.libraryAnchor, anchor: .top)
                    }
                }
        }
        .overlay(alignment: .bottom) {
            if isSelectingClips {
                LibrarySelectionBar(picked: pickedClips) {
                    vlogRequest = VlogRequest(clips: pickedClips)
                }
                .padding(.bottom, OneDay.tabBarClearance + 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $planningAhead) {
            GuidedMomentsView(initialMoments: []) { draft in
                let moments = draft.moments
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                guard !moments.isEmpty else { return }
                _ = store.create(
                    title: draft.suggestedName ?? Strings.dayPlanTitle(selectedDay),
                    mode: .oneDay,
                    clipLength: .scene,
                    cameraStyle: CameraStyle.defaultCamera,
                    momentTitles: moments,
                    startDate: selectedDay)
            }
        }
        .sheet(item: $vlogRequest) { request in
            LibraryVlogSheet(clips: request.clips)
        }
        #if DEBUG
        .onAppear { LibraryDebugSeed.runIfAsked(store: store, drafts: drafts, moods: moods) }
        #endif
    }

    private static let libraryAnchor = "library-section"

    private var storiesScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if let onBackToRooms {
                    Button(action: onBackToRooms) {
                        Label(Strings.surfaceFriends, systemImage: "chevron.left")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(OneDay.brandText)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .accessibilityIdentifier("personal-back")
                }
                header

                #if DEBUG || LOCAL_ROOM_CHAT_DEMO
                if DemoEntries.areEnabled {
                    Button {
                        showRoomDemo = true
                    } label: {
                        Label(appLanguage.resolved == .chinese ? "房间演示" : "Room demo",
                              systemImage: "person.3.sequence")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .accessibilityIdentifier("home-room-demo")
                }
                #endif

                DayStrip(
                    selected: $selectedDay,
                    hasSomething: { day in store.plan(on: day) != nil || !clips(on: day).isEmpty },
                    mood: { day in day > .now ? nil : moods?.mood(on: day)?.mood })
                todayCards
                todayStrip

                if !store.challenges.contains(where: { !$0.isShared }), library.clips.isEmpty { emptyState }

                LibrarySection(
                    library: library,
                    rooms: store.challenges.filter(\.isShared),
                    onOpenStory: { path.append($0) },
                    draftsRequest: draftsRequest,
                    isSelecting: $isSelectingClips,
                    picked: $pickedClips,
                    onMakeVlog: { dayClips in
                        vlogRequest = VlogRequest(clips: dayClips.sorted { $0.recordedAt < $1.recordedAt })
                    },
                    hiddenDay: showsTodayStrip ? .now : nil)
                    .id(Self.libraryAnchor)
            }
            .padding(.top, 8)
            .padding(.bottom, OneDay.tabBarClearance + 20)
            .containerRelativeFrame(.horizontal)
        }
        .scrollIndicators(.hidden)
        .overlay { joiningOverlay }
    }

    private var library: ClipLibrary {
        let mine = [account.account?.id, RoomProgress.soloAuthorID, "local"].compactMap { $0 }
        return ClipLibrary(
            stories: store.challenges.map { ($0, store.recordedClips(for: $0.id)) },
            drafts: drafts.sortedDrafts.map { ($0, drafts.url(for: $0)) },
            myIDs: Set(mine))
    }

    @ViewBuilder
    private var joiningOverlay: some View {
        if joining {
            VStack(spacing: 14) {
                ProgressView(Strings.joining)
                    .controlSize(.large)
                Button(Strings.cancel) {
                    joinAttempt += 1
                    joinTask?.cancel()
                    joinTask = nil
                    joining = false
                }
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(OneDay.brandText)
            }
            .padding(24)
            .glassSurface()
        }
    }


    private var sharedStories: [Challenge] {
        store.challenges.filter(\.isShared)
            .map { ($0, Self.latestClip(store.recordedClips(for: $0.id))?.recordedAt ?? $0.startDate) }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private var friendsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: OneDay.Space.s) {
                    greetingRow
                    MoodTodayBadge()
                }
                .padding(.horizontal, 20)
                friendsHeader
                if !account.isSignedIn, !sharedStories.isEmpty {
                    signedOutBanner
                }

                if onOpenPersonal != nil || !sharedStories.isEmpty {
                    LazyVGrid(columns: Self.tileColumns, alignment: .leading, spacing: 14) {
                        if let onOpenPersonal {
                            personalTile(onOpen: onOpenPersonal)
                        }
                        ForEach(sharedStories) { challenge in
                            storyRow(challenge, membersAsCover: true)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                if sharedStories.isEmpty {
                    friendsEmptyState
                }
            }
            .padding(.top, 8)
            .padding(.bottom, OneDay.tabBarClearance + 20)
            .containerRelativeFrame(.horizontal)
        }
        .scrollIndicators(.hidden)
        .overlay { joiningOverlay }
    }

    private var signedOutBanner: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Strings.signedOutRoomsTitle)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                Text(Strings.signedOutRoomsBody)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
            }
            Spacer(minLength: 6)
            Button(Strings.signIn) {
                joinCode = ""
                afterSignIn = {}
            }
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black, in: Capsule())
            .accessibilityIdentifier("rooms-sign-in")
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .glassSurface(radius: 18)
        .padding(.horizontal, 20)
    }

    static let tileColumns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    private func personalTile(onOpen: @escaping () -> Void) -> some View {
        let latest = library.clips.filter(\.isMine).max { $0.recordedAt < $1.recordedAt }
        return Button(action: onOpen) {
            PortraitTile(
                coverURL: latest?.url, refreshToken: latest?.recordedAt,
                title: Strings.surfacePlans,
                subtitle: latest.flatMap { latestLine($0.clip) } ?? Strings.roomNobodyFilmed
            ) {
                AvatarDot(name: account.account?.displayName, size: 30, image: AvatarStore.shared.image)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("rooms-personal")
    }

    struct DebugAlert {
        let title: String
        let message: String
    }

    struct InviteRequest: Identifiable {
        let id = UUID()
        let roomID: UUID?
    }

    private func inviteFriends() {
        let rooms = sharedStories
        switch rooms.count {
        case 0:
            onCompose()
        case 1:
            showInvite(for: rooms[0])
        default:
            inviteRequest = InviteRequest(roomID: nil)
        }
    }

    private func showInvite(for room: Challenge) {
        openRoomForInvite(room)
        inviteRequest = InviteRequest(roomID: room.id)
    }

    private func openRoomForInvite(_ room: Challenge) {
        if let code = room.roomCode { RoomShareNudge.markOffered(code: code) }
        path = [room.id]
    }

    private func inviteSheet(_ request: InviteRequest) -> some View {
        FriendsInviteSheet(
            rooms: sharedStories,
            initialRoomID: request.roomID,
            memberCount: { store.members(for: $0.id).count },
            onPick: { openRoomForInvite($0) },
            onNewRoom: {
                inviteRequest = nil
                onCompose()
            })
    }

    #if DEBUG
    private func createDebugTestRoomIfAsked() {
        guard DebugTestRoom.consumeLaunchRequest() else { return }
        guard account.isSignedIn else {
            debugAlert = DebugAlert(
                title: Strings.signInRequiredTitle, message: Strings.debugTestRoomNeedsSignIn)
            return
        }
        Task {
            do {
                let room = try await DebugTestRoom.create(in: store)
                showInvite(for: room)
            } catch {
                debugAlert = DebugAlert(
                    title: Strings.debugTestRoomFailedTitle, message: error.localizedDescription)
            }
        }
    }
    #endif

    private var friendsHeader: some View {
        HStack(spacing: 11) {
            Text(Strings.surfaceFriends)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(OneDay.ink)
            Spacer(minLength: 6)
            joinButton
            newRoomButton
        }
        .padding(.horizontal, 20)
    }

    private var newRoomButton: some View {
        Button { onCompose() } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .heavy))
                Text(Strings.newRoomRow)
                    .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(OneDay.onBrand)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(OneDay.brandHorizontal, in: Capsule())
            .oneDayGlow(strength: 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("friends-new-room")
    }

    private var friendsEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(OneDay.brandText)
                .frame(width: 68, height: 68)
                .background(Color.oneDayBrand.opacity(0.12), in: Circle())
                .padding(.top, 8)

            VStack(spacing: 7) {
                Text(Strings.friendsEmptyTitle)
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                    .multilineTextAlignment(.center)
                Text(Strings.friendsEmptyBody)
                    .font(.system(size: 14.5, weight: .medium, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
                    .multilineTextAlignment(.center)
            }

            Button(Strings.inviteFriends) { inviteFriends() }
                .buttonStyle(.primaryAction)
                .padding(.top, 4)
                .accessibilityIdentifier("friends-invite")

            Button(Strings.haveInviteCode) {
                joinCode = ""
                showJoin = true
            }
            .font(.system(size: 13.5, weight: .bold, design: .rounded))
            .foregroundStyle(OneDay.brandText)
            .accessibilityIdentifier("friends-join-room")
        }
        .frame(maxWidth: .infinity)
        .padding(26)
        .glassSurface(radius: OneDay.Radius.hero)
        .padding(.horizontal, 20)
    }

    private var greetingRow: some View {
        HStack(spacing: 11) {
            Button { showSettings = true } label: {
                AvatarDot(name: account.account?.displayName, size: 42, image: AvatarStore.shared.image)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Strings.settings)

            VStack(alignment: .leading, spacing: 3) {
                Text(Strings.greeting(
                    name: account.account?.displayName,
                    hour: Calendar.current.component(.hour, from: .now)))
                    .font(.system(size: 16.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                dateline
            }
            Spacer(minLength: 0)
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            if onBackToRooms != nil {
                mineHeader
            } else {
                greetingAndCompose
            }
        }
        .padding(.horizontal, 20)
    }

    private var mineHeader: some View {
        HStack(spacing: OneDay.Space.m) {
            Button { showSettings = true } label: {
                AvatarDot(name: account.account?.displayName, size: 48, image: AvatarStore.shared.image)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Strings.settings)

            VStack(alignment: .leading, spacing: OneDay.Space.xs) {
                Text(Strings.surfacePlans)
                    .font(OneDay.Font.title)
                    .foregroundStyle(OneDay.ink)
                Text(mineStatsLine)
                    .font(OneDay.Font.subhead)
                    .foregroundStyle(OneDay.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: OneDay.Space.s)
            composeButton
        }
        .accessibilityIdentifier("mine-header")
    }

    private var mineStatsLine: String {
        let mine = library.scoped(includingFriends: false).clips
        let calendar = Calendar.current
        let week = calendar.dateInterval(of: .weekOfYear, for: .now)
        let days = Set(mine.filter { week?.contains($0.recordedAt) ?? false }
            .map { calendar.startOfDay(for: $0.recordedAt) }).count
        return Strings.mineStats(days: days, clips: mine.count)
    }

    private var showsTodayStrip: Bool {
        onBackToRooms != nil && Calendar.current.isDateInToday(selectedDay) && !clips(on: .now).isEmpty
    }

    @ViewBuilder
    private var todayStrip: some View {
        let today = clips(on: .now).sorted { $0.recordedAt < $1.recordedAt }
        if showsTodayStrip {
            VStack(alignment: .leading, spacing: OneDay.Space.m) {
                HStack {
                    SectionLabel(text: Strings.mineTodayHeader)
                    Spacer(minLength: 0)
                    Text(Strings.libraryClipCount(today.count))
                        .font(OneDay.Font.caption)
                        .foregroundStyle(OneDay.inkFaint)
                }
                .padding(.horizontal, OneDay.Space.xl)
                ScrollView(.horizontal) {
                    HStack(spacing: OneDay.Space.s) {
                        ForEach(today) { clip in
                            ClipTile(url: clip.url, refreshToken: clip.recordedAt, bedsInsteadOfCrops: true)
                                // Fixed tile size: a row of 9:16 previews, like the camera's dated look.
                                .frame(width: 112, height: 199)
                                .overlay(alignment: .bottomTrailing) {
                                    ClipTileLabel(text: clip.recordedAt.formatted(date: .omitted, time: .shortened))
                                }
                        }
                    }
                    .padding(.horizontal, OneDay.Space.xl)
                }
                .scrollIndicators(.hidden)
                Button(Strings.mineMakeTodayVlog, systemImage: "film.stack.fill") {
                    vlogRequest = VlogRequest(clips: today)
                }
                .buttonStyle(.primaryAction)
                .padding(.horizontal, OneDay.Space.xl)
                .accessibilityIdentifier("mine-make-today-vlog")
            }
        }
    }

    private var greetingAndCompose: some View {
        HStack(spacing: 6) {
            greetingRow
            composeButton
        }
    }

    private var composeButton: some View {
        Button { onCompose() } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .heavy))
                Text(Strings.surfaceCompose)
                    .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(OneDay.onBrand)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(OneDay.brandHorizontal, in: Capsule())
            .oneDayGlow(strength: 0.5)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home-compose")
    }

    private var joinButton: some View {
        Button {
            joinCode = ""
            showJoin = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "person.2.badge.plus")
                    .font(.system(size: 13, weight: .bold))
                Text(Strings.joinShort)
                    .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(OneDay.ink)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(OneDay.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(OneDay.hairline, lineWidth: 1))
            .oneDaySoftShadow(strength: 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.enterInviteCode)
        .accessibilityIdentifier("home-join-room")
    }

    private var dateline: some View {
        let summary = HomeHeaderSummary()
        return HStack(spacing: 6) {
            Text(summary.dateLine)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(OneDay.inkSoft)
                .lineLimit(1)
                .fixedSize()

        }
    }

    @ViewBuilder
    private var draftsRow: some View {
        if !drafts.isEmpty {
            Button { showDrafts = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(OneDay.brandText)
                        .frame(width: 34, height: 34)
                        .background(
                            Color.oneDayBrand.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text(Strings.draftsPending(drafts.count))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(OneDay.brandText)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(OneDay.inkFaint)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    OneDay.surface,
                    in: RoundedRectangle(cornerRadius: OneDay.Radius.chip, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: OneDay.Radius.chip, style: .continuous)
                        .strokeBorder(
                            Color.oneDayBrand.opacity(0.28),
                            style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .accessibilityIdentifier("drafts-row")
        }
    }

    @ViewBuilder
    private var todayCards: some View {
        if !Calendar.current.isDateInToday(selectedDay) {
            otherDayCards
        } else if let plan = store.todaysPlan() {
            HStack(alignment: .top, spacing: 12) {
                if onBackToRooms == nil {
                    MoodTodayCard(compact: true)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                TodayPlanCard(
                    challenge: plan,
                    progress: cardState(for: plan).progress,
                    onFilm: { recordPlanSlot = PlanSlot(challengeID: plan.id, slot: $0) },
                    onOpen: { path.append(plan.id) })
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
        } else if onBackToRooms == nil {
            MoodTodayCard()
                .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private var otherDayCards: some View {
        let isFuture = selectedDay > .now
        let mood = isFuture ? nil : moods?.mood(on: selectedDay)
        if let plan = store.plan(on: selectedDay) {
            HStack(alignment: .top, spacing: 12) {
                if let mood { MoodDayCard(entry: mood).frame(maxHeight: .infinity, alignment: .top) }
                TodayPlanCard(
                    challenge: plan,
                    progress: cardState(for: plan).progress,
                    onFilm: { recordPlanSlot = PlanSlot(challengeID: plan.id, slot: $0) },
                    onOpen: { path.append(plan.id) },
                    title: Strings.dayPlanTitle(selectedDay))
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
        } else if isFuture {
            Button(Strings.planAhead, systemImage: "square.and.pencil") { planningAhead = true }
                .buttonStyle(.primaryAction)
                .padding(.horizontal, 20)
                .accessibilityIdentifier("day-plan-ahead")
        }
        if !isFuture, store.plan(on: selectedDay) == nil {
            let dayClips = clips(on: selectedDay).sorted { $0.recordedAt < $1.recordedAt }
            let recap = DayRecapCard(count: dayClips.count) { vlogRequest = VlogRequest(clips: dayClips) }
            Group {
                if let mood, !dayClips.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        MoodDayCard(entry: mood).frame(maxHeight: .infinity, alignment: .top)
                        recap.frame(maxHeight: .infinity, alignment: .top)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } else if let mood {
                    MoodDayCard(entry: mood, wide: true)
                } else if !dayClips.isEmpty {
                    recap
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func clips(on day: Date) -> [LibraryClip] {
        library.scoped(includingFriends: false).clips
            .filter { Calendar.current.isDate($0.recordedAt, inSameDayAs: day) }
    }

    private func todaySection(_ challenges: [Challenge], label: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: label)
                .padding(.horizontal, 20)
            ForEach(challenges) { challenge in
                todayRow(challenge)
            }
        }
    }

    private func todayRow(_ challenge: Challenge) -> some View {
        let state = cardState(for: challenge)
        return TodayStoryRow(
            challenge: challenge,
            progress: state.progress,
            coverURL: state.coverURL,
            refreshToken: state.refreshToken,
            onContinue: { recordChallenge = challenge },
            onOpen: { path.append(challenge.id) })
            .padding(.horizontal, 20)
    }

    private func todayStories(leading: Challenge) -> [Challenge] {
        let calendar = Calendar.current
        let others = store.challenges.filter { challenge in
            guard !challenge.isShared, challenge.id != leading.id, !challenge.isComplete, !challenge.cards.isEmpty
            else { return false }
            if challenge.isOneDay { return calendar.isDateInToday(challenge.startDate) }
            return (1...max(challenge.cards.count, 1)).contains(challenge.currentDay)
        }
        return [leading] + others.sorted { $0.startDate > $1.startDate }
    }

    private func heroSection(_ challenge: Challenge, label: String) -> some View {
        let state = cardState(for: challenge)
        return VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: label)
                .padding(.horizontal, 20)

            StoryCard(
                challenge: challenge,
                memberNames: store.members(for: challenge.id).map(\.name),
                progress: state.progress,
                coverURL: state.coverURL,
                refreshToken: state.refreshToken,
                onContinue: { recordChallenge = challenge },
                onOpen: { path.append(challenge.id) })
                .padding(.horizontal, 20)
        }
    }

    private var startTodayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: Strings.startTodayLabel)
                .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 12) {
                Text(Strings.startTodayBody)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)

                Button(Strings.startTodayCTA) { onCompose() }
                    .buttonStyle(.primaryAction)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .glassSurface(radius: OneDay.Radius.card)
            .padding(.horizontal, 20)
        }
    }

    private var emptyState: some View {
        EmptyFrame(radius: OneDay.Radius.card) {
            VStack(spacing: OneDay.Space.m) {
                Image(systemName: "video.badge.plus")
                    .font(OneDay.Font.title)
                    .foregroundStyle(OneDay.brandText)
                Text(Strings.mineEmptyTitle)
                    .font(OneDay.Font.headline)
                    .foregroundStyle(OneDay.ink)
                Text(Strings.mineEmptyHint)
                    .font(OneDay.Font.subhead)
                    .foregroundStyle(OneDay.inkSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(OneDay.Space.l)
            .padding(.vertical, OneDay.Space.s)
        }
        .padding(.horizontal, OneDay.Space.xl)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home-guide")
    }

    private var timelineSection: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            if let title = stories.sectionTitle {
                SectionLabel(text: title)
                    .padding(.horizontal, 20)
            }

            ForEach(timeline.days) { day in
                VStack(alignment: .leading, spacing: 9) {
                    Text(day.label)
                        .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(OneDay.inkFaint)
                        .padding(.horizontal, 20)

                    ForEach(day.stories) { challenge in
                        storyRow(challenge)
                    }
                }
            }
        }
    }

    private func storyRow(_ challenge: Challenge, membersAsCover: Bool = false) -> some View {
        let state = cardState(for: challenge)
        let members = store.members(for: challenge.id)
        return Button {
            path.append(challenge.id)
        } label: {
            StoryRowCard(
                challenge: challenge,
                progress: state.progress,
                coverURL: membersAsCover ? state.latest?.url ?? state.coverURL : state.coverURL,
                refreshToken: membersAsCover ? state.latest?.recordedAt ?? state.refreshToken : state.refreshToken,
                memberNames: members.map(\.name),
                showsMembersAsCover: membersAsCover,
                roomMembers: members,
                memberImages: membersAsCover ? store.memberAvatarsByID(for: challenge.id) : [:],
                latestLine: membersAsCover ? latestLine(state.latest) : nil,
                latestCaption: membersAsCover ? state.latest?.captions.firstText : nil,
                hasNew: membersAsCover && hasNew(challenge, latest: state.latest))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(membersAsCover ? "room-preview-card" : "story-row")
        .contextMenu {
            Button(
                challenge.isShared ? Strings.leaveRoom : Strings.deleteChallenge,
                role: .destructive
            ) {
                pendingDeletion = challenge
            }
        }
        .padding(.horizontal, membersAsCover ? 0 : 20)
    }



    @ViewBuilder
    private func recorder(for challenge: Challenge, preferredDay: Int? = nil) -> some View {
        let slot = slotToRecord(in: challenge, preferred: preferredDay)
        let label = ChallengePresenter(challenge: challenge).slotLabel(forSlot: slot)
        RecordClipView(
            day: slot,
            slotTitle: challenge.isTimeOnly ? nil : label,
            momentCount: challenge.isShared ? 0 : challenge.cards.count,
            clipLength: challenge.resolvedClipLength,
            showsPrompt: !challenge.isTimeOnly && label != nil,
            orientation: challenge.resolvedOrientation,
            lockedCamera: challenge.cameraStyle
        ) { url, overlayText in
            store.saveClip(
                from: url, day: slot, challengeID: challenge.id, overlayText: overlayText)
            if store.challenge(challenge.id)?.isComplete == true {
                path.append(challenge.id)
            }
        }
    }

    private func slotToRecord(in challenge: Challenge, preferred: Int?) -> Int {
        if let preferred,
           let card = challenge.cards.first(where: { $0.day == preferred }),
           card.clipFileName == nil {
            return card.day
        }
        return cardState(for: challenge).progress.slotToOffer(
            today: challenge.isOneDay ? nil : challenge.currentDay)
    }


    private func consumePendingJoinCode() {
        guard let code = pendingJoinCode else { return }
        guard onActivate?() != false else { return }
        pendingJoinCode = nil
        joinCode = code
        startJoin(code)
    }

    private func consumeLaunchAction() {
        guard let action = launchAction else { return }
        guard onActivate?() != false else { return }
        launchAction = nil
        switch action {
        case .quickStart:
            let challenge = store.createQuickStart()
            path = [challenge.id]
        case .newStory:
            onCompose()
        case .join:
            joinCode = ""
            showJoin = true
        case .record(let id):
            recordChallenge = store.challenge(id)
        case .openStory(let id):
            guard store.challenge(id) != nil else { return }
            path = [id]
        }
    }

    private func openPendingNotificationRoute() {
        guard let route = NotificationRouteInbox.peek(),
              let challenge = store.challenge(route.challengeID)
        else { return }
        guard (scope == .friends) == challenge.isShared,
              onActivate?() != false else { return }
        _ = NotificationRouteInbox.consume()
        if challenge.isComplete {
            path = [challenge.id]
        } else {
            notificationRecordRoute = route
        }
    }

    private func startJoin(_ code: String) {
        let code = code.uppercased().trimmingCharacters(in: .whitespaces)
        guard code.count >= 6 else { return }
        let run = {
            joining = true
            let attempt = joinAttempt
            joinTask = Task {
                defer {
                    if attempt == joinAttempt {
                        joining = false
                        joinTask = nil
                    }
                }
                do {
                    let challenge = try await store.joinRoom(code: code)
                    guard attempt == joinAttempt else { return }
                    path = [challenge.id]
                } catch is CancellationError {
                    return
                } catch {
                    guard attempt == joinAttempt else { return }
                    errorText = error.localizedDescription
                }
            }
            Task {
                try? await Task.sleep(for: .seconds(20))
                guard attempt == joinAttempt, joining else { return }
                joinAttempt += 1
                joinTask?.cancel()
                joinTask = nil
                joining = false
                errorText = Strings.joinTimedOut
            }
        }
        if account.isSignedIn { run() } else { afterSignIn = run }
    }


    private struct CardState {
        let progress: RoomProgress
        let coverURL: URL?
        let refreshToken: Date?
        let latest: DayClip?
    }

    private func cardState(for challenge: Challenge) -> CardState {
        let clips = store.recordedClips(for: challenge.id)
        let first = clips.min {
            ($0.recordedAt ?? .distantFuture, $0.day) < ($1.recordedAt ?? .distantFuture, $1.day)
        }
        return CardState(
            progress: RoomProgress(
                momentCount: challenge.cards.count,
                clips: clips,
                myID: account.account?.id ?? RoomProgress.soloAuthorID),
            coverURL: first?.url,
            refreshToken: first?.recordedAt,
            latest: Self.latestClip(clips))
    }

    private static func latestClip(_ clips: [DayClip]) -> DayClip? {
        clips.filter { $0.recordedAt != nil }.max { $0.recordedAt! < $1.recordedAt! }
    }

    private func latestLine(_ clip: DayClip?) -> String? {
        guard let clip, let date = clip.recordedAt else { return nil }
        let name = isMine(clip) ? Strings.youLabel : (clip.authorName ?? "")
        let when = Calendar.current.isDateInToday(date)
            ? date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
            : date.formatted(.dateTime.month().day())
        return name.isEmpty ? when : "\(name) · \(when)"
    }

    private func isMine(_ clip: DayClip) -> Bool {
        clip.authorID == nil || clip.authorID == RoomProgress.soloAuthorID
            || clip.authorID == account.account?.id
    }

    private func hasNew(_ challenge: Challenge, latest: DayClip?) -> Bool {
        guard let latest, let date = latest.recordedAt, !isMine(latest) else { return false }
        guard let seen = roomSeenAt[challenge.id.uuidString] else { return true }
        return date > Date(timeIntervalSince1970: seen)
    }

    private static let roomSeenKey = "roomSeenAt"

    private func markSeen(_ id: UUID) {
        roomSeenAt[id.uuidString] = Date.now.timeIntervalSince1970
        UserDefaults.standard.set(roomSeenAt, forKey: Self.roomSeenKey)
    }

}

struct PlanSlot: Identifiable, Equatable {
    let challengeID: UUID
    let slot: Int
    var id: String { "\(challengeID.uuidString).\(slot)" }
}
