import SwiftUI

/// Cards shown in the home challenge list: the hero "next capture" card, the
/// active-challenge row, and the completed-challenge film-strip card.

/// A completed challenge's "history" card — the clip's first frame peeking
/// through behind a date stamp, like a film-strip frame instead of a plain row.
struct FilmStripCard: View {
    let challenge: Challenge
    let clipURL: URL?

    private var dateStamp: String {
        challenge.startDate.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let clipURL {
                ClipThumbnail(url: clipURL)
                    .scaledToFill()
            } else {
                Color(.systemGray5)
            }

            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 3) {
                Text(challenge.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if challenge.isShared {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(10)
        }
        .frame(width: 130, height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .topTrailing) {
            Text(dateStamp)
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.black.opacity(0.35), in: Capsule())
                .rotationEffect(.degrees(-6))
                .padding(8)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }
}

/// The home screen's hero card — the next unrecorded moment in the most
/// pressing active challenge, with a one-tap way into the camera for it.
struct NextCaptureCard: View {
    let challenge: Challenge
    let memberNames: [String]
    /// The most recently recorded clip in this challenge — previewed large at
    /// the top of the card when it exists.
    let clipURL: URL?
    let onRecord: () -> Void

    private var nextSlot: Int { min(challenge.recordedCount + 1, max(challenge.cards.count, 1)) }
    private var momentTitle: String { ChallengePresenter(challenge: challenge).title(forSlot: nextSlot) }
    private var momentIcon: String {
        MomentCatalog.icon(for: challenge.momentTitles?[safe: nextSlot - 1])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                if let clipURL {
                    ClipThumbnail(url: clipURL)
                } else {
                    LinearGradient(
                        colors: [Color.oneDaySky, Color.oneDayBlue],
                        startPoint: .top, endPoint: .bottom
                    )
                    .overlay(
                        Image(systemName: momentIcon)
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(momentTitle)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.oneDayNavy)
                    .lineLimit(1)

                if memberNames.count > 1 {
                    AvatarStack(names: memberNames)
                        .padding(.top, 2)
                }
            }

            Button(action: onRecord) {
                Label(Strings.recordSeconds(challenge.resolvedClipLength.secondsLabel), systemImage: "video.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.oneDayBlue, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 18, y: 8)
    }
}

/// One row in the "active stories" list: progress ring, title, status line.
struct ChallengeRow: View {
    let challenge: Challenge
    var memberCount: Int = 0

    var body: some View {
        HStack(spacing: 14) {
            ProgressRing(recorded: challenge.recordedCount, total: challenge.cards.count)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(challenge.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if challenge.isShared {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.oneDayBlue)
                    }
                }
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .contentShape(Rectangle())
    }

    private var statusText: String {
        let fmt = Date.FormatStyle().month(.abbreviated).day()
        let range = "\(challenge.startDate.formatted(fmt)) – \((Calendar.current.date(byAdding: .day, value: 6, to: challenge.startDate) ?? challenge.startDate).formatted(fmt))"
        if challenge.isOneDay {
            if challenge.isComplete {
                return Strings.completedOn(challenge.startDate.formatted(fmt))
            }
            return Strings.oneDayProgress(challenge.recordedCount, secondsLabel: challenge.resolvedClipLength.secondsLabel)
        }
        if challenge.isShared, memberCount > 1 {
            return Strings.friendsRange(memberCount, range)
        }
        if challenge.isComplete {
            return Strings.completedRange(range)
        }
        if challenge.currentDay > 7 {
            return Strings.endedRecorded(challenge.recordedCount)
        }
        return Strings.dayOfRange(challenge.currentDay, range)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
