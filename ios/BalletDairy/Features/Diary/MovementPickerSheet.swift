import SwiftUI

/// Tick off the movements practised today.
struct MovementPickerSheet: View {
    @Binding var selected: [String]
    @Environment(MovementLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var category: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22, pinnedViews: []) {
                    categoryChips
                    ForEach(sections) { section in
                        let cat = section.category, items = section.items
                        VStack(alignment: .leading, spacing: 8) {
                            Text(cat.name).font(Theme.display(20)).foregroundStyle(Theme.ink)
                                .padding(.horizontal, 20)
                            VStack(spacing: 0) {
                                ForEach(items) { m in
                                    row(m)
                                    if m.id != items.last?.id { Divider().overlay(Theme.rule).padding(.leading, 86) }
                                }
                            }
                            .paperCard(cornerRadius: 24, padding: 0)
                            .padding(.horizontal, 16)
                        }
                    }
                    if sections.isEmpty {
                        DoodleEmptyState(title: "No steps found", message: "Try the French or English name — “pas de chat”, “cat step”.")
                    }
                }
                .padding(.vertical, 12)
            }
            .background(PlainPaper())
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search tendu, pirouette, jeté…")
            .navigationTitle("Today's movements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("\(selected.count) chosen").font(Theme.hand(15)).foregroundStyle(Theme.inkSoft)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .buttonStyle(.glassProminent).tint(Theme.ribbon)
                }
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(34)
    }

    private struct Section: Identifiable {
        let category: MovementCategory
        let items: [Movement]
        var id: String { category.id }
    }

    private var sections: [Section] {
        library.categories
            .filter { category == nil || $0.id == category }
            .compactMap { c in
                let items = library.movements(in: c.id, matching: query)
                return items.isEmpty ? nil : Section(category: c, items: items)
            }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    GlassChip(title: "All", isSelected: category == nil) { category = nil }
                    ForEach(library.categories) { c in
                        GlassChip(title: c.name, isSelected: category == c.id, tint: c.color) {
                            category = category == c.id ? nil : c.id
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 4)
            }
        }
        .scrollClipDisabled()
    }

    private func row(_ m: Movement) -> some View {
        let isOn = selected.contains(m.id)
        return Button {
            withAnimation(.snappy) {
                if isOn { selected.removeAll { $0 == m.id } } else { selected.append(m.id) }
            }
        } label: {
            HStack(spacing: 14) {
                SketchTile(movement: m, poses: library.poses, cornerRadius: 14)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.name).font(Theme.display(17)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text(m.english).font(.system(size: 13)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
                Spacer()
                ZStack {
                    Circle().strokeBorder(isOn ? Theme.ribbon : Theme.inkFaint, lineWidth: 1.4)
                    if isOn {
                        Circle().fill(Theme.ribbon).padding(3)
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    }
                }
                .frame(width: 26, height: 26)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
    }
}
