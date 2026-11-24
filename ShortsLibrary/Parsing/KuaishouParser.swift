import Foundation

struct KuaishouParser: PlatformParser {
    let source: MediaSource = .kuaishou
    let supportedHosts = ["kuaishou.com", "chenzhongtech.com", "gifshow.com"]

    func parse(url: URL) async throws -> ParsedMedia {
        let (html, finalURL) = try await PublicPageLoader.load(url: url)
        let metadata = HTMLMetadataExtractor.extract(html: html, finalURL: finalURL)

        guard let sourceId = extractSourceID(from: finalURL, html: html) else {
            throw AppError.parsingFailed("无法提取快手视频 ID")
        }

        let videos = metadata.videoURLs.map { MediaQualityHeuristic.videoCandidate(for: $0) }
        let images = MediaQualityHeuristic.sortedImages(metadata.imageURLs)
        guard !videos.isEmpty || !images.isEmpty else {
            throw AppError.noMedia
        }

        return ParsedMedia(
            source: .kuaishou,
            sourceId: sourceId,
            kind: MediaKindResolver.resolve(videos: videos.count, images: images.count, audios: 0),
            title: metadata.title ?? "快手内容 \(sourceId)",
            author: metadata.author,
            caption: metadata.description,
            pageURL: finalURL,
            coverURL: metadata.image,
            images: images,
            videos: videos,
            audioURL: nil
        )
    }

    private func extractSourceID(from url: URL, html: String) -> String? {
        let components = url.pathComponents.filter { $0 != "/" }
        if let last = components.last, last.count >= 8 {
            return last
        }

        let patterns = [
            #"/short-video/(\d+)"#,
            #"/video/(\d+)"#,
            #""photoId"\s*:\s*"(\d+)""#,
            #""videoId"\s*:\s*"(\d+)""#
        ]
        for pattern in patterns {
            if let id = firstCapture(pattern: pattern, in: html) {
                return id
            }
        }
        return nil
    }

    private func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1 else { return nil }
        let r = match.range(at: 1)
        guard r.location != NSNotFound else { return nil }
        return ns.substring(with: r)
    }
}
