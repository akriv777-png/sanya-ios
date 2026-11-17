// PetLife.swift — idle behaviours, wandering, night sleep
// Sanya/Modules/Pet/PetLife.swift

import Foundation
import Combine
import SwiftUI

final class PetLife: ObservableObject {
    static let shared = PetLife()

    /// Normalised horizontal wander position in [0, 1]
    @Published var wanderPosition: Double = 0.5
    @Published var isMirrored: Bool = false

    private var idleTimer: Timer? = nil
    private var engine: PetEngine { PetEngine.shared }
    private var store: PetStore { PetStore.shared }

    private init() {
        startIdleTimer()
    }

    // MARK: - Idle Timer

    private func startIdleTimer() {
        // Tick every ~8 seconds for overlay wander, every ~30s for life events
        idleTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.idleTick() }
        }
    }

    private func idleTick() {
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)

        // Sleep at night or when exhausted
        let shouldSleep = (hour >= 0 && hour < 7) || store.stats.energy < 0.15
        if shouldSleep {
            engine.forceEmotion(id: "sleep")
            return
        }

        // Wake in morning
        if hour == 7 {
            engine.forceEmotion(id: "calm")
        }

        // Random idle behaviours (25% chance each tick)
        let roll = Double.random(in: 0...1)
        switch roll {
        case 0..<0.15:
            wander()
        case 0.15..<0.25:
            yawn()
        case 0.25..<0.35:
            lookAround()
        default:
            break
        }
    }

    private func wander() {
        let newPos = Double.random(in: 0.05...0.95)
        let goingRight = newPos > wanderPosition
        withAnimation(.easeInOut(duration: 2.0)) {
            isMirrored = !goingRight
            wanderPosition = newPos
        }
    }

    private func yawn() {
        guard store.stats.energy < 0.5 else { return }
        engine.forceEmotion(id: "yawn")
        engine.showBubble("зевает...")
    }

    private func lookAround() {
        // Just a brief mirror flip — visual only
        withAnimation(.easeInOut(duration: 0.3)) {
            isMirrored.toggle()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            withAnimation(.easeInOut(duration: 0.3)) {
                self?.isMirrored.toggle()
            }
        }
    }

    // MARK: - Manual position (drag)

    func setPosition(_ x: Double) {
        wanderPosition = max(0.0, min(1.0, x))
    }
}
