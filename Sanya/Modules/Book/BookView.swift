import SwiftUI
import WebKit

/// Книга Мастера — веб-версия внутри приложения, обновляется без пересборки.
final class WebHolder: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    static let home = URL(string: "https://akriv777-png.github.io/kniga-mastera/")!
    let webView: WKWebView
    @Published var loading = true
    @Published var canGoBack = false
    @Published var failed: String?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        // Мост JS → Swift: window.webkit.messageHandlers.sanya.postMessage("haptic")
        webView.configuration.userContentController.add(self, name: "sanya")
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        goHome()
    }

    func goHome() {
        var req = URLRequest(url: Self.home)
        req.cachePolicy = .returnCacheDataElseLoad
        webView.load(req)
    }

    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        if (message.body as? String) == "haptic" { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { loading = true; failed = nil }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loading = false; canGoBack = webView.canGoBack }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { loading = false; failed = error.localizedDescription }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loading = false; failed = error.localizedDescription
    }
}

struct WebContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct BookView: View {
    @StateObject private var web = WebHolder()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            WebContainer(webView: web.webView).ignoresSafeArea(edges: .bottom)
            if web.loading {
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text("Открываю Книгу Мастера…").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let f = web.failed {
                VStack(spacing: 10) {
                    Text("📖").font(.system(size: 60))
                    Text("Нет связи").font(.headline)
                    Text(f).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Повторить") { web.goHome() }.buttonStyle(.borderedProminent)
                }
                .padding(30).background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
            }
        }
        .navigationTitle("📖 Книга Мастера")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { web.webView.goBack() } label: { Image(systemName: "chevron.backward.circle") }.disabled(!web.canGoBack)
                Button { web.goHome() } label: { Image(systemName: "house") }
                Button { web.webView.reload() } label: { Image(systemName: "arrow.clockwise") }
            }
        }
    }
}
