import SwiftUI

extension StoryTimelineView {
    var signedOutLine: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(OneDay.inkFaint)
            Text(Strings.signedOutRoomBody)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(OneDay.ink)
            Spacer(minLength: 6)
            Button(Strings.signIn) { showSignIn = true }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.black, in: Capsule())
                .accessibilityIdentifier("room-sign-in")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassSurface(radius: 16)
    }

    func roomPage(
        _ challenge: Challenge, clips: [DayClip], members: [(id: String, name: String)],
        myID: String, agenda: StoryAgenda
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            let dayClips = clips.filter { Self.isClip($0, on: roomDay) }
            let dayColumns = RoomFeed.columns(clips: dayClips, members: members, myID: myID)
            let signedOut = challenge.isShared && !account.isSignedIn
            let isToday = Calendar.current.isDateInToday(roomDay)
            let filmedDays = Set(clips.compactMap { $0.recordedAt.map(Calendar.current.startOfDay) })

            if signedOut { signedOutLine }

            RoomDateStrip(
                selected: Binding(
                    get: { roomDay },
                    set: { roomDay = $0 }),
                anchor: $roomAnchor,
                expanded: $roomMonthOpen,
                hasClips: { filmedDays.contains(Calendar.current.startOfDay(for: $0)) })

            let nextToFilm = agenda.suggested ?? agenda.openToMe.first
            RoomPeopleRow(
                columns: dayColumns,
                canFilm: isToday && nextToFilm != nil,
                isToday: isToday,
                onSelect: { personPage = $0 },
                onFilm: { if let nextToFilm { sheet = .record(day: nextToFilm) } },
                trailing: inviteCell(challenge))
            if Self.everyoneFilmedToday(dayColumns), !agenda.isComplete {
                FilmReadyCard(eyebrow: Strings.everyoneFilmedToday, momentCount: nil) { showFilm = true }
                    .accessibilityIdentifier("room-everyone-filmed")
            }
            if dayClips.isEmpty {
                if isToday, let nextToFilm, !signedOut {
                    filmTodaySlot { sheet = .record(day: nextToFilm) }
                }
                Spacer(minLength: 0)
            } else {
                RoomFrames(
                    clips: dayClips,
                    members: members,
                    myID: myID,
                    nextToFilm: nextToFilm,
                    slotTitle: { slotTitle(for: $0) },
                    onPlay: { clip in sheet = .open(clip) },
                    onFilm: { day in sheet = .record(day: day) },
                    onOpenPerson: { column in personPage = column.id },
                    hasPoked: { id in
                        store.hasPokedToday(challengeID: challengeID, targetAuthorID: id)
                    },
                    onPoke: { id in
                        store.poke(challengeID: challengeID, targetAuthorID: id)
                    },
                    orientation: challenge.resolvedOrientation,
                    latestComment: { clip in
                        store.interactions(
                            for: challengeID, day: clip.day,
                            targetAuthorID: clip.authorID ?? myID
                        ).comments.max { $0.createdAt < $1.createdAt }
                    },
                    reactions: { reactions(for: $0, myID: myID) },
                    onReact: { react($0, $1, myID: myID) },
                    signedOut: signedOut,
                    onSignIn: { showSignIn = true })
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    func roomTitleRow(_ challenge: Challenge) -> some View {
        HStack(spacing: OneDay.Space.s) {
            TimelineHeader(
                challenge: challenge,
                isSyncing: store.syncing.contains(challenge.roomCode ?? ""),
                onRename: { name in
                    Task { await store.renameRoom(challengeID, to: name) }
                },
                fontSize: 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsBackToToday {
                Button(Strings.todayLabel) { backToToday() }
                    .font(OneDay.Font.caption)
                    .foregroundStyle(OneDay.brandText)
                    .padding(.horizontal, OneDay.Space.m)
                    .frame(minHeight: 30)
                    .background(OneDay.surfaceSoft, in: Capsule())
                    .frame(minHeight: 44)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("room-back-to-today")
            }
            Button {
                withAnimation(OneDay.Motion.snap) { roomMonthOpen.toggle() }
            } label: {
                HStack(spacing: OneDay.Space.xs) {
                    Text(RoomDateStrip.monthLabel(roomAnchor))
                    Image(systemName: roomMonthOpen ? "chevron.up" : "chevron.down")
                        .font(OneDay.Font.micro)
                }
                .font(OneDay.Font.callout)
                .foregroundStyle(OneDay.brandText)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("room-month")
        }
        .padding(.leading, OneDay.Space.xs)
    }

    var showsBackToToday: Bool {
        let unit: Calendar.Component = roomMonthOpen ? .month : .weekOfYear
        return !Calendar.current.isDateInToday(roomDay)
            || !Calendar.current.isDate(roomAnchor, equalTo: .now, toGranularity: unit)
    }

    func backToToday() {
        withAnimation(OneDay.Motion.snap) {
            roomDay = Calendar.current.startOfDay(for: .now)
            roomAnchor = roomDay
            roomMonthOpen = false
        }
    }

    var filmClips: [DayClip] {
        let all = store.recordedClips(for: challengeID)
        guard challenge?.isShared == true else { return all }
        return all.filter { Self.isClip($0, on: roomDay) }
    }

    func filmTodaySlot(_ onFilm: @escaping () -> Void) -> some View {
        Button(action: onFilm) {
            EmptyFrame(radius: OneDay.Radius.card) {
                Label(Strings.roomFeedFilm, systemImage: "camera.fill")
                    .font(OneDay.Font.headline)
                    .foregroundStyle(OneDay.brandText)
                    .frame(maxWidth: .infinity, minHeight: 220)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("room-film-today")
    }

    func inviteCell(_ challenge: Challenge) -> AnyView? {
        if let code = challenge.roomCode, previewMedia == nil {
            return AnyView(RoomInviteShareLink(
                content: RoomInviteCardContent(challenge: challenge, inviter: account.account?.displayName),
                message: shareText(code: code, challenge: challenge)
            ) {
                RoomPeopleRow.addCell(Strings.inviteLabel)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("room-invite"))
        }
        return nil
    }

    static func replyTarget(clips: [DayClip], myID: String) -> DayClip? {
        clips.filter { $0.authorID != myID && $0.authorID != RoomProgress.soloAuthorID }
            .max { ($0.recordedAt ?? .distantPast) < ($1.recordedAt ?? .distantPast) }
    }

    func roomChatBar(target: DayClip?, myID: String) -> some View {
        HStack(spacing: OneDay.Space.s) {
            if let target, !chatFocused {
                MoodReactButton(
                    reactions: reactions(for: target, myID: myID), myID: myID,
                    showsOthers: false, onCanvas: true
                ) { react(target, $0, myID: myID) }
            }
            TextField(Strings.chatSayPlaceholder, text: $chatDraft)
                .font(OneDay.Font.subhead)
                .focused($chatFocused)
                .submitLabel(.send)
                .onSubmit { sendChat(target: target, myID: myID) }
                .padding(.horizontal, OneDay.Space.m)
                .frame(minHeight: 40)
                .background(OneDay.surfaceSoft, in: Capsule())
                .accessibilityIdentifier("room-chat-field")
            Button(Strings.chatLabel) { openRoomChat() }
                .font(OneDay.Font.caption)
                .foregroundStyle(OneDay.brandText)
                .frame(minWidth: 44, minHeight: 44)
                .buttonStyle(.plain)
                .accessibilityIdentifier("room-chat")
        }
        .padding(.horizontal, OneDay.Space.l)
        .padding(.vertical, OneDay.Space.xs)
        .background(.regularMaterial)
        .animation(OneDay.Motion.snap, value: chatFocused)
    }

    func sendChat(target: DayClip?, myID: String) {
        let text = chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            chatFocused = false
            return
        }
        guard let target else {
            openRoomChat()
            return
        }
        store.addComment(text, day: target.day, challengeID: challengeID, targetAuthorID: target.authorID ?? myID)
        chatDraft = ""
        chatFocused = false
    }

    func openRoomChat() {
        chatHandoff = chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        chatDraft = ""
        chatFocused = false
        showRoomChat = true
    }

    func reactions(for clip: DayClip, myID: String) -> [ClipReaction] {
        store.interactions(for: challengeID, day: clip.day, targetAuthorID: clip.authorID ?? myID).reactions
    }

    func react(_ clip: DayClip, _ key: String, myID: String) {
        store.toggleReaction(key, day: clip.day, challengeID: challengeID, targetAuthorID: clip.authorID ?? myID)
    }

    static func canPoke(_ column: RoomFeed.Column, signedIn: Bool) -> Bool {
        signedIn && !column.isMine
            && !column.clips.contains { $0.recordedAt.map(Calendar.current.isDateInToday) ?? false }
    }

    static func everyoneFilmedToday(_ columns: [RoomFeed.Column]) -> Bool {
        columns.count > 1 && columns.allSatisfy { column in
            column.clips.contains { $0.recordedAt.map(Calendar.current.isDateInToday) ?? false }
        }
    }

    static func isClip(_ clip: DayClip, on day: Date) -> Bool {
        clip.recordedAt.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false
    }
}
