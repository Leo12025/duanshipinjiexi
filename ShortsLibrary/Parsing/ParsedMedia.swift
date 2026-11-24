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

    var bestVideo: VideoCandidate? {
        videos.max { lhs, rhs in
            if lhs.pixelCount != rhs.pixelCount { return lhs.pixelCount < rhs.pixelCount }
            return (lhs.bitrate ?? 0) < (rhs.bitrate ?? 0)
        }
    }
}
