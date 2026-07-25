import SwiftUI

struct DayCardView: View {
    let card: DayCard
    let status: DayCard.Status
    let title: String
    let isOneDay: Bool
    let clipURL: URL?
    /// Cell aspect (width / height) — follows the challenge's locked frame.
    var aspectRatio: CGFloat = 0.7

    var body: some View {
        // Color.clear fixes the cell box. Every piece of content is an
        // edge-pinned overlay — overlays never resize the base, so nothing can
        // push past the clip frame (the bug the VStack-fill version had).
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay { background(for: status).clipped() }
            .overlay { centerContent(for: status) }
            .overlay(alignment: .topTrailing) {
                if status == .done {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(radius: 3)
                        .padding(8)
                }
            }
            .overlay(alignment: .topLeading) {
                if status == .done, !card.reactions.isEmpty {
                    reactionBadge
                        .padding(6)
                }
            }
            .overlay(alignment: .bottom) {
                if status == .done {
                    HStack {
                        Text(title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer()
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.green)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(colors: [.clear, .black.opacity(0.55)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                if status == .today {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(BoardTheme.actionGradient, lineWidth: 2)
                } else if status != .done {
                    // Unrecorded slots read as an empty storyboard frame —
                    // a dashed sketch outline rather than a filled block.
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            BoardTheme.secondaryText.opacity(0.3),
                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
            }
            .shadow(
                color: status == .today ? BoardTheme.tint.opacity(0.45) : BoardTheme.deep.opacity(0.14),
                radius: status == .today ? 8 : 4, y: 3
            )
            .animation(.spring(duration: 0.45), value: card.clipFileName)
    }

    /// A small glassy pill in the tile corner: the distinct emoji used plus a
    /// total count, so the board shows interaction at a glance.
    private var reactionBadge: some View {
        let distinct = Array(NSOrderedSet(array: card.reactions.map(\.emoji)).array
            .compactMap { $0 as? String }.prefix(3))
        return HStack(spacing: 1) {
            ForEach(distinct, id: \.self) { Text($0).font(.system(size: 11)) }
            if card.reactions.count > 1 {
                Text("\(card.reactions.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.leading, 2)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
    }

    @ViewBuilder
    private func background(for status: DayCard.Status) -> some View {
        switch status {
        case .done:
            if let clipURL {
                // A live loop instead of a static frame — the board reads as
                // "footage in hand" the moment a slot is filled. recordedAt
                // rebuilds the player when a re-record overwrites the file.
                LoopingClipPlayer(url: clipURL, refreshToken: card.recordedAt)
            } else {
                Color(.systemGray5)
            }
        case .today:
            BoardTheme.card
        case .missed:
            BoardTheme.card
        case .locked:
            Color.oneDayMist.opacity(0.5)
        }
    }

    /// Centered label for the non-recorded states (today / missed / locked).
    @ViewBuilder
    private func centerContent(for status: DayCard.Status) -> some View {
        switch status {
        case .done:
            EmptyView()
        case .today:
            VStack(spacing: 6) {
                Image(systemName: ChallengeTemplate.icon(forPrompt: title))
                    .font(.system(size: 32))
                    .symbolEffect(.pulse)
                    .foregroundStyle(BoardTheme.primary)
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                Text(Strings.record)
                    .font(.system(size: 10))
                    .opacity(0.85)
            }
            .foregroundStyle(BoardTheme.primaryText)
        case .missed:
            VStack(spacing: 5) {
                Image(systemName: "exclamationmark.arrow.circlepath")
                    .font(.system(size: 24))
                    .foregroundStyle(BoardTheme.primary)
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                Text(Strings.catchUp)
                    .font(.system(size: 10))
                    .foregroundStyle(BoardTheme.secondaryText)
            }
            .foregroundStyle(BoardTheme.primaryText)
        case .locked:
            VStack(spacing: 5) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 20))
                Text(Strings.lockedSlot(oneDay: isOneDay, day: card.day))
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(BoardTheme.secondaryText.opacity(0.72))
        }
    }
}
