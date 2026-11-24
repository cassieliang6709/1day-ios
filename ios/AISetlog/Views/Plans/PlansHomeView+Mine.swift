import SwiftUI

extension PlansHomeView {
    var storiesContent: some View {
        ScrollViewReader { proxy in
            storiesScroll
                .onChange(of: draftsRequest) { _, _ in
                    withAnimation(OneDay.Motion.soft) {
                        proxy.scrollTo(Self.libraryAnchor, anchor: .top)
                    }
                }
        }
        .onChange(of: isSelectingClips) { _, selecting in onSelectingChange?(selecting) }
        .sheet(isPresented: $planningAhead) {
            GuidedMomentsView(initialMoments: []) { draft in
                let moments = draft.moments
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                guard !moments.isEmpty else { return }
                _ = store.create(
                    title: draft.suggestedName ?? Strings.dayPlanTitle(selectedDay),
                    mode: .oneDay,
                    clipLength: .scene,
                    cameraStyle: CameraStyle.defaultCamera,
                    momentTitles: moments,
                    startDate: selectedDay)
            }
        }
        .sheet(item: $vlogRequest) { request in
            LibraryVlogSheet(clips: request.clips)
        }
        #if DEBUG
        .onAppear { LibraryDebugSeed.runIfAsked(store: store, drafts: drafts, moods: moods) }
        #endif
    }

    static let libraryAnchor = "library-section"

    var storiesScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if !isSelectingClips {
                    header
                }

                #if DEBUG || LOCAL_ROOM_CHAT_DEMO
                if DemoEntries.areEnabled {
                    Button {
                        showRoomDemo = true
                    } label: {
                        Label(appLanguage.resolved == .chinese ? "房间演示" : "Room demo",
                              systemImage: "person.3.sequence")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .accessibilityIdentifier("home-room-demo")
                }
                #endif

                otherDayChip
                todayCards

                if !store.challenges.contains(where: { !$0.isShared }), library.clips.isEmpty { emptyState }

                LibrarySection(
                    library: library,
                    rooms: store.challenges.filter(\.isShared),
                    onOpenStory: { path.append($0) },
                    draftsRequest: draftsRequest,
                    isSelecting: $isSelectingClips,
                    picked: $pickedClips)
                    .id(Self.libraryAnchor)
            }
            .padding(.top, 8)
            .padding(.bottom, OneDay.tabBarClearance + 20)
            .containerRelativeFrame(.horizontal)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            if isSelectingClips {
                VStack(spacing: OneDay.Space.l) {
                    header
                    LibrarySelectionCard(picked: $pickedClips) {
                        vlogRequest = VlogRequest(clips: pickedClips)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, OneDay.Space.m)
                .background { OneDayCanvas().ignoresSafeArea(edges: .top) }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay { joiningOverlay }
    }

    var library: ClipLibrary {
        let mine = [account.account?.id, RoomProgress.soloAuthorID, "local"].compactMap { $0 }
        return ClipLibrary(
            stories: store.challenges.map { ($0, store.recordedClips(for: $0.id)) },
            drafts: drafts.sortedDrafts.map { ($0, drafts.url(for: $0)) },
            myIDs: Set(mine))
    }

    var greetingRow: some View {
        HStack(spacing: 11) {
            Button { showSettings = true } label: {
                AvatarDot(name: account.account?.displayName, size: 42, image: AvatarStore.shared.image)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Strings.settings)

            VStack(alignment: .leading, spacing: 3) {
                Text(Strings.greeting(
                    name: account.account?.displayName,
                    hour: Calendar.current.component(.hour, from: .now)))
                    .font(.system(size: 16.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                dateline
            }
            Spacer(minLength: 0)
        }
    }

    var header: some View {
        HStack(spacing: 11) {
            if onBackToRooms != nil {
                mineHeader
            } else {
                greetingAndCompose
            }
        }
        .padding(.horizontal, 20)
    }

    var mineHeader: some View {
        HStack(spacing: OneDay.Space.m) {
            Button { showSettings = true } label: {
                AvatarDot(name: account.account?.displayName, size: 48, image: AvatarStore.shared.image)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Strings.settings)

            Text(Strings.surfacePlans)
                .font(OneDay.Font.title)
                .foregroundStyle(OneDay.ink)
            Spacer(minLength: OneDay.Space.s)
            // 日历收到右上角（2026-11-21 Cassie：整行周日历太乱）
            if isSelectingClips {
                Button(Strings.libraryRandomPick, systemImage: "dice") {
                    Task {
                        let picks = await randomPick()
                        withAnimation(OneDay.Motion.snap) { pickedClips = picks }
                    }
                }
                .font(OneDay.Font.callout)
                .foregroundStyle(OneDay.ink)
                .padding(.horizontal, OneDay.Space.m)
                .frame(height: 38)
                .background(Color.oneDayBrand.opacity(0.18), in: Capsule())
                .accessibilityIdentifier("library-random-pick")
            } else {
                IconBubble(systemName: "calendar", label: DayPickerSheet.title) { showsDayPicker = true }
                    .accessibilityIdentifier("mine-calendar")
            }
            if !library.scoped(includingFriends: false).clips.isEmpty {
                Button(isSelectingClips ? Strings.cancel : Strings.dayMakeVlog) {
                    withAnimation(OneDay.Motion.snap) {
                        isSelectingClips.toggle()
                        if isSelectingClips {
                            pickedClips = clips(on: .now).sorted { $0.recordedAt < $1.recordedAt }
                        }
                    }
                }
                .font(OneDay.Font.callout)
                .foregroundStyle(OneDay.ink)
                .padding(.horizontal, OneDay.Space.m)
                .frame(height: 38)
                .background(Color.oneDayBrand.opacity(0.18), in: Capsule())
                .accessibilityIdentifier("library-select")
            }
        }
        .accessibilityIdentifier("mine-header")
        .sheet(isPresented: $showsDayPicker) {
            DayPickerSheet(
                selected: $selectedDay,
                hasSomething: { day in store.plan(on: day) != nil || !clips(on: day).isEmpty },
                mood: { day in day > .now ? nil : moods?.mood(on: day)?.mood })
                .presentationDetents([.medium])
                .presentationBackground(OneDay.surface)
        }
    }

    /// 看的不是今天时，提示是哪天，点 × 回到今天
    @ViewBuilder
    var otherDayChip: some View {
        if !Calendar.current.isDateInToday(selectedDay) {
            Button {
                withAnimation(OneDay.Motion.soft) { selectedDay = Calendar.current.startOfDay(for: .now) }
            } label: {
                HStack(spacing: OneDay.Space.xs) {
                    Text(selectedDay.formatted(.dateTime.month().day().weekday(.abbreviated)
                        .locale(AppLanguage.effective.locale)))
                    Image(systemName: "xmark")
                        .font(OneDay.Font.rounded(.caption2, weight: .heavy))
                }
                .font(OneDay.Font.caption)
                .foregroundStyle(OneDay.brandText)
                .padding(.horizontal, OneDay.Space.m)
                .padding(.vertical, OneDay.Space.xs + 2)
                .background(Capsule().fill(Color.oneDayBrand.opacity(0.12)))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, OneDay.Space.xl)
            .accessibilityLabel(DayPickerSheet.backToToday)
            .accessibilityIdentifier("mine-back-to-today")
        }
    }

    var greetingAndCompose: some View {
        HStack(spacing: 6) {
            greetingRow
            composeButton
        }
    }

    var composeButton: some View {
        Button { onCompose() } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .heavy))
                Text(Strings.surfaceCompose)
                    .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(OneDay.onBrand)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(OneDay.brandHorizontal, in: Capsule())
            .oneDayGlow(strength: 0.5)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home-compose")
    }

    var dateline: some View {
        let summary = HomeHeaderSummary()
        return HStack(spacing: 6) {
            Text(summary.dateLine)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(OneDay.inkSoft)
                .lineLimit(1)
                .fixedSize()

        }
    }

    @ViewBuilder
    var draftsRow: some View {
        if !drafts.isEmpty {
            Button { showDrafts = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(OneDay.brandText)
                        .frame(width: 34, height: 34)
                        .background(
                            Color.oneDayBrand.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text(Strings.draftsPending(drafts.count))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(OneDay.brandText)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(OneDay.inkFaint)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    OneDay.surface,
                    in: RoundedRectangle(cornerRadius: OneDay.Radius.chip, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: OneDay.Radius.chip, style: .continuous)
                        .strokeBorder(
                            Color.oneDayBrand.opacity(0.28),
                            style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .accessibilityIdentifier("drafts-row")
        }
    }

    func randomPick() async -> [LibraryClip] {
        let mine = library.scoped(includingFriends: false).clips
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .distantPast
        let recent = mine.filter { $0.recordedAt >= weekAgo }
        let candidates = recent.isEmpty ? mine : recent
        var usable: [LibraryClip] = []
        for clip in candidates where await ClipQuality.isUsable(clip.url) {
            usable.append(clip)
        }
        let pool = usable.isEmpty ? candidates : usable
        var picks: [LibraryClip] = []
        var total = 0.0
        for clip in pool.shuffled() where total < Self.randomPickSeconds {
            picks.append(clip)
            total += await ClipDurations.seconds(of: clip.url)
        }
        return picks.sorted { $0.recordedAt < $1.recordedAt }
    }

    static let randomPickSeconds = 30.0

    func clips(on day: Date) -> [LibraryClip] {
        library.scoped(includingFriends: false).clips
            .filter { Calendar.current.isDate($0.recordedAt, inSameDayAs: day) }
    }
}
