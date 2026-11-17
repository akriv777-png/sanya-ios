import SwiftUI

struct LauncherView: View {
    @ObservedObject var router = Router.shared
    @ObservedObject var shifts = ShiftStore.shared
    @ObservedObject var player = PlayerModel.shared
    @ObservedObject var timers = TimerStore.shared
    @State private var showSettings = false
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        NavigationStack(path: $router.path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if let next = shifts.nextShift {
                        Button { router.go(.shifts) } label: { NextShiftCard(shift: next) }.buttonStyle(.plain)
                    }
                    if let t = player.current {
                        Button { router.go(.player) } label: { NowPlayingCard(track: t, playing: player.isPlaying) }.buttonStyle(.plain)
                    }
                    if let t = timers.running.first {
                        Button { router.go(.timers) } label: { TimerMiniCard(timer: t) }.buttonStyle(.plain)
                    }
                    Text("Модули").font(.title3.bold())
                    LazyVGrid(columns: cols, spacing: 12) {
                        ForEach(Modules.ready) { m in tile(m) }
                    }
                    HStack {
                        Text("Скоро").font(.title3.bold())
                        Spacer()
                        Text("\(Modules.soon.count) модулей").font(.caption).foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: cols, spacing: 12) {
                        ForEach(Modules.soon) { m in tile(m) }
                    }
                }
                .padding()
            }
            .background(Theme.background)
            .navigationDestination(for: ModuleID.self) { ModuleScreen(id: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape.fill") }
                        .accessibilityIdentifier("settings")
                }
            }
            .sheet(isPresented: $showSettings) { NavigationStack { AssistantSettingsView() } }
        }
    }

    private func tile(_ m: ModuleInfo) -> some View {
        NavigationLink(value: m.id) { ModuleTile(info: m) }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tile_\(m.id.rawValue)")
    }

    private var header: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting(ctx.date)).font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.white, Theme.violet], startPoint: .leading, endPoint: .trailing))
                Text(Fmt.longDay(ctx.date).capitalized).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }

    private func greeting(_ d: Date) -> String {
        switch Calendar.current.component(.hour, from: d) {
        case 5..<12: return "Доброе утро, Егор"
        case 12..<18: return "Привет, Егор"
        case 18..<23: return "Добрый вечер, Егор"
        default: return "Не спится, Егор?"
        }
    }
}

struct ModuleTile: View {
    let info: ModuleInfo
    var body: some View {
        let tint = Color(hex: info.tint)
        VStack(spacing: 8) {
            Text(info.emoji).font(.system(size: 34))
            Text(info.title).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            if !info.ready {
                Text(info.wave).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 104)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(info.ready ? 0.55 : 0.18), Theme.card], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(tint.opacity(info.ready ? 0.6 : 0.15), lineWidth: 1))
        .opacity(info.ready ? 1 : 0.7)
        .contentShape(Rectangle())
    }
}

struct NextShiftCard: View {
    let shift: Shift
    var body: some View {
        HStack(spacing: 14) {
            Text("🍟").font(.largeTitle)
            VStack(alignment: .leading, spacing: 3) {
                Text(shift.start <= Date() ? "Сейчас смена" : "Следующая смена").font(.caption).foregroundStyle(.secondary)
                Text("\(Fmt.day(shift.start)), \(Fmt.time(shift.start))–\(Fmt.time(shift.end))").font(.headline)
                Text(Fmt.hours(shift.hours)).font(.caption).foregroundStyle(Theme.gold)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }
        .card()
    }
}

struct NowPlayingCard: View {
    let track: Track
    let playing: Bool
    var body: some View {
        HStack(spacing: 14) {
            CoverArt(track: track, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.headline).lineLimit(1)
                Text(track.artist).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            EqualizerBars(tint: Color(hex: track.colorHex), playing: playing, seed: Int(Date().timeIntervalSince1970), height: 20)
        }
        .card()
    }
}

struct TimerMiniCard: View {
    let timer: RunningTimer
    var body: some View {
        HStack {
            Text("⏱").font(.largeTitle)
            Text(timer.title).font(.headline)
            Spacer()
            Text(timerInterval: timer.start...max(timer.start, timer.end), countsDown: true)
                .monospacedDigit().font(.title3.bold()).foregroundStyle(Theme.gold)
        }
        .card()
    }
}
