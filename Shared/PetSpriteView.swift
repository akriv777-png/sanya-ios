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
        Image("pet_\(sprite)")
            .interpolation(.none)
            .resizable()
            .frame(width: size, height: size)
    }
}

// MARK: - Particle

private struct Particle: Identifiable {
    let id: UUID
    var x: CGFloat
    var y: CGFloat
    var opacity: Double
    var scale: CGFloat
    var isSmoke: Bool
}

// MARK: - PetSpriteView

/// Full animated pet sprite renderer.
/// Two stacked layers crossfade on emotion change.
/// Idle breathing, blinking, eye glow, particles, effects.
public struct PetSpriteView: View {
    public let emotion: EmotionDef
    public let size: CGFloat

    public init(emotion: EmotionDef, size: CGFloat) {
        self.emotion = emotion
        self.size = size
    }

    // MARK: State

    @State private var previousEmotion: EmotionDef? = nil
    @State private var crossfadeProgress: Double = 1.0  // 0=previous, 1=current

    @State private var breathScale: CGFloat = 1.0
    @State private var isBlinking: Bool = false
    @State private var blinkTimer: Timer? = nil
    @State private var breathTimer: Timer? = nil

    // Effects
    @State private var swayAngle: Double = 0
    @State private var bobAngle: Double = 0
    @State private var shakeOffset: CGFloat = 0
    @State private var droop: CGFloat = 0
    @State private var flickerOpacity: Double = 1.0
    @State private var eyeGlowOpacity: Double = 0.6

    // Spring on change
    @State private var springScale: CGFloat = 1.0

    // Particles
    @State private var particles: [Particle] = []
    @State private var particleTimer: Timer? = nil

    // ZZZ / notes
    @State private var floatingChars: [(id: UUID, text: String, offset: CGFloat, opacity: Double)] = []
    @State private var floatTimer: Timer? = nil

    public var body: some View {
        ZStack(alignment: .bottom) {
            particleLayer
            spriteStack
            eyeGlowLayer
            floatLayer
        }
        .frame(width: size, height: size)
        .onChange(of: emotion.id) { _ in
            handleEmotionChange()
        }
        .onAppear {
            startBreathTimer()
            startBlinkTimer()
            startEffectTimers()
            startParticleTimer()
        }
        .onDisappear {
            stopAllTimers()
        }
    }

    // MARK: - Sprite Stack (crossfade)

    private var spriteStack: some View {
        ZStack {
            // Previous emotion (fades out)
            if let prev = previousEmotion {
                spriteImage(sprite: prev.sprite, effects: prev.effects)
                    .opacity(1.0 - crossfadeProgress)
            }

            // Current emotion (fades in)
            spriteImage(sprite: emotion.sprite, effects: emotion.effects)
                .opacity(crossfadeProgress)
        }
        .scaleEffect(x: mirrorX, y: 1, anchor: .bottom)
        .scaleEffect(CGSize(width: springScale, height: springScale * breathScale), anchor: .bottom)
        .rotationEffect(.degrees(swayAngle + bobAngle))
        .offset(x: shakeOffset)
        .offset(y: droop)
        .opacity(flickerOpacity)
    }

    private func spriteImage(sprite: String, effects: [String]) -> some View {
        let useBlink = isBlinking
        let imageName = useBlink ? "pet_\(sprite)_blink" : "pet_\(sprite)"
        return Image(imageName)
            .interpolation(.none)
            .resizable()
            .frame(width: size, height: size)
    }

    // MARK: - Eye glow layer

    private var eyeGlowLayer: some View {
        ZStack {
            // Blurred copy for glow halo
            Image("pet_\(emotion.sprite)_eyes")
                .interpolation(.none)
                .resizable()
                .frame(width: size, height: size)
                .blur(radius: 3)
                .blendMode(.plusLighter)
                .opacity(eyeGlowOpacity * 0.5)

            // Sharp eyes overlay
            Image("pet_\(emotion.sprite)_eyes")
                .interpolation(.none)
                .resizable()
                .frame(width: size, height: size)
                .blendMode(.plusLighter)
                .opacity(isBlinking ? 0 : eyeGlowOpacity)
        }
        .scaleEffect(x: mirrorX, y: 1, anchor: .bottom)
        .offset(x: shakeOffset)
    }

    // MARK: - Particles

    private var particleLayer: some View {
        TimelineView(.animation(minimumInterval: 1.0/60.0)) { _ in
            Canvas { ctx, canvasSize in
                for p in particles {
                    let rect = CGRect(
                        x: p.x * canvasSize.width - 3,
                        y: p.y * canvasSize.height - 3,
                        width: 6, height: 6
                    )
                    if p.isSmoke {
                        ctx.opacity = p.opacity * 0.4
                        ctx.fill(Path(ellipseIn: rect.insetBy(dx: -2, dy: -2)),
                                 with: .color(.gray.opacity(0.5)))
                    } else {
                        ctx.opacity = p.opacity
                        let col: Color = p.id.uuidString.hasPrefix("a") ? Color(hex: "F2B25C") : Color(hex: "E8894A")
                        ctx.fill(Path(ellipseIn: rect), with: .color(col))
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }

    // MARK: - Floating chars (ZZZ / notes)

    private var floatLayer: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(floatingChars, id: \.id) { item in
                Text(item.text)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "9AA59C"))
                    .offset(x: 4, y: item.offset)
                    .opacity(item.opacity)
            }
        }
        .frame(width: size, height: size, alignment: .topTrailing)
        .allowsHitTesting(false)
    }

    // MARK: - Effect helpers

    private var mirrorX: CGFloat {
        emotion.effects.contains("mirror") ? -1 : 1
    }

    // MARK: - Animation on emotion change

    private func handleEmotionChange() {
        previousEmotion = emotion
        crossfadeProgress = 0

        // Squash-and-stretch spring
        springScale = 0.9
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
            springScale = 1.08
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                springScale = 1.0
            }
        }

        withAnimation(.easeInOut(duration: 0.45)) {
            crossfadeProgress = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            previousEmotion = nil
        }

        stopAllTimers()
        startBreathTimer()
        startBlinkTimer()
        startEffectTimers()
        startParticleTimer()
    }

    // MARK: - Timers

    private func startBreathTimer() {
        breathTimer?.invalidate()
        var phase: Double = 0
        breathTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            phase += (2 * .pi) / (3.0 * 30.0)
            let v = 1.0 + 0.02 * sin(phase)
            DispatchQueue.main.async {
                breathScale = CGFloat(v)
            }
        }
    }

    private func startBlinkTimer() {
        blinkTimer?.invalidate()
        scheduleBlink()
    }

    private func scheduleBlink() {
        let interval = Double.random(in: 2.5...6.0)
        blinkTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [self] _ in
            DispatchQueue.main.async {
                isBlinking = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    isBlinking = false
                    scheduleBlink()
                }
            }
        }
    }

    private func startEffectTimers() {
        let effects = emotion.effects

        // Sway
        if effects.contains("sway") {
            var swayPhase: Double = 0
            Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
                swayPhase += (2 * .pi) / (4.0 * 30.0)
                DispatchQueue.main.async { swayAngle = 5.0 * sin(swayPhase) }
            }
        } else {
            withAnimation(.easeOut(duration: 0.3)) { swayAngle = 0 }
        }

        // Bob / headbang
        if effects.contains("headbang") || effects.contains("bob") {
            let speed = effects.contains("headbang") ? 0.5 : 2.0
            var bobPhase: Double = 0
            Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
                bobPhase += (2 * .pi) / (speed * 30.0)
                let amp = effects.contains("headbang") ? 8.0 : 4.0
                DispatchQueue.main.async { bobAngle = amp * sin(bobPhase) }
            }
        } else {
            withAnimation(.easeOut(duration: 0.3)) { bobAngle = 0 }
        }

        // Shake
        if effects.contains("shake") {
            var shakePhase: Double = 0
            Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
                shakePhase += (2 * .pi) / (0.3 * 30.0)
                DispatchQueue.main.async { shakeOffset = 3.0 * CGFloat(sin(shakePhase)) }
            }
        } else {
            withAnimation(.easeOut(duration: 0.3)) { shakeOffset = 0 }
        }

        // Droop
        if effects.contains("droop") {
            withAnimation(.easeIn(duration: 0.4)) { droop = 4 }
        } else {
            withAnimation(.easeOut(duration: 0.3)) { droop = 0 }
        }

        // Flicker
        if effects.contains("flicker") {
            var flickPhase: Double = 0
            Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { _ in
                flickPhase += 1
                let v = flickPhase.truncatingRemainder(dividingBy: 5) == 0
                    ? Double.random(in: 0.6...1.0) : 1.0
                DispatchQueue.main.async { flickerOpacity = v }
            }
        } else {
            flickerOpacity = 1.0
        }

        // Eye glow pulse
        var glowPhase: Double = 0
        Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { _ in
            glowPhase += (2 * .pi) / (2.5 * 20.0)
            let v = 0.4 + 0.3 * sin(glowPhase)
            DispatchQueue.main.async { eyeGlowOpacity = v }
        }

        // ZZZ
        if effects.contains("zzz") {
            startFloatTimer(chars: ["z", "zz", "zzz"])
        }

        // Notes
        if effects.contains("notes") {
            startFloatTimer(chars: ["♪", "♪♪"])
        }
    }

    private func startParticleTimer() {
        particleTimer?.invalidate()
        // Spawn ember dots and smoke
        particleTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            DispatchQueue.main.async {
                // Remove dead particles
                particles.removeAll { $0.opacity <= 0.01 }
                // Limit
                guard particles.count < 20 else { return }
                let isSmoke = Double.random(in: 0...1) < 0.3
                let p = Particle(
                    id: UUID(),
                    x: Double.random(in: 0.2...0.8),
                    y: 0.85,
                    opacity: Double.random(in: 0.5...0.9),
                    scale: CGFloat.random(in: 0.5...1.0),
                    isSmoke: isSmoke
                )
                particles.append(p)

                // Animate rise and fade
                withAnimation(.linear(duration: Double.random(in: 1.5...3.0))) {
                    if let idx = particles.firstIndex(where: { $0.id == p.id }) {
                        particles[idx].y = Double.random(in: 0.1...0.5)
                        particles[idx].opacity = 0
                    }
                }
            }
        }
    }

    private func startFloatTimer(chars: [String]) {
        floatTimer?.invalidate()
        floatTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            DispatchQueue.main.async {
                floatingChars.removeAll { $0.opacity <= 0.01 }
                guard floatingChars.count < 3, let ch = chars.randomElement() else { return }
                let entry = (id: UUID(), text: ch, offset: CGFloat(0), opacity: Double(1.0))
                floatingChars.append(entry)
                withAnimation(.easeOut(duration: 2.0)) {
                    if let idx = floatingChars.firstIndex(where: { $0.id == entry.id }) {
                        floatingChars[idx].offset = -30
                        floatingChars[idx].opacity = 0
                    }
                }
            }
        }
    }

    private func stopAllTimers() {
        breathTimer?.invalidate()
        blinkTimer?.invalidate()
        particleTimer?.invalidate()
        floatTimer?.invalidate()
        breathTimer = nil
        blinkTimer = nil
        particleTimer = nil
        floatTimer = nil
    }
}
