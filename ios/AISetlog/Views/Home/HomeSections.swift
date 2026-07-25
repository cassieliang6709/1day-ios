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

/// "Today" title + subtitle under the header, with a prominent Start-today
/// pill on the right (it used to hide inside the header's + menu).
struct TodayHeader: View {
    let onStart: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.todayTitle)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.oneDayNavy)
                Text(Strings.todaySubtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onStart) {
                Label(Strings.startToday, systemImage: "plus")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        LinearGradient(
                            colors: [Color.oneDayBlue, Color.oneDayCyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
    }
}

/// Fallback hero shown only when every existing challenge is already
/// complete — there's no "next capture" to feature, so offer to start one.
struct HomeHero: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            OneDayLogoMark()
                .frame(width: 92, height: 92)

            Text(Strings.startNewFilm)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            BreathingStartButton(action: onStart)
        }
        .padding(.horizontal)
    }
}

/// First-launch screen: big logo, tagline, start / join-by-code.
struct HomeEmptyState: View {
    let onNewChallenge: () -> Void
    let onJoin: () -> Void

    var body: some View {
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
                    Button(action: onNewChallenge) {
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

                    Button(Strings.haveInviteCode, action: onJoin)
                        .font(.headline)
                        .foregroundStyle(Color.oneDayBlue)
                }
                .padding(.bottom, 48)
            }
            .padding(.horizontal, 34)
        }
    }
}
