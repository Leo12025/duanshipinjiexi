import Foundation
import SwiftData

@MainActor
final class LibraryRepository {
    static let shared = LibraryRepository()
    private init() {}

    func existingItem(source: MediaSource, sourceId: String, in context: ModelContext) -> LibraryItem? {
        let sourceValue = source.rawValue
        let predicate = #Predicate<LibraryItem> { item in
            item.source == sourceValue && item.sourceId == sourceId && !item.isTrashed
        }
        var descriptor = FetchDescriptor<LibraryItem>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    @discardableResult
    func makeItem(from parsed: ParsedMedia, in context: ModelContext) throws -> LibraryItem {
        if let existing = existingItem(source: parsed.source, sourceId: parsed.sourceId, in: context) {
            existing.title = parsed.title
            existing.author = parsed.author
            existing.caption = parsed.caption
            existing.pageURLString = parsed.pageURL.absoluteString
            existing.sourceVideoURLString = parsed.bestVideo?.url.absoluteString
            existing.sourceAudioURLString = parsed.audioURL?.absoluteString
            existing.sourceCoverURLString = parsed.coverURL?.absoluteString
            existing.sourceImageURLStrings = parsed.images.map(\.absoluteString)
            existing.updatedAt = Date()
            return existing
        }

        let item = LibraryItem(
            source: parsed.source,
            sourceId: parsed.sourceId,
            kind: parsed.kind,
            title: parsed.title,
            author: parsed.author,
            caption: parsed.caption,
            pageURL: parsed.pageURL
        )
        item.sourceVideoURLString = parsed.bestVideo?.url.absoluteString
        item.sourceAudioURLString = parsed.audioURL?.absoluteString
        item.sourceCoverURLString = parsed.coverURL?.absoluteString
        item.sourceImageURLStrings = parsed.images.map(\.absoluteString)
        context.insert(item)
        return item
    }

    @discardableResult
    func addFile(
        to item: LibraryItem,
        relativePath: String,
        role: FileRole,
        mimeType: String,
        width: Int? = nil,
        height: Int? = nil,
        orderIndex: Int = 0,
        in context: ModelContext
    ) -> MediaFile {
        let file = MediaFile(
            relativePath: relativePath,
            role: role,
            mimeType: mimeType,
            width: width,
            height: height,
            orderIndex: orderIndex
        )
        item.files.append(file)
        context.insert(file)
        return file
    }

    func trash(item: LibraryItem, in context: ModelContext) {
        item.isTrashed = true
        item.trashedAt = Date()
        try? context.save()
    }

    func restore(item: LibraryItem, in context: ModelContext) {
        item.isTrashed = false
        item.trashedAt = nil
        try? context.save()
    }

    func deletePermanently(item: LibraryItem, in context: ModelContext) throws {
        for file in item.files where file.existsOnDisk {
            try? FileManager.default.removeItem(at: file.fileURL)
        }
        let directory = AppPaths.itemDirectory(source: item.source, sourceId: item.sourceId)
        try? FileManager.default.removeItem(at: directory)
        context.delete(item)
        try? context.save()
    }

    func purgeExpiredTrash(in context: ModelContext) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let predicate = #Predicate<LibraryItem> { item in item.isTrashed }
        let descriptor = FetchDescriptor<LibraryItem>(predicate: predicate)
        guard let trashed = try? context.fetch(descriptor) else { return }

        for item in trashed where (item.trashedAt ?? .distantFuture) < cutoff {
            try? deletePermanently(item: item, in: context)
        }
    }
}
