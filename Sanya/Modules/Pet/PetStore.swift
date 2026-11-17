// PetStore.swift — persistent pet state, stats, actions
// Sanya/Modules/Pet/PetStore.swift

import Foundation
import Combine

// MARK: - Value Types

struct PetStats: Codable {
    var satiety: Double  // 0…1, сытость
    var energy: Double   // 0…1, энергия
    var mood: Double     // 0…1, настроение
    var bond: Double     // 0…1, связь (slow decay)

    static let initial = PetStats(satiety: 0.8, energy: 0.75, mood: 0.7, bond: 0.1)

    mutating func clamp() {
        satiety = max(0, min(1, satiety))
        energy  = max(0, min(1, energy))
        mood    = max(0, min(1, mood))
        bond    = max(0, min(1, bond))
    }
}

struct PetSave: Codable {
    var name: String
    var stats: PetStats
    var xp: Double
    var bornAt: Date
    var lastUpdate: Date
    var statsHistory: [PetStatsSnapshot]
}

struct PetStatsSnapshot: Codable {
    var date: Date
    var satiety: Double
    var energy: Double
    var mood: Double
    var bond: Double
}

// MARK: - Foods

struct PetFood: Identifiable {
    let id: String
    let name: String
    let emoji: String
    let satietyDelta: Double
    let energyDelta: Double
    let moodDelta: Double
    let bondDelta: Double
    let jittery: Bool   // «Энергетик» effect

    static let menu: [PetFood] = [
        PetFood(id: "burger",    name: "Бургер",        emoji: "🍔", satietyDelta: 0.35, energyDelta: 0.1,  moodDelta: 0.1,  bondDelta: 0.02, jittery: false),
        PetFood(id: "energetic", name: "Энергетик",     emoji: "⚡",  satietyDelta: 0.1,  energyDelta: 0.4,  moodDelta: 0.2,  bondDelta: 0.01, jittery: true),
        PetFood(id: "fries",     name: "Картошка фри", emoji: "🍟", satietyDelta: 0.25, energyDelta: 0.05, moodDelta: 0.15, bondDelta: 0.03, jittery: false)
    ]
}

// MARK: - Bond Level

enum BondLevel: Int, CaseIterable {
    case stranger = 0, neighbor, koresh, bro, svoy, foreverBro

    var name: String {
        switch self {
        case .stranger:   return "Незнакомец"
        case .neighbor:   return "Сосед"
        case .koresh:     return "Кореш"
        case .bro:        return "Бро"
        case .svoy:       return "Свой"
        case .foreverBro: return "Братан навсегда"
        }
    }

    static func from(bond: Double, xp: Double) -> BondLevel {
        let combined = (bond + min(xp / 100.0, 1.0)) / 2.0
        switch combined {
        case 0..<0.1: return .stranger
        case 0.1..<0.25: return .neighbor
        case 0.25..<0.45: return .koresh
        case 0.45..<0.65: return .bro
        case 0.65..<0.85: return .svoy
        default: return .foreverBro
        }
    }
}

// MARK: - PetStore

final class PetStore: ObservableObject {
    static let shared = PetStore()

    @Published var name: String = "Шиза"
    @Published var stats: PetStats = .initial
    @Published var xp: Double = 0
    @Published var bornAt: Date = Date()
    @Published var lastUpdate: Date = Date()
    @Published var statsHistory: [PetStatsSnapshot] = []
    @Published var pettingCooldownUntil: Date = .distantPast

    private let saveKey = "petSave_v1"
    private var decayTimer: Timer?
    private var historyTimer: Timer?

    var bondLevel: BondLevel { BondLevel.from(bond: stats.bond, xp: xp) }

    private init() {
        load()
        applyDecay()

        if ProcessInfo.processInfo.arguments.contains("-petDemo") {
            seedDemo()
        }

        startDecayTimer()
        startHistoryTimer()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let save = try? JSONDecoder().decode(PetSave.self, from: data) else { return }
        name    = save.name
        stats   = save.stats
        xp      = save.xp
        bornAt  = save.bornAt
        lastUpdate = save.lastUpdate
        statsHistory = save.statsHistory
    }

    func save() {
        let save = PetSave(name: name, stats: stats, xp: xp, bornAt: bornAt,
                           lastUpdate: lastUpdate, statsHistory: statsHistory)
        if let data = try? JSONEncoder().encode(save) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    // MARK: - Decay

    private func applyDecay() {
        let now = Date()
        let hours = now.timeIntervalSince(lastUpdate) / 3600.0
        guard hours > 0 else { return }

        let isAsleep = isNightHour(now)
        let hungerPenalty = stats.satiety < 0.3 ? 0.01 * hours : 0

        stats.satiety -= 0.04 * hours
        if isAsleep {
            stats.energy += 0.12 * hours
        } else {
            stats.energy -= 0.03 * hours
        }
        stats.mood -= (0.02 + hungerPenalty) * hours
        stats.bond -= 0.001 * hours  // very slow decay

        stats.clamp()
        lastUpdate = now
        save()
    }

    private func isNightHour(_ date: Date) -> Bool {
        let h = Calendar.current.component(.hour, from: date)
        return h >= 0 && h < 7
    }

    private func startDecayTimer() {
        decayTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.tick() }
        }
    }

    private func tick() {
        applyDecay()
    }

    // MARK: - History snapshotting

    private func startHistoryTimer() {
        historyTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.snapshotStats() }
        }
    }

    private func snapshotStats() {
        let snap = PetStatsSnapshot(date: Date(), satiety: stats.satiety,
                                   energy: stats.energy, mood: stats.mood, bond: stats.bond)
        statsHistory.append(snap)
        // Keep last 7 days of hourly snapshots = 168
        if statsHistory.count > 168 { statsHistory.removeFirst(statsHistory.count - 168) }
        save()
    }

    // MARK: - Actions

    func feed(food: PetFood) {
        stats.satiety += food.satietyDelta
        stats.energy  += food.energyDelta
        stats.mood    += food.moodDelta
        stats.bond    += food.bondDelta
        xp += 5
        stats.clamp()
        lastUpdate = Date()
        save()
        EventBus.shared.emit(.petFed(food.id))
    }

    func play() {
        stats.mood  += 0.15
        stats.energy -= 0.1
        stats.bond  += 0.05
        xp += 8
        stats.clamp()
        lastUpdate = Date()
        save()
        EventBus.shared.emit(.petPlayed)
    }

    func pet() {
        guard Date() >= pettingCooldownUntil else { return }
        stats.bond += 0.03
        stats.mood += 0.08
        xp += 2
        stats.clamp()
        pettingCooldownUntil = Date().addingTimeInterval(5)
        lastUpdate = Date()
        save()
        EventBus.shared.emit(.petPetted)
    }

    // MARK: - Demo Seed

    func seedDemo() {
        name = "Шиза"
        stats = PetStats(satiety: 0.55, energy: 0.6, mood: 0.65, bond: 0.65)
        xp = 42
        bornAt = Date().addingTimeInterval(-7 * 24 * 3600)
        lastUpdate = Date()

        // Seed fake history snapshots (7 days × 4 per day)
        statsHistory = []
        for day in 0..<7 {
            for slot in 0..<4 {
                let offset: TimeInterval = -Double((6 - day) * 24 * 3600 + (3 - slot) * 6 * 3600)
                let snap = PetStatsSnapshot(
                    date: Date().addingTimeInterval(offset),
                    satiety: Double.random(in: 0.3...0.9),
                    energy:  Double.random(in: 0.2...0.9),
                    mood:    Double.random(in: 0.4...0.9),
                    bond:    Double.random(in: 0.5...0.75)
                )
                statsHistory.append(snap)
            }
        }

        save()

        // Emit fake event log via EventBus (async to let store finish loading)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            EventBus.shared.seedDemoEvents()
            PetDiary.shared.generateCurrentWeek()
        }
    }
}
