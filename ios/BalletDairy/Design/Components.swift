import SwiftUI

// MARK: - Glass chip

struct GlassChip: View {
    let title: String
    var systemImage: String? = nil
    var isSelected = false
    var tint: Color = Theme.rose
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 12, weight: .semibold)) }
                Text(title).font(.system(size: 14, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? Theme.ink : Theme.inkSoft)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(isSelected ? .regular.tint(tint.opacity(0.45)).interactive() : .regular.interactive(), in: .capsule)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isSelected)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

// MARK: - Section header with a pen underline

struct SectionHeader: View {
    let title: String
    var eyebrow: String? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                if let eyebrow { Text(eyebrow).eyebrow() }
                Text(title)
                    .font(Theme.display(24))
                    .foregroundStyle(Theme.ink)
                    .background(alignment: .bottomLeading) {
                        HandUnderline(seed: title.stableHash)
                            .inked(Theme.rose.opacity(0.8), width: 2)
                            .frame(height: 8)
                            .offset(y: 6)
                            .padding(.trailing, -6)
                    }
            }
            Spacer()
            if let trailing { trailing }
        }
    }
}

// MARK: - Flow layout (wrapping chips / stickers)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW { x = 0; y += lineH + lineSpacing; lineH = 0 }
            x += s.width + spacing; lineH = max(lineH, s.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += lineH + lineSpacing; lineH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; lineH = max(lineH, s.height)
        }
    }
}

// MARK: - Washi-tape sticker for a practised movement

struct WashiSticker: View {
    let text: String
    var color: Color = Theme.blush
    var onRemove: (() -> Void)? = nil

    private var tilt: Double {
        var rng = SeededRandom(seed: text.stableHash)
        return Double(rng.signed()) * 3.2
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(text).font(Theme.hand(15)).foregroundStyle(Theme.ink)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.inkSoft)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(text)")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background {
            ZStack {
                Rectangle().fill(color.opacity(0.75))
                // tape stripes
                Canvas { ctx, size in
                    var x: CGFloat = -size.height
                    while x < size.width {
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0))
                        ctx.stroke(p, with: .color(.white.opacity(0.35)), lineWidth: 3)
                        x += 9
                    }
                }
            }
            .mask(TornTape())
        }
        .rotationEffect(.degrees(tilt))
        .shadow(color: Theme.ink.opacity(0.06), radius: 1, y: 1)
    }
}

/// Tape with zig-zag torn ends.
struct TornTape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let teeth = 4, d: CGFloat = 3
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        for i in 0...teeth {
            let y = r.minY + r.height * CGFloat(i) / CGFloat(teeth)
            p.addLine(to: CGPoint(x: r.maxX - (i % 2 == 0 ? 0 : d), y: y))
        }
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        for i in stride(from: teeth, through: 0, by: -1) {
            let y = r.minY + r.height * CGFloat(i) / CGFloat(teeth)
            p.addLine(to: CGPoint(x: r.minX + (i % 2 == 0 ? 0 : d), y: y))
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Small pieces

struct LevelDots: View {
    let level: Int
    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...4, id: \.self) { i in
                Circle()
                    .fill(i <= level ? Theme.ribbon : Theme.inkFaint.opacity(0.35))
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityLabel("Level \(level) of 4")
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var symbol: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ribbon)
            }
            Text(value)
                .font(.system(size: 28, weight: .regular, design: .serif))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(label).eyebrow()
        }
        .paperCard(cornerRadius: 22, padding: 14)
    }
}

/// A round glass icon button.
struct GlassIconButton: View {
    let systemImage: String
    var label: String
    var prominent = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(prominent ? Color.white : Theme.ink)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(prominent ? .regular.tint(Theme.ribbon.opacity(0.85)).interactive() : .regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }
}

/// Hand-written empty state with a little doodle.
struct DoodleEmptyState: View {
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            BowDoodle().inked(Theme.rose, width: 1.6).frame(width: 64, height: 48)
            Text(title).font(Theme.display(20)).foregroundStyle(Theme.ink)
            Text(message).font(Theme.hand(15)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}
