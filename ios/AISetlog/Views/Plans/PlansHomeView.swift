import SwiftUI

struct PlansHomeView: View {
    @Environment(ChallengeStore.self) var store
    @Environment(AccountStore.self) var account
    @Environment(ClipDraftStore.self) var drafts
    @Environment(MoodStore.self) var moods: MoodStore?
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
    var onDetailOpenChange: ((Bool) -> Void)? = nil
    var onSelectingChange: ((Bool) -> Void)? = nil
    let onCompose: () -> Void
    @State var path: [UUID] = []

    @State var roomSeenAt: [String: Double] =
        UserDefaults.standard.dictionary(forKey: PlansHomeView.roomSeenKey) as? [String: Double] ?? [:]

    @State var showJoin = false
    @State var showSettings = false
    @State var showRoomDemo = false
    @State var showDrafts = false
    @State var joinCode = ""
    @State var joining = false
    @State var joinAttempt = 0
    @State var joinTask: Task<Void, Never>?
    @State var errorText: String?
    @State var recordChallenge: Challenge?
    @State var recordPlanSlot: PlanSlot?
    @State var pendingDeletion: Challenge?
    @State var notificationRecordRoute: NotificationRecordRoute?
    @State var afterSignIn: (() -> Void)?
    @State var isSelectingClips = false
    @State var pickedClips: [LibraryClip] = []
    @State var isPicking = false
    @State var aiPickResult: ClipPick?
    @State var vlogRequest: VlogRequest?
    @State var selectedDay = Calendar.current.startOfDay(for: .now)
    @State var showsDayPicker = false
    @State var planningAhead = false
    @State var inviteRequest: InviteRequest?
    @State var debugAlert: DebugAlert?
    @AppStorage(AppLanguage.storageKey) var appLanguage: AppLanguage = .system
    var timeline: StoryTimeline { stories.timeline }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                OneDayCanvas()
                content
            }
            .accessibilityHidden(!isActive)
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: path.isEmpty) { _, empty in onDetailOpenChange?(!empty) }
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
    var content: some View {
        switch scope {
        case .stories: storiesContent
        case .friends: friendsContent
        }
    }
}

struct PlanSlot: Identifiable, Equatable {
    let challengeID: UUID
    let slot: Int
    var id: String { "\(challengeID.uuidString).\(slot)" }
}
