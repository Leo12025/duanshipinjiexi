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
                    sourceVideoFallbackURLStrings: item.sourceVideoFallbackURLStrings,
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

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "library-\(formatter.string(from: Date())).json"
        let url = AppPaths.root.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    @discardableResult
    static func restore(from url: URL, in context: ModelContext) throws -> Int {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(LibraryBackupFile.self, from: data)
        guard backup.version <= 1 else {
            throw AppError.fileSystem("不支持的备份版本 \(backup.version)")
        }

        let allItems = (try? context.fetch(FetchDescriptor<LibraryItem>())) ?? []
        var existingByKey: [String: LibraryItem] = [:]
        for item in allItems {
            existingByKey[key(source: item.source, sourceId: item.sourceId)] = item
        }

        var seenItemKeys: Set<String> = []
        var restoredItems = 0

        for saved in backup.items {
            let itemKey = key(source: saved.source, sourceId: saved.sourceId)
            guard seenItemKeys.insert(itemKey).inserted,
                  let source = MediaSource(rawValue: saved.source),
                  let kind = MediaKind(rawValue: saved.kind) else { continue }

            if let existing = existingByKey[itemKey], existing.updatedAt > saved.updatedAt { continue }

            let item: LibraryItem
            if let existing = existingByKey[itemKey] {
                item = existing
            } else {
                item = LibraryItem(
                    source: source,
                    sourceId: saved.sourceId,
                    kind: kind,
                    title: saved.title,
                    author: saved.author,
                    caption: saved.caption,
                    pageURL: URL(string: saved.pageURLString) ?? URL(string: "about:blank")!
                )
                item.id = saved.id
                context.insert(item)
            }

            item.kind = kind.rawValue
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
            item.sourceVideoFallbackURLStrings = saved.sourceVideoFallbackURLStrings ?? []
            item.sourceAudioURLString = saved.sourceAudioURLString
            item.sourceCoverURLString = saved.sourceCoverURLString
            item.sourceImageURLStrings = saved.sourceImageURLStrings
            item.downloadFailed = saved.downloadFailed
            item.lastDownloadError = saved.lastDownloadError
            item.needsAudioMux = saved.needsAudioMux ?? false

            for file in item.files { context.delete(file) }
            item.files = []

            var hasMissingFile = false
            for savedFile in saved.files {
                guard isValidRelativePath(savedFile.relativePath),
                      let role = FileRole(rawValue: savedFile.role) else {
                    hasMissingFile = true
                    continue
                }
                let file = MediaFile(
                    relativePath: savedFile.relativePath,
                    role: role,
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
                if !file.existsOnDisk { hasMissingFile = true }
            }
            if hasMissingFile { item.downloadFailed = true }

            existingByKey[itemKey] = item
            restoredItems += 1
        }

        var restoredAccounts = 0
        let existingAccounts = (try? context.fetch(FetchDescriptor<FollowedAccount>())) ?? []
        var accountsByKey: [String: FollowedAccount] = [:]
        for account in existingAccounts {
            accountsByKey[key(source: account.platform, sourceId: account.platformUserId)] = account
        }
        var seenAccountKeys: Set<String> = []

        for saved in backup.accounts ?? [] {
            let accountKey = key(source: saved.platform, sourceId: saved.platformUserId)
            guard seenAccountKeys.insert(accountKey).inserted,
                  let platform = MediaSource(rawValue: saved.platform),
                  let source = FollowSource(rawValue: saved.source) else { continue }

            let account: FollowedAccount
            if let existing = accountsByKey[accountKey] {
                if existing.syncedAt > saved.syncedAt { continue }
                account = existing
            } else {
                account = FollowedAccount(
                    platform: platform,
                    platformUserId: saved.platformUserId,
                    secUserId: saved.secUserId,
                    displayName: saved.displayName,
                    remark: saved.remark,
                    groupName: saved.groupName,
                    avatarURLString: saved.avatarURLString,
                    source: source
                )
                account.id = saved.id
                context.insert(account)
            }
            account.secUserId = saved.secUserId
            account.displayName = saved.displayName
            account.remark = saved.remark
            account.groupName = saved.groupName
            account.avatarURLString = saved.avatarURLString
            account.avatarPHash = saved.avatarPHash
            account.syncedAt = saved.syncedAt
            account.createdAt = saved.createdAt
            accountsByKey[accountKey] = account
            restoredAccounts += 1
        }

        try context.save()
        return restoredItems + restoredAccounts
    }

    private static func isValidRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains(".."),
              !path.contains("\\") else { return false }
        let root = AppPaths.root.standardizedFileURL.path
        let resolved = AppPaths.root.appendingPathComponent(path).standardizedFileURL.path
        return resolved.hasPrefix(root + "/")
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
    let sourceVideoFallbackURLStrings: [String]?
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
