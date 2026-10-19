import SwiftUI

/// Keep the action on the same horizontal axis as the idle shutter.
/// Instruction length (including translations and Dynamic Type) must not move it.
struct CenteredCaptureControl<Action: View>: View {
    /// The line under the control. Nil draws none — the camera's shutter has
    /// gone without one since 1.5.
    let instruction: String?
    @ViewBuilder var action: () -> Action

    var body: some View {
        VStack(spacing: 5) {
            action()
            if let instruction {
                Text(instruction)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
