import Foundation

struct WechatChannelsParser: PlatformParser {
    let source: MediaSource = .wechatChannels
    let supportedHosts = ["weixin.qq.com", "channels.weixin.qq.com", "finder.video.qq.com", "video.qq.com"]

    struct FeedInfo {
        var description: String?
        var author: String?
        var coverURL: URL?
        var galleryImages: [URL] = []
        var videoURLs: [URL] = []
    }

    func parse(url: URL) async throws -> ParsedMedia {
        let loaded: (String, URL)
        if let captured = try? await PublicPageLoader.loadWechatChannelsWithCapture(url: url),
           !captured.0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            loaded = captured
        } else {
            loaded = try await PublicPageLoader.loadWithoutLoginCheck(url: url)
        }
        let (html, finalURL) = loaded

        let metadata = HTMLMetadataExtractor.extract(html: html, finalURL: finalURL)
        let feed = Self.extractFeedInfo(from: html)
        let sourceID = Self.extractSourceID(from: finalURL, html: html)
            ?? finalURL.lastPathComponent
        guard !sourceID.isEmpty else {
            throw AppError.parsingFailed("无法提取视频号内容 ID")
        }

        let videos = URL.dedupeMedia(metadata.videoURLs + feed.videoURLs).map {
            MediaQualityHeuristic.videoCandidate(for: $0, hint: metadata.videoQualityHints[$0])
        }
        let images = URL.dedupeMedia(metadata.imageURLs + feed.galleryImages)
        guard !videos.isEmpty || !images.isEmpty else {
            throw AppError.parsingFailed("视频号 Web 预览未提供可下载的视频地址，暂时无法下载该作品")
        }

        let audioURL = metadata.audioURLs.first
        let caption = feed.description ?? metadata.description
        let coverURL = feed.coverURL ?? metadata.image ?? MediaQualityHeuristic.bestCover(from: images)

        return ParsedMedia(
            source: source,
            sourceId: sourceID,
            kind: MediaKindResolver.resolve(videos: videos.count, images: images.count, audios: 0),
            title: metadata.title ?? caption ?? "视频号内容 \(sourceID)",
            author: metadata.author ?? feed.author,
            caption: caption,
            pageURL: finalURL,
            coverURL: coverURL,
            images: MediaQualityHeuristic.sortedImages(images),
            videos: videos,
            audioURL: audioURL,
            needsAudioMux: audioURL != nil
        )
    }

    static func extractSourceID(from url: URL, html: String) -> String? {
        let patterns = [
            #"/sph/([A-Za-z0-9_-]+)"#,
            #"/finder-preview/([A-Za-z0-9_-]+)"#,
            #"/post/([A-Za-z0-9_-]+)"#,
            #"(?:object_id|objectId|objectNonceId)[\\":=\\s]+([A-Za-z0-9_-]{8,})"#
        ]
        for pattern in patterns {
            if let value = firstCapture(pattern: pattern, in: html) {
                return value
            }
            if let value = firstCapture(pattern: pattern, in: url.absoluteString) {
                return value
            }
        }

        let last = url.pathComponents.filter { $0 != "/" }.last ?? ""
        return last.isEmpty ? nil : last
    }

    static func extractFeedInfo(from html: String) -> FeedInfo {
        var result = FeedInfo()

        if let author = jsonObjectAfter(marker: "\"authorInfo\"", in: html) {
            collectFeed(author, into: &result, context: "authorInfo")
        }
        if let feed = jsonObjectAfter(marker: "\"feedInfo\"", in: html) {
            collectFeed(feed, into: &result, context: "feedInfo")
        }

        result.videoURLs = URL.dedupeMedia(result.videoURLs)
        result.galleryImages = URL.dedupeMedia(result.galleryImages)
        return result
    }

    private static func collectFeed(_ value: Any, into result: inout FeedInfo, context: String) {
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                let lower = key.lowercased()
                let nextContext = "\(context) \(lower)"
                if let string = child as? String {
                    if result.description == nil,
                       lower == "description", !string.isEmpty,
                       !nextContext.contains("author") {
                        result.description = string
                    }
                    if result.author == nil,
                       lower == "nickname", !string.isEmpty {
                        result.author = string
                    }
                    if let url = httpURL(string) {
                        if lower == "coverurl" {
                            result.coverURL = url
                        } else if ["videourl", "playurl", "downloadurl", "mediaurl"].contains(lower) {
                            result.videoURLs.append(url)
                        } else if ["url", "picurl", "origurl", "imageurl"].contains(lower),
                                  nextContext.contains("picinfo") || nextContext.contains("image") {
                            result.galleryImages.append(url)
                        }
                    }
                } else {
                    collectFeed(child, into: &result, context: nextContext)
                }
            }
            return
        }

        if let array = value as? [Any] {
            for child in array {
                collectFeed(child, into: &result, context: context)
            }
        }
    }

    private static func httpURL(_ string: String) -> URL? {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else { return nil }
        return url
    }

    private static func jsonObjectAfter(marker: String, in text: String) -> [String: Any]? {
        guard let markerRange = text.range(of: marker, options: [.caseInsensitive]) else { return nil }
        let tail = text[markerRange.upperBound...]
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

    private static func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captureRange])
    }
}
