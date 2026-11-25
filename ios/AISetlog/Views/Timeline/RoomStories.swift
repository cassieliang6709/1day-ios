import SwiftUI

struct RoomPeopleRow: View {
    let columns: [RoomFeed.Column]
    var selected: String?
    var canFilm = true
    var signedOut = false
    var isToday = true
    let onSelect: (String) -> Void
    let onFilm: () -> Void
    let hasPoked: (String) -> Bool
    let onPoke: (String) -> Void
    var trailing: AnyView? = nil

    @State private var pokedNow: Set<String> = []

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
        .accessibilityIdentifier("room-people")
    }

    @ViewBuilder
    private func person(_ column: RoomFeed.Column) -> some View {
        let filmed = !column.clips.isEmpty
        if column.isMine, isToday {
            Button(action: onFilm) {
                cell(column, filmed: filmed, label: column.name, showsPlus: true)
            }
            .buttonStyle(.plain)
            .disabled(!canFilm)
            .accessibilityLabel(Strings.roomFeedFilm)
            .accessibilityIdentifier("room-people-me")
        } else if filmed {
            Button { onSelect(column.id) } label: {
                cell(column, filmed: true, label: column.name, showsPlus: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(column.name)
            .accessibilityAddTraits(selected == column.id ? .isSelected : [])
            .accessibilityIdentifier("room-people-filmed")
        } else if column.isMine || !isToday {
            cell(column, filmed: false, label: column.name, showsPlus: false)
                .accessibilityElement(children: .combine)
        } else {
            let sent = pokedNow.contains(column.id) || hasPoked(column.id)
            Button {
                onPoke(column.id)
                pokedNow.insert(column.id)
            } label: {
                cell(column, filmed: false,
                     label: sent ? Strings.roomTilePoked : Strings.roomTilePoke, showsPlus: false,
                     labelColor: sent ? OneDay.inkFaint : OneDay.brandText)
            }
            .buttonStyle(.plain)
            .disabled(sent || signedOut)
            .accessibilityLabel("\(column.name), \(sent ? Strings.roomTilePoked : Strings.roomTilePoke)")
            .accessibilityIdentifier("room-people-poke")
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
        _ column: RoomFeed.Column, filmed: Bool, label: String, showsPlus: Bool,
        labelColor: Color = OneDay.inkSoft
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
            Text(label)
                .font(OneDay.Font.caption)
                .foregroundStyle(labelColor)
                .lineLimit(1)
        }
        .frame(minWidth: 50)
        .contentShape(Rectangle())
    }
}
