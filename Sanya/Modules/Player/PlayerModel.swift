import Foundation
import AVFoundation
import MediaPlayer
import UIKit
import CoreImage

struct Track: Codable, Identifiable, Hashable {
    var id = UUID()
    var fileName: String
    var title: String
    var artist: String
    var colorHex: String
    var artFile: String? = nil
    var bundled: Bool = false
}

final class PlayerModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = PlayerModel()

    @Published var tracks: [Track] = []
    @Published var currentIndex: Int?
    @Published var isPlaying = false
    @Published var time: Double = 0
    @Published var duration: Double = 0
    @Published var levels: [CGFloat] = Array(repeating: 0.05, count: 32)
    @Published var islandStyle: String = UserDefaults.standard.string(forKey: "player.island") ?? "bars" {
        didSet { UserDefaults.standard.set(islandStyle, forKey: "player.island"); if current != nil { pushActivity(restart: true) } }
    }

    private var player: AVAudioPlayer?
    private var ticker: Timer?
    private var tickCount = 0
    private var phase: Double = 0

    var current: Track? {
        guard let i = currentIndex, tracks.indices.contains(i) else { return nil }
        return tracks[i]
    }

    var islandSymbol: String {
        switch islandStyle {
        case "rune": return "seal.fill"
        case "flame": return "flame.fill"
        default: return "music.note"
        }
    }

    override init() {
        super.init()
        tracks = DiskStore.load([Track].self, "tracks.json") ?? []
        if !tracks.contains(where: { $0.bundled }) {
            tracks.insert(Track(fileName: "demo.m4a", title: "Руны в ночи (демо)", artist: "Саня", colorHex: "8A5CFF", bundled: true), at: 0)
        }
        setupRemote()
    }

    static var musicDir: URL {
        let d = DiskStore.docs.appendingPathComponent("Music", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func url(for t: Track) -> URL? {
        t.bundled ? Bundle.main.url(forResource: "demo", withExtension: "m4a") : Self.musicDir.appendingPathComponent(t.fileName)
    }

    func artwork(for t: Track) -> UIImage? {
        guard let f = t.artFile else { return nil }
        return UIImage(contentsOfFile: Self.musicDir.appendingPathComponent(f).path)
    }

    // MARK: управление

    func play(index: Int) {
        guard tracks.indices.contains(index), let u = url(for: tracks[index]) else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: u)
            p.delegate = self
            p.isMeteringEnabled = true
            p.prepareToPlay()
            p.play()
            player = p
            currentIndex = index
            duration = p.duration
            isPlaying = true
            startTicker()
            updateNowPlaying()
            pushActivity(restart: true)
        } catch {
            print("play error", error)
        }
    }

    func toggle() {
        guard let p = player else { play(index: currentIndex ?? 0); return }
        if p.isPlaying { p.pause(); isPlaying = false } else { p.play(); isPlaying = true }
        updateNowPlaying()
        pushActivity()
    }

    func next() { guard !tracks.isEmpty else { return }; play(index: ((currentIndex ?? -1) + 1) % tracks.count) }
    func prev() {
        guard !tracks.isEmpty else { return }
        if time > 3 { seek(0); return }
        play(index: ((currentIndex ?? 0) - 1 + tracks.count) % tracks.count)
    }

    func seek(_ t: Double) {
        player?.currentTime = t
        time = t
        updateNowPlaying()
        pushActivity()
    }

    func remove(_ t: Track) {
        guard !t.bundled, let i = tracks.firstIndex(of: t) else { return }
        if currentIndex == i { player?.stop(); player = nil; isPlaying = false; currentIndex = nil; LiveActivityManager.shared.end(kind: "player") }
        try? FileManager.default.removeItem(at: Self.musicDir.appendingPathComponent(t.fileName))
        tracks.remove(at: i)
        save()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { self.next() }
    }

    // MARK: визуализация

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        guard let p = player else { return }
        time = p.currentTime
        if p.isPlaying {
            p.updateMeters()
            let db = Double(p.averagePower(forChannel: 0))
            let base = max(0.08, pow(10, db / 25))
            phase += 0.32
            levels = (0..<levels.count).map { i in
                let w = (sin(phase + Double(i) * 0.55) + sin(phase * 1.7 + Double(i) * 1.1) + 2) / 4
                return CGFloat(min(1, base * (0.35 + w * 1.1)))
            }
            tickCount += 1
            if tickCount % 30 == 0 { pushActivity() }   // ~раз в 1.5 c — двигаем столбики на острове
        } else {
            levels = levels.map { max(0.05, $0 * 0.85) }
        }
    }

    // MARK: экран блокировки и остров

    private func setupRemote() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in if self?.isPlaying == false { self?.toggle() }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in if self?.isPlaying == true { self?.toggle() }; return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in self?.toggle(); return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in self?.next(); return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in self?.prev(); return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            if let e = e as? MPChangePlaybackPositionCommandEvent { self?.seek(e.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let t = current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: t.title,
            MPMediaItemPropertyArtist: t.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player?.currentTime ?? 0,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let img = artwork(for: t) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func pushActivity(restart: Bool = false) {
        guard let t = current else { return }
        let elapsed = player?.currentTime ?? 0
        let start = Date().addingTimeInterval(-elapsed)
        let state = SanyaActivityAttributes.ContentState(
            title: t.title, subtitle: t.artist, start: start, end: start.addingTimeInterval(max(duration, 1)),
            colorHex: t.colorHex, isPlaying: isPlaying, progress: duration > 0 ? elapsed / duration : 0)
        if restart || !LiveActivityManager.shared.has("player") {
            LiveActivityManager.shared.start(kind: "player", symbol: islandSymbol, state: state)
        } else {
            LiveActivityManager.shared.update(kind: "player", state: state)
        }
    }

    // MARK: импорт

    func importFiles(_ urls: [URL]) async {
        for u in urls {
            let scoped = u.startAccessingSecurityScopedResource()
            defer { if scoped { u.stopAccessingSecurityScopedResource() } }
            let id = UUID()
            let ext = u.pathExtension.isEmpty ? "mp3" : u.pathExtension
            let dest = Self.musicDir.appendingPathComponent("\(id.uuidString).\(ext)")
            do { try FileManager.default.copyItem(at: u, to: dest) } catch { continue }

            var title = u.deletingPathExtension().lastPathComponent
            var artist = "Неизвестный исполнитель"
            var color = "FF3B5C"
            var artFile: String?
            let asset = AVURLAsset(url: dest)
            if let meta = try? await asset.load(.commonMetadata) {
                for item in meta {
                    guard let key = item.commonKey else { continue }
                    if key == .commonKeyTitle, let v = try? await item.load(.stringValue) { title = v }
                    if key == .commonKeyArtist, let v = try? await item.load(.stringValue) { artist = v }
                    if key == .commonKeyArtwork, let d = try? await item.load(.dataValue), let img = UIImage(data: d) {
                        let name = "\(id.uuidString).jpg"
                        try? img.jpegData(compressionQuality: 0.85)?.write(to: Self.musicDir.appendingPathComponent(name))
                        artFile = name
                        color = img.vividAverageHex
                    }
                }
            }
            let track = Track(id: id, fileName: dest.lastPathComponent, title: title, artist: artist, colorHex: color, artFile: artFile)
            await MainActor.run {
                self.tracks.append(track)
                self.save()
            }
        }
    }

    private func save() { DiskStore.save(tracks, "tracks.json") }
}

extension UIImage {
    /// Средний цвет обложки, «разогнанный» по яркости — для эквалайзера на острове.
    var vividAverageHex: String {
        guard let ci = CIImage(image: self),
              let out = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: ci, kCIInputExtentKey: CIVector(cgRect: ci.extent)])?.outputImage
        else { return "FF3B5C" }
        var px = [UInt8](repeating: 0, count: 4)
        CIContext().render(out, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                           format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        let mx = max(1, Double(max(px[0], px[1], px[2])))
        let k = 255.0 / mx
        func c(_ v: UInt8) -> Int { min(255, Int(Double(v) * k)) }
        return String(format: "%02X%02X%02X", c(px[0]), c(px[1]), c(px[2]))
    }
}
