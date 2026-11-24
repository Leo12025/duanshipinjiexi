import Foundation
import SwiftData

@MainActor
enum LibraryBackup {
    static func export(in context: ModelContext) throws -> URL {
        let descriptor = FetchDescriptor<LibraryItem>(sortBy: [SortDescriptor(\.createdAt)])
        let items = (try? context.fetch(descriptor)) ?? []

        let followAccounts = (try? context.fetch(FetchDescriptor<FollowedAccount>())) ?? []
        let backup = LibraryBackupFile(
            version: 1,
            exportedAt: Date(),
            accounts: followAccounts.map { account in
                LibraryBackupAccount(
                    id: account.id,
                    platform: account.platform,
                    platformUserId: account.platformUserId,
                    secUserId: account.secUserId,
                    displayName: account.displayName,
                    remark: account.remark,
                    groupName: account.groupName,
                    avatarURLString: account.avatarURLString,
                    avatarPHash: account.avatarPHash,
                    source: account.source,
                    syncedAt: account.syncedAt,
                    createdAt: account.createdAt
                )
            },
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
                    needsAudioMux: item.needsAudioMux,
                    files: item.files.map { file in
                        LibraryBackupMediaFile(
                            relativePath: file.relativePath,
                            role: file.role,
                            mimeType: file.mimeType,
                            width: file.width,
                            height: file.height,
                            orderIndex: file.orderIndex,
                            isAnimated: file.isAnimated,
                            isLongImageSplit: file.isLongImageSplit,
                            segmentIndex: file.segmentIndex,
                            segmentCount: file.segmentCount
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
            item.needsAudioMux = saved.needsAudioMux ?? false

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
                    orderIndex: savedFile.orderIndex,
                    isAnimated: savedFile.isAnimated ?? false,
                    isLongImageSplit: savedFile.isLongImageSplit ?? false,
                    segmentIndex: savedFile.segmentIndex,
                    segmentCount: savedFile.segmentCount
                )
                item.files.append(file)
                context.insert(file)
            }
        }

        var restoredAccounts = 0
        let existingAccounts = (try? context.fetch(FetchDescriptor<FollowedAccount>())) ?? []
        var accountsByKey: [String: FollowedAccount] = [:]
        for account in existingAccounts {
            accountsByKey[key(source: account.platform, sourceId: account.platformUserId)] = account
        }
        for saved in backup.accounts ?? [] {
            let account: FollowedAccount
            if let existing = accountsByKey[key(source: saved.platform, sourceId: saved.platformUserId)] {
                account = existing
            } else {
                account = FollowedAccount(
                    platform: MediaSource(rawValue: saved.platform) ?? .douyin,
                    platformUserId: saved.platformUserId,
                    secUserId: saved.secUserId,
                    displayName: saved.displayName,
                    remark: saved.remark,
                    groupName: saved.groupName,
                    avatarURLString: saved.avatarURLString,
                    source: FollowSource(rawValue: saved.source) ?? .manual
                )
                account.id = saved.id
                context.insert(account)
                restoredAccounts += 1
            }
            account.secUserId = saved.secUserId
            account.displayName = saved.displayName
            account.remark = saved.remark
            account.groupName = saved.groupName
            account.avatarURLString = saved.avatarURLString
            account.avatarPHash = saved.avatarPHash
            account.syncedAt = saved.syncedAt
            account.createdAt = saved.createdAt
        }

        try context.save()
        return backup.items.count + restoredAccounts
    }

    private static func key(source: String, sourceId: String) -> String {
        "\(source)::\(sourceId)"
    }
}

private struct LibraryBackupFile: Codable {
    let version: Int
    let exportedAt: Date
    let accounts: [LibraryBackupAccount]?
    let items: [LibraryBackupItem]
}

private struct LibraryBackupAccount: Codable {
    let id: UUID
    let platform: String
    let platformUserId: String
    let secUserId: String?
    let displayName: String
    let remark: String?
    let groupName: String?
    let avatarURLString: String?
    let avatarPHash: String?
    let source: String
    let syncedAt: Date
    let createdAt: Date
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
    let needsAudioMux: Bool?
    let files: [LibraryBackupMediaFile]
}

private struct LibraryBackupMediaFile: Codable {
    let relativePath: String
    let role: String
    let mimeType: String
    let width: Int?
    let height: Int?
    let orderIndex: Int
    let isAnimated: Bool?
    let isLongImageSplit: Bool?
    let segmentIndex: Int?
    let segmentCount: Int?
}
