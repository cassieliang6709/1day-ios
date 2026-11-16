import SwiftUI


struct FilmReadyCard: View {
    let momentCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) { card }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(Strings.watchTheFilm))
            .accessibilityHint(Text(Strings.filmFromMoments(momentCount)))
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

                Text(Strings.filmFromMoments(momentCount))
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(OneDay.onBrand.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(OneDay.onBrand.opacity(0.9))
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

struct ClipThumb: View {
    let momentTitle: String
    let lanes: [MomentLane]
    var timeStamp: String?
    var authorNames: [String] = []
    var reaction: String?
    var awaitingMine = false
    var aspectRatio: CGFloat = 0.72
    var sourceAspect: CGFloat = 9.0 / 16
    var showsCaption = true
    let onTap: () -> Void

    private let radius: CGFloat = 16

    private var grid: (rows: Int, columns: Int) {
        VideoStitcher.grid(for: lanes.count, sourceAspect: sourceAspect)
    }

    var body: some View {
        Button(action: onTap) { thumb }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(accessibilityTitle))
            .accessibilityHint(Text(Strings.watchThisMoment))
            .animation(OneDay.Motion.soft, value: lanes.map(\.id).joined())
    }

    private var accessibilityTitle: String {
        let named = authorNames.filter { !$0.isEmpty }
        guard !named.isEmpty else { return momentTitle }
        return Strings.momentFilmedBy(momentTitle, names: named)
    }

    private var thumb: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay { frames.clipped() }
            .overlay(alignment: .topLeading) { topRow }
            .overlay(alignment: .topTrailing) { playGlyph }
            .overlay(alignment: .bottom) {
                if showsCaption {
                    caption
                } else if let reaction {
                    Text(reaction)
                        .font(.system(size: 10))
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
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
        return VStack(spacing: 0) {
            ForEach(
                Array(StoryGridView.rows(of: lanes, columns: split.columns).enumerated()),
                id: \.offset
            ) { _, row in
                HStack(spacing: 0) {
                    ForEach(row) { lane in
                        if let clip = lane.clip {
                            ClipThumbnail(
                                url: clip.url,
                                refreshToken: clip.recordedAt,
                                bedsInsteadOfCrops: true)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                        }
                    }
                }
            }
        }
    }

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

struct OpenSlotRow: View {
    let momentTitle: String
    let momentIcon: String
    var awaitingMine = false
    var isSuggested = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: momentIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(OneDay.brandText)
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
                    .foregroundStyle(OneDay.brandText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(OneDay.inkFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
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
