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
        XCTAssertTrue(detail.videos.contains {
            $0.url.absoluteString.contains("douyinvod.com/video.mp4") && $0.context.contains("play_addr")
        })
        XCTAssertTrue(detail.images.contains { $0.absoluteString.contains("douyinpic.com") })
    }

    func testDouyinRelativePlayURI() {
        let html = #"""
        <script>window._ROUTER_DATA = {"aweme_detail":{"video":{"play_addr":{"uri":"/aweme/v1/play/?video_id=abc"}}}}</script>
        """#
        let detail = DouyinParser().extractDetail(from: html)
        XCTAssertTrue(detail.videos.contains {
            $0.url.host() == "aweme.snssdk.com" && $0.url.path.contains("/play/")
        })
    }

    func testNoWatermarkCandidatePreferred() {
        let cleanURL = URL(string: "https://v3-web.douyinvod.com/video/clean.mp4")!
        let watermarkedURL = URL(string: "https://v3-web.douyinvod.com/video/download.mp4")!
        let clean = MediaQualityHeuristic.videoCandidate(
            for: cleanURL,
            sourceField: "play_addr",
            prefersNoWatermark: true
        )
        let watermarked = MediaQualityHeuristic.videoCandidate(
            for: watermarkedURL,
            sourceField: "download_addr",
            isWatermarked: true
        )
        let parsed = ParsedMedia(
            source: .douyin,
            sourceId: "7711741462283352058",
            kind: .video,
            title: "测试",
            author: nil,
            caption: nil,
            pageURL: URL(string: "https://www.douyin.com/video/7711741462283352058")!,
            coverURL: nil,
            images: [],
            videos: [watermarked, clean],
            audioURL: nil,
            needsAudioMux: false
        )

        XCTAssertEqual(parsed.bestVideo?.url, cleanURL)
        XCTAssertEqual(parsed.fallbackVideos.first?.url, watermarkedURL)
    }

    func testDouyinAudioExtraction() {
        let html = #"""
        <script>window._ROUTER_DATA = {"aweme_detail":{"video":{"play_addr":{"url_list":["https://v3-web.douyinvod.com/video.mp4"]}},"music_info":{"audio_url":{"url_list":["https://sf1-cdn-tos.douyinstatic.com/obj/audio.mp3"]}}}}</script>
        """#
        let detail = DouyinParser().extractDetail(from: html)
        XCTAssertEqual(detail.audioURL?.pathExtension, "mp3")
        XCTAssertTrue(detail.videos.contains {
            $0.url.absoluteString.contains("douyinvod.com/video.mp4")
        })
    }

    func testDouyinBuildPlayURLFromURI() {
        let uri = "v0200fg10000dc2ojrvog65j90it6nhg"
        let html = #"""
        <script>{"aweme_detail":{"video":{"play_addr":{"uri":"v0200fg10000dc2ojrvog65j90it6nhg","url_list":[]}}}}</script>
        """#
        let detail = DouyinParser().extractDetail(from: html)
        XCTAssertEqual(detail.playURI, uri)
        XCTAssertEqual(
            DouyinParser.buildPlayURL(from: uri)?.absoluteString,
            "https://aweme.snssdk.com/aweme/v1/play/?video_id=v0200fg10000dc2ojrvog65j90it6nhg&ratio=0p&line=1"
        )
        XCTAssertNil(DouyinParser.buildPlayURL(from: "7700000000000000000"))
    }

    func testDouyinPlaywmVariant() {
        let html = #"""
        <script>window._ROUTER_DATA = {"aweme_detail":{"download_addr":{"url_list":["https://aweme.snssdk.com/aweme/v1/playwm/?video_id=abc"]}}}</script>
        """#
        let detail = DouyinParser().extractDetail(from: html)
        XCTAssertTrue(detail.videos.contains {
            $0.url.path.contains("/play/")
                && $0.context.contains("play_addr")
                && $0.isConvertedNoWatermark
        })
        XCTAssertTrue(detail.videos.contains {
            $0.url.path.contains("/playwm/") && $0.context.contains("download_addr")
        })
    }

    func testDouyinBitrateSourcesExtraction() {
        let html = #"""
        <script>{"aweme_detail":{"video":{"bit_rate":[{"bitrate":4000000,"gear_name":"1080p","play_addr":{"url_list":["https://v3-web.douyinvod.com/video/1080.mp4"]}},{"bitrate":1000000,"gear_name":"720p","play_addr":{"url_list":["https://v3-web.douyinvod.com/video/720.mp4"]}}]}}}</script>
        """#
        let detail = DouyinParser().extractDetail(from: html)
        let bitrateSources = detail.videos.filter { $0.context.contains("bit_rate") }
        XCTAssertEqual(bitrateSources.count, 2)
        XCTAssertTrue(bitrateSources.contains { $0.context.contains("bitrate=4000000") })
        XCTAssertTrue(bitrateSources.contains {
            $0.url.absoluteString.contains("1080.mp4") && $0.context.contains("gear_name=1080p")
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

    func testShareTextAndLinkPayload() {
        let item = LibraryItem(
            source: .douyin,
            sourceId: "7711741462283352058",
            kind: .video,
            title: "标题",
            author: nil,
            caption: "  原始文案  ",
            pageURL: URL(string: "https://www.douyin.com/video/7711741462283352058")!
        )
        let expected = "原始文案\nhttps://www.douyin.com/video/7711741462283352058"
        XCTAssertEqual(SharePayload.textAndLink(for: item), expected)

        let items = SharePayload.textAndLinkItems(for: item)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first as? String, expected)

        item.caption = ""
        XCTAssertEqual(
            SharePayload.textAndLink(for: item),
            "标题\nhttps://www.douyin.com/video/7711741462283352058"
        )
    }

    func testWechatChannelsRecognitionAndSourceID() {
        let shortURL = URL(string: "https://weixin.qq.com/sph/AbC_123456")!
        XCTAssertEqual(ParserRegistry.parser(for: shortURL)?.source, .wechatChannels)
        XCTAssertEqual(
            WechatChannelsParser.extractSourceID(from: shortURL, html: ""),
            "AbC_123456"
        )

        let previewURL = URL(string: "https://channels.weixin.qq.com/finder-preview/xyz987654")!
        XCTAssertEqual(
            WechatChannelsParser.extractSourceID(from: previewURL, html: ""),
            "xyz987654"
        )
    }

    func testWechatChannelsMetadataExtraction() {
        let html = #"""
        <html>
          <meta property="og:title" content="视频号标题">
          <meta property="og:video" content="https://finder.video.qq.com/abc/video.mp4">
          <meta property="og:image" content="https://finder.video.qq.com/abc/cover.jpg">
        </html>
        """#
        let metadata = HTMLMetadataExtractor.extract(
            html: html,
            finalURL: URL(string: "https://weixin.qq.com/sph/AbC_123456")!
        )
        XCTAssertEqual(metadata.title, "视频号标题")
        XCTAssertTrue(metadata.videoURLs.contains {
            $0.host() == "finder.video.qq.com" && $0.pathExtension == "mp4"
        })
        XCTAssertTrue(metadata.imageURLs.contains {
            $0.host() == "finder.video.qq.com" && $0.pathExtension == "jpg"
        })
    }

    func testWechatChannelsFeedInfoExtraction() {
        let html = #"""
        <script>{"data":{"authorInfo":{"nickname":"江西软件职业技术大学"},"feedInfo":{"description":"慌啥子嘛，慢慢来","coverUrl":"https://finder.video.qq.com/251/20304/stodownload?encfilekey=abc&scene=2&picformat=200"}}}</script>
        """#
        let info = WechatChannelsParser.extractFeedInfo(from: html)
        XCTAssertEqual(info.author, "江西软件职业技术大学")
        XCTAssertEqual(info.description, "慌啥子嘛，慢慢来")
        XCTAssertEqual(info.coverURL?.host(), "finder.video.qq.com")
        XCTAssertTrue(info.videoURLs.isEmpty)
    }

    func testXiaohongshuImageListExtraction() {
        let html = #"""
        <script>{"imageList":[
          {"fileId":"fileA","infoList":[{"imageScene":"H5_DTL","url":"http://sns-webpic-qc.xhscdn.com/20260101/hashA/fileA!h5_1080jpg"}]},
          {"fileId":"fileB","infoList":[{"imageScene":"H5_DTL","url":"http://sns-webpic-qc.xhscdn.com/20260101/hashB/fileB!h5_1080jpg"}]}
        ]}</script>
        """#
        let page = XiaohongshuParser().extractPageData(from: html)
        XCTAssertEqual(page.images.count, 2)
        XCTAssertEqual(page.images.map(\.absoluteString), [
            "https://ci.xiaohongshu.com/fileA",
            "https://ci.xiaohongshu.com/fileB"
        ])
    }

    func testXiaohongshuNestedImageListExtraction() {
        let html = #"""
        <script>{"imageList":[{"traceId":"","infoList":[{"imageScene":"H5_DTL","url":"http:\u002F\u002Fsns-webpic-qc.xhscdn.com\u002F20260101\u002FhashA\u002FfileA!h5_1080jpg"},{"imageScene":"H5_PRV","url":"http:\u002F\u002Fsns-webpic-qc.xhscdn.com\u002F20260101\u002FhashB\u002FfileB!style_x"}]}]}</script>
        """#
        let page = XiaohongshuParser().extractPageData(from: html)
        XCTAssertEqual(page.images.map(\.absoluteString), ["https://ci.xiaohongshu.com/fileA"])
    }

    func testXiaohongshuPrefersDetailImageScene() {
        let html = #"""
        <script>{"imageList":[{"infoList":[{"imageScene":"H5_DTL","url":"http://sns-webpic-qc.xhscdn.com/20260101/hashA/detail!h5_1080jpg"},{"imageScene":"H5_PRV","url":"http://sns-webpic-qc.xhscdn.com/20260101/hashB/preview!style_x"}]}]}</script>
        """#
        let page = XiaohongshuParser().extractPageData(from: html)
        XCTAssertEqual(page.images.map(\.absoluteString), ["https://ci.xiaohongshu.com/detail"])
    }

    func testXiaohongshuLivePhotoVideoExtraction() {
        let html = #"""
        <script>{"imageList":[
          {"fileId":"one","livePhoto":true,"infoList":[{"imageScene":"H5_DTL","url":"http://sns-webpic-qc.xhscdn.com/20260101/hashA/one!h5_1080jpg"}],"stream":{"h264":[{"masterUrl":"http://sns-video-v6.xhscdn.com/stream/one.mp4"}]}},
          {"fileId":"two","livePhoto":true,"infoList":[{"imageScene":"H5_DTL","url":"http://sns-webpic-qc.xhscdn.com/20260101/hashB/two!h5_1080jpg"}],"stream":{"h264":[{"masterUrl":"http://sns-video-v6.xhscdn.com/stream/two.mp4"}]}}
        ]}</script>
        """#
        let page = XiaohongshuParser().extractPageData(from: html)
        XCTAssertEqual(page.images.map(\.absoluteString), [
            "https://ci.xiaohongshu.com/one",
            "https://ci.xiaohongshu.com/two"
        ])
        XCTAssertEqual(page.livePhotoVideos.count, 2)
        XCTAssertTrue(page.livePhotoVideos[0]?.absoluteString.contains("one.mp4") == true)
    }

    func testXiaohongshuDOMImagesAreIgnored() {
        let html = #"""
        <html><body>
        <img class="avatar" src="http://sns-avatar-qc.xhscdn.com/avatar/1.jpg">
        <img src="http://sns-webpic-qc.xhscdn.com/20260101/hashA/fileA!h5_1080jpg">
        </body></html>
        """#
        let page = XiaohongshuParser().extractPageData(from: html)
        XCTAssertEqual(page.images.count, 1)
        XCTAssertEqual(page.images.first?.absoluteString, "https://ci.xiaohongshu.com/fileA")
    }

    func testKindResolution() {
        XCTAssertEqual(MediaKindResolver.resolve(videos: 1, images: 0, audios: 0), .video)
        XCTAssertEqual(MediaKindResolver.resolve(videos: 0, images: 1, audios: 0), .image)
        XCTAssertEqual(MediaKindResolver.resolve(videos: 0, images: 3, audios: 0), .imageText)
        XCTAssertEqual(MediaKindResolver.resolve(videos: 0, images: 0, audios: 1), .audio)
        XCTAssertEqual(MediaKindResolver.resolve(videos: 0, images: 2, audios: 0, isDynamic: true), .dynamic)
    }
}
