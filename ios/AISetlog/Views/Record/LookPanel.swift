import SwiftUI

/// The grade, chosen while you watch it happen.
///
/// Not a sheet. A sheet would cover the one thing you're deciding about — you
/// can't pick how bright your face should be by looking at a slider. So it sits
/// on the bottom of the clip you're already watching, and the picture behind it
/// changes as you drag.
///
/// Three dials and no presets. Presets were four names for four points somebody
/// else picked, and the two rooms people film in most — a dim kitchen and a
/// bright pavement — never landed on any of them. There is no "auto", and no
/// number is shown: a figure invites you to get it right, and there is no right.
struct LookPanel: View {
    @Binding var look: PersonalEffectParameters
    @Binding var sticky: Bool
    /// Held down = show the clip as it was filmed. Bound rather than owned,
    /// because the thing that has to change is the player above this panel.
    @Binding var showingOriginal: Bool
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            dials
            compare
            remember
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 18)
        // Nearly opaque, not a tint. Glass over a bright clip let the picture
        // read straight through the panel and put whatever the video says at
        // that moment behind "A gentler look".
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.black.opacity(0.94)))
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
            // Only offered once there is something to undo, and it resets all
            // three at once: three dials to put back by hand is how people end
            // up near centre but not on it, which looks like the app is broken.
            if !look.isIdentity {
                Button(Strings.lookReset) {
                    withAnimation(OneDay.Motion.soft) { look = .none }
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.trailing, 4)
            }
            Button(Strings.done, action: onDone)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Dials

    private var dials: some View {
        VStack(spacing: 4) {
            dial(Strings.lookExposure, look.exposure) {
                PersonalEffectParameters(
                    exposure: $0, temperature: look.temperature, contrast: look.contrast)
            }
            dial(Strings.lookTemperature, look.temperature) {
                PersonalEffectParameters(
                    exposure: look.exposure, temperature: $0, contrast: look.contrast)
            }
            dial(Strings.lookContrast, look.contrast) {
                PersonalEffectParameters(
                    exposure: look.exposure, temperature: look.temperature, contrast: $0)
            }
        }
    }

    private func dial(
        _ title: String, _ value: Double,
        set: @escaping (Double) -> PersonalEffectParameters
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 54, alignment: .leading)
            ZStack {
                // A tick at centre, so "off" is somewhere your thumb can find
                // without reading anything. On a 0...1 slider off was the far
                // left, which is a different gesture from "a bit less".
                Rectangle()
                    .fill(.white.opacity(0.35))
                    .frame(width: 1, height: 10)
                Slider(
                    value: Binding(get: { value }, set: { look = set($0) }),
                    in: PersonalEffectParameters.range,
                    step: 1)
                    .tint(.white)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
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
