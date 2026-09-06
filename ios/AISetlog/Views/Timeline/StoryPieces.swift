import SwiftUI

/// The pieces the story page is built from: how far the day has got, the
/// moments that are still yours to take, the moments that happened, and — only
/// once there is nothing left to film — the film.
///
/// The page is deliberately weighted in that order rather than around a single
/// next step. An earlier version put one moment on a full-width gradient card
/// labelled "next up" and demoted the rest to a list, which reads as a queue:
/// this one first, the others after. A day doesn't work like that. You film
/// the walk because you're on the walk. So every open moment here is the same
/// row, the same size and the same tap; the only thing the suggestion earns is
/// a softer word and a tint you have to be looking for.

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

/// The film, once every moment holds footage — and the only object on this
/// page that gets the loudest treatment.
///
/// It earns that because by the time it appears there is genuinely nothing
/// else to do: no moment is still open, so a full-width gradient card can't be
/// read as a queue of one. While the day is still being filmed, nothing here
/// looks like this. The way into the film used to be a second full-width
/// button floating at the bottom of this same screen, competing with a card
/// that wanted you to film instead.
struct FilmReadyCard: View {
    let clipCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) { card }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(Strings.watchTheFilm))
            .accessibilityHint(Text(Strings.filmFromMoments(clipCount)))
    }

    private var card: some View {
        HStack(spacing: 14) {
            Image(systemName: "film.stack.fill")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(.white.opacity(0.18), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.34), lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.dayIsFull)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .kerning(0.7)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(Strings.watchTheFilm)
                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)

                Text(Strings.filmFromMoments(clipCount))
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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

/// A moment that's still yours to take, as one row among equals.
///
/// Every row in this list is the same height, the same weight and the same
/// tap: it opens the camera on that moment. Nothing is dimmed, nothing is
/// numbered, and there is no order to work through — three rows down is as
/// available as the first one.
///
/// Two rows say something extra, and both are one short phrase rather than a
/// different kind of object:
///
/// - `isSuggested` — the place to start if you'd rather not choose. It gets a
///   tint you have to be looking for and a question, not an instruction.
/// - `awaitingMine` — a friend filmed this one; the thumbnail above plays
///   their take and this row is how mine gets in.
///
/// The two can never both be true: a moment somebody has filmed is never the
/// one being suggested.
struct OpenSlotRow: View {
    let momentTitle: String
    let momentIcon: String
    /// A friend filmed this moment already; this row is how mine gets in.
    var awaitingMine = false
    /// Somewhere to start, for a day you haven't got into yet.
    var isSuggested = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: momentIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.oneDayBlue)
                    .frame(width: 34, height: 34)
                    .background(Color.oneDayMist.opacity(0.55), in: Circle())

                Text(momentTitle)
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 8)

                Text(trailingLabel)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.oneDayBlue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(OneDay.inkFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            // A wash rather than a border. A stroked outline reads as a
            // selected item — as though the others were waiting their turn —
            // and that is the exact wrong sentence for this list.
            .background(isSuggested ? Color.oneDayMist.opacity(0.35) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(momentTitle))
        .accessibilityHint(Text(trailingLabel))
    }

    private var trailingLabel: String {
        if awaitingMine { return Strings.addYourTake }
        return isSuggested ? Strings.startHere : Strings.filmThisOne
    }
}
