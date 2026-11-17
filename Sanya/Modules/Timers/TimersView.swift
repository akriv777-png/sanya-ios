import SwiftUI
import Combine

struct RunningTimer: Codable, Identifiable, Hashable {
    var id    = UUID()
    var title: String
    var start: Date
    var end:   Date
    var total: Double { max(1, end.timeIntervalSince(start)) }
}

final class TimerStore: ObservableObject {
    static let shared = TimerStore()
    @Published var running: [RunningTimer]  = [] { didSet { persist() } }
    @Published var history: [RunningTimer]  = [] { didSet { persist() } }

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
        EventBus.shared.emit(.timerStarted(minutes: Int(minutes)))
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
        for _ in done { EventBus.shared.emit(.timerDone) }
        refreshIsland()
    }

    private func refreshIsland() {
        guard let t = running.min(by: { $0.end < $1.end }) else {
            LiveActivityManager.shared.end(kind: "timer"); return
        }
        let petEmo = EmotionRegistry.baseSprite(for: PetEngine.shared.currentEmotion.id)
        LiveActivityManager.shared.start(kind: "timer", symbol: "timer", state: .init(
            title: t.title,
            subtitle: running.count > 1 ? "Ещё таймеров: \(running.count - 1)" : "До конца \(Fmt.time(t.end))",
            start: t.start, end: t.end, colorHex: "FF9F0A", isPlaying: true, progress: 0,
            petEmotion: petEmo,
            petSatiety: PetStore.shared.stats.satiety,
            petEnergy: PetStore.shared.stats.energy,
            petMood: PetStore.shared.stats.mood
        ))
    }

    private func persist() {
        guard !AppEnv.isUITest else { return }
        DiskStore.save(running, "timers.json")
        DiskStore.save(history, "timers_history.json")
    }
}

// MARK: - TimersView

struct TimersView: View {
    @ObservedObject var store = TimerStore.shared
    @State private var minutes: Double = 10
    @State private var title = ""
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        ZStack {
            AtmosphereBackground().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    // Active timers
                    if !store.running.isEmpty {
                        SectionHeader("Активные")
                        ForEach(store.running) { t in
                            RunningTimerCard(timer: t) { store.cancel(t) }
                        }
                    }

                    // Quick start grid
                    SectionHeader("Быстрый старт")
                    LazyVGrid(columns: cols, spacing: 10) {
                        ForEach(Array(store.presets.enumerated()), id: \.offset) { i, p in
                            Button { store.start(title: p.1, minutes: p.2) } label: {
                                VStack(spacing: 6) {
                                    Text(p.0).font(.system(size: 30))
                                    Text(p.1)
                                        .font(DS.Font.bodyMed)
                                        .foregroundStyle(DS.Color.ink)
                                    Text("\(Int(p.2)) мин")
                                        .font(DS.Font.caption)
                                        .foregroundStyle(DS.Color.mute)
                                }
                                .frame(maxWidth: .infinity, minHeight: 90)
                                .glassCard(radius: DS.Radius.tile, padding: 12)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("preset_\(i)")
                        }
                    }

                    // Custom timer
                    SectionHeader("Свой таймер")
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Название", text: $title)
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Color.ink)
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.Color.line, lineWidth: 1))

                        HStack {
                            Text("\(Int(minutes)) мин")
                                .font(DS.Font.display(28))
                                .foregroundStyle(DS.Color.ink)
                            Spacer()
                            Stepper("", value: $minutes, in: 1...240)
                                .labelsHidden()
                        }

                        Button {
                            store.start(title: title.isEmpty ? "Таймер" : title, minutes: minutes)
                            title = ""
                        } label: {
                            Label("Запустить", systemImage: "play.fill")
                                .font(DS.Font.bodyMed)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GlassButtonStyle(kind: .primary))
                    }
                    .glassCard()

                    // History
                    if !store.history.isEmpty {
                        SectionHeader("История")
                        ForEach(store.history.prefix(8)) { t in
                            HStack {
                                Text(t.title)
                                    .font(DS.Font.body).foregroundStyle(DS.Color.ink)
                                Spacer()
                                Text("\(Int(t.total / 60)) мин · \(Fmt.time(t.end))")
                                    .font(DS.Font.caption).foregroundStyle(DS.Color.mute)
                            }
                            .glassCard(radius: DS.Radius.small, padding: 10)
                        }
                    }

                    Text("Фокус-режим и будильники через «Команды» — в v0.3.")
                        .font(DS.Font.caption).foregroundStyle(DS.Color.dim)
                }
                .padding()
            }
        }
        .navigationTitle("Таймеры")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Таймеры").font(DS.Font.display(22)).foregroundStyle(DS.Color.ink)
            }
        }
        .onReceive(tick) { _ in store.sweep() }
    }
}

// MARK: - RunningTimerCard

struct RunningTimerCard: View {
    let timer:    RunningTimer
    let onCancel: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let p = min(1, max(0, ctx.date.timeIntervalSince(timer.start) / timer.total))
            HStack(spacing: 16) {
                // Ring
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: CGFloat(1 - p))
                        .stroke(
                            AngularGradient(colors: [DS.Color.sage, DS.Color.ember2, DS.Color.sage],
                                            center: .center),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Text(timerInterval: timer.start...max(timer.start, timer.end), countsDown: true)
                        .monospacedDigit()
                        .font(DS.Font.display(20))
                        .foregroundStyle(DS.Color.ink)
                }
                .frame(width: 90, height: 90)

                VStack(alignment: .leading, spacing: 6) {
                    Text(timer.title)
                        .font(DS.Font.display(22))
                        .foregroundStyle(DS.Color.ink)
                    Text("До \(Fmt.time(timer.end))")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.mute)
                    Button("Отменить", role: .destructive, action: onCancel)
                        .font(DS.Font.label)
                        .foregroundStyle(DS.Color.danger)
                }
                Spacer()
            }
            .glassCard()
        }
    }
}
