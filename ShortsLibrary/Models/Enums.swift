import Foundation

enum MediaSource: String, CaseIterable, Identifiable {
    case douyin
    case kuaishou
    case xiaohongshu

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .douyin: return "抖音"
        case .kuaishou: return "快手"
        case .xiaohongshu: return "小红书"
        }
    }
}

enum MediaKind: String, CaseIterable, Identifiable {
    case video
    case imageText

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .video: return "视频"
        case .imageText: return "图文"
        }
    }
}

enum FileRole: String {
    case video
    case image
    case cover
    case thumbnail
}
