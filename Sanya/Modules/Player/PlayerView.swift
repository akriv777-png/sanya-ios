import SwiftUI
import UniformTypeIdentifiers

struct CoverArt: View {
    let track: Track?
    let size: CGFloat
    var symbol: String = "music.note"

    var body: some View {
        let tint = DS.Color.sage
        ZStack {
            if let t = track, let img = PlayerModel.shared.artwork(for: t) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: [tint.opacity(0.4), DS.Color.glass], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: symbol)
                    .font(.system(size: size * 0.36, weight: .light))
                    .foregroundStyle(DS.Color.ink.opacity(0.85))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .stroke(DS.Color.line, lineWidth: 1)
        )
    }
}

struct Visualizer: View {
    let levels: [CGFloat]
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(levels.indices, id: \.self) { i in
                Capsule()
                    .fill(LinearGradient(colors: [tint, tint.opacity(0.3)], startPoint: .top, endPoint: .bottom))
                    .frame(height: max(4, 56 * levels[i]))
            }
        }
        .frame(height: 56)
        .animation(.easeOut(duration: 0.08), value: levels)
    }
}

struct PlayerView: View {
    @ObservedObject private var player = PlayerModel.shared
    @State private var importing = false
    @State private var showLyrics = false

    var body: some View {
        ZStack {
            AtmosphereBackground()
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Big Cover
                    CoverArt(track: player.current, size: 240, symbol: player.islandSymbol)
                        .scaleEffect(player.isPlaying ? 1.0 : 0.94)
                        .shadow(color: .black.opacity(0.55), radius: 24, y: 12)
                        .animation(.spring(duration: 0.5), value: player.isPlaying)
                        .padding(.top, 8)

                    // Title & Artist
                    VStack(spacing: 6) {
                        Text(player.current?.title ?? "Выбери трек")
                            .font(DS.Font.display(30))
                            .foregroundStyle(DS.Color.ink)
                            .lineLimit(1)
                        Text(player.current?.artist ?? "Добавь музыку из «Файлов» через +")
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Color.mute)
                            .lineLimit(1)
                    }

                    // Visualizer
                    Visualizer(levels: player.levels, tint: DS.Color.sage)

                    // Scrubber
                    VStack(spacing: 6) {
                        Slider(
                            value: Binding(get: { player.time }, set: { player.seek($0) }),
                            in: 0...max(player.duration, 1)
                        )
                        .tint(DS.Color.sage)

                        HStack {
                            Text(Fmt.clock(player.time))
                            Spacer()
                            Text("-" + Fmt.clock(max(0, player.duration - player.time)))
                        }
                        .font(DS.Font.caption)
                        .monospacedDigit()
                        .foregroundStyle(DS.Color.dim)
                    }
                    .padding(.horizontal, 4)

                    // Controls
                    HStack(spacing: 36) {
                        IconButton(systemName: "backward.fill", tint: DS.Color.ink, size: 48) {
                            player.prev()
                        }

                        Button {
                            player.toggle()
                        } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 28, weight: .bold))
                                .frame(width: 72, height: 72)
                                .background(DS.Color.sage, in: Circle())
                                .foregroundStyle(Color(hex: "18221B"))
                                .shadow(color: DS.Color.sage.opacity(0.3), radius: 12)
                        }
                        .accessibilityIdentifier("player_toggle")

                        IconButton(systemName: "forward.fill", tint: DS.Color.ink, size: 48) {
                            player.next()
                        }
                    }

                    // Island styles: bars / wave / pulse
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader("Стиль на острове")
                        HStack(spacing: 8) {
                            DSChip(title: "Столбики", selected: player.islandStyle == "bars") {
                                player.islandStyle = "bars"
                            }
                            DSChip(title: "Волна", selected: player.islandStyle == "wave") {
                                player.islandStyle = "wave"
                            }
                            DSChip(title: "Пульс", selected: player.islandStyle == "pulse") {
                                player.islandStyle = "pulse"
                            }
                        }
                    }
                    .glassCard()

                    // Karaoke button
                    Button {
                        showLyrics = true
                    } label: {
                        Label("Караоке-текст", systemImage: "music.mic")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GlassButtonStyle(kind: .secondary))

                    // Track list
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader("Треки · \(player.tracks.count)")

                        ForEach(Array(player.tracks.enumerated()), id: \.element.id) { i, t in
                            Button {
                                player.play(index: i)
                            } label: {
                                HStack(spacing: 12) {
                                    CoverArt(track: t, size: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(t.title)
                                            .font(DS.Font.ui(14, weight: .semibold))
                                            .foregroundStyle(DS.Color.ink)
                                            .lineLimit(1)
                                        Text(t.artist)
                                            .font(DS.Font.caption)
                                            .foregroundStyle(DS.Color.mute)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if player.currentIndex == i {
                                        EqualizerBars(tint: DS.Color.sage, playing: player.isPlaying, seed: Int(player.time * 3), height: 18)
                                    }
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                                        .fill(player.currentIndex == i ? DS.Color.glass2 : DS.Color.glass)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                                        .stroke(player.currentIndex == i ? DS.Color.sage.opacity(0.4) : DS.Color.line, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("track_\(i)")
                            .contextMenu {
                                if !t.bundled {
                                    Button("Удалить", systemImage: "trash", role: .destructive) {
                                        player.remove(t)
                                    }
                                }
                            }
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .navigationTitle("Плеер")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    importing = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(DS.Color.ink)
                }
                .accessibilityIdentifier("player_import")
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                Task { await player.importFiles(urls) }
            }
        }
        .sheet(isPresented: $showLyrics) {
            LyricsStub()
        }
    }
}

struct LyricsStub: View {
    var body: some View {
        ZStack {
            AtmosphereBackground().ignoresSafeArea()
            VStack(spacing: 16) {
                Text("🎤")
                    .font(.system(size: 64))
                Text("Караоке — в v0.3")
                    .font(DS.Font.display(28))
                    .foregroundStyle(DS.Color.ink)
                Text("Саня найдёт текст песни в интернете, а ИИ на сервере расставит тайминги по словам — подсветка как в Spotify, и всё сохранится для офлайна.")
                    .font(DS.Font.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(DS.Color.mute)
                    .padding(.horizontal)
            }
            .padding(24)
            .glassCard()
            .padding()
        }
        .presentationDetents([.medium])
    }
}
