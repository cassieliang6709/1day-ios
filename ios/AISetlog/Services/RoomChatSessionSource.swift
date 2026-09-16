import Foundation
import SwiftUI

/// Explicit routing for the production room/clip chat UI. A local route never
/// falls back to live services, including for a mismatched scope or closed owner.
enum RoomChatSessionSource {
    case live
    case local(RoomChatDemoTransport)

    @MainActor
    var identity: String {
        switch self {
        case .live: return "live"
        case .local(let preview): return preview.directory.absoluteString
        }
    }

    @MainActor
    var preview: RoomChatDemoTransport? {
        if case .local(let preview) = self { return preview }
        return nil
    }

    /// Lazy dependencies keep local routing from even reading live persistence
    /// or identity. Tests exercise the default-live branch with isolated inputs.
    struct LiveDependencies {
        var directory: () -> URL
        var transport: () -> any RoomChatTransport
        var identityLease: (RoomChatScope) -> () -> Bool

        @MainActor static var production: Self {
            Self(directory: {
                FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("RoomChat", isDirectory: true)
            }, transport: { CloudRoomChatTransport() }, identityLease: { scope in
                let revision = AccountStore.identityRevision
                return {
                    AccountStore.identityRevision == revision && AccountStore.persistedUserID == scope.accountID
                }
            })
        }
    }

    @MainActor
    func makeSession(scope: RoomChatScope, live: LiveDependencies? = nil) -> RoomChatSession {
        switch self {
        case .live:
            let live = live ?? .production
            return RoomChatSession(scope: scope, directory: live.directory(), transport: live.transport(),
                                   identityIsCurrent: live.identityLease(scope))
        case .local(let preview):
            return RoomChatSession(scope: scope, directory: preview.directory, transport: preview,
                                   identityIsCurrent: { !preview.isClosed && preview.scope == scope })
        }
    }
}

private struct RoomChatSessionSourceKey: EnvironmentKey {
    static let defaultValue: RoomChatSessionSource = .live
}

extension EnvironmentValues {
    var roomChatSessionSource: RoomChatSessionSource {
        get { self[RoomChatSessionSourceKey.self] }
        set { self[RoomChatSessionSourceKey.self] = newValue }
    }
}
