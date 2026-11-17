// PetSpriteView.swift — pixel-art pet renderer (SwiftUI only, no UIKit app APIs)
// Shared/PetSpriteView.swift
// Lives in Shared/ so the widget extension can reuse PetStaticSprite and EmotionDef.

import SwiftUI

// MARK: - Data Models (compiled into app and widget)

public struct EmotionTrigger: Codable, Hashable {
    public let kind: String          // "stat" | "event" | "time" | "bond" | "random"
    public let stat: String?
    public let below: Double?
    public let above: Double?
    public let event: String?
    public let fromHour: Int?
    public let toHour: Int?
    public let chance: Double?

    public init(
        kind: String,
        stat: String? = nil,
        below: Double? = nil,
        above: Double? = nil,
        event: String? = nil,
        fromHour: Int? = nil,
        toHour: Int? = nil,
        chance: Double? = nil
    ) {
        self.kind = kind
        self.stat = stat
        self.below = below
        self.above = above
        self.event = event
        self.fromHour = fromHour
        self.toHour = toHour
        self.chance = chance
    }
}

public struct EmotionDef: Codable, Identifiable, Hashable {
    public let id: String
    public let name: String          // Russian display name
    public let sprite: String        // base sprite id: calm/happy/hungry/sleep/angry/music
    public let effects: [String]     // sway, bob, headbang, shake, stretch, droop, mirror, flicker, zzz, notes, cap, bell
    public let priority: Int
    public let triggers: [EmotionTrigger]
    public let minDuration: Double   // seconds
    public let bubble: [String]      // random bubble lines

    public init(
        id: String,
        name: String,
        sprite: String,
        effects: [String] = [],
        priority: Int = 0,
        triggers: [EmotionTrigger] = [],
        minDuration: Double = 3.0,
        bubble: [String] = []
    ) {
        self.id = id
        self.name = name
        self.sprite = sprite
        self.effects = effects
        self.priority = priority
        self.triggers = triggers
        self.minDuration = minDuration
        self.bubble = bubble
    }
}

// MARK: - PetStaticSprite (simple, widget-safe)

/// Lightweight static pet image — suitable for Live Activity and widget.
public struct PetStaticSprite: View {
    public let sprite: String   // base sprite id: calm/happy/hungry/sleep/angry/music
    public let size: CGFloat

    public init(sprite: String, size: CGFloat) {
        self.sprite = sprite
        self.size = size
    }

    public var body: some View {
        Image("pet_\(PetSprites.base(sprite))")
            .interpolation(.none)
            .resizable()
            .aspectRatio(100.0 / 104.0, contentMode: .fit)
            .frame(width: size, height: size)
    }
}

public enum PetSprites {
    public static let ids: Set<String> = ["calm", "happy", "hungry", "sleep", "angry", "music"]
    public static func base(_ s: String) -> String { ids.contains(s) ? s : "calm" }
}

// MARK: - PetSpriteView
//
// Fully time-driven renderer: everything (crossfade, squash, breathing, blinking, eye glow,
// effects, ember/smoke particles) is a pure function of the TimelineView date, so there are
// no Timers and no per-frame @State mutations — cheap and safe to have several on screen.

public struct PetSpriteView: View {
    public let emotion: EmotionDef
    public let size: CGFloat

    public init(emotion: EmotionDef, size: CGFloat) {
        self.emotion = emotion
        self.size = size
    }

    @State private var shown: EmotionDef? = nil
    @State private var previous: EmotionDef? = nil
    @State private var switchedAt: Double = 0
    @State private var seed: Double = Double.random(in: 0...50)

    private static let fade: Double = 0.45

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
            frame(t: ctx.date.timeIntervalSinceReferenceDate)
        }
        .frame(width: size, height: size * 1.04)
        .onAppear {
            if shown == nil { shown = emotion }
        }
        .onChange(of: emotion.id) { _, _ in
            previous = shown ?? emotion
            shown = emotion
            switchedAt = Date().timeIntervalSinceReferenceDate
        }
    }

    // MARK: frame

    @ViewBuilder
    private func frame(t: Double) -> some View {
        let cur: EmotionDef = shown ?? emotion
        let k: Double = min(1, max(0, (t - switchedAt) / Self.fade))
        let squash: Double = sin(k * .pi)                         // 0 → 1 → 0 during the switch
        let breath: Double = sin(t * 2 * .pi / 3.0)
        ZStack(alignment: .bottom) {
            ParticleLayer(t: t, seed: seed, size: size, heavy: cur.effects.contains("flicker") || cur.sprite == "angry")
            if let prev = previous, k < 1 {
                layer(prev, t: t)
                    .opacity(1 - k)
            }
            layer(cur, t: t)
                .opacity(previous == nil ? 1 : k)
                .scaleEffect(x: 1 + 0.07 * squash, y: 1 - 0.09 * squash + 0.02 * breath, anchor: .bottom)
            overlays(cur, t: t)
        }
        .frame(width: size, height: size * 1.04, alignment: .bottom)
    }

    private func layer(_ e: EmotionDef, t: Double) -> some View {
        let fx = Set(e.effects)
        let base = PetSprites.base(e.sprite)
        let period: Double = 3.2 + (seed.truncatingRemainder(dividingBy: 1)) * 2.6
        let blink: Bool = base != "sleep" && (t + seed).truncatingRemainder(dividingBy: period) < 0.13
        let glow: Double = 0.55 + 0.35 * sin(t * 2.4 + seed)

        var rot: Double = 0
        var dx: Double = 0
        var dy: Double = 0
        var sy: Double = 1
        var opacity: Double = 1
        if fx.contains("sway")     { rot += 4 * sin(t * 1.3) }
        if fx.contains("headbang") { rot += 8 * sin(t * 9); dy -= 3 * abs(sin(t * 9)) }
        if fx.contains("bob")      { dy -= 4 * abs(sin(t * 4)) }
        if fx.contains("shake")    { dx += 2.2 * sin(t * 42) }
        if fx.contains("stretch")  { sy *= 1 + 0.07 * max(0, sin(t * 0.9)) }
        if fx.contains("droop")    { sy *= 0.96; dy += Double(size) * 0.015 }
        if fx.contains("flicker")  { opacity = 0.88 + 0.12 * sin(t * 13) }
        let mirror: Bool = fx.contains("mirror")
        let unit = Double(size) / 100.0

        return ZStack {
            Image(blink ? "pet_\(base)_blink" : "pet_\(base)")
                .interpolation(.none)
                .resizable()
            if !blink {
                Image("pet_\(base)_eyes")
                    .interpolation(.none)
                    .resizable()
                    .blur(radius: 2.5 * unit)
                    .opacity(glow)
                    .blendMode(.plusLighter)
                Image("pet_\(base)_eyes")
                    .interpolation(.none)
                    .resizable()
                    .blendMode(.plusLighter)
            }
        }
        .aspectRatio(100.0 / 104.0, contentMode: .fit)
        .frame(width: size, height: size * 1.04)
        .scaleEffect(x: mirror ? -1 : 1, y: sy, anchor: .bottom)
        .rotationEffect(.degrees(rot), anchor: .bottom)
        .offset(x: dx * unit, y: dy * unit)
        .opacity(opacity)
    }

    @ViewBuilder
    private func overlays(_ e: EmotionDef, t: Double) -> some View {
        let fx = Set(e.effects)
        let s = size
        if fx.contains("cap") {
            CapShape()
                .fill(DSColors.sageDeep)
                .overlay(CapShape().stroke(Color.black.opacity(0.6), lineWidth: max(1, s / 90)))
                .frame(width: s * 0.36, height: s * 0.12)
                .offset(x: -s * 0.02, y: -s * 0.86)
        }
        if fx.contains("bell") {
            Image(systemName: "bell.fill")
                .font(.system(size: s * 0.14))
                .foregroundStyle(DSColors.ember2)
                .rotationEffect(.degrees(18 * sin(t * 14)), anchor: .top)
                .offset(x: s * 0.36, y: -s * 0.72)
        }
        if fx.contains("zzz") { FloatingGlyphs(t: t, glyphs: ["z", "Z", "z"], size: s, color: DSColors.mute) }
        if fx.contains("notes") { FloatingGlyphs(t: t, glyphs: ["♪", "♫", "♪"], size: s, color: DSColors.sage) }
    }
}

// MARK: - Helpers

private struct CapShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        // crown
        p.addRoundedRect(in: CGRect(x: r.minX + r.width * 0.12, y: r.minY, width: r.width * 0.7, height: r.height * 0.75),
                         cornerSize: CGSize(width: r.height * 0.35, height: r.height * 0.35))
        // brim
        p.addRect(CGRect(x: r.minX + r.width * 0.05, y: r.minY + r.height * 0.62, width: r.width * 0.95, height: r.height * 0.3))
        return p
    }
}

private struct FloatingGlyphs: View {
    let t: Double
    let glyphs: [String]
    let size: CGFloat
    let color: Color

    var body: some View {
        ZStack {
            ForEach(0..<glyphs.count, id: \.self) { i in
                let life: Double = 2.4
                let ph: Double = ((t + Double(i) * life / Double(glyphs.count)) / life).truncatingRemainder(dividingBy: 1)
                Text(glyphs[i])
                    .font(.system(size: size * (0.1 + 0.04 * Double(i)), weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
                    .opacity(ph < 0.15 ? ph / 0.15 : 1 - ph)
                    .offset(x: size * (0.22 + 0.12 * ph + 0.04 * sin(ph * 6)), y: -size * (0.7 + 0.35 * ph))
            }
        }
    }
}

private struct ParticleLayer: View {
    let t: Double
    let seed: Double
    let size: CGFloat
    let heavy: Bool

    private func h(_ i: Int, _ salt: Double) -> Double {
        let v = sin(Double(i) * 12.9898 + salt * 78.233 + seed) * 43758.5453
        return v - v.rounded(.down)
    }

    var body: some View {
        Canvas { ctx, sz in
            let w = Double(sz.width), hgt = Double(sz.height)
            // smoke puffs (soft, dark)
            var smoke = ctx
            smoke.addFilter(.blur(radius: w * 0.05))
            for i in 0..<6 {
                let life = 3.5 + 1.5 * h(i, 1)
                let ph = ((t + life * h(i, 2)) / life).truncatingRemainder(dividingBy: 1)
                let x = w * (0.2 + 0.6 * h(i, 3)) + w * 0.05 * sin(t * 0.8 + Double(i))
                let y = hgt * (0.95 - 0.55 * ph)
                let r = w * (0.07 + 0.06 * ph)
                let a = 0.35 * sin(ph * .pi)
                smoke.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                           with: .color(Color.black.opacity(a)))
            }
            // embers (small, bright)
            let n = heavy ? 18 : 11
            for i in 0..<n {
                let life = 1.8 + 1.4 * h(i, 4)
                let ph = ((t + life * h(i, 5)) / life).truncatingRemainder(dividingBy: 1)
                let x = w * (0.15 + 0.7 * h(i, 6)) + w * 0.03 * sin(t * 2 + Double(i))
                let y = hgt * (0.92 - 0.75 * ph)
                let r = max(1.0, w * 0.012 * (1 - ph * 0.5))
                let col = h(i, 7) > 0.5 ? DSColors.ember : DSColors.ember2
                ctx.fill(Path(CGRect(x: x, y: y, width: r * 1.6, height: r * 1.6)),
                         with: .color(col.opacity(0.9 * (1 - ph))))
            }
        }
        .allowsHitTesting(false)
    }
}
