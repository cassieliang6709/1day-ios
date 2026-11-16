import SwiftUI

struct CenteredCaptureControl<Action: View>: View {
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
