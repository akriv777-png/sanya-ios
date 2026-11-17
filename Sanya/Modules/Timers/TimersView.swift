import SwiftUI
import Combine

struct RunningTimer: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var start: Date
    var end: Date
    var total: Double { max(1, end.timeIntervalSince(start)) }
}

final class TimerStore: ObservableObject {
    static let shared = TimerStore()
    @Published var running: [RunningTimer] = [] { didSet { persist() } }
    @Published var history: [RunningTimer] = [] { didSet { persist() } }

    let presets: [(String, String, Double)] = [
        ("🍅", "Помодоро", 25), ("☕️", "Перерыв", 5), ("🍜", "Лапша", 3),
        ("🧺", "Стирка", 45), ("😴", "Поспать", 20), ("⚡️", "Тест", 1),
    ]

    init() {
        if !AppEnv.isUITest {
            running = DiskStore.load([RunningTimer].self, "timers.json") ?? []
            history = DiskStore.load([RunningTimer].self, "timers_history.json") ?? []
        }
        sweep()
    }

    func start(title: String, minutes: Double) {
        let now = Date()
        let t = RunningTimer(title: title, start: now, end: now.addingTimeInterval(minutes * 60))
        running.append(t)
        Notifier.schedule(id: "timer-\(t.id.uuidString)", title: "⏱ \(title)", body: "Время вышло!", at: t.end)
        refreshIsland()
    }

    func cancel(_ t: RunningTimer) {
        running.removeAll { $0.id == t.id }
        Notifier.cancel(ids: ["timer-\(t.id.uuidString)"])
        refreshIsland()
    }

    func sweep() {
        let now = Date()
        let done = running.filter { $0.end <= now }
        guard !done.isEmpty else { return }
        running.removeAll { $0.end <= now }
        history = Array((done + history).prefix(30))
        refreshIsland()
    }

    /// На острове — ближайший к окончанию таймер.
    private func refreshIsland() {
        guard let t = running.min(by: { $0.end < $1.end }) else {
            LiveActivityManager.shared.end(kind: "timer"); return
        }
        LiveActivityManager.shared.start(kind: "timer", symbol: "timer", state: .init(
            title: t.title, subtitle: running.count > 1 ? "Ещё таймеров: \(running.count - 1)" : "До конца \(Fmt.time(t.end))",
            start: t.start, end: t.end, colorHex: "FF9F0A", isPlaying: true, progress: 0))
    }

    private func persist() {
        guard !AppEnv.isUITest else { return }
        DiskStore.save(running, "timers.json")
        DiskStore.save(history, "timers_history.json")
    }
}

struct TimersView: View {
    @ObservedObject var store = TimerStore.shared
    @State private var minutes: Double = 10
    @State private var title = ""
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !store.running.isEmpty {
                    ForEach(store.running) { t in RunningTimerCard(timer: t) { store.cancel(t) } }
                }
                Text("Быстрый старт").font(.headline)
                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(Array(store.presets.enumerated()), id: \.offset) { i, p in
                        Button { store.start(title: p.1, minutes: p.2) } label: {
                            VStack(spacing: 4) {
                                Text(p.0).font(.title)
                                Text(p.1).font(.footnote.bold())
                                Text("\(Int(p.2)) мин").font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 90)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("preset_\(i)")
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Свой таймер").font(.headline)
                    TextField("Название", text: $title).textFieldStyle(.roundedBorder)
                    Stepper("\(Int(minutes)) мин", value: $minutes, in: 1...240)
                    Button {
                        store.start(title: title.isEmpty ? "Таймер" : title, minutes: minutes); title = ""
                    } label: { Label("Запустить", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(Theme.gold)
                }
                .card()
                if !store.history.isEmpty {
                    Text("История").font(.headline)
                    ForEach(store.history.prefix(8)) { t in
                        HStack {
                            Text(t.title)
                            Spacer()
                            Text("\(Int(t.total / 60)) мин · \(Fmt.day(t.end)) \(Fmt.time(t.end))").font(.caption).foregroundStyle(.secondary)
                        }
                        .card()
                    }
                }
                Text("Фокус-режим и будильники через «Команды» — в v0.2.").font(.caption).foregroundStyle(.secondary)
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("⏱ Таймеры")
        .onReceive(tick) { _ in store.sweep() }
    }
}

struct RunningTimerCard: View {
    let timer: RunningTimer
    let onCancel: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let p = min(1, max(0, ctx.date.timeIntervalSince(timer.start) / timer.total))
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(.white.opacity(0.1), lineWidth: 10)
                    Circle().trim(from: 0, to: CGFloat(1 - p))
                        .stroke(AngularGradient(colors: [Theme.gold, Theme.accent, Theme.gold], center: .center),
                                style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(timerInterval: timer.start...max(timer.start, timer.end), countsDown: true)
                        .monospacedDigit().font(.headline)
                }
                .frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 6) {
                    Text(timer.title).font(.title3.bold())
                    Text("До \(Fmt.time(timer.end))").foregroundStyle(.secondary)
                    Button("Отменить", role: .destructive, action: onCancel).font(.footnote)
                }
                Spacer()
            }
            .card()
        }
    }
}
