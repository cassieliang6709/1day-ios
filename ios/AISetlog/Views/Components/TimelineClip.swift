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
    var tint: Color = .oneDayBrand
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
                    .font(OneDay.Font.rounded(.caption, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(isEmphasized ? OneDay.brandText : OneDay.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            if let caption {
                Text(caption)
                    .font(OneDay.Font.rounded(.caption2, weight: .medium))
                    .foregroundStyle(OneDay.inkFaint)
                    .lineLimit(1)
            }

            if let icon {
                Image(systemName: icon)
                    .font(OneDay.Font.rounded(.caption2, weight: .regular))
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
        // No `.waiting(friend:)` any more. A friend who hasn't filmed used to
        // get a 120pt card under every moment they hadn't filmed; who the room
        // is waiting on is one line at the bottom of the story page now, and
        // `RoomCast` is the only thing that decides it.
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
        // A tap gesture isn't a button to VoiceOver: without these the card
        // read as loose text and image fragments with no way to activate it.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
        .accessibilityAction { onTap?() }
    }

    /// Whose moment, which one, and — for an empty slot — that tapping films it.
    private var accessibilityTitle: String {
        let who = authorName ?? Strings.youLabel
        switch state {
        case .filmed:
            return showsMomentTitle ? "\(momentTitle), \(who)" : who
        case .mine, .upcoming:
            return showsMomentTitle ? "\(momentTitle), \(Strings.tapToFilm)" : Strings.tapToFilm
        }
    }

    private var tintForState: Color? {
        if case .mine = state { return .oneDayBrand }
        return nil
    }

    // MARK: Byline

    private var byline: some View {
        HStack(spacing: 8) {
            switch state {
            case .filmed, .mine:
                AvatarDot(name: authorName, size: 22)
                Text(authorName ?? Strings.youLabel)
                    .font(OneDay.Font.rounded(.footnote, weight: .bold))
                    .foregroundStyle(OneDay.ink)
                    .lineLimit(1)
            case .upcoming:
                // Fixed size: centred in a fixed 22pt disc, matching the avatar
                // it stands in for.
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
                        .font(OneDay.Font.rounded(.footnote, weight: .bold))
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
                    .font(OneDay.Font.rounded(.caption2, weight: .bold))
                    .foregroundStyle(OneDay.brandText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.oneDayBrand.opacity(0.12), in: Capsule())
            }
        }
    }

    private var reactionPill: some View {
        let distinct = Array(NSOrderedSet(array: reactions).array.compactMap { $0 as? String }.prefix(3))
        return HStack(spacing: 1) {
            ForEach(distinct, id: \.self) { Text($0).font(OneDay.Font.rounded(.caption2, weight: .regular)) }
            if reactions.count > distinct.count {
                Text("\(reactions.count)")
                    .font(OneDay.Font.rounded(.caption2, weight: .bold))
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
                        // Dark glass, not a bare material: the material went
                        // near-white in light mode and the white title on it
                        // vanished over a bright frame.
                        Text(momentTitle)
                            .font(OneDay.Font.rounded(.caption, weight: .bold))
                            .lineLimit(1)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .overVideoControl()
                            .padding(8)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "play.circle.fill")
                        .font(OneDay.Font.rounded(.title3, weight: .regular))
                        .foregroundStyle(.white.opacity(0.92))
                        .shadow(radius: 4)
                        .padding(8)
                }

        case .mine:
            EmptyFrame {
                VStack(spacing: 7) {
                    Image(systemName: showsMomentTitle ? momentIcon : "camera.fill")
                        .font(OneDay.Font.rounded(.title2, weight: .medium))
                        .foregroundStyle(OneDay.brandText)
                        .symbolEffect(.pulse)
                    if showsMomentTitle {
                        Text(momentTitle)
                            .font(OneDay.Font.rounded(.subheadline, weight: .bold))
                            .foregroundStyle(OneDay.ink)
                            .lineLimit(1)
                    }
                    Text(Strings.tapToFilm)
                        .font(OneDay.Font.caption)
                        .foregroundStyle(OneDay.brandText)
                }
                .padding(.vertical, 22)
            }

        case .upcoming:
            // Same words as `.mine`, quieter. The difference is emphasis, not
            // permission — saying "later today" would be a lie for a moment
            // whose slot has already passed.
            EmptyFrame {
                // No icon here — the byline above already carries it.
                Text(Strings.tapToFilm)
                    .font(OneDay.Font.caption)
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
