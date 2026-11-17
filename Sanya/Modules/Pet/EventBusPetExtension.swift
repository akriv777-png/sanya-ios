// EventBusPetExtension.swift — seedDemoEvents() for -petDemo launch arg
// Sanya/Modules/Pet/EventBusPetExtension.swift
//
// NOTE: This file adds the seedDemoEvents() method to EventBus.
// EventBus itself is defined in Sanya/Core/EventBus.swift (by Agent A+B).
// We call EventBus.shared.emit() — no new stored properties needed here.

import Foundation

extension EventBus {
    /// Seeds a fake 7-day event log for the -petDemo launch argument.
    /// Call this after EventBus is initialised (from PetStore.seedDemo).
    func seedDemoEvents() {
        let now = Date()

        // 3 shifts across the week
        let shiftOffsets: [(Double, Double)] = [
            (-6 * 86400, 8.5),
            (-4 * 86400, 7.0),
            (-1 * 86400, 9.0)
        ]
        for (offset, hours) in shiftOffsets {
            let start = now.addingTimeInterval(offset)
            // Inject via public emit — EventBus persists these
            emit(.shiftStarted)
            emit(.shiftEnded(hours: hours))
        }

        // 40 track plays
        for i in 0..<40 {
            let titles = ["Город", "Mire", "Bleed", "Иди", "Nox", "Ночь", "Current", "Weight"]
            let title = titles[i % titles.count]
            emit(.trackStarted(title: title, artist: "Demo Artist"))
        }

        // 6 feedings
        let foods = ["burger", "energetic", "fries", "burger", "energetic", "burger"]
        for f in foods {
            emit(.petFed(f))
        }

        // Energy over limit (3 drinks in one day)
        emit(.counterAdded(kind: "energy", today: 3, limit: 2))
        emit(.counterAdded(kind: "energy", today: 3, limit: 2))
        emit(.counterAdded(kind: "energy", today: 3, limit: 2))

        // Some timers
        emit(.timerStarted(minutes: 25))
        emit(.timerDone)
        emit(.timerStarted(minutes: 25))
        emit(.timerDone)

        // Some chat messages
        for _ in 0..<12 {
            emit(.chatMessage(fromUser: true))
            emit(.chatMessage(fromUser: false))
        }

        // Vault
        emit(.vaultOpened)
        emit(.vaultWrongPIN)

        // Module opens
        for mod in ["player", "shifts", "timers", "pet"] {
            emit(.moduleOpened(mod))
        }
    }
}
