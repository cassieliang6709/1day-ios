import SwiftUI

/// Making today's plan, or a room — two pages from two doors (1.5).
///
/// From 我的 it's a plan: a name and today's list, then 开始拍. One plan a
/// day — once there is one, 新建 opens it instead (`RootShellView`).
/// From 朋友 it's a room: a name, then 创建房间 and the code. A room has no
/// list: everyone films whenever, and the order is settled in the film.
///
/// 写今天的清单 opens the list editor (`GuidedMomentsView`) — typed by hand or
/// drafted by AI from one sentence, in the same page; the page shows it folded
/// to one 清单 · N 项 row. Templates (从模板开始, 存为我的模板, the posters)
/// are gone (1.5).
struct StoryComposerView: View {
    var onCreate: (UUID) -> Void = { _ in }
    /// How to leave. Nil means "I was presented, dismiss me" — the sheet path.
    /// `RootShellView` passes a closure instead, because as the 新建 surface
    /// this view has no presentation to dismiss and `dismiss()` is a no-op.
    var onClose: (() -> Void)? = nil
    /// A room (the 朋友 tab's 新建) rather than a plan (我的's). Fixed: the
    /// page doesn't switch between the two.
    var startsWithFriends = false

    @Environment(ChallengeStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    /// 写今天的清单 or 按时间拍.
    @State private var entry: ComposerEntry = .byTime
    /// No longer asked: 一日 / 7 日 is gone from the page, every new story is one day.
    private let days: Challenge.Mode = .oneDay
    /// No longer asked (1.5): with hold-to-record a length is only a ceiling,
    /// and the camera you pick already decides the frame's shape.
    private let clipLength: Challenge.ClipLength = .scene
    private let orientation: Challenge.Orientation = .portrait
    /// No longer asked (1.5): there is one camera.
    private let cameraStyle = CameraStyle.defaultCamera
    @State private var withFriends = false
    @State private var title = ""
    /// Set once the user edits the name, so the date name 按时间拍 gives stops
    /// overwriting what they typed.
    @State private var titleEdited = false
    /// The story's moments: whatever the list editor last handed back.
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

    // MARK: - Layout

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
            // Above the button: the reason a tap did nothing has to be on
            // screen when the tap happens.
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

    // MARK: - Choices

    private func openList() {
        showGuided = true
    }

    /// What the list editor wrote, applied to this story. The name only
    /// follows the AI's suggestion while the user hasn't typed one.
    private func applyCustomDraft(_ draft: CustomStoryDraft) {
        entry = .writeList
        moments = draft.moments
        errorText = nil
        // The AI's name replaces the date name, until the user types one.
        if !titleEdited, let name = draft.suggestedName {
            title = name
        }
    }

    // MARK: - Actions

    /// Leaving, whichever way this view got on screen. See `onClose`.
    private func leave() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func start() {
        // `dismiss()` isn't instant, so a second tap inside the closing
        // animation used to insert a second story.
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

    // MARK: - Derived state

    /// Named for the date until the user types a name of their own.
    private func nameForTheDay() {
        guard !titleEdited else { return }
        title = Strings.byTimeTitle(.now)
    }

    /// Blank rows are dropped. Nil for 按时间拍, which has no list.
    private var resolvedMoments: [String]? {
        if isTimeOnly { return nil }
        let cleaned = moments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return cleaned.isEmpty ? nil : cleaned
    }
}
