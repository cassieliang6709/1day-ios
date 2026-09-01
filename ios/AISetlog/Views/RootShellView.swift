import SwiftUI

/// The app's two surfaces — your plans and the free-form camera — swapped by
/// a floating capsule instead of a tab bar. The plans surface stays mounted so
/// switching never loses its navigation stack.
///
/// There is no third tab and no primary button down here: the one action that
/// matters lives inside today's `StoryCard`, where it has the context to say
/// what it will actually do.
enum HomeLaunchAction: Equatable {
    /// First-run path: make the three-moment personal story immediately.
    case quickStart
    case newStory
    case join
    case record(UUID)
}

struct RootShellView: View {
    @Environment(ChallengeStore.self) private var store
    @Binding var pendingJoinCode: String?
    @Binding var launchAction: HomeLaunchAction?

    enum Surface: Hashable { case plans, camera }
    @State private var surface: Surface = .plans

    /// The camera surface reports through this whether it's still holding a
    /// clip nobody has filed, and hands back the two ways out.
    @State private var unfiledGuard = UnfiledClipGuard()
    @State private var askBeforeLeavingCamera = false
    @State private var pendingSurface: Surface?

    /// Bound only so a language change re-renders the tab labels.
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    /// What the home screen leads with. See `HomeHeroChoice` for why this isn't
    /// just "the story with the fewest moments filmed".
    private var heroChoice: HomeHeroChoice {
        HomeHeroChoice(challenges: store.challenges)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            PlansHomeView(
                pendingJoinCode: $pendingJoinCode,
                launchAction: $launchAction,
                heroChoice: heroChoice)
                .opacity(surface == .plans ? 1 : 0)
                .allowsHitTesting(surface == .plans)

            // Mounted only while active so the capture session stops on leave.
            // That unmount is also what used to destroy unfiled clips, so the
            // guard below gets a say before it happens.
            if surface == .camera {
                CameraTabView(
                    unfiledGuard: unfiledGuard,
                    onStartStory: {
                        launchAction = .newStory
                        surface = .plans
                    })
            }

            FloatingTabBar(
                items: [
                    .init(
                        tab: Surface.plans,
                        label: Strings.surfacePlans,
                        icon: "rectangle.stack",
                        activeIcon: "rectangle.stack.fill"),
                    .init(
                        tab: Surface.camera,
                        label: Strings.surfaceCamera,
                        icon: "camera",
                        activeIcon: "camera.fill"),
                ],
                selection: guardedSurface)
                .padding(.bottom, 6)
        }
        .confirmationDialog(
            Strings.keepClipQuestion,
            isPresented: $askBeforeLeavingCamera,
            titleVisibility: .visible
        ) {
            Button(Strings.keepClip) {
                unfiledGuard.keep?()
                leaveCamera()
            }
            Button(Strings.discardClip, role: .destructive) {
                unfiledGuard.discard?()
                leaveCamera()
            }
            Button(Strings.cancel, role: .cancel) { pendingSurface = nil }
        }
    }

    /// Leaving the camera with a clip still in review used to throw it away
    /// silently. Now the switch has to go through here first, so discarding is
    /// something a person chose rather than something that just happened.
    private var guardedSurface: Binding<Surface> {
        Binding(
            get: { surface },
            set: { next in
                guard surface == .camera, next != .camera, unfiledGuard.hasUnfiledClip else {
                    surface = next
                    return
                }
                pendingSurface = next
                askBeforeLeavingCamera = true
            })
    }

    private func leaveCamera() {
        surface = pendingSurface ?? .plans
        pendingSurface = nil
    }
}

/// Shared between the shell and the camera surface so the shell can ask "you
/// still have a clip — keep it?" while the temp file is still there to keep.
/// The camera owns the recorder, so it supplies the actions; the shell owns the
/// navigation, so it decides when to ask.
@Observable
final class UnfiledClipGuard {
    var hasUnfiledClip = false
    var keep: (() -> Void)?
    var discard: (() -> Void)?
}

/// The free-form camera surface: the same recorder as the per-moment one, in
/// free-form mode — roll a clip any time, then file it into a story.
struct CameraTabView: View {
    var unfiledGuard: UnfiledClipGuard?
    var onStartStory: (() -> Void)?

    @Environment(ClipDraftStore.self) private var drafts
    @State private var showDrafts = false

    var body: some View {
        RecordClipView(
            day: 1,
            slotTitle: Strings.freeformSlot,
            isFreeform: true,
            unfiledGuard: unfiledGuard,
            onStartStory: onStartStory
        ) { _, _ in }
            // Over the camera rather than on the home screen: this is where the
            // clips came from, and home doesn't need another section. Clear of
            // the wordmark, and gone while a take is in review — the clip in
            // front of you is the one that needs deciding about.
            .overlay(alignment: .top) {
                if !drafts.isEmpty, unfiledGuard?.hasUnfiledClip != true {
                    DraftsEntryButton(count: drafts.count) { showDrafts = true }
                        .padding(.top, 88)
                }
            }
            .sheet(isPresented: $showDrafts) { ClipDraftsView() }
    }
}
