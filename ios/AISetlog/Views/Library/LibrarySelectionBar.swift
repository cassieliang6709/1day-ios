import SwiftUI

struct LibrarySelectionBar: View {
    let picked: [LibraryClip]
    let onMake: () -> Void

    @State private var seconds: Int?

    var body: some View {
        HStack(spacing: 12) {
            Text(picked.isEmpty
                 ? Strings.pickClipsHint
                 : Strings.librarySelectedSummary(picked.count, seconds: seconds))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(OneDay.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityIdentifier("library-selected-summary")
            Spacer(minLength: 4)
            Button(Strings.libraryMakeVlogCTA, action: onMake)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(OneDay.onBrand)
                .padding(.horizontal, 18)
                .frame(height: 44)
                .background(Color.oneDayBrand, in: Capsule())
                .opacity(picked.isEmpty ? 0.45 : 1)
                .disabled(picked.isEmpty)
                .accessibilityIdentifier("library-make-vlog")
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassSurface(radius: 30)
        .padding(.horizontal, 20)
        .task(id: picked.map(\.id)) {
            seconds = nil
            seconds = await ClipDurations.totalSeconds(of: picked.map(\.url))
        }
    }
}

struct VlogRequest: Identifiable {
    let clips: [LibraryClip]
    var id: String { clips.map(\.id).joined(separator: "|") }
}
