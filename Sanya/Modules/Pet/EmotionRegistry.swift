// EmotionRegistry.swift — data-driven emotion loader
// Sanya/Modules/Pet/EmotionRegistry.swift

import Foundation

// MARK: - Registry (EmotionTrigger and EmotionDef are in Shared/PetSpriteView.swift)

final class EmotionRegistry {
    static let shared = EmotionRegistry()

    private(set) var all: [EmotionDef] = []
    private var byID: [String: EmotionDef] = [:]

    private init() {
        load()
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "emotions", withExtension: "json") else {
            print("[EmotionRegistry] emotions.json not found")
            return
        }
        guard let data = try? Data(contentsOf: url) else { return }
        do {
            let defs = try JSONDecoder().decode([EmotionDef].self, from: data)
            all = defs.sorted { $0.priority > $1.priority }
            byID = Dictionary(uniqueKeysWithValues: defs.map { ($0.id, $0) })
        } catch {
            print("[EmotionRegistry] decode error:", error)
        }
    }

    func def(for id: String) -> EmotionDef? { byID[id] }

    // MARK: - Trigger Evaluation

    /// Returns the highest-priority def whose triggers all match given context.
    func resolve(stats: PetStats, hour: Int, bond: Double, pendingEvent: String?) -> EmotionDef {
        for def in all {
            if triggersMatch(def.triggers, stats: stats, hour: hour, bond: bond, pendingEvent: pendingEvent) {
                return def
            }
        }
        return byID["calm"] ?? all.first!
    }

    private func triggersMatch(
        _ triggers: [EmotionTrigger],
        stats: PetStats,
        hour: Int,
        bond: Double,
        pendingEvent: String?
    ) -> Bool {
        guard !triggers.isEmpty else { return true }
        // ALL triggers must match (AND semantics)
        for t in triggers {
            if !triggerMatches(t, stats: stats, hour: hour, bond: bond, pendingEvent: pendingEvent) {
                return false
            }
        }
        return true
    }

    private func triggerMatches(
        _ t: EmotionTrigger,
        stats: PetStats,
        hour: Int,
        bond: Double,
        pendingEvent: String?
    ) -> Bool {
        switch t.kind {
        case "stat":
            let value: Double
            switch t.stat ?? "" {
            case "satiety": value = stats.satiety
            case "energy":  value = stats.energy
            case "mood":    value = stats.mood
            case "bond":    value = bond
            default: return false
            }
            if let below = t.below, value >= below { return false }
            if let above = t.above, value <= above { return false }
            return true

        case "bond":
            if let below = t.below, bond >= below { return false }
            if let above = t.above, bond <= above { return false }
            return true

        case "event":
            return pendingEvent == t.event

        case "time":
            let from = t.fromHour ?? 0
            let to   = t.toHour ?? 24
            return hour >= from && hour < to

        case "random":
            let chance = t.chance ?? 0
            return Double.random(in: 0...1) < chance

        default:
            return false
        }
    }

    // MARK: - Sprite Mapping

    static let validSprites: Set<String> = ["calm", "happy", "hungry", "sleep", "angry", "music"]

    static func baseSprite(for emotionID: String) -> String {
        let registry = EmotionRegistry.shared
        guard let def = registry.def(for: emotionID) else { return "calm" }
        return validSprites.contains(def.sprite) ? def.sprite : "calm"
    }
}
