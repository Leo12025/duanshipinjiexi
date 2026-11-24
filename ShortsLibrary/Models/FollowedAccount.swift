import Foundation
import SwiftData

@Model
final class FollowedAccount {
    var id: UUID = UUID()
    var platform: String
    var platformUserId: String
    var secUserId: String?
    var displayName: String
    var remark: String?
    var groupName: String?
    var avatarURLString: String?
    var avatarPHash: String?
    var source: String
    var syncedAt: Date
    var createdAt: Date

    init(
        platform: MediaSource,
        platformUserId: String,
        secUserId: String? = nil,
        displayName: String,
        remark: String? = nil,
        groupName: String? = nil,
        avatarURLString: String? = nil,
        source: FollowSource = .manual
    ) {
        self.platform = platform.rawValue
        self.platformUserId = platformUserId
        self.secUserId = secUserId
        self.displayName = displayName
        self.remark = remark
        self.groupName = groupName
        self.avatarURLString = avatarURLString
        self.source = source.rawValue
        self.syncedAt = Date()
        self.createdAt = Date()
    }

    var platformEnum: MediaSource {
        MediaSource(rawValue: platform) ?? .douyin
    }

    var sourceEnum: FollowSource {
        FollowSource(rawValue: source) ?? .manual
    }
}

enum FollowSource: String, CaseIterable, Identifiable {
    case api
    case webview
    case manual

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .api: return "平台接口"
        case .webview: return "页面读取"
        case .manual: return "手动录入"
        }
    }
}

extension FollowedAccount: Hashable {
    static func == (lhs: FollowedAccount, rhs: FollowedAccount) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
