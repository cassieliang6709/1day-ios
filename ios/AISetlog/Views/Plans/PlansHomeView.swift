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
    @Binding var pendingJoinCode: String?
    @Binding var launchAction: HomeLaunchAction?
    /// What the shell decided to lead with, and why. See `HomeHeroChoice`.
    let heroChoice: HomeHeroChoice

    @State private var path: [UUID] = []
    @State private var showComposer = false
    @State private var showJoin = false
    @State private var showSettings = false
    @State private var joinCode = ""
    @State private var joining = false
    @State private var errorText: String?
    @State private var recordChallenge: Challenge?
    @State private var notificationRecordRoute: NotificationRecordRoute?
    /// When set, present sign-in and run this once the user finishes.
    @State private var afterSignIn: (() -> Void)?

    /// Bound only so a language change re-renders the screen.
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var hero: Challenge? { heroChoice.challenge }
    /// Everything except the hero, by the day it was for. See `StoryTimeline`.
    private var timeline: StoryTimeline {
        StoryTimeline(challenges: store.challenges, excluding: hero?.id)
    }

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
        .fullScreenCover(isPresented: $showComposer) {
            StoryComposerView { id in path.append(id) }
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
        .sheet(isPresented: $showJoin) {
            JoinInviteSheet(
                code: $joinCode,
                onCancel: { showJoin = false },
                onJoin: {
                    showJoin = false
                    startJoin(joinCode)
                }
            )
            .presentationDetents([.height(430)])
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: Binding(
            get: { afterSignIn != nil },
            set: { if !$0 { afterSignIn = nil } }
        )) {
            SignInView { afterSignIn?() }
                .presentationDetents([.medium])
        }
        .alert(Strings.couldntJoin, isPresented: Binding(
            get: { errorText != nil }, set: { if !$0 { errorText = nil } }
        )) {
            Button(Strings.ok, role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
        .onAppear {
            openPendingNotificationRoute()
            consumePendingJoinCode()
            consumeLaunchAction()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .oneDayNotificationRoutePending
        )) { _ in
            openPendingNotificationRoute()
        }
        .onChange(of: pendingJoinCode) { _, _ in consumePendingJoinCode() }
        .onChange(of: launchAction) { _, _ in consumeLaunchAction() }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header

                switch heroChoice {
                case .today(let challenge):
                    heroSection(challenge, label: Strings.todaysStory)
                case .resume(let challenge):
                    heroSection(challenge, label: Strings.resumeStory)
                case .startToday:
                    // First run gets the mascot; someone who already has
                    // finished films just needs the one button.
                    if store.challenges.isEmpty { emptyState } else { startTodayCard }
                }

                if !timeline.isEmpty {
                    timelineSection
                }
            }
            .padding(.top, 8)
            .padding(.bottom, OneDay.tabBarClearance + 20)
            // Belt and braces: the page can never be wider than the scroll
            // viewport. Without this a single over-eager child silently drags
            // every section off both edges of the display.
            .containerRelativeFrame(.horizontal)
        }
        .scrollIndicators(.hidden)
        .overlay {
            if joining {
                ProgressView(Strings.joining)
                    .controlSize(.large)
                    .padding(24)
                    .glassSurface()
            }
        }
    }

    /// Who you are, what day it is, how far today has got — then the two
    /// actions. The wordmark used to sit here; it's the one fact a person
    /// opening 1day already has, and it was crowding out the two they didn't.
    ///
    /// Nothing up here is allowed to outshine "continue today's story" in the
    /// card below, so all three controls are the same 36pt and the create
    /// button earns its emphasis from the brand gradient alone.
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

            IconBubble(systemName: "person.2.badge.plus", size: 36) {
                joinCode = ""
                showJoin = true
            }
            .accessibilityLabel(Strings.enterInviteCode)

            Button {
                showComposer = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(OneDay.brandHorizontal, in: Circle())
                    .oneDaySoftShadow(strength: 0.6)
            }
            .buttonStyle(.plain)
            // Visually 36pt so it sits level with the bubble beside it, but
            // the tap target still clears Apple's 44pt floor.
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .accessibilityLabel(Strings.newStory)
        }
        .padding(.horizontal, 20)
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

                MomentPips(filled: recorded, total: total, size: 4.5, tint: .oneDayBlue)
                    .layoutPriority(-1)
            }
        }
    }

    /// `label` varies because the card isn't always today's story — calling an
    /// unfinished story from yesterday "today's story" is the kind of small lie
    /// that makes the whole screen untrustworthy.
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

                Button(Strings.startTodayCTA) { showComposer = true }
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

            Button(Strings.startTodaysStory) { showComposer = true }
                .buttonStyle(.primaryAction)
                .padding(.top, 4)
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
            SectionLabel(text: timeline.includesToday
                ? Strings.yourStories
                : Strings.scrollBack)
                .padding(.horizontal, 20)

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
                store.delete(challenge.id)
            }
        }
        .padding(.horizontal, 20)
    }


    // MARK: - Recorder

    /// Opens the camera on the next unfilmed slot (or a specific one, when a
    /// notification asked for it).
    @ViewBuilder
    private func recorder(for challenge: Challenge, preferredDay: Int? = nil) -> some View {
        let slot = slotToRecord(in: challenge, preferred: preferredDay)
        RecordClipView(
            day: slot,
            slotTitle: challenge.isTimeOnly
                ? nil
                : ChallengePresenter(challenge: challenge).title(forSlot: slot),
            clipLength: challenge.resolvedClipLength,
            showsPrompt: !challenge.isTimeOnly,
            orientation: challenge.resolvedOrientation
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

    private func slotToRecord(in challenge: Challenge, preferred: Int?) -> Int {
        if let preferred,
           let card = challenge.cards.first(where: { $0.day == preferred }),
           card.clipFileName == nil {
            return card.day
        }
        // The first moment *nobody* has filmed. Offering one a friend already
        // covered, while an untouched one waits further down, is how a room
        // ends up with three takes of breakfast and no evening.
        return cardState(for: challenge).progress.nextOpenMoment
    }

    // MARK: - Routing

    private func consumePendingJoinCode() {
        guard let code = pendingJoinCode else { return }
        pendingJoinCode = nil
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
            showComposer = true
        case .join:
            joinCode = ""
            showJoin = true
        case .record(let id):
            recordChallenge = store.challenge(id)
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
            Task {
                defer { joining = false }
                do {
                    let challenge = try await store.joinRoom(code: code)
                    path = [challenge.id]
                } catch {
                    errorText = error.localizedDescription
                }
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
        /// The most recent clip in the story, from anyone. A room where only my
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
            coverURL: latest?.url,
            refreshToken: latest?.recordedAt)
    }

}
