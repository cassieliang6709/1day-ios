import SwiftUI

/// The app's two surfaces — your plans feed and the free-form camera — swapped
/// by a small floating pill instead of a full tab bar. The plans surface stays
/// mounted so switching never loses its navigation stack.
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

    /// Bound only so a language change re-renders the pill labels.
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var featuredChallenge: Challenge? {
        store.challenges
            .filter { !$0.isComplete && !$0.cards.isEmpty }
            .min { $0.recordedCount < $1.recordedCount }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            HomeView(
                pendingJoinCode: $pendingJoinCode,
                launchAction: $launchAction,
                featuredChallengeID: featuredChallenge?.id)
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: surface == .plans ? 132 : 66)
                }
                .opacity(surface == .plans ? 1 : 0)
                .allowsHitTesting(surface == .plans)

            // Mounted only while active so the capture session stops on leave.
            if surface == .camera {
                CameraTabView()
            }

            VStack(spacing: 10) {
                if surface == .plans {
                    primaryActionButton
                }
                SurfacePill(surface: $surface)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 4)
        }
    }

    private var primaryActionTitle: String {
        guard let challenge = featuredChallenge else {
            return store.challenges.isEmpty
                ? Strings.createFirstStory
                : Strings.startAnotherStory
        }
        let slot = min(challenge.recordedCount + 1, max(challenge.cards.count, 1))
        return Strings.recordSlot(
            oneDay: challenge.isOneDay,
            index: slot,
            secondsLabel: challenge.resolvedClipLength.secondsLabel)
    }

    private var primaryActionIcon: String {
        featuredChallenge == nil ? "plus" : "video.fill"
    }

    private var primaryActionButton: some View {
        Button {
            if let id = featuredChallenge?.id {
                launchAction = .record(id)
            } else {
                launchAction = .newStory
            }
        } label: {
            Label(primaryActionTitle, systemImage: primaryActionIcon)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    LinearGradient(
                        colors: [Color.oneDayBlue, Color.oneDayCyan],
                        startPoint: .leading,
                        endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: Color.oneDayBlue.opacity(0.22), radius: 16, y: 7)
        }
        .buttonStyle(.plain)
    }
}

/// The floating two-state toggle. Active segment fills with the app's blue.
private struct SurfacePill: View {
    @Binding var surface: RootShellView.Surface

    var body: some View {
        HStack(spacing: 4) {
            segment(.plans, label: Strings.surfacePlans, icon: "rectangle.stack")
            segment(.camera, label: Strings.surfaceCamera, icon: "video")
        }
        .padding(5)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
        .shadow(color: .black.opacity(0.14), radius: 16, y: 6)
        .sensoryFeedback(.selection, trigger: surface)
    }

    @ViewBuilder
    private func segment(_ s: RootShellView.Surface, label: String, icon: String) -> some View {
        let on = surface == s
        Button {
            withAnimation(.snappy(duration: 0.28)) { surface = s }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                Text(label).font(.system(size: 14.5, weight: .semibold))
            }
            .foregroundStyle(on ? Color.white : Color.secondary)
            .padding(.vertical, 9)
            .padding(.horizontal, 20)
            .background(on ? Color.oneDayBlue : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The free-form camera surface (the `camera` pill) — the same recorder UI as
/// the per-day recorder, just in free-form mode: roll a clip any time, then
/// file it to one of your plans.
struct CameraTabView: View {
    var body: some View {
        RecordClipView(
            day: 1,
            slotTitle: Strings.freeformSlot,
            isFreeform: true
        ) { _, _ in }
    }
}
