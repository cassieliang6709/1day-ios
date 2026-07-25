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

    private var stampDate: Date { timestamp ?? .now }

    private var dateText: String {
        stampDate.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private var timeText: String {
        stampDate.formatted(date: .omitted, time: .shortened)
    }

    private var modeText: String {
        mode == .recording ? "REC 00:\(String(format: "%02d", Int(clipSeconds)))" : Strings.capturedLabel
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(
                    colors: [.black.opacity(0.22), .clear, .black.opacity(0.34)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack {
                    HStack(alignment: .top) {
                        BrandStamp()
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(dateText)
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                            Text(timeText)
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .monospacedDigit()
                        }
                        .foregroundStyle(.white)
                    }
                    .padding(28)

                    Spacer()

                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 9) {
                            if let name, !name.isEmpty {
                                NameChip(name: name)
                            }
                            Text(momentTitle)
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .minimumScaleFactor(0.72)
                            Text(Strings.momentN(day))
                                .font(.caption.weight(.black))
                                .foregroundStyle(.white.opacity(0.78))
                            HStack(spacing: 7) {
                                Capsule()
                                    .fill(.white.opacity(0.42))
                                    .frame(width: 34, height: 5)
                                Capsule()
                                    .fill(.white)
                                    .frame(width: 46, height: 5)
                                Capsule()
                                    .fill(.white.opacity(0.42))
                                    .frame(width: 34, height: 5)
                            }
                        }

                        Spacer()
                    }
                    .padding(28)
                }

                if mode == .recording {
                    Text(modeText)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.red, in: Capsule())
                        .position(x: size.width * 0.5, y: size.height * 0.5)
                }

                if let overlayText, !overlayText.isEmpty {
                    Text(overlayText)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                        .shadow(color: .black.opacity(0.28), radius: 5, y: 2)
                        .padding(.horizontal, 38)
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

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "pencil")
                .font(.system(size: 11, weight: .bold))
            Text(name)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.black.opacity(0.22), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(0.85), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
        )
    }
}

struct BrandStamp: View {
    var body: some View {
        HStack(spacing: 9) {
            Text("1D")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .frame(width: 42, height: 42)
                .background(.white, in: Circle())
                .overlay(Circle().stroke(Color.oneDayBlue, lineWidth: 3))

            VStack(alignment: .leading, spacing: 1) {
                Text("1DAY")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                Text(Strings.dailyFilm)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .opacity(0.8)
            }
            .foregroundStyle(.white)
        }
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
                prompt: Text("Write on this moment")
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
