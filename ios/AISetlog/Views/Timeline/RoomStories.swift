import SwiftUI

struct RoomStoriesRow: View {
    let columns: [RoomFeed.Column]
    var selected: String?
    let onOpen: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(columns) { column in
                let filmed = !column.clips.isEmpty
                let isPicked = selected == column.id
                Button { onOpen(column.id) } label: {
                    Group {
                        if filmed {
                            MemberFace(id: column.id, name: column.isMine ? nil : column.name,
                                       size: 28, isYou: column.isMine, showsMood: false)
                                .padding(2)
                                .overlay {
                                    Circle().strokeBorder(
                                        Color.oneDayBrand, lineWidth: isPicked ? 3 : 1.5)
                                }
                        } else {
                            Circle()
                                .fill(OneDay.inkFaint.opacity(0.5))
                                .frame(width: 8, height: 8)
                        }
                    }
                    .frame(minWidth: 32, minHeight: 44)
                    .contentShape(Rectangle())
                    .opacity(selected == nil || isPicked ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .disabled(!filmed)
                .accessibilityLabel(column.name)
                .accessibilityAddTraits(isPicked ? .isSelected : [])
                .accessibilityIdentifier("room-story-face")
            }
        }
        .frame(maxWidth: .infinity)
    }
}
