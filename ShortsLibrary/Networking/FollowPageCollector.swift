import Foundation
import WebKit

@MainActor
final class FollowPageCollector: NSObject, WKNavigationDelegate {
    static let shared = FollowPageCollector()

    private var continuation: CheckedContinuation<[FollowedAccountDraft], Error>?
    private var webView: WKWebView?
    private var collected: [FollowedAccountDraft] = []
    private var scrollCount = 0
    private var timeoutWorkItem: DispatchWorkItem?

    func collect(platform: MediaSource) async throws -> [FollowedAccountDraft] {
        let url: URL
        switch platform {
        case .douyin:
            url = URL(string: "https://www.douyin.com/user/self?showTab=following")!
        case .kuaishou:
            url = URL(string: "https://www.kuaishou.com/profile")!
        default:
            throw AppError.parsingFailed("该平台暂不支持页面采集，请手动录入")
        }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
        self.webView = webView
        self.collected = []
        self.scrollCount = 0
        webView.navigationDelegate = self

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let timeout = DispatchWorkItem { [weak self] in
                self?.finish(with: .success(self?.collected ?? []))
            }
            self.timeoutWorkItem = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: timeout)
            webView.load(URLRequest(url: url))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            await self.extractOnce(webView, script: Self.script(for: webView.url))
            self.scheduleScroll(webView)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: .failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(with: .failure(error))
    }

    private func scheduleScroll(_ webView: WKWebView) {
        guard scrollCount < 8 else {
            finish(with: .success(collected))
            return
        }
        scrollCount += 1
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            _ = try? await webView.evaluateJavaScript("window.scrollBy(0, 900);")
            await self.extractOnce(webView, script: Self.script(for: webView.url))
            self.scheduleScroll(webView)
        }
    }

    private func extractOnce(_ webView: WKWebView, script: String) async {
        guard let result = try? await webView.evaluateJavaScript(script),
              let json = result as? String,
              let data = json.data(using: .utf8),
              let items = try? JSONDecoder().decode([FollowedAccountDraft].self, from: data) else { return }
        for item in items where !item.platformUserId.isEmpty {
            if !collected.contains(where: { $0.platformUserId == item.platformUserId }) {
                collected.append(item)
            }
        }
    }

    private func finish(with result: Result<[FollowedAccountDraft], Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
        switch result {
        case .success(let value): continuation.resume(returning: value)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }

    private static func script(for url: URL?) -> String {
        let host = url?.host()?.lowercased() ?? ""
        return host.contains("kuaishou") ? kuaishouScript : douyinScript
    }

    private static let douyinScript = """
    (() => {
      const out = [];
      document.querySelectorAll('a[href*="/user/"]').forEach(a => {
        const href = a.getAttribute('href') || '';
        const m = href.match(/\\/user\\/([A-Za-z0-9_\\-]{8,})/);
        if (!m) return;
        const name = (a.innerText || a.textContent || '').trim();
        if (!name || name.length > 80) return;
        const img = a.querySelector('img');
        out.push(JSON.stringify({
          platformUserId: m[1],
          secUserId: m[1],
          displayName: name,
          remark: null,
          groupName: null,
          avatarURLString: img ? (img.src || '') : null
        }));
      });
      return '[' + out.join(',') + ']';
    })()
    """

    private static let kuaishouScript = """
    (() => {
      const out = [];
      document.querySelectorAll('a[href*="/profile/"]').forEach(a => {
        const href = a.getAttribute('href') || '';
        const m = href.match(/\\/profile\\/([A-Za-z0-9_\\-]{6,})/);
        if (!m) return;
        const name = (a.innerText || a.textContent || '').trim();
        if (!name || name.length > 80) return;
        const img = a.querySelector('img');
        out.push(JSON.stringify({
          platformUserId: m[1],
          secUserId: null,
          displayName: name,
          remark: null,
          groupName: null,
          avatarURLString: img ? (img.src || '') : null
        }));
      });
      return '[' + out.join(',') + ']';
    })()
    """
}
