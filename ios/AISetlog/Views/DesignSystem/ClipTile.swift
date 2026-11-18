import SwiftUI

struct ClipTile: View {
    enum Edge {
        case inset
        case flush
    }

    let url: URL?
    var refreshToken: Date?
    var bedsInsteadOfCrops = false
    var edge: Edge = .inset
    var isSelected = false
    var scrim = false

    private var radius: CGFloat { edge == .inset ? OneDay.Radius.tile : 0 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Color.clear
            .overlay {
                if let url {
                    ClipThumbnail(url: url, refreshToken: refreshToken, bedsInsteadOfCrops: bedsInsteadOfCrops)
                } else {
                    StoryCoverPlaceholder()
                }
            }
            .overlay {
                if scrim { OneDay.scrim }
            }
            .clipShape(shape)
            .overlay {
                if isSelected {
                    shape.strokeBorder(Color.oneDayBrand, lineWidth: 3)
                } else if edge == .inset {
                    shape.strokeBorder(OneDay.hairline, lineWidth: 1)
                }
            }
            .contentShape(shape)
    }
}

struct ClipTileLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(OneDay.Font.micro)
            .monospacedDigit()
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
            .padding(OneDay.Space.s)
    }
}
