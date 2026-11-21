import Foundation
import simd

// Mirrors backend/scripts/build_poses.py — keep the two in sync.
// Dancer faces +Z (the audience), +X is the dancer's LEFT, +Y is up.
// A joint's local rotation is Rz · Rx · Ry of its Euler angles (degrees), Y applied first.

enum Joint: String, CaseIterable {
    case pelvis
    case lHip = "l_hip", lKnee = "l_knee", lAnkle = "l_ankle"
    case rHip = "r_hip", rKnee = "r_knee", rAnkle = "r_ankle"
    case spine, chest, neck, head
    case lShoulder = "l_shoulder", lElbow = "l_elbow", lWrist = "l_wrist"
    case rShoulder = "r_shoulder", rElbow = "r_elbow", rWrist = "r_wrist"

    var parent: Joint? {
        switch self {
        case .pelvis: return nil
        case .lHip, .rHip, .spine: return .pelvis
        case .lKnee: return .lHip
        case .lAnkle: return .lKnee
        case .rKnee: return .rHip
        case .rAnkle: return .rKnee
        case .chest: return .spine
        case .neck, .lShoulder, .rShoulder: return .chest
        case .head: return .neck
        case .lElbow: return .lShoulder
        case .lWrist: return .lElbow
        case .rElbow: return .rShoulder
        case .rWrist: return .rElbow
        }
    }

    var offset: SIMD3<Float> {
        switch self {
        case .pelvis: return .zero
        case .lHip: return [0.09, -0.06, 0]
        case .rHip: return [-0.09, -0.06, 0]
        case .lKnee, .rKnee: return [0, -0.44, 0]
        case .lAnkle, .rAnkle: return [0, -0.42, 0]
        case .spine: return [0, 0.10, 0]
        case .chest: return [0, 0.22, 0]
        case .neck: return [0, 0.20, 0]
        case .head: return [0, 0.07, 0]
        case .lShoulder: return [0.17, 0.16, 0]
        case .rShoulder: return [-0.17, 0.16, 0]
        case .lElbow, .rElbow: return [0, -0.27, 0]
        case .lWrist, .rWrist: return [0, -0.24, 0]
        }
    }

    /// Left/right partner (for mirroring).
    var mirrored: Joint {
        switch self {
        case .lHip: return .rHip
        case .rHip: return .lHip
        case .lKnee: return .rKnee
        case .rKnee: return .lKnee
        case .lAnkle: return .rAnkle
        case .rAnkle: return .lAnkle
        case .lShoulder: return .rShoulder
        case .rShoulder: return .lShoulder
        case .lElbow: return .rElbow
        case .rElbow: return .lElbow
        case .lWrist: return .rWrist
        case .rWrist: return .lWrist
        default: return self
        }
    }

    /// Parents always precede children.
    static let order: [Joint] = Joint.allCases
}

enum Marker: CaseIterable {
    case lHeel, lToe, rHeel, rToe, headTop, lHand, rHand
    var attachment: (Joint, SIMD3<Float>) {
        switch self {
        case .lHeel: return (Joint.lAnkle, [0, -0.06, -0.04])
        case .lToe: return (Joint.lAnkle, [0, -0.055, 0.17])
        case .rHeel: return (Joint.rAnkle, [0, -0.06, -0.04])
        case .rToe: return (Joint.rAnkle, [0, -0.055, 0.17])
        case .headTop: return (Joint.head, [0, 0.22, 0])
        case .lHand: return (Joint.lWrist, [0, -0.08, 0])
        case .rHand: return (Joint.rWrist, [0, -0.08, 0])
        }
    }
}

typealias PoseAngles = [Joint: SIMD3<Float>]

@inline(__always) func radians(_ d: Float) -> Float { d * .pi / 180 }

func localRotation(_ e: SIMD3<Float>) -> simd_quatf {
    let qx = simd_quatf(angle: radians(e.x), axis: [1, 0, 0])
    let qy = simd_quatf(angle: radians(e.y), axis: [0, 1, 0])
    let qz = simd_quatf(angle: radians(e.z), axis: [0, 0, 1])
    return qz * qx * qy
}

struct FKResult {
    var position: [Joint: SIMD3<Float>] = [:]
    var rotation: [Joint: simd_quatf] = [:]
    func marker(_ m: Marker) -> SIMD3<Float> {
        let (j, off) = m.attachment
        return position[j, default: .zero] + rotation[j, default: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)].act(off)
    }
}

enum Kinematics {
    static func solve(_ angles: PoseAngles, root: SIMD3<Float>, yaw: Float) -> FKResult {
        var r = FKResult()
        let yawQ = simd_quatf(angle: radians(yaw), axis: [0, 1, 0])
        for j in Joint.order {
            let lr = localRotation(angles[j] ?? .zero)
            if let p = j.parent {
                let pr = r.rotation[p]!
                r.rotation[j] = pr * lr
                r.position[j] = r.position[p]! + pr.act(j.offset)
            } else {
                r.rotation[j] = yawQ * lr
                r.position[j] = root
            }
        }
        return r
    }
}

// MARK: - Pose library (poses.json)

enum Support: String, Decodable {
    case both, left, right, air
    var mirrored: Support { self == .left ? .right : self == .right ? .left : self }
}

struct PoseLibrary {
    struct LegsPart: Decodable { let support: Support; let lift: Float; let joints: [String: [Float]] }
    struct Part: Decodable { let joints: [String: [Float]] }
    struct File: Decodable {
        let standingRootY: Float
        let legs: [String: LegsPart]
        let arms: [String: Part]
        let torso: [String: Part]
    }

    let standingRootY: Float
    private let legs: [String: (Support, Float, PoseAngles)]
    private let arms: [String: PoseAngles]
    private let torso: [String: PoseAngles]

    static func load(bundle: Bundle = .main) -> PoseLibrary {
        guard let url = bundle.url(forResource: "poses", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else {
            assertionFailure("poses.json missing or invalid")
            return PoseLibrary(standingRootY: 0.98, legs: [:], arms: [:], torso: [:])
        }
        func angles(_ raw: [String: [Float]]) -> PoseAngles {
            var out = PoseAngles()
            for (k, v) in raw where v.count == 3 { if let j = Joint(rawValue: k) { out[j] = SIMD3(v[0], v[1], v[2]) } }
            return out
        }
        return PoseLibrary(
            standingRootY: file.standingRootY,
            legs: file.legs.mapValues { ($0.support, $0.lift, angles($0.joints)) },
            arms: file.arms.mapValues { angles($0.joints) },
            torso: file.torso.mapValues { angles($0.joints) })
    }

    private init(standingRootY: Float, legs: [String: (Support, Float, PoseAngles)], arms: [String: PoseAngles], torso: [String: PoseAngles]) {
        self.standingRootY = standingRootY; self.legs = legs; self.arms = arms; self.torso = torso
    }

    struct Composed { var angles: PoseAngles; var support: Support; var lift: Float }

    func compose(_ k: Keyframe) -> Composed {
        let (support, lift, legAngles) = legs[k.l] ?? (.both, 0, [:])
        var a = legAngles
        for (j, v) in arms[k.a] ?? [:] { a[j] = v }
        for (j, v) in torso[k.t] ?? [:] { a[j] = v }
        var c = Composed(angles: a, support: support, lift: k.lift ?? lift)
        if k.m == true { c = mirror(c) }
        return c
    }

    func mirror(_ c: Composed) -> Composed {
        var out = PoseAngles()
        for (j, v) in c.angles { out[j.mirrored] = SIMD3(v.x, -v.y, -v.z) }
        return Composed(angles: out, support: c.support.mirrored, lift: c.lift)
    }
}

// MARK: - Animator

struct DancerFrame {
    var angles: PoseAngles
    var root: SIMD3<Float>
    var yaw: Float
}

/// Turns a movement's keyframes into a looping, grounded animation.
final class MovementAnimator {
    private struct Key {
        let pose: PoseLibrary.Composed
        let yaw: Float
        let root: SIMD3<Float>
        let duration: Double
    }

    private let keys: [Key]
    private let library: PoseLibrary
    let cycle: Double

    init(movement: Movement, library: PoseLibrary) {
        self.library = library
        var ks: [Key] = []
        for k in movement.animation.keys {
            let pose = library.compose(k)
            let yaw = k.yaw ?? 0
            let root = MovementAnimator.groundedRoot(pose, yaw: yaw, dx: k.dx ?? 0, dz: k.dz ?? 0, library: library)
            ks.append(Key(pose: pose, yaw: yaw, root: root, duration: max(k.d, 0.05)))
        }
        if ks.isEmpty {
            let still = PoseLibrary.Composed(angles: [:], support: .both, lift: 0)
            ks = [Key(pose: still, yaw: 0, root: [0, library.standingRootY, 0], duration: 1)]
        }
        keys = ks
        cycle = ks.reduce(0) { $0 + $1.duration }
    }

    /// Root placement so the supporting foot (or feet) rest on the floor at the key's travel offset.
    private static func groundedRoot(_ p: PoseLibrary.Composed, yaw: Float, dx: Float, dz: Float, library: PoseLibrary) -> SIMD3<Float> {
        if p.support == .air { return [dx, library.standingRootY + p.lift, dz] }
        let fk = Kinematics.solve(p.angles, root: [0, library.standingRootY, 0], yaw: yaw)
        let feet = supportMarkers(p.support)
        let low = feet.map { fk.marker($0).y }.min() ?? 0
        let anchor: SIMD3<Float>
        switch p.support {
        case .left: anchor = fk.position[.lAnkle]!
        case .right: anchor = fk.position[.rAnkle]!
        default: anchor = (fk.position[.lAnkle]! + fk.position[.rAnkle]!) / 2
        }
        return [dx - anchor.x, library.standingRootY - low, dz - anchor.z]
    }

    private static func supportMarkers(_ s: Support) -> [Marker] {
        switch s {
        case .left: return [.lHeel, .lToe]
        case .right: return [.rHeel, .rToe]
        default: return [.lHeel, .lToe, .rHeel, .rToe]
        }
    }

    /// The frame used for thumbnails.
    func pose(at index: Int) -> DancerFrame {
        let k = keys[min(max(index, 0), keys.count - 1)]
        return DancerFrame(angles: k.pose.angles, root: k.root, yaw: k.yaw)
    }

    func sample(at time: Double) -> DancerFrame {
        guard keys.count > 1 else { return pose(at: 0) }
        var t = time.truncatingRemainder(dividingBy: cycle)
        if t < 0 { t += cycle }
        // segments: k0→k1 (k1.d), …, k(n-1)→k0 (k0.d)
        var i = 1
        while true {
            let target = i % keys.count
            let d = keys[target].duration
            if t <= d || i >= keys.count {
                let a = keys[i - 1], b = keys[target]
                let u = Float(min(max(t / d, 0), 1))
                let e = u * u * (3 - 2 * u) // smoothstep
                return blend(a, b, e, wrapping: target == 0)
            }
            t -= d; i += 1
        }
    }

    private func blend(_ a: Key, _ b: Key, _ e: Float, wrapping: Bool) -> DancerFrame {
        var angles = PoseAngles()
        for j in Joint.allCases {
            let va = a.pose.angles[j] ?? .zero, vb = b.pose.angles[j] ?? .zero
            angles[j] = va + (vb - va) * e
        }
        // when looping back, keep turning forward instead of unwinding
        var yawB = b.yaw
        if wrapping { yawB += 360 * ((a.yaw - b.yaw) / 360).rounded() }
        let yaw = a.yaw + (yawB - a.yaw) * e
        var root = a.root + (b.root - a.root) * e

        // keep feet planted while both keys stand on the same support
        if a.pose.support == b.pose.support, a.pose.support != .air {
            let fk = Kinematics.solve(angles, root: root, yaw: yaw)
            let low = MovementAnimator.supportMarkers(a.pose.support).map { fk.marker($0).y }.min() ?? 0
            root.y -= low
        } else if a.pose.support == .air || b.pose.support == .air {
            // a little parabola on top of the blend so jumps float
            root.y += 0.06 * sin(e * .pi)
        }
        // never let a gesture foot sweep through the floor mid-transition
        let check = Kinematics.solve(angles, root: root, yaw: yaw)
        let lowest = [Marker.lHeel, .lToe, .rHeel, .rToe].map { check.marker($0).y }.min() ?? 0
        if lowest < 0 { root.y -= lowest }
        return DancerFrame(angles: angles, root: root, yaw: yaw)
    }
}
