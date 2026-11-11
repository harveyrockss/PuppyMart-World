import SceneKit
import SwiftUI

// MARK: - Dog

final class Dog {
    let breed: Breed
    let node: SCNNode       // the dog itself
    let ears: SCNNode       // ears poking out of the bush
    let bush: SCNNode
    let bushPos: SCNVector3
    var peek: Float = 0

    init(breed: Breed, node: SCNNode, ears: SCNNode, bush: SCNNode, bushPos: SCNVector3) {
        self.breed = breed; self.node = node; self.ears = ears
        self.bush = bush; self.bushPos = bushPos
    }
}

// MARK: - Game

final class GameScene: NSObject, ObservableObject, SCNSceneRendererDelegate {

    // Scene graph
    let scene = SCNScene()
    let playerNode = SCNNode()
    let cameraNode = SCNNode()
    let sunNode = SCNNode()

    // Input (written from the UI, read on the render thread)
    var input = CGPoint.zero
    var yawTarget: Float = 0

    // State
    private var yaw: Float = 0
    private var lastT: TimeInterval = 0
    private var walkPhase: Float = 0
    private var dogs: [Dog] = []
    private var obstacles: [(x: Float, z: Float, r: Float)] = []
    private var rng = SeededRNG(seed: 20261111)
    private var lastNear: Int = -1

    // Published UI state
    @Published var coins = 0
    @Published var found = 0
    @Published var hidingCount = 0
    @Published var canCatch = false
    @Published var toast: String? = nil

    // Catch mini-game
    @Published var catching: Dog? = nil
    @Published var marker: Double = 0
    @Published var zoneStart: Double = 0.35
    @Published var zoneWidth: Double = 0.3
    @Published var triesLeft = 3
    private var markerDir: Double = 1
    private var zoneVel: Double = 0.2
    private var hopTimer: Double = 1.5
    private var catchTimer: Timer?

    override init() {
        super.init()
        buildWorld()
    }

    // MARK: Random helpers

    private func rand(_ a: Float, _ b: Float) -> Float {
        a + Float.random(in: 0...1, using: &rng) * (b - a)
    }

    private func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t = max(0, min(1, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    private func mat(_ c: UIColor, rough: CGFloat = 0.85) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = c
        m.lightingModel = .physicallyBased
        m.roughness.contents = rough
        m.metalness.contents = 0.0
        return m
    }

    // MARK: World

    private func buildWorld() {
        let sky = hex(0xBFE4F7)
        scene.background.contents = sky
        scene.fogColor = sky
        scene.fogStartDistance = 45
        scene.fogEndDistance = 130
        scene.fogDensityExponent = 1.5

        // Lights
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = hex(0xDDEBFF)
        ambient.light?.intensity = 650
        scene.rootNode.addChildNode(ambient)

        let sun = SCNLight()
        sun.type = .directional
        sun.color = hex(0xFFF0D0)
        sun.intensity = 1500
        sun.castsShadow = true
        sun.shadowMode = .deferred
        sun.shadowRadius = 4
        sun.shadowSampleCount = 8
        sun.shadowColor = UIColor(white: 0, alpha: 0.35)
        sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-0.95, -0.6, 0)
        scene.rootNode.addChildNode(sunNode)

        // Ground
        let ground = SCNPlane(width: 400, height: 400)
        ground.materials = [mat(hex(0x7CC35A), rough: 1)]
        let groundNode = SCNNode(geometry: ground)
        groundNode.eulerAngles.x = -.pi / 2
        scene.rootNode.addChildNode(groundNode)

        // Dirt clearing at spawn
        let clearing = SCNCylinder(radius: 7, height: 0.04)
        clearing.materials = [mat(hex(0xD9B77E), rough: 1)]
        let clearingNode = SCNNode(geometry: clearing)
        clearingNode.position = SCNVector3(0, 0.02, 0)
        scene.rootNode.addChildNode(clearingNode)

        addLamp(x: 3.5, z: -3)
        addSign(x: -3.2, z: -2.5)

        // Flowers
        let flowerColors: [UInt32] = [0xFF7DA8, 0xFFD84D, 0xFFFFFF, 0xB28DFF]
        for _ in 0..<140 {
            let a = rand(0, .pi * 2), d = rand(8, 75)
            let f = SCNSphere(radius: 0.13)
            f.materials = [mat(hex(flowerColors[Int(rand(0, 3.99))]))]
            let n = SCNNode(geometry: f)
            n.position = SCNVector3(cos(a) * d, 0.18, sin(a) * d)
            scene.rootNode.addChildNode(n)
        }

        // Trees
        for i in 0..<90 {
            let a = rand(0, .pi * 2), d = rand(11, 80)
            addTree(x: cos(a) * d, z: sin(a) * d, pine: i % 3 != 0)
        }
        // Dense ring of trees at the edge
        for i in 0..<60 {
            let a = Float(i) / 60 * .pi * 2, d = rand(84, 92)
            addTree(x: cos(a) * d, z: sin(a) * d, pine: i % 2 == 0)
        }

        // Plain bushes (decoys)
        for _ in 0..<40 {
            let a = rand(0, .pi * 2), d = rand(9, 70)
            _ = addBush(x: cos(a) * d, z: sin(a) * d)
        }

        buildPlayer()

        // Camera
        let cam = SCNCamera()
        cam.fieldOfView = 55
        cam.zNear = 0.1
        cam.zFar = 300
        cam.wantsHDR = true
        cam.bloomIntensity = 0.5
        cam.bloomThreshold = 0.85
        cam.bloomBlurRadius = 8
        cam.vignettingIntensity = 0.5
        cam.vignettingPower = 1.2
        cam.saturation = 1.12
        cam.contrast = 0.05
        cameraNode.camera = cam
        cameraNode.position = SCNVector3(0, 8, 9)
        scene.rootNode.addChildNode(cameraNode)

        // Dogs
        for _ in 0..<6 { spawnDog() }
        hidingCount = dogs.count
    }

    private func addTree(x: Float, z: Float, pine: Bool) {
        let tree = SCNNode()
        let trunkH: CGFloat = pine ? 1.4 : 1.8
        let trunk = SCNCylinder(radius: 0.22, height: trunkH)
        trunk.materials = [mat(hex(0x7A5230))]
        let t = SCNNode(geometry: trunk)
        t.position = SCNVector3(0, Float(trunkH) / 2, 0)
        tree.addChildNode(t)

        if pine {
            let greens: [UInt32] = [0x2E7D4F, 0x35915A, 0x3FA566]
            for k in 0..<3 {
                let cone = SCNCone(topRadius: 0, bottomRadius: CGFloat(1.5 - Float(k) * 0.35), height: 1.8)
                cone.materials = [mat(hex(greens[k]))]
                let c = SCNNode(geometry: cone)
                c.position = SCNVector3(0, Float(trunkH) + 0.7 + Float(k) * 1.0, 0)
                tree.addChildNode(c)
            }
        } else {
            for k in 0..<3 {
                let s = SCNSphere(radius: CGFloat(rand(1.0, 1.4)))
                s.materials = [mat(hex(k == 0 ? 0x4FB26A : 0x63C77A))]
                let c = SCNNode(geometry: s)
                c.position = SCNVector3(rand(-0.6, 0.6), Float(trunkH) + 1.0 + rand(0, 0.9), rand(-0.6, 0.6))
                tree.addChildNode(c)
            }
        }
        tree.position = SCNVector3(x, 0, z)
        tree.eulerAngles.y = rand(0, .pi * 2)
        tree.scale = SCNVector3(1, 1, 1).scaled(rand(0.9, 1.35))
        scene.rootNode.addChildNode(tree)
        obstacles.append((x, z, 0.7))
    }

    private func addBush(x: Float, z: Float) -> SCNNode {
        let bush = SCNNode()
        for k in 0..<4 {
            let s = SCNSphere(radius: CGFloat(rand(0.6, 0.85)))
            s.materials = [mat(hex(k % 2 == 0 ? 0x3F9E4F : 0x58B964))]
            let n = SCNNode(geometry: s)
            n.position = SCNVector3(rand(-0.5, 0.5), 0.55 + rand(0, 0.25), rand(-0.5, 0.5))
            bush.addChildNode(n)
        }
        bush.position = SCNVector3(x, 0, z)
        scene.rootNode.addChildNode(bush)
        return bush
    }

    private func addLamp(x: Float, z: Float) {
        let post = SCNCylinder(radius: 0.08, height: 3)
        post.materials = [mat(hex(0x2B2B33))]
        let p = SCNNode(geometry: post)
        p.position = SCNVector3(x, 1.5, z)
        scene.rootNode.addChildNode(p)
        let bulb = SCNSphere(radius: 0.3)
        let bm = mat(hex(0xFFE9A8))
        bm.emission.contents = hex(0xFFD36B)
        bm.emission.intensity = 1.6
        bulb.materials = [bm]
        let b = SCNNode(geometry: bulb)
        b.position = SCNVector3(x, 3.2, z)
        scene.rootNode.addChildNode(b)
        obstacles.append((x, z, 0.3))
    }

    private func addSign(x: Float, z: Float) {
        let post = SCNBox(width: 0.14, height: 1.6, length: 0.14, chamferRadius: 0.02)
        post.materials = [mat(hex(0x7A5230))]
        let p = SCNNode(geometry: post)
        p.position = SCNVector3(x, 0.8, z)
        scene.rootNode.addChildNode(p)
        let board = SCNBox(width: 1.3, height: 0.5, length: 0.08, chamferRadius: 0.04)
        board.materials = [mat(hex(0xF0DDB0))]
        let b = SCNNode(geometry: board)
        b.position = SCNVector3(x, 1.5, z)
        b.eulerAngles.y = 0.3
        scene.rootNode.addChildNode(b)
        obstacles.append((x, z, 0.4))
    }

    // MARK: Player (original avatar)

    private func buildPlayer() {
        let skin = hex(0xF0B48F), dress = hex(0xF06FA8), hair = hex(0x4A2A20), hat = hex(0xEFD58A)

        let body = SCNCapsule(capRadius: 0.32, height: 1.0)
        body.materials = [mat(dress)]
        let bn = SCNNode(geometry: body)
        bn.position = SCNVector3(0, 0.62, 0)
        bn.name = "body"
        playerNode.addChildNode(bn)

        let head = SCNSphere(radius: 0.36)
        head.materials = [mat(skin, rough: 0.6)]
        let hn = SCNNode(geometry: head)
        hn.position = SCNVector3(0, 1.4, 0)
        hn.name = "head"
        playerNode.addChildNode(hn)

        let hairG = SCNSphere(radius: 0.4)
        hairG.materials = [mat(hair)]
        let hairN = SCNNode(geometry: hairG)
        hairN.position = SCNVector3(0, 1.46, -0.07)
        hairN.scale = SCNVector3(1, 1, 1.0)
        playerNode.addChildNode(hairN)

        for sx: Float in [-1, 1] {
            let eye = SCNSphere(radius: 0.07)
            eye.materials = [mat(hex(0x1B1B1F), rough: 0.3)]
            let en = SCNNode(geometry: eye)
            en.position = SCNVector3(sx * 0.14, 1.4, 0.31)
            playerNode.addChildNode(en)
            let shine = SCNSphere(radius: 0.022)
            let sm = mat(.white); sm.emission.contents = UIColor.white
            shine.materials = [sm]
            let sn = SCNNode(geometry: shine)
            sn.position = SCNVector3(sx * 0.14 + 0.02, 1.43, 0.37)
            playerNode.addChildNode(sn)
            let cheek = SCNSphere(radius: 0.06)
            cheek.materials = [mat(hex(0xFF8FA0))]
            let cn = SCNNode(geometry: cheek)
            cn.position = SCNVector3(sx * 0.24, 1.3, 0.27)
            cn.scale = SCNVector3(1, 0.6, 0.5)
            playerNode.addChildNode(cn)
        }

        let brim = SCNCylinder(radius: 0.55, height: 0.05)
        brim.materials = [mat(hat)]
        let brimN = SCNNode(geometry: brim)
        brimN.position = SCNVector3(0, 1.66, 0)
        playerNode.addChildNode(brimN)
        let crown = SCNCylinder(radius: 0.3, height: 0.25)
        crown.materials = [mat(hat)]
        let crownN = SCNNode(geometry: crown)
        crownN.position = SCNVector3(0, 1.79, 0)
        playerNode.addChildNode(crownN)
        let band = SCNCylinder(radius: 0.31, height: 0.07)
        band.materials = [mat(hex(0xE0527F))]
        let bandN = SCNNode(geometry: band)
        bandN.position = SCNVector3(0, 1.72, 0)
        playerNode.addChildNode(bandN)

        for sx: Float in [-1, 1] {
            let foot = SCNBox(width: 0.2, height: 0.12, length: 0.3, chamferRadius: 0.05)
            foot.materials = [mat(.white)]
            let f = SCNNode(geometry: foot)
            f.position = SCNVector3(sx * 0.16, 0.06, 0.05)
            f.name = sx < 0 ? "footL" : "footR"
            playerNode.addChildNode(f)
        }

        playerNode.position = SCNVector3(0, 0, 4)
        scene.rootNode.addChildNode(playerNode)
    }

    // MARK: Dogs

    private func makeDogNode(_ b: Breed) -> SCNNode {
        let dog = SCNNode()
        let body = SCNCapsule(capRadius: 0.24, height: 0.85)
        body.materials = [mat(b.body)]
        let bn = SCNNode(geometry: body)
        bn.eulerAngles.x = .pi / 2
        bn.position = SCNVector3(0, 0.5, 0)
        dog.addChildNode(bn)

        let patch = SCNSphere(radius: 0.2)
        patch.materials = [mat(b.patch)]
        let pn = SCNNode(geometry: patch)
        pn.position = SCNVector3(0.12, 0.62, -0.1)
        pn.scale = SCNVector3(1, 0.7, 1)
        dog.addChildNode(pn)

        let head = SCNSphere(radius: 0.26)
        head.materials = [mat(b.body)]
        let hn = SCNNode(geometry: head)
        hn.position = SCNVector3(0, 0.82, 0.5)
        dog.addChildNode(hn)

        let snout = SCNSphere(radius: 0.14)
        snout.materials = [mat(b.patch == hex(0xFFFFFF) ? b.patch : b.body)]
        let sn = SCNNode(geometry: snout)
        sn.position = SCNVector3(0, 0.76, 0.72)
        sn.scale = SCNVector3(1, 0.8, 1.2)
        dog.addChildNode(sn)

        let nose = SCNSphere(radius: 0.055)
        nose.materials = [mat(hex(0x1A1A1A), rough: 0.3)]
        let nn = SCNNode(geometry: nose)
        nn.position = SCNVector3(0, 0.8, 0.86)
        dog.addChildNode(nn)

        for sx: Float in [-1, 1] {
            let eye = SCNSphere(radius: 0.05)
            eye.materials = [mat(hex(0x111111), rough: 0.2)]
            let en = SCNNode(geometry: eye)
            en.position = SCNVector3(sx * 0.11, 0.88, 0.7)
            dog.addChildNode(en)
            dog.addChildNode(makeEar(b, side: sx, atBush: false))
        }

        let tail = SCNCapsule(capRadius: 0.05, height: 0.4)
        tail.materials = [mat(b.body)]
        let tn = SCNNode(geometry: tail)
        tn.position = SCNVector3(0, 0.7, -0.55)
        tn.eulerAngles.x = -0.8
        tn.name = "tail"
        dog.addChildNode(tn)

        for (lx, lz): (Float, Float) in [(-0.14, 0.28), (0.14, 0.28), (-0.14, -0.28), (0.14, -0.28)] {
            let leg = SCNCylinder(radius: 0.065, height: 0.3)
            leg.materials = [mat(b.body)]
            let ln = SCNNode(geometry: leg)
            ln.position = SCNVector3(lx, 0.15, lz)
            dog.addChildNode(ln)
        }
        return dog
    }

    private func makeEar(_ b: Breed, side: Float, atBush: Bool) -> SCNNode {
        let ear: SCNNode
        if b.pointyEars {
            let g = SCNCone(topRadius: 0, bottomRadius: 0.1, height: 0.3)
            g.materials = [mat(b.body)]
            ear = SCNNode(geometry: g)
            ear.position = atBush ? SCNVector3(side * 0.18, 0, 0) : SCNVector3(side * 0.16, 1.08, 0.46)
            ear.eulerAngles.z = -side * 0.25
        } else {
            let g = SCNCapsule(capRadius: 0.09, height: 0.36)
            g.materials = [mat(b.patch.isWhiteish ? b.body : b.patch)]
            ear = SCNNode(geometry: g)
            ear.position = atBush ? SCNVector3(side * 0.2, 0, 0) : SCNVector3(side * 0.24, 0.8, 0.46)
            ear.eulerAngles.z = side * 0.35
        }
        return ear
    }

    private func pickBreed() -> Breed {
        // 60% common, 30% rare, 10% epic
        let r = rand(0, 100)
        let rarity = r < 60 ? 0 : (r < 90 ? 1 : 2)
        let pool = breeds.filter { $0.rarity == rarity }
        return pool[Int(rand(0, Float(pool.count) - 0.01))]
    }

    private func spawnDog() {
        let b = pickBreed()
        var x: Float = 0, z: Float = 0
        for _ in 0..<60 {
            let a = rand(0, .pi * 2), d = rand(12, 50)
            x = cos(a) * d; z = sin(a) * d
            let ok = !obstacles.contains { hypot($0.x - x, $0.z - z) < $0.r + 1.6 }
                && !dogs.contains { hypot($0.bushPos.x - x, $0.bushPos.z - z) < 6 }
                && hypot(playerNode.position.x - x, playerNode.position.z - z) > 10
            if ok { break }
        }
        let bush = addBush(x: x, z: z)
        let node = makeDogNode(b)
        node.position = SCNVector3(x, -0.8, z)
        scene.rootNode.addChildNode(node)

        // ears poking out of the top of the bush
        let ears = SCNNode()
        for sx: Float in [-1, 1] {
            let e = makeEar(b, side: sx, atBush: true)
            ears.addChildNode(e)
        }
        ears.position = SCNVector3(x, 1.28, z)
        scene.rootNode.addChildNode(ears)

        dogs.append(Dog(breed: b, node: node, ears: ears, bush: bush, bushPos: SCNVector3(x, 0, z)))
    }

    private func removeDog(_ d: Dog) {
        d.node.removeFromParentNode()
        d.ears.removeFromParentNode()
        d.bush.removeFromParentNode()
        dogs.removeAll { $0 === d }
    }

    // MARK: Per-frame update

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = lastT == 0 ? 0.016 : Float(min(0.05, time - lastT))
        lastT = time
        let t = Float(time)

        // Camera yaw
        yaw += (yawTarget - yaw) * min(1, dt * 6)

        // Movement relative to the camera
        let ix = Float(input.x), iy = Float(input.y)
        let mag = min(1, hypot(ix, iy))
        let fx = -sin(yaw), fz = -cos(yaw)
        let rx = cos(yaw), rz = -sin(yaw)
        var mx = fx * iy + rx * ix
        var mz = fz * iy + rz * ix
        let ml = hypot(mx, mz)
        if ml > 0.001 { mx /= ml; mz /= ml }
        let speed: Float = 6.2 * mag

        var px = playerNode.position.x + mx * speed * dt
        var pz = playerNode.position.z + mz * speed * dt
        for o in obstacles {
            let dx = px - o.x, dz = pz - o.z
            let d = hypot(dx, dz), minD = o.r + 0.45
            if d < minD && d > 0.0001 { px = o.x + dx / d * minD; pz = o.z + dz / d * minD }
        }
        for d in dogs {   // bushes block too
            let dx = px - d.bushPos.x, dz = pz - d.bushPos.z
            let dist = hypot(dx, dz)
            if dist < 1.1 && dist > 0.0001 { px = d.bushPos.x + dx / dist * 1.1; pz = d.bushPos.z + dz / dist * 1.1 }
        }
        let r = hypot(px, pz)
        if r > 86 { px *= 86 / r; pz *= 86 / r }
        playerNode.position.x = px
        playerNode.position.z = pz

        // Facing + walk bob
        if mag > 0.05 {
            let target = atan2(mx, mz)
            var diff = target - playerNode.eulerAngles.y
            while diff > .pi { diff -= 2 * .pi }
            while diff < -.pi { diff += 2 * .pi }
            playerNode.eulerAngles.y += diff * min(1, dt * 12)
            walkPhase += dt * 11 * mag
        } else {
            walkPhase *= 0.9
        }
        playerNode.position.y = abs(sin(walkPhase)) * 0.07
        playerNode.childNode(withName: "footL", recursively: false)?.position.z = 0.05 + sin(walkPhase) * 0.14
        playerNode.childNode(withName: "footR", recursively: false)?.position.z = 0.05 - sin(walkPhase) * 0.14

        // Camera follow
        let pitch: Float = 0.62, dist: Float = 9
        let target = SCNVector3(px, 1.4, pz)
        let cx = target.x + sin(yaw) * cos(pitch) * dist
        let cz = target.z + cos(yaw) * cos(pitch) * dist
        let cy = target.y + sin(pitch) * dist
        let k = min(1, dt * 8)
        cameraNode.position.x += (cx - cameraNode.position.x) * k
        cameraNode.position.y += (cy - cameraNode.position.y) * k
        cameraNode.position.z += (cz - cameraNode.position.z) * k
        cameraNode.look(at: target)

        // Sun follows the player so shadows stay sharp
        sunNode.position = SCNVector3(px + 20, 40, pz + 15)

        // Dogs peek out of bushes as you get close
        var nearest = -1
        var nearD: Float = 1e9
        for (i, d) in dogs.enumerated() {
            let dx = px - d.bushPos.x, dz = pz - d.bushPos.z
            let dist = hypot(dx, dz)
            let want = smooth(10, 3.6, dist)
            d.peek += (want - d.peek) * min(1, dt * 4)
            let dirX = dist > 0.001 ? dx / dist : 0, dirZ = dist > 0.001 ? dz / dist : 1
            let out = 0.15 + 1.05 * d.peek
            d.node.position = SCNVector3(d.bushPos.x + dirX * out, -0.8 + 0.8 * d.peek, d.bushPos.z + dirZ * out)
            d.node.eulerAngles.y = atan2(dirX, dirZ)
            d.node.childNode(withName: "tail", recursively: false)?.eulerAngles.z = sin(t * 14) * 0.5 * d.peek

            // ears twitch above the bush, then give way to the whole dog
            d.ears.isHidden = d.peek > 0.5
            d.ears.position.y = 1.28 + max(0, sin(t * 0.9 + d.bushPos.x)) * 0.08
            if let l = d.ears.childNodes.first, let rr = d.ears.childNodes.last {
                l.eulerAngles.x = max(0, sin(t * 2.3 + d.bushPos.x * 3)) * 0.5
                rr.eulerAngles.x = max(0, sin(t * 2.1 + d.bushPos.z * 3 + 1)) * 0.5
            }
            // bush wobble when a dog is hiding nearby
            d.bush.eulerAngles.z = sin(t * 9 + d.bushPos.x) * 0.03 * (1 - d.peek)

            if dist < 3.8 && d.peek > 0.6 && dist < nearD { nearD = dist; nearest = i }
        }
        if nearest != lastNear {
            lastNear = nearest
            let n = nearest
            DispatchQueue.main.async { self.canCatch = n >= 0 && self.catching == nil }
        }
    }

    // MARK: Actions

    func rotateCamera(_ delta: Float) { yawTarget += delta }

    func actPressed() {
        guard catching == nil, lastNear >= 0, lastNear < dogs.count else { return }
        startCatch(dogs[lastNear])
    }

    private func startCatch(_ d: Dog) {
        catching = d
        canCatch = false
        triesLeft = 3
        zoneWidth = rarityZone[d.breed.rarity]
        zoneStart = Double.random(in: 0.1...(0.9 - zoneWidth))
        zoneVel = (Bool.random() ? -1 : 1) * (0.18 + Double(d.breed.rarity) * 0.14)
        hopTimer = 1.5
        marker = 0
        markerDir = 1
        catchTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick(1.0 / 60.0) }
        RunLoop.main.add(timer, forMode: .common)
        catchTimer = timer
    }

    /// The marker sweeps back and forth, and the dog keeps running and
    /// jumping, so the green zone drifts and leaps around.
    private func tick(_ dt: Double) {
        guard let d = catching else { return }
        let rar = d.breed.rarity
        marker += markerDir * raritySpeed[rar] * dt
        if marker >= 1 { marker = 1; markerDir = -1 }
        if marker <= 0 { marker = 0; markerDir = 1 }

        zoneStart += zoneVel * dt
        if zoneStart <= 0.02 { zoneStart = 0.02; zoneVel = abs(zoneVel) }
        if zoneStart >= 0.98 - zoneWidth { zoneStart = 0.98 - zoneWidth; zoneVel = -abs(zoneVel) }

        hopTimer -= dt
        if hopTimer <= 0 {
            hopTimer = (rar == 0 ? 2.6 : rar == 1 ? 1.9 : 1.4) + Double.random(in: 0...0.8)
            zoneStart = Double.random(in: 0.03...(0.94 - zoneWidth))
            zoneVel = (Bool.random() ? -1 : 1) * (0.18 + Double(rar) * 0.14)
        }
    }

    func tryCatch() {
        guard let d = catching else { return }
        if marker >= zoneStart && marker <= zoneStart + zoneWidth {
            let reward = rarityCoins[d.breed.rarity]
            coins += reward
            found += 1
            endCatch()
            say("Caught a \(d.breed.name)! +\(reward) 🪙")
            removeDog(d)
            hidingCount = dogs.count
            lastNear = -1
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                self?.spawnDog(); self?.hidingCount = self?.dogs.count ?? 0
            }
        } else {
            triesLeft -= 1
            if triesLeft <= 0 {
                endCatch()
                say("The \(d.breed.name) got away! 🐕💨")
                removeDog(d)
                hidingCount = dogs.count
                lastNear = -1
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                    self?.spawnDog(); self?.hidingCount = self?.dogs.count ?? 0
                }
            } else {
                hopTimer = 0   // the dog hops away to a new spot
            }
        }
    }

    func cancelCatch() { endCatch() }

    private func endCatch() {
        catchTimer?.invalidate()
        catchTimer = nil
        catching = nil
    }

    private func say(_ s: String) {
        toast = s
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            if self?.toast == s { self?.toast = nil }
        }
    }
}

// MARK: - Small helpers

extension SCNVector3 {
    func scaled(_ k: Float) -> SCNVector3 { SCNVector3(x * k, y * k, z * k) }
}

extension UIColor {
    /// True for near-white colours (used to avoid white ears on white dogs).
    var isWhiteish: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return r > 0.9 && g > 0.9 && b > 0.9
    }
}
