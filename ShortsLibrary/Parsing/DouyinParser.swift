import Foundation

struct DouyinParser: PlatformParser {
    let source: MediaSource = .douyin
    let supportedHosts = ["douyin.com", "iesdouyin.com"]

    private static let detailMarkers = [
        "aweme_detail", "aweme_details", "awemeDetail", "item_detail", "itemInfo",
        "RENDER_DATA", "_ROUTER_DATA", "_SSR_DATA"
    ]

    struct VideoSource {
        let url: URL
        let context: String
        var isConvertedNoWatermark: Bool = false
    }

    func parse(url: URL) async throws -> ParsedMedia {
        let loaded: (String, URL)
        if let captured = try? await PublicPageLoader.loadDouyinWithCapture(url: url),
           captured.0.localizedCaseInsensitiveContains("aweme_detail") {
            loaded = captured
        } else {
            loaded = try await PublicPageLoader.loadWithoutLoginCheck(url: url)
        }
        let (html, finalURL) = loaded
        let metadata = HTMLMetadataExtractor.extract(html: html, finalURL: finalURL)
        let detail = extractDetail(from: html)

        let sourceId = extractSourceID(from: finalURL, html: html) ?? detail.sourceID
            ?? "\(finalURL.lastPathComponent)"
        guard !sourceId.isEmpty else {
            throw AppError.parsingFailed("无法提取抖音视频 ID")
        }

        let isVideoPage = Self.isVideoPage(finalURL)
        let audioURL = detail.audioURL ?? metadata.audioURLs.first

        var imageURLs = isVideoPage ? detail.images : metadata.imageURLs + detail.images
        imageURLs = unique(imageURLs)

        var videoSources: [VideoSource] = []
        if let uri = detail.playURI {
            if let playURL = Self.buildPlayURL(from: uri) {
                videoSources.append(VideoSource(
                    url: playURL,
                    context: "build_play_url play_addr ratio=0p line=1"
                ))
            }
            if let playURL = Self.buildPlayURL(from: uri, ratio: "1080p", line: 0) {
                videoSources.append(VideoSource(
                    url: playURL,
                    context: "build_play_url play_addr ratio=1080p line=0"
                ))
            }
        }
        for url in metadata.videoURLs {
            if let clean = Self.noWatermarkVariant(of: url) {
                videoSources.append(VideoSource(
                    url: clean,
                    context: "metadata play_addr",
                    isConvertedNoWatermark: true
                ))
                videoSources.append(VideoSource(url: url, context: "metadata download_addr"))
            } else {
                videoSources.append(VideoSource(url: url, context: "metadata"))
            }
        }
        videoSources.append(contentsOf: detail.videos.filter {
            audioURL != nil || !$0.isConvertedNoWatermark
        })
        videoSources = uniqueVideoSources(videoSources)

        let videos = videoSources.map { source in
            MediaQualityHeuristic.videoCandidate(
                for: source.url,
                hint: Self.mergedHint(metadata.videoQualityHints[source.url], context: source.context),
                sourceField: source.context,
                prefersNoWatermark: Self.prefersNoWatermark(source.context),
                isWatermarked: Self.isWatermarked(source.context)
            )
        }
        let images = MediaQualityHeuristic.sortedImages(imageURLs)
        if (videos.isEmpty && images.isEmpty) || (isVideoPage && videos.isEmpty) {
            if PublicPageLoader.requiresLogin(html: html) {
                throw AppError.loginRequired(MediaSource.douyin.displayName)
            }
            if !videos.isEmpty || !images.isEmpty {
                throw AppError.parsingFailed("未能提取抖音视频地址，请稍后重试")
            }
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
            coverURL: metadata.image ?? MediaQualityHeuristic.bestCover(from: images),
            images: images,
            videos: videos,
            audioURL: audioURL,
            needsAudioMux: audioURL != nil
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
            if let id = Self.firstCapture(pattern: pattern, in: html) {
                return id
            }
        }
        return nil
    }

    private static func isVideoPage(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.contains("/video/") || path.hasSuffix("/video")
    }

    struct DouyinDetail {
        var sourceID: String?
        var title: String?
        var author: String?
        var description: String?
        var images: [URL] = []
        var videos: [VideoSource] = []
        var audioURL: URL?
        var playURI: String?
    }

    func extractDetail(from html: String) -> DouyinDetail {
        var result = DouyinDetail()
        var texts = [html]

        let scriptPattern = #"<script\b[^>]*>([\s\S]{0,400000}?)</script>"#
        for group in captures(pattern: scriptPattern, in: html, options: .dotMatchesLineSeparators) {
            guard let raw = group.dropFirst().first else { continue }
            if Self.detailMarkers.contains(where: { raw.localizedCaseInsensitiveContains($0) }) {
                texts.append(raw.removingPercentEncoding ?? raw)
            }
        }

        for text in texts {
            for object in jsonObjects(in: text) {
                collect(from: object, into: &result)
            }
        }

        result.images = unique(result.images)
        result.videos = uniqueVideoSources(result.videos)
        return result
    }

    private func jsonObjects(in text: String) -> [[String: Any]] {
        var results: [[String: Any]] = []

        for marker in Self.detailMarkers {
            var searchStart = text.startIndex
            while let markerRange = text.range(
                of: marker,
                options: [.caseInsensitive],
                range: searchStart..<text.endIndex
            ) {
                searchStart = markerRange.upperBound
                let tail = text[markerRange.upperBound...]
                guard let open = tail.firstIndex(of: "{"),
                      let object = jsonObject(in: tail, from: open) else { continue }
                results.append(object)
            }
        }

        return results
    }

    private func jsonObject(in text: Substring, from open: String.Index) -> [String: Any]? {
        var depth = 0
        var inString = false
        var escaped = false
        var close: String.Index?

        for index in text[open...].indices {
            let character = text[index]
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
        let jsonText = String(text[open...close])
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

                var nextContext = "\(context) \(lower)"
                if result.playURI == nil,
                   lower == "uri",
                   let value = child as? String,
                   Self.isPlayURI(value),
                   nextContext.localizedCaseInsensitiveContains("play_addr") {
                    result.playURI = value
                }
                if ["bitrate", "bit_rate", "gear_name", "quality_type"].contains(lower) {
                    let scalar: String
                    if let number = child as? NSNumber {
                        scalar = number.stringValue
                    } else if let text = child as? String {
                        scalar = text
                    } else {
                        scalar = ""
                    }
                    if !scalar.isEmpty { nextContext += "=\(scalar)" }
                }
                if let strings = child as? [String],
                   ["url_list", "urls", "image_urls", "play_url_list", "play_addr_list"].contains(lower) {
                    for value in strings {
                        add(value, context: nextContext, to: &result)
                    }
                } else if let string = child as? String,
                          ["url", "display_url", "origin_url", "download_url", "play_url", "video_url", "source_url", "src", "uri", "audio_url", "music_url", "bgm_url"].contains(lower) {
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
        var cleaned = raw
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\u002F"#, with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerCleaned = cleaned.lowercased()
        if !lowerCleaned.contains("://"),
           cleaned.hasPrefix("/"),
           lowerCleaned.contains("/play/") || lowerCleaned.contains("/video/")
            || lowerCleaned.contains("/audio") || lowerCleaned.contains("/music") {
            cleaned = "https://aweme.snssdk.com" + cleaned
        }
        guard let url = URL(string: cleaned),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else { return }

        let host = url.host()?.lowercased() ?? ""
        let path = url.path.lowercased()
        let ext = url.pathExtension.lowercased()
        let isPageHost = host == "douyin.com" || host.hasSuffix(".douyin.com")
            || host == "iesdouyin.com" || host.hasSuffix(".iesdouyin.com")
        if isPageHost, !path.contains("/play/") { return }

        if result.sourceID == nil {
            if let value = Self.firstCapture(pattern: #"(\d{8,})"#, in: context) {
                result.sourceID = value
            }
        }

        let contextLower = context.lowercased()
        let imageContext = contextLower.contains("image")
            || contextLower.contains("cover")
            || contextLower.contains("poster")
            || contextLower.contains("thumbnail")
        let audioContext = contextLower.contains("audio")
            || contextLower.contains("music")
            || contextLower.contains("bgm")
        let isAudioExt = ["m4a", "mp3", "aac", "wav", "flac"].contains(ext)
        let isAudioPath = path.contains("/audio") || path.contains("/music")
        let isImageHost = host.contains("douyinpic") || host.contains("byteimg")
        let isImagePath = path.contains("aweme_images")
            || ["jpg", "jpeg", "png", "webp", "awebp", "image", "gif", "apng"].contains(ext)
            || imageContext
        if isImageHost && isImagePath,
           !path.contains("avatar"),
           !path.contains("image-cut-tos-priv"),
           !result.images.contains(url) {
            result.images.append(url)
        }

        if (audioContext || isAudioExt || isAudioPath), !imageContext {
            if result.audioURL == nil { result.audioURL = url }
            return
        }

        let isVideoHost = host.contains("douyinvod") || host.contains("snssdk") || host.contains("ixigua")
        let isVideoExt = ["mp4", "m3u8"].contains(ext)
        let isVideoPath = path.contains("/video/") || path.contains("/play/")
        if isVideoHost || isVideoExt || isVideoPath {
            if let clean = Self.noWatermarkVariant(of: url) {
                result.videos.append(VideoSource(
                    url: clean,
                    context: "\(context) play_addr",
                    isConvertedNoWatermark: true
                ))
                result.videos.append(VideoSource(url: url, context: "\(context) download_addr"))
            } else {
                result.videos.append(VideoSource(url: url, context: context))
            }
        }
    }

    private func unique(_ urls: [URL]) -> [URL] {
        URL.dedupeMedia(urls)
    }

    static func isPlayURI(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8, trimmed.first == "v" else { return false }
        return trimmed.dropFirst().allSatisfy { $0.isNumber || $0.isLetter }
    }

    static func buildPlayURL(from uri: String, ratio: String = "0p", line: Int = 1) -> URL? {
        guard isPlayURI(uri),
              var components = URLComponents(string: "https://aweme.snssdk.com/aweme/v1/play/") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "video_id", value: uri.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "ratio", value: ratio),
            URLQueryItem(name: "line", value: String(line))
        ]
        return components.url
    }

    private static func noWatermarkVariant(of url: URL) -> URL? {
        let host = url.host()?.lowercased() ?? ""
        guard url.path.lowercased().contains("/playwm/"),
              host.contains("snssdk") || host.contains("douyin") || host.contains("iesdouyin"),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.path = components.path.replacingOccurrences(
            of: "/playwm/",
            with: "/play/",
            options: [.caseInsensitive]
        )
        return components.url
    }

    private static func mergedHint(_ base: VideoQualityHint?, context: String) -> VideoQualityHint? {
        let lower = context.lowercased()
        guard lower.contains("bit_rate") || lower.contains("bitrate")
            || lower.contains("gear_name") || lower.contains("quality_type") else { return base }
        let bitrate = base?.bitrate
            ?? firstCapture(pattern: #"(?:bit_?rate=)(\d{4,9})"#, in: context).flatMap(Int.init)
        let quality = base?.quality
            ?? firstCapture(pattern: #"(?:gear_name|quality_type)=([A-Za-z0-9_]+)"#, in: context)
        if bitrate == nil && quality == nil { return base }
        return VideoQualityHint(
            width: base?.width,
            height: base?.height,
            bitrate: bitrate,
            quality: quality
        )
    }

    private static func prefersNoWatermark(_ context: String) -> Bool {
        let lower = context.lowercased()
        return lower.contains("play_addr")
            || lower.contains("bitrate")
            || lower.contains("bit_rate")
            || lower.contains("gear_name")
            || lower.contains("quality_type")
            || lower.contains("play_url")
            || lower.contains("video_url")
            || lower.contains("source_url")
            || lower.contains("uri")
            || (lower.contains("/play/") && !lower.contains("download"))
    }

    private static func isWatermarked(_ context: String) -> Bool {
        let lower = context.lowercased()
        let hasWatermarkSource = lower.contains("download") || lower.contains("watermark")
        let hasCleanSource = lower.contains("play_addr") || lower.contains("bitrate") || lower.contains("bit_rate")
        return hasWatermarkSource && !hasCleanSource
    }

    private static func videoContextScore(_ context: String) -> Int {
        if isWatermarked(context) { return 0 }
        if prefersNoWatermark(context) { return 2 }
        return 1
    }

    private func uniqueVideoSources(_ sources: [VideoSource]) -> [VideoSource] {
        var order: [URL] = []
        var best: [URL: VideoSource] = [:]

        for source in sources {
            if let existing = best[source.url] {
                if Self.videoContextScore(source.context) > Self.videoContextScore(existing.context) {
                    best[source.url] = source
                }
            } else {
                order.append(source.url)
                best[source.url] = source
            }
        }

        return order.compactMap { best[$0] }
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
