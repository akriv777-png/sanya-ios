import SwiftUI
import Combine

enum ModuleID: String, CaseIterable, Identifiable, Hashable {
    case assistant, shifts, book, timers, player
    case pet                                                     // placeholder — section C
    case vex, counter, vault, piggy, rust, ml,
         weather, scanner, diary, wardrobe, webapps, home, games
    var id: String { rawValue }
}

struct ModuleInfo: Identifiable {
    let id: ModuleID
    let emoji: String
    let title: String
    let tint: String
    let wave: String
    let blurb: String
    /// A module is "ready" when wave <= "v0.2" and explicitly listed here.
    var ready: Bool { readyIDs.contains(id) }
}

private let readyIDs: Set<ModuleID> = [.assistant, .shifts, .book, .timers, .player, .counter, .pet]

enum Modules {
    static let all: [ModuleInfo] = [
        .init(id: .assistant, emoji: "🗣",  title: "Саня",           tint: "8A5CFF", wave: "v0.1", blurb: "Голосовой ассистент: чат, голос, команды модулям"),
        .init(id: .shifts,    emoji: "🍟",  title: "Смены",          tint: "FFB020", wave: "v0.1", blurb: "График из скринов Orquest, часы, зарплата, напоминания"),
        .init(id: .book,      emoji: "📖",  title: "Книга Мастера",  tint: "C0392B", wave: "v0.1", blurb: "Твоя DnD-книга внутри приложения"),
        .init(id: .timers,    emoji: "⏱",  title: "Таймеры",        tint: "FF9F0A", wave: "v0.1", blurb: "Помодоро и таймеры на острове"),
        .init(id: .player,    emoji: "🎧",  title: "Плеер",          tint: "FF3B5C", wave: "v0.1", blurb: "Офлайн-музыка без рекламы, эквалайзер на острове"),
        .init(id: .pet,       emoji: "🖤",  title: "Питомец",        tint: "A8C5A0", wave: "v0.2", blurb: "Тёмный питомец «Шиза» — ест, дремлет, злится"),
        .init(id: .counter,   emoji: "🥫",  title: "Счётчик",        tint: "64D2FF", wave: "v0.2", blurb: "Баночки, снюс и деньги на них — без нотаций"),
        .init(id: .vex,       emoji: "🤖",  title: "Векс-пульт",     tint: "30D158", wave: "v0.2", blurb: "Статус Векса, кто пишет, быстрые команды боту"),
        .init(id: .vault,     emoji: "🔐",  title: "Сейф",           tint: "8E8E93", wave: "v0.2", blurb: "Заметки и фото под Face ID, маскировка под калькулятор"),
        .init(id: .piggy,     emoji: "💶",  title: "Копилка",        tint: "34C759", wave: "v0.2", blurb: "Цели: пирсинг, рукав, шмот — заполняются по мере накоплений"),
        .init(id: .rust,      emoji: "🦀",  title: "Ржавый",         tint: "E8590C", wave: "v0.3", blurb: "Rust каждый день: задача, тест, стрик"),
        .init(id: .ml,        emoji: "⚔️",  title: "Mobile Legends", tint: "0A84FF", wave: "v0.4", blurb: "Сборки на Сесилиона, таймер баффов"),
        .init(id: .weather,   emoji: "🌦",  title: "Погода",         tint: "5AC8FA", wave: "v0.5", blurb: "Погода и «во сколько выходить»"),
        .init(id: .scanner,   emoji: "🧾",  title: "Сканер",         tint: "A2845E", wave: "v0.4", blurb: "Документы, nóminas, чеки — ИИ объяснит"),
        .init(id: .diary,     emoji: "📓",  title: "Дневник",        tint: "FF9500", wave: "v0.5", blurb: "Дневник голосом"),
        .init(id: .wardrobe,  emoji: "👕",  title: "Гардероб",       tint: "AC8E68", wave: "v0.6", blurb: "Шмот и образы"),
        .init(id: .webapps,   emoji: "🧩",  title: "Мини-приложения",tint: "66D4CF", wave: "v0.3", blurb: "Веб-модули, которые обновляются без пересборки"),
        .init(id: .home,      emoji: "🏠",  title: "Умный дом",      tint: "30B0C7", wave: "v0.6", blurb: "Свет и розетки через Дом"),
        .init(id: .games,     emoji: "🎮",  title: "Мини-игры",      tint: "FF375F", wave: "v0.6", blurb: "Игры на SpriteKit"),
    ]
    static var ready: [ModuleInfo] { all.filter { $0.ready } }
    static var soon:  [ModuleInfo] { all.filter { !$0.ready } }
    static func info(_ id: ModuleID) -> ModuleInfo { all.first { $0.id == id }! }
}

final class Router: ObservableObject {
    static let shared = Router()
    @Published var path: [ModuleID] = []
    func go(_ m: ModuleID) { path = [m] }
    func open(_ url: URL) {
        if AIClient.configure(from: url) { Haptics.success(); return }
        if let h = url.host, let m = ModuleID(rawValue: h) { go(m) }
    }
}

struct ModuleScreen: View {
    let id: ModuleID
    var body: some View {
        switch id {
        case .assistant: AssistantView()
        case .shifts:    ShiftsView()
        case .book:      BookView()
        case .timers:    TimersView()
        case .player:    PlayerView()
        case .counter:   CounterView()
        case .pet:       PetView()
        default:         ComingSoonView(info: Modules.info(id))
        }
    }
}

struct ComingSoonView: View {
    let info: ModuleInfo
    @State private var glow = false
    var body: some View {
        ZStack {
            AtmosphereBackground()
            VStack(spacing: 18) {
                Spacer()
                Text(info.emoji).font(.system(size: 90))
                    .scaleEffect(glow ? 1.08 : 0.95)
                    .shadow(color: SwiftUI.Color(hex: info.tint).opacity(0.8), radius: glow ? 30 : 10)
                Text(info.title)
                    .font(DS.Font.display(34))
                    .foregroundStyle(DS.Color.ink)
                Text(info.blurb)
                    .font(DS.Font.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(DS.Color.mute)
                    .padding(.horizontal, 30)
                Text("Будет в \(info.wave)")
                    .font(DS.Font.label)
                    .tracking(2)
                    .foregroundStyle(DS.Color.mute)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(SwiftUI.Color(hex: info.tint).opacity(0.2), in: Capsule())
                    .overlay(Capsule().stroke(SwiftUI.Color(hex: info.tint).opacity(0.4), lineWidth: 1))
                Spacer(); Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.6).repeatForever()) { glow = true } }
        .accessibilityIdentifier("coming_soon")
    }
}
