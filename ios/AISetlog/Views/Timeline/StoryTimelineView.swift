import SwiftUI

struct StoryTimelineView: View {
    let challengeID: UUID

    @Environment(ChallengeStore.self) var store
    @Environment(AccountStore.self) var account
    @Environment(\.dismiss) var dismiss
    @Environment(\.roomPreviewMediaScope) var previewMedia
    @Environment(\.reservesTabBarClearance) var reservesTabBarClearance
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    @State var sheet: TimelineSheet?
    @State var showFilm = false
    @State var showEditPlan = false
    @State var askBeforeDeleting = false
    @State var showRoomChat = false
    @State var chatHandoff = ""
    @State var showSignIn = false
    @State var roomDay = Calendar.current.startOfDay(for: .now)
    @State var roomAnchor = Calendar.current.startOfDay(for: .now)
    @State var roomMonthOpen = false
    @State var chatDraft = ""
    @FocusState var chatFocused: Bool
    @State var personPage: String?
    @State var nudgeShareCode: String?
    @State var celebrate = false

    @AppStorage(AppLanguage.storageKey) var appLanguage: AppLanguage = .system

    var challenge: Challenge? { store.challenge(challengeID) }

    enum TimelineSheet: Identifiable, Equatable {
        case record(day: Int, take: TakeTarget = .replace(nil))
        case preview(day: Int, authorID: String?)
        case clip(day: Int, authorID: String?, takeID: UUID?)

        static func open(_ clip: DayClip) -> TimelineSheet {
            .clip(day: clip.day, authorID: clip.authorID, takeID: clip.takeID)
        }

        var id: String {
            switch self {
            case .record(let day, _): "record-\(day)"
            case .preview(let day, let authorID): "preview-\(day)-\(authorID ?? "local")"
            case .clip(let day, let authorID, let takeID):
                "clip-\(day)-\(authorID ?? "local")-\(takeID?.uuidString ?? "1")"
            }
        }
    }

    var body: some View {
        ZStack {
            OneDayCanvas(seed: 2)

            if let challenge {
                timeline(challenge)
            }

            if celebrate { celebration }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(item: $sheet, content: sheetContent)

        .navigationDestination(isPresented: $showFilm) {
            if let challenge {
                FilmView(challenge: challenge, clips: filmClips)
                    .environment(\.memberProfiles, store.memberProfiles(for: challengeID))
            }
        }
        .sheet(isPresented: $showSignIn) {
            SignInView { showSignIn = false }
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showRoomChat) {
            RoomChatView(challengeID: challengeID, onOpenMoment: { day in
                showRoomChat = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    sheet = .clip(day: day, authorID: nil, takeID: nil)
                }
            }, draft: chatHandoff)
        }
        .sheet(isPresented: $showEditPlan) {
            if let challenge {
                GuidedMomentsView(
                    initialMoments: challenge.cards.map {
                        challenge.momentValue(forSlot: $0.day) ?? Strings.dayN($0.day)
                    },
                    initialSlots: challenge.cards.map(\.day),
                    filmedSlots: Set(challenge.cards.filter { $0.clipFileName != nil }.map(\.day)),
                    saveLabel: Strings.save
                ) { draft in
                    store.replacePlan(
                        challengeID,
                        items: zip(draft.moments, draft.slots).map { (title: $0, fromSlot: $1) })
                }
            }
        }
        .confirmationDialog(
            challenge.map {
                $0.isShared
                    ? Strings.leaveRoomTitle($0.title)
                    : Strings.deleteStoryTitle($0.title)
            } ?? "",
            isPresented: $askBeforeDeleting,
            titleVisibility: .visible
        ) {
            if let challenge {
                Button(
                    challenge.isShared ? Strings.leaveRoom : Strings.deleteChallenge,
                    role: .destructive
                ) {
                    store.delete(challengeID)
                    dismiss()
                }
            }
            Button(Strings.cancel, role: .cancel) {}
        } message: {
            if let challenge {
                Text(
                    challenge.isShared
                        ? Strings.leaveRoomWarning
                        : Strings.deleteStoryWarning(challenge.recordedCount))
            }
        }
        .environment(\.memberProfiles, store.memberProfiles(for: challengeID))
    }

    var dayIsComplete: Bool {
        guard let challenge else { return false }
        return StoryAgenda(
            momentCount: challenge.cards.count,
            clips: store.recordedClips(for: challengeID),
            myID: account.account?.id ?? RoomProgress.soloAuthorID
        ).isComplete
    }

    func celebrateMyFinish() {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : OneDay.Motion.pop) {
            celebrate = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            celebrate = false
            showFilm = true
        }
    }


    func timeline(_ challenge: Challenge) -> some View {
        let clips = store.recordedClips(for: challengeID)
        let members = store.members(for: challengeID)
        let myID = account.account?.id ?? RoomProgress.soloAuthorID
        let agenda = StoryAgenda(momentCount: challenge.cards.count, clips: clips, myID: myID)

        return Group {
            if challenge.isShared {
                roomPage(challenge, clips: clips, members: members, myID: myID, agenda: agenda)
            } else {
                storyPage(challenge, clips: clips, members: members, myID: myID, agenda: agenda)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            navBar(challenge, agenda: agenda,
                   clipCount: challenge.isShared ? filmClips.count : clips.count)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: .zero) {
                if challenge.isShared, account.isSignedIn {
                    roomChatBar(target: Self.replyTarget(
                        clips: clips.filter { Self.isClip($0, on: roomDay) }, myID: myID), myID: myID)
                }
                Color.clear.frame(height: reservesTabBarClearance ? OneDay.tabBarClearance : 0)
            }
        }
        .sensoryFeedback(.success, trigger: challenge.recordedCount)
        .refreshable {
            if challenge.isShared { await store.syncRoom(challengeID) }
        }
        .task(id: challengeID) {
            offerShareIfRoomIsStillEmpty()
            guard challenge.isShared else { return }
            while !Task.isCancelled {
                await store.syncRoom(challengeID)
                do { try await Task.sleep(for: .seconds(10)) } catch { break }
            }
        }
        .navigationDestination(item: $personPage) { id in
            if let column = RoomFeed.columns(clips: clips, members: members, myID: myID)
                .first(where: { $0.id == id }) {
                RoomPersonPage(
                    column: column,
                    slotTitle: { slotTitle(for: $0) },
                    onPlay: { clip in sheet = .open(clip) },
                    canPoke: Self.canPoke(column, signedIn: account.isSignedIn),
                    hasPoked: store.hasPokedToday(challengeID: challengeID, targetAuthorID: column.id),
                    onPoke: { _ = store.poke(challengeID: challengeID, targetAuthorID: column.id) })
                    .environment(\.memberProfiles, store.memberProfiles(for: challengeID))
            }
        }
        .confirmationDialog(
            Strings.sendTheCodeTitle,
            isPresented: Binding(
                get: { nudgeShareCode != nil },
                set: { if !$0 { nudgeShareCode = nil } }),
            titleVisibility: .visible
        ) {
            if let code = nudgeShareCode {
                let card = RoomInviteCardImage(content: RoomInviteCardContent(
                    challenge: challenge, inviter: account.account?.displayName))
                ShareLink(
                    item: card,
                    subject: Text(card.content.headline),
                    message: Text(shareText(code: code, challenge: challenge)),
                    preview: SharePreview(card.content.headline, image: card),
                    label: { Text(Strings.sendTheCodeNow) })
            }
            Button(Strings.sendTheCodeLater, role: .cancel) {}
        }
    }

    func storyPage(
        _ challenge: Challenge, clips: [DayClip], members: [(id: String, name: String)],
        myID: String, agenda: StoryAgenda
    ) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                TimelineHeader(
                    challenge: challenge,
                    isSyncing: store.syncing.contains(challenge.roomCode ?? ""),
                    onRename: { name in
                        store.updatePlan(
                            challengeID, title: name, momentTitles: challenge.momentTitles ?? [])
                    })

                if agenda.isComplete {
                    FilmReadyCard(momentCount: agenda.total) { showFilm = true }
                }

                if challenge.isTimeOnly {
                    MomentFilmstrip(
                        challenge: challenge,
                        clips: clips,
                        members: members,
                        myID: myID,
                        agenda: agenda,
                        onPlay: { day in
                            sheet = challenge.isShared
                                ? .clip(day: day, authorID: nil, takeID: nil)
                                : .preview(day: day, authorID: nil)
                        },
                        onFilm: { day in sheet = .record(day: day) })
                } else {
                    MomentTimeline(
                        challenge: challenge,
                        clips: clips,
                        members: members,
                        myID: myID,
                        agenda: agenda,
                        onPlay: { day in
                            sheet = challenge.isShared
                                ? .clip(day: day, authorID: nil, takeID: nil)
                                : .preview(day: day, authorID: nil)
                        },
                        onFilm: { day in sheet = .record(day: day) })
                }

            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    func offerShareIfRoomIsStillEmpty() {
        guard let challenge, challenge.isShared, previewMedia == nil,
              let code = challenge.roomCode,
              store.members(for: challengeID).count <= 1,
              RoomShareNudge.shouldOffer(code: code, isEmptyRoom: true)
        else { return }
        RoomShareNudge.markOffered(code: code)
        nudgeShareCode = code
    }


    func navBar(
        _ challenge: Challenge, agenda: StoryAgenda, clipCount: Int
    ) -> some View {
        let syncError = store.syncError(for: challengeID)

        return VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 8) {
            IconBubble(systemName: "chevron.left") { dismiss() }
                .accessibilityLabel(Text(Strings.back))
                .accessibilityIdentifier("room-back")

            Spacer(minLength: 4)

            if challenge.isShared {
                Button(Strings.dayMakeVlog, systemImage: "film.stack.fill") { showFilm = true }
                    .font(OneDay.Font.callout)
                    .foregroundStyle(OneDay.onBrand)
                    .padding(.horizontal, OneDay.Space.m)
                    .frame(height: 38)
                    .background(Color.oneDayBrand, in: Capsule())
                    .frame(minHeight: 44)
                    .buttonStyle(.plain)
                    .opacity(clipCount == 0 ? 0.45 : 1)
                    .disabled(clipCount == 0)
                    .accessibilityIdentifier("room-make-vlog")
            }

            Menu {
                if !challenge.isShared, clipCount > 0, !agenda.isComplete {
                    Button(Strings.previewTheFilm(clipCount), systemImage: "film.stack") {
                        showFilm = true
                    }
                }

                if !challenge.isTimeOnly {
                    Button(challenge.isShared ? Strings.editRoom : Strings.editPlan, systemImage: "pencil") {
                        showEditPlan = true
                    }
                }

                Button(
                    challenge.isShared ? Strings.leaveRoom : Strings.deleteChallenge,
                    systemImage: challenge.isShared ? "rectangle.portrait.and.arrow.right" : "trash",
                    role: .destructive
                ) {
                    askBeforeDeleting = true
                }

                if let syncError {
                    Section {
                        Button(Strings.retrySync, systemImage: "arrow.clockwise") {
                            Task { await store.syncRoom(challengeID) }
                        }
                    } header: {
                        Text(syncError)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(OneDay.ink)
                    .frame(width: 38, height: 38)
                    .background(.regularMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1))
                    .overlay(alignment: .topTrailing) {
                        if syncError != nil {
                            Circle()
                                .fill(Color.oneDayButter)
                                .frame(width: 9, height: 9)
                                .overlay(Circle().strokeBorder(OneDay.canvas, lineWidth: 1.5))
                        }
                    }
                    .oneDaySoftShadow(strength: 0.5)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text(syncError ?? Strings.moreLabel))
            .accessibilityIdentifier("room-more")
        }
        if challenge.isShared {
            roomTitleRow(challenge)
        }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    var celebration: some View {
        VStack(spacing: 14) {
            OneDayBuddy(size: 78, isWorking: !reduceMotion)
            Text(Strings.yourFilmIsHere)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(OneDay.onBrand)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OneDay.brand.opacity(0.96).ignoresSafeArea())
        .transition(.opacity)
    }

}

private struct ReservesTabBarClearanceKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var reservesTabBarClearance: Bool {
        get { self[ReservesTabBarClearanceKey.self] }
        set { self[ReservesTabBarClearanceKey.self] = newValue }
    }
}
