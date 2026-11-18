import SpriteKit
import SwiftUI
import CoreImage
import simd

// MARK: - Textures

enum RLTex {
    private static var cache: [String: SKTexture] = [:]
    static func get(_ name: String, nearest: Bool = true) -> SKTexture {
        if let t = cache[name] { return t }
        let t = SKTexture(imageNamed: name)
        t.filteringMode = nearest ? .nearest : .linear
        cache[name] = t
        return t
    }
    private static var sheets: [String: [[SKTexture]]] = [:]
    /// Character sheet: 4 cols × 5 rows of 24×36 (rows: down, up, left, right, cast).
    static func sheet(_ name: String) -> [[SKTexture]] {
        if let s = sheets[name] { return s }
        let base = get(name)
        var rows: [[SKTexture]] = []
        for r in 0..<5 {
            var row: [SKTexture] = []
            for c in 0..<4 {
                let t = SKTexture(rect: CGRect(x: CGFloat(c) * 0.25, y: 1 - CGFloat(r + 1) * 0.2, width: 0.25, height: 0.2), in: base)
                t.filteringMode = .nearest
                row.append(t)
            }
            rows.append(row)
        }
        sheets[name] = rows
        return rows
    }
    static func glyph(_ i: Int) -> SKTexture {
        let base = get("fx_glyphs", nearest: false)
        let n: CGFloat = 5
        return SKTexture(rect: CGRect(x: CGFloat(i % 5) / n, y: 0, width: 1 / n, height: 1), in: base)
    }
}

// MARK: - Actor

final class RLActor: SKNode {
    let id: String
    let body = SKSpriteNode()
    let shadow = SKSpriteNode(texture: RLTex.get("fx_shadow"))
    var frames: [[SKTexture]]
    var dir = 0
    var animT: CGFloat = 0
    var moving = false
    var path: [CGPoint] = []
    var walkSpeed: CGFloat = 60
    var umbrella: SKSpriteNode?
    var casting = false
    var fleeTime: CGFloat = 0
    var fleeDir = CGVector.zero
    var idleTimer: CGFloat = .random(in: 2...5)
    var spotName = ""
    var leaving = false
    var lane: [CGPoint] = []
    var bubble: SKNode?
    let px: CGFloat

    init(id: String, sheet: String, scale: CGFloat = 1.4) {
        self.id = id
        self.frames = RLTex.sheet(sheet)
        self.px = scale
        super.init()
        shadow.setScale(scale * 0.9)
        shadow.alpha = 0.8
        shadow.zPosition = -0.5
        addChild(shadow)
        body.texture = frames[0][0]
        body.size = CGSize(width: 24 * scale, height: 36 * scale)
        body.anchorPoint = CGPoint(x: 0.5, y: 0.04)
        body.lightingBitMask = 1
        addChild(body)
    }
    required init?(coder: NSCoder) { fatalError() }

    func face(_ v: CGVector) {
        guard abs(v.dx) + abs(v.dy) > 0.01 else { return }
        if abs(v.dx) > abs(v.dy) * 0.9 { dir = v.dx > 0 ? 3 : 2 } else { dir = v.dy > 0 ? 1 : 0 }
    }

    func animate(_ dt: CGFloat) {
        if casting {
            animT += dt
            body.texture = frames[4][Int(animT * 10) % 4]
        } else if moving {
            animT += dt * (walkSpeed > 100 ? 1.6 : 1)
            body.texture = frames[dir][Int(animT * 8) % 4]
            body.yScale = 1
        } else {
            animT += dt
            body.texture = frames[dir][0]
            body.yScale = 1 + sin(animT * 2.2) * 0.012
        }
        zPosition = 100 + (800 - position.y) * 0.1
        if let u = umbrella { u.position.y = body.size.height * 0.98 + (moving ? abs(sin(animT * 8 * .pi / 2)) * 1.5 : 0) }
    }

    func say(_ text: String, color: SKColor, duration: TimeInterval = 3.6) {
        bubble?.removeFromParent()
        let node = SKNode()
        let label = SKLabelNode(fontNamed: "Inter-Medium")
        label.text = text
        label.fontSize = 11
        label.numberOfLines = 0
        label.preferredMaxLayoutWidth = 170
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.fontColor = SKColor(white: 0.95, alpha: 1)
        let f = label.frame.insetBy(dx: -9, dy: -6)
        let bg = SKShapeNode(rect: CGRect(x: -f.width / 2, y: -f.height / 2, width: f.width, height: f.height), cornerRadius: 9)
        bg.fillColor = SKColor(red: 0.05, green: 0.05, blue: 0.1, alpha: 0.86)
        bg.strokeColor = color.withAlphaComponent(0.85)
        bg.lineWidth = 1
        let tail = SKShapeNode(path: { let p = CGMutablePath(); p.move(to: CGPoint(x: -5, y: -f.height / 2 + 0.5)); p.addLine(to: CGPoint(x: 0, y: -f.height / 2 - 6)); p.addLine(to: CGPoint(x: 5, y: -f.height / 2 + 0.5)); return p }())
        tail.fillColor = bg.fillColor; tail.strokeColor = .clear
        node.addChild(bg); node.addChild(tail); node.addChild(label)
        node.position = CGPoint(x: 0, y: body.size.height + 14 + f.height / 2)
        node.zPosition = 400
        node.setScale(0.3); node.alpha = 0
        addChild(node)
        bubble = node
        node.run(.sequence([
            .group([.scale(to: 1, duration: 0.22), .fadeIn(withDuration: 0.15)]),
            .repeat(.sequence([.moveBy(x: 0, y: 2, duration: 0.6), .moveBy(x: 0, y: -2, duration: 0.6)]), count: Int(duration / 1.2) + 1),
            .group([.fadeOut(withDuration: 0.3), .moveBy(x: 0, y: 6, duration: 0.3)]),
            .removeFromParent(),
        ]))
    }
}

struct RLMini: Equatable {
    var player = CGPoint(x: 0.5, y: 0.5); var dir: CGFloat = 0
    var npcs: [String: CGPoint] = [:]; var drone: CGPoint? = nil; var zone: RLZone = .street
}

// MARK: - Scene

final class RLScene: SKScene {
    weak var game: RLGame?
    var map = RLWorld.street
    let world = SKNode()
    var bg = SKSpriteNode()
    var bgTexture = SKTexture()
    let fx = SKEffectNode()
    let fxGround = SKEffectNode()
    var shockShader: SKShader?
    var bloomOn = true
    let fxPlain = SKNode()
    let cam = SKCameraNode()
    var player: RLActor!
    var npcs: [String: RLActor] = [:]
    var walkers: [RLActor] = []
    var ambientLight = SKLightNode()
    var mapLights: [(node: SKLightNode, color: SKColor, flicker: Bool)] = []
    var playerLight = SKLightNode()
    var spellLights: [SKLightNode] = []
    var rain: SKEmitterNode?
    var splash: SKEmitterNode?
    var vignette = SKSpriteNode(texture: RLTex.get("fx_vignette", nearest: false))
    var grade = SKSpriteNode(color: .white, size: .zero)
    var flashNode = SKSpriteNode(color: .white, size: .zero)
    var chromaA = SKSpriteNode(texture: RLTex.get("fx_vignette", nearest: false))
    var chromaB = SKSpriteNode(texture: RLTex.get("fx_vignette", nearest: false))
    var fadeNode = SKSpriteNode(color: .black, size: .zero)

    // drone
    let drone = SKNode()
    let droneBody = SKSpriteNode()
    let droneShadow = SKSpriteNode(texture: RLTex.get("fx_shadow"))
    let droneCone = SKSpriteNode(texture: RLTex.get("fx_cone", nearest: false))
    let droneSpot = SKSpriteNode(texture: RLTex.get("g_soft", nearest: false))
    let droneLight = SKLightNode()
    var droneGround = CGPoint(x: 640, y: 360)
    var droneRoute: [CGPoint] = []
    var droneLeg = 0
    var droneScanCooldown: CGFloat = 12
    var droneFrames: [SKTexture] = []

    var lastTime: TimeInterval = 0
    var clock: TimeInterval = 0
    var hitStopUntil: TimeInterval = 0
    var trauma: CGFloat = 0
    var talkTarget: String?
    var tapPath: [CGPoint] = []
    var promptTimer: CGFloat = 0
    var miniTimer: CGFloat = 0
    var castLock = false
    var doorCooldown: CGFloat = 0
    var cooldowns: [RLSpell: TimeInterval] = [:]
    var baseScale: CGFloat = 1
    var zoom: CGFloat = 1
    var darkPulse: CGFloat = 0
    var built = false

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.02, green: 0.02, blue: 0.05, alpha: 1)
        scaleMode = .resizeFill
        if world.parent == nil { addChild(world) }
        if cam.parent == nil { addChild(cam); camera = cam; setupCameraOverlays() }
        if !built { build(); built = true }
        layoutOverlays()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard cam.parent != nil else { return }
        layoutOverlays()
    }

    // MARK: Build

    func reload() {
        guard let game else { return }
        map = RLWorld.map(game.state.zone)
        build()
        syncAudio()
    }

    func build() {
        guard let game else { return }
        map = RLWorld.map(game.state.zone)
        world.removeAllChildren()
        npcs = [:]; walkers = []; mapLights = []; spellLights = []
        fx.removeAllChildren(); fxPlain.removeAllChildren(); fxGround.removeAllChildren()

        bgTexture = RLTex.get(map.bg)
        bg = SKSpriteNode(texture: bgTexture, size: map.size)
        bg.anchorPoint = .zero
        bg.zPosition = 0
        bg.lightingBitMask = 1
        bg.normalTexture = bgTexture.generatingNormalMap(withSmoothness: 0.25, contrast: 0.55)
        world.addChild(bg)

        // ambient + map lights
        ambientLight = SKLightNode()
        ambientLight.categoryBitMask = 1
        ambientLight.lightColor = SKColor(white: 0.12, alpha: 1)
        ambientLight.ambientColor = map.ambient
        ambientLight.falloff = 4
        ambientLight.position = CGPoint(x: 640, y: 900)
        world.addChild(ambientLight)
        for l in map.lights {
            let n = SKLightNode()
            n.categoryBitMask = 1
            n.lightColor = l.color
            n.ambientColor = .black
            n.falloff = l.falloff
            n.position = l.at
            n.zPosition = 50
            world.addChild(n)
            mapLights.append((n, l.color, l.flicker))
        }
        playerLight = SKLightNode()
        playerLight.categoryBitMask = 1
        playerLight.lightColor = SKColor(red: 0.12, green: 0.45, blue: 0.55, alpha: 1)
        playerLight.ambientColor = .black
        playerLight.falloff = 3
        world.addChild(playerLight)
        for _ in 0..<2 {
            let n = SKLightNode()
            n.categoryBitMask = 1; n.lightColor = .black; n.ambientColor = .black; n.falloff = 1.2; n.isEnabled = false
            world.addChild(n); spellLights.append(n)
        }

        // puddles with ripple shader that samples the painted ground
        let bgU = SKUniform(name: "u_bg", texture: bgTexture)
        let puddleShader = RLShaders.puddle(bgU)
        for p in map.puddles {
            let s = SKSpriteNode(color: .white, size: p.size)
            s.position = p.at
            s.zPosition = 2
            s.shader = puddleShader
            s.setValue(SKAttributeValue(vectorFloat4: RLShaders.rect(of: s.frame, in: map.size)), forAttribute: "a_rect")
            s.setValue(SKAttributeValue(float: 1.05), forAttribute: "a_dim")
            world.addChild(s)
            if map.rain {
                let r = SKEmitterNode()
                r.particleTexture = RLTex.get("fx_ring", nearest: false)
                r.particleBirthRate = 6 + p.size.width * p.size.height / 2500
                r.particleLifetime = 0.55
                r.particlePositionRange = CGVector(dx: p.size.width * 0.8, dy: p.size.height * 0.8)
                r.particleScale = 0.015; r.particleScaleSpeed = 0.09
                r.particleAlpha = 0.5; r.particleAlphaSpeed = -0.9
                r.particleColor = SKColor(red: 0.75, green: 0.85, blue: 1, alpha: 1); r.particleColorBlendFactor = 1
                r.particleBlendMode = .add
                r.yScale = 0.55
                r.position = p.at; r.zPosition = 3
                world.addChild(r)
            }
        }

        // neon signs (crisp Russian lettering with blurred glow)
        for sgn in map.signs { world.addChild(makeSign(sgn)) }

        // steam
        for st in map.steam {
            let e = SKEmitterNode()
            e.particleTexture = RLTex.get("fx_smoke", nearest: false)
            e.particleBirthRate = 9; e.particleLifetime = 2.6; e.particleLifetimeRange = 0.8
            e.particleSpeed = 26; e.particleSpeedRange = 10; e.emissionAngle = .pi / 2; e.emissionAngleRange = 0.5
            e.xAcceleration = 4
            e.particleScale = 0.18; e.particleScaleSpeed = 0.22; e.particleScaleRange = 0.08
            e.particleAlpha = 0.22; e.particleAlphaSpeed = -0.08
            e.particleColor = SKColor(red: 0.85, green: 0.8, blue: 0.9, alpha: 1); e.particleColorBlendFactor = 1
            e.particleRotationRange = .pi; e.particleRotationSpeed = 0.4
            e.position = st; e.zPosition = 180
            world.addChild(e)
        }

        // fog drift
        let fogColors: [SKColor] = [SKColor(red: 0.5, green: 0.2, blue: 0.9, alpha: 1), SKColor(red: 0.1, green: 0.6, blue: 0.7, alpha: 1), SKColor(red: 0.8, green: 0.2, blue: 0.6, alpha: 1)]
        for (i, c) in fogColors.enumerated() where map.rain {
            let f = SKSpriteNode(texture: RLTex.get("g_soft", nearest: false))
            f.size = CGSize(width: 900, height: 520)
            f.color = c; f.colorBlendFactor = 1; f.blendMode = .add; f.alpha = 0.06
            f.position = CGPoint(x: 300 + CGFloat(i) * 360, y: 200 + CGFloat(i % 2) * 260)
            f.zPosition = 300
            f.run(.repeatForever(.sequence([.moveBy(x: 140, y: 30, duration: 14 + Double(i) * 3), .moveBy(x: -140, y: -30, duration: 14 + Double(i) * 3)])))
            world.addChild(f)
        }

        // local lit rain near neon sources
        if map.rain {
            for l in map.lights {
                let e = makeRain(width: 300, height: 260, rate: 60, color: l.color, add: true)
                e.position = CGPoint(x: l.at.x, y: l.at.y + 40)
                e.zPosition = 310
                e.particlePositionRange = CGVector(dx: 300, dy: 260)
                e.particleSpeed = 520
                e.particleLifetime = 0.35
                world.addChild(e)
            }
        }

        shockShader = RLShaders.shock(bgU)
        for (node, z) in [(fx, CGFloat(350)), (fxGround, CGFloat(9))] {
            node.zPosition = z
            node.blendMode = .add
            node.shouldEnableEffects = false
            if let bloom = CIFilter(name: "CIBloom") {
                bloom.setValue(10, forKey: kCIInputRadiusKey); bloom.setValue(1.1, forKey: kCIInputIntensityKey)
                node.filter = bloom
            }
            world.addChild(node)
        }
        fxPlain.zPosition = 340
        world.addChild(fxPlain)

        // player
        player = RLActor(id: "vex", sheet: "ch_vex")
        player.walkSpeed = 105
        player.position = CGPoint(x: game.state.px, y: game.state.py)
        if !map.walkable(player.position) { player.position = map.spots["spawn"] ?? CGPoint(x: 640, y: 300) }
        world.addChild(player)
        let eye = SKSpriteNode(texture: RLTex.get("g_soft", nearest: false))
        eye.size = CGSize(width: 26, height: 26); eye.color = SKColor(red: 0.2, green: 0.95, blue: 1, alpha: 1)
        eye.colorBlendFactor = 1; eye.blendMode = .add; eye.alpha = 0.35
        eye.position = CGPoint(x: 0, y: 40); eye.name = "eye"
        player.addChild(eye)

        // NPCs
        for d in RLCast.all where d.id != "drone" {
            let slot = d.slot(at: game.state.minute)
            guard slot.zone == map.zone, let spot = map.spots[slot.spot] else { continue }
            let a = RLActor(id: d.id, sheet: d.sprite)
            a.position = spot; a.spotName = slot.spot; a.walkSpeed = 55
            a.dir = d.id == "lin" ? 2 : 0
            world.addChild(a); npcs[d.id] = a
        }
        // pedestrians with umbrellas
        if map.zone == .street {
            for i in 0..<5 { spawnWalker(i, initial: true) }
            setupDrone()
        }
        syncWeather()
        updateCamera(1, snap: true)
    }

    private func makeSign(_ s: RLSign) -> SKNode {
        let root = SKNode()
        root.position = s.at
        root.zPosition = 60
        let halo = SKSpriteNode(texture: RLTex.get("g_soft", nearest: false))
        halo.size = CGSize(width: s.size * CGFloat(s.text.count) * 1.1 + 60, height: s.size * 3.2)
        halo.color = s.color; halo.colorBlendFactor = 1; halo.blendMode = .add; halo.alpha = 0.35
        root.addChild(halo)
        let glow = SKEffectNode()
        glow.shouldRasterize = true
        glow.filter = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: 5])
        glow.blendMode = .add
        let gl = label(s.text, size: s.size, color: s.color)
        glow.addChild(gl)
        root.addChild(glow)
        let core = label(s.text, size: s.size, color: s.color.blended(with: .white, 0.55))
        core.blendMode = .add
        root.addChild(core)
        if s.flicker {
            root.run(.repeatForever(.sequence([
                .wait(forDuration: .random(in: 2.5...6)),
                .fadeAlpha(to: 0.25, duration: 0.04), .fadeAlpha(to: 1, duration: 0.05),
                .fadeAlpha(to: 0.4, duration: 0.05), .fadeAlpha(to: 1, duration: 0.08),
            ])))
        }
        return root
    }
    private func label(_ t: String, size: CGFloat, color: SKColor) -> SKLabelNode {
        let l = SKLabelNode(fontNamed: "Inter-SemiBold")
        l.text = t; l.fontSize = size; l.fontColor = color
        l.verticalAlignmentMode = .center; l.horizontalAlignmentMode = .center
        return l
    }

    func makeRain(width: CGFloat, height: CGFloat, rate: CGFloat, color: SKColor, add: Bool) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = RLTex.get("fx_rain", nearest: false)
        e.particleBirthRate = rate
        e.particleLifetime = 0.75
        e.particlePositionRange = CGVector(dx: width, dy: 10)
        e.emissionAngle = -.pi / 2 - 0.12
        e.particleSpeed = 880; e.particleSpeedRange = 160
        e.particleAlpha = add ? 0.5 : 0.36; e.particleAlphaRange = 0.2
        e.particleScale = 1; e.particleScaleRange = 0.35
        e.particleRotation = -0.12
        e.particleColor = color; e.particleColorBlendFactor = 1
        e.particleBlendMode = add ? .add : .alpha
        return e
    }

    private func setupCameraOverlays() {
        let r = makeRain(width: 1000, height: 10, rate: 400, color: SKColor(red: 0.75, green: 0.82, blue: 1, alpha: 1), add: false)
        r.zPosition = 500
        cam.addChild(r); rain = r
        let sp = SKEmitterNode()
        sp.particleTexture = RLTex.get("fx_splash", nearest: false)
        sp.particleBirthRate = 90; sp.particleLifetime = 0.22
        sp.particleScale = 0.7; sp.particleScaleSpeed = 3
        sp.particleAlpha = 0.45; sp.particleAlphaSpeed = -2
        sp.particleColor = SKColor(red: 0.8, green: 0.88, blue: 1, alpha: 1); sp.particleColorBlendFactor = 1
        sp.particleSpeed = 0
        sp.zPosition = 490
        cam.addChild(sp); splash = sp
        grade.blendMode = .multiply; grade.zPosition = 790
        grade.color = SKColor(red: 0.9, green: 0.86, blue: 1, alpha: 1)
        cam.addChild(grade)
        vignette.zPosition = 800; vignette.alpha = 0.9
        cam.addChild(vignette)
        for (n, c) in [(chromaA, SKColor(red: 1, green: 0.1, blue: 0.6, alpha: 1)), (chromaB, SKColor(red: 0.1, green: 0.9, blue: 1, alpha: 1))] {
            n.color = c; n.colorBlendFactor = 1; n.blendMode = .add; n.alpha = 0; n.zPosition = 810
            cam.addChild(n)
        }
        flashNode.blendMode = .add; flashNode.alpha = 0; flashNode.zPosition = 820
        cam.addChild(flashNode)
        fadeNode.alpha = 0; fadeNode.zPosition = 900
        cam.addChild(fadeNode)
    }

    private func layoutOverlays() {
        let s = CGSize(width: size.width * 1.2, height: size.height * 1.2)
        baseScale = 430 / max(size.height, 1)
        vignette.size = s; grade.size = s; flashNode.size = s; fadeNode.size = s
        chromaA.size = s; chromaB.size = s
        rain?.position = CGPoint(x: 60, y: size.height / 2 + 30)
        rain?.particlePositionRange = CGVector(dx: size.width * 1.4, dy: 10)
        splash?.particlePositionRange = CGVector(dx: size.width, dy: size.height)
    }

    // MARK: Walkers

    private func spawnWalker(_ i: Int, initial: Bool) {
        guard let lane = map.walkerLanes.randomElement() else { return }
        let a = RLActor(id: "walker\(i)", sheet: "ch_walker\(i % 3)")
        a.walkSpeed = .random(in: 38...54)
        let ln: [CGPoint] = Bool.random() ? lane : Array(lane.reversed())
        if initial {
            let k = Int.random(in: 0..<(ln.count - 1))
            let t = CGFloat.random(in: 0...1)
            a.position = CGPoint(x: ln[k].x + (ln[k + 1].x - ln[k].x) * t, y: ln[k].y + (ln[k + 1].y - ln[k].y) * t)
            a.lane = Array(ln[(k + 1)...])
        } else {
            a.position = ln[0]; a.lane = Array(ln.dropFirst())
        }
        if Int.random(in: 0..<5) != 0 {
            let u = SKSpriteNode(texture: RLTex.get(["umb_magenta", "umb_teal", "umb_dark"].randomElement()!))
            u.size = CGSize(width: 34 * 1.45, height: 20 * 1.45)
            u.anchorPoint = CGPoint(x: 0.5, y: 0.3)
            u.zPosition = 1; u.lightingBitMask = 1
            a.addChild(u); a.umbrella = u
        }
        world.addChild(a); walkers.append(a)
    }

    // MARK: Drone

    private func setupDrone() {
        let tex = RLTex.get("ch_drone")
        droneFrames = (0..<2).map { i -> SKTexture in let t = SKTexture(rect: CGRect(x: CGFloat(i) * 0.5, y: 0, width: 0.5, height: 1), in: tex); t.filteringMode = .nearest; return t }
        droneBody.texture = droneFrames[0]
        droneBody.size = CGSize(width: 56 * 1.3, height: 30 * 1.3)
        droneBody.run(.repeatForever(.animate(with: droneFrames, timePerFrame: 0.05)))
        drone.removeAllChildren()
        drone.addChild(droneBody)
        let eyeGlow = SKSpriteNode(texture: RLTex.get("g_soft", nearest: false))
        eyeGlow.size = CGSize(width: 40, height: 40); eyeGlow.color = WorldColor.red; eyeGlow.colorBlendFactor = 1; eyeGlow.blendMode = .add
        eyeGlow.position = CGPoint(x: 0, y: -8)
        eyeGlow.run(.repeatForever(.sequence([.fadeAlpha(to: 0.4, duration: 0.5), .fadeAlpha(to: 1, duration: 0.5)])))
        drone.addChild(eyeGlow)
        drone.zPosition = 450
        world.addChild(drone)
        droneShadow.setScale(2); droneShadow.alpha = 0.5; droneShadow.zPosition = 5
        world.addChild(droneShadow)
        droneCone.anchorPoint = CGPoint(x: 0.5, y: 1)
        droneCone.color = SKColor(red: 1, green: 0.12, blue: 0.18, alpha: 1); droneCone.colorBlendFactor = 1
        droneCone.blendMode = .add; droneCone.alpha = 0.55; droneCone.zPosition = 440
        world.addChild(droneCone)
        droneSpot.color = droneCone.color; droneSpot.colorBlendFactor = 1; droneSpot.blendMode = .add
        droneSpot.size = CGSize(width: 120, height: 70); droneSpot.alpha = 0.75; droneSpot.zPosition = 6
        world.addChild(droneSpot)
        droneLight.categoryBitMask = 1; droneLight.lightColor = SKColor(red: 1, green: 0.1, blue: 0.15, alpha: 1)
        droneLight.ambientColor = .black; droneLight.falloff = 2.2
        world.addChild(droneLight)
        let I = RLZoneMap.img
        droneRoute = [I(660, 300), I(880, 430), I(700, 600), I(450, 540), I(560, 260)]
        droneGround = droneRoute[0]
    }

    // MARK: Update

    override func update(_ currentTime: TimeInterval) {
        guard let game, player != nil else { lastTime = currentTime; return }
        let rdt = lastTime == 0 ? 1.0 / 60 : min(1.0 / 20, currentTime - lastTime)
        lastTime = currentTime
        clock += rdt
        let stopped = clock < hitStopUntil
        let dt = CGFloat(stopped ? rdt * 0.04 : rdt)
        world.speed = stopped ? 0.04 : 1
        game.tick(rdt)

        // player movement
        if !game.paused && !castLock {
            let v = game.input.vector
            let mag = min(1, hypot(v.dx, v.dy))
            if mag > 0.12 {
                tapPath = []
                let sp = player.walkSpeed * (game.state.energy < 10 ? 0.7 : 1) * mag
                let mv = CGVector(dx: v.dx / max(mag, 0.001) * sp * dt * mag, dy: v.dy / max(mag, 0.001) * sp * dt * mag)
                player.position = map.slide(from: player.position, by: mv)
                player.face(v); player.moving = true
            } else if let target = tapPath.first {
                let d = CGVector(dx: target.x - player.position.x, dy: target.y - player.position.y)
                let len = hypot(d.dx, d.dy)
                if len < 6 { tapPath.removeFirst() } else {
                    let step = min(len, player.walkSpeed * dt)
                    let np = map.slide(from: player.position, by: CGVector(dx: d.dx / len * step, dy: d.dy / len * step))
                    if np == player.position { tapPath = [] }
                    player.position = np
                    player.face(d); player.moving = true
                }
            } else { player.moving = false }
        } else if !castLock { player.moving = false }
        player.animate(dt)
        game.state.px = Double(player.position.x); game.state.py = Double(player.position.y)
        playerLight.position = CGPoint(x: player.position.x, y: player.position.y + 30)

        doorCooldown -= dt
        for d in map.doors where d.rect.contains(player.position) && doorCooldown <= 0 {
            doorCooldown = 1.2
            if d.open { transition(to: d.to, spawn: d.spawn) }
            else {
                game.computer("Лифт в «Высоту» заблокирован для теста. Бар откроется в бета-версии.")
                player.position = map.slide(from: player.position, by: CGVector(dx: -24, dy: -18))
                tapPath = []
            }
        }

        updateNPCs(dt, game)
        updateWalkers(dt)
        if map.zone == .street { updateDrone(dt, game) }
        updateLights(dt, game)
        updateCamera(dt)
        fx.shouldEnableEffects = bloomOn && !fx.children.isEmpty
        fxGround.shouldEnableEffects = bloomOn && !fxGround.children.isEmpty

        promptTimer -= dt
        if promptTimer <= 0 { promptTimer = 0.15; updatePrompt(game) }
        miniTimer -= dt
        if miniTimer <= 0 { miniTimer = 0.2; publishMini(game) }
    }

    private func updateNPCs(_ dt: CGFloat, _ game: RLGame) {
        for (id, a) in npcs {
            guard let d = RLCast.get(id) else { continue }
            let slot = d.slot(at: game.state.minute)
            let talking = talkTarget == id
            if !talking && !a.leaving {
                if slot.zone != map.zone {
                    a.leaving = true
                    a.path = map.path(from: a.position, to: map.spots["alley_mouth"] ?? CGPoint(x: 860, y: 600))
                } else if slot.spot != a.spotName, let sp = map.spots[slot.spot] {
                    a.spotName = slot.spot
                    a.path = map.path(from: a.position, to: sp)
                }
            }
            if a.fleeTime > 0 {
                a.fleeTime -= dt
                let np = map.slide(from: a.position, by: CGVector(dx: a.fleeDir.dx * 120 * dt, dy: a.fleeDir.dy * 120 * dt))
                a.position = np; a.face(a.fleeDir); a.moving = true
                a.walkSpeed = 120
                if a.fleeTime <= 0, let sp = map.spots[a.spotName] { a.walkSpeed = 55; a.path = map.path(from: a.position, to: sp) }
            } else if talking {
                a.moving = false; a.path = []
                a.face(CGVector(dx: player.position.x - a.position.x, dy: player.position.y - a.position.y))
            } else if let t = a.path.first {
                let v = CGVector(dx: t.x - a.position.x, dy: t.y - a.position.y)
                let len = hypot(v.dx, v.dy)
                if len < 4 { a.path.removeFirst() } else {
                    let st = min(len, a.walkSpeed * dt)
                    a.position = CGPoint(x: a.position.x + v.dx / len * st, y: a.position.y + v.dy / len * st)
                    a.face(v); a.moving = true
                }
                if a.path.isEmpty && a.leaving {
                    a.run(.sequence([.fadeOut(withDuration: 0.6), .removeFromParent()]))
                    npcs[id] = nil
                }
            } else {
                a.moving = false
                let toP = CGVector(dx: player.position.x - a.position.x, dy: player.position.y - a.position.y)
                if hypot(toP.dx, toP.dy) < 110 { a.face(toP) }
                else {
                    a.idleTimer -= dt
                    if a.idleTimer < 0 {
                        a.idleTimer = .random(in: 3...7)
                        if id == "lin" { a.dir = [0, 2, 2, 3].randomElement()! }
                        else if let sp = map.spots[a.spotName] { a.path = [map.randomWalkable(near: sp, radius: 40)] }
                    }
                }
            }
            a.animate(dt)
        }
    }

    private func updateWalkers(_ dt: CGFloat) {
        for (i, w) in walkers.enumerated().reversed() {
            if w.fleeTime > 0 {
                w.fleeTime -= dt
                w.position = CGPoint(x: w.position.x + w.fleeDir.dx * 150 * dt, y: w.position.y + w.fleeDir.dy * 150 * dt)
                w.face(w.fleeDir); w.moving = true; w.walkSpeed = 150
                if w.fleeTime <= 0 { w.walkSpeed = .random(in: 38...54) }
            } else if let t = w.lane.first {
                let v = CGVector(dx: t.x - w.position.x, dy: t.y - w.position.y)
                let len = hypot(v.dx, v.dy)
                if len < 6 { w.lane.removeFirst() } else {
                    let st = min(len, w.walkSpeed * dt)
                    w.position = CGPoint(x: w.position.x + v.dx / len * st, y: w.position.y + v.dy / len * st)
                    w.face(v); w.moving = true
                }
            }
            w.animate(dt)
            let out = w.position.x < -60 || w.position.x > 1340 || w.position.y < -60 || w.position.y > 780
            if w.lane.isEmpty || out && w.fleeTime <= 0 && w.lane.count < 2 {
                w.removeFromParent(); walkers.remove(at: i)
                let idx = Int(w.id.dropFirst(6)) ?? 0
                run(.wait(forDuration: .random(in: 1...5))) { [weak self] in self?.spawnWalker(idx, initial: false) }
            }
        }
    }

    private func updateDrone(_ dt: CGFloat, _ game: RLGame) {
        guard !droneRoute.isEmpty else { return }
        let chasing = game.state.wanted >= 2
        let target = chasing ? player.position : droneRoute[droneLeg]
        let v = CGVector(dx: target.x - droneGround.x, dy: target.y - droneGround.y)
        let len = hypot(v.dx, v.dy)
        let speed: CGFloat = chasing ? 82 : 42
        if len > 3 {
            let st = min(len, speed * dt)
            droneGround = CGPoint(x: droneGround.x + v.dx / len * st, y: droneGround.y + v.dy / len * st)
        } else if !chasing { droneLeg = (droneLeg + 1) % droneRoute.count }
        let tt = CGFloat(clock)
        let wob = CGPoint(x: sin(tt * 1.3) * 26, y: cos(tt * 0.9) * 16)
        let spot = CGPoint(x: droneGround.x + wob.x, y: droneGround.y + wob.y)
        let hover = CGPoint(x: droneGround.x, y: droneGround.y + 120 + sin(tt * 2.2) * 5)
        drone.position = hover
        droneBody.xScale = v.dx < 0 ? -1 : 1
        droneShadow.position = CGPoint(x: droneGround.x, y: droneGround.y - 4)
        droneSpot.position = spot
        droneLight.position = spot
        let cv = CGVector(dx: spot.x - hover.x, dy: spot.y - (hover.y - 12))
        let dist = hypot(cv.dx, cv.dy)
        droneCone.position = CGPoint(x: hover.x, y: hover.y - 12)
        droneCone.zRotation = atan2(cv.dy, cv.dx) + .pi / 2
        droneCone.yScale = dist / 256
        droneCone.xScale = chasing ? 1.15 : 0.9
        let pulse: CGFloat = chasing ? 0.75 + 0.25 * sin(tt * 9) : 0.55
        droneCone.alpha = pulse; droneSpot.alpha = pulse + 0.15
        droneScanCooldown -= dt
        let lit = hypot(spot.x - player.position.x, spot.y - player.position.y) < 48
        if lit && droneScanCooldown <= 0 && !game.paused {
            droneScanCooldown = 25
            game.droneScanned()
            shake(0.12)
        }
        if lit && chasing && !game.paused { game.state.wanted = min(5, game.state.wanted + Double(dt) * 0.08) }
    }

    var droneSeesPlayer: Bool {
        guard map.zone == .street else { return false }
        return hypot(droneGround.x - player.position.x, droneGround.y - player.position.y) < 280
    }

    private func updateLights(_ dt: CGFloat, _ game: RLGame) {
        let dark = CGFloat(RLClock.darkness(game.state.minute))
        let a = 0.66 + (1 - dark) * 0.3 - darkPulse * 0.35
        darkPulse = max(0, darkPulse - dt * 2.5)
        let amb = map.ambient
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, al: CGFloat = 0
        amb.getRed(&r, green: &g, blue: &b, alpha: &al)
        ambientLight.ambientColor = SKColor(red: r * a / 0.66, green: g * a / 0.66, blue: b * a / 0.66, alpha: 1)
        for (i, l) in mapLights.enumerated() {
            var k: CGFloat = 0.55 + dark * 0.45
            if l.flicker { k *= (sin(clock * 13 + Double(i)) > 0.96 ? 0.3 : 1) * (0.9 + 0.1 * CGFloat(sin(clock * 3 + Double(i) * 2))) }
            l.node.lightColor = l.color.scaled(k)
        }
        grade.color = SKColor(red: 0.86 + (1 - dark) * 0.12, green: 0.84 + (1 - dark) * 0.12, blue: 1, alpha: 1)
    }

    func updateCamera(_ dt: CGFloat, snap: Bool = false) {
        guard player != nil else { return }
        var target = player.position
        var z: CGFloat = 1
        if let t = talkTarget, let a = npcs[t] {
            target = CGPoint(x: (player.position.x + a.position.x) / 2, y: (player.position.y + a.position.y) / 2 - 70)
            z = 0.78
        }
        zoom += (z - zoom) * min(1, dt * 4)
        let scale = baseScale * zoom
        cam.setScale(scale)
        let hw = size.width * scale / 2, hh = size.height * scale / 2
        if map.size.width > hw * 2 { target.x = min(max(target.x, hw), map.size.width - hw) } else { target.x = map.size.width / 2 }
        if map.size.height > hh * 2 { target.y = min(max(target.y, hh - 40), map.size.height - hh + 20) } else { target.y = map.size.height / 2 }
        var p = snap ? target : CGPoint(x: cam.position.x + (target.x - cam.position.x) * min(1, dt * 5), y: cam.position.y + (target.y - cam.position.y) * min(1, dt * 5))
        trauma = max(0, trauma - dt * 1.6)
        if trauma > 0 {
            let s = trauma * trauma * 16
            p.x += CGFloat.random(in: -s...s); p.y += CGFloat.random(in: -s...s)
            cam.zRotation = CGFloat.random(in: -1...1) * trauma * trauma * 0.02
        } else { cam.zRotation = 0 }
        cam.position = p
    }

    func shake(_ amount: CGFloat) { trauma = min(1, trauma + amount) }
    func hitStop(_ seconds: TimeInterval) { hitStopUntil = clock + seconds }

    private func updatePrompt(_ game: RLGame) {
        var best: RLPrompt?
        var bestD: CGFloat = .greatestFiniteMagnitude
        for (id, a) in npcs {
            let d = hypot(a.position.x - player.position.x, a.position.y - player.position.y)
            if d < 75 && d < bestD, let def = RLCast.get(id) {
                bestD = d; best = RLPrompt(kind: .npc(id), label: def.name, symbol: "bubble.left.and.bubble.right.fill")
            }
        }
        if best == nil && map.zone == .street && hypot(droneGround.x - player.position.x, droneGround.y - player.position.y) < 70 {
            best = RLPrompt(kind: .npc("drone"), label: "Сенсор-9", symbol: "dot.radiowaves.left.and.right")
        }
        if best == nil {
            for it in map.interacts {
                let d = hypot(it.at.x - player.position.x, it.at.y - player.position.y)
                if d < it.radius && d < bestD { bestD = d; best = RLPrompt(kind: .interact(it.kind), label: it.label, symbol: RLScene.symbol(it.kind)) }
            }
        }
        if best != game.prompt { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { game.prompt = best } }
    }

    static func symbol(_ k: RLInteractKind) -> String {
        switch k {
        case .noodle: return "takeoutbag.and.cup.and.straw.fill"
        case .sleep: return "bed.double.fill"
        case .cook: return "flame.fill"
        case .terminal: return "desktopcomputer"
        case .couch: return "sofa.fill"
        case .shift: return "wineglass.fill"
        case .jukebox: return "music.note"
        default: return "hand.point.up.left.fill"
        }
    }

    private func publishMini(_ game: RLGame) {
        var m = RLMini()
        let W = map.size.width, H = map.size.height
        m.player = CGPoint(x: player.position.x / W, y: 1 - player.position.y / H)
        m.dir = [CGFloat.pi, 0, -.pi / 2, .pi / 2][player.dir]
        for (id, a) in npcs { m.npcs[id] = CGPoint(x: a.position.x / W, y: 1 - a.position.y / H) }
        if map.zone == .street { m.drone = CGPoint(x: droneGround.x / W, y: 1 - droneGround.y / H) }
        m.zone = map.zone
        if m != game.mini { game.mini = m }
    }

    // MARK: Touch: tap to move

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let game, !game.paused, !castLock, let t = touches.first else { return }
        let p = t.location(in: self)
        if let hit = npcs.first(where: { hypot($0.value.position.x - p.x, $0.value.position.y + 25 - p.y) < 30 }),
           hypot(hit.value.position.x - player.position.x, hit.value.position.y - player.position.y) < 90 {
            game.openDialog(hit.key); return
        }
        var goal = p
        if !map.walkable(goal) { goal = map.randomWalkable(near: p, radius: 30) }
        tapPath = map.path(from: player.position, to: goal)
        let ring = SKSpriteNode(texture: RLTex.get("fx_ring", nearest: false))
        ring.size = CGSize(width: 30, height: 18); ring.position = goal; ring.zPosition = 8
        ring.color = SKColor(red: 0.66, green: 0.77, blue: 0.63, alpha: 1); ring.colorBlendFactor = 1; ring.blendMode = .add
        world.addChild(ring)
        ring.run(.sequence([.group([.scale(to: 1.8, duration: 0.4), .fadeOut(withDuration: 0.4)]), .removeFromParent()]))
    }

    // MARK: Game hooks

    func transition(to zone: RLZone, spawn: CGPoint) {
        guard let game else { return }
        castLock = true
        RLAudio.shared.sfx("door", volume: 0.5)
        fadeNode.run(.sequence([.fadeIn(withDuration: 0.25), .run { [weak self] in
            game.state.zone = zone; game.state.px = Double(spawn.x); game.state.py = Double(spawn.y)
            self?.reload(); game.refreshHud()
        }, .fadeOut(withDuration: 0.35), .run { [weak self] in self?.castLock = false }]))
    }

    func beginTalk(_ id: String) { talkTarget = id == "drone" ? nil : id; tapPath = [] }
    func endTalk() { talkTarget = nil }
    func npcVisible(_ id: String) -> Bool { npcs[id] != nil }
    func flash() { flashNode.color = .white; flashNode.run(.sequence([.fadeAlpha(to: 0.5, duration: 0.15), .fadeAlpha(to: 0, duration: 0.5)])) }

    func say(_ id: String, _ text: String, ifNear: Bool = false) {
        guard let a = npcs[id] else { return }
        if ifNear && hypot(a.position.x - player.position.x, a.position.y - player.position.y) > 320 { return }
        let col = SKColor(hex: RLCast.get(id)?.accent ?? "A8C5A0")
        a.say(text, color: col, duration: 2.6 + Double(text.count) / 25)
    }
    func npcSay(nearest: Bool, _ text: String) {
        if let id = npcNearPlayer() { say(id, text) }
    }
    func nearbyPairs() -> [(String, String)] {
        let ids = Array(npcs.keys)
        var out: [(String, String)] = []
        for i in 0..<ids.count { for j in (i + 1)..<ids.count {
            let a = npcs[ids[i]]!, b = npcs[ids[j]]!
            if hypot(a.position.x - b.position.x, a.position.y - b.position.y) < 260 &&
                hypot(a.position.x - player.position.x, a.position.y - player.position.y) < 500 { out.append((ids[i], ids[j])) }
        } }
        return out
    }
    func npcNearPlayer() -> String? {
        npcs.min { hypot($0.value.position.x - player.position.x, $0.value.position.y - player.position.y) < hypot($1.value.position.x - player.position.x, $1.value.position.y - player.position.y) }
            .flatMap { hypot($0.value.position.x - player.position.x, $0.value.position.y - player.position.y) < 320 ? $0.key : nil }
    }
    func syncWeather() {
        guard let game else { return }
        let k = CGFloat(map.rain ? max(0.15, game.state.weather.intensity) : 0)
        rain?.particleBirthRate = 520 * k
        splash?.particleBirthRate = 160 * k
        rain?.isHidden = !map.rain; splash?.isHidden = !map.rain
    }
    func syncAudio() {
        guard let game else { return }
        RLAudio.shared.ambience(zone: map.zone, rain: game.state.weather.intensity)
    }
}

enum WorldColor {
    static let red = SKColor(red: 1, green: 0.15, blue: 0.2, alpha: 1)
}

extension SKColor {
    convenience init(hex: String) {
        var v: UInt64 = 0; Scanner(string: hex).scanHexInt64(&v)
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
    func scaled(_ k: CGFloat) -> SKColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return SKColor(red: min(1, r * k), green: min(1, g * k), blue: min(1, b * k), alpha: a)
    }
    func blended(with c: SKColor, _ t: CGFloat) -> SKColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a); c.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return SKColor(red: r + (r2 - r) * t, green: g + (g2 - g) * t, blue: b + (b2 - b) * t, alpha: 1)
    }
}
