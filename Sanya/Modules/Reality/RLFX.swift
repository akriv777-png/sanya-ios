import SpriteKit
import SwiftUI
import simd

// MARK: - Spells

enum RLSpell: String, CaseIterable, Identifiable {
    case glyph, hex, shadow, sigil
    var id: String { rawValue }
    var title: String {
        switch self { case .glyph: return "Неоновый глиф"; case .hex: return "Багровая метка"; case .shadow: return "Теневой шаг"; case .sigil: return "Сигил света" }
    }
    var blurb: String {
        switch self {
        case .glyph: return "Руна разрывает воздух фиолетовой молнией и отбрасывает всех вокруг"
        case .hex: return "Кровавая метка вселяет страх — цель бежит прочь"
        case .shadow: return "Рывок сквозь тень, оставляя дымные силуэты"
        case .sigil: return "Божественный сигил света: лечит настрой, но слепит сенсоры"
        }
    }
    var cost: Double { switch self { case .glyph: return 32; case .hex: return 24; case .shadow: return 16; case .sigil: return 40 } }
    var heat: Double { switch self { case .glyph: return 1.1; case .hex: return 0.8; case .shadow: return 0.35; case .sigil: return 1.4 } }
    var cooldown: TimeInterval { switch self { case .glyph: return 2.6; case .hex: return 3.5; case .shadow: return 1.1; case .sigil: return 9 } }
    var icon: String { "spell_" + rawValue }
    var color: SKColor {
        switch self {
        case .glyph: return SKColor(red: 0.69, green: 0.36, blue: 1, alpha: 1)
        case .hex: return SKColor(red: 1, green: 0.16, blue: 0.24, alpha: 1)
        case .shadow: return SKColor(red: 0.23, green: 0.89, blue: 1, alpha: 1)
        case .sigil: return SKColor(red: 0.55, green: 0.97, blue: 1, alpha: 1)
        }
    }
    var ui: Color { Color(uiColor: color) }
}

// MARK: - Shaders

enum RLShaders {
    static func rect(of f: CGRect, in s: CGSize) -> vector_float4 {
        vector_float4(Float(f.minX / s.width), Float(f.minY / s.height), Float(f.width / s.width), Float(f.height / s.height))
    }
    static func col(_ c: SKColor) -> vector_float4 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return vector_float4(Float(r), Float(g), Float(b), 1)
    }

    /// Rune circle: angular draw-in sweep with a hot leading edge and a travelling pulse.
    static let rune: SKShader = {
        let s = SKShader(source: """
        void main() {
            vec2 p = v_tex_coord - 0.5;
            float r = length(p) * 2.0;
            float ang = atan(p.y, p.x) / 6.2831853 + 0.5;
            float lum = texture2D(u_texture, v_tex_coord).r;
            float sweep = 1.0 - smoothstep(a_prog - 0.012, a_prog + 0.012, ang);
            float edge = exp(-abs(ang - a_prog) * 60.0) * step(0.01, a_prog) * (1.0 - step(0.995, a_prog));
            float pulse = 0.78 + 0.22 * sin(u_time * 7.0 - r * 16.0);
            float hot = pow(lum, 2.6);
            vec3 col = a_col.rgb * lum * sweep * pulse * a_int;
            col += vec3(1.0) * hot * sweep * 0.45 * a_int;
            col += mix(a_col.rgb, vec3(1.0), 0.6) * lum * edge * 2.5;
            float a = v_color_mix.a;
            col *= a;
            gl_FragColor = vec4(col, max(max(col.r, col.g), col.b));
        }
        """)
        s.attributes = [SKAttribute(name: "a_prog", type: .float), SKAttribute(name: "a_int", type: .float), SKAttribute(name: "a_col", type: .vectorFloat4)]
        return s
    }()

    /// Rippling puddle that re-samples the painted ground.
    static func puddle(_ bg: SKUniform) -> SKShader {
        let s = SKShader(source: """
        void main() {
            vec2 p = v_tex_coord - 0.5;
            float m = 1.0 - smoothstep(0.18, 0.5, length(p));
            vec2 uv = a_rect.xy + v_tex_coord * a_rect.zw;
            float t = u_time;
            vec2 off = vec2(sin(uv.y * 520.0 + t * 2.7) + 0.5 * sin(uv.y * 1300.0 - t * 4.1),
                            cos(uv.x * 610.0 + t * 2.1)) * 0.0011;
            vec3 c = texture2D(u_bg, uv + off).rgb;
            float sh = 0.86 + 0.3 * sin(t * 1.7 + uv.x * 220.0 + uv.y * 140.0);
            vec3 col = c * a_dim * sh * 1.18;
            float a = m * 0.8 * v_color_mix.a;
            gl_FragColor = vec4(col * a, a);
        }
        """)
        s.uniforms = [bg]
        s.attributes = [SKAttribute(name: "a_rect", type: .vectorFloat4), SKAttribute(name: "a_dim", type: .float)]
        return s
    }

    /// Shockwave: refracts the painted ground with chromatic split along an expanding ring.
    static func shock(_ bg: SKUniform) -> SKShader {
        let s = SKShader(source: """
        void main() {
            vec2 p = v_tex_coord - 0.5;
            float d = length(p) * 2.0;
            float band = 1.0 - smoothstep(0.0, 0.13, abs(d - a_rad));
            vec2 dir = p / max(length(p), 0.0001);
            vec2 uv = a_rect.xy + v_tex_coord * a_rect.zw;
            vec2 off = dir * band * a_str * 0.07 * a_rect.zw;
            float cr = texture2D(u_bg, uv - off * 1.5).r;
            float cg = texture2D(u_bg, uv - off).g;
            float cb = texture2D(u_bg, uv - off * 0.55).b;
            vec3 col = vec3(cr, cg, cb) * 0.92 + a_col.rgb * band * band * 0.55 * a_str;
            float alpha = band * v_color_mix.a * (1.0 - smoothstep(0.85, 1.0, d));
            gl_FragColor = vec4(col * alpha, alpha);
        }
        """)
        s.uniforms = [bg]
        s.attributes = [SKAttribute(name: "a_rect", type: .vectorFloat4), SKAttribute(name: "a_rad", type: .float),
                        SKAttribute(name: "a_str", type: .float), SKAttribute(name: "a_col", type: .vectorFloat4)]
        return s
    }
}

// MARK: - VFX toolkit

extension RLScene {
    static let perspective: CGFloat = 0.6

    func glowSprite(_ color: SKColor, size: CGFloat, alpha: CGFloat = 1, tex: String = "g_soft") -> SKSpriteNode {
        let s = SKSpriteNode(texture: RLTex.get(tex, nearest: false))
        s.size = CGSize(width: size, height: size)
        s.color = color; s.colorBlendFactor = 1; s.blendMode = .add; s.alpha = alpha
        return s
    }

    /// Dynamic light from the pool, animated rise → hold → fall.
    func spellLight(_ color: SKColor, at p: CGPoint, peak: CGFloat, rise: TimeInterval, hold: TimeInterval, fall: TimeInterval, falloff: CGFloat = 1.0, follow: SKNode? = nil) {
        guard !spellLights.isEmpty else { return }
        let l = spellLights.first(where: { !$0.isEnabled }) ?? spellLights[Int.random(in: 0..<spellLights.count)]
        l.removeAllActions()
        l.isEnabled = true; l.position = p; l.falloff = falloff; l.lightColor = .black
        let total = rise + hold + fall
        l.run(.sequence([
            .customAction(withDuration: total) { node, t in
                guard let n = node as? SKLightNode else { return }
                let tt = TimeInterval(t)
                var k: CGFloat
                if tt < rise { k = CGFloat(tt / max(rise, 0.001)); k = k * k }
                else if tt < rise + hold { k = 1 + CGFloat(sin(tt * 30)) * 0.06 }
                else { let f = CGFloat((tt - rise - hold) / max(fall, 0.001)); k = (1 - f) * (1 - f) }
                n.lightColor = color.scaled(peak * k)
                if let follow { n.position = CGPoint(x: follow.position.x, y: follow.position.y + 20) }
            },
            .run { l.isEnabled = false },
        ]))
    }

    /// Ground rune circle in 3/4 perspective. Returns (container, spinner).
    @discardableResult
    func runeCircle(_ color: SKColor, at p: CGPoint, radius: CGFloat, draw: TimeInterval, life: TimeInterval, spin: CGFloat = 0.8, intensity: Float = 1.2) -> SKNode {
        let root = SKNode()
        root.position = p
        root.yScale = RLScene.perspective
        let s = SKSpriteNode(texture: RLTex.get("fx_rune", nearest: false))
        s.size = CGSize(width: radius * 2, height: radius * 2)
        s.shader = RLShaders.rune
        s.blendMode = .add
        s.setValue(SKAttributeValue(float: 0), forAttribute: "a_prog")
        s.setValue(SKAttributeValue(float: intensity), forAttribute: "a_int")
        s.setValue(SKAttributeValue(vectorFloat4: RLShaders.col(color)), forAttribute: "a_col")
        root.addChild(s)
        let halo = glowSprite(color, size: radius * 2.6, alpha: 0)
        root.addChild(halo)
        halo.run(.sequence([.fadeAlpha(to: 0.45, duration: draw), .wait(forDuration: max(0, life - draw - 0.6)), .fadeOut(withDuration: 0.6)]))
        s.run(.customAction(withDuration: draw) { n, t in
            let k = Float(t / CGFloat(max(draw, 0.001)))
            (n as? SKSpriteNode)?.setValue(SKAttributeValue(float: 1 - (1 - k) * (1 - k)), forAttribute: "a_prog")
        })
        s.run(.repeatForever(.rotate(byAngle: spin, duration: 1)))
        s.setScale(0.7)
        s.run(.scale(to: 1, duration: draw * 0.9))
        root.run(.sequence([.wait(forDuration: max(0, life - 0.6)), .group([.fadeOut(withDuration: 0.6), .scaleX(to: 1.12, y: RLScene.perspective * 1.12, duration: 0.6)]), .removeFromParent()]))
        fxGround.addChild(root)
        return root
    }

    /// Jagged lightning that re-rolls its shape every few frames.
    func lightning(from a: CGPoint, to b: CGPoint, color: SKColor, duration: TimeInterval, width: CGFloat = 2, jag: CGFloat = 22, layer: SKNode? = nil) {
        let glow = SKShapeNode()
        glow.strokeColor = color; glow.lineWidth = width * 2.6; glow.glowWidth = width * 2.2; glow.blendMode = .add; glow.alpha = 0.7
        glow.lineCap = .round; glow.lineJoin = .round
        let core = SKShapeNode()
        core.strokeColor = color.blended(with: .white, 0.75); core.lineWidth = width; core.blendMode = .add
        core.lineCap = .round; core.lineJoin = .round
        let root = SKNode()
        root.addChild(glow); root.addChild(core)
        (layer ?? fx).addChild(root)
        func roll() {
            let path = RLScene.boltPath(a, b, jag: jag)
            glow.path = path; core.path = path
        }
        roll()
        root.run(.sequence([
            .repeat(.sequence([.wait(forDuration: 0.04), .run(roll), .fadeAlpha(to: .random(in: 0.55...1), duration: 0)]), count: max(1, Int(duration / 0.04))),
            .fadeOut(withDuration: 0.08), .removeFromParent(),
        ]))
    }

    static func boltPath(_ a: CGPoint, _ b: CGPoint, jag: CGFloat) -> CGPath {
        var pts = [a, b]
        var amp = jag
        for _ in 0..<4 {
            var np: [CGPoint] = []
            for i in 0..<(pts.count - 1) {
                let p = pts[i], q = pts[i + 1]
                let m = CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)
                let dx = q.x - p.x, dy = q.y - p.y, len = max(1, hypot(dx, dy))
                let off = CGFloat.random(in: -amp...amp)
                np.append(p); np.append(CGPoint(x: m.x - dy / len * off, y: m.y + dx / len * off))
            }
            np.append(pts.last!)
            pts = np; amp *= 0.5
        }
        let path = CGMutablePath()
        path.addLines(between: pts)
        if Bool.random() && pts.count > 6 {   // branch
            let k = Int.random(in: 3..<(pts.count - 3))
            let s = pts[k]
            let e = CGPoint(x: s.x + .random(in: -40...40), y: s.y + .random(in: -40...40))
            path.move(to: s); path.addLine(to: CGPoint(x: (s.x + e.x) / 2 + .random(in: -8...8), y: (s.y + e.y) / 2 + .random(in: -8...8))); path.addLine(to: e)
        }
        return path
    }

    func burst(_ color: SKColor, at p: CGPoint, count: Int, speed: CGFloat, life: CGFloat, tex: String = "fx_ember", scale: CGFloat = 0.9, flat: Bool = true, rise: CGFloat = 0, layer: SKNode? = nil, alphaBlend: Bool = false) {
        let e = SKEmitterNode()
        e.particleTexture = RLTex.get(tex, nearest: false)
        e.numParticlesToEmit = count
        e.particleBirthRate = CGFloat(count) * 40
        e.particleLifetime = life; e.particleLifetimeRange = life * 0.5
        e.particleSpeed = speed; e.particleSpeedRange = speed * 0.6
        e.emissionAngleRange = .pi * 2
        e.yAcceleration = rise
        e.particleScale = scale; e.particleScaleRange = scale * 0.5; e.particleScaleSpeed = -scale / life * 0.8
        e.particleAlpha = 1; e.particleAlphaSpeed = -1 / life
        e.particleColorBlendFactor = 1
        e.particleColorSequence = SKKeyframeSequence(keyframeValues: [SKColor.white, color, color.scaled(0.4)], times: [0, 0.18, 1])
        e.particleBlendMode = alphaBlend ? .alpha : .add
        e.particleRotationRange = .pi
        if flat { e.yScale = RLScene.perspective }
        e.position = p
        e.targetNode = layer ?? fx
        (layer ?? fx).addChild(e)
        e.run(.sequence([.wait(forDuration: TimeInterval(life * 1.6) + 0.2), .removeFromParent()]))
    }

    func smoke(_ color: SKColor, at p: CGPoint, count: Int, speed: CGFloat, life: CGFloat, scale: CGFloat = 0.5, rise: CGFloat = 20) {
        let e = SKEmitterNode()
        e.particleTexture = RLTex.get("fx_smoke", nearest: false)
        e.numParticlesToEmit = count
        e.particleBirthRate = CGFloat(count) * 12
        e.particleLifetime = life; e.particleLifetimeRange = life * 0.4
        e.particleSpeed = speed; e.particleSpeedRange = speed * 0.5
        e.emissionAngleRange = .pi * 2
        e.yAcceleration = rise
        e.particleScale = scale * 0.6; e.particleScaleSpeed = scale / life
        e.particleAlpha = 0.6; e.particleAlphaSpeed = -0.6 / life
        e.particleColor = color; e.particleColorBlendFactor = 1
        e.particleRotationRange = .pi * 2; e.particleRotationSpeed = 1.2
        e.particleBlendMode = .alpha
        e.position = p
        e.zPosition = 330
        e.targetNode = fxPlain
        fxPlain.addChild(e)
        e.run(.sequence([.wait(forDuration: TimeInterval(life * 1.5) + 0.2), .removeFromParent()]))
    }

    /// Living tendrils of smoke/shadow curling out of a point.
    func tendrils(_ color: SKColor, at p: CGPoint, count: Int, radius: CGFloat, life: TimeInterval, inward: Bool = false) {
        for i in 0..<count {
            let n = SKShapeNode()
            n.strokeColor = color; n.lineWidth = 3.2; n.glowWidth = 1.5; n.lineCap = .round; n.alpha = 0
            n.zPosition = 335
            let base = CGFloat(i) / CGFloat(count) * .pi * 2 + .random(in: -0.3...0.3)
            let len = radius * .random(in: 0.7...1.2)
            let phase = CGFloat.random(in: 0...6)
            fxPlain.addChild(n)
            n.run(.sequence([
                .group([
                    .fadeAlpha(to: 0.85, duration: 0.2),
                    .customAction(withDuration: life) { node, t in
                        guard let s = node as? SKShapeNode else { return }
                        let k = t / CGFloat(life)
                        let grow = inward ? (1 - k) : min(1, k * 2.2)
                        let path = CGMutablePath()
                        let start = CGPoint(x: p.x + cos(base) * radius * 0.3, y: p.y + sin(base) * radius * 0.3 * RLScene.perspective)
                        path.move(to: start)
                        let steps = 10
                        for j in 1...steps {
                            let f = CGFloat(j) / CGFloat(steps) * grow
                            let ang = base + sin(phase + t * 4 + f * 5) * 0.45 * f
                            let rr = radius * 0.3 + len * f
                            path.addLine(to: CGPoint(x: p.x + cos(ang) * rr, y: p.y + sin(ang) * rr * RLScene.perspective + f * f * 26))
                        }
                        s.path = path
                        s.lineWidth = 3.4 * (1 - k * 0.6)
                    },
                ]),
                .fadeOut(withDuration: 0.25), .removeFromParent(),
            ]))
        }
    }

    func shockwave(_ color: SKColor, at p: CGPoint, radius: CGFloat, duration: TimeInterval, strength: Float) {
        if let sh = shockShader {
            let s = SKSpriteNode(color: .white, size: CGSize(width: radius * 2, height: radius * 2 * RLScene.perspective))
            s.position = p; s.zPosition = 8
            s.shader = sh
            s.setValue(SKAttributeValue(vectorFloat4: RLShaders.rect(of: s.frame, in: map.size)), forAttribute: "a_rect")
            s.setValue(SKAttributeValue(vectorFloat4: RLShaders.col(color)), forAttribute: "a_col")
            s.setValue(SKAttributeValue(float: 0), forAttribute: "a_rad")
            s.setValue(SKAttributeValue(float: strength), forAttribute: "a_str")
            world.addChild(s)
            s.run(.sequence([.customAction(withDuration: duration) { n, t in
                let k = Float(t / CGFloat(duration))
                let e = 1 - (1 - k) * (1 - k) * (1 - k)
                (n as? SKSpriteNode)?.setValue(SKAttributeValue(float: e * 0.98), forAttribute: "a_rad")
                (n as? SKSpriteNode)?.setValue(SKAttributeValue(float: strength * (1 - k)), forAttribute: "a_str")
            }, .removeFromParent()]))
        }
        let ring = SKSpriteNode(texture: RLTex.get("fx_ring", nearest: false))
        ring.color = color; ring.colorBlendFactor = 1; ring.blendMode = .add
        ring.size = CGSize(width: radius * 2, height: radius * 2 * RLScene.perspective)
        ring.position = p; ring.setScale(0.05); ring.alpha = 1
        fxGround.addChild(ring)
        ring.run(.sequence([.group([.scale(to: 1, duration: duration).withTiming(.easeOut), .fadeOut(withDuration: duration)]), .removeFromParent()]))
    }

    func screenFlash(_ color: SKColor, _ a: CGFloat, _ d: TimeInterval) {
        flashNode.removeAllActions()
        flashNode.color = color; flashNode.colorBlendFactor = 1
        flashNode.alpha = a
        flashNode.run(.fadeOut(withDuration: d))
    }

    func chroma(_ k: CGFloat) {
        for (n, dx) in [(chromaA, 10 * k), (chromaB, -10 * k)] {
            n.removeAllActions()
            n.position = CGPoint(x: dx, y: 0); n.alpha = 0.55 * k
            n.run(.group([.fadeOut(withDuration: 0.35), .move(to: .zero, duration: 0.35)]))
        }
    }

    func inwardSparks(_ color: SKColor, at p: CGPoint, count: Int, radius: CGFloat, duration: TimeInterval) {
        for i in 0..<count {
            let s = glowSprite(color.blended(with: .white, 0.4), size: .random(in: 6...12), tex: "fx_ember")
            let a = CGFloat(i) / CGFloat(count) * .pi * 2 * 3 + .random(in: 0...1)
            let r = radius * .random(in: 0.8...1.3)
            s.position = CGPoint(x: p.x + cos(a) * r, y: p.y + sin(a) * r * RLScene.perspective + 10)
            s.alpha = 0
            let delay = duration * Double(i) / Double(count) * 0.6
            fx.addChild(s)
            let path = CGMutablePath()
            path.move(to: s.position)
            path.addQuadCurve(to: CGPoint(x: p.x, y: p.y + 30), control: CGPoint(x: p.x + cos(a + 1.2) * r * 0.6, y: p.y + sin(a + 1.2) * r * 0.6 * RLScene.perspective + 40))
            s.run(.sequence([.wait(forDuration: delay), .fadeIn(withDuration: 0.05),
                             .group([.follow(path, asOffset: false, orientToPath: false, duration: duration - delay).withTiming(.easeIn), .scale(to: 0.3, duration: duration - delay)]),
                             .removeFromParent()]))
        }
    }

    func floatGlyphs(_ color: SKColor, at p: CGPoint, count: Int, radius: CGFloat, life: TimeInterval) {
        for i in 0..<count {
            let g = SKSpriteNode(texture: RLTex.glyph(i % 5))
            g.size = CGSize(width: 18, height: 18)
            g.color = color.blended(with: .white, 0.3); g.colorBlendFactor = 1; g.blendMode = .add; g.alpha = 0
            let a = CGFloat(i) / CGFloat(count) * .pi * 2
            g.position = CGPoint(x: p.x + cos(a) * radius, y: p.y + sin(a) * radius * RLScene.perspective + 8)
            let halo = glowSprite(color, size: 34, alpha: 0.5)
            g.addChild(halo)
            fx.addChild(g)
            let dx = CGFloat.random(in: -6...6), dy = CGFloat.random(in: 50...90)
            let rise = SKAction.moveBy(x: dx, y: dy, duration: life).withTiming(.easeOut)
            let fade = SKAction.sequence([.wait(forDuration: life * 0.55), .fadeOut(withDuration: life * 0.45)])
            let body = SKAction.group([.fadeAlpha(to: 1, duration: 0.2), rise, fade])
            g.run(.sequence([.wait(forDuration: 0.04 * Double(i)), body, .removeFromParent()]))
        }
    }

    func afterimage(_ a: RLActor, color: SKColor, alpha: CGFloat, add: Bool) {
        let s = SKSpriteNode(texture: a.body.texture)
        s.size = a.body.size; s.anchorPoint = a.body.anchorPoint
        s.position = a.position
        s.color = color; s.colorBlendFactor = 1; s.alpha = alpha
        s.blendMode = add ? .add : .alpha
        s.zPosition = a.zPosition - 0.2
        world.addChild(s)
        s.run(.sequence([.group([.fadeOut(withDuration: 0.42), .scaleX(to: 1.15, duration: 0.42), .moveBy(x: 0, y: 6, duration: 0.42)]), .removeFromParent()]))
    }

    /// Pushes and scares everyone around; returns ids of story NPCs who saw it.
    @discardableResult
    func affect(at p: CGPoint, radius: CGFloat, push: CGFloat, flee: CGFloat) -> [String] {
        var seen: [String] = []
        for (id, a) in npcs {
            let d = hypot(a.position.x - p.x, a.position.y - p.y)
            if d < 420 { seen.append(id) }
            if d < radius {
                let dir = CGVector(dx: (a.position.x - p.x) / max(d, 1), dy: (a.position.y - p.y) / max(d, 1))
                if push > 0 {
                    let to = map.slide(from: a.position, by: CGVector(dx: dir.dx * push * (1 - d / radius), dy: dir.dy * push * (1 - d / radius)))
                    a.run(.move(to: to, duration: 0.25).withTiming(.easeOut))
                    a.body.run(.sequence([.scaleX(to: 1.2, y: 0.8, duration: 0.06), .scaleX(to: 1, y: 1, duration: 0.25)]))
                }
                if flee > 0 && id != "lin" { a.fleeTime = flee; a.fleeDir = dir }
            }
        }
        for w in walkers {
            let d = hypot(w.position.x - p.x, w.position.y - p.y)
            if d < radius * 1.6 {
                let dir = CGVector(dx: (w.position.x - p.x) / max(d, 1), dy: (w.position.y - p.y) / max(d, 1))
                w.fleeTime = max(w.fleeTime, flee > 0 ? flee : 2.5); w.fleeDir = dir
                if push > 0 && d < radius { w.run(.move(by: CGVector(dx: dir.dx * push * 0.6, dy: dir.dy * push * 0.6), duration: 0.22).withTiming(.easeOut)) }
            }
        }
        return seen
    }

    // MARK: Casting

    func cast(_ sp: RLSpell) {
        guard let game, !castLock, game.canCast(sp), player != nil else {
            if let game, game.state.mana < sp.cost { Haptics.warning(); RLAudio.shared.sfx("error", volume: 0.35); game.float("Мало маны", Color(uiColor: sp.color)) }
            return
        }
        if let cd = cooldowns[sp], clock < cd { return }
        cooldowns[sp] = clock + sp.cooldown
        game.spend(sp)
        tapPath = []
        switch sp {
        case .glyph: castGlyph()
        case .shadow: castShadow()
        case .hex: castHex()
        case .sigil: castSigil()
        }
    }

    func cooldownLeft(_ sp: RLSpell) -> Double { max(0, (cooldowns[sp] ?? 0) - clock) }

    private func resolve(_ sp: RLSpell, _ seen: [String]) {
        guard let game else { return }
        let droneSaw = droneSeesPlayer
        game.magicResolved(sp, witnesses: seen, droneSaw: droneSaw)
    }

    private func beginCast(_ dur: TimeInterval) {
        castLock = true
        player.casting = true; player.moving = false
        player.body.run(.sequence([.scaleX(to: 0.92, y: 1.08, duration: dur * 0.6).withTiming(.easeOut), .scaleX(to: 1, y: 1, duration: 0.1)]))
    }
    private func endCast(after: TimeInterval) {
        run(.wait(forDuration: after)) { [weak self] in self?.castLock = false; self?.player.casting = false }
    }

    func castGlyph() {
        let c = RLSpell.glyph.color
        let p = player.position
        let charge: TimeInterval = 0.58
        beginCast(charge)
        Haptics.soft()
        RLAudio.shared.sfx("charge", volume: 0.7)
        runeCircle(c, at: p, radius: 92, draw: charge * 0.9, life: 2.2, spin: 0.9)
        runeCircle(c.blended(with: SKColor(red: 1, green: 0.3, blue: 0.5, alpha: 1), 0.5), at: p, radius: 46, draw: charge * 0.7, life: 1.9, spin: -1.8, intensity: 1.5)
        spellLight(c, at: CGPoint(x: p.x, y: p.y + 20), peak: 1, rise: charge, hold: 0.15, fall: 1.0, falloff: 0.9)
        inwardSparks(c, at: p, count: 34, radius: 120, duration: charge)
        floatGlyphs(c, at: p, count: 7, radius: 70, life: 1.6)
        tendrils(SKColor(red: 0.12, green: 0.03, blue: 0.2, alpha: 1), at: p, count: 7, radius: 110, life: 1.8)
        let core = glowSprite(c, size: 40, alpha: 0)
        core.position = CGPoint(x: p.x, y: p.y + 34)
        fx.addChild(core)
        core.run(.sequence([.group([.fadeAlpha(to: 0.9, duration: charge), .scale(to: 2.2, duration: charge)]), .group([.scale(to: 7, duration: 0.25), .fadeOut(withDuration: 0.3)]), .removeFromParent()]))
        for k in 0..<5 { run(.wait(forDuration: charge * Double(k) / 5)) { [weak self] in self?.shake(0.05) } }

        run(.wait(forDuration: charge)) { [weak self] in
            guard let self else { return }
            self.hitStop(0.075)
            Haptics.heavy()
            RLAudio.shared.sfx("blast", volume: 0.9)
            self.shake(0.85)
            self.screenFlash(c.blended(with: .white, 0.5), 0.55, 0.35)
            self.chroma(1)
            self.shockwave(c, at: p, radius: 270, duration: 0.6, strength: 1)
            self.runeCircle(c, at: p, radius: 210, draw: 0.12, life: 0.9, spin: 3, intensity: 1.6)
            for _ in 0..<7 {
                let a = CGFloat.random(in: 0...(.pi * 2)), r = CGFloat.random(in: 140...240)
                self.lightning(from: CGPoint(x: p.x, y: p.y + 26), to: CGPoint(x: p.x + cos(a) * r, y: p.y + sin(a) * r * RLScene.perspective), color: c, duration: 0.32, width: 2, jag: 26)
            }
            for (_, a) in self.npcs where hypot(a.position.x - p.x, a.position.y - p.y) < 240 {
                self.lightning(from: CGPoint(x: p.x, y: p.y + 26), to: CGPoint(x: a.position.x, y: a.position.y + 30), color: c.blended(with: .white, 0.3), duration: 0.4, width: 2.4, jag: 18)
            }
            self.burst(c, at: CGPoint(x: p.x, y: p.y + 10), count: 160, speed: 330, life: 0.9, scale: 1.0)
            self.burst(.white, at: CGPoint(x: p.x, y: p.y + 20), count: 50, speed: 520, life: 0.35, tex: "fx_spark", scale: 1.2)
            self.burst(c, at: p, count: 40, speed: 40, life: 1.8, scale: 0.7, flat: false, rise: 60)
            self.smoke(SKColor(red: 0.16, green: 0.06, blue: 0.24, alpha: 1), at: p, count: 26, speed: 90, life: 1.6, scale: 0.9, rise: 30)
            let seen = self.affect(at: p, radius: 240, push: 70, flee: 3.5)
            self.resolve(.glyph, seen)
        }
        endCast(after: charge + 0.22)
    }

    func castShadow() {
        let c = RLSpell.shadow.color
        let dark = SKColor(red: 0.08, green: 0.02, blue: 0.14, alpha: 1)
        let start = player.position
        let charge: TimeInterval = 0.16
        beginCast(charge)
        RLAudio.shared.sfx("whoosh", volume: 0.8)
        Haptics.tap()
        darkPulse = 1
        runeCircle(c, at: start, radius: 46, draw: 0.14, life: 0.8, spin: -3, intensity: 1.0)
        tendrils(dark, at: start, count: 6, radius: 70, life: 0.4, inward: true)
        player.body.run(.sequence([.scaleX(to: 1.15, y: 0.78, duration: charge), .scaleX(to: 1, y: 1, duration: 0.1)]))
        var v = game?.input.vector ?? .zero
        if hypot(v.dx, v.dy) < 0.2 { v = [CGVector(dx: 0, dy: -1), CGVector(dx: 0, dy: 1), CGVector(dx: -1, dy: 0), CGVector(dx: 1, dy: 0)][player.dir] }
        let n = hypot(v.dx, v.dy); v = CGVector(dx: v.dx / n, dy: v.dy / n)
        var pts: [CGPoint] = [start]
        var cur = start
        for _ in 0..<18 { let nx = map.slide(from: cur, by: CGVector(dx: v.dx * 10, dy: v.dy * 10)); if nx == cur { break }; cur = nx; pts.append(cur) }
        let end = cur
        run(.wait(forDuration: charge)) { [weak self] in
            guard let self else { return }
            let dashT: CGFloat = 0.14
            self.spellLight(c, at: start, peak: 0.6, rise: 0.05, hold: 0.15, fall: 0.5, falloff: 1.4, follow: self.player)
            var last: CGFloat = -1
            self.player.run(.customAction(withDuration: TimeInterval(dashT)) { [weak self] _, t in
                guard let self else { return }
                let k = 1 - pow(1 - t / dashT, 3)
                let idx = min(pts.count - 1, Int(k * CGFloat(pts.count - 1)))
                self.player.position = pts[idx]
                if t - last > 0.016 {
                    last = t
                    self.afterimage(self.player, color: dark, alpha: 0.75, add: false)
                    self.afterimage(self.player, color: c, alpha: 0.28, add: true)
                    self.smoke(dark, at: CGPoint(x: self.player.position.x, y: self.player.position.y + 18), count: 3, speed: 20, life: 0.8, scale: 0.45, rise: 15)
                }
            })
            self.run(.wait(forDuration: TimeInterval(dashT))) { [weak self] in
                guard let self else { return }
                Haptics.heavy()
                self.shake(0.4)
                self.chroma(0.6)
                self.shockwave(c, at: end, radius: 150, duration: 0.45, strength: 0.75)
                self.smoke(dark, at: CGPoint(x: end.x, y: end.y + 12), count: 30, speed: 110, life: 1.1, scale: 0.7, rise: 10)
                self.burst(c, at: end, count: 46, speed: 220, life: 0.5, tex: "fx_spark", scale: 1.1)
                for _ in 0..<3 {
                    let a = CGFloat.random(in: 0...(.pi * 2))
                    self.lightning(from: CGPoint(x: end.x, y: end.y + 8), to: CGPoint(x: end.x + cos(a) * 60, y: end.y + sin(a) * 36), color: c, duration: 0.2, width: 1.4, jag: 10)
                }
                self.tendrils(dark, at: end, count: 6, radius: 80, life: 0.9)
                let seen = self.affect(at: end, radius: 120, push: 30, flee: 2)
                self.resolve(.shadow, seen)
            }
        }
        endCast(after: charge + 0.2)
    }

    func castHex() {
        let c = RLSpell.hex.color
        let p = player.position
        let charge: TimeInterval = 0.45
        // nearest target in front
        var target: RLActor?
        var best: CGFloat = 280
        for a in Array(npcs.values) + walkers {
            let d = hypot(a.position.x - p.x, a.position.y - p.y)
            if d < best { best = d; target = a }
        }
        let tp = target?.position ?? map.slide(from: p, by: [CGVector(dx: 0, dy: -120), CGVector(dx: 0, dy: 120), CGVector(dx: -120, dy: 0), CGVector(dx: 120, dy: 0)][player.dir])
        beginCast(charge)
        RLAudio.shared.sfx("hex", volume: 0.8)
        Haptics.soft()
        runeCircle(c, at: p, radius: 60, draw: charge * 0.8, life: 1.4, spin: 1.6)
        runeCircle(c, at: tp, radius: 52, draw: charge, life: 2.4, spin: -2.2, intensity: 1.4)
        floatGlyphs(c, at: tp, count: 5, radius: 40, life: 1.4)
        spellLight(c, at: CGPoint(x: tp.x, y: tp.y + 20), peak: 0.9, rise: charge, hold: 0.6, fall: 1.0, falloff: 1.2, follow: target)
        tendrils(SKColor(red: 0.25, green: 0.01, blue: 0.04, alpha: 1), at: tp, count: 6, radius: 70, life: 1.6)
        run(.wait(forDuration: charge)) { [weak self] in
            guard let self else { return }
            self.hitStop(0.05)
            Haptics.heavy()
            self.shake(0.45)
            self.chroma(0.8)
            self.screenFlash(c, 0.25, 0.3)
            let from = CGPoint(x: p.x, y: p.y + 40)
            let to = CGPoint(x: (target?.position.x ?? tp.x), y: (target?.position.y ?? tp.y) + 30)
            for _ in 0..<3 { self.lightning(from: from, to: to, color: c, duration: 0.45, width: 1.8, jag: 20) }
            self.shockwave(c, at: tp, radius: 130, duration: 0.45, strength: 0.7)
            self.burst(c, at: to, count: 70, speed: 180, life: 0.8)
            let eye = SKSpriteNode(texture: RLTex.get("spell_hex", nearest: false))
            eye.size = CGSize(width: 46, height: 46); eye.blendMode = .add; eye.setScale(0.1)
            eye.position = CGPoint(x: 0, y: 92)
            let host: SKNode = target ?? self.fx
            if target == nil { eye.position = CGPoint(x: tp.x, y: tp.y + 70) }
            host.addChild(eye)
            eye.run(.sequence([.scale(to: 1.15, duration: 0.18).withTiming(.easeOut), .scale(to: 1, duration: 0.1),
                               .repeat(.sequence([.fadeAlpha(to: 0.5, duration: 0.25), .fadeAlpha(to: 1, duration: 0.25)]), count: 4),
                               .group([.fadeOut(withDuration: 0.4), .moveBy(x: 0, y: 20, duration: 0.4)]), .removeFromParent()]))
            if let t = target {
                t.fleeTime = 5
                t.fleeDir = CGVector(dx: (t.position.x - p.x) / max(best, 1), dy: (t.position.y - p.y) / max(best, 1))
                t.body.run(.sequence([.colorize(with: c, colorBlendFactor: 0.6, duration: 0.05), .wait(forDuration: 0.3), .colorize(withColorBlendFactor: 0, duration: 0.6)]))
            }
            var seen = self.affect(at: p, radius: 0, push: 0, flee: 0)
            if let t = target, self.npcs[t.id] != nil, !seen.contains(t.id) { seen.append(t.id) }
            self.resolve(.hex, seen)
        }
        endCast(after: charge + 0.2)
    }

    func castSigil() {
        let c = RLSpell.sigil.color
        let p = player.position
        let charge: TimeInterval = 0.62
        let life: TimeInterval = 18
        beginCast(charge)
        RLAudio.shared.sfx("sigil", volume: 0.8)
        Haptics.soft()
        burst(c, at: p, count: 50, speed: 30, life: 1.4, scale: 0.6, flat: false, rise: 80)
        runeCircle(c, at: p, radius: 120, draw: charge, life: life, spin: 0.25, intensity: 1.1)
        spellLight(c.blended(with: .white, 0.4), at: CGPoint(x: p.x, y: p.y + 30), peak: 1, rise: charge, hold: life - charge - 2, fall: 2, falloff: 0.75)
        inwardSparks(.white, at: p, count: 24, radius: 140, duration: charge)
        run(.wait(forDuration: charge)) { [weak self] in
            guard let self else { return }
            Haptics.success()
            self.shake(0.4)
            self.screenFlash(c.blended(with: .white, 0.6), 0.6, 0.6)
            self.shockwave(c, at: p, radius: 230, duration: 0.7, strength: 0.6)
            let pillar = SKSpriteNode(texture: RLTex.get("fx_cone", nearest: false))
            pillar.anchorPoint = CGPoint(x: 0.5, y: 0); pillar.zRotation = 0
            pillar.yScale = -1
            pillar.size = CGSize(width: 150, height: 420)
            pillar.position = CGPoint(x: p.x, y: p.y + 420)
            pillar.color = c.blended(with: .white, 0.5); pillar.colorBlendFactor = 1; pillar.blendMode = .add; pillar.alpha = 0
            self.fx.addChild(pillar)
            pillar.run(.sequence([.fadeAlpha(to: 0.8, duration: 0.15), .fadeAlpha(to: 0.25, duration: 1.2), .wait(forDuration: life - 4), .fadeOut(withDuration: 2), .removeFromParent()]))
            let motes = SKEmitterNode()
            motes.particleTexture = RLTex.get("fx_ember", nearest: false)
            motes.particleBirthRate = 22; motes.particleLifetime = 2.4
            motes.particlePositionRange = CGVector(dx: 180, dy: 100)
            motes.particleSpeed = 30; motes.emissionAngle = .pi / 2; motes.emissionAngleRange = 0.4
            motes.particleAlpha = 0.9; motes.particleAlphaSpeed = -0.4; motes.particleScale = 0.7; motes.particleScaleRange = 0.4
            motes.particleColor = c.blended(with: .white, 0.5); motes.particleColorBlendFactor = 1; motes.particleBlendMode = .add
            motes.position = p; motes.targetNode = self.fx
            self.fx.addChild(motes)
            motes.run(.sequence([.wait(forDuration: life - 2), .run { motes.particleBirthRate = 0 }, .wait(forDuration: 2.5), .removeFromParent()]))
            self.burst(.white, at: CGPoint(x: p.x, y: p.y + 20), count: 60, speed: 300, life: 0.6, tex: "fx_spark")
            if let game = self.game { game.state.mood = min(100, game.state.mood + 8); game.float("+настрой", DS.Color.sage) }
            let seen = self.affect(at: p, radius: 0, push: 0, flee: 0)
            self.resolve(.sigil, seen)
        }
        endCast(after: charge + 0.25)
    }
}


extension SKAction {
    func withTiming(_ mode: SKActionTimingMode) -> SKAction { timingMode = mode; return self }
}
