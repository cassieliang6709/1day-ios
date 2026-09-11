import Foundation

/// Non-storage side effects triggered by changes to a store. Local previews must
/// explicitly supply .isolated as well as isolated storage and room transport.
struct ChallengeStoreEffects {
    let allowsCloudRoomManagement: Bool
    var reconcileReminders: ([Challenge]) -> Void
    var reconcileSubscriptions: ([Challenge]) -> Void
    var resetNotificationPreferences: () -> Void

    static var live: ChallengeStoreEffects {
        ChallengeStoreEffects(
            allowsCloudRoomManagement: true,
            reconcileReminders: { ReminderService.reconcile(for: $0) },
            reconcileSubscriptions: { SharedActivityNotificationService.reconcileSubscriptions(for: $0) },
            resetNotificationPreferences: { NotificationPreferences.resetAll() })
    }

    static var isolated: ChallengeStoreEffects {
        ChallengeStoreEffects(
            allowsCloudRoomManagement: false,
            reconcileReminders: { _ in },
            reconcileSubscriptions: { _ in },
            resetNotificationPreferences: {})
    }
}
