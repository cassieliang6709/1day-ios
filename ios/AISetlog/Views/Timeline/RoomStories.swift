import SwiftUI

struct RoomPeopleRow: View {
    let columns: [RoomFeed.Column]
    var canFilm = true
    var isToday = true
    let onSelect: (String) -> Void
    let onFilm: () -> Void
    var trailing: AnyView? = nil

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
                cell(column, filmed: filmed, showsPlus: true)
            }
            .buttonStyle(.plain)
            .disabled(!canFilm)
            .accessibilityLabel(Strings.roomFeedFilm)
            .accessibilityIdentifier("room-people-me")
        } else {
            Button { onSelect(column.id) } label: {
                cell(column, filmed: filmed, showsPlus: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(column.name)
            .accessibilityIdentifier(filmed ? "room-people-filmed" : "room-people-person")
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

    private func cell(_ column: RoomFeed.Column, filmed: Bool, showsPlus: Bool) -> some View {
        VStack(spacing: OneDay.Space.xs) {
            MemberFace(id: column.id, name: column.isMine ? nil : column.name,
                       size: Self.faceSize, isYou: column.isMine, showsMood: false)
                .opacity(filmed ? 1 : 0.4)
                .padding(OneDay.Space.xs)
                .overlay {
                    Circle().strokeBorder(Color.oneDayBrand, lineWidth: filmed ? 2 : 0)
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
            Text(column.name)
                .font(OneDay.Font.caption)
                .foregroundStyle(OneDay.inkSoft)
                .lineLimit(1)
        }
        .frame(minWidth: 50)
        .contentShape(Rectangle())
    }
}
