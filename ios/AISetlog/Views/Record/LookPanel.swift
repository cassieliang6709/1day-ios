import SwiftUI

/// The look, chosen while you watch it happen.
///
/// Not a sheet. A sheet would cover the one thing you're deciding about — you
/// can't pick how soft your face should be by looking at a slider. So it sits
/// on the bottom of the clip you're already watching, and the picture behind it
/// changes as you drag.
///
/// Everything here is either a preset or a dial. There is no "auto", and no
/// number is shown: a percentage invites you to get it right, and there is no
/// right.
struct LookPanel: View {
    @Binding var look: GentleLook
    @Binding var sticky: Bool
    /// Held down = show the clip as it was filmed. Bound rather than owned,
    /// because the thing that has to change is the player above this panel.
    @Binding var showingOriginal: Bool
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            presets
            dials
            compare
            remember
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.black.opacity(0.62)))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1))
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Strings.lookTitle)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(Strings.lookFootnote)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(Strings.done, action: onDone)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Presets

    private var presets: some View {
        HStack(spacing: 8) {
            ForEach(GentleLook.presets, id: \.key) { preset in
                let chosen = look == preset.look
                Button {
                    withAnimation(OneDay.Motion.soft) { look = preset.look }
                } label: {
                    Text(GentleLook.presetName(preset.key))
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(chosen ? OneDay.ink : .white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            Capsule().fill(chosen ? .white : .white.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Dials

    private var dials: some View {
        VStack(spacing: 4) {
            dial(Strings.lookSmoothing, look.smoothing) {
                GentleLook(smoothing: $0, brightness: look.brightness, warmth: look.warmth)
            }
            dial(Strings.lookBrightness, look.brightness) {
                GentleLook(smoothing: look.smoothing, brightness: $0, warmth: look.warmth)
            }
            dial(Strings.lookWarmth, look.warmth) {
                GentleLook(smoothing: look.smoothing, brightness: look.brightness, warmth: $0)
            }
        }
    }

    private func dial(
        _ title: String, _ value: Double, set: @escaping (Double) -> GentleLook
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 54, alignment: .leading)
            Slider(
                value: Binding(get: { value }, set: { look = set($0) }),
                in: 0...1)
                .tint(.white)
        }
    }

    // MARK: - Compare

    /// Press and hold, don't tap-to-toggle. A toggle leaves you one tap away
    /// from forgetting which one you're looking at; holding can only ever be
    /// temporary, so the thing on screen when your thumb is up is always the
    /// thing you're choosing.
    private var compare: some View {
        HStack(spacing: 6) {
            Image(systemName: showingOriginal ? "eye.fill" : "eye")
                .font(.system(size: 12, weight: .bold))
            Text(Strings.lookHoldToCompare)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(showingOriginal ? OneDay.ink : .white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(
            Capsule().fill(showingOriginal ? .white : .white.opacity(0.14)))
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !showingOriginal else { return }
                    showingOriginal = true
                }
                .onEnded { _ in showingOriginal = false })
        .opacity(look.isIdentity ? 0.35 : 1)
        .disabled(look.isIdentity)
    }

    // MARK: - Remember

    private var remember: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $sticky) {
                Text(Strings.lookRemember)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            .tint(Color.oneDaySky)
            Text(Strings.lookRememberFootnote)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
