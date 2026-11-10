import SwiftUI
import WebKit

@main
struct GeneratedAppMain: App {
    var body: some Scene {
        WindowGroup {
            WebAppScreen()
                .ignoresSafeArea()
        }
    }
}

struct WebAppScreen: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .black
        if let url = Bundle.main.url(forResource: "webapp", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.loadHTMLString("<html><body style='background:#101225;color:white'>App not found</body></html>", baseURL: nil)
        }
        return webView
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
