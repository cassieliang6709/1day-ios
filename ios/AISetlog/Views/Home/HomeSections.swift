import SwiftUI

/// Whole-screen sections of `HomeView`, parameterized by closures so the view
/// itself keeps all navigation/sheet state.

/// Avatar + bell + join-by-code, scrolling with the page content
/// (there's no separate nav bar once a challenge exists).
struct HomeHeader: View {
    let avatarName: String?
    let onAvatar: () -> Void
    let onBell: () -> Void
    let onJoin: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onAvatar) {
                AvatarDot(name: avatarName, size: 44)
            }
            .accessibilityLabel(Strings.settings)

            Spacer()

            Button(action: onBell) {
                Image(systemName: "bell")
                    .font(.title3)
                    .foregroundStyle(Color.oneDayNavy)
            }

            Button(action: onJoin) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.oneDayBlue)
            }
            .accessibilityLabel(Strings.enterInviteCode)
        }
        .padding(.horizontal)
    }
}

/// Informational home heading. The single primary action now lives in the
/// fixed bottom dock instead of competing with the hero card.
struct TodayHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Strings.todayTitle)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.oneDayNavy)
            Text(Strings.todaySubtitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }
}

/// Fallback hero shown when there is no active challenge. The fixed bottom
/// dock owns the action, so this view only establishes the empty-state mood.
struct HomeHero: View {
    var body: some View {
        VStack(spacing: 14) {
            OneDayLogoMark()
                .frame(width: 92, height: 92)

            Text(Strings.startNewFilm)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }
}
