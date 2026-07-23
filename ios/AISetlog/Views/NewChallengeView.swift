import SwiftUI

/// Full-screen challenge creation. Calls `onCreate` with the new id so the
/// home screen can navigate straight to its board.
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
                    Color.setlogMist.opacity(0.85),
                    Color.white,
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    dayDots
                    formatPicker
                    clipLengthPicker
                    goalField
                    templateGrid
                    audiencePicker
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
                    startButton
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
                    .foregroundStyle(Color.setlogBlue)
                    .padding(10)
                    .background(.white.opacity(0.94), in: Circle())
                    .shadow(color: Color.setlogBlue.opacity(0.12), radius: 12, y: 5)
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
            print("[newch] appeared, withFriends=\(withFriends)")
            for day in 1...7 {
                withAnimation(.spring(duration: 0.5).delay(0.15 * Double(day))) {
                    litDays = day
                }
            }
        }
        .onChange(of: withFriends) { _, v in
            print("[newch] withFriends changed → \(v)")
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(challengeMode == .oneDay
                ? "What's your\n1-day story?"
                : "What's your\n7-day story?")
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.setlogNavy)
            Text(challengeMode == .oneDay
                ? "7 moments, \(clipLength.secondsLabel) each. One tiny film tonight."
                : "\(clipLength.secondsLabel) a day. One film at the end.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 28)
    }

    private var dayDots: some View {
        HStack(spacing: 10) {
            ForEach(1...7, id: \.self) { day in
                ZStack {
                    Circle()
                        .fill(day <= litDays ? Color.setlogBlue : .white)
                        .frame(width: 34, height: 34)
                        .overlay(Circle().stroke(Color.setlogBlue.opacity(0.16), lineWidth: 1))
                    Text("\(day)")
                        .font(.footnote.bold())
                        .foregroundStyle(day <= litDays ? .white : Color.setlogBlue.opacity(0.62))
                }
                .scaleEffect(day == litDays ? 1.12 : 1)
            }
        }
    }

    private var goalField: some View {
        TextField(
            "", text: $title,
            prompt: Text(challengeMode == .oneDay ? "My 1-day story..." : "My 7-day goal...")
                .foregroundStyle(.secondary.opacity(0.75))
        )
        .font(.title3.weight(.semibold))
        .foregroundStyle(.primary)
        .tint(Color.setlogBlue)
        .focused($goalFocused)
        .padding(18)
        .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.setlogBlue.opacity(goalFocused ? 0.38 : 0.13), lineWidth: 1.5)
        )
        .shadow(color: Color.setlogBlue.opacity(0.08), radius: 16, y: 8)
        .onChange(of: title) { _, newValue in
            if selectedTemplate.map(fullTitle) != newValue { selectedTemplate = nil }
        }
    }

    private func fullTitle(for template: ChallengeTemplate) -> String {
        challengeMode == .sevenDay ? "7 Days of \(template.name)" : template.name
    }

    private var formatPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FORMAT")
                .font(.caption.bold())
                .foregroundStyle(Color.setlogBlue.opacity(0.62))
                .kerning(1.2)

            Picker("Format", selection: $challengeMode) {
                Text("1-Day").tag(Challenge.Mode.oneDay)
                Text("7-Day").tag(Challenge.Mode.sevenDay)
            }
            .pickerStyle(.segmented)
            .tint(Color.setlogBlue)
            .onChange(of: challengeMode) { _, _ in
                selectedTemplate = nil
                title = ""
                carouselIndex = 0
                carouselPosition = 0
            }
        }
    }

    private var clipLengthPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CLIP LENGTH")
                .font(.caption.bold())
                .foregroundStyle(Color.setlogBlue.opacity(0.62))
                .kerning(1.2)

            HStack(spacing: 10) {
                ForEach(Challenge.ClipLength.allCases) { length in
                    Button {
                        clipLength = length
                    } label: {
                        let selected = clipLength == length
                        VStack(alignment: .leading, spacing: 5) {
                            Text(length.secondsLabel)
                                .font(.title3.bold())
                            Text(length.displayName)
                                .font(.subheadline.bold())
                            Text(length.caption)
                                .font(.caption2.weight(.semibold))
                                .opacity(0.68)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                        .foregroundStyle(selected ? Color.setlogBlue : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            selected ? Color.setlogBlue.opacity(0.12) : .white.opacity(0.94),
                            in: RoundedRectangle(cornerRadius: 18)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(
                                    Color.setlogBlue.opacity(selected ? 0.9 : 0.12),
                                    lineWidth: selected ? 2 : 1)
                        )
                        .shadow(color: Color.setlogBlue.opacity(selected ? 0.12 : 0.06), radius: 12, y: 6)
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.selection, trigger: clipLength)
                }
            }
        }
    }

    /// Immersive swipeable script picker: one big card at a time instead of a
    /// flat grid, each tinted by the template's own identity color (reusing
    /// `Identity` — no real per-template footage to show, so an accent color
    /// + big type stands in for it).
    private var templateGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(challengeMode == .oneDay ? "PICK TODAY'S SCRIPT" : "OR PICK A VIBE")
                .font(.caption.bold())
                .foregroundStyle(Color.setlogBlue.opacity(0.62))
                .kerning(1.2)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(templates.enumerated()), id: \.offset) { index, template in
                        templateCard(template)
                            .containerRelativeFrame(.horizontal)
                            .id(index)
                    }
                    buildYourOwnCard
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
                selectedTemplate = templates[newValue]
                title = fullTitle(for: templates[newValue])
                goalFocused = false
            }

            HStack(spacing: 6) {
                ForEach(0...templates.count, id: \.self) { index in
                    Circle()
                        .fill(index == carouselIndex ? Color.setlogBlue : Color.setlogBlue.opacity(0.22))
                        .frame(width: 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func templateCard(_ template: ChallengeTemplate) -> some View {
        let tint = Identity.tint(for: template.name)
        let selected = selectedTemplate == template
        return VStack(spacing: 14) {
            Text(template.emoji)
                .font(.system(size: 52))
            Text(template.name)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            if let count = template.momentTitles?.count {
                Text("\(count) moments, \(clipLength.secondsLabel) each")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 0)
            Text(selected ? "Selected" : "Tap to select this script")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.white.opacity(selected ? 0.34 : 0.16), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 1))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [tint, tint.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .shadow(color: tint.opacity(0.35), radius: 16, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture {
            selectedTemplate = template
            title = fullTitle(for: template)
            goalFocused = false
        }
        .sensoryFeedback(.selection, trigger: selectedTemplate)
        .contextMenu {
            if template.isCustom {
                Button(role: .destructive) {
                    if selectedTemplate == template {
                        selectedTemplate = nil
                        title = ""
                    }
                    store.deleteCustomTemplate(template)
                } label: {
                    Label("Delete template", systemImage: "trash")
                }
            }
        }
    }

    private var buildYourOwnCard: some View {
        Button {
            showBuildTemplate = true
        } label: {
            VStack(spacing: 14) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.setlogBlue.opacity(0.7))
                Text("Build your own")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.primary)
                Text("Pick your own prompts")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(Color.setlogBlue.opacity(0.35))
            )
        }
        .buttonStyle(.plain)
    }

    private var audiencePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WHO'S IN")
                .font(.caption.bold())
                .foregroundStyle(Color.setlogBlue.opacity(0.62))
                .kerning(1.2)

            HStack(spacing: 12) {
                modeCard(
                    icon: "person.fill", label: "Just me",
                    caption: "A private week", selected: !withFriends
                ) { withFriends = false }
                modeCard(
                    icon: "person.2.fill", label: "With friends",
                    caption: "Room + invite code", selected: withFriends
                ) { withFriends = true }
            }
        }
    }

    private func modeCard(
        icon: String, label: String, caption: String,
        selected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.subheadline.bold())
                Text(caption)
                    .font(.caption)
                    .opacity(0.7)
            }
            .foregroundStyle(selected ? Color.setlogBlue : Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                selected ? Color.setlogBlue.opacity(0.12) : .white.opacity(0.94),
                in: RoundedRectangle(cornerRadius: 18)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.setlogBlue.opacity(selected ? 0.82 : 0.12),
                                  lineWidth: selected ? 2 : 1)
            )
            .shadow(color: Color.setlogBlue.opacity(selected ? 0.12 : 0.06), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
    }

    private var startButton: some View {
        return Button(action: start) {
            HStack {
                if creating {
                    ProgressView().tint(.white)
                } else {
                    Text(startButtonTitle)
                    Image(systemName: "arrow.right")
                }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.setlogBlue, in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: Color.setlogBlue.opacity(0.24), radius: 12, y: 6)
        }
        .disabled(!canSubmit)
        .animation(.easeOut(duration: 0.2), value: canSubmit)
    }

    private var hasTitle: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canSubmit: Bool {
        hasTitle && !creating
    }

    private var startButtonTitle: String {
        if withFriends { return "Create room" }
        return challengeMode == .oneDay ? "Start Moment 1" : "Start Day 1"
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
                templateName: selectedTemplate?.name,
                momentTitles: selectedTemplate?.momentTitles)
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
                    templateName: selectedTemplate?.name,
                    momentTitles: selectedTemplate?.momentTitles)
                dismiss()
                onCreate(challenge.id)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
