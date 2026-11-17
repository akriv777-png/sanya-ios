import SwiftUI
import PhotosUI

struct ShiftsView: View {
    @ObservedObject var store   = ShiftStore.shared
    @State private var mode     = 0
    @State private var anchor   = Date()
    @State private var editing: Shift?
    @State private var photoItem: PhotosPickerItem?
    @State private var importResult: ImportResult?
    @State private var scanning = false

    private var interval: DateInterval {
        Fmt.cal.dateInterval(of: mode == 0 ? .weekOfYear : .month, for: anchor) ?? DateInterval(start: anchor, duration: 7 * 86400)
    }

    var body: some View {
        let list  = store.shifts(in: interval)
        let hours = list.reduce(0) { $0 + $1.hours }

        ZStack {
            AtmosphereBackground().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Period picker
                    HStack(spacing: 0) {
                        ForEach(["Неделя", "Месяц"], id: \.self) { label in
                            let sel = (label == "Неделя") ? mode == 0 : mode == 1
                            Button {
                                withAnimation { mode = label == "Неделя" ? 0 : 1 }
                            } label: {
                                Text(label)
                                    .font(DS.Font.bodyMed)
                                    .foregroundStyle(sel ? Color(hex: "18221B") : DS.Color.mute)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 38)
                                    .background(sel ? DS.Color.sage : Color.clear, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(DS.Color.line, lineWidth: 1))

                    // Nav row
                    HStack {
                        IconButton(systemName: "chevron.left", tint: DS.Color.mute, size: 36) { shift(-1) }
                        Spacer()
                        Text(periodTitle)
                            .font(DS.Font.display(22))
                            .foregroundStyle(DS.Color.ink)
                        Spacer()
                        IconButton(systemName: "chevron.right", tint: DS.Color.mute, size: 36) { shift(1) }
                    }

                    // Stats strip
                    HStack(spacing: 10) {
                        statCell("Смены",     "\(list.count)",                    DS.Color.sage)
                        statCell("Часов",     String(format: "%.1f", hours),      DS.Color.ember2)
                        statCell("Заработок", Fmt.money(hours * store.rate),     Color(hex: "30D158"))
                    }

                    // Calendar body
                    if mode == 0 {
                        WeekView(interval: interval, shifts: list) { editing = $0 }
                    } else {
                        MonthGrid(interval: interval, shifts: list) { day in
                            if let s = list.first(where: { Fmt.cal.isDate($0.start, inSameDayAs: day) }) { editing = s }
                            else { editing = newShift(on: day) }
                        }
                    }

                    // Island button
                    if let next = store.nextShift {
                        Button { store.showOnIsland(next) } label: {
                            Label("Показать смену на острове", systemImage: "capsule.inset.filled")
                                .font(DS.Font.bodyMed)
                                .foregroundStyle(DS.Color.ink)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GlassButtonStyle(kind: .secondary))
                        .accessibilityIdentifier("shift_island")
                    }

                    // Settings card
                    settingsCard
                }
                .padding()
            }
            .overlay {
                if scanning {
                    ProgressView("Читаю скрин…")
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .navigationTitle("Смены")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Смены").font(DS.Font.display(22)).foregroundStyle(DS.Color.ink)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "photo.badge.plus").foregroundStyle(DS.Color.ink)
                }
                .accessibilityIdentifier("shift_import")
                Button {
                    editing = newShift(on: Date())
                } label: {
                    Image(systemName: "plus").foregroundStyle(DS.Color.ink)
                }
                .accessibilityIdentifier("shift_add")
            }
        }
        .sheet(item: $editing)      { ShiftEditor(shift: $0) }
        .sheet(item: $importResult) { ImportReview(result: $0) }
        .onChange(of: photoItem) { _, item in guard let item else { return }; scan(item) }
    }

    // MARK: – Stats

    private func statCell(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(DS.Font.display(26))
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label)
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.mute)
        }
        .frame(maxWidth: .infinity)
        .glassCard(radius: DS.Radius.small, padding: 12)
    }

    // MARK: – Period

    private var periodTitle: String {
        if mode == 1 { return Fmt.month(anchor) }
        let i = interval
        return "\(Fmt.day(i.start)) – \(Fmt.day(i.end.addingTimeInterval(-1)))"
    }

    private func shift(_ dir: Int) {
        anchor = Fmt.cal.date(byAdding: mode == 0 ? .weekOfYear : .month, value: dir, to: anchor) ?? anchor
    }

    private func newShift(on day: Date) -> Shift {
        let start = Fmt.cal.date(bySettingHour: 17, minute: 0, second: 0, of: day) ?? day
        return Shift(start: start, end: start.addingTimeInterval(7 * 3600))
    }

    // MARK: – Settings card

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Настройки")
            Stepper(value: $store.rate, in: 5...30, step: 0.25) {
                HStack {
                    Text("Ставка").font(DS.Font.body).foregroundStyle(DS.Color.ink)
                    Spacer()
                    Text(String(format: "%.2f €/ч", store.rate))
                        .font(DS.Font.bodyMed).foregroundStyle(DS.Color.ember2)
                }
            }
            Picker("Напоминать за", selection: $store.remindMinutes) {
                Text("15 мин").tag(15)
                Text("30 мин").tag(30)
                Text("1 час").tag(60)
                Text("2 часа").tag(120)
            }
            .pickerStyle(.segmented)
            Text("Скрин графика из Orquest → кнопка с фото сверху.")
                .font(DS.Font.caption).foregroundStyle(DS.Color.dim)
        }
        .glassCard()
    }

    // MARK: – OCR scan

    private func scan(_ item: PhotosPickerItem) {
        scanning = true
        Task {
            var lines: [String] = []
            if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                lines = await OCR.recognize(img)
            }
            var found = ShiftParser.parse(lines: lines)
            if let ai = await ShiftAIParser.parse(lines: lines), ai.count >= found.count { found = ai }
            await MainActor.run {
                scanning = false
                photoItem = nil
                importResult = ImportResult(lines: lines, shifts: found)
            }
        }
    }
}

// MARK: – WeekView

struct WeekView: View {
    let interval: DateInterval
    let shifts: [Shift]
    let onTap: (Shift) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<7, id: \.self) { i in
                let day      = Fmt.cal.date(byAdding: .day, value: i, to: interval.start)!
                let dayShifts = shifts.filter { Fmt.cal.isDate($0.start, inSameDayAs: day) }
                let isToday  = Fmt.cal.isDateInToday(day)
                HStack(spacing: 10) {
                    VStack(spacing: 0) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated).locale(Fmt.ru)).uppercased())
                            .font(DS.Font.caption).foregroundStyle(DS.Color.mute)
                        Text(day.formatted(.dateTime.day().locale(Fmt.ru)))
                            .font(DS.Font.display(22))
                            .foregroundStyle(isToday ? DS.Color.sage : DS.Color.ink)
                    }
                    .frame(width: 44)

                    if dayShifts.isEmpty {
                        Text("Выходной")
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Color.dim)
                        Spacer()
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(dayShifts) { s in
                                Button { onTap(s) } label: { ShiftBar(shift: s, day: day) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(isToday ? DS.Color.sage.opacity(0.08) : DS.Color.glass)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(isToday ? DS.Color.sage.opacity(0.3) : DS.Color.line, lineWidth: 1)
                        )
                }
            }
        }
    }
}

struct ShiftBar: View {
    let shift: Shift
    let day: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(Fmt.time(shift.start))–\(Fmt.time(shift.end))")
                    .font(DS.Font.display(18))
                    .foregroundStyle(DS.Color.ink)
                Text(shift.note)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.mute)
                Spacer()
                Text(Fmt.hours(shift.hours))
                    .font(DS.Font.label)
                    .foregroundStyle(DS.Color.ember2)
            }
            GeometryReader { geo in
                let dayStart = Fmt.cal.startOfDay(for: day)
                let a = max(0, shift.start.timeIntervalSince(dayStart) / 86400)
                let b = min(1, shift.end.timeIntervalSince(dayStart) / 86400)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [DS.Color.sage, DS.Color.ember2],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * CGFloat(b - a)))
                        .offset(x: geo.size.width * CGFloat(a))
                }
            }
            .frame(height: 5)
        }
    }
}

// MARK: – MonthGrid

struct MonthGrid: View {
    let interval: DateInterval
    let shifts: [Shift]
    let onTap: (Date) -> Void
    private let cols  = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let names = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

    var body: some View {
        let cal   = Fmt.cal
        let first = interval.start
        let lead  = (cal.component(.weekday, from: first) + 5) % 7
        let days  = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        LazyVGrid(columns: cols, spacing: 6) {
            ForEach(names, id: \.self) {
                Text($0).font(DS.Font.caption).foregroundStyle(DS.Color.mute)
            }
            ForEach((-lead)..<0, id: \.self) { _ in Color.clear.frame(height: 48) }
            ForEach(0..<days, id: \.self) { i in
                let day = cal.date(byAdding: .day, value: i, to: first)!
                let h   = shifts.filter { cal.isDate($0.start, inSameDayAs: day) }.reduce(0) { $0 + $1.hours }
                Button { onTap(day) } label: {
                    VStack(spacing: 2) {
                        Text("\(i + 1)")
                            .font(DS.Font.bodyMed)
                            .foregroundStyle(DS.Color.ink)
                        Text(h > 0 ? String(format: "%.0fч", h) : " ")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.ember2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(h > 0 ? DS.Color.sage.opacity(0.18) : Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(cal.isDateInToday(day) ? DS.Color.sage : DS.Color.line, lineWidth: cal.isDateInToday(day) ? 2 : 1)
                            )
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: – ShiftEditor

struct ShiftEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ShiftStore.shared
    @State var shift: Shift

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Начало", selection: $shift.start)
                DatePicker("Конец",  selection: $shift.end)
                TextField("Заметка (кухня, грилль…)", text: $shift.note)
                Section {
                    LabeledContent("Часы",        value: Fmt.hours(shift.hours))
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
                    Button("Сохранить") { store.upsert(shift); dismiss() }
                        .accessibilityIdentifier("shift_save")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: – ImportReview

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
                    Button("Добавить") { ShiftStore.shared.addMany(result.shifts); dismiss() }
                        .disabled(result.shifts.isEmpty)
                }
            }
        }
    }
}
