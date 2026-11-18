import SwiftUI

struct LookPanel: View {
    @Binding var look: PersonalEffectParameters
    @Binding var sticky: Bool
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
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.black.opacity(0.94)))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1))
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }


    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Strings.lookTitle)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 8)
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


    private var compare: some View {
        HStack(spacing: 6) {
            Image(systemName: showingOriginal ? "eye.fill" : "eye")
                .font(.system(size: 12, weight: .bold))
            Text(Strings.lookHoldToCompare)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(showingOriginal ? Color(uiColor: UIColor(hex: 0x0F2E6B)) : .white)
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


    private var remember: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $sticky) {
                Text(Strings.lookRemember)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            .tint(Color.oneDaySky)
        }
    }
}
