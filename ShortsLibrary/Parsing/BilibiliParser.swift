import Foundation

struct BilibiliParser: PlatformParser {
    let source: MediaSource = .bilibili
    let supportedHosts = ["bilibili.com", "b23.tv"]

    func parse(url: URL) async throws -> ParsedMedia {
        let (html, finalURL) = try await PublicPageLoader.load(url: url)
        let metadata = HTMLMetadataExtractor.extract(html: html, finalURL: finalURL)

        guard let sourceId = extractSourceID(from: finalURL, html: html) else {
            throw AppError.parsingFailed("无法提取 B站内容 ID")
        }

        let audios = metadata.audioURLs
        let videos = metadata.videoURLs
            .filter { !audios.contains($0) }
            .map { MediaQualityHeuristic.videoCandidate(for: $0, hint: metadata.videoQualityHints[$0]) }
        let images = MediaQualityHeuristic.sortedImages(metadata.imageURLs)
        let dynamic = isDynamicPage(finalURL)

        guard !videos.isEmpty || !audios.isEmpty || !images.isEmpty else {
            throw AppError.noMedia
        }

        return ParsedMedia(
            source: .bilibili,
            sourceId: sourceId,
            kind: MediaKindResolver.resolve(
                videos: videos.count,
                images: images.count,
                audios: audios.count,
                isDynamic: dynamic
            ),
            title: metadata.title ?? "B站内容 \(sourceId)",
            author: metadata.author,
            caption: metadata.description,
            pageURL: finalURL,
            coverURL: metadata.image ?? MediaQualityHeuristic.bestCover(from: images),
            images: images,
            videos: videos,
            audioURL: audios.first,
            needsAudioMux: !audios.isEmpty && !videos.isEmpty
        )
    }

    private func isDynamicPage(_ url: URL) -> Bool {
        let host = url.host()?.lowercased() ?? ""
        let path = url.path.lowercased()
        return host == "t.bilibili.com"
            || path.contains("/opus/")
            || path.contains("/dynamic/")
    }

    private func extractSourceID(from url: URL, html: String) -> String? {
        let components = url.pathComponents.filter { $0 != "/" }
        if let id = components.first(where: { component in
            component.hasPrefix("BV") || component.hasPrefix("av") || component.hasPrefix("au")
        }) {
            return id
        }
        if let last = components.last, last.count >= 8 {
            return last
        }

        let patterns = [
            #""bvid"\s*:\s*"(BV[^"]+)""#,
            #""aid"\s*:\s*(\d+)"#,
            #""au"\s*:\s*(\d+)"#,
            #""opus_id"\s*:\s*(\d+)"#,
            #""opus_id"\s*:\s*"(\d+)""#,
            #""dynamic_id"\s*:\s*(\d+)"#,
            #""dynamic_id"\s*:\s*"(\d+)""#
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
