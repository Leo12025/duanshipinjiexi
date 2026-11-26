import Foundation

struct XiaohongshuParser: PlatformParser {
    let source: MediaSource = .xiaohongshu
    let supportedHosts = ["xiaohongshu.com", "xhslink.com", "xhslink.cn"]

    func parse(url: URL) async throws -> ParsedMedia {
        let loaded: (String, URL)
        if let captured = try? await PublicPageLoader.loadXiaohongshuWithCapture(url: url),
           captured.0.localizedCaseInsensitiveContains("sns-webpic") {
            loaded = captured
        } else {
            loaded = try await PublicPageLoader.load(url: url)
        }
        let (html, finalURL) = loaded
        let metadata = HTMLMetadataExtractor.extract(html: html, finalURL: finalURL)
        let page = extractPageData(from: html)

        guard let sourceId = extractSourceID(from: finalURL, html: html) else {
            throw AppError.parsingFailed("无法提取小红书笔记 ID")
        }

        var assets = metadata.imageURLs.compactMap { url -> ImageAsset? in
            let host = url.host()?.lowercased() ?? ""
            guard host.contains("sns-webpic") || host.contains("xhscdn") else { return nil }
            guard let fileID = fileID(from: url.absoluteString),
                  let original = originalImageURL(fileID: fileID) else { return nil }
            return ImageAsset(url: original, livePhotoVideo: nil)
        } + page.assets
        var seenImage = Set<String>()
        assets = assets.filter { seenImage.insert($0.url.mediaDedupeKey).inserted }
        var videoURLs = metadata.videoURLs + page.videos
        videoURLs = unique(videoURLs)

        let videos = videoURLs.map {
            MediaQualityHeuristic.videoCandidate(for: $0, hint: metadata.videoQualityHints[$0])
        }
        let images = MediaQualityHeuristic.sortedImages(assets.map(\.url))
        let livePhotoVideos = assets.map(\.livePhotoVideo)
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
            livePhotoVideos: livePhotoVideos,
            videos: videos,
            audioURL: nil,
            needsAudioMux: false
        )
    }

    struct ImageAsset {
        let url: URL
        let livePhotoVideo: URL?
    }

    struct PageData {
        var title: String?
        var desc: String?
        var assets: [ImageAsset] = []
        var videos: [URL] = []

        var images: [URL] { assets.map(\.url) }
        var livePhotoVideos: [URL?] { assets.map(\.livePhotoVideo) }
    }

    func extractPageData(from html: String) -> PageData {
        var result = PageData()

        result.title = firstCapture(
            pattern: #"<meta[^>]+(?:name|property)=["']og:title["'][^>]+content=["']([^"']+)["'][^>]*>"#,
            in: html
        ).map(decode)

        result.desc = firstCapture(
            pattern: #""desc"\s*:\s*"((?:[^"\\]|\\.)*)""#,
            in: html
        ).map(decode)

        result.assets = extractImageAssets(from: html)

        if result.assets.isEmpty {
            let imagePattern = #"content=["'](https?://sns-webpic-[^"']+)["']"#
            for raw in captures(pattern: imagePattern, in: html) {
                guard let url = makeURL(from: raw),
                      let fileID = fileID(from: url.absoluteString),
                      let original = originalImageURL(fileID: fileID),
                      !result.assets.contains(where: { $0.url == original }) else { continue }
                result.assets.append(ImageAsset(url: original, livePhotoVideo: nil))
            }
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

    private func extractImageAssets(from html: String) -> [ImageAsset] {
        var assets: [ImageAsset] = []
        for key in ["imageList", "image_list", "images"] {
            for raw in jsonArrays(forKey: key, in: html) {
                guard let data = raw.data(using: .utf8),
                      let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else { continue }
                for item in array {
                    guard let dictionary = item as? [String: Any],
                          let imageURL = noteImageURL(in: dictionary) else { continue }
                    assets.append(ImageAsset(
                        url: imageURL,
                        livePhotoVideo: livePhotoVideoURL(in: dictionary)
                    ))
                }
                if !assets.isEmpty { break }
            }
            if !assets.isEmpty { break }
        }
        var seen = Set<String>()
        return assets.filter { seen.insert($0.url.mediaDedupeKey).inserted }
    }

    private func noteImageURL(in dictionary: [String: Any]) -> URL? {
        if let fileID = dictionary["fileId"] as? String, !fileID.isEmpty,
           let url = originalImageURL(fileID: fileID) {
            return url
        }
        var detailRaw: String?
        if let infoList = dictionary["infoList"] as? [Any] {
            for entry in infoList {
                guard let info = entry as? [String: Any] else { continue }
                let scene = (info["imageScene"] as? String)?.uppercased() ?? ""
                guard scene.isEmpty || scene == "H5_DTL" else { continue }
                if let raw = info["url"] as? String, isNoteImageString(raw) {
                    detailRaw = raw
                    break
                }
            }
        }
        if detailRaw == nil, let raw = dictionary["url"] as? String, isNoteImageString(raw) {
            detailRaw = raw
        }
        guard let raw = detailRaw,
              let fileID = fileID(from: raw),
              let url = originalImageURL(fileID: fileID) else { return nil }
        return url
    }

    private func fileID(from raw: String) -> String? {
        let cleaned = decode(raw)
            .replacingOccurrences(of: "\\u002F", with: "/")
            .replacingOccurrences(of: "\\/", with: "/")
        guard let url = URL(string: cleaned),
              let host = url.host()?.lowercased(),
              host.contains("xhscdn") else { return nil }
        let path = url.path
        let parts = path.split(separator: "/").map(String.init)
        guard let last = parts.last else { return nil }
        return last.split(separator: "!").first.map(String.init)
    }

    private func originalImageURL(fileID: String) -> URL? {
        URL(string: "https://ci.xiaohongshu.com/\(fileID)")
    }

    private func isNoteImageString(_ raw: String) -> Bool {
        guard let url = makeURL(from: raw) else { return false }
        return isNoteImage(url)
    }

    private func livePhotoVideoURL(in dictionary: [String: Any]) -> URL? {
        guard dictionary["livePhoto"] as? Bool == true,
              let stream = dictionary["stream"] as? [String: Any] else { return nil }
        for codec in ["h264", "h265", "h266", "av1"] {
            guard let items = stream[codec] as? [Any] else { continue }
            for entry in items {
                guard let info = entry as? [String: Any] else { continue }
                if let raw = info["masterUrl"] as? String,
                   let url = makeURL(from: raw) {
                    return url
                }
                if let backups = info["backupUrls"] as? [String],
                   let first = backups.first,
                   let url = makeURL(from: first) {
                    return url
                }
            }
        }
        return nil
    }

    private func jsonArrays(forKey key: String, in text: String) -> [String] {
        var arrays: [String] = []
        let marker = "\"\(key)\""
        var cursor = text.startIndex
        while cursor < text.endIndex,
              let found = text.range(of: marker, range: cursor..<text.endIndex) {
            var index = found.upperBound
            while index < text.endIndex, text[index] != "[" {
                if text[index] == "{" || text[index] == "\"" { break }
                index = text.index(after: index)
            }
            guard index < text.endIndex, text[index] == "[" else {
                cursor = found.upperBound
                continue
            }
            let start = index
            var depth = 0
            var inString = false
            var escaped = false
            var end: String.Index?
            while index < text.endIndex {
                let char = text[index]
                if inString {
                    if escaped { escaped = false }
                    else if char == "\\" { escaped = true }
                    else if char == "\"" { inString = false }
                } else {
                    if char == "\"" { inString = true }
                    else if char == "[" { depth += 1 }
                    else if char == "]" {
                        depth -= 1
                        if depth == 0 { end = index; break }
                    }
                }
                index = text.index(after: index)
            }
            guard let end else { break }
            arrays.append(String(text[start...end]))
            cursor = text.index(after: end)
        }
        return arrays
    }

    private func isNoteImage(_ url: URL) -> Bool {
        let host = url.host()?.lowercased() ?? ""
        let path = url.path.lowercased()
        guard host.contains("xhscdn") || host.contains("xiaohongshu") else { return false }
        guard !host.contains("avatar") && !path.contains("avatar") else { return false }
        return host.contains("sns-webpic")
            || path.contains("image")
            || ["jpg", "jpeg", "png", "webp", "gif", "apng"].contains(url.pathExtension.lowercased())
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
        var value = decode(raw)
            .replacingOccurrences(of: "%5C", with: "")
            .replacingOccurrences(of: "\\", with: "")
        if value.hasPrefix("//") { value = "https:" + value }
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
