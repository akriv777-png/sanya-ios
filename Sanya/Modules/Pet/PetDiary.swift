// PetDiary.swift — weekly diary generation, templates, protocol
// Sanya/Modules/Pet/PetDiary.swift

import Foundation
import Combine

// MARK: - Diary Entry

struct DiaryEntry: Codable, Identifiable {
    let id: UUID
    let weekStart: Date
    let weekEnd: Date
    let lines: [String]
    let generatedAt: Date

    var weekLabel: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ru_RU")
        fmt.dateFormat = "d MMM"
        return "\(fmt.string(from: weekStart)) — \(fmt.string(from: weekEnd))"
    }
}

// MARK: - Stats for diary

struct WeeklyStats {
    var shifts: Int = 0
    var shiftHours: Double = 0
    var tracksPlayed: Int = 0
    var feedings: Int = 0
    var timersDone: Int = 0
    var energyDrinks: Int = 0
    var snus: Int = 0
    var chatMessages: Int = 0
    var vaultOpens: Int = 0
    var wrongPINs: Int = 0
    var modulesOpened: Int = 0
}

// MARK: - DiaryGenerator Protocol

protocol DiaryGenerator {
    func generate(stats: WeeklyStats, petName: String, bondLevel: BondLevel) async -> [String]
}

// MARK: - LocalDiaryGenerator (25+ templated Russian lines)

struct LocalDiaryGenerator: DiaryGenerator {
    static let templates: [String] = [
        // Shifts
        "Хозяин отпахал {shifts} смен, {hours} часов у фритюра. Я сидел в его кармане.",
        "За неделю — {shifts} смен. Суммарно {hours} ч в кепке. Героизм? Нет, просто работа.",
        "Три смены? Хватило бы. Нет, пошёл на {shifts}. Молодец что ли.",
        "{shifts} раз выходил к людям. Я бы не стал, но я питомец, мне можно не выходить.",
        "Итого: {hours} часов труда, ноль благодарностей. Это жизнь.",
        // Tracks
        "Прокрутил {tracks} треков. Вкус у хозяина, прямо скажем, мрачный. Уважаю.",
        "Музыки было много — {tracks} треков. Я покачал головой примерно на треть. Остальное — нет.",
        "{tracks} песен за неделю. Некоторые ставил по три раза. Я делал вид, что не замечаю.",
        "Слушал {tracks} треков со мной рядом. Я молчал. Это и есть дружба.",
        // Feedings
        "Кормил меня {feedings} раз. {feedings_comment}",
        "{feedings} кормёжек. Мог бы и больше, честно говоря.",
        "Принёс еды {feedings} раз. Картошку фри оценил.",
        // Timers
        "Таймер запускал {timers} раз. Всегда был удивлён, когда он срабатывал.",
        "{timers} таймеров за неделю. Иногда даже останавливал работу по сигналу. Нечасто.",
        // Energy drinks
        "Выпил {energy} энергетиков. {energy_comment}",
        "{energy} банок за неделю. Я ворчал. Он не слушал. Мы оба знали, чем это кончится.",
        // Chat
        "Написал Сане {chats} раз. Питомца не спрашивал ни разу. Нормально.",
        "Общался с ботом {chats} раз, со мной — ноль. Есть над чем подумать.",
        // General/meta
        "Неделя прошла. Он живой, я живой. Это уже достижение.",
        "Если бы я вёл счёт обидам — не хватило бы памяти. Но я не веду. Пока.",
        "Он носил меня в кармане всю неделю. Это либо забота, либо забывчивость. Не знаю.",
        "Телефон падал {falls} раз. Я не считаю, но запомнил.",
        "Открывал приложение каждый день. Это что-то значит. Или нет. Я питомец, не психолог.",
        "Скучно не было. Плохо тоже не было. Это называется стабильность. Ненавижу стабильность.",
        "За эту неделю я научился ничему. Зато хозяин, кажется, тоже.",
        // Vault / secrets
        "В Сейф заходил {vault} раз. {wrongpin} из них — с неверным пином. Не осуждаю.",
        // Bond
        "Мы вместе {bond_days} дней. Я всё ещё не уверен, что мне это нравится. Но ухожу я тоже не собираюсь.",
        // Sleep / mood
        "Настроение всю неделю было где-то между «норм» и «да ну». Это норма для нас обоих.",
        "По ночам он не спал — я знаю. Я тоже не спал. Мы хотя бы были не одни в своей бессоннице."
    ]

    func generate(stats: WeeklyStats, petName: String, bondLevel: BondLevel) async -> [String] {
        var result: [String] = []
        // Pick 4–6 unique templates, fill in values
        var pool = Self.templates.shuffled()
        var picked = 0
        for template in pool {
            if picked >= 5 { break }
            let line = fill(template: template, stats: stats, petName: petName)
            if !line.isEmpty {
                result.append(line)
                picked += 1
            }
        }
        return result
    }

    private func fill(template: String, stats: WeeklyStats, petName: String) -> String {
        var s = template
        s = s.replacingOccurrences(of: "{shifts}", with: "\(stats.shifts)")
        s = s.replacingOccurrences(of: "{hours}", with: String(format: "%.1f", stats.shiftHours))
        s = s.replacingOccurrences(of: "{tracks}", with: "\(stats.tracksPlayed)")
        s = s.replacingOccurrences(of: "{feedings}", with: "\(stats.feedings)")
        s = s.replacingOccurrences(of: "{timers}", with: "\(stats.timersDone)")
        s = s.replacingOccurrences(of: "{energy}", with: "\(stats.energyDrinks)")
        s = s.replacingOccurrences(of: "{chats}", with: "\(stats.chatMessages)")
        s = s.replacingOccurrences(of: "{vault}", with: "\(stats.vaultOpens)")
        s = s.replacingOccurrences(of: "{wrongpin}", with: "\(stats.wrongPINs)")
        s = s.replacingOccurrences(of: "{falls}", with: "\(Int.random(in: 1...4))")
        s = s.replacingOccurrences(of: "{bond_days}", with: "\(daysSinceBorn())")

        // Conditional comments
        let feedComment: String
        switch stats.feedings {
        case 0: feedComment = "Я не забуду."
        case 1...2: feedComment = "Мог бы и почаще."
        case 3...5: feedComment = "Нормально."
        default: feedComment = "Это уже много, но я не жалуюсь."
        }
        s = s.replacingOccurrences(of: "{feedings_comment}", with: feedComment)

        let energyComment: String
        switch stats.energyDrinks {
        case 0: energyComment = "Молодец."
        case 1...2: energyComment = "Пойдёт."
        case 3...5: energyComment = "Я ворчал. Он не слышал."
        default: energyComment = "Перебор. Но ладно."
        }
        s = s.replacingOccurrences(of: "{energy_comment}", with: energyComment)

        return s
    }

    private func daysSinceBorn() -> Int {
        let born = PetStore.shared.bornAt
        return max(1, Int(Date().timeIntervalSince(born) / 86400))
    }
}

// MARK: - AIDiaryGenerator stub

struct AIDiaryGenerator: DiaryGenerator {
    // TODO: call OpenAI-compatible endpoint from Assistant settings
    // Endpoint: UserDefaults.standard.string(forKey: "aiBaseURL") ?? ""
    // Key: Keychain.get("openai_key")
    // Build a prompt from WeeklyStats + petName + bond level
    // Parse JSON response as [String]
    func generate(stats: WeeklyStats, petName: String, bondLevel: BondLevel) async -> [String] {
        // Stub: fall back to local generator
        return await LocalDiaryGenerator().generate(stats: stats, petName: petName, bondLevel: bondLevel)
    }
}

// MARK: - PetDiary

final class PetDiary: ObservableObject {
    static let shared = PetDiary()

    @Published var entries: [DiaryEntry] = []
    @Published var isGenerating: Bool = false

    private let saveKey = "petDiary_v1"
    private var generator: DiaryGenerator = LocalDiaryGenerator()

    private init() {
        loadEntries()
    }

    // MARK: - Persistence

    private func loadEntries() {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let saved = try? JSONDecoder().decode([DiaryEntry].self, from: data) else { return }
        entries = saved
    }

    private func saveEntries() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    // MARK: - Generation

    func generateCurrentWeek() {
        guard !isGenerating else { return }
        isGenerating = true

        let cal = Calendar.current
        let now = Date()
        let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now.addingTimeInterval(-7*86400)
        let weekEnd = now

        // Build stats from EventBus log
        let log = EventBus.shared.log(since: weekStart)
        var stats = WeeklyStats()
        var shiftStartTime: Date? = nil

        for logged in log {
            switch logged.event {
            case .shiftStarted:
                shiftStartTime = logged.date
                stats.shifts += 1
            case .shiftEnded(let hours):
                stats.shiftHours += hours
            case .trackStarted:
                stats.tracksPlayed += 1
            case .petFed:
                stats.feedings += 1
            case .timerDone:
                stats.timersDone += 1
            case .counterAdded(let kind, _, _):
                if kind == "energy" { stats.energyDrinks += 1 }
                else if kind == "snus" { stats.snus += 1 }
            case .chatMessage:
                stats.chatMessages += 1
            case .vaultOpened:
                stats.vaultOpens += 1
            case .vaultWrongPIN:
                stats.wrongPINs += 1
            case .moduleOpened:
                stats.modulesOpened += 1
            default:
                break
            }
        }

        let store = PetStore.shared
        let petName = store.name
        let bondLevel = store.bondLevel

        Task { @MainActor in
            let lines = await generator.generate(stats: stats, petName: petName, bondLevel: bondLevel)
            let entry = DiaryEntry(id: UUID(), weekStart: weekStart, weekEnd: weekEnd,
                                   lines: lines, generatedAt: Date())
            // Replace existing entry for this week if any
            entries.removeAll { cal.isDate($0.weekStart, inSameDayAs: weekStart) }
            entries.insert(entry, at: 0)
            // Keep last 8 weeks
            if entries.count > 8 { entries = Array(entries.prefix(8)) }
            saveEntries()
            isGenerating = false
        }
    }

    // MARK: - Demo seed

    func seedDemoEntries() {
        guard entries.isEmpty else { return }
        let cal = Calendar.current
        let now = Date()

        for weekOffset in 1...3 {
            let weekEnd = now.addingTimeInterval(-Double((weekOffset - 1)) * 7 * 86400)
            let weekStart = weekEnd.addingTimeInterval(-7 * 86400)

            var stats = WeeklyStats()
            stats.shifts = Int.random(in: 2...4)
            stats.shiftHours = Double(stats.shifts) * Double.random(in: 6...9)
            stats.tracksPlayed = Int.random(in: 20...60)
            stats.feedings = Int.random(in: 3...8)
            stats.timersDone = Int.random(in: 1...5)
            stats.energyDrinks = Int.random(in: 1...6)
            stats.chatMessages = Int.random(in: 5...20)

            Task { @MainActor in
                let lines = await LocalDiaryGenerator().generate(
                    stats: stats, petName: PetStore.shared.name, bondLevel: .shadow
                )
                let entry = DiaryEntry(id: UUID(), weekStart: weekStart, weekEnd: weekEnd,
                                       lines: lines, generatedAt: Date())
                self.entries.append(entry)
                self.saveEntries()
            }
        }
    }
}
