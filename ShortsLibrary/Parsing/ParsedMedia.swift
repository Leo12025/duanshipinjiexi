import Foundation

struct VideoCandidate {
    let url: URL
    let quality: String
    let width: Int?
    let height: Int?
    let bitrate: Int?

    var pixelCount: Int {
        (width ?? 0) * (height ?? 0)
    }
}

enum MediaKindResolver {
    static func resolve(videos: Int, images: Int, audios: Int, isDynamic: Bool = false) -> MediaKind {
        if videos > 0 { return .video }
        if audios > 0 { return .audio }
        if isDynamic { return .dynamic }
        if images == 1 { return .image }
        return .imageText
    }
}

struct ParsedMedia {
    let source: MediaSource
    let sourceId: String
    let kind: MediaKind
    let title: String
    let author: String?
    let caption: String?
    let pageURL: URL
    let coverURL: URL?
    let images: [URL]
    let videos: [VideoCandidate]
    let audioURL: URL?

    var bestVideo: VideoCandidate? {
        videos.max { lhs, rhs in
            if lhs.pixelCount != rhs.pixelCount { return lhs.pixelCount < rhs.pixelCount }
            return (lhs.bitrate ?? 0) < (rhs.bitrate ?? 0)
        }
    }
}
