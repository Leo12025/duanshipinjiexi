import XCTest
@testable import ShortsLibrary

final class ParserTests: XCTestCase {
    func testLinkExtraction() async {
        let text = "分享文案 https://www.douyin.com/video/7123456789012345678 复制打开"
        XCTAssertEqual(LinkExtractor.firstURL(in: text)?.host(), "www.douyin.com")
        let platform = await LinkIngestService.detectPlatform(in: text)
        XCTAssertEqual(platform, "抖音")
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
