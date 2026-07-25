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
    @State private var withFriends = false
    @State private var creating = false
    @State private var errorText: String?
    @State private var showSignIn = false
    @State private var showBuildTemplate = false
    @State private var carouselIndex = 0
    @State private var carouselPosition: Int?
    @State private var litDays = 0
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
                    DayDots(litDays: litDays)
                    formatPicker
                    ClipLengthPicker(selection: $clipLength)
                    goalField
                    templateCarousel
                    AudiencePicker(withFriends: $withFriends)
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
        .onAppear {
            for day in 1...7 {
                withAnimation(.spring(duration: 0.5).delay(0.15 * Double(day))) {
                    litDays = day
                }
            }
        }
    }

    // MARK: - Sections kept inline (they drive local state)

    private var formatPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            FormSectionHeader(text: Strings.formatHeader)

            Picker("Format", selection: $challengeMode) {
                Text(Strings.modeOneDay).tag(Challenge.Mode.oneDay)
                Text(Strings.modeSevenDay).tag(Challenge.Mode.sevenDay)
            }
            .pickerStyle(.segmented)
            .tint(Color.oneDayBlue)
            .onChange(of: challengeMode) { _, _ in
                selectedTemplate = nil
                title = ""
                carouselIndex = 0
                carouselPosition = 0
            }
        }
    }

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

    /// Immersive swipeable script picker: one big card at a time instead of a
    /// flat grid, each tinted by the template's own identity color (reusing
    /// `Identity` — no real per-template footage to show, so an accent color
    /// + big type stands in for it).
    private var templateCarousel: some View {
        VStack(alignment: .leading, spacing: 12) {
            FormSectionHeader(text: Strings.pickScriptHeader(oneDay: challengeMode == .oneDay))

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(templates.enumerated()), id: \.offset) { index, template in
                        TemplateCard(
                            template: template,
                            selected: selectedTemplate == template,
                            secondsLabel: clipLength.secondsLabel,
                            onTap: { select(template) },
                            onDelete: template.isCustom ? { delete(template) } : nil)
                            .containerRelativeFrame(.horizontal)
                            .id(index)
                    }
                    BuildYourOwnCard { showBuildTemplate = true }
                        .containerRelativeFrame(.horizontal)
                        .id(templates.count)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $carouselPosition)
            .frame(height: 300)
            .onChange(of: carouselPosition) { _, newValue in
                guard let newValue, templates.indices.contains(newValue) else { return }
                carouselIndex = newValue
                select(templates[newValue])
            }

            HStack(spacing: 6) {
                ForEach(0...templates.count, id: \.self) { index in
                    Circle()
                        .fill(index == carouselIndex ? Color.oneDayBlue : Color.oneDayBlue.opacity(0.22))
                        .frame(width: 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Helpers

    private func select(_ template: ChallengeTemplate) {
        selectedTemplate = template
        title = fullTitle(for: template)
        goalFocused = false
    }

    private func delete(_ template: ChallengeTemplate) {
        if selectedTemplate == template {
            selectedTemplate = nil
            title = ""
        }
        store.deleteCustomTemplate(template)
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
