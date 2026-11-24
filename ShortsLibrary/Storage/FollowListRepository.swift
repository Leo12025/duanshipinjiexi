import Foundation
import SwiftData

@MainActor
enum FollowListRepository {
    static func upsert(
        drafts: [FollowedAccountDraft],
        platform: MediaSource,
        source: FollowSource,
        in context: ModelContext
    ) async -> Int {
        var count = 0
        for draft in drafts {
            var hash: String?
            if let avatar = draft.avatarURLString,
               let url = URL(string: avatar),
               ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                hash = await FollowSimilarity.avatarHash(from: url)
            }
            let existing = find(platform: platform, platformUserId: draft.platformUserId, in: context)
                ?? find(platform: platform, secUserId: draft.secUserId, in: context)
            if let existing {
                existing.displayName = draft.displayName
                existing.secUserId = draft.secUserId ?? existing.secUserId
                existing.remark = draft.remark ?? existing.remark
                existing.groupName = draft.groupName ?? existing.groupName
                existing.avatarURLString = draft.avatarURLString ?? existing.avatarURLString
                if let hash { existing.avatarPHash = hash }
                existing.source = source.rawValue
                existing.syncedAt = Date()
            } else {
                let account = FollowedAccount(
                    platform: platform,
                    platformUserId: draft.platformUserId,
                    secUserId: draft.secUserId,
                    displayName: draft.displayName,
                    remark: draft.remark,
                    groupName: draft.groupName,
                    avatarURLString: draft.avatarURLString,
                    source: source
                )
                account.avatarPHash = hash
                context.insert(account)
                count += 1
            }
        }
        try? context.save()
        return count
    }

    static func find(
        platform: MediaSource,
        platformUserId: String,
        in context: ModelContext
    ) -> FollowedAccount? {
        let value = platform.rawValue
        let id = platformUserId
        let predicate = #Predicate<FollowedAccount> {
            $0.platform == value && $0.platformUserId == id
        }
        var descriptor = FetchDescriptor<FollowedAccount>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func find(
        platform: MediaSource,
        secUserId: String?,
        in context: ModelContext
    ) -> FollowedAccount? {
        guard let secUserId else { return nil }
        let value = platform.rawValue
        let sec = secUserId
        let predicate = #Predicate<FollowedAccount> {
            $0.platform == value && $0.secUserId == sec
        }
        var descriptor = FetchDescriptor<FollowedAccount>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func deleteAll(platform: MediaSource, in context: ModelContext) {
        let value = platform.rawValue
        let predicate = #Predicate<FollowedAccount> { $0.platform == value }
        guard let items = try? context.fetch(FetchDescriptor(predicate: predicate)) else { return }
        for item in items { context.delete(item) }
        try? context.save()
    }
}

struct FollowedAccountDraft: Sendable, Codable {
    let platformUserId: String
    let secUserId: String?
    let displayName: String
    let remark: String?
    let groupName: String?
    let avatarURLString: String?
}
