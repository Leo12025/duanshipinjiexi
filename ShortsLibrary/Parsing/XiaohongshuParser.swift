import Foundation

struct XiaohongshuParser: PlatformParser {
    let source: MediaSource = .xiaohongshu
    let supportedHosts = ["xiaohongshu.com", "xhslink.com", "xhslink.cn"]

    func parse(url: URL) async throws -> ParsedMedia {
        let (html, finalURL) = try await PublicPageLoader.load(url: url)
        let metadata = HTMLMetadataExtractor.extract(html: html, finalURL: finalURL)
        let page = extractPageData(from: html)

        guard let sourceId = extractSourceID(from: finalURL, html: html) else {
            throw AppError.parsingFailed("无法提取小红书笔记 ID")
        }

        var imageURLs = metadata.imageURLs + page.images
        var videoURLs = metadata.videoURLs + page.videos
        imageURLs = unique(imageURLs)
        videoURLs = unique(videoURLs)

        let videos = videoURLs.map {
            MediaQualityHeuristic.videoCandidate(for: $0, hint: metadata.videoQualityHints[$0])
        }
        let images = MediaQualityHeuristic.sortedImages(imageURLs)
        let kind = MediaKindResolver.resolve(videos: videos.count, images: images.count, audios: 0)

        guard !videos.isEmpty || !images.isEmpty else {
            throw AppError.noMedia
        }

        return ParsedMedia(
            source: .xiaohongshu,
            sourceId: sourceId,
            kind: kind,
            title: metadata.title ?? page.title ?? "小红书笔记 \(sourceId)",
            author: metadata.author,
            caption: metadata.description ?? page.desc,
            pageURL: finalURL,
            coverURL: metadata.image ?? MediaQualityHeuristic.bestCover(from: images),
            images: images,
            videos: videos,
            audioURL: nil,
            needsAudioMux: false
        )
    }

    private struct PageData {
        var title: String?
        var desc: String?
        var images: [URL] = []
        var videos: [URL] = []
    }

    private func extractPageData(from html: String) -> PageData {
        var result = PageData()

        result.title = firstCapture(
            pattern: #"<meta[^>]+(?:name|property)=["']og:title["'][^>]+content=["']([^"']+)["'][^>]*>"#,
            in: html
        ).map(decode)

        result.desc = firstCapture(
            pattern: #""desc"\s*:\s*"((?:[^"\\]|\\.)*)""#,
            in: html
        ).map(decode)

        let imagePattern = #"content=["'](https?://sns-webpic-[^"']+)["']"#
        for raw in captures(pattern: imagePattern, in: html) {
            guard let url = makeURL(from: raw) else { continue }
            if !result.images.contains(url) { result.images.append(url) }
        }

        let videoPattern = #"content=["'](https?://sns-video-[^"']+)["']"#
        for raw in captures(pattern: videoPattern, in: html) {
            guard let url = makeURL(from: raw) else { continue }
            if !result.videos.contains(url) { result.videos.append(url) }
        }

        let livePattern = #""masterUrl"\s*:\s*"((?:[^"\\]|\\.)*)""#
        for raw in captures(pattern: livePattern, in: html) {
            guard let url = makeURL(from: raw) else { continue }
            if !result.videos.contains(url) { result.videos.append(url) }
        }

        return result
    }

    private func extractSourceID(from url: URL, html: String) -> String? {
        let components = url.pathComponents.filter { $0 != "/" }
        if let last = components.last,
           last.count == 24,
           last.allSatisfy(\.isHexDigit) {
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

    private func unique(_ urls: [URL]) -> [URL] {
        URL.dedupeMedia(urls)
    }

    private func makeURL(from raw: String) -> URL? {
        let value = decode(raw)
            .replacingOccurrences(of: "%5C", with: "")
            .replacingOccurrences(of: "\\", with: "")
        guard let url = URL(string: value),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    private func decode(_ raw: String) -> String {
        var value = raw
            .replacingOccurrences(of: #"\\u002F"#, with: "/")
            .replacingOccurrences(of: #"\u002F"#, with: "/")
            .replacingOccurrences(of: #"\\/"#, with: "/")
            .replacingOccurrences(of: #"\/"#, with: "/")
        let entities = [
            ("&amp;", "&"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&nbsp;", " ")
        ]
        for (token, replacement) in entities {
            value = value.replacingOccurrences(of: token, with: replacement)
        }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\\"))

        let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
        if let data = "\"\(escaped)\"".data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? String {
            return decoded.trimmingCharacters(in: CharacterSet(charactersIn: "\\"))
        }
        return value
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

    private func captures(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let r = match.range(at: 1)
            guard r.location != NSNotFound else { return nil }
            return ns.substring(with: r)
        }
    }
}
