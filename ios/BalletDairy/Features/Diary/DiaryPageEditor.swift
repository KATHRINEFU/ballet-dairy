import SwiftUI

/// One diary page: session details, handwritten notes, practised movements and sketches.
struct DiaryPageEditor: View {
    @Bindable var entry: DiaryEntry
    @Environment(MovementLibrary.self) private var library
    @State private var showPicker = false
    @State private var doodleTool: DoodleTool = .ink
    @State private var isDoodling = false
    @Namespace private var toolNS

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            sessionCard
            notes
            practised
            sketches
        }
        .onChange(of: entry.text) { entry.touch() }
        .onChange(of: entry.movementIDs) { entry.touch() }
        .onChange(of: entry.durationMinutes) { entry.touch() }
        .onChange(of: entry.classType) { entry.touch() }
        .onChange(of: entry.energy) { entry.touch() }
        .onChange(of: entry.drawing) { entry.touch() }
        .sheet(isPresented: $showPicker) {
            MovementPickerSheet(selected: $entry.movementIDs)
        }
    }

    // MARK: Session

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Today's session").eyebrow()

            GlassEffectContainer(spacing: 8) {
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(ClassType.allCases) { type in
                        GlassChip(title: type.rawValue, systemImage: type.symbol,
                                  isSelected: entry.classType == type.rawValue) {
                            entry.classType = type.rawValue
                        }
                    }
                }
            }

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.durationMinutes == 0 ? "—" : entry.durationMinutes.minutesLabel)
                        .font(.system(size: 34, weight: .regular, design: .serif))
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText())
                    Text("in the studio").font(Theme.hand(14)).foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        GlassIconButton(systemImage: "minus", label: "15 minutes less") {
                            withAnimation(.snappy) { entry.durationMinutes = max(0, entry.durationMinutes - 15) }
                        }
                        GlassIconButton(systemImage: "plus", label: "15 minutes more", prominent: true) {
                            withAnimation(.snappy) { entry.durationMinutes = min(600, entry.durationMinutes + 15) }
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                ForEach([45, 60, 90, 120], id: \.self) { m in
                    Button { withAnimation(.snappy) { entry.durationMinutes = m } } label: {
                        Text(m.minutesLabel)
                            .font(Theme.hand(14))
                            .foregroundStyle(entry.durationMinutes == m ? Theme.ribbon : Theme.inkSoft)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background {
                                if entry.durationMinutes == m {
                                    WobblyCircle(seed: UInt64(m)).inked(Theme.ribbon, width: 1.2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("How did your body feel?").font(Theme.hand(15)).foregroundStyle(Theme.inkSoft)
                HStack(spacing: 12) {
                    ForEach(1...5, id: \.self) { i in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                                entry.energy = entry.energy == i ? 0 : i
                            }
                        } label: {
                            ZStack {
                                HeartDoodle().fill(i <= entry.energy ? Theme.rose : .clear)
                                HeartDoodle().inked(i <= entry.energy ? Theme.ribbon : Theme.inkFaint, width: 1.4)
                            }
                            .frame(width: 26, height: 24)
                            .scaleEffect(i == entry.energy ? 1.15 : 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(i) of 5")
                    }
                }
                .sensoryFeedback(.impact(weight: .light), trigger: entry.energy)
            }
        }
        .paperCard()
    }

    // MARK: Notes

    private var notes: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Dear diary", eyebrow: "Notes")
            RuledTextField(text: $entry.text, placeholder: "corrections from class, a combination to remember, how the pirouettes felt…")
        }
    }

    // MARK: Movements

    private var practised: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Practised today", eyebrow: "Movements", trailing: AnyView(
                Button { showPicker = true } label: {
                    Label("Add", systemImage: "plus").font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.glass)
                .tint(Theme.ribbon)
            ))

            if entry.movementIDs.isEmpty {
                Text("Tap Add to tick off what you worked on — tendus, pirouettes, that tricky grand jeté.")
                    .font(Theme.hand(16)).foregroundStyle(Theme.inkSoft)
                    .padding(.vertical, 4)
            } else {
                FlowLayout(spacing: 10, lineSpacing: 12) {
                    ForEach(entry.movementIDs, id: \.self) { id in
                        let m = library.movement(id)
                        WashiSticker(text: m?.name ?? id,
                                     color: Theme.categoryColor(m?.category ?? "").opacity(0.45)) {
                            withAnimation(.snappy) { entry.movementIDs.removeAll { $0 == id } }
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                musclesWorked
            }
        }
    }

    private var musclesWorked: some View {
        let counts = entry.movementIDs.compactMap(library.movement).flatMap(\.muscles.primary)
            .reduce(into: [Muscle: Int]()) { $0[$1, default: 0] += 1 }
        let top = counts.sorted { $0.value > $1.value }.prefix(5).map(\.key)
        return Group {
            if !top.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "sparkle").foregroundStyle(Theme.gold)
                    Text("You worked your ").font(Theme.hand(15)).foregroundStyle(Theme.inkSoft)
                    + Text(top.map(\.displayName).joined(separator: ", ").lowercased())
                        .font(Theme.handBold(15)).foregroundStyle(Theme.ribbon)
                }
                .padding(.top, 6)
            }
        }
    }

    // MARK: Sketches

    private var sketches: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Sketches", eyebrow: "Doodle", trailing: AnyView(
                Button {
                    withAnimation(.snappy) { isDoodling.toggle() }
                } label: {
                    Label(isDoodling ? "Done" : "Draw", systemImage: isDoodling ? "checkmark" : "pencil.tip")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.glass)
                .tint(Theme.ribbon)
            ))

            ZStack(alignment: .bottom) {
                WobblyRect(seed: 11, cornerRadius: 22)
                    .fill(Theme.paper.opacity(0.6))
                    .overlay(WobblyRect(seed: 11, cornerRadius: 22).inked(Theme.inkFaint, width: 1.1))
                if entry.drawing == nil && !isDoodling {
                    Text("sketch an arabesque, a floor pattern, anything")
                        .font(Theme.hand(15)).foregroundStyle(Theme.inkFaint)
                        .frame(maxHeight: .infinity)
                }
                DoodleCanvas(data: $entry.drawing, tool: doodleTool, isEditable: isDoodling)
                    .clipShape(.rect(cornerRadius: 22))

                if isDoodling {
                    GlassEffectContainer(spacing: 10) {
                        HStack(spacing: 10) {
                            ForEach(DoodleTool.allCases) { t in
                                Button { doodleTool = t } label: {
                                    Group {
                                        if t == .eraser {
                                            Image(systemName: "eraser").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                                        } else {
                                            Circle().fill(t.color).frame(width: 18, height: 18)
                                        }
                                    }
                                    .frame(width: 38, height: 38)
                                }
                                .buttonStyle(.plain)
                                .glassEffect(doodleTool == t ? .regular.tint(Theme.rose.opacity(0.5)).interactive() : .regular.interactive(), in: .circle)
                                .glassEffectID(t.id, in: toolNS)
                                .accessibilityLabel(t.rawValue)
                            }
                        }
                    }
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(height: 280)
        }
    }
}

// MARK: - Ruled handwriting field

/// A growing text field whose lines sit on the notebook rules.
struct RuledTextField: View {
    @Binding var text: String
    var placeholder: String
    var spacing: CGFloat = 32
    var minLines = 6

    var body: some View {
        let font = Theme.handUIFont
        let lineSpacing = max(0, spacing - font.lineHeight)
        ZStack(alignment: .topLeading) {
            Canvas { ctx, size in
                var y = font.ascender + 6
                while y < size.height + 1 {
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(p, with: .color(Theme.margin.opacity(0.45)), lineWidth: 0.8)
                    y += spacing
                }
            }
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.inkFaint), axis: .vertical)
                .font(Theme.hand(18))
                .lineSpacing(lineSpacing)
                .foregroundStyle(Theme.ink)
                .tint(Theme.ribbon)
                .textInputAutocapitalization(.sentences)
        }
        .frame(minHeight: spacing * CGFloat(minLines), alignment: .top)
        .contentShape(.rect)
    }
}
