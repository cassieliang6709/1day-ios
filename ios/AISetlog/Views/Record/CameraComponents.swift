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

/// The camera's round glass buttons — close, flip, frame — and its glass
/// capsules, all one material.
///
/// Dark glass with white glyphs in both appearances. They used to be a 92%
/// white disc with no foreground set, so in dark mode the glyph inherited the
/// system's white and sat on a white disc at about 1.3:1. Dark glass reads over
/// a bright frame and a night shot alike, which is the same reasoning
/// `ZoomControlRow` already follows. Pinned to `.dark` so the material doesn't
/// flip to near-white in light mode.
///
/// Local to the camera on purpose: a shared over-video style is being added to
/// the design system, and when it lands these should move onto it rather than
/// grow a second copy there.
struct CameraGlass: ViewModifier {
    enum Shape { case circle, capsule }
    var shape: Shape = .circle
    var diameter: CGFloat = 38

    func body(content: Content) -> some View {
        switch shape {
        case .circle:
            content
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: diameter, height: diameter)
                .background(.black.opacity(0.32), in: Circle())
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1))
                .environment(\.colorScheme, .dark)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                // Drawn at 38, hit at 44: the HIG minimum, without the disc
                // getting any bigger next to the shutter.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        case .capsule:
            content
                .foregroundStyle(.white)
                .background(.black.opacity(0.32), in: Capsule())
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1))
                .environment(\.colorScheme, .dark)
        }
    }
}

extension View {
    func cameraGlass(_ shape: CameraGlass.Shape = .circle, diameter: CGFloat = 38) -> some View {
        modifier(CameraGlass(shape: shape, diameter: diameter))
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
    /// The camera picked in the viewfinder; draws its frame over the picture.
    var cameraStyle: CameraStyle = .standard
    /// Off when a camera prints its own date — on the live picture, or already
    /// baked into the take under review.
    var showsDate = true
    @ViewBuilder var content: Content

    private var tint: Color { Identity.tint(for: name) }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                content
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                CameraStyleOverlay(style: cameraStyle, date: timestamp)
                MomentStampOverlay(
                    momentTitle: momentTitle,
                    day: day,
                    momentCount: momentCount,
                    mode: mode,
                    timestamp: timestamp,
                    overlayText: overlayText,
                    clipSeconds: clipSeconds,
                    showsPrompt: showsPrompt,
                    showsDate: showsDate && cameraStyle == .standard
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
    /// Off under a camera that prints its own date (`CameraStyle`).
    var showsDate = true

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
    ///
    /// Just "REC". It used to print the take's *cap* as "REC 00:02", which
    /// never moved and so read as a frozen clock; the seconds that matter are
    /// counting down in the ring under the picture.
    private var modeText: String { "REC" }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let scale = min(max(min(size.width / 360, size.height / 570), 0.62), 1)
            let edgeInset = max(16, 28 * scale)

            ZStack {
                // There for the white date; under a camera's own frame it only
                // greyed the frame, which the film doesn't do.
                LinearGradient(
                    colors: [.black.opacity(0.22), .clear, .black.opacity(0.34)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .opacity(showsDate ? 1 : 0)

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
                    .opacity(showsDate ? 1 : 0)

                    Spacer(minLength: 8 * scale)

                    VStack(spacing: 10 * scale) {
                        progressBars(scale: scale)
                        momentPill(scale: scale)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(edgeInset)
                }

                // Top centre, between the timer chip and the date, rather than
                // on the middle of the picture: dead centre is where the face
                // and the caption go, and a red pill there sat on both.
                if mode == .recording {
                    HStack(spacing: 5 * scale) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8 * scale))
                            .foregroundStyle(.red)
                            // The one moving thing in the stamp, so "it is
                            // filming" doesn't depend on reading anything.
                            .symbolEffect(.pulse, options: .repeating)
                        Text(modeText)
                            .font(.system(size: 12 * scale, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10 * scale)
                    .padding(.vertical, 6 * scale)
                    .background(.black.opacity(0.45), in: Capsule())
                    .position(x: size.width * 0.5, y: edgeInset + 11 * scale)
                    .accessibilityHidden(true)
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
/// It floats over the picture, above the burn-in block.
///
/// The bottom of the frame is spoken for by the moment's name and the story's
/// progress bars, and both of those are promises about the export — a control
/// must not cover them. That ruled out a floating picker for one round; what
/// makes it work is sitting *above* that block rather than over it, which is
/// what `RecordClipView.zoomControls` positions it to do. The reward is the
/// whole control bar's height going back to the viewfinder: the picture is the
/// screen, which is the Apple lesson that matters here.
///
/// On glass over video rather than on the app canvas, so the styling is dark
/// and self-contained — an `inkSoft` number is invisible over a night shot.
///
/// One ticked capsule as of 1.3, replacing four 64×34 chips and a word-width
/// 「自定义」 — 260pt of chrome under a picture that wanted the room.
///
/// The ticks are not decoration. The row had a horizontal drag before this and
/// nothing said so, so nobody used it: a row of discrete buttons reads as
/// buttons, and a person who wants 1.4x pinches the picture instead. Marks
/// between the numbers is how the system camera says "this is continuous", and
/// it is the cheapest possible signal — no label, no hint, no onboarding.
///
/// Three ways to the same value, in the order they cost: tap a number to jump;
/// drag anywhere along the capsule for anything in between; tap the number you
/// are already on for the fine slider. There is no separate 「自定义」 button —
/// off-preset, the pinched value takes its own slot, already selected, so 1.8x
/// has somewhere to show up and somewhere to be adjusted from.
struct ZoomControlRow: View {
    let presets: [CGFloat]
    let capabilities: CameraZoom
    let tint: Color
    /// Writes go straight to the lens — the setter is `ClipRecorder.setZoom`,
    /// which clamps, so this row never has to check a value before sending it.
    @Binding var zoom: CGFloat
    /// Whether the fine slider has replaced the chips.
    @Binding var showsSlider: Bool

    /// The zoom the current drag began at. Held for the length of the gesture
    /// so the mapping is relative to where your finger went down rather than
    /// to wherever the lens happens to be mid-drag.
    @State private var dragStartZoom: CGFloat?

    /// Whether the zoom is somewhere the chips don't name — after a pinch, or
    /// after the slider.
    private var isOffPreset: Bool {
        !presets.contains { CameraZoom.isSame($0, zoom) }
    }

    /// The height of one number on the track, and therefore of the control.
    /// Apple's lens picker is about this; the previous 36pt circles plus their
    /// own row padding were the thing eating the picture's height.
    private static let pill: CGFloat = 30

    var body: some View {
        Group {
            if showsSlider {
                sliderRow
            } else {
                track
            }
        }
        // The row has to fit the width of the narrowest phone this app runs on,
        // and at accessibility sizes the numbers stop fitting their circles.
        // Capped here rather than left to shrink the picture above it or slide
        // off the screen; VoiceOver reads the accessibility labels at full size
        // regardless of the drawn text.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    /// The capsule: numbers with tick marks between them, and a drag across
    /// the whole thing.
    private var track: some View {
        HStack(spacing: 0) {
            ForEach(Array(presets.enumerated()), id: \.element) { index, preset in
                if index > 0 { ticks }
                chip(preset)
            }
            // Only when the zoom is somewhere the presets don't name. On-preset
            // there is nothing for it to say, and the number that *is* selected
            // already opens the slider.
            if isOffPreset {
                ticks
                pinchedChip
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        // Its own dark glass, not `.regularMaterial`: the material picks up the
        // system appearance and turns near-white in light mode, which over a
        // bright frame is a white bar on a white picture.
        .background(.black.opacity(0.28), in: Capsule())
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1))
        // The whole capsule is the control. `highPriorityGesture` so the drag
        // wins over the buttons inside it — a tap still gets through, because a
        // `DragGesture` with a minimum distance does not fire on one.
        .highPriorityGesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in
                    let start = dragStartZoom ?? zoom
                    dragStartZoom = start
                    zoom = CameraZoom.zoom(
                        draggedBy: value.translation.width, from: start)
                }
                .onEnded { _ in dragStartZoom = nil })
        .accessibilityElement(children: .contain)
    }

    /// Five marks, the middle one taller. Purely the "you can drag this" sign;
    /// they are not scaled to the range and deliberately do not claim to be.
    private var ticks: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(i == 2 ? 0.85 : 0.45))
                    .frame(width: 1.5, height: i == 2 ? 11 : 7)
            }
        }
        .padding(.horizontal, 5)
        .accessibilityHidden(true)
    }

    /// One lens. Tapping the one you are already on opens the fine slider —
    /// which is why this is a single button rather than a picker: the second
    /// tap means something different from the first.
    private func chip(_ preset: CGFloat) -> some View {
        let selected = CameraZoom.isSame(zoom, preset)
        return Button {
            if selected {
                showsSlider = true
            } else {
                zoom = preset
            }
        } label: {
            dotLabel(CameraZoom.label(preset), selected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            selected ? Strings.customZoom : Strings.zoomTo(CameraZoom.label(preset)))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Where a pinch lands. Always drawn selected, because it only exists while
    /// it is the current zoom, and tapping it opens the slider at that value.
    private var pinchedChip: some View {
        Button {
            showsSlider = true
        } label: {
            dotLabel(CameraZoom.label(zoom), selected: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.customZoom)
        .accessibilityValue(CameraZoom.label(zoom))
    }

    /// One number on the track. A pill rather than a circle: it lives inside a
    /// capsule now, and a circle inside a capsule is a box inside a box.
    ///
    /// The selected one is the only filled thing in the control, which is what
    /// makes the current lens readable at a glance while your eye is on the
    /// picture rather than on this.
    private func dotLabel(_ text: String, selected: Bool) -> some View {
        Text(text)
            .font(.system(size: 12.5, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            // "9.9x" needs the last of this at accessibility sizes; VoiceOver
            // reads the full label either way.
            .minimumScaleFactor(0.62)
            // White at 82% rather than `inkSoft`: this sits on video now, and
            // a blue-grey number over a dark frame cannot be read at all.
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.82))
            .shadow(color: .black.opacity(selected ? 0 : 0.35), radius: 3)
            .padding(.horizontal, 10)
            .frame(minWidth: 34)
            .frame(height: Self.pill)
            .background {
                if selected {
                    Capsule().fill(tint)
                } else {
                    Capsule().fill(.black.opacity(0.28))
                }
            }
            .contentShape(Capsule())
    }

    private var sliderRow: some View {
        HStack(spacing: 10) {
            Button {
                showsSlider = false
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(.black.opacity(0.35)))
                    // Hit area to 44 without growing the disc; the row's
                    // vertical padding gives the extra height back.
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
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
                .foregroundStyle(.white)
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
                .foregroundStyle(OneDay.brandText)
                .frame(width: 30, height: 30)
                .background(Color.oneDayBrand.opacity(0.12), in: Circle())

            // Fixed dark ink: the capsule behind this is a fixed near-white, so
            // the system's adaptive `.primary`/`.secondary` turned white-on-
            // white in dark mode.
            TextField(
                "",
                text: $text,
                prompt: Text(Strings.writeOnMoment)
                    .foregroundStyle(Color.black.opacity(0.45))
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.black.opacity(0.86))
            .tint(Color.oneDayBrand)
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
                        .foregroundStyle(Color.black.opacity(0.4))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, -10)
                .accessibilityLabel(Strings.deleteCaptionAction)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.86), in: Capsule())
        .overlay(Capsule().stroke(Color.oneDayBrand.opacity(0.16), lineWidth: 1))
    }
}

/// The dual-camera button's icon: a big frame with a small one overlapping
/// its top-right corner — two pictures, one on the other.
///
/// Drawn rather than an SF Symbol: `rectangle.inset.topright.filled` is a
/// solid slab, and white on the dark glass it read as a grey blob with no
/// shape in it. Outlines keep both rectangles visible; on, the small one fills
/// with the brand colour so the state reads at a glance.
struct DualCameraGlyph: View {
    var isOn: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .strokeBorder(.white, lineWidth: 1.8)
                .frame(width: 15, height: 20)
                .frame(width: 20, height: 24, alignment: .bottomLeading)
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(isOn ? Color.oneDayBrand : Color.black.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .strokeBorder(.white, lineWidth: 1.6))
                .frame(width: 10, height: 13)
        }
        .frame(width: 20, height: 24)
        .accessibilityHidden(true)
    }
}

/// The viewfinder in dual-camera mode: one picture full frame, the other in
/// a white-bordered inset at `inset` (normalized, see `PiPInsetLayout`) — the
/// same box and border `PiPComposer` burns into the file, so the preview
/// matches the composed clip. `swapped` trades which camera is which without
/// recreating either preview view. With `showsInset` off, only the primary is
/// drawn.
///
/// The inset can be dragged anywhere and pinched between 22% and 45% of the
/// frame's width while `isEditable`; a tap on it calls `onTapInset` (the
/// camera swaps which picture is big). The gesture's running state stays in
/// here and only the finished rect goes out through `onInsetChange`, so a
/// drag doesn't write to UserDefaults on every frame.
struct DualCameraStage<Primary: View, Secondary: View>: View {
    var showsInset: Bool
    var swapped: Bool
    var inset: CGRect = PiPInsetLayout.defaultRect()
    var isEditable = true
    var onInsetChange: (CGRect) -> Void = { _ in }
    var onTapInset: () -> Void = {}
    @ViewBuilder var primary: Primary
    @ViewBuilder var secondary: Secondary

    /// A drag and a pinch on the inset, in flight. One value for both so the
    /// pair commits once, when the last finger lifts — committed separately,
    /// the second to end re-applied the first on top of the rect it had
    /// already written.
    struct Adjustment: Equatable {
        var translation: CGSize = .zero
        var scale: CGFloat = 1
    }
    /// What is drawn mid-gesture; resets on its own if the gesture is
    /// cancelled.
    @GestureState private var live = Adjustment()
    /// The last value seen, for `onEnded` — by then `live` has already reset.
    @State private var lastAdjustment = Adjustment()

    var body: some View {
        GeometryReader { proxy in
            stage(in: proxy.size)
        }
    }

    private func stage(in size: CGSize) -> some View {
        let full = CGRect(origin: .zero, size: size)
        let rect = liveRect(in: size)
        let box = PiPInsetLayout.pictureBox(rect, in: size)
        let primaryIsInset = showsInset && swapped
        return ZStack(alignment: .topLeading) {
            framed(primary, in: primaryIsInset ? box : full,
                   isInset: primaryIsInset, canvas: size)
                .zIndex(primaryIsInset ? 1 : 0)
            if showsInset {
                framed(secondary, in: swapped ? full : box,
                       isInset: !swapped, canvas: size)
                    .zIndex(swapped ? 0 : 1)
            }
        }
        .coordinateSpace(.named(Self.stageSpace))
    }

    /// The drag is measured in the stage's space, not the inset's own. The
    /// inset moves under the finger, so in its local space every move
    /// shrank the next reading by the same amount: the inset was pulled
    /// back, the translation grew again, and it shook between the two.
    private static var stageSpace: String { "DualCameraStage" }

    /// The committed rect with the gesture in flight applied on top.
    private func liveRect(in size: CGSize) -> CGRect {
        applying(live, in: size)
    }

    private func applying(_ adjustment: Adjustment, in size: CGSize) -> CGRect {
        PiPInsetLayout.adjusted(
            inset, scale: adjustment.scale, translation: adjustment.translation, in: size)
    }

    /// The decoration is always applied and only switched by `isInset`, so a
    /// swap changes values rather than view structure — the camera preview
    /// layers underneath are never torn down.
    private func framed(
        _ view: some View, in rect: CGRect, isInset: Bool, canvas: CGSize
    ) -> some View {
        let border = PiPInsetLayout.border(in: canvas)
        let radius = PiPInsetLayout.cornerRadius(in: canvas)
        let innerRadius = max(radius - border, 0)
        return view
            .frame(width: rect.width, height: rect.height)
            .clipShape(RoundedRectangle(cornerRadius: isInset ? innerRadius : 0))
            .background {
                RoundedRectangle(cornerRadius: radius, style: .circular)
                    .fill(.white)
                    .padding(-border)
                    .shadow(color: .black.opacity(0.28), radius: border * 2, y: border * 0.75)
                    .opacity(isInset ? 1 : 0)
            }
            .contentShape(Rectangle())
            .gesture(insetGestures(canvas: canvas),
                     including: isInset && isEditable ? .all : .subviews)
            .offset(x: rect.minX, y: rect.minY)
    }

    private func insetGestures(canvas: CGSize) -> some Gesture {
        let adjust = DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.stageSpace))
            .simultaneously(with: MagnifyGesture(minimumScaleDelta: 0.01))
            .updating($live) { value, state, _ in
                state = Adjustment(
                    translation: value.first?.translation ?? state.translation,
                    scale: value.second?.magnification ?? state.scale)
            }
            .onChanged { value in
                lastAdjustment = Adjustment(
                    translation: value.first?.translation ?? lastAdjustment.translation,
                    scale: value.second?.magnification ?? lastAdjustment.scale)
            }
            .onEnded { _ in
                onInsetChange(applying(lastAdjustment, in: canvas))
                lastAdjustment = Adjustment()
            }
        let tap = TapGesture().onEnded { onTapInset() }
        return adjust.exclusively(before: tap)
    }
}

#if DEBUG && targetEnvironment(simulator)
/// What the viewfinder shows under `-simulatedCamera YES`: a moving scene, so
/// screenshots of the camera have something in the frame and a still frame is
/// distinguishable from a frozen one. See `ClipRecorder.isSimulated`.
struct SimulatedCameraPreview: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(hue: 0.58 + 0.04 * sin(t / 3), saturation: 0.45, brightness: 0.95),
                            Color(hue: 0.08, saturation: 0.35, brightness: 0.98),
                        ],
                        startPoint: .top, endPoint: .bottom)
                    Circle()
                        .fill(Color(hue: 0.12, saturation: 0.6, brightness: 1))
                        .frame(width: size.width * 0.28)
                        .position(
                            x: size.width * (0.5 + 0.3 * sin(t / 2)),
                            y: size.height * (0.3 + 0.05 * cos(t / 2)))
                    RoundedRectangle(cornerRadius: 40, style: .continuous)
                        .fill(Color(hue: 0.35, saturation: 0.35, brightness: 0.7))
                        .frame(width: size.width * 1.4, height: size.height * 0.45)
                        .position(x: size.width * 0.5, y: size.height * 0.95)
                    Text("SIMULATOR")
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                        .position(x: size.width * 0.5, y: size.height * 0.62)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
#endif
