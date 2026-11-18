import AVFoundation

/// Ambience loops + one-shot SFX for the game. All sounds are synthesised (tools/gen_reality_audio.py).
final class RLAudio {
    static let shared = RLAudio()
    var muted = false { didSet { if muted { stopAll() } else if running { apply() } } }
    private var loops: [String: AVAudioPlayer] = [:]
    private var live: [AVAudioPlayer] = []
    private var data: [String: Data] = [:]
    private var running = false
    private var target: [String: Float] = [:]

    private func url(_ n: String) -> URL? { Bundle.main.url(forResource: n, withExtension: "wav") }

    func start() {
        running = true
        for n in ["amb_rain", "amb_city", "amb_room"] where loops[n] == nil {
            guard let u = url(n), let p = try? AVAudioPlayer(contentsOf: u) else { continue }
            p.numberOfLoops = -1; p.volume = 0; p.prepareToPlay()
            loops[n] = p
        }
        apply()
    }

    func stop() { running = false; stopAll() }

    private func stopAll() { loops.values.forEach { $0.setVolume(0, fadeDuration: 0.4) }; DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in if self?.muted == true || self?.running == false { self?.loops.values.forEach { $0.pause() } } } }

    func ambience(zone: RLZone, rain: Double) {
        let indoor = zone.indoor
        target = ["amb_rain": Float(indoor ? 0.12 + rain * 0.1 : 0.25 + rain * 0.5),
                  "amb_city": Float(indoor ? 0.08 : 0.4),
                  "amb_room": Float(indoor ? 0.5 : 0)]
        apply()
    }

    private func apply() {
        guard running, !muted else { return }
        for (n, p) in loops {
            if !p.isPlaying { p.play() }
            p.setVolume(target[n] ?? 0, fadeDuration: 0.8)
        }
    }

    func sfx(_ name: String, volume: Float = 0.6) {
        guard !muted else { return }
        let key = "sfx_" + name
        if data[key] == nil, let u = url(key) { data[key] = try? Data(contentsOf: u) }
        guard let d = data[key], let p = try? AVAudioPlayer(data: d) else { return }
        p.volume = volume
        p.play()
        live.append(p)
        live.removeAll { !$0.isPlaying && $0 !== p }
    }

    func nextBarTrack() { sfx("blip", volume: 0.4) }
}
