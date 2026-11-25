import Foundation

struct VideoCandidate {
    let url: URL
    let quality: String
    let width: Int?
    let height: Int?
    let bitrate: Int?
    var sourceField: String? = nil
    var prefersNoWatermark: Bool = false
    var isWatermarked: Bool = false

    var pixelCount: Int {
        (width ?? 0) * (height ?? 0)
    }
}

struct VideoQualityHint {
    let width: Int?
    let height: Int?
    let bitrate: Int?
    let quality: String?
}

enum MediaQualityHeuristic {
    static func videoCandidate(
        for url: URL,
        hint: VideoQualityHint? = nil,
        sourceField: String? = nil,
        prefersNoWatermark: Bool = false,
        isWatermarked: Bool = false
    ) -> VideoCandidate {
        let text = url.absoluteString.lowercased()
        var width = hint?.width
        var height = hint?.height
        var bitrate = hint?.bitrate

        if width == nil || height == nil,
           let groups = captures(pattern: #"(\d{2,5})[x](\d{2,5})"#, in: text), groups.count >= 3 {
            if width == nil { width = Int(groups[1]) }
            if height == nil { height = Int(groups[2]) }
        }
        if height == nil, let value = firstCapture(pattern: #"(\d{2,5})p"#, in: text) {
            height = Int(value)
        }
        if width == nil, let value = firstCapture(pattern: #"width[=_]?(\d{3,4})"#, in: text) {
            width = Int(value)
        }
        if height == nil, let value = firstCapture(pattern: #"height[=_]?(\d{3,4})"#, in: text) {
            height = Int(value)
        }
        if bitrate == nil, let value = firstCapture(pattern: #"bitrate[=_]?(\d{3,8})"#, in: text) {
            bitrate = Int(value)
        }

        let quality = hint?.quality ?? qualityLabel(width: width, height: height, bitrate: bitrate)
        return VideoCandidate(
            url: url,
            quality: quality,
            width: width,
            height: height,
            bitrate: bitrate,
            sourceField: sourceField,
            prefersNoWatermark: prefersNoWatermark,
            isWatermarked: isWatermarked
        )
    }

    static func sortedImages(_ urls: [URL]) -> [URL] {
        urls
    }

    static func bestCover(from urls: [URL]) -> URL? {
        urls.max { estimatedPixels(for: $0) < estimatedPixels(for: $1) }
    }

    static func estimatedPixels(for url: URL) -> Int {
        let candidate = videoCandidate(for: url)
        if candidate.pixelCount > 0 { return candidate.pixelCount }
        return candidate.height.map { $0 * $0 } ?? 0
    }

    private static func qualityLabel(width: Int?, height: Int?, bitrate: Int?) -> String {
        if let width, let height {
            return "\(width)x\(height)"
        }
        if let height {
            return "\(height)p"
        }
        if let bitrate {
            return "\(bitrate / 1000) kbps"
        }
        return "公开最高画质"
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        guard let groups = captures(pattern: pattern, in: text), groups.count > 1 else { return nil }
        return groups[1]
    }

    private static func captures(pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        return (0..<match.numberOfRanges).compactMap { index in
            let r = match.range(at: index)
            guard r.location != NSNotFound else { return nil }
            return ns.substring(with: r)
        }
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
    let needsAudioMux: Bool

    private static func rank(_ candidate: VideoCandidate) -> (Int, Int, Int, Int, Int) {
        let watermarkPriority = candidate.isWatermarked ? 0 : (candidate.prefersNoWatermark ? 2 : 1)
        let ext = candidate.url.pathExtension.lowercased()
        let direct = ext == "mp4" ? 2 : (ext == "m3u8" ? 0 : 1)
        return (
            watermarkPriority,
            direct,
            candidate.pixelCount,
            candidate.bitrate ?? 0,
            candidate.quality.isEmpty ? 0 : 1
        )
    }

    var orderedVideos: [VideoCandidate] {
        videos.sorted { Self.rank($0) > Self.rank($1) }
    }

    var bestVideo: VideoCandidate? {
        orderedVideos.first
    }

    var fallbackVideos: [VideoCandidate] {
        Array(orderedVideos.dropFirst())
    }
}
