import SwiftUI

struct RoomDayList: View {
    let clips: [DayClip]
    let members: [(id: String, name: String)]
    let myID: String
    let onPlay: (DayClip) -> Void
    var reactions: (DayClip) -> [ClipReaction] = { _ in [] }
    var onReact: (DayClip, String) -> Void = { _, _ in }
    var hasPoked: (String) -> Bool = { _ in false }
    var onPoke: (String) -> Void = { _ in }

    @State private var pokedNow: Set<String> = []

    private static let spacing: CGFloat = 6
    private let grid = Array(repeating: GridItem(.flexible(), spacing: Self.spacing), count: 3)

    private var days: [(day: Date, clips: [DayClip])] {
        let calendar = Calendar.current
        let dated = clips.filter { $0.recordedAt != nil }
        return Dictionary(grouping: dated) { calendar.startOfDay(for: $0.recordedAt!) }
            .map { ($0.key, $0.value.sorted { $0.recordedAt! > $1.recordedAt! }) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        if clips.isEmpty {
            Text(Strings.roomFeedEmpty)
                .font(OneDay.Font.callout)
                .foregroundStyle(OneDay.inkSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
        } else {
            LazyVStack(alignment: .leading, spacing: 18) {
                if !notFilmedToday.isEmpty { pokeRow }
                ForEach(days, id: \.day) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.day.formatted(.dateTime.month().day().weekday(.abbreviated)
                            .locale(AppLanguage.effective.locale)))
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(OneDay.ink)
                        LazyVGrid(columns: grid, spacing: Self.spacing) {
                            ForEach(group.clips) { tile($0) }
                        }
                    }
                }
            }
            .accessibilityIdentifier("room-day-list")
        }
    }

    private func isMine(_ clip: DayClip) -> Bool {
        clip.authorID == myID || clip.authorID == RoomProgress.soloAuthorID
    }

    private func name(of clip: DayClip) -> String {
        if isMine(clip) { return Strings.youLabel }
        return members.first { $0.id == clip.authorID }?.name ?? clip.authorName ?? ""
    }

    private func tile(_ clip: DayClip) -> some View {
        Button { onPlay(clip) } label: {
            Color.clear
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay { ClipThumbnail(url: clip.url, refreshToken: clip.recordedAt) }
                .overlay {
                    LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 4) {
                        MemberFace(
                            id: isMine(clip) ? myID : (clip.authorID ?? clip.id),
                            name: isMine(clip) ? nil : name(of: clip), size: 18, isYou: isMine(clip))
                        if let at = clip.recordedAt {
                            Text(at.formatted(.roomClock))
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(6)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(name(of: clip)), \(clip.recordedAt?.formatted(date: .abbreviated, time: .shortened) ?? "")"))
        .accessibilityIdentifier("room-day-tile")
        .overlay(alignment: .topTrailing) {
            if !isMine(clip) {
                MoodReactButton(reactions: reactions(clip), myID: myID, showsOthers: false) { onReact(clip, $0) }
            }
        }
    }

    private var notFilmedToday: [(id: String, name: String)] {
        let calendar = Calendar.current
        let filmed = Set(clips.compactMap { clip in
            clip.recordedAt.flatMap { calendar.isDateInToday($0) ? clip.authorID : nil }
        })
        return members.filter { $0.id != myID && !filmed.contains($0.id) }
    }

    private var pokeRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: OneDay.Space.l) {
                ForEach(notFilmedToday, id: \.id) { member in
                    let sent = pokedNow.contains(member.id) || hasPoked(member.id)
                    Button {
                        onPoke(member.id)
                        pokedNow.insert(member.id)
                    } label: {
                        VStack(spacing: OneDay.Space.xs) {
                            MemberFace(id: member.id, name: member.name, size: 40)
                            Label(sent ? Strings.roomTilePoked : Strings.roomTilePoke,
                                  systemImage: sent ? "checkmark" : "hand.tap.fill")
                                .font(OneDay.Font.caption)
                                .foregroundStyle(sent ? OneDay.inkFaint : OneDay.brandText)
                                .lineLimit(1)
                        }
                        .frame(minWidth: 64, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(sent)
                    .accessibilityLabel("\(member.name), \(sent ? Strings.roomTilePoked : Strings.roomTilePoke)")
                    .accessibilityIdentifier("room-day-poke")
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}
