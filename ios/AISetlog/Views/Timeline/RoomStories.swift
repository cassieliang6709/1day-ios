import SwiftUI

struct RoomPeopleRow: View {
    let columns: [RoomFeed.Column]
    var canFilm = true
    var isToday = true
    var selected: String?
    var signedOut = false
    let onSelect: (String) -> Void
    let onOpenAll: (String) -> Void
    let onFilm: () -> Void
    let hasPoked: (String) -> Bool
    let onPoke: (String) -> Void
    var trailing: AnyView? = nil

    @State private var pokedNow: Set<String> = []
    @State private var shaking: String?

    private static let faceSize: CGFloat = 40

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: OneDay.Space.s) {
                ForEach(columns) { column in
                    person(column)
                }
                if let trailing { trailing }
            }
            .padding(.vertical, OneDay.Space.xs)
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.impact(weight: .medium), trigger: pokedNow)
        .accessibilityIdentifier("room-people")
    }

    @ViewBuilder
    private func person(_ column: RoomFeed.Column) -> some View {
        let filmed = !column.clips.isEmpty
        if column.isMine, isToday {
            Button(action: onFilm) {
                cell(column, filmed: filmed, showsPlus: true)
            }
            .buttonStyle(.plain)
            .disabled(!canFilm)
            .accessibilityLabel(Strings.roomFeedFilm)
            .accessibilityIdentifier("room-people-me")
        } else {
            other(column, filmed: filmed)
        }
    }

    private func canPoke(_ column: RoomFeed.Column, filmed: Bool) -> Bool {
        isToday && !filmed && !signedOut && !pokedNow.contains(column.id) && !hasPoked(column.id)
    }

    private func poke(_ column: RoomFeed.Column) {
        onPoke(column.id)
        pokedNow.insert(column.id)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.3)) { shaking = column.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(OneDay.Motion.snap) { shaking = nil }
        }
    }

    private func tap(_ column: RoomFeed.Column, filmed: Bool) {
        if filmed {
            onSelect(column.id)
        } else {
            onOpenAll(column.id)
        }
    }

    @ViewBuilder
    private func other(_ column: RoomFeed.Column, filmed: Bool) -> some View {
        let pokeable = canPoke(column, filmed: filmed)
        let poked = pokedNow.contains(column.id) || (isToday && !filmed && hasPoked(column.id))
        let base = cell(column, filmed: filmed, showsPlus: false, poked: poked)
            .rotationEffect(.degrees(shaking == column.id ? 8 : 0))
            .contextMenu {
                if filmed {
                    Button(Strings.roomPersonOnlyDay(today: isToday), systemImage: "eye") { onSelect(column.id) }
                }
                Button(Strings.roomPersonSeeAll, systemImage: "square.grid.2x2") { onOpenAll(column.id) }
                if pokeable {
                    Button(Strings.roomTilePoke, systemImage: "hand.tap") { poke(column) }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(column.name)
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(selected == column.id ? .isSelected : [])
            .accessibilityIdentifier(filmed ? "room-people-filmed" : "room-people-person")
        if pokeable {
            base
                .onTapGesture(count: 2) { poke(column) }
                .onTapGesture { tap(column, filmed: filmed) }
                .accessibilityAction(named: Text(Strings.roomTilePoke)) { poke(column) }
                .accessibilityAction { tap(column, filmed: filmed) }
        } else {
            base
                .onTapGesture { tap(column, filmed: filmed) }
                .accessibilityAction { tap(column, filmed: filmed) }
        }
    }

    static func addCell(_ label: String) -> some View {
        VStack(spacing: OneDay.Space.xs) {
            Image(systemName: "plus")
                .font(OneDay.Font.headline)
                .foregroundStyle(OneDay.brandText)
                .frame(width: faceSize, height: faceSize)
                .overlay(Circle().strokeBorder(OneDay.inkFaint, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                .padding(OneDay.Space.xs)
            Text(label)
                .font(OneDay.Font.caption)
                .foregroundStyle(OneDay.inkSoft)
                .lineLimit(1)
        }
        .frame(minWidth: 50)
        .contentShape(Rectangle())
    }

    private func cell(
        _ column: RoomFeed.Column, filmed: Bool, showsPlus: Bool, poked: Bool = false
    ) -> some View {
        let isPicked = selected == column.id
        return VStack(spacing: OneDay.Space.xs) {
            MemberFace(id: column.id, name: column.isMine ? nil : column.name,
                       size: Self.faceSize, isYou: column.isMine, showsMood: false)
                .opacity(filmed ? 1 : 0.4)
                .padding(OneDay.Space.xs)
                .overlay {
                    Circle().strokeBorder(Color.oneDayBrand, lineWidth: filmed ? (isPicked ? 3.5 : 2) : 0)
                }
                .overlay(alignment: .bottomTrailing) {
                    if showsPlus {
                        Image(systemName: "plus")
                            .font(OneDay.Font.micro)
                            .foregroundStyle(OneDay.onBrand)
                            .frame(width: 20, height: 20)
                            .background(Color.oneDayBrand, in: Circle())
                            .overlay(Circle().strokeBorder(OneDay.canvas, lineWidth: 2))
                    }
                }
            Text(poked ? Strings.roomTilePoked : column.name)
                .font(OneDay.Font.caption)
                .foregroundStyle(poked ? OneDay.inkFaint : OneDay.inkSoft)
                .lineLimit(1)
        }
        .frame(minWidth: 50)
        .contentShape(Rectangle())
    }
}
