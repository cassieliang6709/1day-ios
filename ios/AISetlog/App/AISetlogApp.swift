import SwiftUI
import LockedCameraCapture
import GoogleSignIn

@main
struct AISetlogApp: App {
    @UIApplicationDelegateAdaptor(NotificationAppDelegate.self) private var appDelegate
    @State private var account: AccountStore
    @State private var store: ChallengeStore
    @State private var drafts = ClipDraftStore()
    @State private var moods: MoodStore
    @State private var promptMetrics = PromptSuggestionMetrics()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppAppearance.storageKey) private var appAppearance: AppAppearance = .system
    @AppStorage(Identity.myTintKey) private var myTintIndex = -1
    @AppStorage(AppSkin.storageKey) private var appSkin: AppSkin = .cream

    init() {
        let account = AccountStore()
        let store = ChallengeStore()
        store.account = account
        let moods = MoodStore()
        store.myRoomProfile = { [weak moods] in
            MyRoomProfile.make(avatar: .shared, today: moods?.today)
        }
        store.adoptAvatar = { url in
            if let data = try? Data(contentsOf: url) { AvatarStore.shared.save(pngData: data) }
        }
        store.forgetAvatar = { AvatarStore.shared.remove() }
        _moods = State(initialValue: moods)
        ReminderService.reconcile(for: store.challenges)
        SharedActivityNotificationService.reconcileSubscriptions(for: store.challenges)
        _account = State(initialValue: account)
        _store = State(initialValue: store)
        Self.settlePersonalEffect()
    }

    private static func settlePersonalEffect() {
        let defaults = UserDefaults.standard
        let stored = defaults.string(forKey: PersonalEffectParameters.storageKey)
            .flatMap(PersonalEffectParameters.init(rawValue:)) ?? .none
        let sticky = defaults.bool(forKey: PersonalEffectParameters.stickyKey)
        let opening = PersonalEffectParameters.onLaunch(stored: stored, sticky: sticky)
        guard opening != stored else { return }
        defaults.set(opening.rawValue, forKey: PersonalEffectParameters.storageKey)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .id(appSkin)
                .environment(store)
                .environment(account)
                .environment(drafts)
                .environment(moods)
                .environment(promptMetrics)
                .tint(OneDay.brandText)
                .preferredColorScheme(appAppearance.colorScheme)
                .task(id: appSkin) { AppSkin.syncAppIcon(to: appSkin) }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Log.app.info("scene active, \(store.challenges.count) stories")
                    ReminderService.reconcile(for: store.challenges)
                    SharedActivityNotificationService.reconcileSubscriptions(
                        for: store.challenges)
                    NotificationPermissionService.registerForRemoteNotificationsIfNeeded()
                    Task {
                        await store.reconcileAccountRooms()
                        await store.syncSharedRooms()
                        await store.publishMyProfileToAllRooms()
                    }
                }
                .onChange(of: account.account?.id, initial: true) { previousID, id in
                    if previousID != id { BackgroundFilmExport.shared.resetForAccountChange() }
                    store.roomSync.reconcileCacheAccount()
                    guard id != nil else { return }
                    Task {
                        await store.reconcileAccountRooms()
                        await store.syncSharedRooms()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .roomActivityArrived)) { note in
                    guard let code = note.userInfo?["roomCode"] as? String,
                          let id = store.challenges.first(where: { $0.roomCode == code })?.id
                    else { return }
                    Task { await store.syncRoom(id) }
                }
                .onChange(of: moods.today) { _, _ in
                    Task { await store.publishMyProfileToAllRooms() }
                }
                .onChange(of: AvatarStore.shared.version) { _, _ in
                    Task { await store.publishMyProfileToAllRooms() }
                }
        }
    }
}

struct RootView: View {
    @State private var captureImportFailed = false
    private static var lockedCaptureActivityType: String {
        if #available(iOS 18.0, *) { return NSUserActivityTypeLockedCameraCapture }
        return "oneday.unavailable.lockedCapture"
    }
    @Environment(ChallengeStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(ClipDraftStore.self) private var drafts
    @Environment(MoodStore.self) private var moods
    @State private var pendingJoinCode: String?
    @State private var homeLaunchAction: HomeLaunchAction?
    @AppStorage("onboarding.completed.v1") private var hasCompletedOnboarding = false
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system
    @State private var showsDebugAvatarFlow = RootView.debugAvatarFlowRequested

    private static var debugAvatarFlowRequested: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "debugAvatarFlow")
        #else
        false
        #endif
    }

    private var needsOnboarding: Bool {
        !hasCompletedOnboarding && store.challenges.isEmpty
    }

    var body: some View {
        Group {
            if needsOnboarding {
                FirstRunOnboardingView(
                    onCreateStory: {
                        hasCompletedOnboarding = true
                        homeLaunchAction = .quickStart
                    })
            } else {
                RootShellView(
                    pendingJoinCode: $pendingJoinCode,
                    launchAction: $homeLaunchAction)
            }
        }
        .environment(\.locale, appLanguage.resolved.locale)
        .task {
            if #available(iOS 18.0, *) {
                for await update in LockedCameraCaptureManager.shared.sessionContentUpdates {
                    if Task.isCancelled { return }
                    let directories: [URL]
                    switch update {
                    case .initial(let urls): directories = urls
                    case .added(let url): directories = [url]
                    case .removed: continue
                    @unknown default: continue
                    }
                    for directory in directories {
                        do { try await LockedCaptureImporter.receive(directory, into: drafts) }
                        catch { captureImportFailed = true }
                    }
                }
            }
        }
        .onContinueUserActivity(Self.lockedCaptureActivityType) { _ in
            hasCompletedOnboarding = true
            UserDefaults.standard.set(true, forKey: "capture.openDraftsRequested")
            NotificationCenter.default.post(name: .oneDayCapturedDraftsRequested, object: nil)
        }
        .alert(Strings.captureImportFailed, isPresented: $captureImportFailed) {
            Button(Strings.retry) {
                Task {
                    if #available(iOS 18.0, *) {
                        for directory in LockedCameraCaptureManager.shared.sessionContentURLs {
                            do { try await LockedCaptureImporter.receive(directory, into: drafts) }
                            catch { captureImportFailed = true }
                        }
                    }
                }
            }
            Button(Strings.cancel, role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showsDebugAvatarFlow) {
            AvatarSetupFlow { _ in showsDebugAvatarFlow = false }
        }
        .onAppear {
            if !store.challenges.isEmpty {
                hasCompletedOnboarding = true
            }
            #if DEBUG
            DebugLinkInbox.start()
            if let path = UserDefaults.standard.string(forKey: "debugLink") {
                if let link = DebugDeepLink(path: path) {
                    DispatchQueue.main.async { handle(link) }
                } else {
                    Log.debug.error("-debugLink: unknown \(path, privacy: .public)")
                }
            }
            #endif
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .debugLinkInbox)) { note in
            if let link = note.userInfo?["link"] as? DebugDeepLink { handle(link) }
        }
        #endif
        .onOpenURL { url in
            #if DEBUG
            if url.host == "debug" {
                if let link = DebugDeepLink(url) { handle(link) }
                else { Log.debug.error("unknown link \(url.absoluteString, privacy: .public)") }
                return
            }
            #endif
            if GIDSignIn.sharedInstance.handle(url) { return }
            guard let code = InviteCode.fromDeepLink(url) else {
                Log.app.notice("unhandled url scheme=\(url.scheme ?? "", privacy: .public) host=\(url.host ?? "", privacy: .public)")
                return
            }
            Log.app.info("join link")
            hasCompletedOnboarding = true
            pendingJoinCode = code
        }
    }
}

#if DEBUG
extension RootView {
    fileprivate func handle(_ link: DebugDeepLink) {
        Log.debug.info("link \(String(describing: link), privacy: .public)")
        switch link {
        case .surface, .story:
            hasCompletedOnboarding = true
            NotificationCenter.default.post(name: .debugDeepLink, object: nil, userInfo: ["link": link])
        case .avatar:
            showsDebugAvatarFlow = true
        case .resetOnboarding:
            hasCompletedOnboarding = false
        case .seedLibrary:
            UserDefaults.standard.set(true, forKey: "debugSeedLibrary")
            UserDefaults.standard.removeObject(forKey: "debugSeedLibrary.done")
            LibraryDebugSeed.runIfAsked(store: store, drafts: drafts, moods: moods)
            Log.debug.info("seed-library done, \(store.challenges.count) stories")
        case .sync:
            Task {
                await store.reconcileAccountRooms()
                await store.syncSharedRooms()
                Log.debug.info("sync done")
            }
        case .dumpState:
            let shared = store.challenges.filter(\.isShared).count
            Log.debug.info("""
                state stories=\(store.challenges.count) rooms=\(shared) \
                drafts=\(drafts.drafts.count) signedIn=\(account.isSignedIn) \
                onboardingDone=\(hasCompletedOnboarding)
                """)
        }
    }
}
#endif
