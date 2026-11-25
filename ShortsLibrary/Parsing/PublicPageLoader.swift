import Foundation

enum PublicPageLoader {
    private static let loginKeywords = [
        "请先登录", "登录后查看", "登录后可见", "请登录后", "登录以查看",
        "log in", "sign in", "验证码", "需要登录"
    ]
    private static let rateLimitKeywords = [
        "访问频繁", "操作频繁", "请求过于频繁", "too many requests", "rate limit"
    ]
    private static let verificationMarkers = [
        "_$jsvmprt", "security verification", "verify yourself", "captcha_challenge", "滑动验证"
    ]

    static func load(url: URL) async throws -> (String, URL) {
        let result = try await loadWithoutLoginCheck(url: url)
        if requiresLogin(html: result.0) {
            throw AppError.loginRequired(platformName(for: url))
        }
        return result
    }

    static func loadWithoutLoginCheck(url: URL) async throws -> (String, URL) {
        let result = try await loadPage(url: url)
        try ensureNotBlocked(html: result.0, url: url)
        return result
    }

    static func loadDouyinWithCapture(url: URL) async throws -> (String, URL) {
        let result = try await WebViewPageLoader.loadDetailed(from: url)
        var html = result.html
        if !result.capturedJSON.isEmpty {
            html += result.capturedJSON.map { "<script>\($0)</script>" }.joined()
        }
        try ensureNotBlocked(html: html, url: result.url)
        return (html, result.url)
    }

    static func loadWechatChannelsWithCapture(url: URL) async throws -> (String, URL) {
        let result = try await WebViewPageLoader.loadDetailed(from: url)
        var html = result.html
        if !result.capturedJSON.isEmpty {
            html += result.capturedJSON.map { "<script>\($0)</script>" }.joined()
        }
        try ensureNotBlocked(html: html, url: result.url)
        return (html, result.url)
    }

    private static func ensureNotBlocked(html: String, url: URL) throws {
        let lower = html.lowercased()
        if rateLimitKeywords.contains(where: { lower.contains($0) }) {
            throw AppError.rateLimited
        }
        if verificationMarkers.contains(where: { lower.contains($0) }) {
            throw AppError.verificationRequired(platformName(for: url))
        }
    }

    static func requiresLogin(html: String) -> Bool {
        let lower = html.lowercased()
        return loginKeywords.contains { lower.contains($0) }
    }

    private static func loadPage(url: URL) async throws -> (String, URL) {
        let shouldPreferWebView = await LoginSessionManager.shared.isLoggedIn(for: url)
            || isDouyin(url) || isWechatChannels(url)
        if shouldPreferWebView,
           let result = try? await WebViewPageLoader.load(from: url),
           isUsable(result.0),
           !requiresLogin(html: result.0) {
            return result
        }

        if let result = try? await NetworkClient.shared.html(from: url),
           isUsable(result.0) {
            return result
        }

        return try await WebViewPageLoader.load(from: url)
    }

    private static func isDouyin(_ url: URL) -> Bool {
        let host = url.host()?.lowercased() ?? ""
        return host == "douyin.com" || host.hasSuffix(".douyin.com")
            || host == "iesdouyin.com" || host.hasSuffix(".iesdouyin.com")
    }

    private static func isWechatChannels(_ url: URL) -> Bool {
        let host = url.host()?.lowercased() ?? ""
        return host == "weixin.qq.com" || host.hasSuffix(".weixin.qq.com")
            || host == "video.qq.com" || host.hasSuffix(".video.qq.com")
    }

    private static func isUsable(_ html: String) -> Bool {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()
        return !verificationMarkers.contains { lower.contains($0) }
    }

    private static func platformName(for url: URL) -> String {
        ParserRegistry.parser(for: url)?.source.displayName ?? "该平台"
    }
}
