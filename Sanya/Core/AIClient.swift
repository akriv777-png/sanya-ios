import Foundation

enum AIError: LocalizedError {
    case notConfigured, badResponse, rateLimited, http(Int)
    var errorDescription: String? {
        switch self {
        case .notConfigured: return "ИИ выключен"
        case .badResponse:   return "ИИ ответил непонятно"
        case .rateLimited:   return "ИИ занят, попробуй через пару секунд"
        case .http(let c):   return "Сервер ИИ: ошибка \(c)"
        }
    }
}

/// Serialises requests: the free default endpoint allows ~1 request per 15 s.
actor AIGate {
    static let shared = AIGate()
    private var last: Date = .distantPast
    func waitTurn(minGap: TimeInterval) async {
        // Reserve the next slot BEFORE sleeping so concurrent callers queue up instead of colliding.
        let slot = max(Date(), last.addingTimeInterval(minGap))
        last = slot
        let wait = slot.timeIntervalSinceNow
        if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
    }
}

/// OpenAI-compatible client. Default backend: Pollinations public endpoint (free, anonymous, no key —
/// so there are no secrets inside the IPA). Settings → «ИИ» can point it at any other compatible server
/// (e.g. your own proxy) with an optional key stored in Keychain. Deep link: sanya://ai?url=…&key=…
enum AIClient {
    static let defaultEndpoint = "https://text.pollinations.ai/openai"

    static var enabled: Bool { UserDefaults.standard.object(forKey: "ai.enabled") as? Bool ?? true }
    static var endpoint: String {
        let s = (UserDefaults.standard.string(forKey: "ai.endpoint") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? defaultEndpoint : s
    }
    static var model: String {
        let m = (UserDefaults.standard.string(forKey: "ai.model") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (m.isEmpty || m == "gpt-4o-mini") && endpoint == defaultEndpoint ? "openai" : (m.isEmpty ? "openai" : m)
    }
    static var isConfigured: Bool { enabled && !AppEnv.isUITest && URL(string: completionsURL) != nil }
    static var usesDefault: Bool { endpoint == defaultEndpoint }

    /// Accepts either a base (…/v1) or a full …/chat/completions URL. Pollinations' URL is used as is.
    static var completionsURL: String {
        let e = endpoint
        if e == defaultEndpoint || e.hasSuffix("/chat/completions") { return e }
        return e.hasSuffix("/") ? e + "chat/completions" : e + "/chat/completions"
    }

    /// Applies sanya://ai?url=…&key=…&model=…
    static func configure(from url: URL) -> Bool {
        guard url.host == "ai", let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        for item in comps.queryItems ?? [] {
            switch item.name {
            case "url":   UserDefaults.standard.set(item.value ?? "", forKey: "ai.endpoint")
            case "model": UserDefaults.standard.set(item.value ?? "", forKey: "ai.model")
            case "key":   Keychain.set(item.value ?? "", for: "ai.key")
            default: break
            }
        }
        UserDefaults.standard.set(true, forKey: "ai.enabled")
        return true
    }

    static func sanyaSystemPrompt() -> String {
        var s = "Ты Саня — дерзкий, тёплый ассистент Егора на iPhone. Говоришь по-русски, на «ты», коротко (1–4 предложения), с юмором и сленгом, без морали. "
        s += "Егор работает в McDonald's Alcoy, живёт в Cocentaina. Никакой магии и фэнтези в ответах. "
        let shifts = ShiftStore.shared.shifts.filter { $0.end > Date() }.sorted { $0.start < $1.start }.prefix(3)
        if !shifts.isEmpty {
            s += "Ближайшие смены: " + shifts.map { "\(Fmt.day($0.start)) \(Fmt.time($0.start))–\(Fmt.time($0.end))" }.joined(separator: "; ") + ". "
        }
        s += "Питомец «\(PetStore.shared.name)» сейчас: \(PetEngine.shared.currentEmotion.name)."
        return s
    }

    static func complete(_ history: [ChatMessage], system: String) async throws -> String {
        let msgs = history.suffix(14).map { (role: $0.role, content: $0.text) }
        return try await chat(system: system, messages: Array(msgs))
    }

    static func chat(system: String, messages: [(role: String, content: String)],
                     temperature: Double = 0.8, maxTokens: Int = 600) async throws -> String {
        guard isConfigured, let url = URL(string: completionsURL) else { throw AIError.notConfigured }
        var payload: [[String: String]] = [["role": "system", "content": system]]
        payload += messages.map { ["role": $0.role, "content": $0.content] }
        let body: [String: Any] = ["model": model, "messages": payload, "temperature": temperature,
                                   "max_tokens": maxTokens, "private": true]
        for attempt in 0..<2 {
            await AIGate.shared.waitTurn(minGap: usesDefault ? 15 : 1)
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 45
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let key = Keychain.get("ai.key")
            if !key.isEmpty { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 200
            if code == 429 || code == 503 {
                if attempt == 0 { continue }
                throw AIError.rateLimited
            }
            guard (200..<300).contains(code) else { throw AIError.http(code) }
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let choices = obj?["choices"] as? [[String: Any]],
               let msg = choices.first?["message"] as? [String: Any],
               let content = msg["content"] as? String,
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let reply = obj?["reply"] as? String { return reply }
            throw AIError.badResponse
        }
        throw AIError.rateLimited
    }

    /// Asks for JSON and decodes the first array/object found in the reply (tolerates ```json fences).
    static func json<T: Decodable>(_ type: T.Type, system: String, user: String) async throws -> T {
        let text = try await chat(system: system + " Отвечай ТОЛЬКО валидным JSON без пояснений.",
                                  messages: [(role: "user", content: user)], temperature: 0.2, maxTokens: 900)
        let chars = Array(text)
        guard let start = chars.firstIndex(where: { $0 == "[" || $0 == "{" }) else { throw AIError.badResponse }
        let close: Character = chars[start] == "[" ? "]" : "}"
        guard let end = chars.lastIndex(of: close), end > start else { throw AIError.badResponse }
        let slice = String(chars[start...end])
        guard let data = slice.data(using: .utf8) else { throw AIError.badResponse }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// One short in-character line for the pet (bubbles / suggestions). Returns nil on any failure.
    static func petLine(_ situation: String) async -> String? {
        guard isConfigured else { return nil }
        let sys = "Ты мрачный эмо-питомец-чиби «\(PetStore.shared.name)» в телефоне Егора. Одна короткая реплика (до 12 слов), от первого лица, сарказм, сленг, без магии, без морали, без кавычек."
        guard let t = try? await chat(system: sys, messages: [(role: "user", content: situation)], temperature: 0.95, maxTokens: 80) else { return nil }
        let line = t.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "«", with: "").replacingOccurrences(of: "»", with: "")
            .components(separatedBy: "\n").first ?? t
        return line.count > 120 ? String(line.prefix(120)) : line
    }
}
