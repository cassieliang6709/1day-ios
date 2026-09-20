import SwiftUI

/// The app's three surfaces — your plans, making a new one, and the free-form
/// camera — swapped by a floating capsule instead of a tab bar. The plans
/// surface stays mounted so switching never loses its navigation stack.
///
/// 新建 became the middle tab in 1.3. It used to be a 36pt wordless `plus` in
/// the corner of the plans header, which made the app's second-most-used action
/// the smallest target on its first screen — and put it in the one place a
/// thumb holding a phone cannot reach. The composer is a full screen either
/// way; as a tab it is also somewhere you can back out of by tapping 计划,
/// rather than hunting for an ✕.
enum HomeLaunchAction: Equatable {
    /// First-run path: make the three-moment personal story immediately.
    case quickStart
    case newStory
    case join
    case record(UUID)
    /// Push a story's timeline onto the plans stack. What the composer asks for
    /// once it has made something: the composer lives in the shell now, and the
    /// navigation stack it needs to push onto belongs to `PlansHomeView`.
    case openStory(UUID)
}

struct RootShellView: View {
    @Environment(ChallengeStore.self) private var store
    /// Read here as well as in the camera: a kept clip has to be findable from
    /// the screen you land on, not only from the one you left.
    @Environment(ClipDraftStore.self) private var drafts
    @Binding var pendingJoinCode: String?
    @Binding var launchAction: HomeLaunchAction?

    enum Surface: Hashable { case plans, compose, camera }
    @State private var surface: Surface = .plans

    /// The camera surface reports through this whether it's still holding a
    /// clip nobody has filed, and hands back the two ways out.
    @State private var unfiledGuard = UnfiledClipGuard()
    @State private var askBeforeLeavingCamera = false
    @State private var pendingSurface: Surface?
    @State private var showDrafts = false
    /// Raised by "保留" and cleared a few seconds later. Lives up here rather
    /// than in the camera because the tab switch that triggers it unmounts the
    /// camera, and a confirmation that dies with the screen that caused it is
    /// the same as no confirmation at all.
    @State private var justKeptADraft = false

    /// Bound only so a language change re-renders the tab labels.
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    /// What the home screen leads with and what it lists underneath. See
    /// `HomeStories`; `HomeHeroChoice` covers why the lead isn't just "the
    /// story with the fewest moments filmed".
    private var stories: HomeStories {
        HomeStories(challenges: store.challenges)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            PlansHomeView(
                pendingJoinCode: $pendingJoinCode,
                launchAction: $launchAction,
                stories: stories,
                onCompose: { surface = .compose })
                .opacity(surface == .plans ? 1 : 0)
                .allowsHitTesting(surface == .plans)

            // Not kept mounted behind the others the way plans is: it holds a
            // half-filled form, and coming back to 新建 after wandering off
            // should offer a fresh one rather than the poster rack scrolled to
            // wherever it was left. There is no navigation stack to lose here.
            if surface == .compose {
                StoryComposerView(
                    onCreate: { id in
                        // Back to plans, with the new story's timeline pushed:
                        // the composer's whole job is done and the thing you
                        // just made is what you want to look at.
                        surface = .plans
                        launchAction = .openStory(id)
                    },
                    onClose: { surface = .plans })
            }

            // Mounted only while active so the capture session stops on leave.
            // That unmount is also what used to destroy unfiled clips, so the
            // guard below gets a say before it happens.
            if surface == .camera {
                CameraTabView(
                    unfiledGuard: unfiledGuard,
                    onStartStory: { surface = .compose })
            }

            // 计划 · 我的 · 拍摄, in that order, with 我的 in the middle and
            // emphasised — see `FloatingTabBar.emphasisedIndex`. The middle
            // slot is the one a thumb reaches without moving the phone, so it
            // holds the screen the app opens on rather than an action.
            FloatingTabBar(
                items: [
                    .init(
                        tab: Surface.compose,
                        label: Strings.surfaceCompose,
                        icon: "sparkles.rectangle.stack",
                        activeIcon: "sparkles.rectangle.stack.fill"),
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
                selection: guardedSurface,
                emphasisedIndex: 1)
                .padding(.bottom, 6)

            draftsBanner
        }
        .confirmationDialog(
            Strings.keepClipQuestion,
            isPresented: $askBeforeLeavingCamera,
            titleVisibility: .visible
        ) {
            Button(Strings.keepClip) {
                unfiledGuard.keep?()
                justKeptADraft = true
                leaveCamera()
            }
            Button(Strings.discardClip, role: .destructive) {
                unfiledGuard.discard?()
                leaveCamera()
            }
            Button(Strings.cancel, role: .cancel) { pendingSurface = nil }
        } message: {
            // The camera's own ✕ has said this since drafts shipped
            // (`RecordClipView`); this dialog — the one you get by tapping
            // another tab, which is how most people leave — never did. So
            // "保留" was a button with no stated destination, and a clip it
            // saved correctly still read as one that vanished.
            Text(Strings.keepClipFootnote)
        }
        .sheet(isPresented: $showDrafts) { ClipDraftsView() }
    }

    /// The four seconds after you keep a clip: what just happened, and the way
    /// in if that is not where you meant it to go.
    ///
    /// It used to hold a second job — a standing "N 段待归档" count that stayed
    /// on the plans surface indefinitely. Two problems with that, and they
    /// compound. The tab bar is itself a floating capsule, so a permanent
    /// second capsule directly above it made the bottom of the screen two
    /// hovering pills with no hierarchy between them; and an overlay cannot be
    /// scrolled out of the way, so the count sat on top of whichever story card
    /// happened to be behind it, forever.
    ///
    /// Underneath that was the real mistake: a confirmation and a count are
    /// different kinds of thing. A confirmation earns the middle of the screen
    /// because you just did something; a count does not, and inheriting the
    /// confirmation's placement and weight is how it ended up shouting. The
    /// count now lives in the plans list as `PlansHomeView.draftsRow`, where it
    /// scrolls with everything else and covers nothing.
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
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(OneDay.brandHorizontal, in: Capsule())
                .oneDayGlow(.oneDayBlue, strength: 0.8)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("drafts-entry")
            // Above the capsule, clear of it.
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
            // A loose take belongs to no story yet, so there is no moment
            // number to be on and no count to be out of. `momentCount` stays 0,
            // which is what stops the camera drawing a position it doesn't
            // know; `day` is only a placeholder for the recorder's plumbing and
            // is never shown here.
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
