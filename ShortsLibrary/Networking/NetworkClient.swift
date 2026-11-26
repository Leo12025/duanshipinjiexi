import Foundation

final class NetworkClient {
    static let shared = NetworkClient()

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 120
        return URLSession(configuration: configuration)
    }()

    static let defaultUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    static let mobileUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    private static let searchEngineUA = "Mozilla/5.0 (compatible; Baiduspider/2.0; +http://www.baidu.com/search/spider.html)"

    func html(from url: URL) async throws -> (String, URL) {
        let initial = try await fetchHTML(from: url, userAgent: Self.userAgent(for: url))

        guard Self.needsPublicMetadata(for: initial.0, finalURL: initial.1) else {
            return initial
        }

        if let fallback = try? await fetchHTML(from: initial.1, userAgent: Self.searchEngineUA),
           fallback.0.contains("application/ld+json") || fallback.0.contains("aweme_detail") {
            return fallback
        }

        return initial
    }

    private func fetchHTML(from url: URL, userAgent: String) async throws -> (String, URL) {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.parsingFailed("无效的网络响应")
        }
        guard (200...299).contains(http.statusCode) else {
            throw AppError.badStatus(http.statusCode)
        }

        let html = String(data: data, encoding: .utf8)
            ?? String(decoding: data, as: UTF8.self)
        return (html, response.url ?? url)
    }

    private static func needsPublicMetadata(for html: String, finalURL: URL) -> Bool {
        let host = finalURL.host()?.lowercased() ?? ""
        guard host.contains("douyin") || host.contains("iesdouyin") else { return false }
        return html.contains("_$jsvmprt")
            || (!html.contains("application/ld+json") && !html.contains("aweme_detail"))
    }

    static func userAgent(for url: URL) -> String {
        let host = url.host()?.lowercased() ?? ""
        if host.contains("kuaishou") || host.contains("chenzhongtech") || host.contains("gifshow")
            || host.contains("weixin.qq.com") || host.contains("video.qq.com") {
            return mobileUserAgent
        }
        return defaultUserAgent
    }

    func temporaryDownload(from url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent(for: url), forHTTPHeaderField: "User-Agent")

        let (location, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.parsingFailed("无效的下载响应")
        }
        guard (200...299).contains(http.statusCode) else {
            throw AppError.badStatus(http.statusCode)
        }
        return location
    }
}
