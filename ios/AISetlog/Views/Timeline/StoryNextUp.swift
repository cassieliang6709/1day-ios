import SwiftUI

/// The story page in three weights: how far the day has got, the one thing to
/// do next, and quiet lists of what happened and what hasn't.
///
/// It replaces a wall of equally weighted tiles. Every moment was the same
/// size, the same shape and equally tappable, which left the page with seven
/// invitations and no answer to "what now". `StoryAgenda` decides which moment
/// is next; these are the shapes that decision gets drawn in.

/// How much of the day exists. The bar and the count come from the same two
/// numbers the story itself is made of — moments in the plan, and moments
/// holding footage.
struct StoryProgressBar: View {
    let filmed: Int
    let total: Int

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(Double(filmed) / Double(total), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(Strings.momentsFilmed(filmed, total: total))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if total > 0, filmed >= total {
                    Text(Strings.dayIsFull)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.oneDayMint)
                        .lineLimit(1)
                }
            }

            // A `GeometryReader` rather than a fraction of `maxWidth`: the fill
            // has to be a real width so the capsule keeps its round ends at 1/7
            // of the way through a day.
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(OneDay.surfaceSoft.opacity(0.8))
                    Capsule()
                        .fill(OneDay.brandHorizontal)
                        .frame(width: max(proxy.size.width * fraction, fraction > 0 ? 8 : 0))
                }
            }
            .frame(height: 7)
            .animation(OneDay.Motion.soft, value: fraction)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The one thing to do next, and by a distance the heaviest object on the page.
///
/// Once every moment holds footage there is nothing left to film, so the card
/// becomes the way into the film. That entry point used to be a second
/// full-width button floating at the bottom of this same screen — two loud
/// actions, and the page never said which one was its point.
struct NextSlotCard: View {
    enum Kind: Equatable {
        /// Film this moment next.
        case film(title: String, icon: String, slot: Int, total: Int)
        /// Nothing left to film. The day is the film now.
        case watch(clipCount: Int)
    }

    let kind: Kind
    /// How long a clip runs, so the card can say what it's asking for.
    var durationLabel: String?
    /// Who else in the room has filmed. Nil in a solo story, and nil in a room
    /// nobody has joined.
    var roomNote: RoomCast.Note?
    let action: () -> Void

    var body: some View {
        Button(action: action) { card }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(headline))
            // Both sentences, even though the card only has room to print one:
            // how long the clip runs and who's already filmed are each worth
            // hearing before you tap.
            .accessibilityHint(Text(hint))
    }

    private var card: some View {
        HStack(spacing: 14) {
            Image(systemName: glyph)
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(.white.opacity(0.18), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.34), lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                Text(kicker)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .kerning(0.7)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(headline)
                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)

                smallPrint
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            OneDay.brand,
            in: RoundedRectangle(cornerRadius: OneDay.Radius.card, style: .continuous))
        .oneDayGlow()
        .contentShape(RoundedRectangle(cornerRadius: OneDay.Radius.card, style: .continuous))
    }

    /// In a shared room the card's last line is who else showed up, and it
    /// takes the caption's place rather than stacking under it — the card stays
    /// three lines tall, and "他俩拍了，就差你" is the more useful of the two
    /// sentences by a distance. The film's own caption keeps its place: how
    /// many clips are in it is a fact about the film, not about filming.
    @ViewBuilder
    private var smallPrint: some View {
        if case .film = kind, let roomNote {
            RoomNote(note: roomNote, tint: .white.opacity(0.9))
        } else {
            Text(caption)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var hint: String {
        [caption, roomNote?.text].compactMap { $0 }.joined(separator: " · ")
    }

    private var glyph: String {
        switch kind {
        case .film(_, let icon, _, _): icon
        case .watch: "film.stack.fill"
        }
    }

    private var kicker: String {
        switch kind {
        case .film(_, _, let slot, let total): Strings.nextUpPosition(slot, total: total)
        case .watch: Strings.dayIsFull
        }
    }

    private var headline: String {
        switch kind {
        case .film(let title, _, _, _): title
        case .watch: Strings.watchTheFilm
        }
    }

    private var caption: String {
        switch kind {
        case .film:
            guard let durationLabel else { return Strings.tapToFilm }
            return "\(Strings.tapToFilm) · \(durationLabel)"
        case .watch(let clipCount):
            return Strings.filmFromMoments(clipCount)
        }
    }
}

/// A moment that happened, at the size of a memory rather than a button.
///
/// One tap region, one meaning: it plays. The tile this replaces stacked three
/// of them on top of each other — a dashed border you could tap, a camera
/// bubble in the middle, and a play badge in the corner — so where your thumb
/// landed decided whether you were about to watch something or film something.
struct ClipThumb: View {
    let momentTitle: String
    /// Everyone who filmed this moment, in stacking order. Rendered with the
    /// split the finished film uses, so the thumbnail is a real preview of the
    /// moment rather than a lookalike.
    let lanes: [MomentLane]
    var timeStamp: String?
    /// Whose takes these are, in the order the thumbnail stacks them. Empty in
    /// a solo story: the badge answers "whose is this", and there is only one
    /// answer to that in a diary.
    var authorNames: [String] = []
    var reaction: String?
    /// A friend filmed this and I haven't. It only changes the edge — adding
    /// my own take is the quiet row's job, because this thumbnail already
    /// means "play what's here".
    var awaitingMine = false
    var aspectRatio: CGFloat = 0.72
    let onTap: () -> Void

    private let radius: CGFloat = 16

    private var grid: (rows: Int, columns: Int) {
        VideoStitcher.grid(for: lanes.count, in: CGSize(width: 100, height: 140))
    }

    var body: some View {
        Button(action: onTap) { thumb }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(momentTitle))
            .accessibilityHint(Text(Strings.watchThisMoment))
            .animation(OneDay.Motion.soft, value: lanes.map(\.id).joined())
    }

    /// A fixed `Color.clear` box with edge-pinned overlays: overlays never
    /// resize their base, so nothing in here can push past the clip frame the
    /// way a filling VStack does.
    private var thumb: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay { frames.clipped() }
            .overlay(alignment: .topLeading) { topRow }
            .overlay(alignment: .topTrailing) { playGlyph }
            .overlay(alignment: .bottom) { caption }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        awaitingMine ? Color.oneDaySky.opacity(0.8) : OneDay.hairline,
                        lineWidth: awaitingMine ? 1.5 : 1)
            }
            .oneDaySoftShadow(strength: 0.7)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    private var frames: some View {
        let split = grid
        return VStack(spacing: 1) {
            ForEach(
                Array(StoryGridView.rows(of: lanes, columns: split.columns).enumerated()),
                id: \.offset
            ) { _, row in
                HStack(spacing: 1) {
                    ForEach(row) { lane in
                        if let clip = lane.clip {
                            ClipThumbnail(url: clip.url, refreshToken: clip.recordedAt)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                        }
                    }
                }
            }
        }
    }

    /// Whose take it is, and when. Both facts about the same clip, so they sit
    /// in one cluster in one corner — the tile is 103pt wide and a second
    /// floating label anywhere else on it starts reading as another button.
    @ViewBuilder
    private var topRow: some View {
        if timeStamp != nil || !authorNames.isEmpty {
            HStack(spacing: 4) {
                if !authorNames.isEmpty {
                    AvatarStack(names: authorNames, maxShown: 3, size: 20)
                }
                if let timeStamp {
                    Text(timeStamp)
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding(6)
        }
    }

    /// Decoration, not a control. The badge that used to sit here was a second
    /// button inside the tile, half of it hanging over the first one.
    private var playGlyph: some View {
        Image(systemName: "play.circle.fill")
            .font(.system(size: 17))
            .foregroundStyle(.white.opacity(0.92))
            .shadow(radius: 3)
            .padding(6)
            .accessibilityHidden(true)
    }

    private var caption: some View {
        HStack(spacing: 4) {
            Text(momentTitle)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            if let reaction {
                Text(reaction).font(.system(size: 10))
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 14)
        .padding(.bottom, 7)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.62)],
                startPoint: .top, endPoint: .bottom))
    }
}

/// A moment that hasn't happened yet, as a line in a list.
///
/// Every open moment stays reachable — a 1-day story never locks one — but
/// only the next one gets the card. The rest read as what's coming, which is
/// what they are.
struct QuietSlotRow: View {
    let momentTitle: String
    let momentIcon: String
    /// A friend filmed this moment already; this row is how mine gets in.
    var awaitingMine = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: momentIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.oneDaySky)
                    .frame(width: 30, height: 30)
                    .background(OneDay.surfaceSoft.opacity(0.7), in: Circle())

                Text(momentTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 8)

                Text(awaitingMine ? Strings.addYourTake : Strings.notYetFilmed)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(awaitingMine ? Color.oneDayBlue : OneDay.inkFaint)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(OneDay.inkFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(Strings.record))
    }
}
