import SwiftUI

struct StoryComposerView: View {
    var onCreate: (UUID) -> Void = { _ in }
    var onClose: (() -> Void)? = nil
    var startsWithFriends = false

    @Environment(ChallengeStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    @State private var entry: ComposerEntry = .byTime
    private let days: Challenge.Mode = .oneDay
    private let clipLength: Challenge.ClipLength = .scene
    @State private var roomOrientation: Challenge.Orientation = .portrait
    private var orientation: Challenge.Orientation { withFriends ? roomOrientation : .portrait }
    private let cameraStyle = CameraStyle.defaultCamera
    @State private var withFriends = false
    @State private var title = ""
    @State private var titleEdited = false
    @State private var moments: [String] = []
    @State private var showGuided = false
    @State private var creating = false
    @State private var errorText: String?
    @State private var showSignIn = false

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var isTimeOnly: Bool { entry == .byTime }

    var body: some View {
        ZStack {
            OneDayCanvas(seed: 1)

            VStack(spacing: 0) {
                topBar
                page
                footer
            }
        }
        .sheet(isPresented: $showGuided) {
            GuidedMomentsView(initialMoments: moments, onDone: applyCustomDraft)
        }
        .sheet(isPresented: $showSignIn) {
            SignInView { createSharedRoom() }
                .presentationDetents([.medium])
        }
        .onAppear {
            withFriends = startsWithFriends
            entry = startsWithFriends ? .byTime : .writeList
            nameForTheDay()
        }
    }


    private var topBar: some View {
        HStack(spacing: 12) {
            IconBubble(systemName: "xmark") { leave() }
            Spacer()
            Color.clear.frame(width: 38, height: 38)
        }
        .padding(.horizontal, ComposerLayout.margin - 4)
        .padding(.top, 8)
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(withFriends ? Strings.newRoomRow : Strings.todaysPlanTitle)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                    .accessibilityIdentifier("composer-question")
                    .padding(.horizontal, ComposerLayout.margin)
                setup
                if withFriends {
                    RoomShapePicker(selection: $roomOrientation)
                        .padding(.horizontal, ComposerLayout.margin)
                }
            }
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private var setup: some View {
        SetupStep(
            title: $title,
            titleEdited: $titleEdited,
            isOneDay: days == .oneDay,
            listCount: entry == .writeList ? resolvedMoments?.count ?? 0 : nil,
            onOpenList: openList)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let errorText {
                footerNote(errorText, systemImage: "exclamationmark.circle.fill", color: .red)
            }
            startButton
        }
        .padding(.horizontal, ComposerLayout.margin)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .animation(OneDay.Motion.soft, value: errorText)
    }

    private func footerNote(_ text: String, systemImage: String? = nil, color: Color) -> some View {
        Group {
            if let systemImage {
                Label(text, systemImage: systemImage)
            } else {
                Text(text)
            }
        }
        .font(.system(size: 13, weight: .medium, design: .rounded))
        .foregroundStyle(color)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }

    private var startButton: some View {
        Button(action: start) {
            HStack(spacing: 8) {
                if creating {
                    ProgressView().tint(.white)
                } else {
                    Text(withFriends ? Strings.createRoom : Strings.startFilmingCTA)
                    Image(systemName: "sparkles")
                }
            }
        }
        .buttonStyle(.primaryAction)
        .disabled(!canStart)
        .opacity(canStart ? 1 : 0.55)
        .accessibilityIdentifier("composer-start")
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canStart: Bool {
        !trimmedTitle.isEmpty && !creating && (isTimeOnly || resolvedMoments?.isEmpty == false)
    }


    private func openList() {
        showGuided = true
    }

    private func applyCustomDraft(_ draft: CustomStoryDraft) {
        entry = .writeList
        moments = draft.moments
        errorText = nil
        if !titleEdited, let name = draft.suggestedName {
            title = name
        }
    }


    private func leave() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func start() {
        guard canStart else { return }
        if withFriends {
            if account.isSignedIn { createSharedRoom() } else { showSignIn = true }
            return
        }
        creating = true
        let challenge = store.create(
            title: trimmedTitle,
            mode: days,
            clipLength: clipLength,
            orientation: orientation,
            cameraStyle: cameraStyle,
            templateName: isTimeOnly ? Challenge.timeOnlyTemplateName : nil,
            momentTitles: resolvedMoments)
        leave()
        onCreate(challenge.id)
    }

    private func createSharedRoom() {
        creating = true
        errorText = nil
        Task {
            defer { creating = false }
            do {
                let challenge = try await store.createSharedRoom(
                    title: trimmedTitle,
                    mode: days,
                    clipLength: clipLength,
                    orientation: orientation,
                    cameraStyle: cameraStyle,
                    templateName: isTimeOnly ? Challenge.timeOnlyTemplateName : nil,
                    momentTitles: resolvedMoments)
                leave()
                onCreate(challenge.id)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }


    private func nameForTheDay() {
        guard !titleEdited else { return }
        title = withFriends
            ? Strings.defaultRoomName(existingTitles: store.challenges.filter(\.isShared).map(\.title))
            : Strings.byTimeTitle(.now)
    }

    private var resolvedMoments: [String]? {
        if isTimeOnly { return nil }
        let cleaned = moments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return cleaned.isEmpty ? nil : cleaned
    }
}

private struct RoomShapePicker: View {
    @Binding var selection: Challenge.Orientation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: Strings.roomShapeLabel)
            HStack(spacing: 12) {
                option(.portrait, title: Strings.roomShapePortrait)
                option(.landscape, title: Strings.roomShapeLandscape)
            }
        }
    }

    private func option(_ orientation: Challenge.Orientation, title: String) -> some View {
        let picked = selection == orientation
        return Button {
            withAnimation(OneDay.Motion.soft) { selection = orientation }
        } label: {
            VStack(spacing: 10) {
                sketch(orientation)
                    .frame(height: 74)
                Text(title)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(OneDay.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(OneDay.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(picked ? Color.oneDayBrand : OneDay.hairline, lineWidth: picked ? 2.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? .isSelected : [])
        .accessibilityIdentifier("room-shape-\(orientation.rawValue)")
    }

    @ViewBuilder
    private func sketch(_ orientation: Challenge.Orientation) -> some View {
        let fill = (selection == orientation ? Color.oneDayBrand : OneDay.inkFaint).opacity(0.55)
        if orientation == .landscape {
            VStack(spacing: 5) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(fill)
                        .aspectRatio(16 / 9, contentMode: .fit)
                }
            }
        } else {
            HStack(spacing: 5) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(fill)
                        .aspectRatio(3 / 4, contentMode: .fit)
                }
            }
        }
    }
}
