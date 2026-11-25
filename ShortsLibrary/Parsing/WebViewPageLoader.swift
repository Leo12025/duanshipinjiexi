import Foundation
import WebKit

typealias WebViewRenderResult = (html: String, url: URL, capturedJSON: [String])

@MainActor
final class WebViewPageLoader: NSObject, WKNavigationDelegate {
    static func load(from url: URL) async throws -> (String, URL) {
        let result = try await loadDetailed(from: url)
        return (result.html, result.url)
    }

    static func loadDetailed(from url: URL) async throws -> WebViewRenderResult {
        let loader = WebViewPageLoader()
        return try await loader.renderedHTML(from: url)
    }

    private var continuation: CheckedContinuation<WebViewRenderResult, Error>?
    private var webView: WKWebView?
    private var originalURL: URL?
    private var timeoutWorkItem: DispatchWorkItem?

    private override init() {}

    private static let captureScript = #"""
    (() => {
      if (window.__douyinCapturedJSON) return;
      window.__douyinCapturedJSON = [];
      const markers = [
        'aweme_detail', 'aweme_details', 'finder', 'objectNonceId',
        'video_url', 'download_url', 'play_addr', 'weixin.qq.com'
      ];
      const store = (text) => {
        if (!text || window.__douyinCapturedJSON.length >= 12) return;
        if (!markers.some((marker) => text.includes(marker))) return;
        window.__douyinCapturedJSON.push(text);
      };
      const originalFetch = window.fetch.bind(window);
      window.fetch = function(...args) {
        return originalFetch(...args).then((response) => {
          try {
            response.clone().text().then(store).catch(() => {});
          } catch (_) {}
          return response;
        });
      };
      const originalSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.send = function(...args) {
        this.addEventListener('loadend', function() {
          try { store(this.responseText); } catch (_) {}
        });
        return originalSend.apply(this, args);
      };
    })();
    """#

    private func renderedHTML(from url: URL) async throws -> WebViewRenderResult {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.captureScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            let script = """
            (() => ({
              html: document.documentElement.outerHTML,
              url: location.href,
              captured: window.__douyinCapturedJSON || []
            }))()
            """
            webView.evaluateJavaScript(script) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let error {
                        self.finish(with: .failure(error))
                        return
                    }
                    guard let dict = result as? [String: Any],
                          let finalURL = URL(string: dict["url"] as? String ?? "")
                            ?? webView.url ?? self.originalURL else {
                        self.finish(with: .failure(AppError.parsingFailed("无法获取页面地址")))
                        return
                    }
                    let captured = (dict["captured"] as? [String]) ?? []
                    self.finish(with: .success((
                        html: dict["html"] as? String ?? "",
                        url: finalURL,
                        capturedJSON: captured
                    )))
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: .failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(with: .failure(error))
    }

    private func finish(with result: Result<WebViewRenderResult, Error>) {
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
