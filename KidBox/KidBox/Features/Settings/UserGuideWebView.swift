//
//  UserGuideWebView.swift
//  KidBox
//
//  Guida all'utilizzo: mostra la pagina web della guida dentro l'app
//  (WKWebView), senza uscire su Safari.
//

import SwiftUI
import WebKit

struct UserGuideWebView: View {
    private static let url = URL(string: "https://kidbox-landing.web.app/guide.html")!

    @State private var isLoading = true

    var body: some View {
        ZStack {
            KBWebView(url: Self.url, isLoading: $isLoading)
            if isLoading {
                ProgressView()
            }
        }
        .navigationTitle("Guida all'utilizzo")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Wrapper minimale di `WKWebView` per mostrare pagine web dentro l'app.
private struct KBWebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) { }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: KBWebView
        init(_ parent: KBWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }

        /// Tutti i link (anche verso altri domini) restano dentro questa WebView:
        /// nessuna uscita dall'app verso Safari.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            decisionHandler(.allow)
        }
    }
}
