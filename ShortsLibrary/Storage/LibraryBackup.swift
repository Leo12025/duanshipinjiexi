import Foundation
import SwiftData

@MainActor
enum LibraryBackup {
    static func export(in context: ModelContext) throws -> URL {
        let descriptor = FetchDescriptor<LibraryItem>(sortBy: [SortDescriptor(\.createdAt)])
        let items = (try? context.fetch(descriptor)) ?? []

        let backup = LibraryBackupFile(
            version: 1,
            exportedAt: Date(),
            items: items.map { item in
                LibraryBackupItem(
                    id: item.id,
                    source: item.source,
                    sourceId: item.sourceId,
                    kind: item.kind,
                    title: item.title,
                    author: item.author,
                    caption: item.caption,
                    pageURLString: item.pageURLString,
                    createdAt: item.createdAt,
                    updatedAt: item.updatedAt,
                    isFavorite: item.isFavorite,
                    isTrashed: item.isTrashed,
                    trashedAt: item.trashedAt,
                    duration: item.duration,
                    resolution: item.resolution,
                    byteSize: item.byteSize,
                    sourceVideoURLString: item.sourceVideoURLString,
                    sourceAudioURLString: item.sourceAudioURLString,
                    sourceCoverURLString: item.sourceCoverURLString,
                    sourceImageURLStrings: item.sourceImageURLStrings,
                    downloadFailed: item.downloadFailed,
                    lastDownloadError: item.lastDownloadError,
                    files: item.files.map { file in
                        LibraryBackupMediaFile(
                            relativePath: file.relativePath,
                            role: file.role,
                            mimeType: file.mimeType,
                            width: file.width,
                            height: file.height,
                            orderIndex: file.orderIndex
                        )
                    }
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)

        let url = AppPaths.root.appendingPathComponent("library.json")
        try data.write(to: url, options: .atomic)
        return url
    }

    @discardableResult
    static func restore(from url: URL, in context: ModelContext) throws -> Int {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(LibraryBackupFile.self, from: data)

        let allItems = (try? context.fetch(FetchDescriptor<LibraryItem>())) ?? []
        var existingByKey: [String: LibraryItem] = [:]
        for item in allItems {
            existingByKey[key(source: item.source, sourceId: item.sourceId)] = item
        }

        for saved in backup.items {
            let item: LibraryItem
            if let existing = existingByKey[key(source: saved.source, sourceId: saved.sourceId)] {
                item = existing
            } else {
                let pageURL = URL(string: saved.pageURLString) ?? URL(string: "about:blank")!
                item = LibraryItem(
                    source: MediaSource(rawValue: saved.source) ?? .douyin,
                    sourceId: saved.sourceId,
                    kind: MediaKind(rawValue: saved.kind) ?? .video,
                    title: saved.title,
                    author: saved.author,
                    caption: saved.caption,
                    pageURL: pageURL
                )
                item.id = saved.id
                context.insert(item)
            }

            item.title = saved.title
            item.author = saved.author
            item.caption = saved.caption
            item.pageURLString = saved.pageURLString
            item.createdAt = saved.createdAt
            item.updatedAt = saved.updatedAt
            item.isFavorite = saved.isFavorite
            item.isTrashed = saved.isTrashed
            item.trashedAt = saved.trashedAt
            item.duration = saved.duration
            item.resolution = saved.resolution
            item.byteSize = saved.byteSize
            item.sourceVideoURLString = saved.sourceVideoURLString
            item.sourceAudioURLString = saved.sourceAudioURLString
            item.sourceCoverURLString = saved.sourceCoverURLString
            item.sourceImageURLStrings = saved.sourceImageURLStrings
            item.downloadFailed = saved.downloadFailed
            item.lastDownloadError = saved.lastDownloadError

            for file in item.files {
                context.delete(file)
            }
            item.files = []

            for savedFile in saved.files {
                let file = MediaFile(
                    relativePath: savedFile.relativePath,
                    role: FileRole(rawValue: savedFile.role) ?? .image,
                    mimeType: savedFile.mimeType,
                    width: savedFile.width,
                    height: savedFile.height,
                    orderIndex: savedFile.orderIndex
                )
                item.files.append(file)
                context.insert(file)
            }
        }

        try context.save()
        return backup.items.count
    }

    private static func key(source: String, sourceId: String) -> String {
        "\(source)::\(sourceId)"
    }
}

private struct LibraryBackupFile: Codable {
    let version: Int
    let exportedAt: Date
    let items: [LibraryBackupItem]
}

private struct LibraryBackupItem: Codable {
    let id: UUID
    let source: String
    let sourceId: String
    let kind: String
    let title: String
    let author: String?
    let caption: String?
    let pageURLString: String
    let createdAt: Date
    let updatedAt: Date
    let isFavorite: Bool
    let isTrashed: Bool
    let trashedAt: Date?
    let duration: Double?
    let resolution: String?
    let byteSize: Int64?
    let sourceVideoURLString: String?
    let sourceAudioURLString: String?
    let sourceCoverURLString: String?
    let sourceImageURLStrings: [String]
    let downloadFailed: Bool
    let lastDownloadError: String?
    let files: [LibraryBackupMediaFile]
}

private struct LibraryBackupMediaFile: Codable {
    let relativePath: String
    let role: String
    let mimeType: String
    let width: Int?
    let height: Int?
    let orderIndex: Int
}
