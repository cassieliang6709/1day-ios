import SwiftUI

/// Brand and identity sub-components of `HomeView`: the app logo mark, the
/// breathing start button, and the avatar dots/stacks. List cards live in
/// `HomeCards.swift`; the join sheet in `JoinInviteSheet.swift`.

struct OneDayLogoMark: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            ZStack {
                RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.oneDayBlue, Color.oneDayCyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.oneDayBlue.opacity(0.22), radius: side * 0.08, y: side * 0.05)

                Text("1D")
                    .font(.system(size: side * 0.34, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Circle()
                    .stroke(.white.opacity(0.82), lineWidth: max(side * 0.045, 2))
                    .frame(width: side * 0.68, height: side * 0.68)
                    .overlay(alignment: .topTrailing) {
                        Circle()
                            .fill(.white)
                            .frame(width: side * 0.13, height: side * 0.13)
                            .offset(x: side * 0.02, y: -side * 0.02)
                    }
            }
        }
    }
}

/// The "Start today" button with a slow breathing glow, so the home screen's
/// single most important action has some life to it.
struct BreathingStartButton: View {
    let action: () -> Void
    @State private var breathe = false

    var body: some View {
        Button(action: action) {
            Text(Strings.startToday)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [Color.oneDayBlue, Color.oneDayCyan],
                        startPoint: .leading, endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
                .shadow(color: Color.oneDayBlue.opacity(breathe ? 0.45 : 0.16), radius: breathe ? 22 : 8, y: 6)
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }
}

/// A small colored initials circle for a person's identity — reuses
/// `Identity` so the color always matches `MemberChip` elsewhere in the app.
struct AvatarDot: View {
    let name: String?
    var size: CGFloat = 34

    var body: some View {
        Text(Identity.initial(for: name))
            .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Identity.tint(for: name).gradient, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
    }
}

/// The "+N" overflow bubble at the end of an `AvatarStack`.
private struct AvatarOverflowDot: View {
    let count: Int
    var size: CGFloat = 34

    var body: some View {
        Text("+\(count)")
            .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
            .foregroundStyle(Color.oneDayNavy)
            .frame(width: size, height: size)
            .background(Color.oneDayMist, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
    }
}

/// Overlapping identity circles for a room's members, capped with a "+N" bubble.
struct AvatarStack: View {
    let names: [String]
    var maxShown: Int = 3

    var body: some View {
        HStack(spacing: -10) {
            ForEach(Array(names.prefix(maxShown).enumerated()), id: \.offset) { _, name in
                AvatarDot(name: name)
            }
            if names.count > maxShown {
                AvatarOverflowDot(count: names.count - maxShown)
            }
        }
    }
}
