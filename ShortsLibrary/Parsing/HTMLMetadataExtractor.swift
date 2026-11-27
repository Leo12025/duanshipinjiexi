import Foundation

struct PageMetadata {
    var title: String?
    var description: String?
    var author: String?
    var image: URL?
    var imageURLs: [URL] = []
    var videoURLs: [URL] = []
    var audioURLs: [URL] = []
    var videoQualityHints: [URL: VideoQualityHint] = [:]
    var finalURL: URL
    var rawHTML: String
}

enum HTMLMetadataExtractor {
    static func extract(html: String, finalURL: URL) -> PageMetadata {
        var result = PageMetadata(finalURL: finalURL, rawHTML: html)

        let metaTags = capture(pattern: #"(<meta\b[^>]*>)"#, in: html)
            .compactMap { $0.first }
        for tag in metaTags {
            let attributes = self.attributes(in: tag)
            guard let key = (attributes["property"] ?? attributes["name"])?.lowercased() else { continue }
            let value = decode(attributes["content"] ?? "")

            switch key {
            case "og:title", "twitter:title":
                if result.title == nil { result.title = value }
            case "og:description", "description", "twitter:description":
                if result.description == nil { result.description = value }
            case "og:image", "twitter:image", "twitter:image:src":
                if let url = Self.httpURL(value) {
                    if result.image == nil { result.image = url }
                    if !result.imageURLs.contains(url) { result.imageURLs.append(url) }
                }
            case "og:video", "og:video:secure_url", "twitter:player":
                if let url = Self.httpURL(value), !result.videoURLs.contains(url) {
                    result.videoURLs.append(url)
                }
            case "og:audio", "twitter:player:stream":
                if let url = Self.httpURL(value), !result.audioURLs.contains(url) {
                    result.audioURLs.append(url)
                }
            case "author", "og:article:author", "article:author":
                if result.author == nil { result.author = value }
            default:
                break
            }
        }

        applyJSONLD(html: html, to: &result)
        applyPublicJSONFallbacks(html: html, to: &result)

        for url in embeddedVideoURLs(in: html) where !result.videoURLs.contains(url) {
            result.videoURLs.append(url)
        }
        for url in embeddedImageURLs(in: html) where !result.imageURLs.contains(url) {
            result.imageURLs.append(url)
        }

        let dash = bilibiliDashURLs(in: html)
        for url in dash.video where !result.videoURLs.contains(url) {
            result.videoURLs.append(url)
        }
        for url in dash.audio where !result.audioURLs.contains(url) {
            result.audioURLs.append(url)
        }
        for url in embeddedAudioURLs(in: html) where !result.audioURLs.contains(url) {
            result.audioURLs.append(url)
        }

        result.videoQualityHints = videoQualityHints(in: html)

        if result.image == nil, let first = result.imageURLs.first {
            result.image = first
        }

        return result
    }

    private static func applyJSONLD(html: String, to result: inout PageMetadata) {
        let pattern = #"<script\b[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>(.*?)</script>"#
        let blocks = capture(pattern: pattern, in: html, options: [.dotMatchesLineSeparators])

        for block in blocks {
            guard let raw = block.dropFirst().first,
                  let data = raw.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else { continue }

            for dictionary in flatten(object) {
                if result.title == nil {
                    result.title = dictionary["headline"] as? String ?? dictionary["name"] as? String
                }
                if result.description == nil {
                    result.description = dictionary["description"] as? String
                }
                if result.author == nil {
                    if let author = dictionary["author"] as? String {
                        result.author = author
                    } else if let author = dictionary["author"] as? [String: Any],
                              let name = author["name"] as? String {
                        result.author = name
                    }
                }
                var imageValues: [String] = []
                if let thumbnail = firstString(in: dictionary["thumbnailUrl"]) {
                    imageValues.append(thumbnail)
                }
                if let images = dictionary["image"] as? [String] {
                    imageValues.append(contentsOf: images)
                } else if let image = dictionary["image"] as? String {
                    imageValues.append(image)
                }
                for value in imageValues {
                    guard let url = httpURL(value) else { continue }
                    if result.image == nil { result.image = url }
                    if !result.imageURLs.contains(url) { result.imageURLs.append(url) }
                }

                for key in ["contentUrl", "embedUrl"] {
                    if let value = firstString(in: dictionary[key]),
                       let url = httpURL(value),
                       !result.videoURLs.contains(url) {
                        result.videoURLs.append(url)
                    }
                }
                if let value = firstString(in: dictionary["url"]),
                   let url = httpURL(value),
                   isVideoURL(url),
                   !result.videoURLs.contains(url) {
                    result.videoURLs.append(url)
                }
            }
        }
    }

    private static func applyPublicJSONFallbacks(html: String, to result: inout PageMetadata) {
        if result.title == nil,
           let raw = firstCaptureOutsideAuxiliaryContext(
            pattern: #""(?:title|name)"\s*:\s*"((?:[^"\\]|\\.)*)""#,
            in: html
           ) {
            result.title = decode(raw)
        }
        if result.author == nil,
           let raw = firstCaptureOutsideAuxiliaryContext(
            pattern: #""(?:nickname|nickName|userName|authorName)"\s*:\s*"((?:[^"\\]|\\.)*)""#,
            in: html
           ) {
            result.author = decode(raw)
        }
        if result.description == nil,
           let raw = firstCaptureOutsideAuxiliaryContext(
            pattern: #""(?:desc|description|caption)"\s*:\s*"((?:[^"\\]|\\.)*)""#,
            in: html
           ) {
            result.description = decode(raw)
        }
    }

    private static func firstCaptureOutsideAuxiliaryContext(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        for match in regex.matches(in: text, options: [], range: range) where match.numberOfRanges > 1 {
            let capture = match.range(at: 1)
            guard capture.location != NSNotFound else { continue }
            let start = max(0, match.range(at: 0).location - 200)
            let preceding = ns.substring(
                with: NSRange(location: start, length: match.range(at: 0).location - start)
            ).lowercased()
            let auxiliaryContexts = [
                "music", "audio", "bgm", "sound",
                "popup", "quickappstrategy", "strongmessage", "dialog", "alert", "modal"
            ]
            if auxiliaryContexts.contains(where: { preceding.contains($0) }) {
                continue
            }
            return ns.substring(with: capture)
        }
        return nil
    }

    private static func embeddedVideoURLs(in html: String) -> [URL] {
        var urls: [URL] = []
        let patterns = [
            #""playUrl"\s*:\s*"((?:[^"\\]|\\.)*)""#,
            #""videoUrl"\s*:\s*"((?:[^"\\]|\\.)*)""#,
            #""play_url"\s*:\s*"((?:[^"\\]|\\.)*)""#,
            #""backupUrl"\s*:\s*\[(.*?)\]"#,
            #""backup_url"\s*:\s*\[(.*?)\]"#,
            #""url"\s*:\s*\[(.*?)\]"#
        ]

        for pattern in patterns {
            for group in capture(pattern: pattern, in: html, options: [.dotMatchesLineSeparators]) {
                guard group.count > 1 else { continue }
                for url in quotedURLs(in: group[1]) where isVideoURL(url) && !urls.contains(url) {
                    urls.append(url)
                }
            }
        }

        for url in quotedURLs(in: html) where isVideoURL(url) && !urls.contains(url) {
            urls.append(url)
        }
        return urls
    }

    private static func embeddedImageURLs(in html: String) -> [URL] {
        var urls: [URL] = []
        let patterns = [
            #""imageList"\s*:\s*\[(.*?)\]"#,
            #""images"\s*:\s*\[(.*?)\]"#,
            #""image"\s*:\s*\[(.*?)\]"#,
            #""pictures"\s*:\s*\[(.*?)\]"#,
            #""image_urls"\s*:\s*\[(.*?)\]"#,
            #""url_list"\s*:\s*\[(.*?)\]"#,
            #""coverUrls"\s*:\s*\[(.*?)\]"#,
            #""coverUrlList"\s*:\s*\[(.*?)\]"#
        ]

        for pattern in patterns {
            for group in capture(pattern: pattern, in: html, options: [.dotMatchesLineSeparators]) {
                guard group.count > 1 else { continue }
                for url in quotedURLs(in: group[1]) where isImageURL(url) && !urls.contains(url) {
                    urls.append(url)
                }
            }
        }
        return urls
    }

    private static func bilibiliDashURLs(in html: String) -> (video: [URL], audio: [URL]) {
        func urls(for key: String) -> [URL] {
            let pattern = #""\#(key)"\s*:\s*\[\s*\{[\s\S]{0,3000}?"baseUrl"\s*:\s*"((?:[^"\\]|\\.)*)""#
            return capture(pattern: pattern, in: html, options: [.dotMatchesLineSeparators])
                .compactMap { group in
                    guard let raw = group.dropFirst().first else { return nil }
                    return URL(string: cleanedURLString(raw))
                }
        }
        return (urls(for: "video"), urls(for: "audio"))
    }

    private static func embeddedAudioURLs(in html: String) -> [URL] {
        var urls: [URL] = []
        let patterns = [
            #""audioUrl"\s*:\s*"((?:[^"\\]|\\.)*)""#,
            #""audio_url"\s*:\s*"((?:[^"\\]|\\.)*)""#
        ]

        for pattern in patterns {
            for group in capture(pattern: pattern, in: html) {
                guard let raw = group.dropFirst().first else { continue }
                if let url = URL(string: cleanedURLString(raw)), isAudioURL(url), !urls.contains(url) {
                    urls.append(url)
                }
            }
        }

        for url in quotedURLs(in: html) where isAudioURL(url) && !urls.contains(url) {
            urls.append(url)
        }
        return urls
    }

    private static func quotedURLs(in text: String) -> [URL] {
        capture(pattern: #""(https?:[^"]+)""#, in: text).compactMap { pair in
            guard let raw = pair.dropFirst().first else { return nil }
            return URL(string: cleanedURLString(raw))
        }
    }

    private static func cleanedURLString(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: #"\\u002F"#, with: "/")
            .replacingOccurrences(of: #"\u002F"#, with: "/")
            .replacingOccurrences(of: #"\\/"#, with: "/")
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: "%5C", with: "")
            .replacingOccurrences(of: "\\", with: "")
            .replacingOccurrences(of: "u0026", with: "&")
            .replacingOccurrences(of: "u003D", with: "=")
    }

    private static func isVideoURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        let ext = url.pathExtension.lowercased()
        let host = url.host()?.lowercased() ?? ""
        if ["m4a", "mp3", "wav", "aac", "flac"].contains(ext) { return false }
        if host == "douyin.com"
            || host.hasSuffix(".douyin.com")
            || host == "iesdouyin.com"
            || host.hasSuffix(".iesdouyin.com") {
            return false
        }
        if (host.contains("bilivideo") || host.contains("sns-video") || host.contains("douyinvod"))
            && (path.isEmpty || path == "/") { return false }
        if (host.contains("snssdk") || host.contains("ixigua"))
            && (path.contains("/play/") || path.contains("/video/")) { return true }
        if host.contains("video.qq.com") {
            let full = url.absoluteString.lowercased()
            return path.contains("/video")
                || ["mp4", "m3u8", "mov"].contains(ext)
                || full.contains("mime_type=video")
        }
        return ["mp4", "m3u8", "mov"].contains(ext)
            || host.contains("bilivideo")
            || host.contains("sns-video")
            || host.contains("douyinvod")
    }

    private static func isAudioURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        let ext = url.pathExtension.lowercased()
        let host = url.host()?.lowercased() ?? ""
        return ["m4a", "mp3", "wav", "aac", "flac"].contains(ext)
            || path.contains("/audio")
            || host.contains("audio")
    }

    private static func isImageURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let host = url.host()?.lowercased() ?? ""
        let path = url.path.lowercased()
        let imageExtensions = ["jpg", "jpeg", "png", "apng", "gif", "webp", "heic", "image", "awebp"]
        if path.contains("avatar") || path.contains("image-cut-tos-priv") { return false }
        if ["mp4", "m3u8", "mov", "webm"].contains(ext) { return false }
        if host.contains("sns-video") || path.contains("/stream/") { return false }
        return imageExtensions.contains(ext)
            || host.contains("xhscdn")
            || host.contains("sns-webpic")
            || host.contains("hdslb")
            || host.contains("douyinpic")
            || host.contains("byteimg")
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1 else { return nil }
        let r = match.range(at: 1)
        guard r.location != NSNotFound else { return nil }
        return ns.substring(with: r)
    }

    private static func videoQualityHints(in html: String) -> [URL: VideoQualityHint] {
        var hints: [URL: VideoQualityHint] = [:]
        let ns = html as NSString
        let pattern = #""(?:width|video_width)"\s*:\s*(\d{3,4})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return hints }
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length))

        for match in matches {
            let location = match.range(at: 0).location
            let start = max(0, location - 500)
            let length = min(ns.length - start, 1400)
            let window = ns.substring(with: NSRange(location: start, length: length))

            guard let width = firstCapture(pattern: #""(?:width|video_width)"\s*:\s*(\d{3,4})"#, in: window),
                  let height = firstCapture(pattern: #""(?:height|video_height)"\s*:\s*(\d{3,4})"#, in: window),
                  let widthValue = Int(width), let heightValue = Int(height) else { continue }

            let bitrate = firstCapture(pattern: #""(?:bitrate|bandwidth)"\s*:\s*(\d{3,9})"#, in: window)
                .flatMap(Int.init)
            let dashID = firstCapture(pattern: #""id"\s*:\s*(\d+)"#, in: window)
            let quality = dashID.flatMap(dashQualityLabel)
                ?? firstCapture(pattern: #""(?:quality|qualityDescription)"\s*:\s*"([^"]{1,20})""#, in: window)

            let hint = VideoQualityHint(
                width: widthValue,
                height: heightValue,
                bitrate: bitrate,
                quality: quality
            )
            for url in quotedURLs(in: window) where isVideoURL(url) {
                let current = (hints[url]?.width ?? 0) * (hints[url]?.height ?? 0)
                if widthValue * heightValue > current { hints[url] = hint }
            }
        }
        return hints
    }

    private static func dashQualityLabel(_ id: String) -> String? {
        switch id {
        case "80": return "1080P"
        case "64": return "720P"
        case "32": return "480P"
        case "16": return "360P"
        default: return nil
        }
    }

    private static func flatten(_ value: Any) -> [[String: Any]] {
        if let dictionary = value as? [String: Any] {
            if let graph = dictionary["@graph"] as? [Any] {
                return graph.flatMap(flatten)
            }
            return [dictionary]
        }
        if let array = value as? [Any] {
            return array.flatMap(flatten)
        }
        return []
    }

    private static func firstString(in value: Any?) -> String? {
        if let string = value as? String { return string }
        if let array = value as? [String] { return array.first }
        return nil
    }

    private static func attributes(in tag: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in capture(pattern: #"([\w:-]+)\s*=\s*["']([^"']*)["']"#, in: tag) {
            guard pair.count >= 3 else { continue }
            result[pair[1].lowercased()] = decode(pair[2])
        }
        return result
    }

    private static func capture(
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

    private static func httpURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else { return nil }
        return url
    }

    private static func decode(_ raw: String) -> String {
        var value = raw
        let replacements = [
            ("&amp;", "&"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&nbsp;", " ")
        ]
        for (token, replacement) in replacements {
            value = value.replacingOccurrences(of: token, with: replacement)
        }

        let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
        if let data = "\"\(escaped)\"".data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? String {
            return decoded
        }
        return value
    }
}
