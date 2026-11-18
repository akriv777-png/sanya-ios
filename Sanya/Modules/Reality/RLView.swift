import SwiftUI
import SpriteKit

// MARK: - Orientation

enum OrientationLock {
    static var mask: UIInterfaceOrientationMask = .portrait
    static func set(_ m: UIInterfaceOrientationMask, prefer: UIInterfaceOrientation) {
        mask = m
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: m)) { _ in }
        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        _ = prefer
    }
}

// MARK: - Session

final class RLSession: ObservableObject {
    let game = RLGame()
    let scene: RLScene
    init() {
        scene = RLScene(size: CGSize(width: 852, height: 393))
        scene.scaleMode = .resizeFill
        scene.game = game
        game.scene = scene
    }
}

struct RealityView: View {
    @StateObject private var session = RLSession()
    var body: some View {
        RLGameUI(game: session.game, scene: session.scene)
            .toolbar(.hidden, for: .navigationBar)
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
            .onAppear { OrientationLock.set(.landscape, prefer: .landscapeRight) }
            .onDisappear {
                session.game.save(); RLAudio.shared.stop()
                OrientationLock.set(.portrait, prefer: .portrait)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in session.game.save() }
    }
}

// MARK: - Glass

private struct RLGlass: ViewModifier {
    var radius: CGFloat = 14
    var tint: Color = .clear
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color(red: 0.03, green: 0.03, blue: 0.07).opacity(0.62)))
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(tint.opacity(0.08)))
            )
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
    }
}
extension View { fileprivate func rlGlass(_ r: CGFloat = 14, tint: Color = .clear) -> some View { modifier(RLGlass(radius: r, tint: tint)) } }

private func rlFont(_ s: CGFloat, _ w: String = "Medium") -> Font { .custom("Inter-\(w)", size: s) }

// MARK: - Root UI

struct RLGameUI: View {
    @ObservedObject var game: RLGame
    let scene: RLScene
    @ObservedObject var dialogue: RLDialogue

    init(game: RLGame, scene: RLScene) {
        _game = ObservedObject(wrappedValue: game); self.scene = scene; _dialogue = ObservedObject(wrappedValue: game.dialogue)
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            SpriteView(scene: scene, preferredFramesPerSecond: 60, options: [.ignoresSiblingOrder, .shouldCullNonVisibleNodes])
                .ignoresSafeArea()
                .accessibilityIdentifier("rl_scene")

            if game.started {
                hudLayer
                    .transition(.opacity)
            }

            floatsLayer

            if let p = game.panel { panelView(p) }

            Color.black.opacity(game.blackout).ignoresSafeArea().allowsHitTesting(game.blackout > 0.5)

            if !game.started { RLIntro(game: game).transition(.opacity) }
        }
        .accessibilityIdentifier("reality_screen")
    }

    // MARK: HUD

    private var talking: Bool { if case .dialog = game.panel { return true }; return false }

    private var hudLayer: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        RLStatusCard(hud: game.hud)
                        if game.hud.wanted > 0 { RLWantedCard(stars: game.hud.wanted).transition(.move(edge: .leading).combined(with: .opacity)) }
                    }
                    Spacer(minLength: 8)
                    if let t = game.toast { RLToastView(toast: t).frame(maxWidth: 330).transition(.move(edge: .top).combined(with: .opacity)) }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 8) {
                        RLMinimap(mini: game.mini, zone: game.state.zone)
                        HStack(spacing: 8) {
                            roundButton("backpack.fill", id: "rl_inventory") { game.panel = .inventory }
                            roundButton("cpu", id: "rl_computer") { game.openDialog("computer") }
                            roundButton("pause.fill", id: "rl_menu") { game.panel = .menu }
                        }
                    }
                }
                Spacer()
                if !talking {
                    HStack(alignment: .bottom) {
                        RLJoystick(input: game.input).accessibilityIdentifier("rl_joystick")
                        Spacer()
                        VStack(spacing: 6) {
                            Text(game.hud.goal)
                                .font(rlFont(11)).foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .rlGlass(10)
                            if let p = game.prompt {
                                Button { game.activate() } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: p.symbol).font(.system(size: 14, weight: .semibold))
                                        Text(promptTitle(p)).font(rlFont(13, "SemiBold"))
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16).padding(.vertical, 10)
                                    .rlGlass(22, tint: DS.Color.sage)
                                    .overlay(Capsule().stroke(DS.Color.sage.opacity(0.7), lineWidth: 1.2).padding(1))
                                }
                                .buttonStyle(PressableStyle(scale: 0.92))
                                .accessibilityIdentifier("rl_action")
                                .transition(.scale(scale: 0.7).combined(with: .opacity))
                            }
                        }
                        Spacer()
                        RLSpellPad(game: game, scene: scene)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }

    private func promptTitle(_ p: RLPrompt) -> String {
        switch p.kind { case .npc: return "Поговорить · \(p.label)"; case .interact: return p.label }
    }

    private func roundButton(_ sym: String, id: String, _ action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            Image(systemName: sym).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                .frame(width: 36, height: 36).rlGlass(18)
        }
        .buttonStyle(PressableStyle(scale: 0.88))
        .accessibilityIdentifier(id)
    }

    private var floatsLayer: some View {
        VStack(spacing: 4) {
            ForEach(game.floats) { f in
                Text(f.text).font(rlFont(16, "SemiBold")).foregroundStyle(f.color)
                    .shadow(color: f.color.opacity(0.8), radius: 8)
                    .transition(.asymmetric(insertion: .scale(scale: 0.5).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: game.floats)
        .offset(y: -60)
        .allowsHitTesting(false)
    }

    // MARK: Panels

    @ViewBuilder private func panelView(_ p: RLPanel) -> some View {
        switch p {
        case .dialog: RLDialogPanel(game: game, dialogue: dialogue).transition(.move(edge: .bottom).combined(with: .opacity))
        case .inventory: RLModal(title: "Рюкзак", close: game.closePanel) { RLInventory(game: game) }
        case .shop(let v): RLModal(title: v == "lin" ? "Лапшичная" : "Автомат", close: game.closePanel) { RLShop(game: game, vendor: v) }
        case .menu: RLModal(title: "Пауза", close: game.closePanel) { RLMenu(game: game, exit: { game.save(); game.panel = nil; Router.shared.path = [] }) }
        case .summary(let text): RLModal(title: "Утро", close: game.closePanel) { Text(text).font(rlFont(14)).foregroundStyle(.white.opacity(0.9)).frame(maxWidth: .infinity, alignment: .leading) }
        case .sleep: RLModal(title: "Кровать", close: game.closePanel) {
            HStack { bigButton("До утра") { game.sleep(hours: nil) }; bigButton("Вздремнуть 2 ч") { game.sleep(hours: 2) } }
        }
        case .terminal: RLModal(title: "Терминал", close: game.closePanel) { RLTerminal(game: game) }
        case .shift: RLModal(title: "Смена", close: game.closePanel) { Text("Смены за стойкой «Высоты» появятся в бете.").font(rlFont(14)).foregroundStyle(.white.opacity(0.8)) }
        }
    }

    private func bigButton(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button(action: { Haptics.tap(); a() }) {
            Text(t).font(rlFont(14, "SemiBold")).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 12).rlGlass(14, tint: DS.Color.sage)
        }.buttonStyle(PressableStyle(scale: 0.95))
    }
}

// MARK: - HUD pieces

private struct RLStatusCard: View {
    let hud: RLHud
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "clock").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                Text(hud.time).font(.custom("Inter-SemiBold", size: 22).monospacedDigit()).foregroundStyle(.white)
                    .contentTransition(.numericText())
                Image(systemName: hud.weather.symbol).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            }
            HStack(spacing: 6) {
                Text("₵").font(rlFont(14, "SemiBold")).foregroundStyle(Color(red: 0.2, green: 0.9, blue: 1))
                Text("\(hud.money)").font(.custom("Inter-SemiBold", size: 15).monospacedDigit()).foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text("· день \(hud.day)").font(rlFont(11)).foregroundStyle(.white.opacity(0.5))
            }
            bar("Голод", "heart.fill", Color(red: 0.95, green: 0.25, blue: 0.3), hud.hunger)
            bar("Энергия", "bolt.fill", Color(red: 1, green: 0.8, blue: 0.2), hud.energy)
            bar("Мана", "drop.fill", Color(red: 0.25, green: 0.55, blue: 1), hud.mana)
        }
        .padding(10)
        .frame(width: 170, alignment: .leading)
        .rlGlass(14)
        .animation(.easeOut(duration: 0.3), value: hud)
        .accessibilityIdentifier("rl_hud")
    }
    private func bar(_ t: String, _ sym: String, _ c: Color, _ v: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: sym).font(.system(size: 10, weight: .bold)).foregroundStyle(c)
                Text(t).font(rlFont(10)).foregroundStyle(.white.opacity(0.8))
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(LinearGradient(colors: [c.opacity(0.75), c], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(3, g.size.width * CGFloat(v / 100)))
                        .shadow(color: c.opacity(0.7), radius: 4)
                }
            }
            .frame(height: 5)
        }
    }
}

private struct RLWantedCard: View {
    let stars: Int
    @State private var pulse = false
    var body: some View {
        HStack(spacing: 6) {
            Text("Розыск").font(rlFont(11, "SemiBold")).foregroundStyle(Color(red: 1, green: 0.35, blue: 0.4))
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    Image(systemName: i < stars ? "star.fill" : "star").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(i < stars ? Color(red: 1, green: 0.2, blue: 0.25) : .white.opacity(0.25))
                        .shadow(color: i < stars ? .red.opacity(0.8) : .clear, radius: pulse ? 6 : 2)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .rlGlass(12, tint: .red)
        .onAppear { withAnimation(.easeInOut(duration: 0.6).repeatForever()) { pulse = true } }
        .accessibilityIdentifier("rl_wanted")
    }
}

private struct RLToastView: View {
    let toast: RLToast
    @State private var shown = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(Color(red: 0.2, green: 0.9, blue: 1)).frame(width: 6, height: 6).shadow(color: .cyan, radius: 4)
                Text(toast.who).font(.custom("Inter-SemiBold", size: 10)).tracking(2).foregroundStyle(Color(red: 0.2, green: 0.9, blue: 1))
            }
            Text(String(toast.text.prefix(shown))).font(rlFont(12)).foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rlGlass(12, tint: .cyan)
        .task(id: toast.id) {
            shown = 0
            for i in 0...toast.text.count { shown = i; try? await Task.sleep(nanoseconds: 14_000_000) }
        }
        .accessibilityIdentifier("rl_toast")
    }
}

private struct RLMinimap: View {
    let mini: RLMini
    let zone: RLZone
    private static let images: [RLZone: UIImage] = {
        var d: [RLZone: UIImage] = [:]
        for z in [RLZone.street, .apartment, .bar] { if let i = UIImage(named: RLWorld.map(z).bg) { d[z] = i } }
        return d
    }()
    var body: some View {
        let w: CGFloat = 132, h: CGFloat = 74
        ZStack(alignment: .topLeading) {
            if let img = RLMinimap.images[zone] {
                Image(uiImage: img).resizable().interpolation(.none).frame(width: w, height: h)
                    .saturation(0.5).brightness(0.05).contrast(1.3).opacity(0.8)
            }
            ForEach(Array(mini.npcs.keys), id: \.self) { id in
                if let p = mini.npcs[id] {
                    Circle().fill(Color(hex: RLCast.get(id)?.accent ?? "FFFFFF")).frame(width: 6, height: 6)
                        .shadow(color: Color(hex: RLCast.get(id)?.accent ?? "FFFFFF"), radius: 3)
                        .position(x: p.x * w, y: p.y * h)
                }
            }
            if let d = mini.drone {
                Image(systemName: "dot.radiowaves.up.forward").font(.system(size: 8, weight: .bold)).foregroundStyle(.red)
                    .position(x: d.x * w, y: d.y * h)
            }
            Image(systemName: "location.north.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                .rotationEffect(.radians(Double(mini.dir)))
                .shadow(color: .white, radius: 3)
                .position(x: mini.player.x * w, y: mini.player.y * h)
        }
        .frame(width: w, height: h)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(5)
        .rlGlass(14)
        .accessibilityIdentifier("rl_minimap")
    }
}

// MARK: - Joystick

private struct RLJoystick: View {
    let input: RLInput
    @State private var knob: CGSize = .zero
    @State private var active = false
    private let r: CGFloat = 52
    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial).overlay(Circle().fill(Color.black.opacity(0.45)))
                .overlay(Circle().stroke(Color.white.opacity(active ? 0.3 : 0.15), lineWidth: 1.2))
            ForEach(0..<4, id: \.self) { i in
                Image(systemName: "chevron.up").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.35))
                    .offset(y: -r + 14).rotationEffect(.degrees(Double(i) * 90))
            }
            Circle().fill(LinearGradient(colors: [Color.white.opacity(0.32), Color.white.opacity(0.12)], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
                .frame(width: 46, height: 46)
                .shadow(color: DS.Color.sage.opacity(active ? 0.6 : 0), radius: 10)
                .offset(knob)
        }
        .frame(width: r * 2, height: r * 2)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in
                var d = CGSize(width: v.location.x - r, height: v.location.y - r)
                let len = hypot(d.width, d.height)
                if len > r - 10 { d = CGSize(width: d.width / len * (r - 10), height: d.height / len * (r - 10)) }
                if !active { Haptics.select() }
                active = true; knob = d
                input.vector = CGVector(dx: d.width / (r - 10), dy: -d.height / (r - 10))
            }
            .onEnded { _ in
                active = false
                withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { knob = .zero }
                input.vector = .zero
            })
    }
}

// MARK: - Spells

private struct RLSpellPad: View {
    @ObservedObject var game: RLGame
    let scene: RLScene
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            VStack(spacing: 8) {
                HStack(spacing: 10) { btn(.glyph); btn(.hex) }
                HStack(spacing: 10) { btn(.shadow); btn(.sigil) }
            }
        }
    }
    private func btn(_ sp: RLSpell) -> some View {
        let cd = scene.cooldownLeft(sp)
        let ok = game.state.mana >= sp.cost
        return Button { scene.cast(sp) } label: {
            ZStack {
                Circle().fill(.ultraThinMaterial).overlay(Circle().fill(Color.black.opacity(0.55)))
                Circle().fill(RadialGradient(colors: [sp.ui.opacity(0.35), .clear], center: .center, startRadius: 2, endRadius: 30))
                Image(uiImage: UIImage(named: sp.icon) ?? UIImage()).resizable().interpolation(.medium).scaledToFit().padding(9)
                    .saturation(ok ? 1 : 0.1).opacity(ok ? 1 : 0.45)
                    .shadow(color: sp.ui.opacity(0.9), radius: ok ? 6 : 0)
                Circle().stroke(sp.ui.opacity(ok ? 0.8 : 0.25), lineWidth: 1.5)
                if cd > 0 {
                    Circle().trim(from: 0, to: CGFloat(cd / sp.cooldown))
                        .stroke(Color.black.opacity(0.6), style: StrokeStyle(lineWidth: 26, lineCap: .butt))
                        .rotationEffect(.degrees(-90)).padding(13)
                    Text(String(format: "%.0f", ceil(cd))).font(rlFont(13, "SemiBold")).foregroundStyle(.white)
                }
                Text("\(Int(sp.cost))").font(.custom("Inter-SemiBold", size: 8)).foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Capsule().fill(Color(red: 0.15, green: 0.3, blue: 0.8)))
                    .offset(x: 18, y: 22)
            }
            .frame(width: 60, height: 60)
        }
        .buttonStyle(PressableStyle(scale: 0.86))
        .accessibilityIdentifier("rl_spell_\(sp.rawValue)")
    }
}

// MARK: - Dialogue

struct RLDialogPanel: View {
    @ObservedObject var game: RLGame
    @ObservedObject var dialogue: RLDialogue
    @FocusState private var focused: Bool

    private var name: String { dialogue.npc == "computer" ? "Компьютер" : (dialogue.def?.name ?? "") }
    private var accent: Color { dialogue.npc == "computer" ? Color(red: 0.2, green: 0.9, blue: 1) : Color(hex: dialogue.def?.accent ?? "A8C5A0") }

    var body: some View {
        VStack {
            Spacer()
            HStack(alignment: .top, spacing: 12) {
                portrait
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(name.uppercased()).font(.custom("Inter-SemiBold", size: 13)).tracking(1.5).foregroundStyle(accent)
                        if let d = dialogue.def, dialogue.npc != "computer" {
                            let rel = game.state.mem(d.id).rel
                            Text("· \(RLGame.relLabel(rel))").font(rlFont(11)).foregroundStyle(.white.opacity(0.5))
                            Capsule().fill(Color.white.opacity(0.1)).frame(width: 46, height: 4)
                                .overlay(alignment: .leading) { Capsule().fill(accent).frame(width: 46 * CGFloat((rel + 100) / 200), height: 4) }
                        }
                        Spacer()
                        Button { Haptics.tap(); focused = false; game.closePanel() } label: {
                            Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.7)).frame(width: 28, height: 28).rlGlass(14)
                        }.accessibilityIdentifier("rl_dialog_close")
                    }
                    lines
                    chips
                    inputRow
                }
            }
            .padding(12)
            .frame(maxWidth: 680)
            .rlGlass(18, tint: accent)
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
        .accessibilityIdentifier("rl_dialog")
    }

    @ViewBuilder private var portrait: some View {
        let img: UIImage? = UIImage(named: "pt_\(dialogue.npc).jpg")
        ZStack {
            if let img { Image(uiImage: img).resizable().interpolation(.none).scaledToFill() }
            else {
                LinearGradient(colors: [accent.opacity(0.35), .black], startPoint: .top, endPoint: .bottom)
                Image(systemName: dialogue.npc == "computer" ? "cpu" : "dot.radiowaves.left.and.right").font(.system(size: 34)).foregroundStyle(accent)
            }
        }
        .frame(width: 92, height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(accent.opacity(0.6), lineWidth: 1))
        .shadow(color: accent.opacity(0.4), radius: 8)
    }

    private var lines: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(dialogue.lines.enumerated()), id: \.element.id) { i, l in
                        line(l).id(l.id)
                            .accessibilityIdentifier(l.fromPlayer ? "rl_line_player" : "rl_line_npc_\(i)")
                    }
                    if dialogue.typing {
                        HStack(spacing: 6) {
                            RLTypingDots(color: accent)
                            if dialogue.waitingLong { Text("сеть занята, ждём очередь…").font(rlFont(10)).foregroundStyle(.white.opacity(0.4)) }
                        }.id("typing")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 40, maxHeight: 92)
            .onChange(of: dialogue.lines.count) { _, _ in withAnimation { proxy.scrollTo(dialogue.lines.last?.id, anchor: .bottom) } }
            .onChange(of: dialogue.typing) { _, t in if t { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } } }
        }
    }

    private func line(_ l: RLDialogue.Line) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if l.fromPlayer { Spacer(minLength: 40) }
            Text(l.text)
                .font(l.system ? rlFont(12).italic() : rlFont(13.5))
                .foregroundStyle(l.system ? Color(red: 0.2, green: 0.9, blue: 1).opacity(0.85) : .white.opacity(l.fromPlayer ? 0.85 : 0.95))
                .padding(.horizontal, l.fromPlayer ? 10 : 0).padding(.vertical, l.fromPlayer ? 5 : 0)
                .background { if l.fromPlayer { RoundedRectangle(cornerRadius: 10).fill(DS.Color.ember.opacity(0.18)) } }
                .multilineTextAlignment(l.fromPlayer ? .trailing : .leading)
            if l.offline { Image(systemName: "wifi.slash").font(.system(size: 8)).foregroundStyle(.white.opacity(0.3)) }
            if !l.fromPlayer { Spacer(minLength: 20) }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(dialogue.actions) { a in
                    Button { Haptics.tap(); dialogue.perform(a.id) } label: {
                        Label(a.title, systemImage: a.symbol).font(rlFont(11.5, "SemiBold")).foregroundStyle(.black)
                            .padding(.horizontal, 10).padding(.vertical, 6).background(Capsule().fill(DS.Color.sage))
                    }.accessibilityIdentifier("rl_act_\(a.id)")
                }
                ForEach(Array(dialogue.quick.enumerated()), id: \.offset) { i, q in
                    Button { dialogue.send(q) } label: {
                        Text(q).font(rlFont(11.5)).foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 10).padding(.vertical, 6).background(Capsule().fill(Color.white.opacity(0.08)))
                            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    }.disabled(dialogue.typing).accessibilityIdentifier("rl_quick_\(i)")
                }
            }
        }
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.4))
            TextField("", text: $dialogue.input, prompt: Text("Скажи что-нибудь…").foregroundStyle(.white.opacity(0.35)))
                .font(rlFont(13.5)).foregroundStyle(.white)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { dialogue.send() }
                .accessibilityIdentifier("rl_input")
            Button { dialogue.send() } label: {
                Image(systemName: "paperplane.fill").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(dialogue.input.isEmpty || dialogue.typing ? .white.opacity(0.3) : accent)
            }
            .disabled(dialogue.input.isEmpty || dialogue.typing)
            .accessibilityIdentifier("rl_send")
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

private struct RLTypingDots: View {
    let color: Color
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(color).frame(width: 6, height: 6)
                        .opacity(0.35 + 0.65 * max(0, sin(t * 6 - Double(i) * 0.8)))
                        .offset(y: -3 * max(0, sin(t * 6 - Double(i) * 0.8)))
                }
            }
        }
        .accessibilityIdentifier("rl_typing")
    }
}

// MARK: - Modal panels

private struct RLModal<Content: View>: View {
    let title: String
    let close: () -> Void
    @ViewBuilder let content: () -> Content
    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { close() }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title).font(.custom("CormorantGaramond-SemiBold", size: 26)).foregroundStyle(.white)
                    Spacer()
                    Button { Haptics.tap(); close() } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.7)).frame(width: 30, height: 30).rlGlass(15)
                    }.accessibilityIdentifier("rl_modal_close")
                }
                ScrollView(showsIndicators: false) { content() }
            }
            .padding(16)
            .frame(maxWidth: 520, maxHeight: 320)
            .rlGlass(20)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
    }
}

private struct RLInventory: View {
    @ObservedObject var game: RLGame
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    var body: some View {
        let items = game.state.inventory.sorted { $0.key < $1.key }
        if items.isEmpty {
            Text("Пусто. Даже пыли нет.").font(rlFont(13)).foregroundStyle(.white.opacity(0.6))
        }
        LazyVGrid(columns: cols, spacing: 8) {
            ForEach(items, id: \.key) { pair in
                let k = pair.key, n = pair.value
                let it = RLItem.get(k)
                Button { game.use(k) } label: {
                    VStack(spacing: 6) {
                        Image(systemName: it.symbol).font(.system(size: 22)).foregroundStyle(DS.Color.sage)
                        Text(it.name).font(rlFont(10.5)).foregroundStyle(.white.opacity(0.9)).lineLimit(2).multilineTextAlignment(.center)
                        Text("×\(n)").font(rlFont(10, "SemiBold")).foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, minHeight: 92).padding(6).rlGlass(12)
                }
                .buttonStyle(PressableStyle(scale: 0.93))
                .accessibilityIdentifier("rl_item_\(k)")
            }
        }
        .accessibilityIdentifier("rl_inventory_panel")
    }
}

private struct RLShop: View {
    @ObservedObject var game: RLGame
    let vendor: String
    var body: some View {
        VStack(spacing: 8) {
            ForEach(RLGame.vendorItems(vendor), id: \.self) { id in
                let it = RLItem.get(id); let p = game.price(it, vendor: vendor)
                HStack(spacing: 10) {
                    Image(systemName: it.symbol).font(.system(size: 18)).foregroundStyle(DS.Color.sage).frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(it.name).font(rlFont(13, "SemiBold")).foregroundStyle(.white)
                        Text(it.note).font(rlFont(11)).foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    Button { game.buy(id, vendor: vendor) } label: {
                        Text("\(p)₵").font(rlFont(13, "SemiBold")).foregroundStyle(.black).padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(game.state.money >= p ? DS.Color.sage : Color.gray))
                    }
                }
                .padding(8).rlGlass(12)
            }
        }
    }
}

private struct RLTerminal: View {
    @ObservedObject var game: RLGame
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ВЕСТНИК ОРАКУЛА").font(.custom("Inter-SemiBold", size: 10)).tracking(2).foregroundStyle(.red.opacity(0.8))
            ForEach(["Порядок — это забота. Сенсоры — ваши друзья.", "Сообщите о свечении: вознаграждение — 500₵.", "Дождь продлится всегда. Это нормально."], id: \.self) { Text("— " + $0).font(rlFont(12)).foregroundStyle(.white.opacity(0.8)) }
            Text("ХРОНИКА КВАРТАЛА").font(.custom("Inter-SemiBold", size: 10)).tracking(2).foregroundStyle(DS.Color.sage).padding(.top, 6)
            ForEach(Array(game.state.events.suffix(6).reversed().enumerated()), id: \.offset) { _, e in
                Text("\(RLClock.text(e.minute)) · \(e.text)").font(rlFont(12)).foregroundStyle(.white.opacity(0.75))
            }
        }
    }
}

private struct RLMenu: View {
    @ObservedObject var game: RLGame
    let exit: () -> Void
    @State private var confirm = false
    var body: some View {
        VStack(spacing: 8) {
            row("play.fill", "Продолжить") { game.closePanel() }
            row(game.soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill", game.soundOn ? "Звук: вкл" : "Звук: выкл") { game.soundOn.toggle() }
            row("square.and.arrow.down", "Сохранить") { game.save(); game.computer("Сохранено. Реальность зафиксирована.") ; game.closePanel() }
            row("arrow.counterclockwise", confirm ? "Точно? Всё сотрётся" : "Новая жизнь") { if confirm { game.newLife() } else { confirm = true } }
            row("door.left.hand.open", "Выйти в Саню", id: "rl_exit") { exit() }
        }
    }
    private func row(_ s: String, _ t: String, id: String? = nil, _ a: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); a() } label: {
            HStack { Image(systemName: s).frame(width: 22); Text(t).font(rlFont(14, "SemiBold")); Spacer() }
                .foregroundStyle(.white).padding(12).rlGlass(12)
        }
        .buttonStyle(PressableStyle(scale: 0.96))
        .accessibilityIdentifier(id ?? "rl_menu_\(s)")
    }
}

// MARK: - Intro

private struct RLIntro: View {
    @ObservedObject var game: RLGame
    @State private var glitch = false
    @State private var appear = false
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.black.opacity(0.55), Color(red: 0.08, green: 0.02, blue: 0.14).opacity(0.85)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 14) {
                ZStack {
                    title.foregroundStyle(Color(red: 1, green: 0.2, blue: 0.6).opacity(0.7)).offset(x: glitch ? -3 : 1, y: glitch ? 1 : 0)
                    title.foregroundStyle(Color(red: 0.2, green: 0.9, blue: 1).opacity(0.7)).offset(x: glitch ? 3 : -1, y: glitch ? -1 : 0)
                    title.foregroundStyle(.white)
                }
                Text("ТЕСТОВАЯ ЛОКАЦИЯ · ПЛОЩАДЬ У «ВЫСОТЫ»").font(.custom("Inter-SemiBold", size: 11)).tracking(3).foregroundStyle(.white.opacity(0.6))
                Text("Город под Оракулом. Сенсоры видят всё, свечение — это задержание.\nТы — Векс, 19, бармен и тайный «проклятый». Просто живи. И не свети.")
                    .font(rlFont(13)).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.8)).padding(.horizontal, 40)
                HStack(spacing: 12) {
                    if game.hasSave {
                        Button { Haptics.success(); game.begin(fresh: false) } label: { pill("Продолжить", true) }.accessibilityIdentifier("rl_continue")
                    }
                    Button { Haptics.success(); game.begin(fresh: !game.hasSave ? false : true) } label: { pill(game.hasSave ? "Новая жизнь" : "Начать жизнь", !game.hasSave) }
                        .accessibilityIdentifier("rl_start")
                }
                .padding(.top, 6)
            }
            .opacity(appear ? 1 : 0).scaleEffect(appear ? 1 : 0.96)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { appear = true }
            withAnimation(.easeInOut(duration: 0.12).repeatForever(autoreverses: true)) { glitch = true }
        }
        .accessibilityIdentifier("rl_intro")
    }
    private var title: some View { Text("РЕАЛЬНОСТЬ").font(.custom("CormorantGaramond-SemiBold", size: 58)).tracking(6) }
    private func pill(_ t: String, _ primary: Bool) -> some View {
        Text(t).font(rlFont(14, "SemiBold")).foregroundStyle(primary ? .black : .white)
            .padding(.horizontal, 22).padding(.vertical, 11)
            .background(Capsule().fill(primary ? DS.Color.sage : Color.white.opacity(0.08)))
            .overlay(Capsule().stroke(Color.white.opacity(primary ? 0 : 0.25), lineWidth: 1))
    }
}
