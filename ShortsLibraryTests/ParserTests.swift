import XCTest
@testable import ShortsLibrary

final class ParserTests: XCTestCase {
    func testLinkExtraction() async {
        let text = "分享文案 https://www.douyin.com/video/7123456789012345678 复制打开"
        XCTAssertEqual(
            LinkExtractor.firstURL(in: text)?.absoluteString,
            "https://www.douyin.com/video/7123456789012345678"
        )
        let platform = await LinkIngestService.detectPlatform(in: text)
        XCTAssertEqual(platform, "抖音")
    }

    func testKuaishouShareTextExtraction() {
        let text = #"""
        https://v.kuaishou.com/KLn1EMbt 普通的一天里，也藏着不动声色的喜欢"少年感 "阳光帅气 "记录美好时光 该作品在快手被播放过2.3万次，点击链接，打开【快手】直接观看！
        """#
        XCTAssertEqual(
            LinkExtractor.firstURL(in: text)?.absoluteString,
            "https://v.kuaishou.com/KLn1EMbt"
        )
    }

    func testMetadataExtraction() {
        let html = """
        <html><head>
        <meta property="og:title" content="测试视频">
        <meta property="og:video" content="https://cdn.example.com/video.mp4">
        <meta property="og:image" content="https://cdn.example.com/cover.jpg">
        <meta name="author" content="作者A">
        </head></html>
        """
        let metadata = HTMLMetadataExtractor.extract(
            html: html,
            finalURL: URL(string: "https://www.douyin.com/video/1")!
        )
        XCTAssertEqual(metadata.title, "测试视频")
        XCTAssertEqual(metadata.author, "作者A")
        XCTAssertEqual(metadata.videoURLs.count, 1)
        XCTAssertEqual(metadata.imageURLs.count, 1)
    }

    func testKuaishouMobileUserAgent() {
        let kuaishouURL = URL(string: "https://v.kuaishou.com/KLn1EMbt")!
        XCTAssertEqual(NetworkClient.userAgent(for: kuaishouURL), NetworkClient.mobileUserAgent)

        let douyinURL = URL(string: "https://www.douyin.com/video/1")!
        XCTAssertEqual(NetworkClient.userAgent(for: douyinURL), NetworkClient.defaultUserAgent)
    }

    func testKuaishouMobileMetadataExtraction() {
        let html = #"""
        {"photoId":"3xg9pj34ceerfeu","coverUrls":[{"cdn":"p23.a.yximgs.com","url":"https://p23.a.yximgs.com/upic/2026/11/21/17/cover.jpg"}],"manifest":{"video":{"adaptationSet":[{"representation":[{"backupUrl":["https://v1.kwaicdn.com/upic/2026/11/21/17/video.mp4?pkey=abc&tt=b"]}]}]}}}
        """#
        let metadata = HTMLMetadataExtractor.extract(
            html: html,
            finalURL: URL(string: "https://m.gifshow.com/fw/photo/3xg9pj34ceerfeu")!
        )
        XCTAssertTrue(metadata.videoURLs.contains { $0.host() == "v1.kwaicdn.com" })
        XCTAssertTrue(metadata.imageURLs.contains { $0.host() == "p23.a.yximgs.com" })
    }

    func testDouyinDetailExtractionFromRouterData() {
        let html = #"""
        <script>window._ROUTER_DATA = {"aweme_detail":{"aweme_id":"7711741462283352058","video":{"play_addr":{"url_list":["https://v3-web.douyinvod.com/video.mp4"]}},"image_posters":{"url_list":["https://p3.douyinpic.com/obj/aweme_images/cover.jpg"]}}}</script>
        """#
        let detail = DouyinParser().extractDetail(from: html)
        XCTAssertEqual(detail.sourceID, "7711741462283352058")
        XCTAssertTrue(detail.videos.contains { $0.absoluteString.contains("douyinvod.com/video.mp4") })
        XCTAssertTrue(detail.images.contains { $0.absoluteString.contains("douyinpic.com") })
    }

    func testDouyinRelativePlayURI() {
        let html = #"""
        <script>window._ROUTER_DATA = {"aweme_detail":{"video":{"play_addr":{"uri":"/aweme/v1/play/?video_id=abc"}}}}</script>
        """#
        let detail = DouyinParser().extractDetail(from: html)
        XCTAssertTrue(detail.videos.contains {
            $0.host() == "aweme.snssdk.com" && $0.path.contains("/play/")
        })
    }

    func testQualityHintFromStructuredJSON() {
        let html = #"""
        {"url":"https://cdn.example.com/video.mp4","width":1920,"height":1080,"bitrate":3000000}
        """#
        let metadata = HTMLMetadataExtractor.extract(
            html: html,
            finalURL: URL(string: "https://www.douyin.com/video/1")!
        )
        let url = URL(string: "https://cdn.example.com/video.mp4")!
        let hint = metadata.videoQualityHints[url]
        XCTAssertEqual(hint?.width, 1920)
        XCTAssertEqual(hint?.height, 1080)
        let candidate = MediaQualityHeuristic.videoCandidate(for: url, hint: hint)
        XCTAssertEqual(candidate.quality, "1920x1080")
    }

    func testKindResolution() {
        XCTAssertEqual(MediaKindResolver.resolve(videos: 1, images: 0, audios: 0), .video)
        XCTAssertEqual(MediaKindResolver.resolve(videos: 0, images: 1, audios: 0), .image)
        XCTAssertEqual(MediaKindResolver.resolve(videos: 0, images: 3, audios: 0), .imageText)
        XCTAssertEqual(MediaKindResolver.resolve(videos: 0, images: 0, audios: 1), .audio)
        XCTAssertEqual(MediaKindResolver.resolve(videos: 0, images: 2, audios: 0, isDynamic: true), .dynamic)
    }
}
