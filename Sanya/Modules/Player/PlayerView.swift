import SwiftUI
import UniformTypeIdentifiers

struct CoverArt: View {
    let track: Track?
    let size: CGFloat
    var symbol: String = "music.note"

    var body: some View {
        let tint = Color(hex: track?.colorHex ?? "8A5CFF")
        ZStack {
            if let t = track, let img = PlayerModel.shared.artwork(for: t) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [tint, Color(hex: "1A0F2E")], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: symbol).font(.system(size: size * 0.38, weight: .bold)).foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.16, style: .continuous))
    }
}

struct Visualizer: View {
    let levels: [CGFloat]
    let tint: Color
    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(levels.indices, id: \.self) { i in
                Capsule()
                    .fill(LinearGradient(colors: [tint, tint.opacity(0.4)], startPoint: .top, endPoint: .bottom))
                    .frame(height: max(4, 70 * levels[i]))
            }
        }
        .frame(height: 70)
        .animation(.easeOut(duration: 0.08), value: levels)
    }
}

struct PlayerView: View {
    @ObservedObject private var player = PlayerModel.shared
    @State private var importing = false
    @State private var showLyrics = false

    var body: some View {
        let tint = Color(hex: player.current?.colorHex ?? "8A5CFF")
        ScrollView {
            VStack(spacing: 18) {
                CoverArt(track: player.current, size: 250, symbol: player.islandSymbol)
                    .scaleEffect(player.isPlaying ? 1 : 0.9)
                    .shadow(color: tint.opacity(player.isPlaying ? 0.7 : 0.2), radius: player.isPlaying ? 40 : 10)
                    .animation(.spring(duration: 0.5), value: player.isPlaying)
                    .padding(.top, 10)

                VStack(spacing: 4) {
                    Text(player.current?.title ?? "Выбери трек").font(.title2.bold()).lineLimit(1)
                    Text(player.current?.artist ?? "Добавь музыку из «Файлов» через +").foregroundStyle(.secondary)
                }

                Visualizer(levels: player.levels, tint: tint)

                VStack(spacing: 4) {
                    Slider(value: Binding(get: { player.time }, set: { player.seek($0) }), in: 0...max(player.duration, 1))
                        .tint(tint)
                    HStack {
                        Text(Fmt.clock(player.time)); Spacer(); Text("-" + Fmt.clock(player.duration - player.time))
                    }
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }

                HStack(spacing: 44) {
                    Button { player.prev() } label: { Image(systemName: "backward.fill").font(.title) }
                    Button { player.toggle() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 30, weight: .bold))
                            .frame(width: 76, height: 76)
                            .background(tint, in: Circle())
                            .foregroundStyle(.white)
                    }
                    .accessibilityIdentifier("player_toggle")
                    Button { player.next() } label: { Image(systemName: "forward.fill").font(.title) }
                }
                .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Анимация на острове").font(.headline)
                    Picker("Остров", selection: $player.islandStyle) {
                        Text("Эквалайзер").tag("bars")
                        Text("Руна").tag("rune")
                        Text("Пламя").tag("flame")
                    }
                    .pickerStyle(.segmented)
                }
                .card()

                Button { showLyrics = true } label: {
                    Label("Караоке-текст", systemImage: "music.mic").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Треки · \(player.tracks.count)").font(.headline)
                    ForEach(Array(player.tracks.enumerated()), id: \.element.id) { i, t in
                        Button { player.play(index: i) } label: {
                            HStack(spacing: 12) {
                                CoverArt(track: t, size: 44)
                                VStack(alignment: .leading) {
                                    Text(t.title).font(.subheadline.bold()).lineLimit(1)
                                    Text(t.artist).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if player.currentIndex == i {
                                    EqualizerBars(tint: Color(hex: t.colorHex), playing: player.isPlaying, seed: Int(player.time * 3), height: 18)
                                }
                            }
                            .padding(8)
                            .background(player.currentIndex == i ? Theme.card2 : Theme.card, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("track_\(i)")
                        .contextMenu {
                            if !t.bundled { Button("Удалить", systemImage: "trash", role: .destructive) { player.remove(t) } }
                        }
                    }
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("🎧 Плеер")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { importing = true } label: { Image(systemName: "plus") }.accessibilityIdentifier("player_import")
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { Task { await player.importFiles(urls) } }
        }
        .sheet(isPresented: $showLyrics) { LyricsStub() }
    }
}

struct LyricsStub: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("🎤").font(.system(size: 70))
            Text("Караоке — в v0.3").font(.title2.bold())
            Text("Саня найдёт текст песни в интернете, а ИИ на сервере расставит тайминги по словам — подсветка как в Spotify, и всё сохранится для офлайна.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal)
        }
        .padding()
        .presentationDetents([.medium])
    }
}
