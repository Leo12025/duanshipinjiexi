import Foundation

enum MediaSource: String, CaseIterable, Identifiable {
    case douyin
    case kuaishou
    case xiaohongshu
    case bilibili
    case wechatChannels

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .douyin: return "抖音"
        case .kuaishou: return "快手"
        case .xiaohongshu: return "小红书"
        case .bilibili: return "B站"
        case .wechatChannels: return "视频号"
        }
    }
}

enum MediaKind: String, CaseIterable, Identifiable {
    case video
    case image
    case imageText
    case dynamic
    case audio

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .video: return "视频"
        case .image: return "图片"
        case .imageText: return "图文"
        case .dynamic: return "动态图片"
        case .audio: return "音频"
        }
    }
}

enum FileRole: String {
    case video
    case audio
    case image
    case imageSegment
    case imageOriginal
    case livePhotoVideo
    case cover
    case thumbnail
}
