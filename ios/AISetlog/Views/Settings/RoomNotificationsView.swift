import SwiftUI

/// Per-room mute switches. One row per shared room, so the list grows with the
/// number of rooms you're in — which is exactly why it isn't on the front page
/// of Settings any more, where it used to push everything below it off-screen.
struct RoomNotificationsView: View {
    @Environment(ChallengeStore.self) private var store
    let rooms: [Challenge]
    @Binding var mutedRooms: Set<String>

    /// What the row one level up says: silence is the thing worth reporting.
    static func summary(rooms: [Challenge], muted: Set<String>) -> String {
        let count = rooms.filter { $0.roomCode.map(muted.contains) ?? false }.count
        return count == 0 ? Strings.allRoomsOn : Strings.roomsMuted(count)
    }

    var body: some View {
        Form {
            Section {
                ForEach(rooms) { room in
                    Toggle(
                        ChallengePresenter(challenge: room).displayTitle,
                        isOn: binding(for: room))
                }
            } header: {
                Text(Strings.sharedRooms)
            } footer: {
                Text(Strings.sharedRoomsFooter)
            }
        }
        .navigationTitle(Strings.sharedRooms)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binding(for challenge: Challenge) -> Binding<Bool> {
        Binding {
            guard let code = challenge.roomCode else { return false }
            return !mutedRooms.contains(code)
        } set: { enabled in
            guard let code = challenge.roomCode else { return }
            NotificationPreferences.setRoom(code, muted: !enabled)
            mutedRooms = NotificationPreferences.mutedRoomCodes
            SharedActivityNotificationService.reconcileSubscriptions(
                for: store.challenges)
        }
    }
}
