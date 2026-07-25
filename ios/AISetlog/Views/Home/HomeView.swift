import SwiftUI


/// Landing screen: all challenges (active + past), start a new one or join a
/// friend's room any time.
///
/// Sections live in `Home/HomeSections.swift`, cards in `HomeCards.swift`,
/// brand/identity bits in `HomeComponents.swift`; the palette is `Theme.swift`.
struct HomeView: View {
    @Environment(ChallengeStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Binding var pendingJoinCode: String?

    @State private var path: [UUID] = []
    @State private var showNewChallenge = false
    @State private var showJoin = false
    @State private var showSettings = false
    @State private var joinCode = ""
    @State private var joining = false
    @State private var errorText: String?
    @State private var showComingSoon = false
    /// The hero card's challenge when its record CTA opens the camera
    /// straight into the next unrecorded slot (no detour via the board).
    @State private var recordChallenge: Challenge?

    /// Bound only so a language change re-renders the home screen.
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    /// When set, present sign-in and run this once the user finishes.
    @State private var afterSignIn: (() -> Void)?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.challenges.isEmpty {
                    HomeEmptyState(
                        onTemplate: { template in
                            let challenge = store.create(
                                title: template.displayName,
                                mode: .oneDay,
                                templateName: template.name.en,
                                momentTitles: template.momentKeys)
                            path.append(challenge.id)
                        },
                        onNewChallenge: { showNewChallenge = true },
                        onJoin: { joinCode = ""; showJoin = true })
                } else {
                    challengeList
                }
            }
            .background(Color(red: 0.93, green: 0.96, blue: 0.99))
            .navigationTitle("")
            .toolbar {
                // The populated home screen has its own in-content header
                // (avatar/bell/friends/plus); only the empty state — which has
                // no other chrome — needs the settings gear up here.
                if store.challenges.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape").font(.title3)
                        }
                        .accessibilityLabel(Strings.settings)
                    }
                }
            }
            .toolbar(store.challenges.isEmpty ? .visible : .hidden, for: .navigationBar)
            .alert(Strings.comingSoon, isPresented: $showComingSoon) {
                Button(Strings.ok, role: .cancel) {}
            }
            .fullScreenCover(isPresented: $showNewChallenge) {
                NewChallengeView { id in path.append(id) }
            }
            .fullScreenCover(item: $recordChallenge) { challenge in
                let slot = min(challenge.recordedCount + 1, max(challenge.cards.count, 1))
                RecordClipView(
                    day: slot,
                    slotTitle: ChallengePresenter(challenge: challenge).title(forSlot: slot),
                    clipLength: challenge.resolvedClipLength
                ) { url, overlayText in
                    store.saveClip(
                        from: url,
                        day: slot,
                        challengeID: challenge.id,
                        overlayText: overlayText)
                    // Just finished the last slot from the hero CTA? Land on
                    // the board so the film moment is one glance away.
                    if store.challenge(challenge.id)?.isComplete == true {
                        path.append(challenge.id)
                    }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showJoin) { joinSheet }
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
            .navigationDestination(for: UUID.self) { id in
                ChallengeBoardView(challengeID: id)
            }
        }
        .onChange(of: pendingJoinCode) { _, code in
            if let code { startJoin(code); pendingJoinCode = nil }
        }
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-demoReel") {
                let demo = store.challenges.first { $0.title == "Demo Week" }
                    ?? store.create(title: "Demo Week")
                path = [demo.id]
            }
            if ProcessInfo.processInfo.arguments.contains("-demoBoard") {
                let demo = store.challenges.first { $0.title == "Demo Week" }
                    ?? store.create(title: "Demo Week")
                store.fillWithDemoClips(challengeID: demo.id)
                path = [demo.id]
            }
            if ProcessInfo.processInfo.arguments.contains("-newChallenge") {
                showNewChallenge = true
            }
        }
        #endif
    }

    // MARK: - Join flow

    private var joinSheet: some View {
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

    // MARK: - List

    private var inProgress: [Challenge] { store.challenges.filter { !$0.isComplete } }
    private var history: [Challenge] { store.challenges.filter { $0.isComplete } }

    /// The active challenge with the fewest recordings still shown first —
    /// that's the one whose next moment is most overdue.
    private var nextCaptureChallenge: Challenge? {
        inProgress.filter { !$0.cards.isEmpty }.min { $0.recordedCount < $1.recordedCount }
    }

    private var challengeList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HomeHeader(
                    avatarName: account.account?.displayName,
                    onAvatar: { showSettings = true },
                    onBell: { showComingSoon = true },
                    onJoin: { joinCode = ""; showJoin = true })
                TodayHeader(onStart: { showNewChallenge = true })

                if let hero = nextCaptureChallenge {
                    NextCaptureCard(
                        challenge: hero,
                        memberNames: store.members(for: hero.id).map { $0.name },
                        clipURL: latestClipURL(for: hero)
                    ) {
                        recordChallenge = hero
                    }
                    .padding(.horizontal)
                } else {
                    HomeHero(onStart: { showNewChallenge = true })
                }

                if !inProgress.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(Strings.activeStories)
                                .font(.title3.bold())
                                .foregroundStyle(Color.oneDayNavy)
                            Spacer()
                            Button(Strings.seeAll) {
                                showComingSoon = true
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.oneDayBlue)
                        }

                        VStack(spacing: 0) {
                            ForEach(Array(inProgress.enumerated()), id: \.element.id) { index, challenge in
                                Button {
                                    path.append(challenge.id)
                                } label: {
                                    ChallengeRow(challenge: challenge, memberCount: store.members(for: challenge.id).count)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(challenge.isShared ? Strings.leaveRoom : Strings.deleteChallenge, role: .destructive) {
                                        store.delete(challenge.id)
                                    }
                                }
                                if index < inProgress.count - 1 {
                                    Divider().padding(.leading, 86)
                                }
                            }
                        }
                        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: .black.opacity(0.05), radius: 12, y: 5)
                    }
                    .padding(.horizontal)
                }

                if !history.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(Strings.history)
                            .font(.caption.bold())
                            .foregroundStyle(Color.oneDayBlue.opacity(0.62))
                            .kerning(1.2)
                            .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(history) { challenge in
                                    Button {
                                        path.append(challenge.id)
                                    } label: {
                                        FilmStripCard(
                                            challenge: challenge,
                                            clipURL: firstClipURL(for: challenge))
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(challenge.isShared ? Strings.leaveRoom : Strings.deleteChallenge, role: .destructive) {
                                            store.delete(challenge.id)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .overlay {
            if joining { ProgressView(Strings.joining).controlSize(.large) }
        }
    }

    private func firstClipURL(for challenge: Challenge) -> URL? {
        challenge.cards.first { $0.clipFileName != nil }
            .flatMap { store.clipURL(for: $0, in: challenge.id) }
    }

    /// Most recently recorded clip in the challenge — feeds the hero card's
    /// large preview.
    private func latestClipURL(for challenge: Challenge) -> URL? {
        challenge.cards.last { $0.clipFileName != nil }
            .flatMap { store.clipURL(for: $0, in: challenge.id) }
    }
}
