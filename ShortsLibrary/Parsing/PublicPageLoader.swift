import Foundation

enum PublicPageLoader {
    static func load(url: URL) async throws -> (String, URL) {
        if await LoginSessionManager.shared.isLoggedIn(for: url),
           let result = try? await WebViewPageLoader.shared.renderedHTML(from: url),
           !result.0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return result
        }

        if let result = try? await NetworkClient.shared.html(from: url),
           !result.0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return result
        }

        return try await WebViewPageLoader.shared.renderedHTML(from: url)
    }
}
