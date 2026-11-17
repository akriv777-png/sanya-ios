import SwiftUI
import Combine
import WebKit

/// Книга Мастера — веб-версия внутри приложения, обновляется без пересборки.
final class WebHolder: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    static let home = URL(string: "https://akriv777-png.github.io/kniga-mastera/")!
    let webView: WKWebView
    @Published var loading = true
    @Published var canGoBack = false
    @Published var failed: String?
    @Published var progress: Double = 0
    @Published var everLoaded = false
    private var progressObs: NSKeyValueObservation?

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
        // Smooth progress line + pull-to-refresh
        progressObs = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
            DispatchQueue.main.async { self?.progress = wv.estimatedProgress }
        }
        let refresh = UIRefreshControl()
        refresh.tintColor = UIColor(red: 0.66, green: 0.77, blue: 0.63, alpha: 1)
        refresh.addTarget(self, action: #selector(pulled(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh
        goHome()
    }

    @objc private func pulled(_ sender: UIRefreshControl) {
        Haptics.soft()
        webView.reload()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { sender.endRefreshing() }
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
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loading = false; everLoaded = true; canGoBack = webView.canGoBack }
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
            WebContainer(webView: web.webView)
                .ignoresSafeArea(edges: .bottom)
                .opacity(web.everLoaded ? 1 : 0)
                .scaleEffect(web.everLoaded ? 1 : 0.98)
                .animation(.spring(response: 0.5, dampingFraction: 0.9), value: web.everLoaded)
            if web.loading && !web.everLoaded {
                VStack(spacing: 14) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(DS.Color.sage)
                        .symbolEffect(.pulse)
                    Text("Открываю Книгу Мастера…").font(DS.Font.caption).foregroundStyle(DS.Color.mute)
                }
                .transition(.opacity)
            }
            VStack {
                if web.loading {
                    GeometryReader { g in
                        Capsule().fill(DS.Color.sage)
                            .frame(width: max(8, g.size.width * CGFloat(web.progress)), height: 2)
                            .animation(.easeOut(duration: 0.25), value: web.progress)
                    }
                    .frame(height: 2)
                    .transition(.opacity)
                }
                Spacer()
            }
            if let f = web.failed {
                VStack(spacing: 12) {
                    Text("📖").font(.system(size: 60))
                    Text("Нет связи")
                        .font(DS.Font.displaySemiBold(22))
                        .foregroundStyle(DS.Color.ink)
                    Text(f)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.dim)
                        .multilineTextAlignment(.center)
                    Button("Повторить") { web.goHome() }
                        .buttonStyle(GlassButtonStyle(kind: .primary))
                }
                .padding(24)
                .glassCard()
                .padding()
            }
        }
        .navigationTitle("Книга Мастера")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { Haptics.tap(); web.webView.goBack() } label: {
                    Image(systemName: "chevron.backward.circle")
                        .foregroundStyle(web.canGoBack ? DS.Color.ink : DS.Color.dim)
                }
                .disabled(!web.canGoBack)

                Button { Haptics.tap(); web.goHome() } label: {
                    Image(systemName: "house")
                        .foregroundStyle(DS.Color.ink)
                }

                Button { Haptics.tap(); web.webView.reload() } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(DS.Color.ink)
                }
            }
        }
    }
}
