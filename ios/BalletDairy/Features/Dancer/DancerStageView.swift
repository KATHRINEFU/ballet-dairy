import SceneKit
import SwiftUI
import UIKit

/// Camera presets for the stage.
enum StageAngle: String, CaseIterable, Identifiable {
    case front = "Front", threeQuarter = "¾", side = "Side", back = "Back"
    var id: String { rawValue }
    var azimuth: Float {
        switch self {
        case .front: 0
        case .threeQuarter: -35
        case .side: -90
        case .back: 180
        }
    }
}

/// The 3D practice stage: a porcelain mannequin in a leotard, tights, pointe shoes and an optional tutu,
/// animated by `MovementAnimator`, with glowing muscle overlays.
struct DancerStageView: UIViewRepresentable {
    let movement: Movement
    let poses: PoseLibrary
    var isPlaying: Bool = true
    var speed: Double = 1
    var showMuscles: Bool = true
    var showTutu: Bool = true
    var focusMuscle: Muscle? = nil
    var angle: StageAngle = .threeQuarter

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.isPlaying = true
        view.allowsCameraControl = true
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.maximumVerticalAngle = 35
        view.defaultCameraController.minimumVerticalAngle = -5
        view.defaultCameraController.target = SCNVector3(0, 0.95, 0)

        let c = context.coordinator
        c.build(in: view)
        c.configure(movement: movement, poses: poses)
        c.apply(self, animatedCamera: false)
        view.delegate = c
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let c = context.coordinator
        if c.movementID != movement.id { c.configure(movement: movement, poses: poses) }
        c.apply(self, animatedCamera: true)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        private(set) var movementID: String?
        private var animator: MovementAnimator?
        private var joints: [Joint: SCNNode] = [:]
        private let root = SCNNode()
        private let tutu = SCNNode()
        private let barre = SCNNode()
        private var cameraNode = SCNNode()
        private var muscleNodes: [Muscle: [SCNNode]] = [:]
        private weak var view: SCNView?

        // driven from SwiftUI, read on the render thread
        var isPlaying = true
        var speed: Double = 1
        var showMuscles = true
        var primary: Set<Muscle> = []
        var secondary: Set<Muscle> = []
        private var angle: StageAngle?

        private var animTime: Double = 0
        private var lastTime: TimeInterval?

        // MARK: build

        func build(in view: SCNView) {
            self.view = view
            let scene = SCNScene()
            scene.background.contents = UIColor.clear
            view.scene = scene

            let cam = SCNCamera()
            cam.fieldOfView = 30
            cam.zNear = 0.05
            cam.wantsHDR = false
            cameraNode.camera = cam
            scene.rootNode.addChildNode(cameraNode)
            view.pointOfView = cameraNode

            // light: soft studio key + warm fill + ambient
            let key = SCNNode(); key.light = SCNLight()
            key.light!.type = .directional
            key.light!.intensity = 900
            key.light!.color = UIColor(hex: 0xFFF7F2)
            key.light!.castsShadow = true
            key.light!.shadowMode = .deferred
            key.light!.shadowColor = UIColor(hex: 0x3A2E35, alpha: 0.22)
            key.light!.shadowRadius = 10
            key.light!.shadowSampleCount = 16
            key.light!.orthographicScale = 3
            key.eulerAngles = SCNVector3(-1.05, 0.45, 0)
            scene.rootNode.addChildNode(key)

            let fill = SCNNode(); fill.light = SCNLight()
            fill.light!.type = .omni
            fill.light!.intensity = 380
            fill.light!.color = UIColor(hex: 0xF6C9D2)
            fill.position = SCNVector3(-2.2, 1.6, 1.8)
            scene.rootNode.addChildNode(fill)

            let rim = SCNNode(); rim.light = SCNLight()
            rim.light!.type = .directional
            rim.light!.intensity = 350
            rim.light!.color = UIColor(hex: 0xD9D0F0)
            rim.eulerAngles = SCNVector3(-0.4, .pi * 0.9, 0)
            scene.rootNode.addChildNode(rim)

            let amb = SCNNode(); amb.light = SCNLight()
            amb.light!.type = .ambient
            amb.light!.intensity = 320
            amb.light!.color = UIColor(hex: 0xFFF1EE)
            scene.rootNode.addChildNode(amb)

            // shadow-catching floor
            let floorGeo = SCNPlane(width: 8, height: 8)
            let floorMat = SCNMaterial()
            floorMat.lightingModel = .shadowOnly
            floorGeo.materials = [floorMat]
            let floor = SCNNode(geometry: floorGeo)
            floor.eulerAngles.x = -.pi / 2
            scene.rootNode.addChildNode(floor)

            buildBarre(scene.rootNode)
            buildBody(scene.rootNode)
        }

        private func material(_ hex: UInt32, shininess: CGFloat = 0.15, specular: UInt32 = 0xFFFFFF, specIntensity: CGFloat = 0.25) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .blinn
            m.diffuse.contents = UIColor(hex: hex)
            m.specular.contents = UIColor(hex: specular)
            m.specular.intensity = specIntensity
            m.shininess = shininess
            return m
        }

        private func ellipsoid(_ scale: SIMD3<Float>, at p: SIMD3<Float>, _ mat: SCNMaterial) -> SCNNode {
            let s = SCNSphere(radius: 1); s.segmentCount = 36; s.materials = [mat]
            let n = SCNNode(geometry: s); n.simdScale = scale; n.simdPosition = p
            n.castsShadow = true
            return n
        }

        private func capsule(radius: CGFloat, length: CGFloat, at p: SIMD3<Float>, _ mat: SCNMaterial) -> SCNNode {
            let c = SCNCapsule(capRadius: radius, height: length + radius * 2)
            c.radialSegmentCount = 28; c.materials = [mat]
            let n = SCNNode(geometry: c); n.simdPosition = p
            return n
        }

        private func buildBody(_ parent: SCNNode) {
            parent.addChildNode(root)
            for j in Joint.order {
                let n = SCNNode(); n.name = j.rawValue
                n.simdPosition = j.offset
                joints[j] = n
                (j.parent.flatMap { joints[$0] } ?? root).addChildNode(n)
            }
            let skin = material(0xF3E6DF, shininess: 0.2, specIntensity: 0.18)
            let leotard = material(0xC97F92, shininess: 0.35, specIntensity: 0.35)
            let tights = material(0xF2D3D2, shininess: 0.4, specIntensity: 0.3)
            let satin = material(0xEFC0C3, shininess: 0.8, specIntensity: 0.7)
            let hair = material(0x4A3A3E, shininess: 0.5, specIntensity: 0.3)

            // torso
            joints[.pelvis]!.addChildNode(ellipsoid(SIMD3(0.145, 0.105, 0.10), at: SIMD3(0, -0.03, 0), leotard))
            joints[.spine]!.addChildNode(ellipsoid([0.105, 0.14, 0.085], at: [0, 0.11, 0], leotard))
            joints[.chest]!.addChildNode(ellipsoid([0.14, 0.145, 0.095], at: [0, 0.08, 0], leotard))
            joints[.chest]!.addChildNode(ellipsoid([0.15, 0.04, 0.07], at: [0, 0.16, -0.005], skin)) // shoulders/collarbone
            joints[.neck]!.addChildNode(capsule(radius: 0.034, length: 0.08, at: [0, 0.02, 0], skin))
            joints[.head]!.addChildNode(ellipsoid([0.083, 0.108, 0.093], at: [0, 0.11, 0.005], skin))
            joints[.head]!.addChildNode(ellipsoid([0.088, 0.07, 0.09], at: [0, 0.155, -0.012], hair))
            joints[.head]!.addChildNode(ellipsoid([0.045, 0.045, 0.045], at: [0, 0.17, -0.1], hair)) // bun

            for s: Float in [1, -1] {
                let hip = joints[s > 0 ? .lHip : .rHip]!, knee = joints[s > 0 ? .lKnee : .rKnee]!
                let ankle = joints[s > 0 ? .lAnkle : .rAnkle]!
                hip.addChildNode(capsule(radius: 0.064, length: 0.36, at: [0, -0.21, 0], tights))
                knee.addChildNode(capsule(radius: 0.044, length: 0.36, at: [0, -0.2, 0], tights))
                let foot = capsule(radius: 0.031, length: 0.17, at: [0, -0.045, 0.06], satin)
                foot.eulerAngles.x = .pi / 2
                ankle.addChildNode(foot)

                let sh = joints[s > 0 ? .lShoulder : .rShoulder]!, el = joints[s > 0 ? .lElbow : .rElbow]!
                let wr = joints[s > 0 ? .lWrist : .rWrist]!
                sh.addChildNode(capsule(radius: 0.037, length: 0.22, at: [0, -0.13, 0], skin))
                el.addChildNode(capsule(radius: 0.029, length: 0.2, at: [0, -0.12, 0], skin))
                wr.addChildNode(ellipsoid([0.024, 0.055, 0.014], at: [0, -0.045, 0], skin))
            }

            // romantic-meets-classical tutu: layered tulle discs
            for (i, r) in [CGFloat(0.36), 0.33, 0.29].enumerated() {
                let cone = SCNCone(topRadius: 0.13, bottomRadius: r, height: 0.05)
                let m = SCNMaterial()
                m.lightingModel = .blinn
                m.diffuse.contents = UIColor(hex: i == 0 ? 0xF7D7DC : 0xF4C9D1)
                m.transparency = 0.62
                m.isDoubleSided = true
                m.writesToDepthBuffer = false
                cone.materials = [m]
                let n = SCNNode(geometry: cone)
                n.position = SCNVector3(0, -0.06 - Float(i) * 0.018, 0)
                n.castsShadow = false
                tutu.addChildNode(n)
            }
            joints[.pelvis]!.addChildNode(tutu)

            buildMuscles()
        }

        private func buildBarre(_ parent: SCNNode) {
            let wood = material(0xD8BFA8, shininess: 0.5, specIntensity: 0.25)
            let rail = SCNCylinder(radius: 0.022, height: 2.0); rail.materials = [wood]
            let railNode = SCNNode(geometry: rail)
            railNode.eulerAngles.x = .pi / 2
            railNode.position = SCNVector3(0.52, 1.22, 0.2)
            barre.addChildNode(railNode)
            for z: Float in [-0.6, 1.0] {
                let post = SCNCylinder(radius: 0.016, height: 1.22); post.materials = [wood]
                let p = SCNNode(geometry: post); p.position = SCNVector3(0.58, 0.61, z)
                barre.addChildNode(p)
                let arm = SCNCylinder(radius: 0.012, height: 0.08); arm.materials = [wood]
                let a = SCNNode(geometry: arm); a.eulerAngles.z = .pi / 2; a.position = SCNVector3(0.55, 1.22, z)
                barre.addChildNode(a)
            }
            parent.addChildNode(barre)
        }

        /// Anatomical overlay spots: (muscle, joint, position, scale, mirrored to both sides?)
        private func buildMuscles() {
            typealias Spot = (Muscle, Joint, SIMD3<Float>, SIMD3<Float>)
            var spots: [Spot] = []
            func add(_ m: Muscle, _ j: Joint, _ p: SIMD3<Float>, _ sc: SIMD3<Float>) { spots.append((m, j, p, sc)) }
            add(.core, .spine, SIMD3(0, 0.1, 0.07), SIMD3(0.07, 0.11, 0.03))
            add(.trapezius, .chest, SIMD3(0, 0.15, -0.06), SIMD3(0.11, 0.05, 0.035))
            for s: Float in [1, -1] {
                let left = s > 0
                let hip: Joint = left ? .lHip : .rHip
                let knee: Joint = left ? .lKnee : .rKnee
                let ankle: Joint = left ? .lAnkle : .rAnkle
                let shoulder: Joint = left ? .lShoulder : .rShoulder
                add(.quadriceps, hip, SIMD3(0, -0.21, 0.045), SIMD3(0.052, 0.17, 0.035))
                add(.hamstrings, hip, SIMD3(0, -0.23, -0.045), SIMD3(0.05, 0.17, 0.035))
                add(.adductors, hip, SIMD3(-s * 0.042, -0.14, 0), SIMD3(0.03, 0.13, 0.04))
                add(.hip_flexors, .pelvis, SIMD3(s * 0.075, -0.05, 0.075), SIMD3(0.04, 0.05, 0.025))
                add(.glutes, .pelvis, SIMD3(s * 0.065, -0.05, -0.075), SIMD3(0.07, 0.07, 0.045))
                add(.deep_rotators, .pelvis, SIMD3(s * 0.07, -0.09, -0.06), SIMD3(0.05, 0.025, 0.03))
                add(.calves, knee, SIMD3(0, -0.12, -0.035), SIMD3(0.04, 0.12, 0.032))
                add(.tibialis, knee, SIMD3(s * 0.012, -0.19, 0.03), SIMD3(0.018, 0.12, 0.018))
                add(.foot_intrinsics, ankle, SIMD3(0, -0.07, 0.07), SIMD3(0.03, 0.012, 0.075))
                add(.obliques, .spine, SIMD3(s * 0.085, 0.1, 0.03), SIMD3(0.03, 0.1, 0.05))
                add(.erector_spinae, .spine, SIMD3(s * 0.03, 0.12, -0.075), SIMD3(0.022, 0.15, 0.02))
                add(.lats, .chest, SIMD3(s * 0.1, 0.02, -0.06), SIMD3(0.04, 0.1, 0.03))
                add(.deltoids, shoulder, SIMD3(0, -0.025, 0), SIMD3(0.05, 0.055, 0.05))
                add(.arms, shoulder, SIMD3(0, -0.15, 0), SIMD3(0.04, 0.1, 0.04))
            }
            for (muscle, joint, pos, scale) in spots {
                let sphere = SCNSphere(radius: 1); sphere.segmentCount = 24
                let m = SCNMaterial()
                m.lightingModel = .constant
                m.diffuse.contents = UIColor(hex: 0xE0556F)
                m.emission.contents = UIColor(hex: 0xFF8FA6)
                m.blendMode = .alpha
                m.writesToDepthBuffer = false
                sphere.materials = [m]
                let n = SCNNode(geometry: sphere)
                n.simdPosition = pos; n.simdScale = scale
                n.opacity = 0
                n.castsShadow = false
                n.renderingOrder = 10
                joints[joint]!.addChildNode(n)
                muscleNodes[muscle, default: []].append(n)
            }
        }

        // MARK: configure

        func configure(movement: Movement, poses: PoseLibrary) {
            movementID = movement.id
            animator = MovementAnimator(movement: movement, library: poses)
            animTime = 0
            barre.isHidden = movement.category != "barre" && !movement.animation.keys.contains { $0.a.hasPrefix("barre") }
            primary = Set(movement.muscles.primary)
            secondary = Set(movement.muscles.secondary)
            if let f = animator?.sample(at: 0) { applyFrame(f) }
        }

        func apply(_ v: DancerStageView, animatedCamera: Bool) {
            isPlaying = v.isPlaying
            speed = v.speed
            showMuscles = v.showMuscles
            tutu.isHidden = !v.showTutu
            if let focus = v.focusMuscle {
                primary = [focus]; secondary = []
            } else {
                primary = Set(v.movement.muscles.primary); secondary = Set(v.movement.muscles.secondary)
            }
            if angle != v.angle {
                angle = v.angle
                placeCamera(v.angle, animated: animatedCamera)
            }
        }

        private func placeCamera(_ a: StageAngle, animated: Bool) {
            let target = SIMD3<Float>(0, 0.95, 0)
            let dist: Float = 4.8, elev: Float = radians(9)
            let az = radians(a.azimuth)
            let pos = target + SIMD3(sin(az) * cos(elev) * dist, sin(elev) * dist + 0.1, cos(az) * cos(elev) * dist)
            let pov = view?.pointOfView ?? cameraNode
            SCNTransaction.begin()
            SCNTransaction.animationDuration = animated ? 0.6 : 0
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pov.simdPosition = pos
            pov.simdLook(at: target, up: [0, 1, 0], localFront: [0, 0, -1])
            SCNTransaction.commit()
        }

        // MARK: render loop

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            let dt = lastTime.map { min(time - $0, 1.0 / 20) } ?? 0
            lastTime = time
            if isPlaying { animTime += dt * speed }
            if let f = animator?.sample(at: animTime) { applyFrame(f) }

            let pulse = Float(0.5 + 0.5 * sin(time * 3.2))
            for (muscle, nodes) in muscleNodes {
                let target: CGFloat
                if !showMuscles { target = 0 }
                else if primary.contains(muscle) { target = CGFloat(0.42 + 0.33 * pulse) }
                else if secondary.contains(muscle) { target = 0.24 }
                else { target = 0 }
                for n in nodes { n.opacity += (target - n.opacity) * 0.18 }
            }
        }

        private func applyFrame(_ f: DancerFrame) {
            root.simdPosition = f.root
            for j in Joint.order {
                let q = localRotation(f.angles[j] ?? .zero)
                if j == .pelvis {
                    joints[j]?.simdOrientation = simd_quatf(angle: radians(f.yaw), axis: [0, 1, 0]) * q
                } else {
                    joints[j]?.simdOrientation = q
                }
            }
        }
    }
}
