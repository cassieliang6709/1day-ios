import SwiftUI

struct StoryComposerView: View {
    var onCreate: (UUID) -> Void = { _ in }
    var onClose: (() -> Void)? = nil
    var startsWithFriends = false
    var compact = false

    @Environment(ChallengeStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    @State private var entry: ComposerEntry = .byTime
    private let days: Challenge.Mode = .oneDay
    private let clipLength: Challenge.ClipLength = .scene
    private let orientation: Challenge.Orientation = .portrait
    private let cameraStyle = CameraStyle.defaultCamera
    @State private var withFriends = false
    @State private var title = ""
    @State private var titleEdited = false
    @State private var moments: [String] = []
    @State private var showGuided = false
    @State private var creating = false
    @State private var errorText: String?
    @State private var showSignIn = false
    @State private var compactHeight: CGFloat = 280

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var isTimeOnly: Bool { entry == .byTime }

    var body: some View {
        content
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


    @ViewBuilder
    private var content: some View {
        if compact {
            VStack(alignment: .leading, spacing: OneDay.Space.l) {
                Text(withFriends ? Strings.newRoomRow : Strings.todaysPlanTitle)
                    .font(OneDay.Font.title)
                    .foregroundStyle(OneDay.ink)
                    .padding(.horizontal, ComposerLayout.margin)
                    .accessibilityIdentifier("composer-question")
                setup
                footer
            }
            .padding(.top, OneDay.Space.xl)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { compactHeight = $0 }
            .frame(maxHeight: .infinity, alignment: .top)
            .presentationDetents([.height(compactHeight)])
            .presentationDragIndicator(.visible)
            .presentationBackground(OneDay.surface)
        } else {
            ZStack {
                OneDayCanvas(seed: 1)
                VStack(spacing: 0) {
                    topBar
                    page
                    footer
                }
            }
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
