import Foundation

struct DouyinParser: PlatformParser {
    let source: MediaSource = .douyin
    let supportedHosts = ["douyin.com", "iesdouyin.com"]

    func parse(url: URL) async throws -> ParsedMedia {
        let (html, finalURL) = try await PublicPageLoader.load(url: url)
        let metadata = HTMLMetadataExtractor.extract(html: html, finalURL: finalURL)
        let detail = extractDetail(from: html)

        let sourceId = extractSourceID(from: finalURL, html: html) ?? detail.sourceID
            ?? "\(finalURL.lastPathComponent)"
        guard !sourceId.isEmpty else {
            throw AppError.parsingFailed("无法提取抖音视频 ID")
        }

        var videoURLs = metadata.videoURLs + detail.videos
        var imageURLs = metadata.imageURLs + detail.images
        videoURLs = unique(videoURLs)
        imageURLs = unique(imageURLs)

        let videos = videoURLs.map {
            MediaQualityHeuristic.videoCandidate(for: $0, hint: metadata.videoQualityHints[$0])
        }
        let images = MediaQualityHeuristic.sortedImages(imageURLs)
        guard !videos.isEmpty || !images.isEmpty else {
            throw AppError.noMedia
        }

        return ParsedMedia(
            source: .douyin,
            sourceId: sourceId,
            kind: MediaKindResolver.resolve(videos: videos.count, images: images.count, audios: 0),
            title: metadata.title ?? detail.title ?? "抖音内容 \(sourceId)",
            author: metadata.author ?? detail.author,
            caption: metadata.description ?? detail.description,
            pageURL: finalURL,
            coverURL: metadata.image ?? images.first,
            images: images,
            videos: videos,
            audioURL: nil,
            needsAudioMux: false
        )
    }

    private func extractSourceID(from url: URL, html: String) -> String? {
        let components = url.pathComponents.filter { $0 != "/" }
        if let last = components.last, last.count >= 8, last.allSatisfy(\.isNumber) {
            return last
        }

        let patterns = [
            #"/video/(\d+)"#,
            #"/note/(\d+)"#,
            #"/slides/(\d+)"#,
            #""aweme_id"\s*:\s*"(\d+)""#,
            #""aweme_id"\s*:\s*(\d+)"#
        ]
        for pattern in patterns {
            if let id = firstCapture(pattern: pattern, in: html) {
                return id
            }
        }
        return components.last
    }

    private struct DouyinDetail {
        var sourceID: String?
        var title: String?
        var author: String?
        var description: String?
        var images: [URL] = []
        var videos: [URL] = []
    }

    private func extractDetail(from html: String) -> DouyinDetail {
        var result = DouyinDetail()
        var texts = [html]

        let scriptPattern = #"<script\b[^>]*>([\s\S]{0,400000}?)</script>"#
        for group in captures(pattern: scriptPattern, in: html, options: .dotMatchesLineSeparators) {
            guard let raw = group.dropFirst().first else { continue }
            if raw.contains("aweme_detail") || raw.contains("RENDER_DATA") {
                texts.append(raw.removingPercentEncoding ?? raw)
            }
        }

        for text in texts {
            guard let object = jsonObjectAfterAwemeDetail(in: text) else { continue }
            collect(from: object, into: &result)
        }

        result.images = unique(result.images)
        result.videos = unique(result.videos)
        return result
    }

    private func jsonObjectAfterAwemeDetail(in text: String) -> [String: Any]? {
        guard let marker = text.range(of: "\"aweme_detail\"") else { return nil }
        let tail = text[marker.upperBound...]
        guard let open = tail.firstIndex(of: "{") else { return nil }

        var depth = 0
        var inString = false
        var escaped = false
        var close: String.Index?

        for index in tail[open...].indices {
            let character = tail[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }
            if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    close = index
                    break
                }
            }
        }

        guard let close else { return nil }
        let jsonText = String(tail[open...close])
        guard let data = jsonText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private func collect(from value: Any, into result: inout DouyinDetail, context: String = "") {
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                let lower = key.lowercased()
                if lower.contains("avatar") { continue }

                if result.sourceID == nil,
                   let value = child as? String,
                   lower == "aweme_id", value.count >= 8 {
                    result.sourceID = value
                }
                if result.description == nil,
                   let value = child as? String,
                   lower == "desc", !value.isEmpty {
                    result.description = value
                }
                if result.author == nil,
                   let value = child as? String,
                   lower == "nickname", !value.isEmpty {
                    result.author = value
                }
                if result.title == nil,
                   let value = child as? String,
                   ["title", "item_title"].contains(lower), !value.isEmpty {
                    result.title = value
                }

                let nextContext = "\(context) \(lower)"
                if let strings = child as? [String],
                   ["url_list", "urls", "image_urls"].contains(lower) {
                    for value in strings {
                        add(value, context: nextContext, to: &result)
                    }
                } else if let string = child as? String,
                          ["url", "display_url", "origin_url", "download_url"].contains(lower) {
                    add(string, context: nextContext, to: &result)
                } else {
                    collect(from: child, into: &result, context: nextContext)
                }
            }
            return
        }

        if let array = value as? [Any] {
            for child in array {
                collect(from: child, into: &result, context: context)
            }
        }
    }

    private func add(_ raw: String, context: String, to result: inout DouyinDetail) {
        let cleaned = raw
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\u002F"#, with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleaned),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else { return }

        let host = url.host()?.lowercased() ?? ""
        let path = url.path.lowercased()
        let ext = url.pathExtension.lowercased()

        if result.sourceID == nil {
            if let value = firstCapture(pattern: #"(\d{8,})"#, in: context) {
                result.sourceID = value
            }
        }

        let isImageHost = host.contains("douyinpic") || host.contains("byteimg")
        let isImagePath = path.contains("aweme_images")
            || ["jpg", "jpeg", "png", "webp", "awebp", "image", "gif", "apng"].contains(ext)
        if isImageHost && isImagePath,
           !path.contains("avatar"),
           !path.contains("image-cut-tos-priv"),
           !result.images.contains(url) {
            result.images.append(url)
        }

        let isVideo = host.contains("douyinvod")
            || ["mp4", "m3u8"].contains(ext)
            || path.contains("/video/")
        if isVideo, !result.videos.contains(url) {
            result.videos.append(url)
        }
    }

    private func unique(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        return urls.filter { url in
            let key = url.absoluteString
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
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

    private func captures(
        pattern: String,
        in text: String,
        options: NSRegularExpression.Options = []
    ) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        return regex.matches(in: text, options: [], range: range).map { match in
            (0..<match.numberOfRanges).compactMap { index in
                let r = match.range(at: index)
                guard r.location != NSNotFound else { return nil }
                return ns.substring(with: r)
            }
        }
    }
}
