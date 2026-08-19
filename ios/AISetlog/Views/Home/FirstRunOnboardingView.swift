import SwiftUI

/// Three short first-run pages that explain the product before asking the user
/// to create a story. Permissions stay out of onboarding and are requested only
/// when the related feature is used.
struct FirstRunOnboardingView: View {
    let onCreateStory: () -> Void
    let onJoin: () -> Void

    @State private var page = 0
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    OneDay.surfaceSoft,
                    OneDay.canvas,
                    OneDay.surfaceSoft,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.oneDayCyan.opacity(0.16))
                .frame(width: 300, height: 300)
                .offset(x: -190, y: -320)
            Circle()
                .fill(Color.oneDayBlue.opacity(0.12))
                .frame(width: 280, height: 280)
                .offset(x: 180, y: 350)

            VStack(spacing: 18) {
                HStack {
                    OneDayLogoMark()
                        .frame(width: 48, height: 48)
                    Spacer()
                    if page < 2 {
                        Button(Strings.onboardingSkip) {
                            withAnimation(.snappy) { page = 2 }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.oneDayBlue)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                TabView(selection: $page) {
                    OnboardingPage(
                        visual: .capture,
                        title: Strings.onboardingCaptureTitle,
                        bodyText: Strings.onboardingCaptureBody)
                        .tag(0)
                    OnboardingPage(
                        visual: .film,
                        title: Strings.onboardingFilmTitle,
                        bodyText: Strings.onboardingFilmBody)
                        .tag(1)
                    OnboardingPage(
                        visual: .together,
                        title: Strings.onboardingTogetherTitle,
                        bodyText: Strings.onboardingTogetherBody)
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? Color.oneDayBlue : Color.oneDayBlue.opacity(0.18))
                            .frame(width: index == page ? 28 : 8, height: 8)
                    }
                }
                .animation(.snappy, value: page)

                VStack(spacing: 12) {
                    Button {
                        if page < 2 {
                            withAnimation(.snappy) { page += 1 }
                        } else {
                            onCreateStory()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Text(page < 2 ? Strings.onboardingNext : Strings.createFirstStory)
                            Image(systemName: "arrow.right")
                        }
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [Color.oneDayBlue, Color.oneDayCyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)

                    if page == 2 {
                        Button(Strings.haveInviteCode, action: onJoin)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.oneDayBlue)
                    } else {
                        Text(Strings.onboardingPage(page + 1, total: 3))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
            }
        }
    }
}

private struct OnboardingPage: View {
    enum Visual { case capture, film, together }

    let visual: Visual
    let title: String
    let bodyText: String

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 12)
            visualContent
                .frame(height: 260)
            VStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.oneDayNavy)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)
                Text(bodyText)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            Spacer(minLength: 8)
        }
    }

    @ViewBuilder
    private var visualContent: some View {
        switch visual {
        case .capture:
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(.white.opacity(0.9))
                .frame(width: 190, height: 250)
                .overlay {
                    ZStack {
                        LinearGradient(
                            colors: [Color.oneDaySky, Color.oneDayBlue],
                            startPoint: .top,
                            endPoint: .bottom)
                        Image(systemName: "video.fill")
                            .font(.system(size: 42, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .padding(10)
                }
                .shadow(color: Color.oneDayBlue.opacity(0.18), radius: 24, y: 12)
        case .film:
            VStack(spacing: 24) {
                HStack(spacing: 7) {
                    ForEach(1...7, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(index.isMultiple(of: 2) ? Color.oneDayCyan : Color.oneDayBlue)
                            .frame(width: 34, height: 48)
                            .overlay {
                                Text("\(index)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                            }
                    }
                }
                Image(systemName: "arrow.down")
                    .font(.title2.bold())
                    .foregroundStyle(Color.oneDayBlue)
                Image(systemName: "film.stack.fill")
                    .font(.system(size: 74, weight: .semibold))
                    .foregroundStyle(Color.oneDayBlue.gradient)
            }
        case .together:
            ZStack {
                Circle()
                    .fill(.white.opacity(0.9))
                    .frame(width: 220, height: 220)
                    .shadow(color: Color.oneDayBlue.opacity(0.16), radius: 24, y: 12)
                Image(systemName: "person.2.fill")
                    .font(.system(size: 72, weight: .semibold))
                    .foregroundStyle(Color.oneDayBlue.gradient)
                Image(systemName: "lock.fill")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(Color.oneDayCyan, in: Circle())
                    .offset(x: 78, y: 72)
            }
        }
    }
}
