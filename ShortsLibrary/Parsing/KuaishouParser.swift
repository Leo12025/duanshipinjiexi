import Foundation

struct KuaishouParser: PlatformParser {
    let source: MediaSource = .kuaishou
    let supportedHosts = ["kuaishou.com", "chenzhongtech.com", "gifshow.com"]

    private static let nonContentTitles = [
        "即将离开微信，打开其他应用", "即将离开微信", "打开其他应用"
    ]

    static func resolvedTitle(metadata: PageMetadata, sourceID: String) -> String {
        for value in [metadata.description, metadata.title] {
            guard let value else { continue }
            let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !nonContentTitles.contains(title) else { continue }
            return title
        }
        return "快手内容 \(sourceID)"
    }

    func parse(url: URL) async throws -> ParsedMedia {
        let (html, finalURL) = try await PublicPageLoader.load(url: url)
        let metadata = HTMLMetadataExtractor.extract(html: html, finalURL: finalURL)

        guard let sourceId = extractSourceID(from: finalURL, html: html) else {
            throw AppError.parsingFailed("无法提取快手视频 ID")
        }

        let manifestHints = manifestQualityHints(from: html)
        var hints = metadata.videoQualityHints
        for (url, hint) in manifestHints {
            let current = (hints[url]?.width ?? 0) * (hints[url]?.height ?? 0)
            if (hint.width ?? 0) * (hint.height ?? 0) > current { hints[url] = hint }
        }
        let videos = metadata.videoURLs.map {
            MediaQualityHeuristic.videoCandidate(for: $0, hint: hints[$0])
        }
        var imageURLs = metadata.imageURLs
        if let atlas = atlasImages(from: html), !atlas.urls.isEmpty {
            imageURLs = atlas.urls
            if atlas.coverIsLarger, let cover = atlas.cover {
                imageURLs[0] = cover
            }
        }
        let images = MediaQualityHeuristic.sortedImages(dedupeImages(imageURLs))
        guard !videos.isEmpty || !images.isEmpty else {
            throw AppError.noMedia
        }

        return ParsedMedia(
            source: .kuaishou,
            sourceId: sourceId,
            kind: MediaKindResolver.resolve(videos: videos.count, images: images.count, audios: 0),
            title: Self.resolvedTitle(metadata: metadata, sourceID: sourceId),
            author: metadata.author,
            caption: metadata.description,
            pageURL: finalURL,
            coverURL: metadata.image ?? MediaQualityHeuristic.bestCover(from: images),
            images: images,
            videos: videos,
            audioURL: nil,
            needsAudioMux: false
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

    private func dedupeImages(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.path).inserted }
    }

    private struct AtlasInfo {
        let urls: [URL]
        let cover: URL?
        let coverIsLarger: Bool
    }

    private func initialState(from html: String) -> [String: Any]? {
        guard let marker = html.range(of: "window.INIT_STATE") else { return nil }
        var index = html.index(marker.lowerBound, offsetBy: "window.INIT_STATE".count)
        while index < html.endIndex, html[index] != "{" {
            if html[index] == "<" { return nil }
            index = html.index(after: index)
        }
        guard index < html.endIndex else { return nil }
        let start = index
        var depth = 0
        var inString = false
        var escaped = false
        while index < html.endIndex {
            let char = html[index]
            if inString {
                if escaped { escaped = false }
                else if char == "\\" { escaped = true }
                else if char == "\"" { inString = false }
            } else {
                if char == "\"" { inString = true }
                else if char == "{" { depth += 1 }
                else if char == "}" {
                    depth -= 1
                    if depth == 0 {
                        let raw = String(html[start...index])
                        return (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any]
                    }
                }
            }
            index = html.index(after: index)
        }
        return nil
    }

    private func walkObjects(in value: Any, visit: ([String: Any]) -> Void) {
        if let dictionary = value as? [String: Any] {
            visit(dictionary)
            for nested in dictionary.values { walkObjects(in: nested, visit: visit) }
        } else if let array = value as? [Any] {
            for nested in array { walkObjects(in: nested, visit: visit) }
        }
    }

    private func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let double = value as? Double { return Int(double) }
        return nil
    }

    private func atlasImages(from html: String) -> AtlasInfo? {
        guard let state = initialState(from: html) else { return nil }
        var result: AtlasInfo?
        walkObjects(in: state) { dictionary in
            guard result == nil,
                  let ext = dictionary["ext_params"] as? [String: Any],
                  let atlas = ext["atlas"] as? [String: Any],
                  let list = atlas["list"] as? [String], !list.isEmpty else { return }

            var cdns = atlas["cdn"] as? [String] ?? []
            if cdns.isEmpty, let entries = atlas["cdnList"] as? [[String: Any]] {
                cdns = entries.compactMap { $0["cdn"] as? String }
            }
            let base = cdns.first ?? "p2.a.yximgs.com"
            let urls = list.compactMap { path -> URL? in
                let normalized = path.hasPrefix("/") ? path : "/" + path
                return URL(string: "https://\(base)\(normalized)")
            }
            let cover = ((dictionary["coverUrls"] as? [[String: Any]])?.first?["url"] as? String)
                .flatMap(URL.init(string:))
            let sizes = atlas["size"] as? [[String: Any]]
            let photoPixels = (intValue(dictionary["width"]) ?? 0) * (intValue(dictionary["height"]) ?? 0)
            let atlasPixels = (intValue(sizes?.first?["w"]) ?? 0) * (intValue(sizes?.first?["h"]) ?? 0)
            result = AtlasInfo(
                urls: urls,
                cover: cover,
                coverIsLarger: cover != nil && photoPixels > atlasPixels && atlasPixels > 0
            )
        }
        return result
    }

    private func manifestQualityHints(from html: String) -> [URL: VideoQualityHint] {
        guard let state = initialState(from: html) else { return [:] }
        var hints: [URL: VideoQualityHint] = [:]
        walkObjects(in: state) { dictionary in
            guard let manifest = dictionary["manifest"] as? [String: Any],
                  let sets = manifest["adaptationSet"] as? [[String: Any]] else { return }
            for set in sets {
                guard let representations = set["representation"] as? [[String: Any]] else { continue }
                for representation in representations {
                    let width = intValue(representation["width"])
                    let height = intValue(representation["height"])
                    let bitrate = intValue(representation["avgBitrate"])
                        ?? intValue(representation["bitrate"])
                    let quality = (representation["qualityType"] as? String)
                        ?? (representation["qualityLabel"] as? String)
                    let hint = VideoQualityHint(width: width, height: height, bitrate: bitrate, quality: quality)
                    var urls: [URL] = []
                    for key in ["backupUrl", "backup_urls", "url", "mainUrl", "playUrl"] {
                        if let raw = representation[key] as? String, let url = URL(string: raw) { urls.append(url) }
                        if let rawList = representation[key] as? [String] {
                            urls.append(contentsOf: rawList.compactMap(URL.init(string:)))
                        }
                    }
                    for url in urls {
                        let current = (hints[url]?.width ?? 0) * (hints[url]?.height ?? 0)
                        if (width ?? 0) * (height ?? 0) > current { hints[url] = hint }
                    }
                }
            }
        }
        return hints
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
