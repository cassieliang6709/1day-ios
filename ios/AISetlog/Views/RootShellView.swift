import SwiftUI

/// The app's two surfaces — your plans and the free-form camera — swapped by
/// a floating capsule instead of a tab bar. The plans surface stays mounted so
/// switching never loses its navigation stack.
///
/// There is no third tab and no primary button down here: the one action that
/// matters lives inside today's `StoryCard`, where it has the context to say
/// what it will actually do.
enum HomeLaunchAction: Equatable {
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

    /// Bound only so a language change re-renders the tab labels.
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    /// "Today's story" — the active story with the fewest moments in, so the
    /// home screen leads with whatever most needs filming.
    private var featuredChallenge: Challenge? {
        store.challenges
            .filter { !$0.isComplete && !$0.cards.isEmpty }
            .min { $0.recordedCount < $1.recordedCount }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            PlansHomeView(
                pendingJoinCode: $pendingJoinCode,
                launchAction: $launchAction,
                featuredChallengeID: featuredChallenge?.id)
                .opacity(surface == .plans ? 1 : 0)
                .allowsHitTesting(surface == .plans)

            // Mounted only while active so the capture session stops on leave.
            if surface == .camera {
                CameraTabView()
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
                selection: $surface)
                .padding(.bottom, 6)
        }
    }
}

/// The free-form camera surface: the same recorder as the per-moment one, in
/// free-form mode — roll a clip any time, then file it into a story.
struct CameraTabView: View {
    var body: some View {
        RecordClipView(
            day: 1,
            slotTitle: Strings.freeformSlot,
            isFreeform: true
        ) { _, _ in }
    }
}
