import SwiftUI

/// Lets a user assemble their own template by picking any number of prompts
/// from the pool of every built-in template's moments, then optionally
/// dragging them into a custom order before saving. Works for both 1-day
/// moments and 7-day themes — the same short prompts read fine either way.
struct BuildTemplateView: View {
    var onSave: (ChallengeTemplate) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Source of truth for both membership and order. Defaults to pool order;
    /// once the user drags (`hasManuallyOrdered`), new picks just append.
    @State private var selected: [String] = []
    @State private var hasManuallyOrdered = false
    @State private var name = ""
    @State private var emoji = "🎬"
    @FocusState private var nameFocused: Bool

    private let pool = ChallengeTemplate.promptPool

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.white, Color.setlogMist.opacity(0.85), Color.white],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                List {
                    Section {
                        headerCard
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    if !selected.isEmpty {
                        Section {
                            ForEach(Array(selected.enumerated()), id: \.element) { index, prompt in
                                orderRow(index: index, prompt: prompt)
                            }
                            .onMove(perform: move)
                        } header: {
                            Text("YOUR ORDER (\(selected.count))")
                                .font(.caption.bold())
                                .foregroundStyle(Color.setlogBlue.opacity(0.62))
                                .kerning(1.2)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }

                    Section {
                        FlowLayout(spacing: 8) {
                            ForEach(pool, id: \.self) { prompt in
                                promptChip(prompt)
                            }
                        }
                    } header: {
                        Text("PROMPT POOL")
                            .font(.caption.bold())
                            .foregroundStyle(Color.setlogBlue.opacity(0.62))
                            .kerning(1.2)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 20, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .sensoryFeedback(.impact(weight: .medium), trigger: selected.count)
            }
            .navigationTitle("Build your own")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .fontWeight(.bold)
                }
                if !selected.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        EditButton()
                    }
                }
            }
        }
    }

    // MARK: - Pieces

    private var headerCard: some View {
        HStack(spacing: 12) {
            TextField("🎬", text: $emoji)
                .font(.title2)
                .frame(width: 44)
                .multilineTextAlignment(.center)
                .onChange(of: emoji) { _, new in
                    if new.count > 1 { emoji = String(new.suffix(1)) }
                }
            TextField(
                "", text: $name,
                prompt: Text("Name your template").foregroundStyle(.secondary.opacity(0.75))
            )
            .font(.title3.weight(.semibold))
            .focused($nameFocused)
        }
        .padding(16)
        .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.setlogBlue.opacity(nameFocused ? 0.38 : 0.13), lineWidth: 1.5)
        )
        .shadow(color: Color.setlogBlue.opacity(0.08), radius: 16, y: 8)
    }

    private func orderRow(index: Int, prompt: String) -> some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.setlogBlue, in: Circle())
            Text(prompt)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button {
                toggle(prompt)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary.opacity(0.5))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.setlogBlue.opacity(0.12), lineWidth: 1)
        )
    }

    private func promptChip(_ prompt: String) -> some View {
        let isSelected = selected.contains(prompt)
        return Button {
            toggle(prompt)
        } label: {
            Text(prompt)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? .white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    isSelected ? Color.setlogBlue : .white.opacity(0.94),
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(Color.setlogBlue.opacity(isSelected ? 0 : 0.2), lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }

    // MARK: - State

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !selected.isEmpty
    }

    private func toggle(_ prompt: String) {
        if let idx = selected.firstIndex(of: prompt) {
            selected.remove(at: idx)
        } else {
            selected.append(prompt)
            if !hasManuallyOrdered {
                selected.sort { poolIndex($0) < poolIndex($1) }
            }
        }
    }

    private func move(from: IndexSet, to: Int) {
        selected.move(fromOffsets: from, toOffset: to)
        hasManuallyOrdered = true
    }

    private func poolIndex(_ prompt: String) -> Int {
        pool.firstIndex(of: prompt) ?? Int.max
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespaces)
        let template = ChallengeTemplate(
            emoji: trimmedEmoji.isEmpty ? "🎬" : trimmedEmoji,
            name: trimmedName,
            momentTitles: selected,
            isCustom: true)
        onSave(template)
        dismiss()
    }
}

/// Wraps children onto multiple lines, left-to-right, like text — used for
/// the prompt pool "tag cloud" instead of a fixed grid.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var origin = CGPoint.zero
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x + size.width > maxWidth, origin.x > 0 {
                origin.x = 0
                origin.y += rowHeight + spacing
                rowHeight = 0
            }
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalHeight = origin.y + rowHeight
        }
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var origin = bounds.origin
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x + size.width > bounds.maxX, origin.x > bounds.minX {
                origin.x = bounds.minX
                origin.y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: origin, proposal: .unspecified)
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
