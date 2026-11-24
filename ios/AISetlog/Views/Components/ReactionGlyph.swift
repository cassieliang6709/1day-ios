import SwiftUI

struct ReactionGlyph: View {
    let key: String
    var size: CGFloat = 20

    var body: some View {
        if let mood = ClipReaction.mood(for: key) {
            Image(mood.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityLabel(mood.label)
        } else {
            Text(key)
                .font(OneDay.Font.headline)
                .frame(width: size, height: size)
        }
    }
}
