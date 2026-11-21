import SwiftUI
import simd

/// A pen-and-ink sketch of a movement's signature pose — cheap enough for a grid of 100+ cards.
struct PoseSketch: View {
    let movement: Movement
    let poses: PoseLibrary
    var ink: Color = Theme.ink
    var accent: Color = Theme.rose
    var showsFloor = true
    /// 0 = front, positive turns the dancer to her right (¾ view).
    var viewYaw: Float = 28

    var body: some View {
        Canvas { ctx, size in
            let animator = MovementAnimator(movement: movement, library: poses)
            let frame = animator.pose(at: movement.animation.hero)
            let fk = Kinematics.solve(frame.angles, root: [0, frame.root.y, 0], yaw: frame.yaw)
            PoseSketch.draw(fk, in: &ctx, size: size, seed: movement.id.stableHash,
                            viewYaw: viewYaw, ink: ink, accent: accent, showsFloor: showsFloor)
        }
        .accessibilityLabel("Sketch of \(movement.name)")
    }

    static func draw(_ fk: FKResult, in ctx: inout GraphicsContext, size: CGSize, seed: UInt64,
                     viewYaw: Float, ink: Color, accent: Color, showsFloor: Bool) {
        let view = simd_quatf(angle: radians(viewYaw), axis: [0, 1, 0])
        // fit the figure (2.3 m tall box) into the canvas
        let scale = min(size.height / 2.35, size.width / 1.9)
        let originX = size.width / 2
        let groundY = size.height - size.height * 0.07
        func P(_ v: SIMD3<Float>) -> CGPoint {
            let r = view.act(v)
            return CGPoint(x: originX + CGFloat(r.x) * scale, y: groundY - CGFloat(r.y) * scale)
        }
        var rng = SeededRandom(seed: seed)

        func stroke(_ pts: [CGPoint], width: CGFloat, color: Color) {
            // two passes, slightly offset: the "sketched twice" look
            for pass in 0..<2 {
                let j: CGFloat = pass == 0 ? 0.6 : 1.3
                let jittered = pts.map { CGPoint(x: $0.x + rng.signed() * j, y: $0.y + rng.signed() * j) }
                var path = Path.smooth(jittered)
                if pts.count == 2 {
                    path = Path()
                    let a = jittered[0], b = jittered[1]
                    let mid = CGPoint(x: (a.x + b.x) / 2 + rng.signed() * 1.4, y: (a.y + b.y) / 2 + rng.signed() * 1.4)
                    path.move(to: a); path.addQuadCurve(to: b, control: mid)
                }
                ctx.stroke(path, with: .color(color.opacity(pass == 0 ? 0.92 : 0.32)),
                           style: StrokeStyle(lineWidth: pass == 0 ? width : width * 0.6, lineCap: .round, lineJoin: .round))
            }
        }

        let p = fk.position
        if showsFloor {
            let fx = (P(p[.lAnkle]!).x + P(p[.rAnkle]!).x) / 2
            let w = scale * 0.9
            ctx.fill(Path(ellipseIn: CGRect(x: fx - w / 2, y: groundY - 4, width: w, height: 9)),
                     with: .color(accent.opacity(0.16)))
        }

        let lw = max(1.1, scale * 0.016)
        // legs
        for (h, k, a, heel, toe) in [(Joint.lHip, Joint.lKnee, Joint.lAnkle, Marker.lHeel, Marker.lToe),
                                     (Joint.rHip, Joint.rKnee, Joint.rAnkle, Marker.rHeel, Marker.rToe)] {
            stroke([P(p[h]!), P(p[k]!), P(p[a]!)], width: lw * 1.25, color: ink)
            stroke([P(fk.marker(heel)), P(fk.marker(toe))], width: lw * 1.4, color: accent)
        }
        // torso: pelvis → chest → neck as a gentle curve
        stroke([P(p[.pelvis]!), P(p[.spine]!), P(p[.chest]!), P(p[.neck]!)], width: lw * 1.5, color: ink)
        // tutu: a flattened ellipse around the hips, oriented by the pelvis
        let pr = fk.rotation[.pelvis]!
        var tutu: [CGPoint] = []
        for i in 0...16 {
            let t = Float(i) / 16 * 2 * .pi
            let local = SIMD3<Float>(cos(t) * 0.33, -0.07 + (i % 2 == 0 ? 0 : -0.025), sin(t) * 0.33)
            tutu.append(P(p[.pelvis]! + pr.act(local)))
        }
        let tutuPath = Path.smooth(tutu, closed: true)
        ctx.fill(tutuPath, with: .color(accent.opacity(0.22)))
        ctx.stroke(tutuPath, with: .color(accent.opacity(0.85)), style: StrokeStyle(lineWidth: lw * 0.8, lineCap: .round))
        // arms
        for (s, e, w, h) in [(Joint.lShoulder, Joint.lElbow, Joint.lWrist, Marker.lHand),
                             (Joint.rShoulder, Joint.rElbow, Joint.rWrist, Marker.rHand)] {
            stroke([P(p[.neck]!), P(p[s]!)], width: lw, color: ink)
            stroke([P(p[s]!), P(p[e]!), P(p[w]!), P(fk.marker(h))], width: lw, color: ink)
        }
        // head + bun
        let hr = fk.rotation[.head]!
        let hc = P(p[.head]! + hr.act([0, 0.11, 0]))
        let r = scale * 0.095
        let head = Path(ellipseIn: CGRect(x: hc.x - r * 0.9, y: hc.y - r, width: r * 1.8, height: r * 2))
        ctx.fill(head, with: .color(Theme.paper))
        stroke(WobblyCircle(seed: rng.next(), wobble: 0.03, overshoot: 0.1)
            .path(in: CGRect(x: hc.x - r * 0.9, y: hc.y - r, width: r * 1.8, height: r * 2))
            .cgPathPoints(), width: lw, color: ink)
        let bun = P(p[.head]! + hr.act([0, 0.17, -0.1]))
        ctx.fill(Path(ellipseIn: CGRect(x: bun.x - r * 0.42, y: bun.y - r * 0.42, width: r * 0.84, height: r * 0.84)),
                 with: .color(ink.opacity(0.85)))
    }
}

private extension Path {
    /// Flatten a path into points (good enough for re-stroking a smooth shape).
    func cgPathPoints() -> [CGPoint] {
        var pts: [CGPoint] = []
        forEach { el in
            switch el {
            case .move(let p), .line(let p): pts.append(p)
            case .quadCurve(let p, _): pts.append(p)
            case .curve(let p, _, _): pts.append(p)
            case .closeSubpath: break
            }
        }
        return pts
    }
}

/// A paper tile holding a sketch.
struct SketchTile: View {
    let movement: Movement
    let poses: PoseLibrary
    var cornerRadius: CGFloat = 22

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius).fill(Theme.paper)
            Canvas { ctx, size in
                // dotted grid like sketchbook paper
                var y: CGFloat = 8
                while y < size.height {
                    var x: CGFloat = 8
                    while x < size.width {
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.2, height: 1.2)), with: .color(Theme.inkFaint.opacity(0.35)))
                        x += 12
                    }
                    y += 12
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            PoseSketch(movement: movement, poses: poses, accent: Theme.categoryColor(movement.category))
                .padding(8)
        }
    }
}
