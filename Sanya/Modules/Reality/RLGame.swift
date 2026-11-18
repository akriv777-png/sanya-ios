import Foundation
import SwiftUI
import Combine

struct RLHud: Equatable {
    var time = "18:20"; var day = 1; var money = 0
    var hunger = 50.0; var energy = 50.0; var mood = 50.0
    var weather: RLWeather = .rain; var zone = ""; var goal = ""
    var mana = 100.0; var wanted = 0
}

enum RLPromptKind: Equatable { case npc(String), interact(RLInteractKind) }
struct RLPrompt: Equatable { var kind: RLPromptKind; var label: String; var symbol: String }

enum RLPanel: Equatable {
    case dialog(String), shop(String), inventory, shift, sleep, terminal, menu, summary(String)
}

struct RLToast: Equatable, Identifiable { let id = UUID(); var who: String; var text: String }
struct RLFloat: Equatable, Identifiable { let id = UUID(); var text: String; var color: Color }

final class RLInput { var vector = CGVector.zero }

final class RLGame: ObservableObject {
    @Published var hud = RLHud()
    @Published var prompt: RLPrompt?
    @Published var toast: RLToast?
    @Published var panel: RLPanel?
    @Published var started = false
    @Published var blackout: Double = 0
    @Published var floats: [RLFloat] = []
    @Published var mini = RLMini()
    @Published var soundOn = UserDefaults.standard.object(forKey: "rl.sound") as? Bool ?? true {
        didSet { UserDefaults.standard.set(soundOn, forKey: "rl.sound"); RLAudio.shared.muted = !soundOn }
    }

    var state: RLState
    let input = RLInput()
    let dialogue = RLDialogue()
    weak var scene: RLScene?
    let demo: Bool

    private var hudTimer: Double = 0
    private var saveTimer: Double = 0
    private var hintCooldown: Double = 20
    private var ambientTimer: Double = 25
    private var lastAIAmbient = Date.distantPast
    private var ambientCache: [String: [(String, String)]] = [:]
    private var toastTask: Task<Void, Never>?
    private var announcedShift = -1

    init() {
        let args = ProcessInfo.processInfo.arguments
        demo = args.contains("-rlDemo")
        if demo {
            var s = RLState()
            s.minute = 22 * 60 + 10
            s.weather = .storm; s.hunger = 34; s.energy = 58; s.money = 46
            s.inventory = ["soda": 2, "bar": 1, "umbrella": 1, "coffee": 1]
            s.tutorial = 9
            var lin = RLNPCMemory(); lin.rel = 34; lin.met = true; lin.facts = ["Векс любит острое", "Векс работает в «Высоте»"]; s.npcs["lin"] = lin
            var alex = RLNPCMemory(); alex.rel = 46; alex.met = true; alex.facts = ["Векс засыпал у него на диване"]; s.npcs["alex"] = alex
            s.log("Векс отработал смену в «Высоте»")
            s.log("Сенсор-9 сканировал прохожих у башни")
            var spot = RLWorld.street.spots["spawn"]!
            if let i = args.firstIndex(of: "-rlZone"), i + 1 < args.count, let z = RLZone(rawValue: args[i + 1]) {
                s.zone = z; spot = RLWorld.map(z).spots["spawn"] ?? spot
            }
            if let i = args.firstIndex(of: "-rlHour"), i + 1 < args.count, let h = Double(args[i + 1]) { s.minute = h * 60 + 5; s.weather = .drizzle }
            if args.contains("-rlNearLin") { spot = RLWorld.street.spots["noodle_front"]! }
            s.px = Double(spot.x); s.py = Double(spot.y)
            s.mana = 100
            state = s
        } else if let saved = RLSave.load() {
            state = saved
        } else {
            state = RLGame.freshState()
        }
        dialogue.game = self
        RLAudio.shared.muted = !soundOn
        refreshHud()
    }

    static func freshState() -> RLState {
        var s = RLState()
        let p = RLWorld.street.spots["spawn"]!
        s.px = Double(p.x); s.py = Double(p.y)
        return s
    }

    var hasSave: Bool { demo || RLSave.exists }
    var paused: Bool { panel != nil || !started }

    func begin(fresh: Bool) {
        if fresh && !demo { state = RLGame.freshState(); scene?.reload() }
        withAnimation(.easeInOut(duration: 0.6)) { started = true }
        RLAudio.shared.start()
        scene?.syncAudio()
        if state.tutorial == 0 {
            state.tutorial = 1
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                self.computer("Векс. Площадь у «Высоты», ливень. Мама Лин варит лапшу слева, Алекс где-то рядом. Руны — справа внизу. Только не свети под дроном.")
            }
        }
    }

    func save() { if !demo { RLSave.save(state) } }

    // MARK: - Tick

    func tick(_ dt: Double) {
        guard !paused else { return }
        let minutes = dt * 1.0
        state.minute += minutes
        let outdoors = state.zone == .street
        state.hunger = max(0, state.hunger - 0.075 * minutes)
        state.energy = max(0, state.energy - 0.06 * minutes)
        var target = 55.0
        if state.hunger < 25 { target -= 22 }
        if state.energy < 20 { target -= 15 }
        if outdoors && state.weather.intensity > 0.5 && (state.inventory["umbrella"] ?? 0) == 0 { target -= 10 }
        if state.zone == .apartment { target += 6 }
        state.mood += (target - state.mood) * min(1, 0.0025 * minutes)
        state.mood = min(100, max(0, state.mood))

        let regen = 2.6 * (1 + state.weather.intensity * 0.5)
        state.mana = min(100, state.mana + regen * dt)
        if state.wanted > 0 { state.wanted = max(0, state.wanted - dt / 40) }
        if state.minute >= state.nextWeatherAt { rollWeather() }
        if let g = state.gig, state.minute > g.deadline {
            state.gig = nil; state.inventory["package"] = nil
            adjustRel("whisper", -6)
            state.log("Векс не донёс посылку Шёпота")
            computer("Срок доставки вышел. Посылка самоуничтожилась. Шёпот будет недоволен.")
        }
        hudTimer += dt
        if hudTimer > 0.25 { hudTimer = 0; refreshHud() }
        saveTimer += dt
        if saveTimer > 40 { saveTimer = 0; save() }
        hintCooldown -= dt
        if hintCooldown < 0 { hintCooldown = 50; contextHint() }
        ambientTimer -= dt
        if ambientTimer < 0 { ambientTimer = Double.random(in: 28...55); ambientChatter() }
    }

    private func rollWeather() {
        let r = Double.random(in: 0...1)
        let w: RLWeather = r < 0.2 ? .clear : r < 0.45 ? .drizzle : r < 0.85 ? .rain : .storm
        if w != state.weather {
            state.weather = w
            if w == .storm { computer("Метеосводка: ливень. Сенсоры хуже видят в дождь. Иногда это плюс.") }
        }
        state.nextWeatherAt = state.minute + Double.random(in: 120...300)
        scene?.syncWeather()
    }

    func refreshHud() {
        var h = RLHud()
        h.time = RLClock.text(state.minute); h.day = RLClock.day(state.minute); h.money = state.money
        h.hunger = state.hunger; h.energy = state.energy; h.mood = state.mood
        h.weather = state.weather; h.zone = state.zone.title; h.goal = goal()
        h.mana = state.mana; h.wanted = Int(ceil(state.wanted - 0.05))
        if h != hud { hud = h }
    }

    var hour: Int { RLClock.hour(state.minute) }
    var shiftWindow: Bool { (18...22).contains(hour) }
    var workDay: Int { RLClock.day(state.minute - 6 * 60) }
    var shiftDoneToday: Bool { state.lastShiftDay == workDay }

    func goal() -> String {
        if let g = state.gig, let d = RLCast.get(g.targetNPC) {
            return "Отнести посылку: \(d.name) · до \(RLClock.text(g.deadline))"
        }
        if state.wanted >= 3 { return "Розыск! Уйди из луча дрона и не колдуй" }
        if state.hunger < 28 { return "Поесть: лапша у Мамы Лин" }
        if state.energy < 18 { return "Выспаться дома — «Дом 9», слева" }
        if state.spellsCast == 0 { return "Попробуй руны справа внизу. Только не под дроном" }
        return "Просто живи. Поговори с Алексом или Мамой Лин"
    }

    private func contextHint() {
        guard started, panel == nil else { return }
        if state.hunger < 20 { computer("Уровень глюкозы низкий. Ты начинаешь злиться на фонари. Поешь.") }
        else if state.energy < 12 { computer("Энергия на нуле. Ещё немного — и ты уснёшь стоя. Домой.") }
        else if shiftWindow && !shiftDoneToday && hour == 18 && announcedShift != workDay {
            announcedShift = workDay
            computer("18:00. Корвин уже смотрит на часы. Лифт в «Высоту» — у башни с вывеской.")
        }
    }

    // MARK: - Messages & floats

    func computer(_ text: String) { show(RLToast(who: "КОМПЬЮТЕР", text: text)) }
    func show(_ t: RLToast) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { toast = t }
        RLAudio.shared.sfx("blip", volume: 0.35)
        let dur = 3.5 + Double(t.text.count) / 22
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(dur * 1e9))
            if !Task.isCancelled { withAnimation(.easeOut(duration: 0.4)) { self.toast = nil } }
        }
    }
    func float(_ text: String, _ color: Color) {
        let f = RLFloat(text: text, color: color)
        floats.append(f)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            self.floats.removeAll { $0.id == f.id }
        }
    }

    // MARK: - Relationships

    func adjustRel(_ id: String, _ d: Double) {
        var m = state.mem(id); m.rel = min(100, max(-100, m.rel + d)); state.npcs[id] = m
    }
    static func relLabel(_ v: Double) -> String {
        switch v { case ..<(-30): return "неприязнь"; case ..<10: return "незнакомец"; case ..<35: return "приятель"; case ..<65: return "доверие"; default: return "близкий" }
    }

    // MARK: - Interaction

    func activate() {
        guard let p = prompt else { return }
        Haptics.tap()
        switch p.kind {
        case .npc(let id): openDialog(id)
        case .interact(let k): interact(k)
        }
    }

    func openDialog(_ id: String) {
        scene?.beginTalk(id)
        dialogue.open(id)
        var m = state.mem(id)
        if !m.met { m.met = true; state.npcs[id] = m }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { panel = .dialog(id) }
    }

    func closePanel() {
        if case .dialog = panel { scene?.endTalk() }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { panel = nil }
        refreshHud()
    }

    func npcPresent(_ id: String) -> Bool { scene?.npcVisible(id) ?? false }

    func interact(_ k: RLInteractKind) {
        switch k {
        case .noodle:
            if npcPresent("lin") { openDialog("lin") }
            else { computer("Лапшичная закрыта. Мама Лин открывается в шесть утра.") }
        case .vending: panel = .shop("vending")
        case .shopCounter: panel = .shop("shop")
        case .sleep: panel = .sleep
        case .terminal: panel = .terminal
        case .shift:
            if shiftDoneToday { computer("Смена на сегодня закрыта. Корвин уже записал тебя в «эффективные».") }
            else if !shiftWindow { computer("Смены — с 18:00, начать можно до 23:00. Сейчас \(RLClock.text(state.minute)).") }
            else { withAnimation(.spring()) { panel = .shift } }
        case .cook:
            if (state.inventory["rice"] ?? 0) > 0 {
                take("rice"); give("ricebowl")
                state.minute += 15
                RLAudio.shared.sfx("coin", volume: 0.4)
                float("+ Миска риса", DS.Color.sage)
                computer("Рис сварен. Невероятно, но факт.")
            } else { computer("Плита работает, но варить нечего. Рис продаётся в круглосуточном.") }
        case .couch:
            state.minute += 30; state.energy = min(100, state.energy + 6); state.mood = min(100, state.mood + 5)
            scene?.flash()
            float("+настрой", DS.Color.sage); computer("Полчаса потолка и тишины. Помогло.")
        case .jukebox:
            state.mood = min(100, state.mood + 4); RLAudio.shared.nextBarTrack()
            float("♪", DS.Color.ember)
            scene?.npcSay(nearest: true, "О, эту я люблю.")
        case .railing:
            state.minute += 20; state.mood = min(100, state.mood + 6)
            float("+настрой", DS.Color.sage)
            let lines = ["Город внизу горит, как будто ему не всё равно.", "Где-то там башня Оракула считает каждого. И тебя.", "Дождь стекает с эстакады вниз, в огни. Красиво. Бессмысленно. Красиво."]
            computer(lines.randomElement()!)
        case .trash:
            let key = "trash_\(RLClock.day(state.minute))"
            if state.events.contains(where: { $0.text == key }) { computer("Ты уже рылся тут сегодня. Даже крысы смотрят с жалостью."); return }
            state.events.append(.init(minute: state.minute, text: key))
            let found = Int.random(in: 1...6)
            state.money += found; state.mood = max(0, state.mood - 3)
            RLAudio.shared.sfx("coin", volume: 0.5)
            float("+\(found)₵", DS.Color.ember)
            computer("Найдено: \(found) кредитов и чья-то старая гарнитура. Гарнитуру оставим.")
        case .mirror: break
        }
    }

    // MARK: - Inventory

    func give(_ id: String, _ n: Int = 1) { state.inventory[id, default: 0] += n }
    func take(_ id: String, _ n: Int = 1) {
        let v = (state.inventory[id] ?? 0) - n
        state.inventory[id] = v > 0 ? v : nil
    }

    static func vendorItems(_ v: String) -> [String] {
        switch v {
        case "lin": return ["noodles"]
        case "vending": return ["soda", "energy", "bar"]
        default: return ["rice", "bar", "coffee", "soda", "energy", "umbrella"]
        }
    }
    func price(_ item: RLItem, vendor: String) -> Int {
        if vendor == "lin" && state.mem("lin").rel >= 40 { return item.price - 2 }
        return item.price
    }

    @discardableResult
    func buy(_ id: String, vendor: String) -> Bool {
        let it = RLItem.get(id); let p = price(it, vendor: vendor)
        guard state.money >= p else {
            Haptics.warning(); RLAudio.shared.sfx("error", volume: 0.4)
            computer("Недостаточно кредитов. Работа в «Высоте» платит. Шёпот тоже.")
            return false
        }
        state.money -= p; state.spentToday += p; give(id)
        Haptics.success(); RLAudio.shared.sfx("coin", volume: 0.5)
        float("−\(p)₵", DS.Color.ember)
        if vendor == "lin" {
            adjustRel("lin", 1.5)
            scene?.say("lin", ["Ешь, пока горячее!", "С лишним яйцом, сынок.", "Худышка, ешь медленно!"].randomElement()!)
        }
        refreshHud()
        return true
    }

    func use(_ id: String) {
        let it = RLItem.get(id)
        guard (state.inventory[id] ?? 0) > 0 else { return }
        if id == "rice" { computer("Сырой рис — не еда. Свари его дома на плите."); return }
        guard it.usable else { computer(it.note); return }
        take(id)
        state.hunger = min(100, state.hunger + it.hunger)
        state.energy = min(100, state.energy + it.energy)
        state.mood = min(100, max(0, state.mood + it.mood))
        Haptics.soft(); RLAudio.shared.sfx("eat", volume: 0.5)
        if it.hunger > 0 { float("+\(Int(it.hunger)) сытость", DS.Color.sage) }
        if it.energy > 0 { float("+\(Int(it.energy)) энергия", DS.Color.ember) }
        if id == "noodles" { state.log("Векс ел лапшу у Мамы Лин") }
        if id == "energy" && Int.random(in: 0..<3) == 0 { computer("Третья банка за неделю? Я считаю. Просто чтобы ты знал.") }
        refreshHud()
    }

    // MARK: - Sleep

    func sleep(hours: Double?) {
        let md = RLClock.minuteOfDay(state.minute)
        let wake = 7.0 * 60
        var delta = hours.map { $0 * 60 } ?? (md < wake ? wake - md : 1440 - md + wake)
        delta = max(60, delta)
        let before = state
        withAnimation(.easeInOut(duration: 0.9)) { blackout = 1; panel = nil }
        RLAudio.shared.sfx("sleep", volume: 0.6)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            let h = delta / 60
            self.state.minute += delta
            self.state.energy = min(100, self.state.energy + h * 12.5)
            self.state.hunger = max(0, self.state.hunger - h * 2.6)
            self.state.mood = min(100, self.state.mood + h * 2)
            self.rollWeather()
            let fullNight = hours == nil
            var summary = ""
            if fullNight {
                let day = RLClock.day(before.minute)
                summary = "День \(day) позади.\nЗаработано: \(before.earnedToday)₵ · потрачено: \(before.spentToday)₵.\n"
                let talked = before.npcs.filter { $0.value.talks > 0 }.count
                summary += talked > 0 ? "Людей, с кем ты говорил: \(talked). Неплохо для интроверта." : "Ты ни с кем не говорил. Город это заметил."
                self.state.earnedToday = 0; self.state.spentToday = 0
                self.state.log("Векс проспал до утра")
            }
            self.scene?.reload()
            self.save()
            withAnimation(.easeInOut(duration: 1.2)) { self.blackout = 0 }
            if fullNight { withAnimation(.spring()) { self.panel = .summary(summary) } }
            else { self.computer("Вздремнул \(Int(h)) ч. Мир не изменился. Ты — немного.") }
        }
    }

    // MARK: - Shift

    var tatiHelps: Bool { state.mem("tati").rel >= 35 && npcPresent("tati") }

    func finishShift(served: Int, tips: Int, missed: Int) {
        let pay = 30 + tips
        state.money += pay; state.earnedToday += pay
        state.lastShiftDay = workDay; state.shiftsDone += 1
        let md = RLClock.minuteOfDay(state.minute)
        state.minute += (md < 6 * 60 ? 0 : 1440 - md) + 2 * 60   // -> 02:00
        state.energy = max(0, state.energy - 28); state.hunger = max(0, state.hunger - 18)
        state.mood = min(100, max(0, state.mood + Double(served * 2 - missed * 4)))
        adjustRel("manager", served >= 6 ? 3 : -1)
        adjustRel("tati", 1); adjustRel("alex", 1.5)
        state.log("Векс отработал смену: \(served) гостей, чаевые \(tips)₵")
        withAnimation(.spring()) { panel = nil }
        scene?.reload()
        RLAudio.shared.sfx("coin", volume: 0.6)
        float("+\(pay)₵", DS.Color.ember)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            self.scene?.say("tati", served >= 6 ? "Живой, малой? Красиво отработал." : "Ну… бывает. Иди спи.")
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            self.scene?.say("alex", "Опять дождь. Не надоело ещё? …Пойдём, провожу до лифта.")
            self.computer("Смена закрыта. +\(pay)₵. Сейчас 02:00 — тело просит кровать.")
        }
        save()
    }

    // MARK: - Gigs

    func canTakeGig() -> Bool { state.gig == nil && (hour >= 20 || hour < 5) }
    func takeGig() {
        let candidates = ["lin", "tati", "alex"].filter { id in
            guard let d = RLCast.get(id) else { return false }
            let s = d.slot(at: state.minute + 30); return s.zone != .offmap
        }
        guard let target = candidates.randomElement(), let d = RLCast.get(target) else {
            dialogue.system("Шёпот качает головой: «Сегодня некому. Приходи позже.»"); return
        }
        let reward = 20 + Int(max(0, state.mem("whisper").rel) / 8) + Int.random(in: 0...8)
        state.gig = RLGig(targetNPC: target, deadline: state.minute + 180, reward: reward)
        give("package")
        state.log("Шёпот передал Вексу посылку")
        dialogue.system("Получено: посылка. Адресат — \(d.name). Срок — до \(RLClock.text(state.minute + 180)). Награда — \(reward)₵.")
        Haptics.success()
    }
    func deliverGig() {
        guard let g = state.gig else { return }
        take("package")
        state.money += g.reward; state.earnedToday += g.reward
        adjustRel("whisper", 5); adjustRel(g.targetNPC, 2)
        state.gig = nil
        state.log("Векс доставил посылку для \(RLCast.get(g.targetNPC)?.name ?? "кого-то")")
        dialogue.system("Посылка передана. +\(g.reward)₵ упали на счёт. Шёпот доволен — где бы он ни был.")
        RLAudio.shared.sfx("coin", volume: 0.6)
        float("+\(g.reward)₵", DS.Color.ember)
        Haptics.success()
    }

    // MARK: - Ambient life

    private static let pairLines: [String: [[String]]] = [
        "lin|tati": [["Лин, налей бульона. Я умираю.", "Сначала сядь, потом умирай."], ["Видела, как Алекс на малого смотрит?", "Я всё вижу. Ешь молча."]],
        "alex|tati": [["Ты сегодня тише обычного.", "Я всегда тихий. Это ты громкая."], ["Корвин опять считает лёд.", "Пусть считает. Лёд тает."]],
        "manager|tati": [["Татьяна, улыбка — часть сервиса.", "Улыбка — часть зарплаты, которой нет."]],
        "alex|manager": [["Алекс, ваш KPI в норме.", "Счастлив. Очень."]],
        "alex|lin": [["Опять без зонта, сынок?", "Дождь всё равно найдёт."]],
        "drone|lin": [["Гражданка, ваш прилавок нарушает…", "Кыш, муха!"]],
        "lin|whisper": [["Поешь хоть, тень.", "…Потом."]],
    ]

    func ambientChatter() {
        guard let scene, panel == nil else { return }
        let pairs = scene.nearbyPairs()
        guard let pair = pairs.randomElement() else {
            if let id = scene.npcNearPlayer(), let d = RLCast.get(id) {
                let pool = (d.fallback["generic"] ?? []) + (d.fallback["rumor"] ?? [])
                if let l = pool.randomElement() { scene.say(id, l) }
            }
            return
        }
        let key = [pair.0, pair.1].sorted().joined(separator: "|")
        let ids = [pair.0, pair.1].sorted()
        var exchange: (String, String)? = nil
        if var cached = ambientCache[key], !cached.isEmpty { exchange = cached.removeFirst(); ambientCache[key] = cached }
        else if let pool = RLGame.pairLines[key], let l = pool.randomElement() { exchange = (l[0], l[1]) }
        if let e = exchange {
            scene.say(ids[0], e.0)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_300_000_000)
                scene.say(ids[1], e.1)
            }
        }
        if AIClient.isConfigured && Date().timeIntervalSince(lastAIAmbient) > 200 && !dialogue.typing {
            lastAIAmbient = Date()
            Task { await self.fetchAmbient(ids[0], ids[1], key: key) }
        }
    }

    private func fetchAmbient(_ a: String, _ b: String, key: String) async {
        guard let da = RLCast.get(a), let db = RLCast.get(b) else { return }
        let ev = state.events.suffix(4).map { $0.text }.joined(separator: "; ")
        let sys = "Ты сценарист живого мира киберпанк-игры. Пиши по-русски, коротко, живо, без мата и откровенности."
        let user = """
        Два персонажа случайно пересеклись на улице квартала «Девятка» (\(RLClock.text(state.minute)), \(state.weather.title)).
        А — \(da.name): \(da.persona.prefix(260))
        Б — \(db.name): \(db.persona.prefix(260))
        Недавние события: \(ev.isEmpty ? "ничего особенного" : ev).
        Напиши обмен из двух коротких реплик (до 70 символов каждая) в формате:
        А: ...
        Б: ...
        """
        guard let text = try? await AIClient.chat(system: sys, messages: [(role: "user", content: user)], temperature: 0.95, maxTokens: 120) else { return }
        var la: String?, lb: String?
        for line in text.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("А:") { la = String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
            if t.hasPrefix("Б:") { lb = String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
        }
        if let la, let lb, la.count < 120, lb.count < 120 { ambientCache[key, default: []].append((la, lb)) }
    }

    // MARK: - Drone scan

    func droneScanned() {
        let d = Int.random(in: -2...2)
        state.loyalty = min(100, max(0, state.loyalty + d))
        state.mood = max(0, state.mood - 2)
        state.log("Сенсор-9 просканировал Векса")
        computer(["Сканирование. Импланты в норме — пока. Я подчистил пару следов.", "Луч Оракула прошёл по тебе. Индекс лояльности: \(state.loyalty). Не улыбайся ему.", "Дрон отметил тебя в базе. Ничего нового — ты для них просто бармен."].randomElement()!)
        scene?.say("lin", "Кыш, муха проклятая!", ifNear: true)
        RLAudio.shared.sfx("scan", volume: 0.5)
        Haptics.warning()
    }

    // MARK: - Magic

    func canCast(_ sp: RLSpell) -> Bool { started && panel == nil && state.mana >= sp.cost }

    func spend(_ sp: RLSpell) {
        state.mana = max(0, state.mana - sp.cost)
        state.spellsCast += 1
        refreshHud()
    }

    /// Called by the scene once the spell has resolved.
    func magicResolved(_ sp: RLSpell, witnesses: [String], droneSaw: Bool) {
        var heat = sp.heat * (droneSaw ? 1.6 : 0.5)
        if !witnesses.isEmpty { heat += 0.3 }
        let before = Int(ceil(state.wanted - 0.05))
        state.wanted = min(5, state.wanted + heat)
        let after = Int(ceil(state.wanted - 0.05))
        if state.events.last?.text.hasPrefix("Векс применил") != true || Int.random(in: 0..<3) == 0 {
            state.log("Векс применил магию («\(sp.title)») на площади" + (droneSaw ? " — дрон Оракула это видел" : ""))
        }
        for id in witnesses {
            adjustRel(id, id == "alex" ? 1.0 : -1.5)
            if let d = RLCast.get(id), let l = d.fallback["magic"]?.randomElement() { scene?.say(id, l) }
        }
        if state.spellsCast == 1 {
            computer("Шум в канале… Импланты фонят, когда ты так делаешь. Печати держат, но Оракул ищет именно такое свечение.")
        } else if after > before && after >= 4 {
            computer("Розыск \(after)/5. Оракул поднимает тревогу. Уходи из света, не колдуй.")
        } else if after > before && after >= 2 && droneSaw {
            computer("Дрон зафиксировал сигнатуру. Розыск \(after). Он идёт к тебе.")
        }
        if state.wanted >= 5 { arrest() }
        refreshHud()
    }

    func arrest() {
        let fine = max(10, state.money * 3 / 10)
        state.money = max(0, state.money - fine)
        state.wanted = 0; state.mana = 0
        state.log("Оракул задержал Векса за свечение и отпустил после допроса")
        withAnimation(.easeInOut(duration: 0.5)) { blackout = 1 }
        RLAudio.shared.sfx("scan", volume: 0.8)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            self.state.minute += 180
            let p = RLWorld.street.spots["spawn"]!
            self.state.zone = .street; self.state.px = Double(p.x); self.state.py = Double(p.y)
            self.scene?.reload()
            withAnimation(.easeInOut(duration: 1)) { self.blackout = 0 }
            self.computer("Три часа допроса. Штраф \(fine)₵. Печати выдержали — они не поняли, кто ты. В следующий раз может не повезти.")
        }
    }

    // MARK: - Reset

    func newLife() {
        RLSave.wipe()
        state = RLGame.freshState()
        state.tutorial = 1
        panel = nil
        scene?.reload()
        computer("Новая жизнь. Те же дожди.")
    }
}

// MARK: - Dialogue

final class RLDialogue: ObservableObject {
    struct Line: Identifiable, Equatable { let id = UUID(); var fromPlayer: Bool; var text: String; var system = false; var offline = false }
    @Published var npc = ""
    @Published var lines: [Line] = []
    @Published var typing = false
    @Published var waitingLong = false
    @Published var input = ""
    weak var game: RLGame?
    private var task: Task<Void, Never>?

    var def: RLNPCDef? { RLCast.get(npc) }

    func open(_ id: String) {
        task?.cancel(); typing = false; waitingLong = false
        npc = id; input = ""
        lines = []
        guard let game else { return }
        let mem = game.state.mem(id)
        // show the tail of the last conversation for continuity
        for l in mem.log.suffix(2) { lines.append(Line(fromPlayer: l.fromPlayer, text: l.text)) }
        if id == "computer" {
            lines.append(Line(fromPlayer: false, text: "Слушаю. Сводка: \(RLClock.text(game.state.minute)), \(game.state.weather.title), на счету \(game.state.money)₵."))
            return
        }
        if let d = def {
            let pool = mem.met && mem.rel > 10 ? (d.fallback["greet"] ?? []) : (d.fallback["greet"] ?? [])
            if mem.log.isEmpty || lines.isEmpty { lines.append(Line(fromPlayer: false, text: pool.randomElement() ?? "…")) }
        }
    }

    func system(_ text: String) { lines.append(Line(fromPlayer: false, text: text, system: true)) }

    var quick: [String] {
        switch npc {
        case "computer": return ["Что мне делать?", "Кто где сейчас?", "Проанализируй Алекса", "Как там Оракул?"]
        case "drone": return ["Что тебе нужно?", "Какой мой индекс?", "Устал летать?"]
        case "whisper": return ["Есть работа?", "Что слышно?", "Кто ты такой?"]
        case "lin": return ["Привет, Мама Лин!", "Что нового в квартале?", "Как дела?"]
        case "alex": return ["Привет", "Как ты?", "Опять дождь…", "Что после смены?"]
        default: return ["Привет", "Что слышно?", "Как дела?"]
        }
    }

    struct Action: Identifiable { let id: String; let title: String; let symbol: String }
    var actions: [Action] {
        guard let game else { return [] }
        var a: [Action] = []
        if let g = game.state.gig, g.targetNPC == npc { a.append(.init(id: "deliver", title: "Отдать посылку", symbol: "shippingbox.fill")) }
        switch npc {
        case "lin":
            let p = game.price(RLItem.get("noodles"), vendor: "lin")
            a.append(.init(id: "buy_noodles", title: "Лапша · \(p)₵", symbol: "takeoutbag.and.cup.and.straw.fill"))
            let m = game.state.mem("lin")
            if game.state.hunger < 30 && m.rel >= 55 && m.lastFreebieDay != RLClock.day(game.state.minute) {
                a.append(.init(id: "free_noodles", title: "«Ешь, за счёт заведения»", symbol: "heart.fill"))
            }
        case "whisper": if game.canTakeGig() { a.append(.init(id: "gig", title: "Взять заказ", symbol: "shippingbox")) }
        case "manager", "tati": if game.shiftWindow && !game.shiftDoneToday && game.state.zone == .bar { a.append(.init(id: "shift", title: "Начать смену", symbol: "wineglass.fill")) }
        case "drone": a.append(.init(id: "id", title: "Показать ID", symbol: "person.text.rectangle"))
        default: break
        }
        return a
    }

    func perform(_ id: String) {
        guard let game else { return }
        switch id {
        case "deliver": game.deliverGig()
        case "buy_noodles": if game.buy("noodles", vendor: "lin") { system("В инвентаре: лапша Мамы Лин. Съешь из рюкзака, пока горячая.") }
        case "free_noodles":
            var m = game.state.mem("lin"); m.lastFreebieDay = RLClock.day(game.state.minute); game.state.npcs["lin"] = m
            game.give("noodles"); system("Мама Лин молча ставит перед тобой миску. Денег не берёт.")
            Haptics.success()
        case "gig": game.takeGig()
        case "shift": game.closePanel(); Task { @MainActor in try? await Task.sleep(nanoseconds: 350_000_000); game.panel = .shift }
        case "id":
            game.state.loyalty = min(100, game.state.loyalty + 2)
            lines.append(Line(fromPlayer: false, text: "Идентификатор принят. Индекс лояльности гражданина: \(game.state.loyalty). Спасибо за прозрачность."))
        default: break
        }
        objectWillChange.send()
    }

    func send(_ raw: String? = nil) {
        let text = (raw ?? input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !typing, let game else { return }
        input = ""
        lines.append(Line(fromPlayer: true, text: text))
        Haptics.select()
        typing = true; waitingLong = false
        let id = npc
        let system = systemPrompt(for: id)
        var history: [(role: String, content: String)] = []
        let mem = game.state.mem(id)
        for l in mem.log.suffix(8) { history.append((role: l.fromPlayer ? "user" : "assistant", content: l.text)) }
        for l in lines.dropLast() where !l.system && !l.offline { history.append((role: l.fromPlayer ? "user" : "assistant", content: l.text)) }
        history = Array(history.suffix(12))
        history.append((role: "user", content: text))
        task = Task { @MainActor in
            let started = Date()
            let slow = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if !Task.isCancelled && self.typing { self.waitingLong = true }
            }
            var reply: String? = nil
            if AIClient.isConfigured {
                reply = try? await withThrowingTaskGroup(of: String?.self) { group in
                    group.addTask { try await AIClient.chat(system: system, messages: history, temperature: 0.85, maxTokens: 220) }
                    group.addTask { try await Task.sleep(nanoseconds: 32_000_000_000); return nil }
                    let first = try await group.next() ?? nil
                    group.cancelAll()
                    return first
                }
            }
            slow.cancel()
            if Task.isCancelled { return }
            var offline = false
            var out: String
            if let r = reply, let parsed = self.parse(r, npc: id) { out = parsed }
            else {
                offline = true
                let wait = max(0, 0.9 - Date().timeIntervalSince(started))
                try? await Task.sleep(nanoseconds: UInt64(wait * 1e9))
                out = self.fallback(id, text)
            }
            self.typing = false; self.waitingLong = false
            self.lines.append(Line(fromPlayer: false, text: out, offline: offline))
            self.remember(id, player: text, npc: out)
            RLAudio.shared.sfx("blip", volume: 0.25)
        }
    }

    private func remember(_ id: String, player: String, npc: String) {
        guard let game else { return }
        var m = game.state.mem(id)
        m.log.append(RLLine(fromPlayer: true, text: player)); m.log.append(RLLine(fromPlayer: false, text: npc))
        if m.log.count > 12 { m.log.removeFirst(m.log.count - 12) }
        if m.talks == 0 { game.state.log("Векс впервые поговорил с \(RLCast.get(id)?.name ?? "Компьютером")") }
        m.talks += 1
        if m.talks % 3 == 1 { m.rel = min(100, m.rel + 0.6) }
        game.state.npcs[id] = m
    }

    private func fallback(_ id: String, _ text: String) -> String {
        guard let game else { return "…" }
        if id == "computer" { return computerFallback(text) }
        guard let d = def else { return "…" }
        let intent = RLIntent.of(text)
        if intent == "flirt" { game.adjustRel(id, id == "alex" ? 2 : 0.5) }
        if intent == "greet" { game.adjustRel(id, 0.5) }
        let pool = d.fallback[intent] ?? d.fallback["generic"] ?? ["…"]
        return pool.randomElement() ?? "…"
    }

    private func computerFallback(_ text: String) -> String {
        guard let g = game else { return "…" }
        let t = text.lowercased()
        if t.contains("где") || t.contains("кто") {
            let who = RLCast.all.filter { $0.id != "drone" }.map { d -> String in
                let s = d.slot(at: g.state.minute); return "\(d.name) — \(s.zone == .offmap ? "вне квартала" : s.activity)"
            }
            return who.joined(separator: ". ") + "."
        }
        if t.contains("алекс") { return "Алекс: пульс ровный, когда ты рядом — нет. Делай выводы сам." }
        return "Цель: \(g.goal()). Голод \(Int(g.state.hunger)), энергия \(Int(g.state.energy)), настрой \(Int(g.state.mood))."
    }

    /// Strips service tags, applies relationship/memory updates.
    private func parse(_ raw: String, npc id: String) -> String? {
        guard let game else { return nil }
        var keep: [String] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let t = line.trimmingCharacters(in: .whitespaces)
            let low = t.lowercased()
            if low.hasPrefix("#rel") || low.hasPrefix("[rel") {
                let num = t.filter { "+-0123456789.".contains($0) }
                if let v = Double(num) { game.adjustRel(id, max(-3, min(3, v))) }
                continue
            }
            if low.hasPrefix("#mem") || low.hasPrefix("[mem") {
                if let r = t.firstIndex(of: ":") {
                    let fact = t[t.index(after: r)...].trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "]")))
                    if !fact.isEmpty && fact.count < 120 {
                        var m = game.state.mem(id)
                        if !m.facts.contains(fact) { m.facts.append(fact); if m.facts.count > 10 { m.facts.removeFirst() } }
                        game.state.npcs[id] = m
                    }
                }
                continue
            }
            keep.append(String(line))
        }
        var text = keep.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if let d = def, text.hasPrefix(d.name + ":") { text = String(text.dropFirst(d.name.count + 1)).trimmingCharacters(in: .whitespaces) }
        let low = text.lowercased()
        if low.contains("языковая модель") || low.contains("as an ai") || low.contains("я не могу помочь") { return nil }
        if text.count > 480 { text = String(text.prefix(480)) + "…" }
        return text.isEmpty ? nil : text
    }

    func systemPrompt(for id: String) -> String {
        guard let g = game else { return "" }
        let s = g.state
        let events = s.events.filter { !$0.text.hasPrefix("trash_") }.suffix(6).map { "— \(RLClock.text($0.minute)) \($0.text)" }.joined(separator: "\n")
        let world = """
        Мир игры «Реальность»: киберпанк-мегаполис под тотальным контролем Корпорации Оракул. Сенсоры и ИИ везде, импланты, хакеры, дроны. Атмосфера: дождь, дым, озон, неон, сырость, усталость. Квартал «Девятка» — нижний город у подножия башни, на верхнем этаже которой элитный бар «Высота». На улице: лапшичная Мамы Лин, круглосуточный 24/7, дом №9, тёмный переулок, эстакада с видом на город, патрульный дрон Оракула.
        Векс — главный герой: 19 лет, бармен в «Высоте», нелегал, через барную стойку тихо торгует информацией; в голове у него ИИ-помощник «Компьютер». Сейчас: день \(RLClock.day(s.minute)), \(RLClock.text(s.minute)), погода — \(s.weather.title). Векс: голод \(Int(100 - s.hunger))%, усталость \(Int(100 - s.energy))%, настроение \(Int(s.mood))/100, на счету \(s.money) кредитов.
        Недавние события квартала:
        \(events.isEmpty ? "— тихо" : events)
        """
        if id == "computer" {
            let who = RLCast.all.map { d -> String in let sl = d.slot(at: s.minute); return "\(d.name): \(sl.zone == .offmap ? "вне квартала" : sl.activity)" }.joined(separator: "; ")
            let rels = RLCast.all.map { "\($0.name) — \(RLGame.relLabel(s.mem($0.id).rel))" }.joined(separator: "; ")
            return RLCast.computerPersona + "\n" + world + "\nКто где: \(who).\nОтношения: \(rels).\nТекущая цель: \(g.goal()).\nПравила: только по-русски, 1–3 коротких предложения, без markdown. Безопасный контент."
        }
        guard let d = RLCast.get(id) else { return world }
        let m = s.mem(id)
        let slot = d.slot(at: s.minute)
        var gig = ""
        if let gg = s.gig { gig = gg.targetNPC == id ? "\nУ Векса для тебя посылка от Шёпота — ты её ждёшь." : "" }
        if id == "whisper" { gig = s.gig == nil ? "\nЗаказ для Векса есть, если он попросит (кнопка «Взять заказ» появится сама)." : "\nВекс сейчас несёт твою посылку." }
        return """
        \(d.persona)

        \(world)

        Ты сейчас: \(slot.activity) (\(slot.zone.title)).
        Твоё отношение к Вексу: \(RLGame.relLabel(m.rel)) (\(Int(m.rel)) из 100). Вы говорили \(m.talks) раз.
        Что ты помнишь о Вексе: \(m.facts.isEmpty ? "почти ничего" : m.facts.joined(separator: "; ")).\(gig)

        Правила ответа: говори только как \(d.name), по-русски, 1–3 коротких живых предложения, без markdown и без описания действий длиннее нескольких слов. Не называй себя ИИ. Не выдумывай цены и механики, которых нет. Только безопасный контент: без откровенности, жестокости и наркотиков. Если Векс груб — реагируй как живой человек.
        После реплики, отдельной строкой, добавь служебное: #rel:+N (целое от -3 до 3 — как разговор изменил твоё отношение). Если узнал о Вексе что-то новое и важное — ещё строку #mem: короткий факт.
        """
    }
}
