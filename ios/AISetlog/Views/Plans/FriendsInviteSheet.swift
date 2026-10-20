import SwiftUI
import UIKit

/// 朋友's 邀请朋友一起拍, once there is a room to invite to.
///
/// One room: its code, straight away. Two or more: a list to pick from, with
/// 新建房间 at the end for the case where none of them is the right one.
/// Picking a room hands it back (`onPick`) so the screen behind can open it,
/// then this sheet shows that room's code.
struct FriendsInviteSheet: View {
    let rooms: [Challenge]
    let memberCount: (Challenge) -> Int
    let onPick: (Challenge) -> Void
    let onNewRoom: () -> Void

    @State private var selectedID: UUID?

    init(
        rooms: [Challenge],
        initialRoomID: UUID? = nil,
        memberCount: @escaping (Challenge) -> Int,
        onPick: @escaping (Challenge) -> Void,
        onNewRoom: @escaping () -> Void
    ) {
        self.rooms = rooms
        self.memberCount = memberCount
        self.onPick = onPick
        self.onNewRoom = onNewRoom
        _selectedID = State(initialValue: initialRoomID)
    }

    private var selected: Challenge? {
        rooms.first { $0.id == selectedID }
    }

    var body: some View {
        ZStack {
            OneDay.surface.ignoresSafeArea()
            if let selected {
                RoomInviteCodeCard(challenge: selected, members: memberCount(selected))
            } else {
                roomList
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var roomList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(Strings.pickRoomTitle)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                    .padding(.bottom, 6)
                ForEach(rooms) { room in
                    Button { pick(room) } label: { roomRow(room) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("friends-invite-room-\(room.roomCode ?? "")")
                }
                Button(action: onNewRoom) { newRoomRow }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("friends-invite-new-room")
            }
            .padding(24)
        }
        .scrollIndicators(.hidden)
    }

    private func pick(_ room: Challenge) {
        selectedID = room.id
        onPick(room)
    }

    private func roomRow(_ room: Challenge) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ChallengePresenter(challenge: room).displayTitle)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                    .lineLimit(1)
                Text(rowCaption(room))
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(OneDay.inkFaint)
        }
        .padding(14)
        .background(OneDay.surfaceSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func rowCaption(_ room: Challenge) -> String {
        let code = room.roomCode.map(Strings.inviteCodeLine) ?? ""
        return "\(Strings.memberCount(memberCount(room))) · \(code)"
    }

    private var newRoomRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .heavy))
            Text(Strings.newRoomRow)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
            Spacer()
        }
        .foregroundStyle(OneDay.brandText)
        .padding(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.oneDayBrand.opacity(0.35),
                              style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }
}

/// A room's invite code, large, with copy and the system share sheet.
/// Also used by the debug test room in Settings.
struct RoomInviteCodeCard: View {
    let challenge: Challenge
    var members: Int? = nil

    @State private var copied = false
    /// Optional because this card is also shown from places (Settings' debug
    /// test room, previews) that may not inject the account; the invite card
    /// then simply says "来 1Day 一起拍" instead of naming you.
    @Environment(AccountStore.self) private var account: AccountStore?

    private var code: String { challenge.roomCode ?? "" }

    var body: some View {
        VStack(spacing: 16) {
            Text(Strings.inviteSheetTitle)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(OneDay.ink)
            Text(subtitle)
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .foregroundStyle(OneDay.inkSoft)
            codeText
            Text(Strings.inviteSheetBody)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(OneDay.inkSoft)
                .multilineTextAlignment(.center)
            buttons
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    private var subtitle: String {
        let title = ChallengePresenter(challenge: challenge).displayTitle
        guard let members else { return title }
        return "\(title) · \(Strings.memberCount(members))"
    }

    private var codeText: some View {
        Text(code)
            .font(.system(size: 40, weight: .heavy, design: .monospaced))
            .kerning(6)
            .foregroundStyle(OneDay.ink)
            .textSelection(.enabled)
            .accessibilityIdentifier("invite-code")
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            // The card image, not the text: WeChat refuses a text share
            // outright. See `RoomInviteCard.swift`.
            RoomInviteShareLink(
                content: RoomInviteCardContent(
                    challenge: challenge, inviter: account?.account?.displayName),
                message: shareText
            ) { Text(Strings.shareCode) }
                .buttonStyle(.primaryAction)
                .accessibilityIdentifier("invite-share")
            Button(copied ? Strings.codeCopied : Strings.copyCode) {
                UIPasteboard.general.string = code
                copied = true
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(OneDay.brandText)
            .accessibilityIdentifier("invite-copy-code")
        }
    }

    /// The same words the room's own 邀请 button sends.
    private var shareText: String {
        let presenter = ChallengePresenter(challenge: challenge)
        if challenge.recordedCount > 0 {
            return Strings.shareMessageCaptured(
                first: presenter.title(forSlot: 1), title: presenter.displayTitle, code: code)
        }
        return Strings.shareMessageInvite(title: presenter.displayTitle, code: code)
    }
}
