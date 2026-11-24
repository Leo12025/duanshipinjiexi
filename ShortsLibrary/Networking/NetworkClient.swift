import Foundation

final class NetworkClient {
    static let shared = NetworkClient()

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 120
        return URLSession(configuration: configuration)
    }()

    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    func html(from url: URL) async throws -> (String, URL) {
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

    func temporaryDownload(from url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

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
