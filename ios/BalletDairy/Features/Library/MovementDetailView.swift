import SwiftData
import SwiftUI

struct MovementDetailView: View {
    let movement: Movement
    @Environment(MovementLibrary.self) private var library
    @Environment(\.modelContext) private var context
    @Query(sort: \DiaryEntry.day) private var entries: [DiaryEntry]

    @State private var isPlaying = true
    @State private var speed: Double = 1
    @State private var showMuscles = true
    @State private var showTutu = true
    @State private var focus: Muscle?
    @State private var angle: StageAngle = .threeQuarter
    @Namespace private var glassNS

    private var today: DiaryEntry? { entries.first { $0.day == Date.now.startOfDay } }
    private var isInToday: Bool { today?.movementIDs.contains(movement.id) ?? false }
    private var timesPracticed: Int { entries.filter { $0.isPracticed && $0.movementIDs.contains(movement.id) }.count }
    private var category: MovementCategory? { library.category(movement.category) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                stage
                titleBlock
                    .padding(.horizontal, 22)
                musclesCard.padding(.horizontal, 16)
                cuesCard.padding(.horizontal, 16)
            }
            .padding(.bottom, 140)
        }
        .background(PlainPaper())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(movement.name).font(Theme.display(17)).foregroundStyle(Theme.ink).lineLimit(1)
            }
        }
        .safeAreaInset(edge: .bottom) { addToToday }
    }

    // MARK: 3D stage

    private var stage: some View {
        ZStack(alignment: .bottom) {
            // studio backdrop: satin gradient + a hand-drawn stage ellipse
            LinearGradient(colors: [Theme.satin, Theme.paper], startPoint: .top, endPoint: .bottom)
            VStack {
                Spacer()
                WobblyCircle(seed: 77, wobble: 0.02, overshoot: 0.08)
                    .inked(Theme.rose.opacity(0.6), width: 1.2)
                    .frame(width: 260, height: 54)
                    .padding(.bottom, 92)
            }
            DancerStageView(movement: movement, poses: library.poses, isPlaying: isPlaying, speed: speed,
                            showMuscles: showMuscles, showTutu: showTutu, focusMuscle: focus, angle: angle)
                .accessibilityLabel("3D animation of \(movement.name)")

            controls.padding(.bottom, 14)
        }
        .frame(height: 470)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 36, bottomTrailingRadius: 36, style: .continuous))
        .overlay(alignment: .topLeading) {
            if let focus {
                Button {
                    withAnimation(.snappy) { self.focus = nil }
                } label: {
                    Label(focus.displayName, systemImage: "xmark.circle.fill").font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.glass).tint(Theme.ribbon)
                .padding(14)
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                GlassIconButton(systemImage: isPlaying ? "pause.fill" : "play.fill",
                                label: isPlaying ? "Pause" : "Play", prominent: true) { isPlaying.toggle() }
                    .glassEffectID("play", in: glassNS)

                Menu {
                    Picker("Speed", selection: $speed) {
                        Text("Slow · ¼").tag(0.25)
                        Text("Half").tag(0.5)
                        Text("Tempo").tag(1.0)
                    }
                    Picker("View", selection: $angle) {
                        ForEach(StageAngle.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "metronome")
                        Text(speed == 1 ? "Tempo" : speed == 0.5 ? "Half" : "¼")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14).frame(height: 44)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
                .glassEffectID("tempo", in: glassNS)

                GlassIconButton(systemImage: "rotate.3d", label: "Next view") {
                    let all = StageAngle.allCases
                    angle = all[(all.firstIndex(of: angle)! + 1) % all.count]
                }
                .glassEffectID("angle", in: glassNS)

                Button { withAnimation(.snappy) { showMuscles.toggle() } } label: {
                    Image(systemName: "figure.strengthtraining.functional")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(showMuscles ? Theme.ribbon : Theme.inkSoft)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(showMuscles ? .regular.tint(Theme.blush.opacity(0.7)).interactive() : .regular.interactive(), in: .circle)
                .glassEffectID("muscles", in: glassNS)
                .accessibilityLabel(showMuscles ? "Hide muscles" : "Show muscles")

                Button { withAnimation(.snappy) { showTutu.toggle() } } label: {
                    Image(systemName: "circle.dotted.and.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(showTutu ? Theme.ribbon : Theme.inkSoft)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(showTutu ? .regular.tint(Theme.blush.opacity(0.7)).interactive() : .regular.interactive(), in: .circle)
                .glassEffectID("tutu", in: glassNS)
                .accessibilityLabel(showTutu ? "Hide tutu" : "Show tutu")
            }
        }
    }

    // MARK: Text

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let category {
                    Text(category.name).eyebrow()
                    Circle().fill(Theme.inkFaint).frame(width: 3, height: 3)
                }
                Text(movement.levelName).eyebrow()
                LevelDots(level: movement.level)
            }
            Text(movement.name)
                .font(Theme.display(34)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(movement.english).font(Theme.hand(18)).foregroundStyle(Theme.ribbon)
            if let aka = movement.aka, !aka.isEmpty {
                Text("also: " + aka.joined(separator: ", ")).font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
            }
            Text(movement.description)
                .font(.system(size: 17, design: .serif)).foregroundStyle(Theme.ink.opacity(0.9))
                .lineSpacing(4).padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
            if timesPracticed > 0 {
                Label("In your diary \(timesPracticed) \(timesPracticed == 1 ? "time" : "times")", systemImage: "book.closed")
                    .font(Theme.hand(15)).foregroundStyle(Theme.inkSoft).padding(.top, 2)
            }
        }
    }

    private var musclesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Muscles at work", eyebrow: "Anatomy")
            Text("Tap a muscle to isolate it on the dancer.").font(Theme.hand(15)).foregroundStyle(Theme.inkSoft)
            muscleGroup("Leading", movement.muscles.primary, dot: Theme.ribbon)
            if !movement.muscles.secondary.isEmpty {
                muscleGroup("Supporting", movement.muscles.secondary, dot: Theme.rose.opacity(0.6))
            }
        }
        .paperCard()
    }

    private func muscleGroup(_ title: String, _ muscles: [Muscle], dot: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).eyebrow()
            ForEach(muscles) { m in
                Button {
                    withAnimation(.snappy) { focus = focus == m ? nil : m; showMuscles = true }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(dot).frame(width: 9, height: 9).padding(.top, 6)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.displayName).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.ink)
                            Text(m.role).font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
                        }
                        Spacer()
                        if focus == m { Image(systemName: "scope").foregroundStyle(Theme.ribbon) }
                    }
                    .padding(.vertical, 4)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var cuesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Teacher's cues", eyebrow: "How to")
            ForEach(Array(movement.cues.enumerated()), id: \.offset) { i, cue in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(i + 1)")
                        .font(.system(size: 15, design: .serif)).foregroundStyle(Theme.ribbon)
                        .frame(width: 26, height: 26)
                        .background(WobblyCircle(seed: UInt64(i + 3)).inked(Theme.rose, width: 1.1))
                    Text(cue).font(Theme.hand(17)).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .paperCard()
    }

    // MARK: Add to today

    private var addToToday: some View {
        Button {
            withAnimation(.snappy) { toggleToday() }
        } label: {
            Label(isInToday ? "In today's diary" : "Add to today's diary",
                  systemImage: isInToday ? "checkmark" : "plus")
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .tint(isInToday ? Theme.rose : Theme.ribbon)
        .padding(.horizontal, 24).padding(.bottom, 8)
        .sensoryFeedback(.success, trigger: isInToday)
    }

    private func toggleToday() {
        let page: DiaryEntry
        if let t = today { page = t } else { page = DiaryEntry(day: .now); context.insert(page) }
        if page.movementIDs.contains(movement.id) {
            page.movementIDs.removeAll { $0 == movement.id }
        } else {
            page.movementIDs.append(movement.id)
        }
        page.touch()
    }
}
