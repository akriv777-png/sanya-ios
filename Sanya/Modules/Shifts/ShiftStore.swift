import Foundation
import Combine
import UIKit
import Vision
import UserNotifications

struct Shift: Codable, Identifiable, Hashable {
    var id = UUID()
    var start: Date
    var end: Date
    var note: String = ""
    var hours: Double { max(0, end.timeIntervalSince(start) / 3600) }
}

final class ShiftStore: ObservableObject {
    static let shared = ShiftStore()

    @Published var shifts: [Shift] = [] { didSet { persist() } }
    @Published var rate: Double = UserDefaults.standard.object(forKey: "shift.rate") as? Double ?? 7.5 {
        didSet { UserDefaults.standard.set(rate, forKey: "shift.rate") }
    }
    @Published var remindMinutes: Int = UserDefaults.standard.object(forKey: "shift.remind") as? Int ?? 60 {
        didSet { UserDefaults.standard.set(remindMinutes, forKey: "shift.remind"); reschedule() }
    }

    init() {
        if AppEnv.isUITest {
            shifts = Self.demo()
        } else {
            shifts = DiskStore.load([Shift].self, "shifts.json") ?? []
        }
    }

    var sorted: [Shift] { shifts.sorted { $0.start < $1.start } }
    var nextShift: Shift? { sorted.first { $0.end > Date() } }

    func contains(_ id: UUID) -> Bool { shifts.contains { $0.id == id } }

    func upsert(_ s: Shift) {
        var s = s
        if s.end <= s.start { s.end = s.start.addingTimeInterval(3600) }
        if let i = shifts.firstIndex(where: { $0.id == s.id }) { shifts[i] = s } else { shifts.append(s) }
    }

    func showOnIsland(_ s: Shift) {
        let now = Date()
        let ongoing = s.start <= now
        if ongoing {
            EventBus.shared.emit(.shiftStarted)
        } else {
            let mins = Int(s.start.timeIntervalSinceNow / 60)
            if mins <= 120 { EventBus.shared.emit(.shiftUpcoming(minutes: mins)) }
        }
        let petEmo = EmotionRegistry.baseSprite(for: PetEngine.shared.currentEmotion.id)
        LiveActivityManager.shared.start(kind: "shift", symbol: "fork.knife", state: .init(
            title: ongoing ? "До конца смены" : "До начала смены",
            subtitle: "\(Fmt.time(s.start))–\(Fmt.time(s.end)) · \(s.note)",
            start: ongoing ? s.start : now, end: ongoing ? s.end : s.start,
            colorHex: "FFB020", isPlaying: true, progress: 0,
            petEmotion: petEmo,
            petSatiety: PetStore.shared.stats.satiety,
            petEnergy: PetStore.shared.stats.energy,
            petMood: PetStore.shared.stats.mood
        ))
    }

    func delete(_ id: UUID) { shifts.removeAll { $0.id == id } }

    func addMany(_ list: [Shift]) {
        // не дублируем смены с тем же началом
        let existing = Set(shifts.map { $0.start })
        shifts.append(contentsOf: list.filter { !existing.contains($0.start) })
    }

    func shifts(in interval: DateInterval) -> [Shift] {
        sorted.filter { $0.start >= interval.start && $0.start < interval.end }
    }

    private func persist() {
        if !AppEnv.isUITest { DiskStore.save(shifts, "shifts.json") }
        reschedule()
    }

    /// Локальные напоминания за N минут до каждой будущей смены.
    func reschedule() {
        let center = UNUserNotificationCenterProxy.self
        center.removeShiftReminders { [shifts, remindMinutes] in
            for s in shifts where s.start > Date() {
                Notifier.schedule(id: "shift-\(s.id.uuidString)", title: "🍟 Скоро смена",
                                  body: "В \(Fmt.time(s.start)) — до \(Fmt.time(s.end)). Через \(remindMinutes) мин.",
                                  at: s.start.addingTimeInterval(Double(-remindMinutes * 60)))
            }
        }
    }

    static func demo() -> [Shift] {
        let cal = Fmt.cal
        let today = cal.startOfDay(for: Date())
        let pattern: [(Int, Int, Int, String)] = [
            (-3, 7, 8, "Кухня"), (-2, 15, 8, "Грилль"), (0, 17, 7, "Кухня"), (1, 7, 8, "Фрайер"),
            (3, 12, 6, "Кухня"), (4, 17, 8, "Закрытие"), (6, 10, 8, "Кухня"), (8, 7, 8, "Кухня"),
            (9, 15, 8, "Грилль"), (11, 17, 7, "Кухня"), (13, 10, 6, "Фрайер"), (15, 7, 8, "Кухня"),
        ]
        return pattern.map { d, h, len, note in
            let start = cal.date(byAdding: .hour, value: d * 24 + h, to: today)!
            return Shift(start: start, end: start.addingTimeInterval(Double(len) * 3600), note: note)
        }
    }
}

enum UNUserNotificationCenterProxy {
    static func removeShiftReminders(then: @escaping () -> Void) {
        let c = UNUserNotificationCenter.current()
        c.getPendingNotificationRequests { reqs in
            c.removePendingNotificationRequests(withIdentifiers: reqs.map(\.identifier).filter { $0.hasPrefix("shift-") })
            DispatchQueue.main.async(execute: then)
        }
    }
}

// MARK: - Импорт из скрина

struct ImportResult: Identifiable {
    let id = UUID()
    var lines: [String]
    var shifts: [Shift]
}

enum OCR {
    static func recognize(_ image: UIImage) async -> [String] {
        guard let cg = image.cgImage else { return [] }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                var done = false
                let req = VNRecognizeTextRequest { req, _ in
                    guard !done else { return }
                    done = true
                    let lines = (req.results as? [VNRecognizedTextObservation])?.compactMap { $0.topCandidates(1).first?.string } ?? []
                    cont.resume(returning: lines)
                }
                req.recognitionLevel = .accurate
                req.recognitionLanguages = ["es-ES", "en-US"]
                req.usesLanguageCorrection = false
                do {
                    try VNImageRequestHandler(cgImage: cg).perform([req])
                } catch {}
                if !done { done = true; cont.resume(returning: []) }
            }
        }
    }
}

/// Простой локальный разборщик. ИИ-разбор на сервере — в следующей версии.
enum ShiftParser {
    static let months = ["ene": 1, "feb": 2, "mar": 3, "abr": 4, "may": 5, "jun": 6, "jul": 7, "ago": 8, "sep": 9, "oct": 10, "nov": 11, "dic": 12]

    static func parse(lines: [String], reference: Date = Date()) -> [Shift] {
        let cal = Fmt.cal
        let year = cal.component(.year, from: reference)
        var currentDay: Date?
        var fallbackDay = cal.startOfDay(for: reference)
        var result: [Shift] = []

        for line in lines {
            if let m = Regex.matches(#"\b(\d{1,2})[/.\-](\d{1,2})(?:[/.\-](\d{2,4}))?\b"#, line).first,
               let d = Int(m[1]), let mo = Int(m[2]), (1...31).contains(d), (1...12).contains(mo) {
                var y = Int(m[3]) ?? year
                if y < 100 { y += 2000 }
                currentDay = cal.date(from: DateComponents(year: y, month: mo, day: d))
            } else if let m = Regex.matches(#"\b(\d{1,2})\s*(?:de\s+)?(ene|feb|mar|abr|may|jun|jul|ago|sep|oct|nov|dic)"#, line).first,
                      let d = Int(m[1]), let mo = months[m[2].lowercased()] {
                currentDay = cal.date(from: DateComponents(year: year, month: mo, day: d))
            }
            for t in Regex.matches(#"(\d{1,2})[:.h](\d{2})\s*(?:-|–|—|a|hasta)\s*(\d{1,2})[:.h](\d{2})"#, line) {
                guard let h1 = Int(t[1]), let m1 = Int(t[2]), let h2 = Int(t[3]), let m2 = Int(t[4]), h1 < 24, h2 < 25 else { continue }
                let day = currentDay ?? fallbackDay
                let start = cal.date(bySettingHour: h1, minute: m1, second: 0, of: day)!
                var end = cal.date(bySettingHour: h2 % 24, minute: m2, second: 0, of: day)!
                if end <= start { end = cal.date(byAdding: .day, value: 1, to: end)! }
                result.append(Shift(start: start, end: end, note: "Из скрина"))
                if currentDay == nil { fallbackDay = cal.date(byAdding: .day, value: 1, to: fallbackDay)! }
            }
        }
        return result
    }
}

// MARK: - ИИ-разбор скрина Orquest

/// Sends on-device OCR text to AIClient and asks for strict JSON shifts. Returns nil on any failure
/// so the caller falls back to the local ShiftParser.
enum ShiftAIParser {
    private struct Item: Decodable { let date: String; let start: String; let end: String; let note: String? }

    static func parse(lines: [String], reference: Date = Date()) async -> [Shift]? {
        guard AIClient.isConfigured, !lines.isEmpty else { return nil }
        let cal = Fmt.cal
        let year = cal.component(.year, from: reference)
        let today = ISO.day.string(from: reference)
        let sys = "Ты разбираешь OCR-текст скриншота графика смен Orquest (McDonald's, Испания; дни по-испански: LUN MAR MIÉ JUE VIE SÁB DOM). " +
            "Сегодня \(today), год \(year). Верни JSON-массив [{\"date\":\"yyyy-MM-dd\",\"start\":\"HH:mm\",\"end\":\"HH:mm\",\"note\":\"\"}] только для рабочих смен; " +
            "выходные (LIBRE, descanso, vacaciones) пропускай. Если конец меньше начала — смена через полночь, дату оставь днём начала."
        let text = lines.joined(separator: "\n")
        guard let items = try? await AIClient.json([Item].self, system: sys, user: String(text.prefix(3500))) else { return nil }
        var out: [Shift] = []
        for it in items {
            guard let day = ISO.day.date(from: it.date),
                  let s = hm(it.start), let e = hm(it.end),
                  let start = cal.date(bySettingHour: s.0, minute: s.1, second: 0, of: day),
                  var end = cal.date(bySettingHour: e.0, minute: e.1, second: 0, of: day) else { continue }
            if end <= start { end = cal.date(byAdding: .day, value: 1, to: end) ?? end }
            guard end.timeIntervalSince(start) <= 14 * 3600 else { continue }
            out.append(Shift(start: start, end: end, note: it.note ?? ""))
        }
        return out.isEmpty ? nil : out.sorted { $0.start < $1.start }
    }

    private static func hm(_ s: String) -> (Int, Int)? {
        let p = s.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard p.count == 2, let h = Int(p[0]), let m = Int(p[1]), (0...24).contains(h), (0...59).contains(m) else { return nil }
        return (h == 24 ? 0 : h, m)
    }
}

enum ISO {
    static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
