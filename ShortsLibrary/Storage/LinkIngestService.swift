import Foundation
import SwiftData

@MainActor
enum LinkIngestService {
    static func detectPlatform(in text: String) -> String? {
        guard let url = LinkExtractor.firstURL(in: text),
              let parser = ParserRegistry.parser(for: url) else { return nil }
        return parser.source.displayName
    }

    @discardableResult
    static func ingest(text: String, modelContext: ModelContext) async throws -> String {
        guard let url = LinkExtractor.firstURL(in: text) else {
            throw AppError.invalidLink
        }
        return try await ingest(url: url, modelContext: modelContext)
    }

    @discardableResult
    static func ingest(url: URL, modelContext: ModelContext) async throws -> String {
        guard let parser = ParserRegistry.parser(for: url) else {
            throw AppError.unsupportedPlatform(url.host() ?? "未知")
        }

        let parsed = try await parser.parse(url: url)
        let item = try LibraryRepository.shared.makeItem(from: parsed, in: modelContext)
        item.downloadFailed = false
        item.lastDownloadError = nil
        item.updatedAt = Date()
        try? modelContext.save()

        MediaRetryService.enqueueRetry(item: item, in: modelContext)
        return "\(parser.source.displayName)解析成功，任务已进入下载队列"
    }
}
