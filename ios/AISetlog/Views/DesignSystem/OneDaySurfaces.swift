import SwiftUI


struct OneDayCanvas: View {
    var seed: Int = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        OneDay.canvas
            .overlay {
                ZStack {
                    bloom(.oneDayMist, dark: .oneDayBrand,
                          size: 320, x: -140, y: -280, opacity: 0.9, darkOpacity: 0.16)
                    bloom(.oneDaySky, dark: .oneDayCyan,
                          size: 260, x: 170, y: -180, opacity: 0.28, darkOpacity: 0.10)
                    bloom(.oneDayLavender, dark: .oneDayLavender,
                          size: 300, x: 160, y: 380, opacity: 0.16, darkOpacity: 0.10)
                    bloom(.oneDayMint, dark: .oneDayMint,
                          size: 200, x: -160, y: 460, opacity: 0.14, darkOpacity: 0.09)
                }
                .allowsHitTesting(false)
            }
            .ignoresSafeArea()
    }

    private func bloom(
        _ color: Color,
        dark darkColor: Color,
        size: CGFloat,
        x: CGFloat,
        y: CGFloat,
        opacity: Double,
        darkOpacity: Double
    ) -> some View {
        let isDark = colorScheme == .dark
        return Circle()
            .fill((isDark ? darkColor : color).opacity(isDark ? darkOpacity : opacity))
            .frame(width: size, height: size)
            .blur(radius: 48)
            .offset(x: x + CGFloat(seed % 3) * 18, y: y - CGFloat(seed % 2) * 24)
    }
}

struct GlassCard<Content: View>: View {
    var radius: CGFloat = OneDay.Radius.card
    var padding: CGFloat = 18
    var tint: Color?
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(radius: radius, tint: tint)
    }
}

extension View {
    func glassSurface(
        radius: CGFloat = OneDay.Radius.card,
        tint: Color? = nil
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background {
            shape
                .fill(OneDay.surface)
                .overlay {
                    if let tint {
                        shape.fill(tint.opacity(0.10))
                    }
                }
        }
        .overlay {
            shape.strokeBorder(OneDay.hairline, lineWidth: 1)
        }
        .oneDaySoftShadow()
    }
}


struct OverVideoGlass<S: InsettableShape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            .foregroundStyle(.white)
            .background(.black.opacity(0.28), in: shape)
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(.white.opacity(0.22), lineWidth: 1))
            .environment(\.colorScheme, .dark)
    }
}

extension View {
    func overVideoControl<S: InsettableShape>(in shape: S) -> some View {
        modifier(OverVideoGlass(shape: shape))
    }

    func overVideoControl() -> some View {
        modifier(OverVideoGlass(shape: Capsule()))
    }
}


struct OneDayBrandLogo: View {
    var width: CGFloat = 96

    var body: some View {
        Image(AppSkin.lockupImageName)
            .resizable()
            .scaledToFit()
            .frame(width: width, height: width * 0.49)
            .accessibilityLabel("1Day")
    }
}

struct OneDayBuddy: View {
    var size: CGFloat = 44
    var isWorking = false

    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AvatarDot(name: nil, size: size)
            .scaleEffect(breathe ? 0.94 : 1)
            .animation(OneDay.Motion.reduced(OneDay.Motion.pulse, if: reduceMotion), value: breathe)
            .onAppear { breathe = isWorking && !reduceMotion }
            .onChange(of: reduceMotion) { _, reduced in
                breathe = isWorking && !reduced
            }
    }
}

extension View {
    func clipBox(height: CGFloat) -> some View {
        Color.clear
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .overlay { self }
            .clipped()
    }
}

struct EmptyFrame<Content: View>: View {
    var radius: CGFloat = OneDay.Radius.chip
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .background(OneDay.surfaceSoft.opacity(0.45), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        Color.oneDaySky.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            }
    }
}
