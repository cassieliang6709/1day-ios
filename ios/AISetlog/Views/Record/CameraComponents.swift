import SwiftUI

/// Shared camera/recording UI pieces used by `RecordClipView` and
/// `ClipPreviewView`: the framed camera shell, the burned-in moment stamp,
/// brand/identity badges, and caption editors.

struct CuteCameraBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(.systemBackground),
                Color.cyan.opacity(0.12),
                Color(.systemBackground),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

struct CameraShell<Content: View>: View {
    let name: String?
    let momentTitle: String
    let day: Int
    let mode: MomentStampOverlay.Mode
    let timestamp: Date?
    let overlayText: String?
    let clipSeconds: Double
    /// nil = the classic portrait frame; set for landscape challenges.
    var aspectRatio: CGFloat? = nil
    @ViewBuilder var content: Content

    private var tint: Color { Identity.tint(for: name) }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                content
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                MomentStampOverlay(
                    name: name,
                    momentTitle: momentTitle,
                    day: day,
                    mode: mode,
                    timestamp: timestamp,
                    overlayText: overlayText,
                    clipSeconds: clipSeconds
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(tint, lineWidth: 3)
            }
            .shadow(color: tint.opacity(0.35), radius: 18, y: 8)
        }
        .aspectRatio(aspectRatio ?? 9 / 14.3, contentMode: .fit)
    }
}

struct MomentStampOverlay: View {
    enum Mode {
        case live
        case recording
        case review
    }

    let name: String?
    let momentTitle: String
    let day: Int
    let mode: Mode
    let timestamp: Date?
    var overlayText: String?
    var clipSeconds: Double = 2

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var stampDate: Date { timestamp ?? .now }
    private var stampLocale: Locale {
        Locale(identifier: appLanguage.resolved.localeCode)
    }

    private var dateText: String {
        stampDate.formatted(
            .dateTime
                .year()
                .month(.abbreviated)
                .day()
                .locale(stampLocale)
        )
    }

    private var timeText: String {
        stampDate.formatted(
            .dateTime
                .hour()
                .minute()
                .locale(stampLocale)
        )
    }

    private var modeText: String {
        mode == .recording ? "REC 00:\(String(format: "%02d", Int(clipSeconds)))" : Strings.capturedLabel
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let scale = min(max(min(size.width / 360, size.height / 570), 0.62), 1)
            let edgeInset = max(16, 28 * scale)

            ZStack {
                LinearGradient(
                    colors: [.black.opacity(0.22), .clear, .black.opacity(0.34)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack {
                    HStack(alignment: .top, spacing: 8 * scale) {
                        BrandStamp(scale: scale)
                        Spacer(minLength: 6 * scale)
                        VStack(alignment: .trailing, spacing: 4 * scale) {
                            Text(dateText)
                                .font(.system(size: 14 * scale, weight: .heavy, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.68)
                                .allowsTightening(true)
                            Text(timeText)
                                .font(.system(size: 22 * scale, weight: .black, design: .rounded))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.68)
                                .allowsTightening(true)
                        }
                        .foregroundStyle(.white)
                    }
                    .padding(edgeInset)

                    Spacer(minLength: 8 * scale)

                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 9 * scale) {
                            if let name, !name.isEmpty {
                                NameChip(name: name, scale: scale)
                            }
                            Text(momentTitle)
                                .font(.system(size: 22 * scale, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .minimumScaleFactor(0.62)
                                .allowsTightening(true)
                            Text(Strings.momentN(day))
                                .font(.system(size: 12 * scale, weight: .black, design: .rounded))
                                .foregroundStyle(.white.opacity(0.78))
                                .lineLimit(1)
                            HStack(spacing: 7 * scale) {
                                Capsule()
                                    .fill(.white.opacity(0.42))
                                    .frame(width: 34 * scale, height: max(3, 5 * scale))
                                Capsule()
                                    .fill(.white)
                                    .frame(width: 46 * scale, height: max(3, 5 * scale))
                                Capsule()
                                    .fill(.white.opacity(0.42))
                                    .frame(width: 34 * scale, height: max(3, 5 * scale))
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(edgeInset)
                }

                if mode == .recording {
                    Text(modeText)
                        .font(.system(size: 13 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12 * scale)
                        .padding(.vertical, 7 * scale)
                        .background(.red, in: Capsule())
                        .position(x: size.width * 0.5, y: size.height * 0.5)
                }

                if let overlayText, !overlayText.isEmpty {
                    Text(overlayText)
                        .font(.system(size: 22 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.68)
                        .shadow(color: .black.opacity(0.28), radius: 5 * scale, y: 2 * scale)
                        .padding(.horizontal, 38 * scale)
                        .position(x: size.width * 0.5, y: size.height * 0.43)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Whose clip this is — a small dashed pill with a pencil, sitting above the
/// moment title in the live preview.
struct NameChip: View {
    let name: String
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 6 * scale) {
            Image(systemName: "pencil")
                .font(.system(size: 11 * scale, weight: .bold))
            Text(name)
                .font(.system(size: 13 * scale, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12 * scale)
        .padding(.vertical, 7 * scale)
        .background(.black.opacity(0.22), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(
                    .white.opacity(0.85),
                    style: StrokeStyle(lineWidth: max(0.8, 1.2 * scale), dash: [5 * scale, 4 * scale])
                )
        )
    }
}

struct BrandStamp: View {
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 9 * scale) {
            Text("1D")
                .font(.system(size: 16 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .frame(width: 42 * scale, height: 42 * scale)
                .background(.white, in: Circle())
                .overlay(Circle().stroke(Color.oneDayBlue, lineWidth: max(2, 3 * scale)))

            VStack(alignment: .leading, spacing: max(1, scale)) {
                Text("1DAY")
                    .font(.system(size: 15 * scale, weight: .black, design: .rounded))
                Text(Strings.dailyFilm)
                    .font(.system(size: 10 * scale, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .opacity(0.8)
            }
            .foregroundStyle(.white)
        }
    }
}

/// On-video center caption editor: the text sits exactly where it will be
/// burned into the exported film, so what you type is what ships.
struct CaptionOverlayEditor: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        GeometryReader { proxy in
            let scale = min(max(min(proxy.size.width / 360, proxy.size.height / 570), 0.62), 1)

            TextField(
                "",
                text: $text,
                prompt: Text(Strings.addCaption)
                    .foregroundStyle(.white.opacity(isFocused.wrappedValue ? 0.32 : 0.42)),
                axis: .vertical
            )
            .font(.system(size: 22 * scale, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .tint(Color.oneDayCyan)
            .textInputAutocapitalization(.sentences)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused(isFocused)
            .textFieldStyle(.plain)
            .lineLimit(1...2)
            .minimumScaleFactor(0.68)
            .shadow(color: .black.opacity(0.28), radius: 5 * scale, y: 2 * scale)
            .padding(.horizontal, 14 * scale)
            .frame(width: proxy.size.width * 0.76, height: 82 * scale)
            .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.43)
            .onChange(of: text) { _, newValue in
                if newValue.count > 40 {
                    text = String(newValue.prefix(40))
                }
            }
        }
        .allowsHitTesting(true)
    }
}

struct CaptionEditor: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "textformat")
                .font(.headline.bold())
                .foregroundStyle(Color.oneDayBlue)
                .frame(width: 30, height: 30)
                .background(Color.oneDayBlue.opacity(0.12), in: Circle())

            TextField(
                "",
                text: $text,
                prompt: Text(Strings.writeOnMoment)
                    .foregroundStyle(.secondary)
            )
            .font(.subheadline.weight(.semibold))
            .textInputAutocapitalization(.sentences)
            .submitLabel(.done)
            .focused(isFocused)
            .onChange(of: text) { _, newValue in
                if newValue.count > 32 {
                    text = String(newValue.prefix(32))
                }
            }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body.bold())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.86), in: Capsule())
        .overlay(Capsule().stroke(Color.oneDayBlue.opacity(0.16), lineWidth: 1))
    }
}
