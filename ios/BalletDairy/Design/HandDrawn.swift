import SwiftUI

// MARK: - Deterministic randomness (so a doodle looks the same every launch)

struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    /// uniform in -1...1
    mutating func signed() -> CGFloat { CGFloat(next() % 20_001) / 10_000 - 1 }
    mutating func unit() -> CGFloat { CGFloat(next() % 10_001) / 10_000 }
}

extension String {
    /// FNV-1a — stable across launches (unlike `hashValue`).
    var stableHash: UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return h
    }
}

extension Path {
    /// Catmull-Rom spline through points — the secret to lines that feel drawn by hand.
    static func smooth(_ pts: [CGPoint], closed: Bool = false) -> Path {
        var p = Path()
        guard pts.count > 1 else { return p }
        let n = pts.count
        func pt(_ i: Int) -> CGPoint {
            if closed { return pts[(i % n + n) % n] }
            return pts[min(max(i, 0), n - 1)]
        }
        p.move(to: pts[0])
        let segs = closed ? n : n - 1
        for i in 0..<segs {
            let p0 = pt(i - 1), p1 = pt(i), p2 = pt(i + 1), p3 = pt(i + 2)
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            p.addCurve(to: p2, control1: c1, control2: c2)
        }
        if closed { p.closeSubpath() }
        return p
    }
}

// MARK: - Shapes

/// A loose, slightly-overlapping ellipse like a pen circling a date.
struct WobblyCircle: Shape {
    var seed: UInt64 = 1
    var wobble: CGFloat = 0.06
    var overshoot: CGFloat = 0.14

    func path(in rect: CGRect) -> Path {
        var rng = SeededRandom(seed: seed)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let start = rng.unit() * .pi * 2
        let steps = 14
        let total = (1 + overshoot) * 2 * .pi
        var pts: [CGPoint] = []
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let a = start + t * total
            let w = 1 + rng.signed() * wobble + (t > 0.9 ? 0.05 : 0)
            pts.append(CGPoint(x: c.x + cos(a) * rect.width / 2 * w, y: c.y + sin(a) * rect.height / 2 * w))
        }
        return .smooth(pts)
    }
}

/// A rounded rectangle traced by hand.
struct WobblyRect: Shape {
    var seed: UInt64 = 7
    var wobble: CGFloat = 1.6
    var cornerRadius: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        var rng = SeededRandom(seed: seed)
        let r = min(cornerRadius, min(rect.width, rect.height) / 2)
        let base = Path(roundedRect: rect, cornerRadius: r)
        // sample the perimeter
        var pts: [CGPoint] = []
        let count = 28
        let trimmed = base
        for i in 0..<count {
            let t = CGFloat(i) / CGFloat(count)
            if let p = trimmed.trimmedPath(from: t, to: min(t + 0.0005, 1)).currentPoint {
                pts.append(CGPoint(x: p.x + rng.signed() * wobble, y: p.y + rng.signed() * wobble))
            }
        }
        return .smooth(pts, closed: true)
    }
}

/// A quick pen underline with a little lift at the end.
struct HandUnderline: Shape {
    var seed: UInt64 = 3
    func path(in rect: CGRect) -> Path {
        var rng = SeededRandom(seed: seed)
        let y = rect.midY
        let pts = (0...6).map { i -> CGPoint in
            let t = CGFloat(i) / 6
            return CGPoint(x: rect.minX + t * rect.width, y: y + rng.signed() * 1.4 - (t > 0.85 ? 2.5 : 0))
        }
        return .smooth(pts)
    }
}

/// A ribbon bow doodle — the brand's little mark.
struct BowDoodle: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * w, y: r.minY + y * h) }
        var p = Path()
        // left loop
        p.addPath(.smooth([P(0.5, 0.42), P(0.30, 0.12), P(0.06, 0.18), P(0.08, 0.52), P(0.30, 0.56), P(0.5, 0.46)]))
        // right loop
        p.addPath(.smooth([P(0.5, 0.42), P(0.70, 0.10), P(0.95, 0.20), P(0.92, 0.50), P(0.70, 0.56), P(0.5, 0.46)]))
        // knot
        p.addEllipse(in: CGRect(x: r.minX + 0.44 * w, y: r.minY + 0.38 * h, width: 0.12 * w, height: 0.12 * h))
        // tails
        p.addPath(.smooth([P(0.47, 0.5), P(0.40, 0.70), P(0.30, 0.95)]))
        p.addPath(.smooth([P(0.53, 0.5), P(0.62, 0.72), P(0.74, 0.96)]))
        return p
    }
}

/// Four-point sparkle.
struct SparkleDoodle: Shape {
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY)
        let a = r.width / 2, b = r.height / 2, k: CGFloat = 0.16
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - b))
        p.addQuadCurve(to: CGPoint(x: c.x + a, y: c.y), control: CGPoint(x: c.x + a * k, y: c.y - b * k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + b), control: CGPoint(x: c.x + a * k, y: c.y + b * k))
        p.addQuadCurve(to: CGPoint(x: c.x - a, y: c.y), control: CGPoint(x: c.x - a * k, y: c.y + b * k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - b), control: CGPoint(x: c.x - a * k, y: c.y - b * k))
        return p
    }
}

/// A slightly lopsided heart.
struct HeartDoodle: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * w, y: r.minY + y * h) }
        var p = Path()
        p.move(to: P(0.5, 0.92))
        p.addCurve(to: P(0.04, 0.34), control1: P(0.28, 0.74), control2: P(0.02, 0.58))
        p.addCurve(to: P(0.5, 0.24), control1: P(0.06, 0.06), control2: P(0.42, 0.04))
        p.addCurve(to: P(0.96, 0.32), control1: P(0.58, 0.02), control2: P(0.95, 0.06))
        p.addCurve(to: P(0.5, 0.92), control1: P(0.98, 0.58), control2: P(0.72, 0.74))
        return p
    }
}

// MARK: - Paper

/// Notebook paper: cream stock, faint rules, a rose margin, punched holes and a touch of grain.
struct PaperBackground: View {
    var ruleSpacing: CGFloat = 32
    var showsMargin = true
    var showsHoles = true

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.paper))
            // grain
            var rng = SeededRandom(seed: 42)
            for _ in 0..<Int(size.width * size.height / 900) {
                let x = rng.unit() * size.width, y = rng.unit() * size.height
                let s = 0.6 + rng.unit() * 0.9
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: s, height: s)),
                         with: .color(Theme.ink.opacity(0.025 + Double(rng.unit()) * 0.03)))
            }
            // rules
            var y: CGFloat = 140
            while y < size.height {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(line, with: .color(Theme.rule.opacity(0.8)), lineWidth: 0.7)
                y += ruleSpacing
            }
            if showsMargin {
                var m = Path()
                m.move(to: CGPoint(x: 34, y: 0)); m.addLine(to: CGPoint(x: 34, y: size.height))
                ctx.stroke(m, with: .color(Theme.margin.opacity(0.55)), lineWidth: 0.9)
            }
            if showsHoles {
                var hy: CGFloat = 180
                while hy < size.height {
                    let r = CGRect(x: 10, y: hy, width: 12, height: 12)
                    ctx.fill(Path(ellipseIn: r), with: .color(Theme.paperDeep))
                    ctx.stroke(Path(ellipseIn: r), with: .color(Theme.inkFaint.opacity(0.35)), lineWidth: 0.6)
                    hy += 220
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Paper without rules — for screens that are more gallery than notebook.
struct PlainPaper: View {
    var body: some View {
        ZStack {
            Theme.paper
            LinearGradient(colors: [Theme.satin.opacity(0.7), Theme.paper.opacity(0)], startPoint: .top, endPoint: .center)
            Canvas { ctx, size in
                var rng = SeededRandom(seed: 9)
                for _ in 0..<Int(size.width * size.height / 1100) {
                    let x = rng.unit() * size.width, y = rng.unit() * size.height
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)), with: .color(Theme.ink.opacity(0.03)))
                }
            }
        }
        .ignoresSafeArea()
    }
}

extension Shape {
    /// The house ink stroke.
    func inked(_ color: Color = Theme.ink, width: CGFloat = 1.4) -> some View {
        stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }
}
