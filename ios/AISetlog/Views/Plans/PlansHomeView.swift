import SwiftUI

/// Screen 1 — today's story.
///
/// Not a list of plans. The screen answers one question ("what am I filming
/// today, and with whom?") with one object: the hero `StoryCard`. Everything
/// else — other stories, finished films — is secondary and sits below the
/// fold, deliberately quieter.
struct PlansHomeView: View {
    @Environment(ChallengeStore.self) private var store
    @Environment(AccountStore.self) private var account
    /// Only for the standing count in `draftsRow`. The camera keeps its own
    /// entry (`DraftsEntryButton`) and the shell keeps the four-second
    /// confirmation; this is the third and quietest way back to the same list.
    @Environment(ClipDraftStore.self) private var drafts
    @Binding var pendingJoinCode: String?
    @Binding var launchAction: HomeLaunchAction?
    /// What to lead with and what to list under it, as one decision. See
    /// `HomeStories`.
    let stories: HomeStories
    /// 故事 shows everything; 朋友 shows only shared stories, with invite and
    /// join up front. Same screen so the join sheet, sign-in and the story push
    /// exist once.
    var scope: Scope = .stories
    enum Scope { case stories, friends }
    /// Open the composer. The composer used to be a
    /// `fullScreenCover` owned by this screen; it is a sibling surface now, so
    /// every in-page CTA that used to raise the cover asks the shell instead.
    /// One composer, one place it can be.
    let onCompose: () -> Void

    @State private var path: [UUID] = []
    @State private var showJoin = false
    @State private var showSettings = false
    @State private var showRoomDemo = false
    @State private var showDrafts = false
    @State private var joinCode = ""
    @State private var joining = false
    /// Bumped to abandon the current join — by the cancel button or the
    /// timeout. The in-flight call checks it before doing anything with its
    /// result, so a late success can't navigate somewhere the person left.
    @State private var joinAttempt = 0
    @State private var errorText: String?
    @State private var recordChallenge: Challenge?
    /// The story a long press is proposing to delete, held until it's confirmed.
    @State private var pendingDeletion: Challenge?
    @State private var notificationRecordRoute: NotificationRecordRoute?
    /// When set, present sign-in and run this once the user finishes.
    @State private var afterSignIn: (() -> Void)?
    /// 我的's select mode and what's been picked; the bar and the vlog sheet
    /// sit on this page so they float over the scroll view.
    @State private var isSelectingClips = false
    @State private var pickedClips: [LibraryClip] = []
    @State private var vlogRequest: VlogRequest?

    /// Bound only so a language change re-renders the screen.
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var hero: Challenge? { stories.hero.challenge }
    /// Everything except the hero, by the day it was for. See `StoryTimeline`.
    private var timeline: StoryTimeline { stories.timeline }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                OneDayCanvas()
                content
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                StoryTimelineView(challengeID: id)
            }
        }
        .fullScreenCover(item: $recordChallenge) { challenge in
            recorder(for: challenge)
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
            // Not a fixed height: with the keyboard up on an SE, 430pt pushed
            // the join button off screen. The sheet scrolls and pins its button.
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: Binding(
            get: { afterSignIn != nil },
            set: { if !$0 { afterSignIn = nil } }
        )) {
            SignInView { afterSignIn?() }
                .presentationDetents([.medium])
                // Cancelling sign-in used to drop the six digits with the
                // pending action: the sheet closed, `afterSignIn` was cleared,
                // and reopening 加入 started from an empty field. The code the
                // friend sent is the one thing here the app can't reproduce,
                // so cancelling puts the sheet back with it still typed.
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
        // Launch routing belongs to the 故事 instance alone. The 朋友 one is
        // mounted beside it and would otherwise open every notification's
        // camera a second time.
        .onAppear {
            guard scope == .stories else { return }
            if UserDefaults.standard.bool(forKey: AppSkin.reopenSettingsKey) {
                UserDefaults.standard.removeObject(forKey: AppSkin.reopenSettingsKey)
                showSettings = true
            }
            openPendingNotificationRoute()
            consumePendingJoinCode()
            consumeLaunchAction()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .oneDayNotificationRoutePending
        )) { _ in
            guard scope == .stories else { return }
            openPendingNotificationRoute()
        }
        .onChange(of: pendingJoinCode) { _, _ in consumePendingJoinCode() }
        .onChange(of: launchAction) { _, _ in consumeLaunchAction() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch scope {
        case .stories: storiesContent
        case .friends: friendsContent
        }
    }

    private var storiesContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header

                // Off unless something asked for it — see `DemoEntries`. It
                // was an always-on button on the first screen of every Debug
                // build, which is where 1.3's 冗余内容清理 found it.
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

                switch stories.hero {
                case .today(let challenge):
                    heroSection(challenge, label: Strings.todaysStory)
                case .resume(let challenge):
                    heroSection(challenge, label: Strings.resumeStory)
                case .startToday:
                    // 1.5: no "start today's story" card. With nothing in
                    // progress the archive is the page, and the round camera
                    // button is the way to add to it. Only a first run, with
                    // no stories and no clips, still gets the mascot.
                    if store.challenges.isEmpty, library.clips.isEmpty { emptyState }
                }

                // Replaces the date-grouped story list (`timelineSection`):
                // every clip, filterable by room, with a calendar.
                LibrarySection(
                    library: library,
                    rooms: store.challenges.filter(\.isShared),
                    onOpenStory: { path.append($0) },
                    onOpenDrafts: { showDrafts = true },
                    isSelecting: $isSelectingClips,
                    picked: $pickedClips)
            }
            .padding(.top, 8)
            .padding(.bottom, OneDay.tabBarClearance + 20)
            // Belt and braces: the page can never be wider than the scroll
            // viewport. Without this a single over-eager child silently drags
            // every section off both edges of the display.
            .containerRelativeFrame(.horizontal)
        }
        .scrollIndicators(.hidden)
        .overlay { joiningOverlay }
        .overlay(alignment: .bottom) {
            if isSelectingClips {
                LibrarySelectionBar(picked: pickedClips) {
                    vlogRequest = VlogRequest(clips: pickedClips)
                }
                .padding(.bottom, OneDay.tabBarClearance + 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(item: $vlogRequest) { request in
            LibraryVlogSheet(clips: request.clips)
        }
    }

    /// Every clip on this device, as 我的 lists it.
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
                // A full-screen spinner with no way out and no ceiling is
                // indistinguishable from a frozen app: a bad code or no
                // signal left the person holding a phone that spun until
                // they force-quit it. Cancelling does not stop the network
                // call — it stops *waiting* for it, which is the part they
                // are stuck in.
                Button(Strings.cancel) {
                    joinAttempt += 1
                    joining = false
                }
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(OneDay.brandText)
            }
            .padding(24)
            .glassSurface()
        }
    }

    // MARK: - 朋友

    /// Shared stories, newest first.
    private var sharedStories: [Challenge] {
        store.challenges.filter(\.isShared).sorted { $0.startDate > $1.startDate }
    }

    private var friendsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                friendsHeader

                if sharedStories.isEmpty {
                    friendsEmptyState
                } else {
                    Button(Strings.inviteFriends) { onCompose() }
                        .buttonStyle(.primaryAction)
                        .padding(.horizontal, 20)
                        .accessibilityIdentifier("friends-invite")

                    LazyVStack(alignment: .leading, spacing: 9) {
                        ForEach(sharedStories) { challenge in
                            storyRow(challenge)
                        }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, OneDay.tabBarClearance + 20)
            .containerRelativeFrame(.horizontal)
        }
        .scrollIndicators(.hidden)
        .overlay { joiningOverlay }
    }

    private var friendsHeader: some View {
        HStack(spacing: 11) {
            Text(Strings.surfaceFriends)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(OneDay.ink)
            Spacer(minLength: 6)
            joinButton
        }
        .padding(.horizontal, 20)
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

            Button(Strings.inviteFriends) { onCompose() }
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

    /// Who you are, what day it is, how far today has got — then the two
    /// actions. The wordmark used to sit here; it's the one fact a person
    /// opening 1day already has, and it was crowding out the two they didn't.
    ///
    /// Nothing up here is allowed to outshine "continue today's story" in the
    /// card below.
    ///
    /// One action on the right: 新建. See the comment on the button for its
    /// history; 加入 lives in the 朋友 header (`joinButton`).
    private var header: some View {
        HStack(spacing: 11) {
            Button { showSettings = true } label: {
                AvatarDot(name: account.account?.displayName, size: 42)
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

            Spacer(minLength: 6)

            // 新建 is back up here as of 1.5, when the bar's middle slot went
            // to the camera — labelled and filled, not the wordless 36pt plus
            // it was before 1.3. 加入 moved to 朋友, where rooms live.
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
        .padding(.horizontal, 20)
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
            // 加入 is two glyphs and Join is four, so the capsule that fits
            // in Chinese is narrower than the English word and the label
            // wrapped to "Joi / n". Fixing the label's width makes the
            // greeting column absorb the squeeze instead — it already
            // shrinks by design, and the dateline drops its pips first.
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

    /// Date, and — when there's a story in progress — how much of it is in.
    /// The pips are the first thing to go on a narrow screen; the numbers
    /// carry the same fact and always fit.
    private var dateline: some View {
        let summary = HomeHeaderSummary(progress: hero.map { cardState(for: $0).progress })
        return HStack(spacing: 6) {
            Text(summary.dateLine)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(OneDay.inkSoft)
                .lineLimit(1)
                .fixedSize()

            if summary.hasProgress, let recorded = summary.recorded, let total = summary.total {
                Circle()
                    .fill(OneDay.inkFaint)
                    .frame(width: 3, height: 3)

                Text(summary.progressLine)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
                    .lineLimit(1)
                    .fixedSize()

                MomentPips(filled: recorded, total: total, size: 4.5, tint: .oneDayBrand)
                    .layoutPriority(-1)
            }
        }
    }

    /// `label` varies because the card isn't always today's story — calling an
    /// unfinished story from yesterday "today's story" is the kind of small lie
    /// that makes the whole screen untrustworthy.
    /// Clips that were kept on the way out of the camera and have not been
    /// filed into a story yet.
    ///
    /// A row rather than the floating capsule it used to be — see
    /// `RootShellView.draftsBanner` for why. Last in the list on purpose: it is
    /// a loose end, not a thing to do today, and putting it under the stories
    /// means it is somewhere you arrive rather than somewhere you are sent.
    ///
    /// Dashed border and no cover: everything above it is a story, and this
    /// has to be reachable without being mistaken for one.
    @ViewBuilder
    private var draftsRow: some View {
        if !drafts.isEmpty {
            Button { showDrafts = true } label: {
                HStack(spacing: 12) {
                    // A brand tint rather than `oneDayMist`, which is a fixed
                    // light hex: on a dark card it lit up as the brightest
                    // thing in the row, and on a light one it matched the card
                    // exactly and vanished. An alpha of the accent lands right
                    // against both.
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
                // `OneDay.surface`, the card background the story rows use, so
                // this sits at the same depth as them. `oneDaySurface` — the
                // soft chip fill — collapses onto the card in dark mode and
                // onto the page in light.
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

    /// Nothing to lead with, but this isn't a first run — there are films
    /// behind this screen, just nothing going on today. Compact on purpose:
    /// the timeline below it is the interesting part.
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

    /// No active story: the mascot, one line of why, one button.
    private var emptyState: some View {
        VStack(spacing: 16) {
            OneDayBuddy(size: 76)
                .padding(.top, 12)

            VStack(spacing: 7) {
                Text(Strings.noStoryTitle)
                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                Text(Strings.noStoryBody)
                    .font(.system(size: 14.5, weight: .medium, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
                    .multilineTextAlignment(.center)
            }

            Button(Strings.startTodaysStory) { onCompose() }
                .buttonStyle(.primaryAction)
                .padding(.top, 4)

            // The empty state used to offer one door. Somebody whose first
            // contact with 1Day is a friend's six-digit code had to find the
            // icon in the header instead.
            Button(Strings.haveInviteCode) {
                joinCode = ""
                showJoin = true
            }
            .font(.system(size: 13.5, weight: .bold, design: .rounded))
            .foregroundStyle(OneDay.brandText)
            .accessibilityIdentifier("empty-join-room")
        }
        .padding(26)
        .glassSurface(radius: OneDay.Radius.hero)
        .padding(.horizontal, 20)
    }

    /// Everything that isn't today, newest day first. One label per day, then
    /// that day's stories — finished or not, they sit together, because "when"
    /// is the axis people actually remember by.
    /// Lazy because each row costs a pass over its story's clips: an eager
    /// stack rebuilt every off-screen row on every render, and this list only
    /// grows.
    private var timelineSection: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            // Nil when nothing in the list has been filmed — the rows still
            // show, the heading doesn't. See `HomeStories.sectionTitle`.
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

    private func storyRow(_ challenge: Challenge) -> some View {
        let state = cardState(for: challenge)
        return Button {
            path.append(challenge.id)
        } label: {
            StoryRowCard(
                challenge: challenge,
                progress: state.progress,
                coverURL: state.coverURL,
                refreshToken: state.refreshToken,
                memberNames: store.members(for: challenge.id).map(\.name))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(
                challenge.isShared ? Strings.leaveRoom : Strings.deleteChallenge,
                role: .destructive
            ) {
                // Ask, don't do. A long press is the easiest gesture in the app
                // to trigger by accident, and this menu item used to delete
                // every clip in a story outright — the app's most destructive
                // frequent action was the one without a confirmation, while
                // "delete account" had a full dialog.
                pendingDeletion = challenge
            }
        }
        .padding(.horizontal, 20)
    }


    // MARK: - Recorder

    /// Opens the camera on an unfilmed slot (or a specific one, when a
    /// notification asked for it).
    @ViewBuilder
    private func recorder(for challenge: Challenge, preferredDay: Int? = nil) -> some View {
        let slot = slotToRecord(in: challenge, preferred: preferredDay)
        RecordClipView(
            day: slot,
            slotTitle: challenge.isTimeOnly
                ? nil
                : ChallengePresenter(challenge: challenge).title(forSlot: slot),
            momentCount: challenge.cards.count,
            clipLength: challenge.resolvedClipLength,
            showsPrompt: !challenge.isTimeOnly,
            orientation: challenge.resolvedOrientation,
            lockedCamera: challenge.cameraStyle
        ) { url, overlayText in
            store.saveClip(
                from: url, day: slot, challengeID: challenge.id, overlayText: overlayText)
            // Finishing the last moment from the home card should land on the
            // timeline, so the film is one glance away.
            if store.challenge(challenge.id)?.isComplete == true {
                path.append(challenge.id)
            }
        }
    }

    /// A default, not a decision. This shortcut skips the story page entirely,
    /// so it has to open the camera on *something* — a home card has no room
    /// to lay seven moments out and ask. Picking any moment yourself is one
    /// tap further in, where `StoryAgenda` offers all of them at once and this
    /// same slot is only the row wearing a question mark.
    private func slotToRecord(in challenge: Challenge, preferred: Int?) -> Int {
        if let preferred,
           let card = challenge.cards.first(where: { $0.day == preferred }),
           card.clipFileName == nil {
            return card.day
        }
        // Today's, when today is still empty — see `RoomProgress.slotToOffer`.
        // Otherwise the first moment *nobody* has filmed: defaulting to one a
        // friend already covered, while an untouched one waits further down, is
        // how a room ends up with three takes of breakfast and no evening.
        return cardState(for: challenge).progress.slotToOffer(
            today: challenge.isOneDay ? nil : challenge.currentDay)
    }

    // MARK: - Routing

    private func consumePendingJoinCode() {
        guard let code = pendingJoinCode else { return }
        pendingJoinCode = nil
        // Kept in the join field too: if sign-in is cancelled, startJoin's
        // deferred run never fires, and the link's code would be gone.
        joinCode = code
        startJoin(code)
    }

    private func consumeLaunchAction() {
        guard let action = launchAction else { return }
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
            // Replaces rather than appends: the composer is not a screen you
            // go "back" to, and it is no longer on this stack to go back to.
            guard store.challenge(id) != nil else { return }
            path = [id]
        }
    }

    private func openPendingNotificationRoute() {
        guard let route = NotificationRouteInbox.consume(),
              let challenge = store.challenge(route.challengeID)
        else { return }
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
            Task {
                defer { if attempt == joinAttempt { joining = false } }
                do {
                    let challenge = try await store.joinRoom(code: code)
                    // Abandoned while it was in flight — cancelled, or timed
                    // out. Navigating now would drop somebody into a room they
                    // had already walked away from.
                    guard attempt == joinAttempt else { return }
                    path = [challenge.id]
                } catch {
                    guard attempt == joinAttempt else { return }
                    errorText = error.localizedDescription
                }
            }
            // The ceiling. 20s is well past a healthy join on a slow
            // connection and well short of the minute it takes to decide an
            // app is broken.
            Task {
                try? await Task.sleep(for: .seconds(20))
                guard attempt == joinAttempt, joining else { return }
                joinAttempt += 1
                joining = false
                errorText = Strings.joinTimedOut
            }
        }
        if account.isSignedIn { run() } else { afterSignIn = run }
    }

    // MARK: - Progress and cover art

    /// Everything a card needs about a story, from one pass over its clips.
    ///
    /// `recordedClips` is not cheap — it localises every moment title and
    /// rebuilds a documents-directory URL per card, and in a room it filters
    /// the whole reaction and comment list per clip. Asking for it three times
    /// per row (progress, cover, refresh token) tripled that for nothing.
    private struct CardState {
        let progress: RoomProgress
        /// What the card shows: the cover this story was given, and failing
        /// that the most recent clip in it, from anyone. A room where only my
        /// friends have filmed used to fall back to the template art, so the
        /// card looked untouched while it was three moments in.
        let coverURL: URL?
        /// Re-records reuse the same file name, so a cached frame needs the
        /// clip's `recordedAt` to notice the change.
        let refreshToken: Date?
    }

    private func cardState(for challenge: Challenge) -> CardState {
        let clips = store.recordedClips(for: challenge.id)
        // Day breaks the tie, so a clip with no timestamp still sorts sanely
        // rather than sinking to the bottom of the pile.
        let latest = clips.max {
            ($0.recordedAt ?? .distantPast, $0.day) < ($1.recordedAt ?? .distantPast, $1.day)
        }
        return CardState(
            progress: RoomProgress(
                momentCount: challenge.cards.count,
                clips: clips,
                myID: account.account?.id ?? RoomProgress.soloAuthorID),
            coverURL: store.storyCoverURL(for: challenge, latestClipURL: latest?.url),
            refreshToken: latest?.recordedAt)
    }

}
