import Foundation

enum PublicPageLoader {
    static func load(url: URL) async throws -> (String, URL) {
        let result = try await loadPage(url: url)
        let lower = result.0.lowercased()

        if ["请先登录", "登录后查看", "登录后可见", "请登录后", "登录以查看"]
            .contains(where: { lower.contains($0) }) {
            throw AppError.loginRequired(platformName(for: url))
        }
        if ["访问频繁", "操作频繁", "请求过于频繁", "too many requests"]
            .contains(where: { lower.contains($0) }) {
            throw AppError.rateLimited
        }
        return result
    }

    private static func loadPage(url: URL) async throws -> (String, URL) {
        if await LoginSessionManager.shared.isLoggedIn(for: url),
           let result = try? await WebViewPageLoader.load(from: url),
           isUsable(result.0) {
            return result
        }

        if let result = try? await NetworkClient.shared.html(from: url),
           isUsable(result.0) {
            return result
        }

        return try await WebViewPageLoader.load(from: url)
    }

    private static func isUsable(_ html: String) -> Bool {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains("_$jsvmprt")
    }

    private static func platformName(for url: URL) -> String {
        ParserRegistry.parser(for: url)?.source.displayName ?? "该平台"
    }
}
