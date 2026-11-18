import SwiftUI


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
    let name: String?
    let momentTitle: String?
    let day: Int
    var momentCount = 0
    let mode: MomentStampOverlay.Mode
    let timestamp: Date?
    let overlayText: String?
    let clipSeconds: Double
    var showsPrompt = true
    var aspectRatio: CGFloat? = nil
    var cameraStyle: CameraStyle = .standard
    var showsDate = true
    var turn: Double = 0
    @ViewBuilder var content: Content

    private var tint: Color { Color.oneDayBrand }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                content
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                let sideways = turn != 0
                ZStack {
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
                .frame(
                    width: sideways ? proxy.size.height : proxy.size.width,
                    height: sideways ? proxy.size.width : proxy.size.height)
                .rotationEffect(.degrees(turn))
                .frame(width: proxy.size.width, height: proxy.size.height)
                .animation(OneDay.Motion.snap, value: turn)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(tint, lineWidth: 3)
            }
            .shadow(color: tint.opacity(0.35), radius: 18, y: 8)
        }
        .aspectRatio(aspectRatio ?? 9 / 16, contentMode: .fit)
    }
}

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
    var showsDate = true

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

    private var modeText: String { "REC" }

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
                .opacity(showsDate ? 1 : 0)

                VStack {
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

                if mode == .recording {
                    HStack(spacing: 5 * scale) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8 * scale))
                            .foregroundStyle(.red)
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

struct ZoomControlRow: View {
    let presets: [CGFloat]
    let capabilities: CameraZoom
    let tint: Color
    @Binding var zoom: CGFloat
    @Binding var showsSlider: Bool

    @State private var dragStartZoom: CGFloat?

    private var isOffPreset: Bool {
        !presets.contains { CameraZoom.isSame($0, zoom) }
    }

    private static let pill: CGFloat = 30

    var body: some View {
        Group {
            if showsSlider {
                sliderRow
            } else {
                track
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private var track: some View {
        HStack(spacing: 0) {
            ForEach(Array(presets.enumerated()), id: \.element) { index, preset in
                if index > 0 { ticks }
                chip(preset)
            }
            if isOffPreset {
                ticks
                pinchedChip
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.black.opacity(0.28), in: Capsule())
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1))
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

    private func dotLabel(_ text: String, selected: Bool) -> some View {
        Text(text)
            .font(.system(size: 12.5, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.62)
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
                .frame(minWidth: 44, alignment: .trailing)
        }
    }
}

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

            TextField(
                "",
                text: $text,
                prompt: Text(Strings.addCaption)
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

struct DualCameraStage<Primary: View, Secondary: View>: View {
    var showsInset: Bool
    var swapped: Bool
    var inset: CGRect = PiPInsetLayout.defaultRect()
    var isEditable = true
    var onInsetChange: (CGRect) -> Void = { _ in }
    var onTapInset: () -> Void = {}
    @ViewBuilder var primary: Primary
    @ViewBuilder var secondary: Secondary

    struct Adjustment: Equatable {
        var translation: CGSize = .zero
        var scale: CGFloat = 1
    }
    @GestureState private var live = Adjustment()
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

    private static var stageSpace: String { "DualCameraStage" }

    private func liveRect(in size: CGSize) -> CGRect {
        applying(live, in: size)
    }

    private func applying(_ adjustment: Adjustment, in size: CGSize) -> CGRect {
        PiPInsetLayout.adjusted(
            inset, scale: adjustment.scale, translation: adjustment.translation, in: size)
    }

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
struct SimulatedCameraPreview: View {
    private var sampleFootage: URL? {
        guard UserDefaults.standard.bool(forKey: "storeShots") else { return nil }
        return Bundle.main.url(forResource: "sample-film", withExtension: "mp4")
    }

    var body: some View {
        if let sampleFootage {
            LoopingClipPlayer(url: sampleFootage, muted: true)
        } else {
            drawnScene
        }
    }

    private var drawnScene: some View {
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
