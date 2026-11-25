import SwiftUI

struct StoryRowCard: View {
    let challenge: Challenge
    let progress: RoomProgress
    let coverURL: URL?
    var refreshToken: Date?
    var memberNames: [String] = []
    var showsMembersAsCover = false
    var roomMembers: [(id: String, name: String)] = []
    var memberImages: [String: UIImage] = [:]
    var latestLine: String?
    var latestCaption: String?
    var hasNew = false

    private var presenter: ChallengePresenter { ChallengePresenter(challenge: challenge) }
    private var todaySlot: Int? { challenge.isOneDay ? nil : challenge.currentDay }
    private var offeredSlot: Int { progress.slotToOffer(today: todaySlot) }

    @ViewBuilder
    var body: some View {
        if showsMembersAsCover {
            roomPreviewCard
        } else {
            compactRow
        }
    }

    private var roomPreviewCard: some View {
        PortraitTile(
            coverURL: coverURL, refreshToken: refreshToken, caption: latestCaption,
            title: title, subtitle: latestLine ?? Strings.roomNobodyFilmed, hasNew: hasNew
        ) {
            RoomAvatarCluster(members: roomMembers, images: memberImages)
        }
    }

    private var compactRow: some View {
        HStack(spacing: 14) {
            thumbnail
            VStack(alignment: .leading, spacing: 5) {
                Text(presenter.displayTitle)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if memberNames.count > 1 {
                AvatarStack(names: memberNames, maxShown: 3, size: 24)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(OneDay.inkFaint)
        }
        .padding(12)
        .glassSurface(radius: OneDay.Radius.card)
        .contentShape(Rectangle())
    }

    private var title: String {
        guard showsMembersAsCover,
              challenge.title == Strings.byTimeTitle(challenge.startDate),
              !memberNames.filter({ !$0.isEmpty }).isEmpty
        else { return presenter.displayTitle }
        return Strings.roomOfPeople(Array(memberNames.filter { !$0.isEmpty }.prefix(3)))
    }

    private var thumbnail: some View {
        ClipTile(url: coverURL, refreshToken: refreshToken)
            .frame(width: 58, height: 66)
    }

    private var subtitle: String {
        if progress.isComplete {
            return Strings.filmReadySubtitle(
                duration: StorySchedule(challenge).filmDuration(clipCount: progress.clipCount))
        }
        if challenge.isTimeOnly { return Strings.timeOnlyMoment }
        if challenge.isShared {
            return presenter.momentName(forSlot: offeredSlot).map { Strings.openMomentLabel($0) }
                ?? Strings.timeOnlyMoment
        }
        let moment = presenter.title(forSlot: offeredSlot)
        return progress.offeringToday(today: todaySlot)
            ? Strings.openMomentLabel(moment)
            : Strings.catchUpDayLabel(day: offeredSlot, moment: moment)
    }
}

struct StoryCoverPlaceholder: View {
    var body: some View {
        ZStack {
            Color.oneDayBrand.opacity(0.18)
            Image(systemName: "video.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(OneDay.brandText.opacity(0.45))
        }
    }
}
