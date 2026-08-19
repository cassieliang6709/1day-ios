import SwiftUI

/// The story, as an object you can hold.
///
/// This is the home screen's centre of gravity: a cover frame from the film so
/// far, the story's name, how much of the day is in, who's in it with you, and
/// the one action that continues it. It is intentionally *not* a progress
/// widget with a button bolted on — the progress lives inside the picture.

struct StoryCard: View {
    let challenge: Challenge
    let memberNames: [String]
    /// Most recent clip — the card's cover. Nil until the first moment lands.
    let coverURL: URL?
    /// Re-records reuse the file name; this busts the cached first frame.
    var refreshToken: Date?
    let onContinue: () -> Void
    let onOpen: () -> Void

    private var presenter: ChallengePresenter { ChallengePresenter(challenge: challenge) }
    private var nextSlot: Int {
        challenge.cards.first { $0.clipFileName == nil }?.day
            ?? min(challenge.recordedCount + 1, max(challenge.cards.count, 1))
    }
    private var nextMoment: String { presenter.title(forSlot: nextSlot) }
    private var momentIcon: String {
        MomentCatalog.icon(for: challenge.momentValue(forSlot: nextSlot))
    }

    var body: some View {
        VStack(spacing: 0) {
            cover
            footer
        }
        .background(OneDay.surface, in: RoundedRectangle(cornerRadius: OneDay.Radius.hero, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: OneDay.Radius.hero, style: .continuous)
                .strokeBorder(OneDay.hairline, lineWidth: 1)
        }
        .oneDaySoftShadow(strength: 1.3)
    }

    // MARK: Cover

    private var cover: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let coverURL {
                    ClipThumbnail(url: coverURL, refreshToken: refreshToken)
                } else {
                    OneDay.brand.overlay {
                        Image(systemName: momentIcon)
                            .font(.system(size: 44, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
            .clipBox(height: 258)

            OneDay.scrim

            VStack(alignment: .leading, spacing: 10) {
                Text(challenge.title)
                    .font(.system(size: 27, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(Strings.storyCardCaption(
                    next: nextMoment,
                    isComplete: challenge.isComplete))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)

                progress
            }
            .padding(18)
        }
        .frame(height: 258)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: OneDay.Radius.hero,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: OneDay.Radius.hero,
                style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .overlay(alignment: .topTrailing) {
            if challenge.isShared {
                OneDayChip(icon: "person.2.fill", text: Strings.sharedLabel, onDark: true)
                    .padding(14)
            }
        }
    }

    /// Members on the left, a slim capacity bar on the right — the whole
    /// status line in one row, over the cover art.
    private var progress: some View {
        HStack(spacing: 12) {
            if memberNames.count > 1 {
                AvatarStack(names: memberNames, maxShown: 4, size: 27)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                MomentPips(
                    filled: challenge.recordedCount,
                    total: max(challenge.cards.count, 1))
                Text("\(challenge.recordedCount)/\(challenge.cards.count)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    // MARK: Footer

    private var footer: some View {
        Button(action: challenge.isComplete ? onOpen : onContinue) {
            Label(
                challenge.isComplete
                    ? Strings.watchYourFilm
                    : Strings.continueTodaysStory,
                systemImage: challenge.isComplete ? "play.fill" : "video.fill")
        }
        .buttonStyle(.primaryAction)
        .padding(16)
    }
}

/// The dot row that stands in for a progress bar. Seven filled circles reads
/// as "moments collected"; a bar reads as a task at 43%.
struct MomentPips: View {
    let filled: Int
    let total: Int
    var size: CGFloat = 6
    var tint: Color = .white

    var body: some View {
        HStack(spacing: size * 0.7) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Circle()
                    .fill(index < filled ? tint : tint.opacity(0.32))
                    .frame(width: size, height: size)
                    .scaleEffect(index < filled ? 1 : 0.8)
            }
        }
        .animation(OneDay.Motion.pop, value: filled)
    }
}

// MARK: - Compact variant

/// A story in a list: thumbnail, name, one status line, progress. Used for
/// "your other plans" under the hero, and for finished films.
struct StoryRowCard: View {
    let challenge: Challenge
    let coverURL: URL?
    var refreshToken: Date?
    var memberNames: [String] = []

    private var presenter: ChallengePresenter { ChallengePresenter(challenge: challenge) }

    var body: some View {
        HStack(spacing: 14) {
            thumbnail

            VStack(alignment: .leading, spacing: 5) {
                Text(challenge.title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    MomentPips(
                        filled: challenge.recordedCount,
                        total: max(challenge.cards.count, 1),
                        size: 5,
                        tint: .oneDayBlue)
                    Text("\(challenge.recordedCount)/\(challenge.cards.count)")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.oneDayBlue)
                }
            }

            Spacer(minLength: 4)

            if memberNames.count > 1 {
                AvatarStack(names: memberNames, maxShown: 3, size: 24)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(OneDay.inkFaint)
        }
        .padding(12)
        .glassSurface(radius: OneDay.Radius.card)
    }

    private var thumbnail: some View {
        Group {
            if let coverURL {
                ClipThumbnail(url: coverURL, refreshToken: refreshToken)
            } else {
                OneDay.surfaceSoft.overlay {
                    Image(systemName: "film")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.oneDaySky)
                }
            }
        }
        .frame(width: 58, height: 66)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var subtitle: String {
        if challenge.isComplete {
            return Strings.filmReadySubtitle(
                duration: StorySchedule(challenge).filmDuration)
        }
        let next = challenge.cards.first { $0.clipFileName == nil }?.day ?? 1
        return Strings.nextUpMoment(presenter.title(forSlot: next))
    }
}
