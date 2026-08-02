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
    /// The story the shell considers "today's" — the least-finished active one.
    let featuredChallengeID: UUID?

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

    private var active: [Challenge] { store.challenges.filter { !$0.isComplete } }
    private var finished: [Challenge] { store.challenges.filter(\.isComplete) }
    private var hero: Challenge? {
        featuredChallengeID.flatMap(store.challenge) ?? active.first
    }
    private var others: [Challenge] { active.filter { $0.id != hero?.id } }

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

                if let hero {
                    heroSection(hero)
                } else {
                    emptyState
                }

                if !others.isEmpty {
                    otherPlansSection
                }

                if !finished.isEmpty {
                    finishedSection
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

    /// Greeting, then the two utility actions. No title bar — the greeting
    /// *is* the title, which is what keeps the screen feeling personal.
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Strings.greeting(
                    name: account.account?.displayName,
                    hour: Calendar.current.component(.hour, from: .now)))
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(Strings.greetingQuestion)
                    .font(.system(size: 14.5, weight: .medium, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
            }

            Spacer(minLength: 8)

            IconBubble(systemName: "person.2.badge.plus") {
                joinCode = ""
                showJoin = true
            }
            .accessibilityLabel(Strings.enterInviteCode)

            Button { showSettings = true } label: {
                AvatarDot(name: account.account?.displayName, size: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Strings.settings)
        }
        .padding(.horizontal, 20)
    }

    private func heroSection(_ challenge: Challenge) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: Strings.todaysStory)
                Spacer()
                Button {
                    showComposer = true
                } label: {
                    Label(Strings.newStory, systemImage: "plus")
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.oneDayBlue)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)

            StoryCard(
                challenge: challenge,
                memberNames: store.members(for: challenge.id).map(\.name),
                coverURL: latestClipURL(for: challenge),
                refreshToken: latestRecordedAt(for: challenge),
                onContinue: { recordChallenge = challenge },
                onOpen: { path.append(challenge.id) })
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

    private var otherPlansSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionLabel(text: Strings.yourOtherPlans)
                .padding(.horizontal, 20)

            ForEach(others) { challenge in
                Button {
                    path.append(challenge.id)
                } label: {
                    StoryRowCard(
                        challenge: challenge,
                        coverURL: latestClipURL(for: challenge),
                        refreshToken: latestRecordedAt(for: challenge),
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
        }
    }

    /// Finished films as a horizontal shelf of posters — a small archive,
    /// not another list to work through.
    private var finishedSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionLabel(text: Strings.finishedFilms)
                .padding(.horizontal, 20)

            ScrollView(.horizontal) {
                HStack(spacing: 13) {
                    ForEach(finished) { challenge in
                        Button {
                            path.append(challenge.id)
                        } label: {
                            FilmPoster(
                                challenge: challenge,
                                coverURL: firstClipURL(for: challenge),
                                refreshToken: firstRecordedAt(for: challenge))
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
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Recorder

    /// Opens the camera on the next unfilmed slot (or a specific one, when a
    /// notification asked for it).
    @ViewBuilder
    private func recorder(for challenge: Challenge, preferredDay: Int? = nil) -> some View {
        let slot = slotToRecord(in: challenge, preferred: preferredDay)
        RecordClipView(
            day: slot,
            slotTitle: ChallengePresenter(challenge: challenge).title(forSlot: slot),
            clipLength: challenge.resolvedClipLength,
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
        return challenge.cards.first { $0.clipFileName == nil }?.day
            ?? min(max(preferred ?? 1, 1), max(challenge.cards.count, 1))
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

    // MARK: - Cover art

    private func firstClipURL(for challenge: Challenge) -> URL? {
        challenge.cards.first { $0.clipFileName != nil }
            .flatMap { store.clipURL(for: $0, in: challenge.id) }
    }

    private func latestClipURL(for challenge: Challenge) -> URL? {
        challenge.cards.last { $0.clipFileName != nil }
            .flatMap { store.clipURL(for: $0, in: challenge.id) }
    }

    /// Re-records reuse the same file name, so a cached first frame needs the
    /// card's `recordedAt` to notice the change.
    private func firstRecordedAt(for challenge: Challenge) -> Date? {
        challenge.cards.first { $0.clipFileName != nil }?.recordedAt
    }

    private func latestRecordedAt(for challenge: Challenge) -> Date? {
        challenge.cards.last { $0.clipFileName != nil }?.recordedAt
    }

}

/// A finished film on the shelf: cover frame, title, and the date it happened.
struct FilmPoster: View {
    let challenge: Challenge
    let coverURL: URL?
    var refreshToken: Date?

    private var dateStamp: String {
        challenge.startDate.formatted(
            .dateTime.month(.abbreviated).day().locale(AppLanguage.effective.locale))
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let coverURL {
                    ClipThumbnail(url: coverURL, refreshToken: refreshToken)
                } else {
                    TemplateCover(identityKey: challenge.title)
                }
            }
            .frame(width: 132, height: 186)
            .clipped()

            OneDay.scrim

            VStack(alignment: .leading, spacing: 3) {
                Text(challenge.title)
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(dateStamp)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(11)
        }
        .frame(width: 132, height: 186)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if challenge.isShared {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(8)
            }
        }
        .oneDaySoftShadow(strength: 0.8)
    }
}
