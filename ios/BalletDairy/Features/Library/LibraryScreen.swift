import SwiftData
import SwiftUI

/// Page 3: the répertoire — every step, sketched.
struct LibraryScreen: View {
    @Environment(MovementLibrary.self) private var library
    @Query private var entries: [DiaryEntry]
    @State private var query = ""
    @State private var category: String? = nil
    @State private var level: Int? = nil
    @Namespace private var zoom

    private var practiceCounts: [String: Int] {
        var c: [String: Int] = [:]
        for e in entries where e.isPracticed { for id in Set(e.movementIDs) { c[id, default: 0] += 1 } }
        return c
    }

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    header
                    filters
                    let counts = practiceCounts
                    ForEach(library.categories.filter { category == nil || $0.id == category }) { cat in
                        let items = library.movements(in: cat.id, matching: query, level: level)
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(alignment: .firstTextBaseline) {
                                    SectionHeader(title: cat.name, eyebrow: "\(items.count) steps")
                                }
                                Text(cat.blurb).font(Theme.hand(15)).foregroundStyle(Theme.inkSoft)
                                LazyVGrid(columns: columns, spacing: 14) {
                                    ForEach(items) { m in
                                        NavigationLink(value: m) {
                                            MovementCard(movement: m, practiced: counts[m.id] ?? 0)
                                                .matchedTransitionSource(id: m.id, in: zoom)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    if library.movements(in: category, matching: query, level: level).isEmpty {
                        DoodleEmptyState(title: "No steps found", message: "Try the French or English name, or clear a filter.")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }
            .background(PlainPaper())
            .searchable(text: $query, prompt: "Search the répertoire")
            .navigationDestination(for: Movement.self) { m in
                MovementDetailView(movement: m)
                    .navigationTransition(.zoom(sourceID: m.id, in: zoom))
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Répertoire").font(Theme.script(42)).foregroundStyle(Theme.ribbon)
            Text("\(library.movements.count) movements, from first position to fouettés")
                .font(Theme.display(16)).foregroundStyle(Theme.inkSoft)
        }
        .padding(.top, 8)
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        GlassChip(title: "All", isSelected: category == nil) { withAnimation(.snappy) { category = nil } }
                        ForEach(library.categories) { c in
                            GlassChip(title: c.name, isSelected: category == c.id, tint: c.color) {
                                withAnimation(.snappy) { category = category == c.id ? nil : c.id }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .scrollClipDisabled()

            HStack(spacing: 8) {
                Text("Level").eyebrow()
                ForEach(1...4, id: \.self) { l in
                    Button {
                        withAnimation(.snappy) { level = level == l ? nil : l }
                    } label: {
                        Text(["", "I", "II", "III", "IV"][l])
                            .font(.system(size: 14, weight: .semibold, design: .serif))
                            .foregroundStyle(level == l ? Theme.ribbon : Theme.inkSoft)
                            .frame(width: 34, height: 30)
                            .background {
                                if level == l { WobblyCircle(seed: UInt64(l * 31)).inked(Theme.ribbon, width: 1.3) }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Level \(l)")
                }
            }
        }
    }
}

struct MovementCard: View {
    let movement: Movement
    var practiced: Int = 0
    @Environment(MovementLibrary.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SketchTile(movement: movement, poses: library.poses)
                .frame(height: 150)
                .overlay(alignment: .topTrailing) {
                    if practiced > 0 {
                        Text("\(practiced)×")
                            .font(Theme.hand(13)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .glassEffect(.regular.tint(Theme.blush.opacity(0.6)), in: .capsule)
                            .padding(8)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(movement.name)
                    .font(Theme.display(16)).foregroundStyle(Theme.ink)
                    .lineLimit(2).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(movement.english).font(.system(size: 12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                LevelDots(level: movement.level).padding(.top, 2)
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.55))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Theme.rule, lineWidth: 0.8))
                .shadow(color: Theme.ink.opacity(0.05), radius: 10, y: 5)
        }
        .contentShape(.rect(cornerRadius: 28))
    }
}
