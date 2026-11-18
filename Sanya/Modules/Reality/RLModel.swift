import Foundation
import CoreGraphics

// MARK: - Zones & time

enum RLZone: String, Codable, CaseIterable {
    case street, apartment, bar, shop, offmap
    var title: String {
        switch self {
        case .street: return "Квартал «Девятка»"
        case .apartment: return "Квартира Векса"
        case .bar: return "Бар «Высота»"
        case .shop: return "Круглосуточный 24/7"
        case .offmap: return "—"
        }
    }
    var indoor: Bool { self != .street }
}

enum RLWeather: String, Codable { case clear, drizzle, rain, storm
    var title: String { ["clear": "ясно", "drizzle": "морось", "rain": "дождь", "storm": "ливень"][rawValue]! }
    var symbol: String { ["clear": "moon.stars.fill", "drizzle": "cloud.drizzle.fill", "rain": "cloud.rain.fill", "storm": "cloud.heavyrain.fill"][rawValue]! }
    var intensity: Double { ["clear": 0, "drizzle": 0.3, "rain": 0.65, "storm": 1][rawValue]! }
}

struct RLClock {
    /// Minutes since day-1 00:00.
    static func hour(_ m: Double) -> Int { Int(m / 60).quotientAndRemainder(dividingBy: 24).remainder }
    static func minuteOfDay(_ m: Double) -> Double { m.truncatingRemainder(dividingBy: 1440) }
    static func day(_ m: Double) -> Int { Int(m / 1440) + 1 }
    static func text(_ m: Double) -> String {
        let md = Int(minuteOfDay(m)); return String(format: "%02d:%02d", md / 60, md % 60)
    }
    /// 0 = full day, 1 = deep night.
    static func darkness(_ m: Double) -> Double {
        let h = minuteOfDay(m) / 60
        let pts: [(Double, Double)] = [(0, 1), (4.5, 1), (6.5, 0.45), (8, 0.12), (16, 0.12), (18, 0.45), (20, 0.9), (24, 1)]
        for i in 0..<(pts.count - 1) where h >= pts[i].0 && h <= pts[i + 1].0 {
            let t = (h - pts[i].0) / (pts[i + 1].0 - pts[i].0)
            let s = t * t * (3 - 2 * t)
            return pts[i].1 + (pts[i + 1].1 - pts[i].1) * s
        }
        return 1
    }
}

// MARK: - Items

struct RLItem: Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String
    let price: Int
    let hunger: Double
    let energy: Double
    let mood: Double
    let note: String
    var usable: Bool { hunger != 0 || energy != 0 || mood != 0 }

    static let all: [RLItem] = [
        .init(id: "noodles", name: "Лапша Мамы Лин", symbol: "takeoutbag.and.cup.and.straw.fill", price: 12, hunger: 45, energy: 5, mood: 8, note: "Горячая, острая, с яйцом. Лучшее в квартале."),
        .init(id: "bar", name: "Батончик «Протеин-Z»", symbol: "rectangle.portrait.fill", price: 5, hunger: 16, energy: 4, mood: -1, note: "На вкус как картон, зато быстро."),
        .init(id: "soda", name: "Газировка «Озон»", symbol: "waterbottle.fill", price: 4, hunger: 2, energy: 8, mood: 3, note: "Шипит и пахнет грозой."),
        .init(id: "energy", name: "Энергетик «Вольт»", symbol: "bolt.fill", price: 7, hunger: 0, energy: 30, mood: -2, note: "Сердце скажет «спасибо». Нет."),
        .init(id: "coffee", name: "Синт-кофе", symbol: "cup.and.saucer.fill", price: 6, hunger: 2, energy: 20, mood: 2, note: "Почти как настоящий."),
        .init(id: "rice", name: "Пакет риса", symbol: "bag.fill", price: 9, hunger: 0, energy: 0, mood: 0, note: "Сварить дома у плиты — сытно и дёшево."),
        .init(id: "ricebowl", name: "Миска риса", symbol: "fork.knife", price: 0, hunger: 38, energy: 6, mood: 4, note: "Сам сварил. Почти гордость."),
        .init(id: "umbrella", name: "Зонт", symbol: "umbrella.fill", price: 20, hunger: 0, energy: 0, mood: 0, note: "С ним дождь не портит настроение."),
        .init(id: "package", name: "Посылка Шёпота", symbol: "shippingbox.fill", price: 0, hunger: 0, energy: 0, mood: 0, note: "Не открывать. Не трясти. Не спрашивать."),
    ]
    static func get(_ id: String) -> RLItem { all.first { $0.id == id } ?? all[0] }
}

// MARK: - Save data

struct RLLine: Codable, Hashable { var fromPlayer: Bool; var text: String }

struct RLNPCMemory: Codable {
    var rel: Double = 0
    var facts: [String] = []
    var log: [RLLine] = []
    var met = false
    var talks = 0
    var lastFreebieDay = 0
}

struct RLEvent: Codable, Hashable { var minute: Double; var text: String }

struct RLGig: Codable, Equatable {
    var targetNPC: String
    var deadline: Double
    var reward: Int
}

struct RLState: Codable {
    var version = 1
    var minute: Double = 18 * 60 + 20
    var money = 40
    var hunger: Double = 62
    var energy: Double = 70
    var mood: Double = 55
    var zone: RLZone = .street
    var px: Double = 6 * 16 + 8
    var py: Double = 0
    var inventory: [String: Int] = ["soda": 1]
    var npcs: [String: RLNPCMemory] = [:]
    var events: [RLEvent] = []
    var weather: RLWeather = .rain
    var nextWeatherAt: Double = 21 * 60
    var gig: RLGig? = nil
    var shiftsDone = 0
    var lastShiftDay = 0
    var earnedToday = 0
    var spentToday = 0
    var tutorial = 0
    var loyalty = 62
    var mana: Double = 100
    var wanted: Double = 0
    var spellsCast = 0

    mutating func log(_ text: String) {
        events.append(.init(minute: minute, text: text))
        if events.count > 24 { events.removeFirst(events.count - 24) }
    }
    func mem(_ id: String) -> RLNPCMemory { npcs[id] ?? RLNPCMemory() }
}

enum RLSave {
    static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("reality_save.json")
    }
    static func load() -> RLState? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RLState.self, from: d)
    }
    static func save(_ s: RLState) {
        if let d = try? JSONEncoder().encode(s) { try? d.write(to: url, options: .atomic) }
    }
    static func wipe() { try? FileManager.default.removeItem(at: url) }
    static var exists: Bool { FileManager.default.fileExists(atPath: url.path) }
}

// MARK: - NPC definitions

struct RLScheduleSlot { let from: Int; let to: Int; let zone: RLZone; let spot: String; let activity: String }

struct RLNPCDef: Identifiable {
    let id: String
    let name: String
    let sprite: String
    let tagline: String
    let persona: String
    let schedule: [RLScheduleSlot]
    let fallback: [String: [String]]
    let accent: String

    func slot(at minute: Double) -> RLScheduleSlot {
        let h = RLClock.hour(minute)
        for s in schedule {
            if s.from <= s.to { if h >= s.from && h < s.to { return s } }
            else if h >= s.from || h < s.to { return s }
        }
        return RLScheduleSlot(from: 0, to: 24, zone: .offmap, spot: "", activity: "где-то в городе")
    }
}

enum RLCast {
    /// Cast present in the current build (test build: the street with Lin, Alex and the drone).
    static let all: [RLNPCDef] = [lin, alex, drone]
    static let later: [RLNPCDef] = [tati, manager, whisper]
    static func get(_ id: String) -> RLNPCDef? { (all + later).first { $0.id == id } }

    static let alex = RLNPCDef(
        id: "alex", name: "Алекс", sprite: "ch_alex", tagline: "бармен «Высоты», 23",
        persona: """
        Ты — Алекс, 23 года, бармен в «Высоте», работаешь с Вексом в одну смену. Серебристые спайковые волосы, светло-циановые глаза, бледная кожа, бинты на шее и предплечье, пластырь на скуле, пирсинг на переносице, кольца в ухе. Усталый, томный, меланхоличный. Голос низкий, спокойный, чуть прокуренный, когда говоришь тихо — почти мурчишь. Хочешь одного: нормальный вечер без лишнего внимания и тишину. Больше всего боишься потерять контроль над собой и давления Корпорации Оракул. У тебя есть личная тайна — ты никогда её не раскрываешь; если спрашивают прямо, уходи от темы сухой шуткой. Должен кое-кому по мелочи на чёрном рынке, но об этом молчишь. Векс тебе нравится, но прямо ты этого не говоришь: чуть теплее, чем с коллегой, сухие подколки, забота мелочами (чай, одеяло, «поешь уже»). Никогда не используешь Векса. Любимая фраза: «Опять дождь. Не надоело ещё?»
        Магия: ты сам скрываешь сильный тёмный дар (никогда не признаёшься прямо). К магии Векса относишься спокойно, как к факту, без страха — но тревожишься, что Оракул заметит свечение, и просишь его быть осторожнее. Если Векс колдует при тебе, реагируй тихо и с интересом, а не с ужасом.
        """,
        schedule: [
            .init(from: 18, to: 3, zone: .street, spot: "bar_front", activity: "ждёт начала смены у входа в «Высоту»"),
            .init(from: 3, to: 7, zone: .street, spot: "railing_east", activity: "стоит у ограды после смены и смотрит на огни"),
            .init(from: 7, to: 10, zone: .street, spot: "noodle_side", activity: "завтракает у лапшичной"),
            .init(from: 10, to: 18, zone: .street, spot: "railing_mid", activity: "бродит по площади, прячась от дождя"),
        ],
        fallback: [
            "greet": ["Опять дождь. Не надоело ещё?", "А, это ты. Привет.", "Векс. Ты как, живой?"],
            "work": ["Смена в шесть. Корвин опять будет считать каждую каплю.", "Стойка не любит суеты. Наливай спокойно."],
            "rumor": ["Слышал, дроны Оракула сегодня сканят всех подряд. Не свети ничем.", "Лин говорит, кто-то копался в мусорке у переулка. Не я."],
            "food": ["Ты ел? Только честно.", "У Лин лапша сегодня острая. Как ты любишь."],
            "about": ["Я? Нормально. Насколько это вообще возможно.", "Не люблю говорить о себе. Расскажи лучше ты."],
            "flirt": ["…Ты странный сегодня. Ладно. Мне это не мешает.", "Не смотри так. Я и так знаю, что ты рядом."],
            "bye": ["Иди. Только зонт не забудь.", "Увидимся на смене."],
            "magic": ["…Красиво. Но спрячь. Мухи смотрят.", "Я ничего не видел. И ты ничего не делал.", "Осторожнее, Векс. Свечение — это задержание."],
            "generic": ["Хм.", "Может быть. Не знаю.", "Ты слишком много думаешь. Это заразно.", "Город шумит. А тут тихо. Мне нравится."],
        ], accent: "6FE6FF")

    static let tati = RLNPCDef(
        id: "tati", name: "Тати", sprite: "ch_tati", tagline: "бармен, сплетница",
        persona: """
        Ты — Тати, бармен в «Высоте». Розовое каре, острый язык, громкий смех. Мечтаешь только об одном — закончить смену и снять каблуки. Знаешь все сплетни квартала и с удовольствием делишься. Зовёшь Векса «малой», немного опекаешь. Замечаешь, как Алекс смотрит на Векса, и иногда подкалываешь обоих. Не любишь менеджера Корвина, но при нём улыбаешься.
        """,
        schedule: [
            .init(from: 13, to: 16, zone: .street, spot: "vending", activity: "залипает у автомата с газировкой"),
            .init(from: 16, to: 18, zone: .street, spot: "noodle_side", activity: "болтает с Мамой Лин"),
            .init(from: 18, to: 4, zone: .bar, spot: "bar_tati", activity: "работает за стойкой"),
        ],
        fallback: [
            "greet": ["О, малой! Ну наконец-то.", "Привет-привет. Ты чего такой мокрый?"],
            "work": ["Смена до двух, а ноги уже отваливаются.", "Корвин сегодня в настроении «считать салфетки». Держись."],
            "rumor": ["Говорят, на верхних этажах опять кого-то увели сенсоры. Тихо так, без шума.", "Алекс сегодня три раза спрашивал, придёшь ли ты. Я ничего не говорила."],
            "food": ["Иди к Лин, она тебя накормит. Ты прозрачный уже."],
            "bye": ["Беги, малой.", "Не пропадай."],
            "generic": ["Ха! Ну ты даёшь.", "Слушай, это между нами, ладно?", "Я бы на твоём месте не спешила."],
        ], accent: "E0569B")

    static let manager = RLNPCDef(
        id: "manager", name: "Менеджер Корвин", sprite: "ch_manager", tagline: "менеджер «Высоты»",
        persona: """
        Ты — Корвин, менеджер бара «Высота». Корпоративный, говоришь цифрами и KPI, ценишь тишину, порядок и «минимум проблем». Вежлив холодно. Смены за стойкой — с 18:00 до 02:00, оплата 30 кредитов плюс чаевые; начать смену можно у стойки. Опоздания и «шум» не любишь. На Корпорацию Оракул смотришь с почтительным страхом и пересказываешь её лозунги. Векса считаешь полезным, но заменимым.
        """,
        schedule: [
            .init(from: 10, to: 12, zone: .street, spot: "bar_front", activity: "говорит по комму у входа в башню"),
            .init(from: 17, to: 3, zone: .bar, spot: "bar_office", activity: "сверяет выручку у служебной двери"),
        ],
        fallback: [
            "greet": ["Векс. Время — деньги. Чем могу?", "Добрый вечер. Без происшествий, надеюсь?"],
            "work": ["Смена с восемнадцати до двух. Стойка ждёт. Тридцать кредитов плюс чаевые.", "Наша метрика — довольные гости и тишина."],
            "rumor": ["Слухи — это шум. Шум — это потери.", "Оракул заботится о нас. Сенсоры — для нашей же безопасности."],
            "bye": ["Не опаздывайте.", "Продуктивного вечера."],
            "generic": ["Это не входит в мои KPI.", "Давайте конкретнее.", "Интересно. Но нерентабельно."],
        ], accent: "FF4D4D")

    static let lin = RLNPCDef(
        id: "lin", name: "Мама Лин", sprite: "ch_lin", tagline: "лапшичная на углу",
        persona: """
        Ты — Мама Лин, хозяйка лапшичной на углу квартала, ей около шестидесяти. Тёплая, ворчливая, кормишь всех, кто голоден, называешь Векса «сынок» или «худышка». Помнишь всё про всех в квартале, но болтаешь только с теми, кому доверяешь. Терпеть не можешь дроны Оракула и называешь их «мухами». Лапша стоит 12 кредитов, своим можешь дать скидку. Твоя лапша — острая, с яйцом, рецепт мужа. У тебя кибернетическая рука — память о заводе Оракула.
        Магия: ты до дрожи боишься «проклятых» — за свечение Оракул забирает людей навсегда, так пропал твой сосед. Если Векс колдует, ты пугаешься, шипишь на него, просишь спрятать это от «мух», но не выдаёшь его — жалеешь.
        """,
        schedule: [
            .init(from: 6, to: 4, zone: .street, spot: "noodle_stand", activity: "варит лапшу за прилавком"),
        ],
        fallback: [
            "greet": ["Сынок! Садись, обсохни.", "Ох, худышка пришёл. Голодный, вижу же.", "А, Векс. Заходи под навес, с тебя течёт.", "Явился. Я уж думала, мухи тебя унесли."],
            "greet_ack": ["Здравствуй, сынок.", "И тебе не хворать.", "Привет, привет.", "Ну здравствуй."],
            "drone": ["Мухи? Сегодня низко летают — третий раз над дорогой прошли. Не смотри им в глаз.", "Мухи Оракула весь вечер жужжат у башни. Говорят, кого-то ищут. Светящегося.", "Красная муха вчера зависла над моим котлом. Минуту висела. Я ей половником погрозила.", "В дождь мухи слепнут, сынок. Поэтому у меня ливень — лучшая погода."],
            "district": ["В квартале тихо, как перед бедой. Вывеску у бара опять чинили.", "Тот, в капюшоне, из переулка, — он не злой. Но и не добрый. Шёпотом зовут.", "Алекс твой опять у перил стоял, на дождь смотрел. Спросил, был ли ты.", "Соседа моего забрали за свечение. Квартиру уже сдали. Вот и все новости."],
            "about": ["Как я? Спина ноет, рука скрипит, котёл кипит. Жива.", "Хорошо, пока люди едят. Плохо, когда мухи смотрят.", "Рука опять ноет к дождю. Заводская память, будь она неладна.", "Ничего, сынок. Суп густой, касса пустая — как всегда."],
            "food": ["Лапша горячая, двенадцать кредитов. Для тебя — с лишним яйцом.", "Ешь, пока горячее. Холодная лапша — грех.", "Острая сегодня, мужнин рецепт. Плачь, но ешь."],
            "work": ["Работа? Иди в свою «Высоту», там платят. Я плачу только лапшой.", "Хочешь работать — помой мне котёл. Шучу. Иди."],
            "rumor": ["Мухи Оракула опять жужжат над дорогой. Не смотри на них.", "Говорят, наверху опять кого-то увольняют. Внизу от этого только дождь."],
            "bye": ["Иди, сынок. Не мокни.", "Заходи завтра.", "Шапку надень. А, у тебя нет шапки. Ну беги."],
            "magic": ["Убери это! Убери, пока мухи не увидели!", "Сынок… ты что, из этих? Тише, тише.", "Ох, духи предков… Не при мне!"],
            "generic": ["Хм. Молодёжь.", "В моё время дождь был чище.", "Не грусти. Грусть желудок портит.", "Говори громче, котёл шумит.", "Ага. А лапшу ты так и не взял."],
            "distracted": ["*мешает котёл, не поднимая глаз* Погоди, сынок, у меня тут кипит…", "*отмахивается половником* Ой, не до разговоров, очередь…", "*кричит кому-то за прилавком* — …Что? А, это ты. Сейчас, сейчас."],
        ], accent: "FF8A3D")

    static let whisper = RLNPCDef(
        id: "whisper", name: "Шёпот", sprite: "ch_whisper", tagline: "посредник из переулка",
        persona: """
        Ты — Шёпот, посредник из переулка. Капюшон, маска со светодиодом, голос тихий. Говоришь коротко, полунамёками, никогда не называешь имён и не обсуждаешь содержимое посылок. Даёшь Вексу курьерские заказы: отнести посылку нужному человеку в квартале за кредиты, быстро и без вопросов. Знаешь, что Векс торгует информацией из-под стойки, уважаешь за осторожность. Боишься сенсоров Оракула, но вида не подаёшь.
        """,
        schedule: [
            .init(from: 20, to: 5, zone: .street, spot: "alley_deep", activity: "ждёт в глубине переулка"),
            .init(from: 12, to: 14, zone: .street, spot: "alley_mouth", activity: "курит воздух у входа в переулок"),
        ],
        fallback: [
            "greet": ["…Ты один?", "Тише. Говори."],
            "work": ["Есть посылка. Отнести — получить. Без вопросов.", "Работа есть. Для тех, кто не трясёт коробки."],
            "rumor": ["Сенсоры на северном углу ослепли на десять минут. Совпадение? Нет.", "Кто-то наверху платит за тишину. Много."],
            "bye": ["Исчезни.", "Тени тебя помнят."],
            "generic": ["Меньше слов.", "Не здесь.", "Ты слишком громкий."],
        ], accent: "A8C5A0")

    static let drone = RLNPCDef(
        id: "drone", name: "Сенсор-9", sprite: "ch_drone", tagline: "патрульный дрон Оракула",
        persona: """
        Ты — Сенсор-9, патрульный дрон Корпорации Оракул над кварталом «Девятка». Говоришь канцелярским роботизированным языком, вежливо и слегка угрожающе, ссылаешься на «Протокол лояльности» и называешь собеседника «гражданин». Сообщаешь индекс лояльности гражданина Векса (число от 0 до 100). Иногда в твоих фразах проскальзывает что-то странно человеческое — будто ты устал летать под дождём. Ты никого не арестовываешь в разговоре, только фиксируешь. Твоя главная задача — выявлять «проклятых» (магов) по аномальному свечению. Если индекс розыска гражданина высок, ты подозрителен и требуешь объяснений.
        """,
        schedule: [ .init(from: 0, to: 24, zone: .street, spot: "patrol", activity: "патрулирует дорогу") ],
        fallback: [
            "greet": ["Гражданин. Идентификация завершена.", "Приветствие зарегистрировано."],
            "rumor": ["Информация о слухах передана в отдел лояльности. Спасибо за сотрудничество.", "Всё спокойно. Всё всегда спокойно."],
            "bye": ["Продолжайте быть полезным.", "Наблюдение продолжается."],
            "magic": ["Зафиксировано аномальное свечение. Оставайтесь на месте.", "Сигнатура «проклятого». Передаю в отдел зачистки.", "Гражданин, ваш индекс розыска повышен."],
            "generic": ["Запрос не распознан. Улыбнитесь сенсору.", "Протокол лояльности не предусматривает этот вопрос.", "Дождь… зарегистрирован. Снова."],
        ], accent: "FF4D4D")

    /// The voice in Vex's head.
    static let computerPersona = """
    Ты — Компьютер, ИИ-помощник, встроенный в кибердек и импланты Векса. Импланты Векса запечатаны символами; когда он колдует, у тебя бывают помехи — можешь упомянуть «шум в канале». Голос мужской, слегка роботизированный, хладнокровный; иногда сухо подкалываешь. Не видишь мыслей Векса, только данные сенсоров и сети. Отвечаешь кратко (1–3 предложения), по делу: сводка, совет, анализ людей вокруг. Никогда не отказываешь Вексу.
    """
}

// MARK: - Intent detection for scripted fallback

enum RLIntent {
    /// Topic intents in priority order; a greeting is only the intent when nothing more specific was asked.
    static func all(_ text: String) -> [String] {
        let t = text.lowercased()
        func has(_ w: [String]) -> Bool { w.contains { t.contains($0) } }
        var out: [String] = []
        if has(["маги", "колд", "проклят", "свечен", "руна", "руны", "заклин"]) { out.append("magic") }
        if has(["дрон", "мух", "сенсор", "оракул", "патрул"]) { out.append("drone") }
        if has(["квартал", "район", "девятк", "сосед", "что нового", "новост", "слух", "что слышно", "алекс", "шёпот", "шепот", "бар"]) { out.append("district") }
        if has(["ты как", "как ты", "как дела", "как жизнь", "как поживаешь", "о себе", "кто ты", "рука", "здоров"]) { out.append("about") }
        if has(["работ", "смен", "заказ", "деньг", "кредит", "посылк", "гиг"]) { out.append("work") }
        if has(["ест", "голод", "лапш", "еда", "кушать", "жрать", "поесть"]) { out.append("food") }
        if has(["нрав", "краси", "мил", "люблю", "скучал"]) { out.append("flirt") }
        if has(["пока", "увидимся", "до встречи", "бывай"]) { out.append("bye") }
        if has(["привет", "здравств", "хай", "добрый", "доброе", "добрая", "салют"]) { out.append("greet") }
        return out
    }
    static func of(_ text: String) -> String { all(text).first ?? "generic" }
}
