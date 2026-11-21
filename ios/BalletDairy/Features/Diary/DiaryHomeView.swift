import SwiftData
import SwiftUI

/// Home: the notebook open on today's page.
struct DiaryHomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DiaryEntry.day) private var entries: [DiaryEntry]
    @Binding var selectedDay: Date
    @State private var showSettings = false

    private var current: DiaryEntry? { entries.first { $0.day == selectedDay } }
    private var practicedDays: Set<Date> { Set(entries.filter(\.isPracticed).map(\.day)) }
    private var isToday: Bool { Calendar.current.isDateInToday(selectedDay) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    WeekStrip(selectedDay: $selectedDay, practicedDays: practicedDays)
                    if let current {
                        DiaryPageEditor(entry: current)
                            .id(current.id)
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                    removal: .opacity))
                    }
                }
                .padding(.leading, 48).padding(.trailing, 20)
                .padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(PaperBackground())
            .toolbar {
                if !isToday {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Today", systemImage: "arrow.uturn.backward") {
                            withAnimation(.snappy) { selectedDay = Date.now.startOfDay }
                        }
                        .labelStyle(.titleAndIcon)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
        .task(id: selectedDay) { ensurePage() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(selectedDay.formatted(.dateTime.weekday(.wide)))
                .font(Theme.script(44))
                .foregroundStyle(Theme.ribbon)
                .padding(.top, 6)
            Text(selectedDay.formatted(.dateTime.day().month(.wide).year()))
                .font(Theme.display(18))
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            BowDoodle()
                .inked(Theme.rose, width: 1.6)
                .frame(width: 58, height: 44)
                .rotationEffect(.degrees(-8))
                .overlay(alignment: .topTrailing) {
                    SparkleDoodle().fill(Theme.gold.opacity(0.8)).frame(width: 12, height: 12).offset(x: 10, y: -4)
                }
                .padding(.top, 18)
                .accessibilityHidden(true)
        }
    }

    /// Create today's page on demand, and tidy away blank pages we leave behind.
    private func ensurePage() {
        for e in entries where e.day != selectedDay && e.text.isEmpty && !e.isPracticed && e.drawing == nil {
            context.delete(e)
        }
        if current == nil { context.insert(DiaryEntry(day: selectedDay)) }
    }
}

// MARK: - Week strip

struct WeekStrip: View {
    @Binding var selectedDay: Date
    let practicedDays: Set<Date>
    @Namespace private var ns
    private let cal = Calendar.current

    private var days: [Date] {
        let start = cal.dateInterval(of: .weekOfYear, for: selectedDay)?.start ?? selectedDay
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(selectedDay.formatted(.dateTime.month(.wide))).eyebrow()
                Spacer()
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.glass).accessibilityLabel("Previous week")
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.glass).accessibilityLabel("Next week")
            }
            .tint(Theme.ink)

            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 4) {
                    ForEach(days, id: \.self) { day in
                        dayCell(day)
                    }
                }
            }
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if v.translation.width < -40 { shift(1) } else if v.translation.width > 40 { shift(-1) }
        })
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = cal.isDate(day, inSameDayAs: selectedDay)
        let isToday = cal.isDateInToday(day)
        let practiced = practicedDays.contains(day)
        return Button {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { selectedDay = day.startOfDay }
        } label: {
            VStack(spacing: 4) {
                Text(day.formatted(.dateTime.weekday(.narrow)))
                    .font(Theme.hand(13))
                    .foregroundStyle(isSelected ? Theme.ink : Theme.inkSoft)
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 19, weight: isSelected ? .semibold : .regular, design: .serif))
                    .foregroundStyle(Theme.ink)
                    .overlay(alignment: .bottom) {
                        if isToday && !isSelected {
                            HandUnderline(seed: 5).inked(Theme.ribbon, width: 1.4).frame(width: 18, height: 4).offset(y: 5)
                        }
                    }
                Group {
                    if practiced {
                        HeartDoodle().fill(Theme.rose)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 8, height: 7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                Capsule().fill(.clear)
                    .glassEffect(.regular.tint(Theme.blush.opacity(0.7)).interactive(), in: .capsule)
                    .glassEffectID("selected-day", in: ns)
            }
        }
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + (practiced ? ", practised" : ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func shift(_ weeks: Int) {
        if let d = cal.date(byAdding: .weekOfYear, value: weeks, to: selectedDay) {
            withAnimation(.snappy) { selectedDay = d.startOfDay }
        }
    }
}
