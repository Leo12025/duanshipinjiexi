import Foundation

struct XiaohongshuParser: PlatformParser {
    let source: MediaSource = .xiaohongshu
    let supportedHosts = ["xiaohongshu.com", "xhslink.com"]

    func parse(url: URL) async throws -> ParsedMedia {
        let (html, finalURL) = try await PublicPageLoader.load(url: url)
        let metadata = HTMLMetadataExtractor.extract(html: html, finalURL: finalURL)

        guard let sourceId = extractSourceID(from: finalURL, html: html) else {
            throw AppError.parsingFailed("无法提取小红书笔记 ID")
        }

        let videos = metadata.videoURLs.map {
            VideoCandidate(url: $0, quality: "公开最高画质", width: nil, height: nil, bitrate: nil)
        }
        let images = metadata.imageURLs
        let kind: MediaKind = videos.isEmpty ? .imageText : .video

        guard !videos.isEmpty || !images.isEmpty else {
            throw AppError.noMedia
        }

        return ParsedMedia(
            source: .xiaohongshu,
            sourceId: sourceId,
            kind: kind,
            title: metadata.title ?? "小红书笔记 \(sourceId)",
            author: metadata.author,
            caption: metadata.description,
            pageURL: finalURL,
            coverURL: metadata.image ?? images.first,
            images: images,
            videos: videos
        )
    }

    private func extractSourceID(from url: URL, html: String) -> String? {
        let components = url.pathComponents.filter { $0 != "/" }
        if let last = components.last, last.count >= 16 {
            return last
        }

        let patterns = [
            #"/explore/([a-zA-Z0-9]{16,32})"#,
            #"/discovery/item/([a-zA-Z0-9]{16,32})"#,
            #""noteId"\s*:\s*"([^"]+)""#,
            #""note_id"\s*:\s*"([^"]+)""#
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
