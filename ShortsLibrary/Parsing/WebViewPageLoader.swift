import Foundation
import WebKit

@MainActor
final class WebViewPageLoader: NSObject, WKNavigationDelegate {
    static let shared = WebViewPageLoader()

    private var continuation: CheckedContinuation<(String, URL), Error>?
    private var webView: WKWebView?
    private var originalURL: URL?
    private var timeoutWorkItem: DispatchWorkItem?

    func renderedHTML(from url: URL) async throws -> (String, URL) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: configuration)
        self.webView = webView
        self.originalURL = url
        webView.navigationDelegate = self

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let timeout = DispatchWorkItem { [weak self] in
                self?.finish(with: .failure(AppError.parsingFailed("页面加载超时")))
            }
            self.timeoutWorkItem = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
            webView.load(URLRequest(url: url))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] html, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.finish(with: .failure(error))
                    return
                }
                guard let finalURL = webView.url ?? self.originalURL else {
                    self.finish(with: .failure(AppError.parsingFailed("无法获取页面地址")))
                    return
                }
                self.finish(with: .success((html as? String ?? "", finalURL)))
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: .failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(with: .failure(error))
    }

    private func finish(with result: Result<(String, URL), Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil

        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
