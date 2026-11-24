import SwiftUI

extension PlansHomeView {
    @ViewBuilder
    var joiningOverlay: some View {
        if joining {
            VStack(spacing: 14) {
                ProgressView(Strings.joining)
                    .controlSize(.large)
                Button(Strings.cancel) {
                    joinAttempt += 1
                    joinTask?.cancel()
                    joinTask = nil
                    joining = false
                }
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(OneDay.brandText)
            }
            .padding(24)
            .glassSurface()
        }
    }

    var sharedStories: [Challenge] {
        store.challenges.filter(\.isShared)
            .map { ($0, Self.latestClip(store.recordedClips(for: $0.id))?.recordedAt ?? $0.startDate) }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    var friendsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: OneDay.Space.s) {
                    greetingRow
                    MoodTodayBadge()
                }
                .padding(.horizontal, 20)
                friendsHeader
                if !account.isSignedIn, !sharedStories.isEmpty {
                    signedOutBanner
                }

                if onOpenPersonal != nil || !sharedStories.isEmpty {
                    LazyVGrid(columns: Self.tileColumns, alignment: .leading, spacing: 14) {
                        if let onOpenPersonal {
                            personalTile(onOpen: onOpenPersonal)
                        }
                        ForEach(sharedStories) { challenge in
                            storyRow(challenge, membersAsCover: true)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                if sharedStories.isEmpty {
                    friendsEmptyState
                }
            }
            .padding(.top, 8)
            .padding(.bottom, OneDay.tabBarClearance + 20)
            .containerRelativeFrame(.horizontal)
        }
        .scrollIndicators(.hidden)
        .overlay { joiningOverlay }
    }

    var signedOutBanner: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Strings.signedOutRoomsTitle)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                Text(Strings.signedOutRoomsBody)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
            }
            Spacer(minLength: 6)
            Button(Strings.signIn) {
                joinCode = ""
                afterSignIn = {}
            }
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black, in: Capsule())
            .accessibilityIdentifier("rooms-sign-in")
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .glassSurface(radius: 18)
        .padding(.horizontal, 20)
    }

    static let tileColumns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    func personalTile(onOpen: @escaping () -> Void) -> some View {
        let latest = library.clips.filter(\.isMine).max { $0.recordedAt < $1.recordedAt }
        return Button(action: onOpen) {
            PortraitTile(
                coverURL: latest?.url, refreshToken: latest?.recordedAt,
                title: Strings.surfacePlans,
                subtitle: latest.flatMap { latestLine($0.clip) } ?? Strings.roomNobodyFilmed
            ) {
                AvatarDot(name: account.account?.displayName, size: 30, image: AvatarStore.shared.image)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("rooms-personal")
    }

    struct DebugAlert {
        let title: String
        let message: String
    }

    struct InviteRequest: Identifiable {
        let id = UUID()
        let roomID: UUID?
    }

    func showInvite(for room: Challenge) {
        openRoomForInvite(room)
        inviteRequest = InviteRequest(roomID: room.id)
    }

    func openRoomForInvite(_ room: Challenge) {
        if let code = room.roomCode { RoomShareNudge.markOffered(code: code) }
        path = [room.id]
    }

    func inviteSheet(_ request: InviteRequest) -> some View {
        FriendsInviteSheet(
            rooms: sharedStories,
            initialRoomID: request.roomID,
            memberCount: { store.members(for: $0.id).count },
            onPick: { openRoomForInvite($0) },
            onNewRoom: {
                inviteRequest = nil
                onCompose()
            })
    }

    #if DEBUG
    func createDebugTestRoomIfAsked() {
        guard DebugTestRoom.consumeLaunchRequest() else { return }
        guard account.isSignedIn else {
            debugAlert = DebugAlert(
                title: Strings.signInRequiredTitle, message: Strings.debugTestRoomNeedsSignIn)
            return
        }
        Task {
            do {
                let room = try await DebugTestRoom.create(in: store)
                showInvite(for: room)
            } catch {
                debugAlert = DebugAlert(
                    title: Strings.debugTestRoomFailedTitle, message: error.localizedDescription)
            }
        }
    }
    #endif

    var friendsHeader: some View {
        HStack(spacing: 11) {
            Text(Strings.surfaceFriends)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(OneDay.ink)
            Spacer(minLength: 6)
            joinButton
            newRoomButton
        }
        .padding(.horizontal, 20)
    }

    var newRoomButton: some View {
        Button { onCompose() } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .heavy))
                Text(Strings.newRoomRow)
                    .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(OneDay.onBrand)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(OneDay.brandHorizontal, in: Capsule())
            .oneDayGlow(strength: 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("friends-new-room")
    }

    var friendsEmptyState: some View {
        VStack(alignment: .leading, spacing: OneDay.Space.s) {
            Text(Strings.roomsGuideTitle)
                .font(OneDay.Font.subhead)
                .foregroundStyle(OneDay.ink)
            ForEach(Array(Strings.roomsGuideSteps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: OneDay.Space.s) {
                    Text("\(index + 1).")
                        .monospacedDigit()
                    Text(step)
                }
                .font(OneDay.Font.caption)
                .foregroundStyle(OneDay.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, OneDay.Space.s)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("rooms-guide")
    }

    var joinButton: some View {
        Button {
            joinCode = ""
            showJoin = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "person.2.badge.plus")
                    .font(.system(size: 13, weight: .bold))
                Text(Strings.joinShort)
                    .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(OneDay.ink)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(OneDay.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(OneDay.hairline, lineWidth: 1))
            .oneDaySoftShadow(strength: 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.enterInviteCode)
        .accessibilityIdentifier("home-join-room")
    }

    func consumePendingJoinCode() {
        guard let code = pendingJoinCode else { return }
        guard onActivate?() != false else { return }
        pendingJoinCode = nil
        joinCode = code
        startJoin(code)
    }

    func startJoin(_ code: String) {
        let code = code.uppercased().trimmingCharacters(in: .whitespaces)
        guard code.count >= 6 else { return }
        let run = {
            joining = true
            let attempt = joinAttempt
            joinTask = Task {
                defer {
                    if attempt == joinAttempt {
                        joining = false
                        joinTask = nil
                    }
                }
                do {
                    let challenge = try await store.joinRoom(code: code)
                    guard attempt == joinAttempt else { return }
                    path = [challenge.id]
                } catch is CancellationError {
                    return
                } catch {
                    guard attempt == joinAttempt else { return }
                    errorText = error.localizedDescription
                }
            }
            Task {
                try? await Task.sleep(for: .seconds(20))
                guard attempt == joinAttempt, joining else { return }
                joinAttempt += 1
                joinTask?.cancel()
                joinTask = nil
                joining = false
                errorText = Strings.joinTimedOut
            }
        }
        if account.isSignedIn { run() } else { afterSignIn = run }
    }
}
