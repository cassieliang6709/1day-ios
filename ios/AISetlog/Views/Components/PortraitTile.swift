import SwiftUI

struct PortraitTile<Accessory: View>: View {
    let coverURL: URL?
    var refreshToken: Date?
    var caption: String?
    let title: String
    let subtitle: String
    var hasNew = false
    @ViewBuilder var accessory: () -> Accessory

    static var coverAspect: CGFloat { 3.0 / 4.0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cover
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(OneDay.ink)
                        .lineLimit(1)
                    if hasNew {
                        Circle().fill(Color.oneDayBrand).frame(width: 7, height: 7)
                            .accessibilityLabel(Strings.roomHasNew)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(OneDay.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(OneDay.hairline, lineWidth: 1)
        }
        .oneDaySoftShadow(strength: 0.45)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var cover: some View {
        ClipTile(url: coverURL, refreshToken: refreshToken, bedsInsteadOfCrops: true, edge: .flush)
            .aspectRatio(Self.coverAspect, contentMode: .fit)
            .overlay(alignment: .bottomLeading) {
                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(.horizontal, 10)
                        .padding(.top, 20)
                        .padding(.bottom, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LinearGradient(colors: [.clear, .black.opacity(0.6)],
                                                   startPoint: .top, endPoint: .bottom))
                }
            }
            .overlay(alignment: .topLeading) {
                accessory().padding(8)
            }
            .clipped()
    }
}
