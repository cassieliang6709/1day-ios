import SwiftUI

/// The vertical timeline: the app's core idea, as a component.
///
/// Everyone's moments hang off one line, ordered by when they happened. It is
/// deliberately not a grid or a collage — a grid says "seven things you did",
/// a line says "one day, and here is how it went".

// MARK: - Rail

/// The line and its node. Drawn as a background behind the row's content so
/// the line's length always matches the row's height, however tall the card is.
struct TimelineRail: View {
    var isFirst = false
    var isLast = false
    /// Filled nodes are moments that exist; hollow ones are still to come.
    var isFilled = true
    var tint: Color = .oneDayBlue
    /// The next moment to film pulses gently — the one live thing on screen.
    var isNext = false

    private let nodeSize: CGFloat = 13

    var body: some View {
        ZStack(alignment: .top) {
            // The line, trimmed at the ends so the day starts and stops.
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : Color.oneDaySky.opacity(0.35))
                    .frame(height: 22)
                Rectangle()
                    .fill(isLast ? Color.clear : Color.oneDaySky.opacity(0.35))
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 2)

            node.padding(.top, 15)
        }
        .frame(width: nodeSize + 8)
    }

    private var node: some View {
        ZStack {
            if isNext {
                Circle()
                    .fill(tint.opacity(0.22))
                    .frame(width: nodeSize + 10, height: nodeSize + 10)
            }
            Circle()
                .fill(isFilled ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.oneDayCanvas))
                .frame(width: nodeSize, height: nodeSize)
                .overlay {
                    Circle().strokeBorder(
                        isFilled ? .clear : Color.oneDaySky.opacity(0.7),
                        lineWidth: 2)
                }
                .overlay {
                    Circle().strokeBorder(OneDay.canvas, lineWidth: 2.5)
                        .padding(-2.5)
                }
        }
        .symbolEffect(.pulse, isActive: isNext)
    }
}

/// The time column: when this moment was filmed, plus a glyph for the part of
/// the day it landed in. `label` is nil for a moment that hasn't happened yet
/// — the column stays blank rather than inventing a time, and the fixed width
/// keeps the rail aligned regardless.
struct TimelineStamp: View {
    let label: String?
    var caption: String?
    var icon: String?
    var isEmphasized = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            if let label {
                Text(label)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isEmphasized ? Color.oneDayBlue : OneDay.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            if let caption {
                Text(caption)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(OneDay.inkFaint)
                    .lineLimit(1)
            }

            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.oneDaySky)
            }
        }
        .frame(width: 58, alignment: .trailing)
        .padding(.top, 9)
    }
}

// MARK: - Clip card

/// One moment on the timeline. Either footage that exists, or the shape of
/// footage that doesn't yet.
struct TimelineClip: View {
    enum State {
        /// Filmed — show the frame.
        case filmed(url: URL, recordedAt: Date?)
        /// Mine to film, and it's next up.
        case mine
        /// Someone else hasn't filmed theirs yet.
        case waiting(friend: String)
        /// A slot further down the day that nobody is on yet.
        case upcoming
    }

    let momentTitle: String
    let momentIcon: String
    let state: State
    var authorName: String?
    var durationLabel: String?
    var reactions: [String] = []
    var mediaHeight: CGFloat = 130
    var showsMomentTitle = true
    var onTap: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            byline
            media
        }
        .padding(10)
        .glassSurface(radius: OneDay.Radius.card, tint: tintForState)
        .contentShape(RoundedRectangle(cornerRadius: OneDay.Radius.card, style: .continuous))
        .onTapGesture { onTap?() }
    }

    private var tintForState: Color? {
        if case .mine = state { return .oneDayBlue }
        return nil
    }

    // MARK: Byline

    private var byline: some View {
        HStack(spacing: 8) {
            switch state {
            case .filmed, .mine:
                AvatarDot(name: authorName, size: 22)
                Text(authorName ?? Strings.youLabel)
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                    .lineLimit(1)
            case .waiting(let friend):
                AvatarDot(name: friend, size: 22, isPending: true)
                Text(friend)
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(OneDay.inkFaint)
                    .lineLimit(1)
            case .upcoming:
                Image(systemName: momentIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.oneDaySky)
                    .frame(width: 22, height: 22)
                    .background(OneDay.surfaceSoft, in: Circle())
                // Nothing to say when the story has no prompts. This used to
                // fall back to "Film this moment" — which, down a record-by-time
                // timeline, printed the same seven words seven times, under a
                // frame that already says "tap to film". A story with no titles
                // should look like one, not like seven identical to-dos.
                if showsMomentTitle {
                    Text(momentTitle)
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundStyle(OneDay.inkSoft)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if !reactions.isEmpty {
                reactionPill
            }

            if let durationLabel {
                Text(durationLabel)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.oneDayBlue)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.oneDayBlue.opacity(0.12), in: Capsule())
            }
        }
    }

    private var reactionPill: some View {
        let distinct = Array(NSOrderedSet(array: reactions).array.compactMap { $0 as? String }.prefix(3))
        return HStack(spacing: 1) {
            ForEach(distinct, id: \.self) { Text($0).font(.system(size: 11)) }
            if reactions.count > distinct.count {
                Text("\(reactions.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
                    .padding(.leading, 2)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(OneDay.surfaceSoft, in: Capsule())
    }

    // MARK: Media

    @ViewBuilder
    private var media: some View {
        switch state {
        case .filmed(let url, let recordedAt):
            ClipThumbnail(url: url, refreshToken: recordedAt)
                .clipBox(height: mediaHeight)
                .clipShape(RoundedRectangle(cornerRadius: OneDay.Radius.chip, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    if showsMomentTitle {
                        Text(momentTitle)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(8)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.92))
                        .shadow(radius: 4)
                        .padding(8)
                }

        case .mine:
            EmptyFrame {
                VStack(spacing: 7) {
                    Image(systemName: showsMomentTitle ? momentIcon : "camera.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color.oneDayBlue)
                        .symbolEffect(.pulse)
                    if showsMomentTitle {
                        Text(momentTitle)
                            .font(.system(size: 14.5, weight: .bold, design: .rounded))
                            .foregroundStyle(OneDay.ink)
                            .lineLimit(1)
                    }
                    Text(Strings.tapToFilm)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.oneDayBlue)
                }
                .padding(.vertical, 22)
            }

        case .waiting(let friend):
            EmptyFrame {
                HStack(spacing: 9) {
                    OneDayBuddy(size: 26)
                    Text(Strings.waitingForMoment(friend))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(OneDay.inkSoft)
                        .lineLimit(1)
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .upcoming:
            // Same words as `.mine`, quieter. The difference is emphasis, not
            // permission — saying "later today" would be a lie for a moment
            // whose slot has already passed.
            EmptyFrame {
                // No icon here — the byline above already carries it.
                Text(Strings.tapToFilm)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(OneDay.inkFaint)
                    .padding(.vertical, 15)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Row

/// One position in the day: the stamp, the rail, and everything filed under
/// that time. In a shared room several friends can land on the same slot, so
/// a row holds a stack of clips rather than exactly one.
struct TimelineRow<Content: View>: View {
    let stamp: TimelineStamp
    var isFirst = false
    var isLast = false
    var isFilled = true
    var isNext = false
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            stamp

            TimelineRail(
                isFirst: isFirst,
                isLast: isLast,
                isFilled: isFilled,
                isNext: isNext)

            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(.bottom, 14)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
