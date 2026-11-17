// PetEngine.swift — emotion resolution + tick loop
// Sanya/Modules/Pet/PetEngine.swift

import Foundation
import Combine

// MARK: - Transient event

private struct TransientEmotion {
    let def: EmotionDef
    let expiresAt: Date
}

// MARK: - PetEngine

final class PetEngine: ObservableObject {
    static let shared = PetEngine()

    @Published var currentEmotion: EmotionDef
    @Published var bubbleText: String? = nil
    @Published var isJittery: Bool = false

    private var pendingEvent: String? = nil
    private var transient: TransientEmotion? = nil
    private var jitteryUntil: Date = .distantPast
    private var bubbleTimer: Timer? = nil
    private var resolveTimer: Timer? = nil
    private var cancellables = Set<AnyCancellable>()

    private let store = PetStore.shared
    private let registry = EmotionRegistry.shared

    private init() {
        currentEmotion = registry.def(for: "calm") ?? registry.all.first!
        startResolveTimer()
    }

    // MARK: - Timer

    private func startResolveTimer() {
        resolveTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.resolve() }
        }
    }

    // MARK: - Resolution

    func resolve() {
        let now = Date()
        isJittery = now < jitteryUntil

        // Expire transient
        if let t = transient, now >= t.expiresAt {
            transient = nil
        }

        if let t = transient {
            setEmotion(t.def)
            return
        }

        let hour = Calendar.current.component(.hour, from: now)
        let resolved = registry.resolve(
            stats: store.stats,
            hour: hour,
            bond: store.stats.bond,
            pendingEvent: pendingEvent
        )
        pendingEvent = nil
        setEmotion(resolved)
    }

    private func setEmotion(_ def: EmotionDef) {
        guard def.id != currentEmotion.id else { return }
        currentEmotion = def
        scheduleBubble(def)
    }

    // MARK: - Bubble

    private func scheduleBubble(_ def: EmotionDef) {
        guard !def.bubble.isEmpty else { return }
        // Show bubble ~40% of the time on emotion change
        guard Double.random(in: 0...1) < 0.4 else { return }
        let line = def.bubble.randomElement() ?? ""
        showBubble(line)
    }

    func showBubble(_ text: String) {
        bubbleText = text
        bubbleTimer?.invalidate()
        bubbleTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.bubbleText = nil }
        }
    }

    // MARK: - Reactions (called by PetBridge)

    func react(to event: AppEvent) {
        switch event {
        case .trackStarted:
            setTransient(id: "music", duration: 30)
        case .trackPaused:
            clearTransient()
        case .shiftUpcoming:
            setTransient(id: "worker", duration: 60)
        case .shiftStarted:
            setTransient(id: "shift_on", duration: 45)
        case .shiftEnded:
            setTransient(id: "tired", duration: 20)
        case .timerDone:
            setTransient(id: "bell", duration: 8)
        case .counterAdded(let kind, let today, let limit):
            if kind == "energy" && today > limit {
                setTransient(id: "grumble", duration: 10)
                showBubble("третья баночка?? ладно.")
            }
        case .vaultWrongPIN:
            setTransient(id: "suspicion", duration: 6)
        case .vaultOpened:
            setTransient(id: "watches", duration: 5)
        case .chatMessage(let fromUser):
            if fromUser, Double.random(in: 0...1) < 0.3 {
                setTransient(id: "chat", duration: 4)
            }
        case .moduleOpened:
            if Double.random(in: 0...1) < 0.2 {
                setTransient(id: "curious", duration: 4)
            }
        case .petFed(let foodID):
            pendingEvent = "petFed"
            if foodID == "energetic" {
                isJittery = true
                jitteryUntil = Date().addingTimeInterval(3600)
                setTransient(id: "energized", duration: 10)
            } else {
                setTransient(id: "fed", duration: 8)
            }
        case .petPlayed:
            setTransient(id: "played", duration: 8)
        case .petPetted:
            setTransient(id: "petted", duration: 5)
        default:
            break
        }
    }

    // MARK: - Force emotion (debug/UI)

    func forceEmotion(id: String) {
        guard let def = registry.def(for: id) else { return }
        setTransient(def: def, duration: 15)
    }

    // MARK: - Helpers

    private func setTransient(id: String, duration: Double) {
        guard let def = registry.def(for: id) else { return }
        setTransient(def: def, duration: duration)
    }

    private func setTransient(def: EmotionDef, duration: Double) {
        transient = TransientEmotion(def: def, expiresAt: Date().addingTimeInterval(duration))
        setEmotion(def)
    }

    private func clearTransient() {
        transient = nil
        resolve()
    }

    // MARK: - Current sprite / effects

    var currentSprite: String { currentEmotion.sprite }
    var currentEffects: [String] { currentEmotion.effects + (isJittery ? ["flicker"] : []) }
}
