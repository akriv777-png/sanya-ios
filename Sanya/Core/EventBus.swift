import Foundation
import Combine

// MARK: - AppEvent

enum AppEvent: Codable, Hashable {
    case moduleOpened(String)
    case trackStarted(title: String, artist: String)
    case trackPaused
    case shiftUpcoming(minutes: Int)
    case shiftStarted
    case shiftEnded(hours: Double)
    case timerStarted(minutes: Int)
    case timerDone
    case counterAdded(kind: String, today: Int, limit: Int)
    case vaultOpened
    case vaultWrongPIN
    case chatMessage(fromUser: Bool)
    case petFed(String)
    case petPlayed
    case petPetted
}

// MARK: - LoggedEvent

struct LoggedEvent: Codable {
    var date: Date
    var event: AppEvent
}

// MARK: - EventBus

final class EventBus: ObservableObject {
    static let shared = EventBus()

    let subject = PassthroughSubject<AppEvent, Never>()

    private let logFileName = "events.json"
    private let maxAge: TimeInterval = 35 * 24 * 3600  // 35 days

    // In-memory log — loaded lazily
    private var cachedLog: [LoggedEvent]?

    func emit(_ e: AppEvent) {
        subject.send(e)
        appendToLog(e)
    }

    func log(since: Date) -> [LoggedEvent] {
        allLog().filter { $0.date >= since }
    }

    // MARK: - Private persistence

    private func allLog() -> [LoggedEvent] {
        if let cached = cachedLog { return cached }
        let loaded = loadLog()
        cachedLog = loaded
        return loaded
    }

    private func appendToLog(_ event: AppEvent) {
        let entry = LoggedEvent(date: Date(), event: event)
        var log = allLog()
        log.append(entry)
        // Remove entries older than 35 days
        let cutoff = Date().addingTimeInterval(-maxAge)
        log = log.filter { $0.date >= cutoff }
        cachedLog = log
        saveLog(log)
    }

    private func loadLog() -> [LoggedEvent] {
        let url = Self.logURL
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([LoggedEvent].self, from: data)) ?? []
    }

    private func saveLog(_ log: [LoggedEvent]) {
        guard let data = try? JSONEncoder().encode(log) else { return }
        try? data.write(to: Self.logURL, options: .atomic)
    }

    private static var logURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("events.json")
    }
}
