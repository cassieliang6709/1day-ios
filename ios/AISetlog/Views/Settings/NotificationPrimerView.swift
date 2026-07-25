import SwiftUI

struct NotificationPrimerView: View {
    let challenges: [Challenge]

    @Environment(\.dismiss) private var dismiss
    @State private var reminderTime = Calendar.current.date(
        bySettingHour: NotificationPreferences.eveningHour,
        minute: NotificationPreferences.eveningMinute,
        second: 0,
        of: .now) ?? .now
    @State private var requesting = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "bell.badge.fill")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(Color.oneDayBlue.gradient)

            VStack(spacing: 10) {
                Text(Strings.notificationPrimerTitle)
                    .font(.title2.bold())
                Text(Strings.notificationPrimerBody)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DatePicker(
                Strings.reminderTime,
                selection: $reminderTime,
                displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))

            VStack(spacing: 12) {
                Button {
                    enableReminders()
                } label: {
                    if requesting {
                        ProgressView().tint(.white)
                    } else {
                        Text(Strings.enableEveningReminder)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.oneDayBlue)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(requesting)

                Button(Strings.notNow) {
                    NotificationPreferences.primerSeen = true
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(requesting)
            }

            Text(Strings.notificationPrimerFootnote)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(24)
        .presentationDetents([.medium])
        .interactiveDismissDisabled(requesting)
    }

    private func enableReminders() {
        requesting = true
        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        NotificationPreferences.eveningHour = components.hour ?? 20
        NotificationPreferences.eveningMinute = components.minute ?? 30
        NotificationPreferences.primerSeen = true

        Task {
            let granted = await NotificationPermissionService.requestAuthorization()
            NotificationPreferences.eveningEnabled = granted
            ReminderService.reconcile(for: challenges)
            requesting = false
            dismiss()
        }
    }
}
