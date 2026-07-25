import SwiftUI

struct MemberChip: View {
    let name: String

    private var tint: Color { Identity.tint(for: name) }

    private var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    var body: some View {
        HStack(spacing: 7) {
            Text(initials.isEmpty ? "?" : initials)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tint.gradient, in: Circle())
            Text(name)
                .font(.subheadline)
                .lineLimit(1)
        }
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .padding(.leading, 4)
        .foregroundStyle(BoardTheme.primaryText)
        .background(BoardTheme.cardStrong, in: Capsule())
        .overlay(Capsule().strokeBorder(BoardTheme.stroke, lineWidth: 1))
    }
}

