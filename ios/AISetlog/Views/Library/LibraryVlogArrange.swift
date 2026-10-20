import SwiftUI

/// The vlog sheet's first step: the picked clips in the order they'll play,
/// dragged into a different order if wanted, any one previewed on top.
struct LibraryVlogArrange: View {
    @Binding var order: [LibraryClip]
    let onMake: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var previewing: LibraryClip?

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    var body: some View {
        VStack(spacing: 12) {
            header
            preview
            list
            Button(Strings.libraryMakeVlogCTA, action: onMake)
                .buttonStyle(.primaryAction)
                .padding(.horizontal, 20)
                .accessibilityIdentifier("vlog-arrange-make")
        }
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(Strings.vlogArrangeTitle)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                Spacer()
                IconBubble(systemName: "xmark") { dismiss() }
            }
            Text(Strings.vlogArrangeHint)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(OneDay.inkSoft)
        }
        .padding(.horizontal, 20)
    }

    /// The tapped clip, else the first one, looping.
    @ViewBuilder
    private var preview: some View {
        if let clip = previewing ?? order.first {
            LoopingClipPlayer(url: clip.url, refreshToken: clip.recordedAt)
                .id(clip.id)
                .frame(width: 150, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var list: some View {
        List {
            ForEach(Array(order.enumerated()), id: \.element.id) { index, clip in
                row(clip, number: index + 1)
                    .listRowBackground(Color.clear)
            }
            .onMove { order.move(fromOffsets: $0, toOffset: $1) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(.active))
    }

    private func row(_ clip: LibraryClip, number: Int) -> some View {
        let isShown = (previewing ?? order.first)?.id == clip.id
        return Button {
            previewing = clip
        } label: {
            HStack(spacing: 12) {
                Text("\(number)")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.oneDayBrand, in: Circle())
                ClipThumbnail(url: clip.url, refreshToken: clip.recordedAt)
                    .frame(width: 40, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(clip.recordedAt.formatted(
                        .dateTime.month().day().hour().minute()
                            .locale(AppLanguage.effective.locale)))
                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
                        .foregroundStyle(OneDay.ink)
                    if let source = sourceName(clip) {
                        Text(source)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(OneDay.inkSoft)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if isShown {
                    Image(systemName: "play.circle.fill")
                        .foregroundStyle(OneDay.brandText)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("vlog-arrange-row-\(number)")
    }

    /// The story the clip is in; nil for a draft, which is in none.
    private func sourceName(_ clip: LibraryClip) -> String? {
        switch clip.source {
        case .story(_, let title, _): title
        case .draft: nil
        }
    }
}
