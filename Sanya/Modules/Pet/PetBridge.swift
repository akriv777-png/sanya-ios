// PetBridge.swift — EventBus subscriber + Live Activity helper
// Sanya/Modules/Pet/PetBridge.swift

import Foundation
import Combine
import SwiftUI

// MARK: - PetBridge

/// Subscribes to EventBus and drives PetEngine reactions.
final class PetBridge {
    static let shared = PetBridge()

    private var cancellables = Set<AnyCancellable>()
    private var engine: PetEngine { PetEngine.shared }
    private var island: PetIsland { PetIsland.shared }

    private init() {
        subscribeToEvents()
    }

    private func subscribeToEvents() {
        EventBus.shared.subject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handle(event)
            }
            .store(in: &cancellables)
    }

    private func handle(_ event: AppEvent) {
        // Drive engine reactions
        engine.react(to: event)

        // Update Live Activity if running
        island.update(emotion: engine.currentEmotion.id, stats: PetStore.shared.stats)
    }
}

// MARK: - PetIsland

/// Manages the «Питомец» Live Activity (kind "pet").
/// Note: SanyaActivityAttributes.ContentState will gain optional fields
///   petEmotion: String?, petSatiety: Double?, petEnergy: Double?, petMood: Double?
/// appended at the end of the memberwise init. This file uses that extended init.
final class PetIsland {
    static let shared = PetIsland()

    private var lastUpdateTime: Date = .distantPast
    private let throttleInterval: TimeInterval = 15.0  // min 15s between updates

    private init() {}

    // MARK: - Start

    func start() {
        let store = PetStore.shared
        let engine = PetEngine.shared
        let spriteID = EmotionRegistry.baseSprite(for: engine.currentEmotion.id)

        let state = makeState(
            title: store.name,
            subtitle: engine.currentEmotion.name,
            spriteID: spriteID,
            stats: store.stats
        )
        LiveActivityManager.shared.start(kind: "pet", symbol: "heart.fill", state: state)
        lastUpdateTime = Date()
    }

    // MARK: - Update (throttled)

    func update(emotion: String, stats: PetStats) {
        let now = Date()
        guard now.timeIntervalSince(lastUpdateTime) >= throttleInterval else { return }
        guard LiveActivityManager.shared.has("pet") else { return }

        let spriteID = EmotionRegistry.baseSprite(for: emotion)
        let store = PetStore.shared
        let engine = PetEngine.shared

        let state = makeState(
            title: store.name,
            subtitle: engine.currentEmotion.name,
            spriteID: spriteID,
            stats: stats
        )
        LiveActivityManager.shared.update(kind: "pet", state: state)
        lastUpdateTime = now
    }

    // MARK: - End

    func end() {
        LiveActivityManager.shared.end(kind: "pet")
    }

    // MARK: - State builder

    /// Builds ContentState assuming the extended memberwise init:
    /// (title, subtitle, start, end, colorHex, isPlaying, progress,
    ///  petEmotion, petSatiety, petEnergy, petMood)
    private func makeState(
        title: String,
        subtitle: String,
        spriteID: String,
        stats: PetStats
    ) -> SanyaActivityAttributes.ContentState {
        return SanyaActivityAttributes.ContentState(
            title: title,
            subtitle: subtitle,
            start: Date(),
            end: Date().addingTimeInterval(3600),
            colorHex: "A8C5A0",
            isPlaying: false,
            progress: stats.mood,
            petEmotion: spriteID,
            petSatiety: stats.satiety,
            petEnergy: stats.energy,
            petMood: stats.mood
        )
    }
}
