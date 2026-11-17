import SwiftUI

struct LauncherView: View {
    @ObservedObject var router  = Router.shared
    @ObservedObject var shifts  = ShiftStore.shared
    @ObservedObject var player  = PlayerModel.shared
    @ObservedObject var timers  = TimerStore.shared
    @State private var showSettings = false

    // 4-column grid for modules
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        NavigationStack(path: $router.path) {
            ZStack(alignment: .bottom) {
                // Atmosphere background fills everything
                AtmosphereBackground()
                    .ignoresSafeArea()

                // Main scrollable content
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        // ── greeting + date ──────────────────────────────
                        headerSection
                            .padding(.top, 60)
                            .appearIn(0)

                        // ── search field ─────────────────────────────────
                        searchBar
                            .appearIn(1)

                        // ── widget row: next shift + now playing ─────────
                        widgetRow
                            .appearIn(2)

                        // ── Modules grid ─────────────────────────────────
                        SectionHeader("Модули")
                            .padding(.top, 4)

                        LazyVGrid(columns: cols, spacing: 14) {
                            ForEach(Modules.ready) { m in tile(m) }
                        }
                        .appearIn(3)

                        // ── Soon ─────────────────────────────────────────
                        SectionHeader("Скоро", trailing:
                            Text("\(Modules.soon.count)")
                                .font(DS.Font.caption)
                                .foregroundStyle(DS.Color.mute)
                        )
                        .padding(.top, 6)

                        LazyVGrid(columns: cols, spacing: 14) {
                            ForEach(Modules.soon) { m in tile(m) }
                        }
                        .appearIn(4)

                        // Bottom padding so dock doesn't overlap content
                        Spacer().frame(height: 100)
                    }
                    .padding(.horizontal, 18)
                }

                // ── Glass dock ───────────────────────────────────────────
                dock
            }
            .navigationBarHidden(true)
            .navigationDestination(for: ModuleID.self) { id in
                ModuleScreen(id: id)
                    .onAppear { EventBus.shared.emit(.moduleOpened(id.rawValue)) }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }
            }
        }
    }

    // MARK: – Header

    private var headerSection: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            VStack(alignment: .leading, spacing: 6) {
                Text(greeting(ctx.date))
                    .font(DS.Font.display(40))
                    .foregroundStyle(DS.Color.ink)
                Text(Fmt.longDay(ctx.date).capitalized)
                    .font(DS.Font.label)
                    .tracking(2)
                    .foregroundStyle(DS.Color.mute)
                    .textCase(.uppercase)
            }
        }
    }

    // MARK: – Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(DS.Color.mute)
            Text("Поиск…")
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.mute)
            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(height: 50)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(DS.Color.line, lineWidth: 1))
    }

    // MARK: – Widget row

    @ViewBuilder
    private var widgetRow: some View {
        let hasShift = shifts.nextShift != nil
        let hasPlayer = player.current != nil

        if hasShift || hasPlayer {
            HStack(spacing: 12) {
                if let next = shifts.nextShift {
                    Button { router.go(.shifts) } label: { NextShiftWidget(shift: next) }
                        .buttonStyle(.plain)
                }
                if let t = player.current {
                    Button { router.go(.player) } label: { NowPlayingWidget(track: t, playing: player.isPlaying) }
                        .buttonStyle(.plain)
                }
                if let t = timers.running.first, !hasShift && !hasPlayer {
                    Button { router.go(.timers) } label: { TimerWidget(timer: t) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: – Tile

    private func tile(_ m: ModuleInfo) -> some View {
        NavigationLink(value: m.id) {
            DSModuleTile(info: m)
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("tile_\(m.id.rawValue)")
    }

    // MARK: – Glass dock

    private var dock: some View {
        HStack(spacing: 0) {
            dockButton(icon: "house.fill",         id: "dock_home",     action: { router.path = [] })
            dockButton(icon: "music.note",          id: "dock_player",   action: { router.go(.player) })
            dockButton(icon: "bubble.left.fill",    id: "dock_chat",     action: { router.go(.assistant) })
            dockButton(icon: "calendar",            id: "dock_shifts",   action: { router.go(.shifts) })
            dockButton(icon: "gearshape.fill",      id: "dock_settings", action: { showSettings = true })
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, max(16, 0))
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(DS.Color.line).frame(height: 1), alignment: .top)
        .ignoresSafeArea(edges: .bottom)
    }

    private func dockButton(icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(DS.Color.ink.opacity(0.85))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.85))
        .accessibilityIdentifier(id)
    }

    // MARK: – Greeting

    private func greeting(_ d: Date) -> String {
        switch Calendar.current.component(.hour, from: d) {
        case 5..<12: return "Доброе утро, Егор"
        case 12..<18: return "Добрый день, Егор"
        case 18..<23: return "Добрый вечер, Егор"
        default:      return "Доброй ночи, Егор"
        }
    }
}

// MARK: - Widget cards

struct NextShiftWidget: View {
    let shift: Shift
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(shift.start <= Date() ? "Сейчас смена" : "Следующая смена")
                    .font(DS.Font.label)
                    .tracking(1.5)
                    .foregroundStyle(DS.Color.mute)
            } icon: {
                Image(systemName: "fork.knife")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(DS.Color.mute)
            }
            Text("\(Fmt.time(shift.start))–\(Fmt.time(shift.end))")
                .font(DS.Font.display(26))
                .foregroundStyle(DS.Color.ink)
            Text(Fmt.hours(shift.hours))
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.ember2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: DS.Radius.tile, padding: 14)
    }
}

struct NowPlayingWidget: View {
    let track: Track
    let playing: Bool
    var body: some View {
        HStack(spacing: 10) {
            CoverArt(track: track, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(DS.Font.bodyMed)
                    .lineLimit(1)
                    .foregroundStyle(DS.Color.ink)
                Text(track.artist)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.mute)
            }
            Spacer(minLength: 0)
            EqualizerBars(tint: DS.Color.sage, playing: playing,
                          seed: Int(Date().timeIntervalSince1970), height: 18)
        }
        .frame(maxWidth: .infinity)
        .glassCard(radius: DS.Radius.tile, padding: 12)
    }
}

struct TimerWidget: View {
    let timer: RunningTimer
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "timer")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(DS.Color.ember)
            VStack(alignment: .leading, spacing: 2) {
                Text(timer.title)
                    .font(DS.Font.bodyMed)
                    .foregroundStyle(DS.Color.ink)
                Text(timerInterval: timer.start...max(timer.start, timer.end), countsDown: true)
                    .monospacedDigit()
                    .font(DS.Font.display(22))
                    .foregroundStyle(DS.Color.ember2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .glassCard(radius: DS.Radius.tile, padding: 12)
    }
}

// MARK: - SettingsView (restyle)

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("bgTheme")     private var bgTheme   = "sea"
    @AppStorage("petOverlay")  private var petOverlay = true
    @AppStorage("ai.speak")    private var speak      = true
    @AppStorage("ai.endpoint") private var endpoint  = ""
    @AppStorage("ai.model")    private var aiModel   = ""
    @AppStorage("ai.enabled")  private var aiEnabled = true
    @State private var key = Keychain.get("ai.key")
    @State private var aiStatus = ""

    private let themes: [(String, String, String)] = [
        ("sea",      "Море",   "bg_sea"),
        ("fog",      "Туман",  "bg_fog"),
        ("city",     "Город",  "bg_city"),
        ("concrete", "Бетон",  "bg_concrete"),
    ]

    var body: some View {
        ZStack {
            AtmosphereBackground().ignoresSafeArea()
            List {
                // Theme picker
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(themes, id: \.0) { key, name, img in
                                Button {
                                    withAnimation { bgTheme = key }
                                } label: {
                                    VStack(spacing: 6) {
                                        Image(img)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 72, height: 100)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .stroke(bgTheme == key ? DS.Color.sage : DS.Color.line,
                                                            lineWidth: bgTheme == key ? 2 : 1)
                                            )
                                        Text(name)
                                            .font(DS.Font.caption)
                                            .foregroundStyle(bgTheme == key ? DS.Color.sage : DS.Color.mute)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("theme_\(key)")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Фон")
                        .font(DS.Font.label)
                        .tracking(2)
                        .foregroundStyle(DS.Color.mute)
                        .textCase(.uppercase)
                }

                // Pet
                Section {
                    Toggle("Питомец на экране", isOn: $petOverlay)
                        .toggleStyle(DSToggleStyle())
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.ink)
                        .accessibilityIdentifier("toggle_pet_overlay")
                } header: {
                    Text("Питомец")
                        .font(DS.Font.label).tracking(2).foregroundStyle(DS.Color.mute).textCase(.uppercase)
                }

                // Voice
                Section {
                    Toggle("Озвучивать ответы", isOn: $speak)
                        .toggleStyle(DSToggleStyle())
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.ink)
                } header: {
                    Text("Голос")
                        .font(DS.Font.label).tracking(2).foregroundStyle(DS.Color.mute).textCase(.uppercase)
                }

                // AI
                Section {
                    Toggle("ИИ включён", isOn: $aiEnabled)
                        .toggleStyle(DSToggleStyle())
                        .font(DS.Font.body).foregroundStyle(DS.Color.ink)
                        .accessibilityIdentifier("ai_toggle")
                    TextField("Свой сервер (пусто = бесплатный)", text: $endpoint)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(DS.Font.body).foregroundStyle(DS.Color.ink)
                    TextField("Модель (пусто = openai)", text: $aiModel)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(DS.Font.body).foregroundStyle(DS.Color.ink)
                    SecureField("Ключ (если нужен)", text: $key)
                        .font(DS.Font.body).foregroundStyle(DS.Color.ink)
                    Button {
                        Keychain.set(key, for: "ai.key")
                        aiStatus = "проверяю…"
                        Task {
                            let ok: Bool
                            do { _ = try await AIClient.chat(system: "Ответь одним словом.", messages: [(role: "user", content: "пинг")], maxTokens: 20); ok = true } catch { ok = false }
                            await MainActor.run {
                                aiStatus = ok ? "на связи ✓" : "не отвечает"
                                if ok { Haptics.success() } else { Haptics.warning() }
                            }
                        }
                    } label: {
                        HStack {
                            Text("Проверить связь").font(DS.Font.body).foregroundStyle(DS.Color.sage)
                            Spacer()
                            Text(aiStatus).font(DS.Font.caption).foregroundStyle(DS.Color.mute)
                        }
                    }
                    .accessibilityIdentifier("ai_ping")
                } header: {
                    Text("ИИ")
                        .font(DS.Font.label).tracking(2).foregroundStyle(DS.Color.mute).textCase(.uppercase)
                } footer: {
                    Text("По умолчанию — бесплатный публичный ИИ без ключа (в приложении нет секретов). Свой сервер: любой OpenAI-совместимый адрес; ключ хранится только в Keychain. Ссылка sanya://ai?url=…&key=… заполнит всё сама.")
                        .font(DS.Font.caption).foregroundStyle(DS.Color.dim)
                }

                // Island preview
                Section {
                    NavigationLink {
                        IslandPreviewView()
                    } label: {
                        Label("Предпросмотр острова", systemImage: "capsule.fill")
                            .font(DS.Font.body).foregroundStyle(DS.Color.ink)
                    }
                    .accessibilityIdentifier("island_preview")
                } header: {
                    Text("Остров")
                        .font(DS.Font.label).tracking(2).foregroundStyle(DS.Color.mute).textCase(.uppercase)
                }

                // About
                Section {
                    LabeledContent("Версия", value: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—")
                    LabeledContent("Модулей готово", value: "\(Modules.ready.count) из \(Modules.all.count)")
                } header: {
                    Text("О приложении")
                        .font(DS.Font.label).tracking(2).foregroundStyle(DS.Color.mute).textCase(.uppercase)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Настройки")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Готово") { Keychain.set(key, for: "ai.key"); dismiss() }
                    .foregroundStyle(DS.Color.sage)
            }
        }
    }
}
