import SwiftUI

/// Keep the action on the same horizontal axis as the idle shutter.
/// Instruction length (including translations and Dynamic Type) must not move it.
struct CenteredCaptureControl<Action: View>: View {
    let instruction: String
    @ViewBuilder var action: () -> Action

    var body: some View {
        VStack(spacing: 5) {
            action()
            Text(instruction)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}
