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
    private var isCollecting = false

    func collect(platform: MediaSource) async throws -> [FollowedAccountDraft] {
        guard !isCollecting else {
            throw AppError.parsingFailed("正在同步关注列表，请稍后再试")
        }
        isCollecting = true

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
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.captureScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
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
            try? await Task.sleep(nanoseconds: 900_000_000)
            _ = try? await webView.evaluateJavaScript(Self.clickFollowTabScript(for: webView.url))
            try? await Task.sleep(nanoseconds: 900_000_000)
            await self.extractCapturedJSON(webView)
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
            try? await Task.sleep(nanoseconds: 700_000_000)
            _ = try? await webView.evaluateJavaScript("window.scrollBy(0, 900);")
            await self.extractCapturedJSON(webView)
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
        self.isCollecting = false
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

    private static func clickFollowTabScript(for url: URL?) -> String {
        let host = url?.host()?.lowercased() ?? ""
        if host.contains("kuaishou") {
            return """
            (() => {
              const candidates = Array.from(document.querySelectorAll('div,span,a,button'))
                .filter(el => ['关注','following'].includes((el.innerText || '').trim().toLowerCase()));
              const target = candidates.reverse().find(el => el.getBoundingClientRect().width > 0);
              if (target) { target.click(); return 'clicked'; }
              return 'none';
            })()
            """
        }
        return """
        (() => {
          if (location.search.includes('showTab=following')) return 'already';
          const candidates = Array.from(document.querySelectorAll('div,span,a,button'))
            .filter(el => ['关注','following'].includes((el.innerText || '').trim().toLowerCase()));
          const target = candidates.reverse().find(el => el.getBoundingClientRect().width > 0);
          if (target) { target.click(); return 'clicked'; }
          return 'none';
        })()
        """
    }

    private static let captureScript = """
    (() => {
      if (window.__followCaptured) return;
      window.__followCaptured = [];
      const store = (text) => {
        if (!text || typeof text !== 'string' || text.length < 40) return;
        if (text.indexOf('"sec_uid"') < 0 && text.indexOf('"nickname"') < 0 && text.indexOf('"followings"') < 0) return;
        if (window.__followCaptured.length >= 30) return;
        window.__followCaptured.push(text);
      };
      const originalFetch = window.fetch.bind(window);
      window.fetch = function(...args) {
        return originalFetch(...args).then(response => {
          try { response.clone().text().then(store).catch(() => {}); } catch (_) {}
          return response;
        });
      };
      const originalSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.send = function(...args) {
        this.addEventListener('loadend', () => {
          try { store(this.responseText); } catch (_) {}
        });
        return originalSend.apply(this, args);
      };
    })();
    """

    private func extractCapturedJSON(_ webView: WKWebView) async {
        guard let result = try? await webView.evaluateJavaScript(
            "JSON.stringify(window.__followCaptured || [])"
        ), let json = result as? String,
              let data = json.data(using: .utf8),
              let payloads = try? JSONDecoder().decode([String].self, from: data) else { return }

        for payload in payloads {
            guard let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else { continue }
            applyCapturedObject(object)
        }
    }

    private func applyCapturedObject(_ object: Any) {
        if let dictionary = object as? [String: Any] {
            for key in ["followings", "following_list", "user_list", "data", "users"] {
                if let array = dictionary[key] as? [Any] {
                    applyCapturedUsers(array)
                }
            }
            for value in dictionary.values {
                applyCapturedObject(value)
            }
        } else if let array = object as? [Any] {
            applyCapturedUsers(array)
        }
    }

    private func applyCapturedUsers(_ array: [Any]) {
        for entry in array {
            guard let user = entry as? [String: Any] else { continue }
            let secUID = user["sec_uid"] as? String
            let uid = user["uid"]
            let id = secUID ?? (uid as? String) ?? (uid as? NSNumber).map { $0.stringValue }
            guard let id, !id.isEmpty else { continue }
            let name = (user["nickname"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let name, !name.isEmpty, name.count <= 80 else { continue }

            var avatar: String?
            if let thumb = user["avatar_thumb"] as? [String: Any],
               let list = thumb["url_list"] as? [String] {
                avatar = list.first
            } else if let list = user["avatar_url_list"] as? [String] {
                avatar = list.first
            } else {
                avatar = user["avatar"] as? String
            }

            let draft = FollowedAccountDraft(
                platformUserId: id,
                secUserId: secUID,
                displayName: name,
                remark: nil,
                groupName: nil,
                avatarURLString: avatar
            )
            if !collected.contains(where: { $0.platformUserId == draft.platformUserId }) {
                collected.append(draft)
            }
        }
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
