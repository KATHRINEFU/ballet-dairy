import Charts
import SwiftData
import SwiftUI

/// Page 2: a hand-circled month calendar and the story of your practice in numbers.
struct CalendarScreen: View {
    @Environment(MovementLibrary.self) private var library
    @Query(sort: \DiaryEntry.day) private var entries: [DiaryEntry]
    @Binding var selectedDay: Date
    var openDiary: () -> Void

    @State private var month = Date.now
    @State private var range: StatsRange = .month
    @State private var editing: DiaryEntry?

    private var stats: PracticeStats {
        StatsEngine.compute(entries: entries, interval: StatsEngine.interval(for: range, around: month), library: library)
    }
    private var byDay: [Date: DiaryEntry] {
        Dictionary(entries.filter(\.isPracticed).map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    monthHeader
                    MonthGrid(month: month, byDay: byDay, selectedDay: $selectedDay)
                    selectedDayCard
                    statsSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }
            .background(PlainPaper())
            .sheet(item: $editing) { e in
                NavigationStack {
                    ScrollView {
                        DiaryPageEditor(entry: e).padding(.leading, 48).padding(.trailing, 20).padding(.vertical, 20)
                    }
                    .background(PaperBackground())
                    .navigationTitle(e.day.formatted(.dateTime.weekday(.wide).day().month()))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done", systemImage: "checkmark") { editing = nil }
                                .buttonStyle(.glassProminent).tint(Theme.ribbon)
                        }
                    }
                }
            }
        }
    }

    // MARK: Header

    private var monthHeader: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text(month.formatted(.dateTime.month(.wide)))
                    .font(Theme.script(42)).foregroundStyle(Theme.ribbon)
                    .contentTransition(.opacity)
                Text(month.formatted(.dateTime.year())).font(Theme.display(18)).foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    GlassIconButton(systemImage: "chevron.left", label: "Previous month") { step(-1) }
                    GlassIconButton(systemImage: "chevron.right", label: "Next month") { step(1) }
                }
            }
        }
        .padding(.top, 8)
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if v.translation.width < -40 { step(1) } else if v.translation.width > 40 { step(-1) }
        })
    }

    private func step(_ n: Int) {
        if let m = Calendar.current.date(byAdding: .month, value: n, to: month) {
            withAnimation(.snappy) { month = m }
        }
    }

    // MARK: Selected day

    @ViewBuilder private var selectedDayCard: some View {
        let entry = entries.first { $0.day == selectedDay }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(Theme.display(20)).foregroundStyle(Theme.ink)
                Spacer()
                if let e = entry, e.isPracticed {
                    Text(e.durationMinutes.minutesLabel).font(Theme.hand(16)).foregroundStyle(Theme.ribbon)
                }
            }
            if let e = entry, e.isPracticed || !e.text.isEmpty {
                Text(e.classType).eyebrow()
                if !e.text.isEmpty {
                    Text(e.text).font(Theme.hand(16)).foregroundStyle(Theme.ink).lineLimit(3)
                }
                if !e.movementIDs.isEmpty {
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(e.movementIDs.prefix(8), id: \.self) { id in
                            let m = library.movement(id)
                            WashiSticker(text: m?.name ?? id, color: Theme.categoryColor(m?.category ?? "").opacity(0.35))
                        }
                    }
                }
                Button("Open page", systemImage: "book.pages") { editing = e }
                    .buttonStyle(.glass).tint(Theme.ribbon).padding(.top, 4)
            } else {
                Text("A rest day. Bodies need those too.").font(Theme.hand(16)).foregroundStyle(Theme.inkSoft)
                Button("Write this day", systemImage: "pencil") { openDiary() }
                    .buttonStyle(.glass).tint(Theme.ribbon)
            }
        }
        .paperCard()
        .animation(.snappy, value: selectedDay)
    }

    // MARK: Stats

    private var statsSection: some View {
        let s = stats
        return VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: "Your practice", eyebrow: "Statistics")
            Picker("Range", selection: $range) {
                ForEach(StatsRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                StatTile(value: "\(s.classes)", label: "Classes", symbol: "figure.dance")
                StatTile(value: s.hoursLabel, label: "Hours", symbol: "clock")
                StatTile(value: "\(s.currentStreak)", label: s.longestStreak > s.currentStreak ? "Streak · best \(s.longestStreak)" : "Day streak", symbol: "flame")
                StatTile(value: "\(s.uniqueMovements)", label: "Movements", symbol: "sparkles")
            }
            .animation(.snappy, value: range)

            WeeklyHoursChart(weeks: s.weekly).paperCard()
            if !s.byCategory.isEmpty { CategoryDonut(counts: s.byCategory).paperCard() }
            if !s.topMovements.isEmpty { TopMovements(counts: s.topMovements).paperCard() }
            if s.classes == 0 {
                DoodleEmptyState(title: "Nothing logged yet", message: "Fill in a diary page and your practice will bloom here.")
            }
        }
    }
}

// MARK: - Month grid with hand-drawn circles

struct MonthGrid: View {
    let month: Date
    let byDay: [Date: DiaryEntry]
    @Binding var selectedDay: Date
    @Namespace private var ns
    private let cal = Calendar.current

    private var cells: [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: month) else { return [] }
        let first = interval.start
        let lead = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        let count = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        return Array(repeating: nil, count: lead) + (0..<count).compactMap { cal.date(byAdding: .day, value: $0, to: first) }
    }

    var body: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(Array(cal.veryShortStandaloneWeekdaySymbols.rotated(by: cal.firstWeekday - 1).enumerated()), id: \.offset) { _, s in
                    Text(s).font(Theme.hand(13)).foregroundStyle(Theme.inkSoft).frame(maxWidth: .infinity)
                }
            }
            GlassEffectContainer(spacing: 4) {
                LazyVGrid(columns: cols, spacing: 6) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                        if let day { cell(day) } else { Color.clear.frame(height: 46) }
                    }
                }
            }
        }
        .padding(14)
        .paperCard(padding: 0)
    }

    private func cell(_ day: Date) -> some View {
        let entry = byDay[day]
        let minutes = entry?.durationMinutes ?? 0
        let isSel = cal.isDate(day, inSameDayAs: selectedDay)
        return Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { selectedDay = day }
        } label: {
            ZStack {
                if entry != nil {
                    // the longer the class, the bolder the circle
                    WobblyCircle(seed: day.formatted(.iso8601).stableHash)
                        .fill(Theme.blush.opacity(min(0.25 + Double(minutes) / 240, 0.85)))
                    WobblyCircle(seed: day.formatted(.iso8601).stableHash)
                        .inked(Theme.ribbon, width: 1 + min(CGFloat(minutes) / 60, 2))
                }
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 16, weight: isSel ? .semibold : .regular, design: .serif))
                    .foregroundStyle(cal.isDateInToday(day) ? Theme.ribbon : Theme.ink)
            }
            .frame(width: 38, height: 38)
            .frame(maxWidth: .infinity, minHeight: 46)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background {
            if isSel {
                Circle().fill(.clear).frame(width: 46, height: 46)
                    .glassEffect(.regular.tint(Theme.lilac.opacity(0.5)).interactive(), in: .circle)
                    .glassEffectID("selected", in: ns)
            }
        }
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + (entry != nil ? ", practised \(minutes.minutesLabel)" : ""))
    }
}

private extension Array {
    func rotated(by n: Int) -> [Element] {
        guard !isEmpty else { return self }
        let k = ((n % count) + count) % count
        return Array(self[k...] + self[..<k])
    }
}

// MARK: - Charts

struct WeeklyHoursChart: View {
    let weeks: [PracticeStats.Week]
    @State private var selected: Date?

    private var selectedWeek: PracticeStats.Week? {
        guard let selected else { return nil }
        return weeks.last { $0.start <= selected }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Hours per week").font(Theme.display(19)).foregroundStyle(Theme.ink)
                Spacer()
                if let w = selectedWeek {
                    Text("\(w.start.formatted(.dateTime.day().month(.abbreviated))) · \(w.minutes.minutesLabel)")
                        .font(Theme.hand(15)).foregroundStyle(Theme.ink)
                } else {
                    Text("last \(weeks.count) weeks").font(Theme.hand(14)).foregroundStyle(Theme.inkSoft)
                }
            }
            Chart(weeks) { w in
                BarMark(x: .value("Week", w.start, unit: .weekOfYear),
                        y: .value("Hours", Double(w.minutes) / 60), width: .ratio(0.55))
                    .foregroundStyle(Theme.ribbon.opacity(selectedWeek == nil || selectedWeek?.start == w.start ? 1 : 0.35))
                    .cornerRadius(4)
                if let s = selectedWeek, s.start == w.start {
                    RuleMark(x: .value("Week", w.start, unit: .weekOfYear))
                        .foregroundStyle(Theme.inkFaint.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartXSelection(value: $selected)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Theme.rule)
                    AxisValueLabel().font(.system(size: 10)).foregroundStyle(Theme.inkSoft)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(.system(size: 10)).foregroundStyle(Theme.inkSoft)
                }
            }
            .frame(height: 170)
        }
    }
}

struct CategoryDonut: View {
    let counts: [PracticeStats.Count]
    @State private var angle: Int?

    private var selected: PracticeStats.Count? {
        guard let angle else { return nil }
        var acc = 0
        for c in counts { acc += c.value; if angle <= acc { return c } }
        return nil
    }
    private var total: Int { counts.reduce(0) { $0 + $1.value } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What you practised").font(Theme.display(19)).foregroundStyle(Theme.ink)
            HStack(alignment: .center, spacing: 18) {
                Chart(counts) { c in
                    SectorMark(angle: .value("Count", c.value), innerRadius: .ratio(0.62), angularInset: 2)
                        .cornerRadius(4)
                        .foregroundStyle(Theme.categoryColor(c.id))
                        .opacity(selected == nil || selected?.id == c.id ? 1 : 0.35)
                }
                .chartAngleSelection(value: $angle)
                .chartBackground { _ in
                    VStack(spacing: 0) {
                        Text("\(selected?.value ?? total)").font(.system(size: 24, design: .serif)).foregroundStyle(Theme.ink)
                        Text(selected?.label ?? "ticks").font(Theme.hand(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                    }
                    .frame(width: 70)
                }
                .frame(width: 140, height: 140)

                // legend with values (identity never by colour alone)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(counts) { c in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2).fill(Theme.categoryColor(c.id)).frame(width: 10, height: 10)
                            Text(c.label).font(.system(size: 13)).foregroundStyle(Theme.ink).lineLimit(1)
                            Spacer(minLength: 4)
                            Text("\(c.value)").font(.system(size: 13, design: .serif)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
            }
        }
    }
}

struct TopMovements: View {
    let counts: [PracticeStats.Count]
    var body: some View {
        let maxV = counts.map(\.value).max() ?? 1
        VStack(alignment: .leading, spacing: 12) {
            Text("Most practised").font(Theme.display(19)).foregroundStyle(Theme.ink)
            ForEach(Array(counts.enumerated()), id: \.element.id) { i, c in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(c.label).font(Theme.display(16)).foregroundStyle(Theme.ink)
                        Spacer()
                        Text("\(c.value)×").font(Theme.hand(15)).foregroundStyle(Theme.inkSoft)
                    }
                    GeometryReader { g in
                        let w = g.size.width * CGFloat(c.value) / CGFloat(maxV)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.rule.opacity(0.5))
                            Capsule().fill(Theme.rose.opacity(0.9)).frame(width: max(w, 6))
                            HandUnderline(seed: UInt64(i + 1)).inked(Theme.ribbon.opacity(0.5), width: 1).frame(width: max(w, 6))
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
    }
}
