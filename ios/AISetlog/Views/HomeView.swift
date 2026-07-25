import SwiftUI


/// Landing screen: all challenges (active + past), start a new one or join a
/// friend's room any time.
///
/// Sub-components live in `Home/HomeComponents.swift`; the color palette is
/// in `Theme.swift`.
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

    /// Bound only so a language change re-renders the home screen.
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    /// When set, present sign-in and run this once the user finishes.
    @State private var afterSignIn: (() -> Void)?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.challenges.isEmpty {
                    emptyState
                } else {
                    challengeList
                }
            }
            .background(Color(.systemGroupedBackground))
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
                homeHeader
                todayHeaderText

                if let hero = nextCaptureChallenge {
                    NextCaptureCard(
                        challenge: hero,
                        memberNames: store.members(for: hero.id).map { $0.name }
                    ) {
                        path.append(hero.id)
                    }
                    .padding(.horizontal)
                } else {
                    homeHero
                }

                if !inProgress.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(Strings.activeStories)
                            .font(.title3.bold())
                            .foregroundStyle(Color.oneDayNavy)

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

    /// Avatar + bell + friends + start-new, scrolling with the page content
    /// (there's no separate nav bar once a challenge exists — see `.toolbar`
    /// above).
    private var homeHeader: some View {
        HStack(spacing: 16) {
            Button {
                showSettings = true
            } label: {
                AvatarDot(name: account.account?.displayName, size: 44)
            }
            .accessibilityLabel(Strings.settings)

            Spacer()

            Button {
                showComingSoon = true
            } label: {
                Image(systemName: "bell")
                    .font(.title3)
                    .foregroundStyle(Color.oneDayNavy)
            }

            Button {
                showComingSoon = true
            } label: {
                Image(systemName: "person.2")
                    .font(.title3)
                    .foregroundStyle(Color.oneDayNavy)
            }

            Menu {
                Button {
                    showNewChallenge = true
                } label: {
                    Label(Strings.startToday, systemImage: "plus")
                }
                Button {
                    joinCode = ""
                    showJoin = true
                } label: {
                    Label(Strings.enterInviteCode, systemImage: "envelope")
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.oneDayBlue)
            }
        }
        .padding(.horizontal)
    }

    private var todayHeaderText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Strings.todayTitle)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.oneDayNavy)
            Text(Strings.todaySubtitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    /// Fallback hero shown only when every existing challenge is already
    /// complete — there's no "next capture" to feature, so offer to start one.
    private var homeHero: some View {
        VStack(spacing: 18) {
            OneDayLogoMark()
                .frame(width: 92, height: 92)

            Text(Strings.startNewFilm)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            BreathingStartButton { showNewChallenge = true }
        }
        .padding(.horizontal)
    }

    private var emptyState: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.oneDayMist,
                    Color(red: 0.95, green: 0.99, blue: 1.0),
                    Color(red: 0.82, green: 0.94, blue: 1.0),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.oneDayCyan.opacity(0.18))
                .frame(width: 260, height: 260)
                .offset(x: -180, y: -280)
            Circle()
                .fill(Color.oneDaySky.opacity(0.18))
                .frame(width: 260, height: 260)
                .offset(x: -160, y: 360)
            Circle()
                .fill(Color.oneDayBlue.opacity(0.13))
                .frame(width: 260, height: 260)
                .offset(x: 170, y: 330)

            VStack(spacing: 26) {
                Spacer(minLength: 24)

                OneDayLogoMark()
                    .frame(width: 170, height: 170)
                    .padding(.bottom, 10)

                VStack(spacing: 10) {
                    Text("1Day")
                        .font(.system(size: 58, weight: .black, design: .rounded))
                        .foregroundStyle(Color.oneDayBlue)
                    Text(Strings.tagline)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color(red: 0.25, green: 0.31, blue: 0.38))
                }
                .multilineTextAlignment(.center)

                Spacer()

                VStack(spacing: 16) {
                    Button {
                        showNewChallenge = true
                    } label: {
                        Text(Strings.startToday)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color.oneDayBlue,
                                        Color.oneDayCyan,
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)

                    Button(Strings.haveInviteCode) {
                        joinCode = ""
                        showJoin = true
                    }
                    .font(.headline)
                    .foregroundStyle(Color.oneDayBlue)
                }
                .padding(.bottom, 48)
            }
            .padding(.horizontal, 34)
        }
    }
}
