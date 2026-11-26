import SwiftUI

struct ClipPreviewView: View {
    struct ExtraAction: Identifiable {
        let id: String
        let symbol: String
        let title: String
        var isDestructive = false
        let action: () -> Void
    }

    let day: Int
    var slotTitle: String?
    var momentCount = 0
    var authorName: String?
    var captions: [Caption] = []
    var clipLength: Challenge.ClipLength = .tiny
    var showsPrompt = true
    var isLive = true
    let url: URL
    let recordedAt: Date?
    var challengeID: UUID?
    var targetAuthorID: String?
    var takeID: UUID? = nil
    let onReRecord: (() -> Void)?
    var onAddTake: (() -> Void)? = nil
    var onDraftCaptions: (([Caption]) -> Void)? = nil
    var extraActions: [ExtraAction] = []

    @State private var draftCaptions: [Caption]?

    @Environment(\.dismiss) private var dismiss
    @Environment(ChallengeStore.self) private var store
    @Environment(AccountStore.self) private var account

    @State private var selectedID: UUID?
    @State private var editingCaption = false
    @State private var editingID: UUID?
    @State private var editingIsNew = false
    @State private var captionDraft = ""
    @State private var snappedToCentre = false
    @AppStorage("caption.gestureHintSeen.v1") private var gestureHintSeen = false
    @FocusState private var captionFocused: Bool
    @State private var showComments = false
    @State private var deleted: DeletedCaption?

    private struct DeletedCaption: Equatable {
        let caption: Caption
        let index: Int
    }

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var myID: String { account.account?.id ?? "local" }

    private var card: DayCard? {
        guard let challengeID else { return nil }
        return store.challenge(challengeID)?.cards.first { $0.day == day }
    }

    private var extraTake: ClipTake? {
        guard let takeID else { return nil }
        return card?.moreTakes.first { $0.id == takeID }
    }

    private var comments: [ClipComment] {
        guard let challengeID else { return [] }
        return store.interactions(
            for: challengeID, day: day, targetAuthorID: targetAuthorID ?? myID).comments
    }

    private var isShared: Bool {
        guard let challengeID else { return false }
        return store.challenge(challengeID)?.isShared ?? false
    }

    @State private var measuredAspect: CGFloat?

    private var isLandscape: Bool {
        guard let challengeID else { return false }
        return store.challenge(challengeID)?.resolvedOrientation == .landscape
    }

    private var aspectRatio: CGFloat { measuredAspect ?? (isLandscape ? 16 / 9 : 9 / 16) }

    private var isMine: Bool {
        targetAuthorID == nil || targetAuthorID == "local" || targetAuthorID == myID
    }

    private var canWrite: Bool { challengeID != nil || onDraftCaptions != nil }

    private var liveCaptions: [Caption] {
        if onDraftCaptions != nil { return draftCaptions ?? captions }
        if takeID != nil {
            return ClipCaptionSelection.captions(
                isMine: isMine, hasLiveCard: extraTake != nil,
                live: extraTake?.captions ?? [], snapshot: captions)
        }
        return ClipCaptionSelection.captions(
            isMine: isMine, hasLiveCard: card != nil,
            live: card?.captions ?? [], snapshot: captions)
    }

    private func writeCaptions(_ list: [Caption]) {
        let kept = list.drawable
        if let onDraftCaptions {
            draftCaptions = kept
            onDraftCaptions(kept)
        } else if let challengeID {
            store.updateCaptions(kept, day: day, challengeID: challengeID, takeID: takeID)
        }
    }

    private var target: Caption? {
        let list = liveCaptions.drawable
        if let selectedID, let hit = list.first(where: { $0.id == selectedID }) { return hit }
        return list.count == 1 ? list.first : nil
    }

    private func saveSticker(_ sticker: CaptionSticker, for id: UUID) {
        var list = liveCaptions
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        list[i].sticker = sticker
        writeCaptions(list)
    }

    private var localizedMomentTitle: String {
        slotTitle.map { MomentCatalog.localize($0) } ?? Strings.dayN(day)
    }

    private var displayLocale: Locale {
        Locale(identifier: appLanguage.resolved.localeCode)
    }

    private var timeText: String? {
        recordedAt?.formatted(.dateTime.hour().minute().locale(displayLocale))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            backdrop
            stage
            scrims
            if editingCaption { outsideTapCatcher }
            chrome
            if deleted != nil { undoToast }
        }
        .statusBarHidden()
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .task(id: url) { measuredAspect = await ClipGeometry.aspect(of: url) }
        .sheet(isPresented: $showComments) { commentsSheet }
        .onChange(of: captionFocused) { _, focused in
            if !focused, editingCaption { saveCaption() }
        }
        .onSubmit { commitCaption() }
        .onChange(of: captionDraft) { old, new in limitCaptionLines(old: old, new: new) }
    }

    private var outsideTapCatcher: some View {
        Color.clear
            .contentShape(Rectangle())
            .ignoresSafeArea()
            .onTapGesture { commitCaption() }
    }


    @ViewBuilder
    private var stage: some View {
        EmptyView()
    }

    private var cardLayout: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            top
            Color.clear
                .aspectRatio(aspectRatio, contentMode: .fit)
                .overlay { videoStage }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .accessibilityIdentifier("moment-stage")
            bottomControls
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var videoStage: some View {
        ZStack {
            if isLive {
                ClipThumbnail(url: url, refreshToken: recordedAt)
                LoopingClipPlayer(url: url, refreshToken: recordedAt)
            } else {
                Color.black
            }
            captionLayer
        }
    }

    private var backdrop: some View {
        Color.clear
            .overlay { ClipThumbnail(url: url, refreshToken: recordedAt) }
            .clipped()
            .blur(radius: 44)
            .overlay(Color.black.opacity(0.28))
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    private var scrims: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 150)
            Spacer(minLength: 0)
            LinearGradient(
                colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .frame(height: 300)
                .opacity(editingCaption ? 0 : 1)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var captionLayer: some View {
        if editingCaption {
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { captionFocused = false }
                CaptionOverlayEditor(text: $captionDraft, isFocused: $captionFocused)
            }
        } else {
            let list = liveCaptions.drawable
            if !list.isEmpty {
                GeometryReader { proxy in
                    ZStack {
                        if selectedID != nil {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { deselectCaption() }
                            if snappedToCentre { centreGuide }
                        }

                        ForEach(list) { caption in
                            CaptionStickerView(
                                caption: caption,
                                stageSize: proxy.size,
                                isSelected: selectedID == caption.id,
                                isMine: isMine,
                                snappedToCentre: $snappedToCentre,
                                onTap: { tapCaption(caption.id) },
                                onChange: { saveSticker($0, for: caption.id) },
                                onDelete: { deleteCaption(caption.id) })
                        }

                        if selectedID != nil, isMine, !gestureHintSeen { gestureHint }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .coordinateSpace(name: CaptionStickerView.stageSpace)
                    .sensoryFeedback(.alignment, trigger: snappedToCentre) { _, now in now }
                }
            }
        }
    }

    private var centreGuide: some View {
        Rectangle()
            .fill(.white.opacity(0.85))
            .frame(width: 1)
            .padding(.vertical, 12)
            .allowsHitTesting(false)
            .transition(.opacity)
    }

    private var gestureHint: some View {
        VStack {
            Spacer(minLength: 0)
            Text(Strings.captionGestureHint)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(.bottom, 12)
        }
        .allowsHitTesting(false)
        .accessibilityIdentifier("caption-gesture-hint")
    }


    @ViewBuilder
    private var chrome: some View {
        cardLayout
    }

    private var bottomControls: some View {
        VStack(spacing: 9) {
            if !isMine { byline }
            if isMine, let target {
                tintRows(for: target)
                plateRow(for: target)
            }
            buttonRow
        }
        .opacity(editingCaption ? 0 : 1)
        .allowsHitTesting(!editingCaption)
        .animation(OneDay.Motion.soft, value: editingCaption)
    }

    private var byline: some View {
        HStack(spacing: 8) {
            Text(isMine ? "" : (authorName ?? ""))
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
            Spacer(minLength: 4)
            if let timeText {
                Text(timeText)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
    }

    private func tintRows(for caption: Caption) -> some View {
        let sticker = caption.placed
        return VStack(spacing: 7) {
            ForEach(Array(tintPages.enumerated()), id: \.offset) { _, page in
                HStack(spacing: 7) {
                    ForEach(page) { tint in
                        Button {
                            saveSticker(
                                sticker.reshaped(
                                    style: CaptionSticker.legibleStyle(
                                        picking: tint, keeping: sticker.style),
                                    tint: tint),
                                for: caption.id)
                        } label: {
                            Circle()
                                .fill(tint.color)
                                .frame(height: 26)
                                .frame(maxWidth: .infinity)
                                .overlay {
                                    Circle()
                                        .strokeBorder(.white.opacity(0.55), lineWidth: 1)
                                        .frame(width: 26, height: 26)
                                    if tint == sticker.tint {
                                        Circle()
                                            .strokeBorder(Color.oneDayBrand, lineWidth: 2.5)
                                            .frame(width: 33, height: 33)
                                    }
                                }
                                .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Strings.captionTintName(tint))
                        .accessibilityAddTraits(tint == sticker.tint ? .isSelected : [])
                    }
                }
            }
        }
        .accessibilityIdentifier("caption-tints")
    }

    private var tintPages: [[CaptionSticker.Tint]] {
        let all = CaptionSticker.Tint.allCases
        return stride(from: 0, to: all.count, by: 6).map {
            Array(all[$0..<min($0 + 6, all.count)])
        }
    }

    private func plateRow(for caption: Caption) -> some View {
        let sticker = caption.placed
        return HStack(spacing: 7) {
            ForEach(CaptionSticker.Style.picker) { style in
                let chosen = style == sticker.style.pickerEquivalent
                let sample = CaptionSticker(
                    x: 0.5, y: 0.5, style: style,
                    tint: CaptionSticker.legibleTint(
                        picking: style, keeping: sticker.tint))
                Button {
                    saveSticker(sticker.reshaped(style: style, tint: sample.tint), for: caption.id)
                } label: {
                    Text(Strings.captionPlateSample)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(sample.tint.color)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background {
                            if let fill = sample.plateColor, let plate = style.plate {
                                RoundedRectangle(
                                    cornerRadius: 30 * plate.radius, style: .continuous
                                )
                                .fill(fill)
                            } else {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(.white.opacity(0.1))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .strokeBorder(
                                                .white.opacity(0.4),
                                                style: StrokeStyle(lineWidth: 1, dash: [3.5, 3]))
                                    }
                            }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(
                                    chosen
                                        ? AnyShapeStyle(Color.oneDayBrand)
                                        : AnyShapeStyle(.white.opacity(0.2)),
                                    lineWidth: chosen ? 2.5 : 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Strings.captionPlateName(style))
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .accessibilityIdentifier("caption-plates")
    }

    private var buttonRow: some View {
        HStack(spacing: 7) {
            if isMine, canWrite {
                actionButton(
                    "text.badge.plus", Strings.captionAction,
                    accented: !isShared && sendActions.isEmpty,
                    identifier: "moment-caption",
                    action: startNewCaption)
            }
            if isMine {
                if let onReRecord {
                    actionButton(
                        "arrow.counterclockwise", Strings.rerecordShort,
                        accented: false, identifier: "moment-rerecord", action: onReRecord)
                }
                if let onAddTake {
                    actionButton(
                        "plus.rectangle.on.rectangle", Strings.addTakeShort,
                        accented: false, identifier: "moment-add-take", action: onAddTake)
                }
            }
            ForEach(sendActions) { extra in
                actionButton(
                    extra.symbol, extra.title, accented: extra.id == sendActions.first?.id,
                    identifier: extra.id, action: extra.action)
            }
        }
    }

    private var sendActions: [ExtraAction] { extraActions.filter { !$0.isDestructive } }

    private func actionButton(
        _ symbol: String, _ title: String, accented: Bool, identifier: String,
        badge: Int? = nil, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let badge {
                    Text("\(badge)")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(accented ? OneDay.onBrand.opacity(0.85) : .white.opacity(0.7))
                }
            }
            .foregroundStyle(accented ? OneDay.onBrand : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                if accented {
                    Capsule().fill(OneDay.brandHorizontal)
                } else {
                    ZStack {
                        Capsule().fill(.ultraThinMaterial)
                        Capsule().fill(.black.opacity(0.18))
                    }
                    .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1))
                    .environment(\.colorScheme, .dark)
                }
            }
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private var top: some View {
        ZStack {
            positionChip
            HStack {
                IconBubble(systemName: "xmark", overVideo: true) { commitCaption(); dismiss() }
                    .accessibilityLabel(Strings.close)
                    .accessibilityIdentifier("moment-close")
                Spacer(minLength: 0)
                topTrailing
            }
        }
    }

    @ViewBuilder
    private var topTrailing: some View {
        if editingCaption {
            Button(action: commitCaption) {
                Text(Strings.done)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(OneDay.onBrand)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(OneDay.brandHorizontal))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("caption-done")
        } else {
            HStack(spacing: 8) {
                if isShared {
                    IconBubble(systemName: "bubble.left.fill", label: Strings.chatShort, overVideo: true) {
                        showComments = true
                    }
                    .overlay(alignment: .topTrailing) {
                        if !comments.isEmpty {
                            Text("\(comments.count)")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(OneDay.onBrand)
                                .padding(.horizontal, 5)
                                .frame(minWidth: 17, minHeight: 17)
                                .background(Capsule().fill(Color.oneDayBrand))
                                .offset(x: 2, y: -2)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityIdentifier("moment-chat")
                }
                let destructive = extraActions.filter(\.isDestructive)
                if !destructive.isEmpty {
                    Menu {
                        ForEach(destructive) { extra in
                            Button(role: .destructive, action: extra.action) {
                                Label(extra.title, systemImage: extra.symbol)
                            }
                            .accessibilityIdentifier(extra.id)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(.black.opacity(0.32), in: Circle())
                    }
                    .accessibilityLabel(Strings.moreLabel)
                    .accessibilityIdentifier("moment-more")
                }
            }
        }
    }

    @ViewBuilder
    private var positionChip: some View {
        let parts = [
            momentCount > 0 ? "\(day) / \(momentCount)" : nil,
            showsPrompt ? localizedMomentTitle : nil,
        ].compactMap { $0 }

        if !parts.isEmpty {
            Text(parts.joined(separator: "  ·  "))
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.black.opacity(0.34), in: Capsule())
                .padding(.horizontal, 54)
        }
    }


    private var commentsSheet: some View {
        Group {
            if let challengeID {
                RoomChatView(
                    challengeID: challengeID,
                    moment: day)
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color.oneDayMist)
    }


    private func startNewCaption() {
        guard canWrite else { return }
        captionDraft = ""
        editingID = UUID()
        editingIsNew = true
        beginTyping()
    }

    private func startEditing(_ id: UUID) {
        guard let caption = liveCaptions.first(where: { $0.id == id }) else { return }
        captionDraft = caption.text
        editingID = id
        editingIsNew = false
        beginTyping()
    }

    private func beginTyping() {
        editingCaption = true
        captionFocused = true
        selectedID = nil
    }

    private func saveCaption() {
        editingCaption = false
        guard canWrite, let id = editingID else { return }
        let text = captionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        captionDraft = ""
        editingID = nil
        var list = liveCaptions
        if editingIsNew {
            guard !text.isEmpty else { return }
            list.append(Caption(id: id, text: text, sticker: Self.placement(after: list)))
        } else if let i = list.firstIndex(where: { $0.id == id }) {
            if text.isEmpty {
                list.remove(at: i)
            } else {
                list[i].text = text
            }
        }
        writeCaptions(list)
    }

    static func placement(after list: [Caption]) -> CaptionSticker? {
        let shown = list.drawable
        guard let last = shown.last?.placed else { return nil }
        let bands: [Double] = [0.62, 0.25, 0.78, 0.15, 0.5]
        let taken = shown.map(\.placed.y)
        let y = bands.first { band in taken.allSatisfy { abs($0 - band) > 0.1 } }
            ?? bands[shown.count % bands.count]
        return CaptionSticker(x: 0.5, y: y, style: last.style, tint: last.tint)
    }

    private func commitCaption() {
        captionFocused = false
        if editingCaption { saveCaption() }
    }

    private func limitCaptionLines(old: String, new text: String) {
        guard editingCaption else { return }
        let breaks = { (s: String) in s.filter { $0 == "\n" }.count }
        if text.count == old.count + 1, breaks(text) > breaks(old) {
            captionDraft = old
            commitCaption()
            return
        }
        let parts = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard parts.count > 2 else { return }
        captionDraft = String(parts[0]) + "\n" + parts[1...].joined()
        commitCaption()
    }

    private func tapCaption(_ id: UUID) {
        guard isMine, canWrite else { return }
        if selectedID == id {
            gestureHintSeen = true
            startEditing(id)
        } else {
            withAnimation(OneDay.Motion.soft) { selectedID = id }
        }
    }

    private func deselectCaption() {
        withAnimation(OneDay.Motion.soft) { selectedID = nil }
        gestureHintSeen = true
    }

    private func deleteCaption(_ id: UUID) {
        guard canWrite else { return }
        var list = liveCaptions
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        let removed = DeletedCaption(caption: list.remove(at: i), index: i)
        writeCaptions(list)
        withAnimation(OneDay.Motion.soft) {
            deleted = removed
            selectedID = nil
        }
        gestureHintSeen = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if deleted == removed {
                withAnimation(OneDay.Motion.soft) { deleted = nil }
            }
        }
    }

    private var undoToast: some View {
        VStack {
            Spacer(minLength: 0)
            HStack(spacing: 14) {
                Text(Strings.captionDeleted)
                    .font(.subheadline.weight(.semibold))
                Button(Strings.undo) {
                    guard let deleted else { return }
                    var list = liveCaptions
                    list.insert(deleted.caption, at: min(deleted.index, list.count))
                    writeCaptions(list)
                    withAnimation(OneDay.Motion.soft) { self.deleted = nil }
                }
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(Color.oneDaySky)
                .frame(minHeight: 44)
                .accessibilityIdentifier("caption-undo")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .background(.black.opacity(0.75), in: Capsule())
            .padding(.bottom, 130)
        }
        .transition(.opacity)
    }
}


private struct CaptionStickerView: View {
    let caption: Caption
    let stageSize: CGSize
    let isSelected: Bool
    let isMine: Bool
    @Binding var snappedToCentre: Bool
    let onTap: () -> Void
    let onChange: (CaptionSticker) -> Void
    let onDelete: () -> Void

    @State private var drag: CGSize = .zero
    @State private var pinch: CGFloat = 1
    @State private var twist: Double = 0
    @State private var handleScale: CGFloat = 1
    @State private var handleTwist: Double = 0

    static let stageSpace = "caption-stage"

    private var sticker: CaptionSticker { caption.placed }

    var body: some View {
        captionText
            .overlay {
                if isSelected, isMine { selectionChrome }
            }
            .frame(maxWidth: stageSize.width * 0.76)
            .scaleEffect(pinch * handleScale)
            .rotationEffect(.degrees(sticker.angle + twist + handleTwist))
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .position(
                x: (sticker.x + dragFraction.x) * stageSize.width,
                y: (sticker.y + dragFraction.y) * stageSize.height)
            .gesture(isMine ? shape : nil)
            .animation(nil, value: drag)
            .animation(nil, value: pinch)
            .animation(nil, value: twist)
            .animation(nil, value: handleScale)
            .animation(nil, value: handleTwist)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("caption-sticker")
    }

    private var captionText: some View {
        let minEdge = min(stageSize.width, stageSize.height)
        let base = minEdge * (sticker.style == .headline ? 0.092 : 0.062)
        let fontSize = base * sticker.scale
        return Text(caption.trimmedText ?? "")
            .font(.system(
                size: fontSize,
                weight: sticker.style == .headline ? .heavy : .bold,
                design: .rounded))
            .foregroundStyle(sticker.tint.color)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.68)
            .padding(.horizontal, (sticker.style.plate?.padH ?? 0) * fontSize)
            .padding(.vertical, (sticker.style.plate?.padV ?? 0) * fontSize)
            .background {
                if let plate = sticker.style.plate, let fill = sticker.plateColor {
                    RoundedRectangle(
                        cornerRadius: fontSize * (1 + plate.padV * 2) * plate.radius,
                        style: .continuous
                    )
                    .fill(fill)
                }
            }
            .shadow(
                color: .black.opacity(sticker.style.plate == nil ? 0.28 : 0),
                radius: 5, y: 2)
            .accessibilityIdentifier("caption-text")
    }

    private var selectionChrome: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(
                .white.opacity(0.92),
                style: StrokeStyle(lineWidth: 1.2, dash: [4.5, 3.5]))
            .padding(-9)
            .overlay(alignment: .topLeading) {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(Color(uiColor: UIColor(hex: 0x0F2E6B)))
                        .frame(width: 28, height: 28)
                        .background(.white, in: Circle())
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(x: -22, y: -22)
                .accessibilityLabel(Strings.deleteCaptionAction)
                .accessibilityIdentifier("caption-delete")
            }
            .overlay(alignment: .topTrailing) { handleDot.offset(x: 4, y: -14) }
            .overlay(alignment: .bottomLeading) { handleDot.offset(x: -14, y: 4) }
            .overlay(alignment: .bottomTrailing) {
                handleDot
                    .offset(x: 4, y: 4)
                    .gesture(cornerDrag)
                    .accessibilityLabel(Strings.captionResizeHandle)
                    .accessibilityIdentifier("caption-handle")
            }
    }

    private var handleDot: some View {
        Circle()
            .fill(.white)
            .frame(width: 11, height: 11)
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .contentShape(Circle().scale(2.6))
    }

    private var shape: some Gesture {
        SimultaneousGesture(
            dragGesture,
            SimultaneousGesture(
                MagnifyGesture()
                    .onChanged { pinch = $0.magnification }
                    .onEnded { value in
                        pinch = 1
                        onChange(sticker.reshaped(scale: sticker.scale * value.magnification))
                    },
                RotateGesture()
                    .onChanged { twist = $0.rotation.degrees }
                    .onEnded { value in
                        twist = 0
                        onChange(sticker.reshaped(angle: sticker.angle + value.rotation.degrees))
                    }))
    }

    private var dragFraction: (x: Double, y: Double) {
        guard stageSize.width > 0, stageSize.height > 0 else { return (0, 0) }
        return (drag.width / stageSize.width, drag.height / stageSize.height)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard stageSize.width > 0 else {
                    drag = value.translation
                    return
                }
                let wanted = sticker.x + value.translation.width / stageSize.width
                if let snapped = CaptionGestureMath.snapToCentre(wanted) {
                    drag = CGSize(
                        width: (snapped - sticker.x) * stageSize.width,
                        height: value.translation.height)
                    snappedToCentre = true
                } else {
                    drag = value.translation
                    snappedToCentre = false
                }
            }
            .onEnded { value in
                let moved = dragFraction
                let wasSnapped = snappedToCentre
                drag = .zero
                snappedToCentre = false
                guard abs(value.translation.width) + abs(value.translation.height) > 2
                else { return }
                onChange(sticker.reshaped(
                    x: wasSnapped ? 0.5 : sticker.x + moved.x,
                    y: sticker.y + moved.y))
            }
    }

    private var cornerDrag: some Gesture {
        DragGesture(coordinateSpace: .named(Self.stageSpace))
            .onChanged { value in
                guard let move = CaptionGestureMath.cornerDrag(
                    centre: CGPoint(
                        x: sticker.x * stageSize.width, y: sticker.y * stageSize.height),
                    start: value.startLocation,
                    current: value.location)
                else { return }
                handleScale = move.scale
                handleTwist = move.angleDelta
            }
            .onEnded { _ in
                let grown = sticker.scale * handleScale
                let turned = sticker.angle + handleTwist
                handleScale = 1
                handleTwist = 0
                onChange(sticker.reshaped(scale: grown, angle: turned))
            }
    }
}

extension CaptionSticker {
    func reshaped(
        x: Double? = nil, y: Double? = nil,
        style: Style? = nil,
        scale: Double? = nil, angle: Double? = nil,
        tint: Tint? = nil
    ) -> CaptionSticker {
        CaptionSticker(
            x: x ?? self.x,
            y: y ?? self.y,
            style: style ?? self.style,
            scale: scale ?? self.scale,
            angle: angle ?? self.angle,
            tint: tint ?? self.tint)
    }
}
