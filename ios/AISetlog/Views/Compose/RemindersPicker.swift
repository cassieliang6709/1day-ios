import SwiftUI
import UIKit

/// The sheet behind 从提醒事项导入: unfinished reminders, today's first. Tick
/// some, 加入 copies their titles into the list. `room` is how many more
/// the list can take.
struct RemindersPicker: View {
    let room: Int
    let onAdd: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    @State private var outcome: RemindersImport.Outcome?
    @State private var picked: [String] = []

    var body: some View {
        NavigationStack {
            ZStack {
                OneDayCanvas(seed: 3)
                content
            }
            .navigationTitle(Strings.remindersTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.remindersAdd(picked.count)) {
                        onAdd(picked.compactMap(title(of:)))
                        dismiss()
                    }
                    .disabled(picked.isEmpty)
                    .accessibilityIdentifier("reminders-add")
                }
            }
            .task { outcome = await RemindersImport.load() }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder private var content: some View {
        switch outcome {
        case nil:
            ProgressView()
        case .noAccess:
            VStack(spacing: 14) {
                Text(Strings.remindersNoAccess)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
                Button(Strings.openSettings) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.primaryAction)
                .fixedSize()
            }
        case .items(let items) where items.isEmpty:
            Text(Strings.remindersEmpty)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(OneDay.inkSoft)
        case .items(let items):
            List(items) { item in
                row(item)
                    .listRowBackground(OneDay.surface)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(_ item: RemindersImport.Item) -> some View {
        let isPicked = picked.contains(item.id)
        let isFull = !isPicked && picked.count >= room
        return Button {
            if isPicked { picked.removeAll { $0 == item.id } } else if !isFull { picked.append(item.id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isPicked ? Color.oneDayBrand : OneDay.inkFaint)
                Text(item.title)
                    .font(.system(size: 15.5, weight: .medium, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isFull ? 0.4 : 1)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
        .accessibilityIdentifier("reminder-row")
    }

    /// Picked in the order tapped, so the list gets them in that order.
    private func title(of id: String) -> String? {
        if case .items(let items) = outcome { return items.first { $0.id == id }?.title }
        return nil
    }
}
