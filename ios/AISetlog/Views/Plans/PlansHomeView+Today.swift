import SwiftUI

extension PlansHomeView {
    @ViewBuilder
    var todayCards: some View {
        if !Calendar.current.isDateInToday(selectedDay) {
            otherDayCards
        } else if let plan = store.todaysPlan() {
            HStack(alignment: .top, spacing: 12) {
                TodayPlanCard(
                    challenge: plan,
                    progress: cardState(for: plan).progress,
                    onFilm: { recordPlanSlot = PlanSlot(challengeID: plan.id, slot: $0) },
                    onOpen: { path.append(plan.id) })
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    var otherDayCards: some View {
        let isFuture = selectedDay > .now
        let mood = isFuture ? nil : moods?.mood(on: selectedDay)
        if let plan = store.plan(on: selectedDay) {
            HStack(alignment: .top, spacing: 12) {
                if let mood { MoodDayCard(entry: mood).frame(maxHeight: .infinity, alignment: .top) }
                TodayPlanCard(
                    challenge: plan,
                    progress: cardState(for: plan).progress,
                    onFilm: { recordPlanSlot = PlanSlot(challengeID: plan.id, slot: $0) },
                    onOpen: { path.append(plan.id) },
                    title: Strings.dayPlanTitle(selectedDay))
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
        } else if isFuture {
            Button(Strings.planAhead, systemImage: "square.and.pencil") { planningAhead = true }
                .buttonStyle(.primaryAction)
                .padding(.horizontal, 20)
                .accessibilityIdentifier("day-plan-ahead")
        }
        if !isFuture, store.plan(on: selectedDay) == nil {
            let dayClips = clips(on: selectedDay).sorted { $0.recordedAt < $1.recordedAt }
            let recap = DayRecapCard(count: dayClips.count) { vlogRequest = VlogRequest(clips: dayClips) }
            Group {
                if let mood, !dayClips.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        MoodDayCard(entry: mood).frame(maxHeight: .infinity, alignment: .top)
                        recap.frame(maxHeight: .infinity, alignment: .top)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } else if let mood {
                    MoodDayCard(entry: mood, wide: true)
                } else if !dayClips.isEmpty {
                    recap
                }
            }
            .padding(.horizontal, 20)
        }
    }

    func todaySection(_ challenges: [Challenge], label: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: label)
                .padding(.horizontal, 20)
            ForEach(challenges) { challenge in
                todayRow(challenge)
            }
        }
    }

    func todayRow(_ challenge: Challenge) -> some View {
        let state = cardState(for: challenge)
        return TodayStoryRow(
            challenge: challenge,
            progress: state.progress,
            coverURL: state.coverURL,
            refreshToken: state.refreshToken,
            onContinue: { recordChallenge = challenge },
            onOpen: { path.append(challenge.id) })
            .padding(.horizontal, 20)
    }

    func todayStories(leading: Challenge) -> [Challenge] {
        let calendar = Calendar.current
        let others = store.challenges.filter { challenge in
            guard !challenge.isShared, challenge.id != leading.id, !challenge.isComplete, !challenge.cards.isEmpty
            else { return false }
            if challenge.isOneDay { return calendar.isDateInToday(challenge.startDate) }
            return (1...max(challenge.cards.count, 1)).contains(challenge.currentDay)
        }
        return [leading] + others.sorted { $0.startDate > $1.startDate }
    }

    func heroSection(_ challenge: Challenge, label: String) -> some View {
        let state = cardState(for: challenge)
        return VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: label)
                .padding(.horizontal, 20)

            StoryCard(
                challenge: challenge,
                memberNames: store.members(for: challenge.id).map(\.name),
                progress: state.progress,
                coverURL: state.coverURL,
                refreshToken: state.refreshToken,
                onContinue: { recordChallenge = challenge },
                onOpen: { path.append(challenge.id) })
                .padding(.horizontal, 20)
        }
    }

    var startTodayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: Strings.startTodayLabel)
                .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 12) {
                Text(Strings.startTodayBody)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)

                Button(Strings.startTodayCTA) { onCompose() }
                    .buttonStyle(.primaryAction)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .glassSurface(radius: OneDay.Radius.card)
            .padding(.horizontal, 20)
        }
    }

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

    var timelineSection: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            if let title = stories.sectionTitle {
                SectionLabel(text: title)
                    .padding(.horizontal, 20)
            }

            ForEach(timeline.days) { day in
                VStack(alignment: .leading, spacing: 9) {
                    Text(day.label)
                        .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(OneDay.inkFaint)
                        .padding(.horizontal, 20)

                    ForEach(day.stories) { challenge in
                        storyRow(challenge)
                    }
                }
            }
        }
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
        case .quickStart:
            let challenge = store.createQuickStart()
            path = [challenge.id]
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
            ? date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
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
