import AVFoundation
import SwiftUI

struct PermissionPrimerView: View {
    let onDone: () -> Void

    @State private var asking = false

    static var isNeeded: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined
    }

    var body: some View {
        ZStack {
            OneDayCanvas(seed: 3)
            VStack(spacing: 0) {
                Spacer()
                VStack(alignment: .leading, spacing: 28) {
                    row(systemImage: "camera.fill", text: Strings.permissionCamera)
                    row(systemImage: "bell.fill", text: Strings.permissionNotifications)
                }
                Spacer()
                Button {
                    asking = true
                    Task {
                        _ = await AVCaptureDevice.requestAccess(for: .video)
                        _ = await NotificationPermissionService.requestAuthorization()
                        onDone()
                    }
                } label: {
                    Text(Strings.ok)
                }
                .buttonStyle(.primaryAction)
                .disabled(asking)
                .accessibilityIdentifier("permission-ok")
                .padding(.horizontal, 28)
                .padding(.bottom, 32)
            }
        }
    }

    private func row(systemImage: String, text: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(OneDay.brandText)
                .frame(width: 40)
            Text(text)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(OneDay.ink)
        }
    }
}
