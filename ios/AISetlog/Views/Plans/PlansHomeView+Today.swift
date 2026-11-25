import SwiftUI

extension PlansHomeView {

    var emptyState: some View {
        EmptyFrame(radius: OneDay.Radius.card) {
            VStack(spacing: OneDay.Space.m) {
                Image(systemName: "video.badge.plus")
                    .font(OneDay.Font.title)
                    .foregroundStyle(OneDay.brandText)
                Text(Strings.mineEmptyTitle)
                    .font(OneDay.Font.headline)
                    .foregroundStyle(OneDay.ink)
            }
            .padding(OneDay.Space.l)
            .padding(.vertical, OneDay.Space.s)
        }
        .padding(.horizontal, OneDay.Space.xl)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home-guide")
    }

    func storyRow(_ challenge: Challenge, membersAsCover: Bool = false) -> some View {
        let state = cardState(for: challenge)
        let members = store.members(for: challenge.id)
        return Button {
            path.append(challenge.id)
        } label: {
            StoryRowCard(
                challenge: challenge,
                progress: state.progress,
                coverURL: membersAsCover ? state.latest?.url ?? state.coverURL : state.coverURL,
                refreshToken: membersAsCover ? state.latest?.recordedAt ?? state.refreshToken : state.refreshToken,
                memberNames: members.map(\.name),
                showsMembersAsCover: membersAsCover,
                roomMembers: members,
                memberImages: membersAsCover ? store.memberAvatarsByID(for: challenge.id) : [:],
                latestLine: membersAsCover ? latestLine(state.latest) : nil,
                latestCaption: membersAsCover ? state.latest?.captions.firstText : nil,
                hasNew: membersAsCover && hasNew(challenge, latest: state.latest))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(membersAsCover ? "room-preview-card" : "story-row")
        .contextMenu {
            Button(
                challenge.isShared ? Strings.leaveRoom : Strings.deleteChallenge,
                role: .destructive
            ) {
                pendingDeletion = challenge
            }
        }
        .padding(.horizontal, membersAsCover ? 0 : 20)
    }

    @ViewBuilder
    func recorder(for challenge: Challenge, preferredDay: Int? = nil) -> some View {
        let slot = slotToRecord(in: challenge, preferred: preferredDay)
        let label = ChallengePresenter(challenge: challenge).slotLabel(forSlot: slot)
        RecordClipView(
            day: slot,
            slotTitle: challenge.isTimeOnly ? nil : label,
            momentCount: challenge.isShared ? 0 : challenge.cards.count,
            clipLength: challenge.resolvedClipLength,
            showsPrompt: !challenge.isTimeOnly && label != nil,
            orientation: challenge.resolvedOrientation,
            lockedCamera: challenge.cameraStyle
        ) { url, overlayText in
            store.saveClip(
                from: url, day: slot, challengeID: challenge.id, overlayText: overlayText)
            if store.challenge(challenge.id)?.isComplete == true {
                path.append(challenge.id)
            }
        }
    }

    func slotToRecord(in challenge: Challenge, preferred: Int?) -> Int {
        if let preferred,
           let card = challenge.cards.first(where: { $0.day == preferred }),
           card.clipFileName == nil {
            return card.day
        }
        return cardState(for: challenge).progress.slotToOffer(
            today: challenge.isOneDay ? nil : challenge.currentDay)
    }

    func consumeLaunchAction() {
        guard let action = launchAction else { return }
        guard onActivate?() != false else { return }
        launchAction = nil
        switch action {
        case .newStory:
            onCompose()
        case .join:
            joinCode = ""
            showJoin = true
        case .record(let id):
            recordChallenge = store.challenge(id)
        case .openStory(let id):
            guard store.challenge(id) != nil else { return }
            path = [id]
        }
    }

    func openPendingNotificationRoute() {
        guard let route = NotificationRouteInbox.peek(),
              let challenge = store.challenge(route.challengeID)
        else { return }
        guard (scope == .friends) == challenge.isShared,
              onActivate?() != false else { return }
        _ = NotificationRouteInbox.consume()
        if challenge.isComplete {
            path = [challenge.id]
        } else {
            notificationRecordRoute = route
        }
    }

    struct CardState {
        let progress: RoomProgress
        let coverURL: URL?
        let refreshToken: Date?
        let latest: DayClip?
    }

    func cardState(for challenge: Challenge) -> CardState {
        let clips = store.recordedClips(for: challenge.id)
        let first = clips.min {
            ($0.recordedAt ?? .distantFuture, $0.day) < ($1.recordedAt ?? .distantFuture, $1.day)
        }
        return CardState(
            progress: RoomProgress(
                momentCount: challenge.cards.count,
                clips: clips,
                myID: account.account?.id ?? RoomProgress.soloAuthorID),
            coverURL: first?.url,
            refreshToken: first?.recordedAt,
            latest: Self.latestClip(clips))
    }

    static func latestClip(_ clips: [DayClip]) -> DayClip? {
        clips.filter { $0.recordedAt != nil }.max { $0.recordedAt! < $1.recordedAt! }
    }

    func latestLine(_ clip: DayClip?) -> String? {
        guard let clip, let date = clip.recordedAt else { return nil }
        let name = isMine(clip) ? Strings.youLabel : (clip.authorName ?? "")
        let when = Calendar.current.isDateInToday(date)
            ? date.formatted(.roomClock)
            : date.formatted(.dateTime.month().day())
        return name.isEmpty ? when : "\(name) · \(when)"
    }

    func isMine(_ clip: DayClip) -> Bool {
        clip.authorID == nil || clip.authorID == RoomProgress.soloAuthorID
            || clip.authorID == account.account?.id
    }

    func hasNew(_ challenge: Challenge, latest: DayClip?) -> Bool {
        guard let latest, let date = latest.recordedAt, !isMine(latest) else { return false }
        guard let seen = roomSeenAt[challenge.id.uuidString] else { return true }
        return date > Date(timeIntervalSince1970: seen)
    }

    static let roomSeenKey = "roomSeenAt"

    func markSeen(_ id: UUID) {
        roomSeenAt[id.uuidString] = Date.now.timeIntervalSince1970
        UserDefaults.standard.set(roomSeenAt, forKey: Self.roomSeenKey)
    }
}
