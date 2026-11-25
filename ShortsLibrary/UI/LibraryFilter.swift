import Foundation

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case douyin
    case kuaishou
    case xiaohongshu
    case bilibili
    case video
    case image
    case imageText
    case dynamic
    case audio
    case favorites
    case trash

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "全部"
        case .douyin: return "抖音"
        case .kuaishou: return "快手"
        case .xiaohongshu: return "小红书"
        case .bilibili: return "B站"
        case .video: return "视频"
        case .image: return "图片"
        case .imageText: return "图文"
        case .dynamic: return "动态"
        case .audio: return "音频"
        case .favorites: return "收藏"
        case .trash: return "最近删除"
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.stack.3d.up"
        case .douyin: return "music.note"
        case .kuaishou: return "bolt"
        case .xiaohongshu: return "book"
        case .bilibili: return "tv"
        case .video: return "video"
        case .image: return "photo"
        case .imageText: return "photo.stack"
        case .dynamic: return "bubble.left.and.bubble.right"
        case .audio: return "waveform"
        case .favorites: return "star"
        case .trash: return "trash"
        }
    }
}
