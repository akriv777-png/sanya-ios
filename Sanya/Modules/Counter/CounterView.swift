// CounterView.swift — minimal Счётчик module (Plan B)
// Sanya/Modules/Counter/CounterView.swift

import SwiftUI
import Combine

// MARK: - CounterItem Model

struct CounterRecord: Codable {
    var dateString: String // YYYY-MM-DD
    var energyCount: Int
    var snusCount: Int
}

// MARK: - CounterStore

final class CounterStore: ObservableObject {
    static let shared = CounterStore()

    @Published var energyToday: Int = 0
    @Published var snusToday: Int = 0
    @Published var history: [CounterRecord] = []

    let energyLimit: Int = 2
    let snusLimit: Int = 5

    private let saveKey = "sanya_counter_records_v1"
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private init() {
        load()
    }

    private var todayString: String {
        dayFormatter.string(from: Date())
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let list = try? JSONDecoder().decode([CounterRecord].self, from: data) {
            history = list
        }
        let key = todayString
        if let current = history.first(where: { $0.dateString == key }) {
            energyToday = current.energyCount
            snusToday = current.snusCount
        } else {
            energyToday = 0
            snusToday = 0
        }
    }

    private func save() {
        let key = todayString
        if let idx = history.firstIndex(where: { $0.dateString == key }) {
            history[idx].energyCount = energyToday
            history[idx].snusCount = snusToday
        } else {
            history.append(CounterRecord(dateString: key, energyCount: energyToday, snusCount: snusToday))
        }
        // Keep last 14 days
        if history.count > 14 {
            history = Array(history.suffix(14))
        }
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    // MARK: - Actions

    func addEnergy() {
        Haptics.tap()
        energyToday += 1
        save()
        EventBus.shared.emit(.counterAdded(kind: "energy", today: energyToday, limit: energyLimit))
    }

    func minusEnergy() {
        guard energyToday > 0 else { return }
        energyToday -= 1
        save()
    }

    func addSnus() {
        Haptics.tap()
        snusToday += 1
        save()
        EventBus.shared.emit(.counterAdded(kind: "snus", today: snusToday, limit: snusLimit))
    }

    func minusSnus() {
        guard snusToday > 0 else { return }
        snusToday -= 1
        save()
    }

    // MARK: - 7-day values for mini bars

    func past7DaysValues(isEnergy: Bool) -> [(label: String, value: Int, limit: Int)] {
        let cal = Calendar.current
        var result: [(label: String, value: Int, limit: Int)] = []
        let weekdaySymbols = ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"]

        for dayOffset in (0..<7).reversed() {
            guard let date = cal.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let dateKey = dayFormatter.string(from: date)
            let weekday = cal.component(.weekday, from: date) - 1
            let label = weekdaySymbols[max(0, min(6, weekday))]

            let val: Int
            if dateKey == todayString {
                val = isEnergy ? energyToday : snusToday
            } else if let found = history.first(where: { $0.dateString == dateKey }) {
                val = isEnergy ? found.energyCount : found.snusCount
            } else {
                val = 0
            }
            result.append((label: label, value: val, limit: isEnergy ? energyLimit : snusLimit))
        }
        return result
    }
}

// MARK: - CounterView

struct CounterView: View {
    @ObservedObject private var store = CounterStore.shared

    var body: some View {
        ZStack {
            AtmosphereBackground()
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    energyCard
                    snusCard
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .navigationTitle("Счётчик")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Energy Card

    private var energyCard: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: "bolt.circle.fill")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(DS.Color.ember)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Энергетики")
                            .font(DS.Font.ui(17, weight: .semibold))
                            .foregroundStyle(DS.Color.ink)
                        Text("банка 250–500 мл")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.mute)
                    }
                }
                Spacer()
                Text("норма \(store.energyLimit)")
                    .font(DS.Font.caption)
                    .foregroundStyle(store.energyToday > store.energyLimit ? DS.Color.danger : DS.Color.ember2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        (store.energyToday > store.energyLimit ? DS.Color.danger : DS.Color.ember).opacity(0.18),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule().stroke(
                            (store.energyToday > store.energyLimit ? DS.Color.danger : DS.Color.ember).opacity(0.4),
                            lineWidth: 1
                        )
                    )
            }

            // Number & +/-
            HStack {
                IconButton(systemName: "minus", tint: DS.Color.ink, size: 52) {
                    store.minusEnergy()
                }
                .accessibilityIdentifier("counter_minus_energy")

                Spacer()

                VStack(spacing: 2) {
                    Text("\(store.energyToday)")
                        .font(DS.Font.display(68))
                        .foregroundStyle(store.energyToday > store.energyLimit ? DS.Color.danger : DS.Color.ember2)
                    Text("сегодня · \(store.energyToday * 250) мл")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.mute)
                }

                Spacer()

                Button {
                    store.addEnergy()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .bold))
                        .frame(width: 52, height: 52)
                        .background(DS.Color.ember, in: Circle())
                        .foregroundStyle(Color(hex: "180F08"))
                }
                .accessibilityIdentifier("counter_plus_energy")
            }

            // 7-day mini bars
            VStack(spacing: 6) {
                let days = store.past7DaysValues(isEnergy: true)
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(days.enumerated()), id: \.offset) { idx, item in
                        VStack(spacing: 4) {
                            let maxH: CGFloat = 64
                            let heightRatio = min(1.0, CGFloat(item.value) / CGFloat(max(1, item.limit * 2)))
                            let isOver = item.value > item.limit
                            let barColor = isOver ? DS.Color.danger : (idx == days.count - 1 ? DS.Color.ember2 : DS.Color.mute.opacity(0.5))

                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(barColor)
                                .frame(height: max(4, maxH * heightRatio))

                            Text(item.label)
                                .font(DS.Font.caption)
                                .foregroundStyle(idx == days.count - 1 ? DS.Color.ember2 : DS.Color.dim)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 80)
            }
        }
        .glassCard()
    }

    // MARK: - Snus Card

    private var snusCard: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: "leaf.circle.fill")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(DS.Color.sage)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Снюс")
                            .font(DS.Font.ui(17, weight: .semibold))
                            .foregroundStyle(DS.Color.ink)
                        Text("пакетики")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.mute)
                    }
                }
                Spacer()
                Text("цель ≤ \(store.snusLimit)")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.sage)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(DS.Color.sage.opacity(0.18), in: Capsule())
                    .overlay(Capsule().stroke(DS.Color.sage.opacity(0.4), lineWidth: 1))
            }

            // Number & +/-
            HStack {
                IconButton(systemName: "minus", tint: DS.Color.ink, size: 52) {
                    store.minusSnus()
                }

                Spacer()

                VStack(spacing: 2) {
                    Text("\(store.snusToday)")
                        .font(DS.Font.display(68))
                        .foregroundStyle(DS.Color.sage)
                    Text("сегодня")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.mute)
                }

                Spacer()

                Button {
                    store.addSnus()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .bold))
                        .frame(width: 52, height: 52)
                        .background(DS.Color.sage, in: Circle())
                        .foregroundStyle(Color(hex: "18221B"))
                }
                .accessibilityIdentifier("counter_plus_snus")
            }

            // 7-day mini bars
            VStack(spacing: 6) {
                let days = store.past7DaysValues(isEnergy: false)
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(days.enumerated()), id: \.offset) { idx, item in
                        VStack(spacing: 4) {
                            let maxH: CGFloat = 64
                            let heightRatio = min(1.0, CGFloat(item.value) / CGFloat(max(1, item.limit * 2)))
                            let isOver = item.value > item.limit
                            let barColor = isOver ? DS.Color.danger : (idx == days.count - 1 ? DS.Color.sage : DS.Color.mute.opacity(0.5))

                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(barColor)
                                .frame(height: max(4, maxH * heightRatio))

                            Text(item.label)
                                .font(DS.Font.caption)
                                .foregroundStyle(idx == days.count - 1 ? DS.Color.sage : DS.Color.dim)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 80)
            }
        }
        .glassCard()
    }
}
