import Foundation
import UserNotifications
import ActivityKit
import Security

enum DiskStore {
    static var docs: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    static func url(_ name: String) -> URL { docs.appendingPathComponent(name) }
    static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let d = try? Data(contentsOf: url(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }
    static func save<T: Encodable>(_ value: T, _ name: String) {
        if let d = try? JSONEncoder().encode(value) { try? d.write(to: url(name), options: .atomic) }
    }
}

enum Notifier {
    static func requestIfNeeded() {
        if AppEnv.isUITest { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
    static func schedule(id: String, title: String, body: String, at date: Date) {
        guard date > Date() else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let req = UNNotificationRequest(identifier: id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        UNUserNotificationCenter.current().add(req)
    }
    static func cancel(ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}

/// Управляет Live Activity (Dynamic Island). Одна активность на каждый kind.
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private var activities: [String: Activity<SanyaActivityAttributes>] = [:]

    func has(_ kind: String) -> Bool { activities[kind] != nil }

    func start(kind: String, symbol: String, state: SanyaActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let old = activities[kind]
        activities[kind] = nil
        Task { @MainActor in
            if let old { await old.end(nil, dismissalPolicy: .immediate) }
            do {
                let a = try Activity.request(attributes: SanyaActivityAttributes(kind: kind, symbol: symbol),
                                             content: .init(state: state, staleDate: nil), pushType: nil)
                self.activities[kind] = a
            } catch {
                print("LiveActivity error:", error)
            }
        }
    }

    func update(kind: String, state: SanyaActivityAttributes.ContentState) {
        guard let a = activities[kind] else { return }
        Task { await a.update(.init(state: state, staleDate: nil)) }
    }

    func end(kind: String) {
        guard let a = activities[kind] else { return }
        activities[kind] = nil
        Task { await a.end(nil, dismissalPolicy: .immediate) }
    }

    func endAll() {
        Task {
            for a in Activity<SanyaActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }
}

enum Keychain {
    static func set(_ value: String, for key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
        guard !value.isEmpty else { return }
        var add = q
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
    static func get(_ key: String) -> String {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return "" }
        return String(decoding: d, as: UTF8.self)
    }
}

enum Regex {
    static func matches(_ pattern: String, _ s: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
    }
}
