import Foundation
import Combine
import UIKit

/// Проверяет публичный источник SideStore (`apps.json`) и открывает установку обновления.
/// Никаких секретов: только публичный URL.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    static let sourceURL = URL(string: "https://raw.githubusercontent.com/akriv777-png/sanya-releases/main/apps.json")!
    static let bundleIdentifier = "com.nezich.sanya"

    struct Release: Equatable {
        var version: String
        var buildVersion: String
        var downloadURL: URL
        var localizedDescription: String
        var marketingLabel: String { "v\(version)" }
    }

    @Published private(set) var available: Release?
    @Published private(set) var status: String = ""
    @Published private(set) var checking = false

    private var lastCheck: Date = .distantPast
    private let cooldown: TimeInterval = 15 * 60

    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }
    var currentBuild: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "0"
    }

    var currentLabel: String { "v\(currentVersion) (\(currentBuild))" }

    func checkIfNeeded() {
        guard !AppEnv.isUITest else { return }
        if Date().timeIntervalSince(lastCheck) < cooldown { return }
        Task { await check() }
    }

    func check() async {
        guard !AppEnv.isUITest else { return }
        checking = true
        if status.isEmpty { status = "проверяю…" }
        defer { checking = false }
        do {
            var req = URLRequest(url: Self.sourceURL)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.timeoutInterval = 15
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                status = "не удалось проверить"
                return
            }
            lastCheck = Date()
            let source = try JSONDecoder().decode(AltStoreSource.self, from: data)
            guard let app = source.apps.first(where: { $0.bundleIdentifier == Self.bundleIdentifier }),
                  let ver = app.versions.first,
                  let url = URL(string: ver.downloadURL), !ver.downloadURL.isEmpty else {
                available = nil
                status = "источник пуст"
                return
            }
            let build = ver.buildVersion ?? "0"
            if Self.isNewer(version: ver.version, build: build, than: currentVersion, currentBuild: currentBuild) {
                let rel = Release(
                    version: ver.version,
                    buildVersion: build,
                    downloadURL: url,
                    localizedDescription: ver.localizedDescription ?? ""
                )
                available = rel
                status = "доступна \(rel.marketingLabel)"
            } else {
                available = nil
                status = "у тебя последняя версия"
            }
        } catch {
            status = "не удалось проверить"
        }
    }

    static func isNewer(version: String, build: String, than currentVersion: String, currentBuild: String) -> Bool {
        let v = version.compare(currentVersion, options: .numeric)
        if v != .orderedSame { return v == .orderedDescending }
        return build.compare(currentBuild, options: .numeric) == .orderedDescending
    }

    func openInstall() {
        guard let url = available?.downloadURL else { return }
        openSideStore(action: "install", target: url, fallbackHTTPS: url)
    }

    func openSource() {
        openSideStore(action: "source", target: Self.sourceURL, fallbackHTTPS: Self.sourceURL)
    }

    private func openSideStore(action: String, target: URL, fallbackHTTPS: URL) {
        func make(_ scheme: String) -> URL? {
            var c = URLComponents()
            c.scheme = scheme
            c.host = action
            c.queryItems = [URLQueryItem(name: "url", value: target.absoluteString)]
            return c.url
        }
        guard let side = make("sidestore") else { return }
        UIApplication.shared.open(side) { ok in
            guard !ok else { return }
            if let alt = make("altstore") {
                UIApplication.shared.open(alt) { altOk in
                    if !altOk { UIApplication.shared.open(fallbackHTTPS) }
                }
            } else {
                UIApplication.shared.open(fallbackHTTPS)
            }
        }
    }
}

private struct AltStoreSource: Decodable {
    var apps: [AltStoreApp]
}

private struct AltStoreApp: Decodable {
    var bundleIdentifier: String
    var versions: [AltStoreVersion]
}

private struct AltStoreVersion: Decodable {
    var version: String
    var buildVersion: String?
    var downloadURL: String
    var localizedDescription: String?
}
