import SwiftUI

/// Shared camera/recording UI pieces used by `RecordClipView`: the framed
/// camera shell, the moment stamp that previews what the film will carry, and
/// the caption editors.

struct CuteCameraBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [
                OneDay.canvas,
                Color.cyan.opacity(0.12),
                OneDay.canvas,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

struct CameraShell<Content: View>: View {
    /// Whose camera this is. Only the frame's tint uses it now — the picture
    /// itself no longer gets labelled with your own name.
    let name: String?
    /// The moment's name, or nil when this take isn't a moment in a story yet.
    let momentTitle: String?
    let day: Int
    /// How many moments the story has. 0 means "no story behind this take",
    /// which is what free-form capture passes.
    var momentCount = 0
    let mode: MomentStampOverlay.Mode
    let timestamp: Date?
    let overlayText: String?
    let clipSeconds: Double
    var showsPrompt = true
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
                    momentTitle: momentTitle,
                    day: day,
                    momentCount: momentCount,
                    mode: mode,
                    timestamp: timestamp,
                    overlayText: overlayText,
                    clipSeconds: clipSeconds,
                    showsPrompt: showsPrompt
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(tint, lineWidth: 3)
            }
            .shadow(color: tint.opacity(0.35), radius: 18, y: 8)
        }
        // The fallback is the portrait capture shape, same as
        // `Challenge.Orientation.portrait.aspectRatio`. It used to be 9/14.3,
        // which is wider than anything the camera writes — and since `content`
        // aspect-fills, a wider shell meant the preview was a cropped, scaled-
        // up view of the take rather than the take.
        .aspectRatio(aspectRatio ?? 9 / 16, contentMode: .fit)
    }
}

/// What the camera draws on top of the picture.
///
/// The rule for this layer: **whatever you can see here has to survive into the
/// finished film.** It sits on the frame like a burned-in stamp, so anything it
/// shows reads as a promise about the export.
///
/// Three things used to break that promise and are gone:
/// - the 1Day badge in the top-left, which the film never draws (the film's
///   own mark is a small "made with 1Day" in the bottom-*left*, added by
///   `VideoStitcher.addWatermark`);
/// - your own name in a dashed pill, which the film only ever shows as an
///   initial in a room with more than one person in it;
/// - "MOMENT 1" plus three decorative bars, which said the same thing on every
///   take of every story.
///
/// What's left maps onto `VideoStitcher`: date and time → `addTimestampPill`,
/// the moment's name → `addCaption`, the caption → `addOverlayText`.
struct MomentStampOverlay: View {
    enum Mode {
        case live
        case recording
        case review
    }

    let momentTitle: String?
    let day: Int
    var momentCount = 0
    let mode: Mode
    let timestamp: Date?
    var overlayText: String?
    var clipSeconds: Double = 2
    var showsPrompt = true

    /// nil when there's no honest indicator to draw — see `MomentProgress`.
    private var progress: MomentProgress? {
        MomentProgress(day: day, momentCount: momentCount)
    }

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

    /// Only ever read while recording — a state read-out, not a sticker.
    private var modeText: String {
        "REC 00:\(String(format: "%02d", Int(clipSeconds)))"
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
                    // Top-right, because that's the corner the film's own
                    // timestamp pill lands in (`addTimestampPill`).
                    HStack(alignment: .top, spacing: 8 * scale) {
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

                    VStack(spacing: 10 * scale) {
                        progressBars(scale: scale)
                        momentPill(scale: scale)
                    }
                    .frame(maxWidth: .infinity)
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

    /// One segment per moment in the story, the one you're filming lit.
    ///
    /// The segments share the row equally, so a five-moment story reads as
    /// fifths — the drawing is the count. There is no printed "MOMENT 3 / 5"
    /// any more; the bars carry it, and VoiceOver gets the sentence.
    @ViewBuilder
    private func progressBars(scale: CGFloat) -> some View {
        if let progress {
            let barHeight = max(3, 5 * scale)
            HStack(spacing: 7 * scale) {
                ForEach(0..<progress.count, id: \.self) { index in
                    Capsule()
                        .fill(.white.opacity(progress.isActive(index) ? 1 : 0.42))
                        .frame(height: barHeight)
                }
            }
            .frame(maxWidth: min(CGFloat(progress.count) * 30, 190) * scale)
            .accessibilityElement()
            .accessibilityLabel(Strings.momentPosition(progress.position, of: progress.count))
        }
    }

    /// The moment's name, drawn where and how the film draws it: a dark capsule
    /// across the bottom center. `VideoStitcher.addCaption` burns the same
    /// string in at `renderSize.height * 0.075`.
    @ViewBuilder
    private func momentPill(scale: CGFloat) -> some View {
        if showsPrompt, let momentTitle, !momentTitle.isEmpty {
            Text(momentTitle)
                .font(.system(size: 17 * scale, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .allowsTightening(true)
                .padding(.horizontal, 16 * scale)
                .padding(.vertical, 8 * scale)
                .background(.black.opacity(0.45), in: Capsule())
        }
    }
}

/// The lens picker: 0.5x / 1x / 2x, and a way past them.
///
/// Every value here is a display value (see `CameraZoom`), never a
/// `videoZoomFactor`. Which presets arrive is the recorder's decision — a
/// front camera has no ultra-wide, so it sends two chips instead of three.
///
/// It sits in the control bar under the picture rather than on top of it, the
/// way the system camera does: the bottom of the frame is already spoken for
/// by the moment's name and the story's progress bars, and both of those are
/// promises about the export that a row of chips must not cover.
struct ZoomControlRow: View {
    let presets: [CGFloat]
    let capabilities: CameraZoom
    let tint: Color
    /// Writes go straight to the lens — the setter is `ClipRecorder.setZoom`,
    /// which clamps, so this row never has to check a value before sending it.
    @Binding var zoom: CGFloat
    /// Whether the fine slider has replaced the chips.
    @Binding var showsSlider: Bool

    /// Whether the zoom is somewhere the chips don't name — after a pinch, or
    /// after the slider.
    private var isOffPreset: Bool {
        !presets.contains { CameraZoom.isSame($0, zoom) }
    }

    var body: some View {
        Group {
            if showsSlider {
                sliderRow
            } else {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { chip($0) }
                    customChip
                }
            }
        }
        // Four capsules of two or three characters each have to fit the width
        // of the narrowest phone this app runs on, and at accessibility sizes
        // they stop fitting. Capped here rather than left to shrink the
        // picture above it or slide off the screen; VoiceOver reads the
        // accessibility labels at full size regardless of the drawn text.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func chip(_ preset: CGFloat) -> some View {
        let selected = CameraZoom.isSame(zoom, preset)
        return Button {
            zoom = preset
        } label: {
            Text(CameraZoom.label(preset))
                .font(.caption.weight(.heavy))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(minWidth: 44)
                .background {
                    Capsule().fill(selected ? AnyShapeStyle(tint) : AnyShapeStyle(Color(.systemGray6)))
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.zoomTo(CameraZoom.label(preset)))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Reads "自定义" until the zoom is somewhere the chips don't name, and
    /// then reads the number it actually is — so a pinch to 1.8x has
    /// somewhere to show up, and tapping it opens the slider already there.
    private var customChip: some View {
        Button {
            showsSlider = true
        } label: {
            Text(isOffPreset ? CameraZoom.label(zoom) : Strings.customZoom)
                .font(.caption.weight(.heavy))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(isOffPreset ? Color.white : Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(minWidth: 44)
                .background {
                    Capsule().fill(isOffPreset ? AnyShapeStyle(tint) : AnyShapeStyle(Color(.systemGray6)))
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.customZoom)
        .accessibilityValue(CameraZoom.label(zoom))
    }

    private var sliderRow: some View {
        HStack(spacing: 10) {
            Button {
                showsSlider = false
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.primary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color(.systemGray6)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Strings.closeCustomZoom)

            Slider(value: $zoom, in: capabilities.minDisplay...capabilities.maxDisplay)
                .tint(tint)
                .accessibilityLabel(Strings.zoomSlider)
                .accessibilityValue(CameraZoom.label(zoom))

            Text(CameraZoom.label(zoom))
                .font(.caption.weight(.heavy))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(.primary)
                // Room for the widest label the ceiling allows, so the slider
                // doesn't shuffle sideways as the number grows a digit.
                .frame(minWidth: 44, alignment: .trailing)
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
                .foregroundStyle(Color.oneDayBrand)
                .frame(width: 30, height: 30)
                .background(Color.oneDayBrand.opacity(0.12), in: Circle())

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
        .overlay(Capsule().stroke(Color.oneDayBrand.opacity(0.16), lineWidth: 1))
    }
}
