import Foundation
import WebKit

@MainActor
final class FollowPageCollector: NSObject, WKNavigationDelegate {
    static let shared = FollowPageCollector()

    private var continuation: CheckedContinuation<[FollowedAccountDraft], Error>?
    private var webView: WKWebView?
    private var collected: [FollowedAccountDraft] = []
    private var scrollCount = 0
    private var emptyRounds = 0
    private var started = false
    private var timeoutWorkItem: DispatchWorkItem?
    private var isCollecting = false
    private var platform: MediaSource = .douyin

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
            isCollecting = false
            throw AppError.parsingFailed("该平台暂不支持页面采集，请手动录入")
        }
        self.platform = platform

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
        webView.customUserAgent = NetworkClient.mobileUserAgent
        self.webView = webView
        self.collected = []
        self.scrollCount = 0
        self.emptyRounds = 0
        self.started = false
        webView.navigationDelegate = self

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let timeout = DispatchWorkItem { [weak self] in
                guard let self, self.continuation != nil else { return }
                Task { @MainActor in
                    guard self.continuation != nil else { return }
                    if self.collected.isEmpty {
                        let detail = await self.diagnose(webView)
                        self.finish(with: .failure(AppError.parsingFailed(detail)))
                    } else {
                        self.finish(with: .success(self.collected))
                    }
                }
            }
            self.timeoutWorkItem = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: timeout)
            webView.load(URLRequest(url: url))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !started else { return }
        started = true
        Task { @MainActor in
            guard self.continuation != nil else { return }
            try? await Task.sleep(nanoseconds: 900_000_000)
            _ = try? await webView.evaluateJavaScript(Self.clickFollowTabScript(for: webView.url))
            try? await Task.sleep(nanoseconds: 1_200_000_000)
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
        guard continuation != nil else { return }
        if scrollCount >= 20 || emptyRounds >= 5 {
            complete(webView)
            return
        }
        scrollCount += 1
        Task { @MainActor in
            guard self.continuation != nil else { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            _ = try? await webView.evaluateJavaScript("window.scrollBy(0, 900); document.scrollingElement?.scrollBy(0, 900);")
            try? await Task.sleep(nanoseconds: 400_000_000)
            let before = self.collected.count
            await self.extractCapturedJSON(webView)
            await self.extractOnce(webView, script: Self.script(for: webView.url))
            self.emptyRounds = self.collected.count > before ? 0 : self.emptyRounds + 1
            self.scheduleScroll(webView)
        }
    }

    private func complete(_ webView: WKWebView) {
        Task { @MainActor in
            guard self.continuation != nil else { return }
            if self.collected.isEmpty {
                let detail = await self.diagnose(webView)
                self.finish(with: .failure(AppError.parsingFailed(detail)))
            } else {
                self.finish(with: .success(self.collected))
            }
        }
    }

    private func diagnose(_ webView: WKWebView) async -> String {
        let script = """
        (() => {
          const captured = window.__followCaptured || [];
          const text = (document.body?.innerText || '').replace(/\\s+/g, ' ').slice(0, 120);
          return JSON.stringify({
            url: location.href,
            title: document.title,
            captured: captured.length,
            text: text
          });
        })()
        """
        var info = ""
        if let result = try? await webView.evaluateJavaScript(script) as? String,
           let data = result.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let url = object["url"] as? String ?? ""
            let title = object["title"] as? String ?? ""
            let captured = object["captured"] as? Int ?? 0
            let text = object["text"] as? String ?? ""
            info = "（页面：\(title)，捕获响应：\(captured)，地址：\(url.prefix(120))，内容：\(text.prefix(60))）"
        }
        let name = platform == .douyin ? "抖音" : "快手"
        return "未从\(name)页面读取到关注账号，请确认已登录且页面未触发验证\(info)"
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
        self.started = false
        self.emptyRounds = 0
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
        _ = url
        return """
        (() => {
          const wanted = ['关注', 'following'];
          const candidates = Array.from(document.querySelectorAll('[role="tab"],[role="button"],div,span,a,button'))
            .filter(el => {
              const text = (el.innerText || '').trim().toLowerCase();
              if (!wanted.includes(text)) return false;
              const rect = el.getBoundingClientRect();
              return rect.width > 0 && rect.height > 0;
            });
          const isTab = el => el.getAttribute('role') === 'tab'
            || (el.className && String(el.className).toLowerCase().includes('tab'))
            || el.closest('[role="tablist"]');
          const target = candidates.find(isTab) || candidates[candidates.length - 1];
          if (!target) return 'none';
          target.click();
          return 'clicked';
        })()
        """
    }

    private static let captureScript = """
    (() => {
      if (window.__followCaptured) return;
      window.__followCaptured = [];
      const markers = ['sec_uid', 'secUid', 'nickname', 'unique_id', 'uniqueId',
        'followings', 'following_list', 'user_list', 'userList', 'follower_list',
        'avatar_thumb', 'avatarThumb', '"uid"'];
      const store = (text) => {
        if (!text || typeof text !== 'string' || text.length < 40) return;
        const lower = text.toLowerCase();
        if (!markers.some(marker => lower.indexOf(marker.toLowerCase()) >= 0)) return;
        if (window.__followCaptured.length >= 80) return;
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
          try {
            if (typeof this.responseText === 'string') store(this.responseText);
            else if (this.response && typeof this.response === 'object') store(JSON.stringify(this.response));
          } catch (_) {}
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
            for key in ["followings", "following_list", "followingList", "user_list", "userList", "follower_list", "users"] {
                if let array = dictionary[key] as? [Any] {
                    applyCapturedUsers(array)
                }
            }
            let looksLikeFollowPage = dictionary["has_more"] != nil
                || dictionary["hasMore"] != nil
                || dictionary["cursor"] != nil
            if looksLikeFollowPage {
                for key in ["data", "list"] {
                    if let array = dictionary[key] as? [Any] {
                        applyCapturedUsers(array)
                    }
                }
            }
            for value in dictionary.values {
                applyCapturedObject(value)
            }
        } else if let array = object as? [Any] {
            applyCapturedUsers(array)
        }
    }

    static func parseUsers(_ array: [Any]) -> [FollowedAccountDraft] {
        var drafts: [FollowedAccountDraft] = []
        for entry in array {
            guard let raw = entry as? [String: Any] else { continue }
            let user = (raw["user"] as? [String: Any]) ?? raw
            let secUID = (user["sec_uid"] as? String) ?? (user["secUid"] as? String)
            let uidValue = user["uid"] ?? user["userId"] ?? user["id"]
            let uid = (uidValue as? String) ?? (uidValue as? NSNumber).map { $0.stringValue }
            guard let id = secUID ?? uid, !id.isEmpty else { continue }
            let rawName = (user["nickname"] as? String)
                ?? (user["name"] as? String)
                ?? (user["uniqueId"] as? String)
                ?? (user["unique_id"] as? String)
            let name = rawName?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let name, !name.isEmpty, name.count <= 80 else { continue }

            let thumb = (user["avatar_thumb"] as? [String: Any]) ?? (user["avatarThumb"] as? [String: Any])
            let thumbList = (thumb?["url_list"] as? [String]) ?? (thumb?["urlList"] as? [String])
            let avatarList = (user["avatar_url_list"] as? [String]) ?? (user["avatarUrlList"] as? [String])
            let avatar = thumbList?.first
                ?? avatarList?.first
                ?? (user["avatar"] as? String)
                ?? (user["avatarUrl"] as? String)

            let draft = FollowedAccountDraft(
                platformUserId: id,
                secUserId: secUID,
                displayName: name,
                remark: nil,
                groupName: nil,
                avatarURLString: avatar
            )
            if !drafts.contains(where: { $0.platformUserId == draft.platformUserId }) {
                drafts.append(draft)
            }
        }
        return drafts
    }

    private func applyCapturedUsers(_ array: [Any]) {
        for draft in Self.parseUsers(array) {
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
