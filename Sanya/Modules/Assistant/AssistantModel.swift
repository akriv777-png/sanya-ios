import Foundation
import Combine
import AVFoundation
import Speech

struct ChatMessage: Codable, Identifiable, Hashable {
    var id = UUID()
    var role: String   // "user" | "assistant"
    var text: String
    var date = Date()
}

enum LocalAction {
    case open(ModuleID)
    case timer(Int)
    case music
}

/// Локальные «мозги»: команды модулям работают без сервера.
enum LocalBrain {
    static func handle(_ text: String) -> (String, LocalAction?)? {
        let t = text.lowercased()
        if t.contains("таймер"), let n = Regex.matches(#"(\d+)"#, t).first.flatMap({ Int($0[1]) }) {
            let word = n == 1 ? "минуту" : (2...4).contains(n % 10) && !(12...14).contains(n % 100) ? "минуты" : "минут"
            return ("Ставлю таймер на \(n) \(word). Смотри на остров ⏱", .timer(n))
        }
        if t.contains("включи музык") || t.contains("включи плеер") || t.contains("поставь музык") {
            return ("Включаю музыку 🎧", .music)
        }
        if t.contains("открой") || t.contains("открыть") || t.contains("покажи") {
            let map: [(String, ModuleID)] = [("смен", .shifts), ("график", .shifts), ("книг", .book), ("мастер", .book),
                                             ("таймер", .timers), ("плеер", .player), ("музык", .player)]
            if let m = map.first(where: { t.contains($0.0) }) {
                return ("Открываю «\(Modules.info(m.1).title)»", .open(m.1))
            }
        }
        if t.contains("смена") || t.contains("смену") || t.contains("работаю") {
            if let s = ShiftStore.shared.nextShift {
                return ("Следующая смена: \(Fmt.longDay(s.start)), \(Fmt.time(s.start))–\(Fmt.time(s.end)) (\(Fmt.hours(s.hours))). Напомню заранее 👌", nil)
            }
            return ("Смен пока нет. Скинь скрин графика в модуль «Смены».", nil)
        }
        if t.contains("что ты умеешь") || t.contains("помощь") || t == "?" {
            return ("Пока умею:\n• «Открой смены / книгу / плеер / таймеры»\n• «Таймер на 5 минут» — с отсчётом на острове\n• «Когда моя смена?»\n• «Включи музыку»\nА с сервером ИИ (⚙︎) — болтать обо всём.", nil)
        }
        return nil
    }
}


final class AssistantModel: ObservableObject {
    static let shared = AssistantModel()

    @Published var messages: [ChatMessage]
    @Published var input = ""
    @Published var thinking = false
    private let synth = AVSpeechSynthesizer()

    init() {
        let saved = AppEnv.isUITest ? nil : DiskStore.load([ChatMessage].self, "chat.json")
        messages = saved ?? [ChatMessage(role: "assistant", text: "Йо, Егор 👋 Я Саня. Пиши или жми на микрофон. Скажи «что ты умеешь», и я покажу.")]
    }

    func clear() {
        messages = [ChatMessage(role: "assistant", text: "Чистый лист. Чем займёмся?")]
        save()
    }

    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        let userMsg = ChatMessage(role: "user", text: text)
        messages.append(userMsg)
        save()
        EventBus.shared.emit(.chatMessage(fromUser: true))

        if let local = LocalBrain.handle(text) {
            let (reply, action) = local
            respond(reply, delay: 0.6) { if let action { self.run(action) } }
            return
        }
        guard AIClient.isConfigured else {
            respond("ИИ выключен в ⚙︎ → «ИИ». Пока понимаю только команды — попробуй «что ты умеешь».", delay: 0.8)
            return
        }
        thinking = true
        let history = messages
        Task {
            var reply: String
            do { reply = try await AIClient.complete(history, system: AIClient.sanyaSystemPrompt()) } catch { reply = "⚠️ \(error.localizedDescription)" }
            await MainActor.run { self.respond(reply, delay: 0) }
        }
    }

    private func respond(_ text: String, delay: Double, then: (() -> Void)? = nil) {
        thinking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.thinking = false
            self.messages.append(ChatMessage(role: "assistant", text: text))
            self.save()
            self.speak(text)
            EventBus.shared.emit(.chatMessage(fromUser: false))
            then?()
        }
    }

    private func run(_ action: LocalAction) {
        switch action {
        case .open(let m):
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { Router.shared.go(m) }
        case .timer(let n):
            TimerStore.shared.start(title: "Таймер Сани", minutes: Double(n))
        case .music:
            PlayerModel.shared.play(index: PlayerModel.shared.currentIndex ?? 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { Router.shared.go(.player) }
        }
    }

    private func speak(_ text: String) {
        let enabled = UserDefaults.standard.object(forKey: "ai.speak") as? Bool ?? true
        guard enabled, !AppEnv.isUITest, !PlayerModel.shared.isPlaying else { return }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "ru-RU")
        u.rate = 0.52
        synth.speak(u)
    }

    private func save() {
        if !AppEnv.isUITest { DiskStore.save(Array(messages.suffix(200)), "chat.json") }
    }
}

/// Распознавание речи на телефоне (ru-RU).
final class SpeechRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var level: CGFloat = 0
    @Published var error: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() { isRecording ? stop() : start() }

    func start() {
        error = nil
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else { self.error = "Нет доступа к распознаванию речи"; return }
                AVAudioApplication.requestRecordPermission { ok in
                    DispatchQueue.main.async {
                        if ok { self.begin() } else { self.error = "Нет доступа к микрофону" }
                    }
                }
            }
        }
    }

    private func begin() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            request = req
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buf, _ in
                req.append(buf)
                let lvl = SpeechRecognizer.rms(buf)
                DispatchQueue.main.async { self?.level = lvl }
            }
            engine.prepare()
            try engine.start()
            transcript = ""
            isRecording = true
            task = recognizer?.recognitionTask(with: req) { [weak self] result, err in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if err != nil || (result?.isFinal ?? false) { self.stop() }
                }
            }
        } catch {
            self.error = "Микрофон недоступен"
            stop()
        }
    }

    func stop() {
        guard isRecording || engine.isRunning else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        level = 0
        isRecording = false
    }

    static func rms(_ buf: AVAudioPCMBuffer) -> CGFloat {
        guard let ch = buf.floatChannelData?[0] else { return 0 }
        let n = Int(buf.frameLength)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<n { sum += ch[i] * ch[i] }
        return CGFloat(min(1, sqrt(sum / Float(n)) * 8))
    }
}
