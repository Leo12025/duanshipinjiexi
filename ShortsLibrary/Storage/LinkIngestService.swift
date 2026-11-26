import Foundation
import SwiftData

enum IngestOutcome {
    case created(LibraryItem)
    case existing(LibraryItem)

    var item: LibraryItem {
        switch self {
        case .created(let item), .existing(let item): return item
        }
    }

    var isNew: Bool {
        if case .created = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .created:
            return "解析成功，任务已进入下载队列"
        case .existing(let item):
            return "「\(item.title)」已在资料库，元数据已更新"
        }
    }
}

@MainActor
enum LinkIngestService {
    private static var inFlight: [String: Task<IngestOutcome, Error>] = [:]

    static func detectPlatform(in text: String) -> String? {
        guard let url = LinkExtractor.firstURL(in: text),
              let parser = ParserRegistry.parser(for: url) else { return nil }
        return parser.source.displayName
    }

    @discardableResult
    static func ingest(text: String, modelContext: ModelContext) async throws -> IngestOutcome {
        guard let url = LinkExtractor.firstURL(in: text) else {
            throw AppError.invalidLink
        }
        return try await ingest(url: url, modelContext: modelContext)
    }

    @discardableResult
    static func ingest(url: URL, modelContext: ModelContext) async throws -> IngestOutcome {
        let key = url.absoluteString
        if let task = inFlight[key] {
            return try await task.value
        }
        let task = Task {
            try await ingestUncached(url: url, modelContext: modelContext)
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        return try await task.value
    }

    private static func ingestUncached(url: URL, modelContext: ModelContext) async throws -> IngestOutcome {
        guard let parser = ParserRegistry.parser(for: url) else {
            throw AppError.unsupportedPlatform(url.host() ?? "未知")
        }

        let loggedIn = await LoginSessionManager.shared.isLoggedIn(for: url)
        let parsed: ParsedMedia
        if let cached = ParseCache.parsed(for: url, loggedIn: loggedIn) {
            parsed = cached
        } else if ParseCache.hasRecentFailure(for: url, loggedIn: loggedIn) {
            throw AppError.platformChanged(parser.source.displayName)
        } else {
            do {
                parsed = try await parser.parse(url: url)
                ParseCache.store(parsed, for: url, loggedIn: loggedIn)
            } catch {
                ParseCache.markFailure(for: url, loggedIn: loggedIn)
                throw error
            }
        }
        let existed = LibraryRepository.shared.existingItem(
            source: parsed.source,
            sourceId: parsed.sourceId,
            in: modelContext,
            includeTrashed: true
        ) != nil
        let item = try LibraryRepository.shared.makeItem(from: parsed, in: modelContext)
        item.updatedAt = Date()
        try? modelContext.save()

        MediaRetryService.enqueueRetry(item: item, in: modelContext)
        return existed ? .existing(item) : .created(item)
    }

    static func redownload(item: LibraryItem, in modelContext: ModelContext) {
        for file in item.files {
            if file.existsOnDisk {
                ThumbnailCache.invalidate(for: file.fileURL)
                VideoThumbnailCache.invalidate(for: file.fileURL)
                try? FileManager.default.removeItem(at: file.fileURL)
            }
            modelContext.delete(file)
        }
        item.files = []
        item.duration = nil
        item.resolution = nil
        item.byteSize = nil
        item.needsAudioMux = item.sourceAudioURLString != nil
        try? modelContext.save()
        MediaRetryService.enqueueRetry(item: item, in: modelContext)
    }
}
