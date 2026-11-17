import SwiftUI
import PhotosUI

struct ShiftsView: View {
    @ObservedObject var store = ShiftStore.shared
    @State private var mode = 0
    @State private var anchor = Date()
    @State private var editing: Shift?
    @State private var photoItem: PhotosPickerItem?
    @State private var importResult: ImportResult?
    @State private var scanning = false

    private var interval: DateInterval {
        Fmt.cal.dateInterval(of: mode == 0 ? .weekOfYear : .month, for: anchor) ?? DateInterval(start: anchor, duration: 7 * 86400)
    }

    var body: some View {
        let list = store.shifts(in: interval)
        let hours = list.reduce(0) { $0 + $1.hours }
        ScrollView {
            VStack(spacing: 16) {
                Picker("Вид", selection: $mode) {
                    Text("Неделя").tag(0)
                    Text("Месяц").tag(1)
                }
                .pickerStyle(.segmented)

                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(periodTitle).font(.headline)
                    Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }
                }
                .padding(.horizontal, 6)

                HStack(spacing: 12) {
                    stat("Смен", "\(list.count)", Theme.violet)
                    stat("Часов", String(format: "%.1f", hours), Theme.gold)
                    stat("≈ Заработок", Fmt.money(hours * store.rate), Color(hex: "30D158"))
                }

                if mode == 0 {
                    WeekView(interval: interval, shifts: list) { editing = $0 }
                } else {
                    MonthGrid(interval: interval, shifts: list) { day in
                        if let s = list.first(where: { Fmt.cal.isDate($0.start, inSameDayAs: day) }) { editing = s }
                        else { editing = newShift(on: day) }
                    }
                }

                if let next = store.nextShift {
                    Button { showOnIsland(next) } label: {
                        Label("Показать смену на острове", systemImage: "capsule.inset.filled")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.gold)
                    .accessibilityIdentifier("shift_island")
                }

                settings
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("🍟 Смены")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "photo.badge.plus")
                }
                .accessibilityIdentifier("shift_import")
                Button { editing = newShift(on: Date()) } label: { Image(systemName: "plus") }
                    .accessibilityIdentifier("shift_add")
            }
        }
        .sheet(item: $editing) { ShiftEditor(shift: $0) }
        .sheet(item: $importResult) { ImportReview(result: $0) }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            scan(item)
        }
        .overlay {
            if scanning {
                ProgressView("Читаю скрин…").padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var periodTitle: String {
        if mode == 1 { return Fmt.month(anchor) }
        let i = interval
        return "\(Fmt.day(i.start)) – \(Fmt.day(i.end.addingTimeInterval(-1)))"
    }

    private func shift(_ dir: Int) {
        anchor = Fmt.cal.date(byAdding: mode == 0 ? .weekOfYear : .month, value: dir, to: anchor) ?? anchor
    }

    private func stat(_ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.bold()).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Настройки").font(.headline)
            Stepper(value: $store.rate, in: 5...30, step: 0.25) {
                Text("Ставка: \(String(format: "%.2f", store.rate)) €/ч")
            }
            Picker("Напоминать за", selection: $store.remindMinutes) {
                Text("15 мин").tag(15); Text("30 мин").tag(30); Text("1 час").tag(60); Text("2 часа").tag(120)
            }
            Text("Скрин графика из Orquest → кнопка с фото сверху. Сейчас читает телефон (Vision OCR), ИИ-разбор на сервере — в v0.2.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }

    private func newShift(on day: Date) -> Shift {
        let start = Fmt.cal.date(bySettingHour: 17, minute: 0, second: 0, of: day) ?? day
        return Shift(start: start, end: start.addingTimeInterval(7 * 3600))
    }

    private func showOnIsland(_ s: Shift) {
        let now = Date()
        let ongoing = s.start <= now
        LiveActivityManager.shared.start(kind: "shift", symbol: "fork.knife", state: .init(
            title: ongoing ? "До конца смены" : "До начала смены",
            subtitle: "\(Fmt.time(s.start))–\(Fmt.time(s.end)) · \(s.note)",
            start: ongoing ? s.start : now, end: ongoing ? s.end : s.start,
            colorHex: "FFB020", isPlaying: true, progress: 0))
    }

    private func scan(_ item: PhotosPickerItem) {
        scanning = true
        Task {
            var lines: [String] = []
            if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                lines = await OCR.recognize(img)
            }
            let found = ShiftParser.parse(lines: lines)
            await MainActor.run {
                scanning = false
                photoItem = nil
                importResult = ImportResult(lines: lines, shifts: found)
            }
        }
    }
}

struct WeekView: View {
    let interval: DateInterval
    let shifts: [Shift]
    let onTap: (Shift) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<7, id: \.self) { i in
                let day = Fmt.cal.date(byAdding: .day, value: i, to: interval.start)!
                let dayShifts = shifts.filter { Fmt.cal.isDate($0.start, inSameDayAs: day) }
                let isToday = Fmt.cal.isDateInToday(day)
                HStack(spacing: 10) {
                    VStack(spacing: 0) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated).locale(Fmt.ru)).uppercased()).font(.caption2.bold())
                        Text(day.formatted(.dateTime.day().locale(Fmt.ru))).font(.title3.bold())
                    }
                    .frame(width: 44)
                    .foregroundStyle(isToday ? Theme.accent : .primary)

                    if dayShifts.isEmpty {
                        Text("Выходной").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(dayShifts) { s in
                                Button { onTap(s) } label: { ShiftBar(shift: s, day: day) }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(10)
                .background(isToday ? Theme.card2 : Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
}

/// Полоска смены на шкале 0–24 ч.
struct ShiftBar: View {
    let shift: Shift
    let day: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(Fmt.time(shift.start))–\(Fmt.time(shift.end))").font(.subheadline.bold())
                Text(shift.note).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(Fmt.hours(shift.hours)).font(.caption.bold()).foregroundStyle(Theme.gold)
            }
            GeometryReader { geo in
                let dayStart = Fmt.cal.startOfDay(for: day)
                let a = max(0, shift.start.timeIntervalSince(dayStart) / 86400)
                let b = min(1, shift.end.timeIntervalSince(dayStart) / 86400)
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08))
                    Capsule().fill(LinearGradient(colors: [Theme.gold, Theme.accent], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * CGFloat(b - a)))
                        .offset(x: geo.size.width * CGFloat(a))
                }
            }
            .frame(height: 6)
        }
    }
}

struct MonthGrid: View {
    let interval: DateInterval
    let shifts: [Shift]
    let onTap: (Date) -> Void
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let names = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

    var body: some View {
        let cal = Fmt.cal
        let first = interval.start
        let lead = (cal.component(.weekday, from: first) + 5) % 7
        let days = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        LazyVGrid(columns: cols, spacing: 6) {
            ForEach(names, id: \.self) { Text($0).font(.caption2.bold()).foregroundStyle(.secondary) }
            ForEach((-lead)..<0, id: \.self) { _ in Color.clear.frame(height: 48) }
            ForEach(0..<days, id: \.self) { i in
                let day = cal.date(byAdding: .day, value: i, to: first)!
                let h = shifts.filter { cal.isDate($0.start, inSameDayAs: day) }.reduce(0) { $0 + $1.hours }
                Button { onTap(day) } label: {
                    VStack(spacing: 2) {
                        Text("\(i + 1)").font(.subheadline.bold())
                        Text(h > 0 ? String(format: "%.0fч", h) : " ").font(.caption2).foregroundStyle(Theme.gold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(h > 0 ? Theme.gold.opacity(0.22) : Theme.card, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(cal.isDateInToday(day) ? Theme.accent : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ShiftEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ShiftStore.shared
    @State var shift: Shift

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Начало", selection: $shift.start)
                DatePicker("Конец", selection: $shift.end)
                TextField("Заметка (кухня, грилль…)", text: $shift.note)
                Section {
                    LabeledContent("Часы", value: Fmt.hours(shift.hours))
                    LabeledContent("≈ Заработок", value: Fmt.money(shift.hours * store.rate))
                }
                if store.contains(shift.id) {
                    Button("Удалить смену", role: .destructive) { store.delete(shift.id); dismiss() }
                }
            }
            .navigationTitle(store.contains(shift.id) ? "Смена" : "Новая смена")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { store.upsert(shift); dismiss() }.accessibilityIdentifier("shift_save")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct ImportReview: View {
    @Environment(\.dismiss) private var dismiss
    @State var result: ImportResult

    var body: some View {
        NavigationStack {
            List {
                Section(result.shifts.isEmpty ? "Смен не нашёл" : "Нашёл смен: \(result.shifts.count)") {
                    ForEach(result.shifts) { s in
                        VStack(alignment: .leading) {
                            Text(Fmt.day(s.start)).font(.headline)
                            Text("\(Fmt.time(s.start))–\(Fmt.time(s.end)) · \(Fmt.hours(s.hours))").foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { result.shifts.remove(atOffsets: $0) }
                }
                Section("Распознанный текст") {
                    Text(result.lines.isEmpty ? "—" : result.lines.joined(separator: "\n")).font(.caption.monospaced())
                }
            }
            .navigationTitle("Импорт со скрина")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") { ShiftStore.shared.addMany(result.shifts); dismiss() }.disabled(result.shifts.isEmpty)
                }
            }
        }
    }
}
