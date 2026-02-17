import SwiftUI
import WebKit

enum WebCommand {
    case load(String)
    case goBack
    case goForward
    case reload
}

struct SimpleWebView: UIViewRepresentable {
    let initialURL: String
    @Binding var command: WebCommand?

    @Binding var currentURL: String
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var isLoading: Bool

    @ObservedObject var tracker: FaceTracker

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        context.coordinator.attach(webView: webView)

        if let url = URL(string: normalize(initialURL)) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard let cmd = command else { return }

        switch cmd {
        case .load(let text):
            if let url = URL(string: normalize(text)) {
                webView.load(URLRequest(url: url))
            }
        case .goBack:
            if webView.canGoBack { webView.goBack() }
        case .goForward:
            if webView.canGoForward { webView.goForward() }
        case .reload:
            webView.reload()
        }

        // ✅ 여기서 바로 command=nil 하지 말고, 다음 runloop로 미루기
        DispatchQueue.main.async {
            self.command = nil
        }
    }


    private func normalize(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("http://") || t.hasPrefix("https://") { return t }
        // 공백 포함 또는 `.` 미포함 → Google 검색
        if t.contains(" ") || !t.contains(".") {
            let query = t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? t
            return "https://www.google.com/search?q=\(query)"
        }
        return "https://\(t)"
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: SimpleWebView
        private weak var webView: WKWebView?

        private var displayLink: CADisplayLink?
        private var lastTs: CFTimeInterval = 0

        init(_ parent: SimpleWebView) {
            self.parent = parent
        }

        func attach(webView: WKWebView) {
            self.webView = webView
            startDisplayLink()
        }

        private func startDisplayLink() {
            displayLink?.invalidate()
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        @objc private func tick(_ link: CADisplayLink) {
            guard let webView = webView else { return }

            // 고개 스크롤
            guard parent.tracker.hasFace, parent.tracker.isScrollEnabled else { return }

            if lastTs == 0 { lastTs = link.timestamp; return }
            let dt = link.timestamp - lastTs
            lastTs = link.timestamp

            let v = parent.tracker.velocity
            if v == 0 { return }

            let sv = webView.scrollView
            let current = sv.contentOffset.y
            let target = current + CGFloat(dt) * v

            let maxY = max(0, sv.contentSize.height - sv.bounds.height)
            let clampedY = min(max(0, target), maxY)
            sv.setContentOffset(CGPoint(x: 0, y: clampedY), animated: false)
        }

        // WKNavigationDelegate
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.canGoBack = webView.canGoBack
                self.parent.canGoForward = webView.canGoForward
                self.parent.isLoading = false
                self.parent.currentURL = webView.url?.absoluteString ?? self.parent.currentURL
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.canGoBack = webView.canGoBack
                self.parent.canGoForward = webView.canGoForward
                self.parent.isLoading = true
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }

        deinit {
            displayLink?.invalidate()
        }
    }
}
