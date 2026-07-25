import SwiftUI

/// Full-screen challenge creation. Calls `onCreate` with the new id so the
/// home screen can navigate straight to its board. Section UI lives in
/// `NewChallengeComponents.swift`; this file owns state and actions.
struct NewChallengeView: View {
    var onCreate: (UUID) -> Void = { _ in }

    @Environment(ChallengeStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var selectedTemplate: ChallengeTemplate?
    @State private var challengeMode: Challenge.Mode = .oneDay
    @State private var clipLength: Challenge.ClipLength = .tiny
    @State private var orientation: Challenge.Orientation = .portrait
    @State private var withFriends = false
    @State private var creating = false
    @State private var errorText: String?
    @State private var showSignIn = false
    @State private var showBuildTemplate = false
    @FocusState private var goalFocused: Bool

    /// Bound only so a language change re-renders the view.
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var templates: [ChallengeTemplate] {
        let builtins = challengeMode == .oneDay
            ? ChallengeTemplate.oneDayBuiltins
            : ChallengeTemplate.sevenDayBuiltins
        return builtins + store.customTemplates
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.white,
                    Color.oneDayMist.opacity(0.85),
                    Color.white,
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    NewChallengeHeader(
                        oneDay: challengeMode == .oneDay,
                        secondsLabel: clipLength.secondsLabel)
                    goalField
                    templateDeckSection
                    optionRows
                    if let errorText {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(24)
                .padding(.bottom, 112)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                if hasTitle || creating {
                    StartChallengeButton(
                        title: startButtonTitle,
                        creating: creating,
                        enabled: canSubmit,
                        action: start)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.oneDayBlue)
                    .padding(10)
                    .background(.white.opacity(0.94), in: Circle())
                    .shadow(color: Color.oneDayBlue.opacity(0.12), radius: 12, y: 5)
            }
            .padding(.trailing, 20)
        }
        .sheet(isPresented: $showSignIn) {
            SignInView { createSharedRoom() }
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showBuildTemplate) {
            BuildTemplateView { template in
                store.addCustomTemplate(template)
                selectedTemplate = template
                title = fullTitle(for: template)
            }
        }
    }

    // MARK: - Sections kept inline (they drive local state)

    private var goalField: some View {
        TextField(
            "", text: $title,
            prompt: Text(Strings.titlePrompt(oneDay: challengeMode == .oneDay))
                .foregroundStyle(.secondary.opacity(0.75))
        )
        .font(.title3.weight(.semibold))
        .foregroundStyle(.primary)
        .tint(Color.oneDayBlue)
        .focused($goalFocused)
        .padding(18)
        .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.oneDayBlue.opacity(goalFocused ? 0.38 : 0.13), lineWidth: 1.5)
        )
        .shadow(color: Color.oneDayBlue.opacity(0.08), radius: 16, y: 8)
        .onChange(of: title) { _, newValue in
            if selectedTemplate.map(fullTitle) != newValue { selectedTemplate = nil }
        }
    }

    /// The template picker: a fanned deck of cards instead of a carousel.
    /// Swiping (or tapping a back card) brings a template to the front and
    /// selects it, filling in the goal field.
    private var templateDeckSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FormSectionHeader(text: Strings.pickScriptHeader(oneDay: challengeMode == .oneDay))

            TemplateDeck(
                templates: templates,
                secondsLabel: clipLength.secondsLabel,
                oneDay: challengeMode == .oneDay,
                withFriends: withFriends,
                selectedTemplate: selectedTemplate
            ) { index in
                guard templates.indices.contains(index) else { return }
                select(templates[index])
            }
        }
    }

    /// Secondary choices as settings-style rows, matching the deck card style.
    private var optionRows: some View {
        VStack(spacing: 12) {
            FormListRow(
                icon: "plus",
                title: Strings.buildYourOwn,
                subtitle: Strings.pickYourPrompts
            ) {
                showBuildTemplate = true
            }
            FormListRow(
                icon: "timer",
                title: Strings.clipLengthHeader,
                subtitle: "\(clipLength.secondsLabel) · \(Strings.clipLengthName(clipLength))"
            ) {
                cycleClipLength()
            }
            FormListRow(
                icon: "calendar.day.timeline.leading",
                title: Strings.formatHeader,
                subtitle: challengeMode == .oneDay ? Strings.modeOneDay : Strings.modeSevenDay
            ) {
                toggleMode()
            }
            FormListRow(
                icon: orientation == .portrait ? "rectangle.portrait" : "rectangle",
                title: Strings.orientationHeader,
                subtitle: orientation == .portrait ? Strings.orientationPortrait : Strings.orientationLandscape
            ) {
                orientation = orientation == .portrait ? .landscape : .portrait
            }
            FormToggleRow(
                icon: "person.2.fill",
                title: Strings.withFriends,
                subtitle: Strings.roomInvite,
                isOn: $withFriends)
        }
    }

    // MARK: - Helpers

    private func select(_ template: ChallengeTemplate) {
        selectedTemplate = template
        title = fullTitle(for: template)
        goalFocused = false
    }

    private func cycleClipLength() {
        let all = Challenge.ClipLength.allCases
        let next = all[(all.firstIndex(of: clipLength) ?? 0) + 1 < all.count
            ? (all.firstIndex(of: clipLength) ?? 0) + 1 : 0]
        clipLength = next
    }

    private func toggleMode() {
        challengeMode = challengeMode == .oneDay ? .sevenDay : .oneDay
        selectedTemplate = nil
        title = ""
    }

    private func fullTitle(for template: ChallengeTemplate) -> String {
        let name = template.displayName
        guard challengeMode == .sevenDay else { return name }
        return Strings.fullTitle7Days(name)
    }

    private var hasTitle: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canSubmit: Bool {
        hasTitle && !creating
    }

    private var startButtonTitle: String {
        if withFriends { return Strings.createRoom }
        return challengeMode == .oneDay ? Strings.startMoment1 : Strings.startDay1
    }

    // MARK: - Actions

    private func start() {
        let name = title.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if withFriends {
            if account.isSignedIn { createSharedRoom() } else { showSignIn = true }
        } else {
            let challenge = store.create(
                title: name,
                mode: challengeMode,
                clipLength: clipLength,
                orientation: orientation,
                templateName: selectedTemplate?.displayName,
                momentTitles: selectedTemplate?.momentKeys)
            dismiss()
            onCreate(challenge.id)
        }
    }

    private func createSharedRoom() {
        creating = true
        errorText = nil
        Task {
            defer { creating = false }
            do {
                let challenge = try await store.createSharedRoom(
                    title: title.trimmingCharacters(in: .whitespaces),
                    mode: challengeMode,
                    clipLength: clipLength,
                    orientation: orientation,
                    templateName: selectedTemplate?.displayName,
                    momentTitles: selectedTemplate?.momentKeys)
                dismiss()
                onCreate(challenge.id)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
