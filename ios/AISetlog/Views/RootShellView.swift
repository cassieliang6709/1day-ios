import SwiftUI

enum HomeLaunchAction: Equatable {
    case quickStart
    case newStory
    case join
    case record(UUID)
    case openStory(UUID)
}

struct RootShellView: View {
    @Environment(ChallengeStore.self) private var store
    @Environment(ClipDraftStore.self) private var drafts
    @Binding var pendingJoinCode: String?
    @Binding var launchAction: HomeLaunchAction?

    enum Surface: Hashable { case plans, friends, compose, camera }
    @State private var surface: Surface = .friends
    @State private var returnTab: Surface = .friends
    @State private var composeTogether = false
    @State private var roomLaunchAction: HomeLaunchAction?
    @State private var draftsRequests = 0

    @State private var unfiledGuard = UnfiledClipGuard()
    @State private var askBeforeLeavingCamera = false
    @State private var pendingSurface: Surface?
    @State private var showDrafts = false
    @State private var justKeptADraft = false
    @State private var tilt = DeviceTiltWatcher()
    @State private var cameraStartsSideways = false
    @State private var plansSelecting = false
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var stories: HomeStories {
        HomeStories(challenges: store.challenges.filter { !$0.isShared })
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            PlansHomeView(
                pendingJoinCode: .constant(nil),
                launchAction: $launchAction,
                stories: stories,
                draftsRequest: draftsRequests,
                isActive: surface == .plans,
                onActivate: { activate(.plans) },
                onBackToRooms: { surface = .friends },
                onSelectingChange: { plansSelecting = $0 },
                onCompose: { openCompose(together: false) })
                .opacity(surface == .plans ? 1 : 0)
                .allowsHitTesting(surface == .plans)
                .accessibilityHidden(surface != .plans)

            PlansHomeView(
                pendingJoinCode: $pendingJoinCode,
                launchAction: $roomLaunchAction,
                stories: stories,
                scope: .friends,
                isActive: surface == .friends,
                onActivate: { activate(.friends) },
                onOpenPersonal: { surface = .plans },
                onCompose: { openCompose(together: true) })
                .opacity(surface == .friends ? 1 : 0)
                .allowsHitTesting(surface == .friends)
                .accessibilityHidden(surface != .friends)

            if surface == .compose {
                StoryComposerView(
                    onCreate: { id in
                        if composeTogether {
                            surface = .friends
                            roomLaunchAction = .openStory(id)
                        } else {
                            surface = .plans
                            launchAction = .openStory(id)
                        }
                    },
                    onClose: { surface = returnTab },
                    startsWithFriends: composeTogether)
            }

            if surface == .camera {
                CameraTabView(
                    unfiledGuard: unfiledGuard,
                    onStartStory: { openCompose(together: false) },
                    onClose: { guardedSurface.wrappedValue = returnTab },
                    onOpenDrafts: {
                        guardedSurface.wrappedValue = .plans
                        draftsRequests += 1
                    },
                    startsSideways: cameraStartsSideways)
            }

            if surface != .compose, !(surface == .plans && plansSelecting) {
                FloatingTabBar(
                    items: [
                        .init(
                            tab: Surface.camera,
                            label: Strings.surfaceCamera,
                            icon: "camera",
                            activeIcon: "camera.fill",
                            identifier: "tab-camera"),
                        .init(
                            tab: Surface.friends,
                            label: Strings.surfaceFriends,
                            icon: "person.2",
                            activeIcon: "person.2.fill",
                            identifier: "tab-rooms"),
                    ],
                    selection: tabSelection)
                    .disabled(unfiledGuard.isRecording)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            draftsBanner
        }
        .confirmationDialog(
            Strings.keepClipQuestion,
            isPresented: $askBeforeLeavingCamera,
            titleVisibility: .visible
        ) {
            Button(Strings.keepClip) {
                guard unfiledGuard.keepForNavigation() else { return }
                justKeptADraft = true
                leaveCamera()
            }
            Button(Strings.discardClip, role: .destructive) {
                unfiledGuard.discard?()
                leaveCamera()
            }
            Button(Strings.cancel, role: .cancel) { pendingSurface = nil }
        } message: {
            Text(Strings.keepClipFootnote)
        }
        .sheet(isPresented: $showDrafts) { ClipDraftsView() }
        .onAppear {
            consumeCaptureLaunch()
            updateTiltWatching()
        }
        .onChange(of: surface) { _, _ in updateTiltWatching() }
        .onChange(of: scenePhase) { _, _ in updateTiltWatching() }
        .onChange(of: tilt.isHeldSideways) { _, sideways in
            guard sideways, canJumpToCamera else { return }
            openCamera(sideways: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .oneDayCaptureRequested)) { _ in
            consumeCaptureLaunch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .oneDayCapturedDraftsRequested)) { _ in
            consumeCaptureLaunch()
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .debugDeepLink)) { note in
            guard let link = note.userInfo?["link"] as? DebugDeepLink else { return }
            switch link {
            case .surface("plans"): _ = activate(.plans)
            case .surface("friends"): _ = activate(.friends)
            case .surface("compose"): openCompose(together: false)
            case .surface("camera"): openCamera()
            case .story(let id):
                _ = activate(.plans)
                launchAction = .openStory(id)
            default: break
            }
        }
        #endif
        .onChange(of: unfiledGuard.isRecording) { _, recording in
            if !recording, let next = pendingSurface {
                pendingSurface = nil
                _ = activate(next)
            }
        }
    }

    private func consumeCaptureLaunch() {
        if UserDefaults.standard.bool(forKey: "capture.openDraftsRequested") {
            UserDefaults.standard.removeObject(forKey: "capture.openDraftsRequested")
            UserDefaults.standard.removeObject(forKey: "capture.launchRequested")
            showDrafts = true
            return
        }
        guard UserDefaults.standard.bool(forKey: "capture.launchRequested") else { return }
        UserDefaults.standard.removeObject(forKey: "capture.launchRequested")
        openCamera()
    }

    @ViewBuilder
    private var draftsBanner: some View {
        if justKeptADraft, !drafts.isEmpty, surface != .camera {
            Button { showDrafts = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("\(Strings.draftKept) · \(Strings.draftKeptSeeIt)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .foregroundStyle(OneDay.onBrand)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(OneDay.brandHorizontal, in: Capsule())
                .oneDayGlow(.oneDayBrand, strength: 0.8)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("drafts-entry")
            .padding(.bottom, OneDay.tabBarClearance + 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(OneDay.Motion.soft, value: justKeptADraft)
            .task(id: justKeptADraft) {
                guard justKeptADraft else { return }
                try? await Task.sleep(for: .seconds(4))
                justKeptADraft = false
            }
        }
    }

    private var guardedSurface: Binding<Surface> {
        Binding(
            get: { surface },
            set: { next in
                guard !unfiledGuard.isRecording else { return }
                guard surface == .camera, next != .camera, unfiledGuard.hasUnfiledClip else {
                    surface = next
                    return
                }
                pendingSurface = next
                guard unfiledGuard.keepForNavigation() else {
                    pendingSurface = nil
                    return
                }
                justKeptADraft = true
                leaveCamera()
            })
    }

    private func leaveCamera() {
        surface = pendingSurface ?? returnTab
        pendingSurface = nil
    }

    private func activate(_ next: Surface) -> Bool {
        if unfiledGuard.isRecording {
            pendingSurface = next
            return false
        }
        guardedSurface.wrappedValue = next
        return surface == next
    }

    private var tabSelection: Binding<Surface> {
        Binding(
            get: { surface == .plans ? .friends : surface },
            set: { next in
                if next == .camera {
                    openCamera()
                } else {
                    guardedSurface.wrappedValue = next
                }
            })
    }

    private var canJumpToCamera: Bool {
        guard surface == .plans || surface == .friends, scenePhase == .active,
              !unfiledGuard.isRecording, !showDrafts else { return false }
        let root = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
        return root?.presentedViewController == nil
    }

    private func updateTiltWatching() {
        if (surface == .plans || surface == .friends) && scenePhase == .active {
            tilt.start()
        } else {
            tilt.stop()
        }
    }

    private func openCamera(sideways: Bool = false) {
        cameraStartsSideways = sideways
        if surface == .plans || surface == .friends { returnTab = surface }
        withAnimation(OneDay.Motion.snap) { surface = .camera }
    }

    private func openCompose(together: Bool) {
        if !together, let plan = store.todaysPlan() {
            returnTab = .plans
            guardedSurface.wrappedValue = .plans
            launchAction = .openStory(plan.id)
            return
        }
        if surface == .plans || surface == .friends { returnTab = surface }
        composeTogether = together
        guardedSurface.wrappedValue = .compose
    }
}

@Observable
final class UnfiledClipGuard {
    var isRecording = false
    var hasUnfiledClip = false
    var keep: (() -> Bool)?
    var discard: (() -> Void)?

    func keepForNavigation() -> Bool {
        guard hasUnfiledClip else { return true }
        guard keep?() == true else { return false }
        hasUnfiledClip = false
        return true
    }
}

struct CameraTabView: View {
    var unfiledGuard: UnfiledClipGuard?
    var onStartStory: (() -> Void)?
    var onClose: (() -> Void)?
    var onOpenDrafts: (() -> Void)?
    var startsSideways = false

    @Environment(ClipDraftStore.self) private var drafts
    @State private var showDrafts = false

    var body: some View {
        RecordClipView(
            day: 1,
            slotTitle: Strings.freeformSlot,
            isFreeform: true,
            unfiledGuard: unfiledGuard,
            onStartStory: onStartStory,
            onCloseFreeform: onClose,
            startsSideways: startsSideways
        ) { _, _ in }
    }
}
