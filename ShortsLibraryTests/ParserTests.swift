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

    func testSchemeLessShortLinkExtraction() {
        XCTAssertEqual(
            LinkExtractor.firstURL(in: "v.douyin.com/abc12345")?.absoluteString,
            "https://v.douyin.com/abc12345"
        )
    }

    func testParseCacheFailureShortCircuit() {
        let url = URL(string: "https://www.douyin.com/video/testfailure")!
        ParseCache.clear()
        ParseCache.markFailure(for: url, loggedIn: false)
        XCTAssertNil(ParseCache.parsed(for: url, loggedIn: false))
        XCTAssertTrue(ParseCache.hasRecentFailure(for: url, loggedIn: false))
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

    func testVideoStreamURLNotTreatedAsImage() {
        let html = #"""
        <script>window.__INITIAL_STATE__={"note":{"noteDetailMap":{"n1":{"note":{"imageList":[{"infoList":[{"url":"https://sns-video-qc.xhscdn.com/stream/1/10/19/file_19.mp4?sign=abc"}]}]}}}}}}</script>
        """#
        let metadata = HTMLMetadataExtractor.extract(
            html: html,
            finalURL: URL(string: "https://www.xiaohongshu.com/explore/n1")!
        )
        XCTAssertFalse(metadata.imageURLs.contains { $0.pathExtension == "mp4" })
    }

    func testKuaishouCDNHostNotParsedAsResolution() {
        let url = URL(string: "https://v23-3.kwaicdn.com/schedule/2408x874cx0x31xx15z/media_720p_b.mp4?tt=b")!
        let candidate = MediaQualityHeuristic.videoCandidate(for: url)
        XCTAssertNil(candidate.width)
        XCTAssertEqual(candidate.height, 720)
        XCTAssertEqual(candidate.quality, "720p")
    }

    func testDouyinDetailDedupesTemplateVariants() {
        let html = #"""
        <script>{"aweme_detail":{"aweme_id":"7712067669570895026","images":[{"url_list":["https://p3.douyinpic.com/tos-cn-i/x~tplv-dy-aweme-images:q75.webp?biz_tag=aweme_images","https://p11.douyinpic.com/tos-cn-i/x~tplv-dy-water-v2:q75.webp?biz_tag=aweme_images"]}],"music_info":{"cover":{"url_list":["https://p11.douyinpic.com/aweme/100x100/music.jpeg"]}}}}</script>
        """#
        let detail = DouyinParser().extractDetail(from: html)
        XCTAssertEqual(detail.images.count, 1)
        XCTAssertTrue(detail.images.first?.path.contains("aweme-images:q75") == true)
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

    func testDouyinShareTextShortLinkExtraction() {
        let text = "7.15 复制打开抖音，看看【Eviig的图文作品】我真的特别爱你# 洗澡姿势大赏 # # 正向健身引... https://v.douyin.com/fdiiC0byXwg/ mqE:/ 07/08 :6pm S@l.Ch"
        XCTAssertEqual(
            LinkExtractor.firstURL(in: text)?.absoluteString,
            "https://v.douyin.com/fdiiC0byXwg/"
        )
    }

    func testFollowListParsesCamelCaseUsers() async throws {
        let json = #"""
        [{"user":{"secUid":"MS4w_test","nickname":"小明","avatarThumb":{"urlList":["https://example.com/a.jpg"]}}},
         {"sec_uid":"MS4w_other","nickname":"小红","avatar_thumb":{"url_list":["https://example.com/b.jpg"]}}]
        """#
        let array = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [Any] ?? []
        let drafts = await FollowPageCollector.parseUsers(array)
        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(drafts[0].platformUserId, "MS4w_test")
        XCTAssertEqual(drafts[0].displayName, "小明")
        XCTAssertEqual(drafts[0].avatarURLString, "https://example.com/a.jpg")
        XCTAssertEqual(drafts[1].platformUserId, "MS4w_other")
    }

    func testUserProvidedShareSamples() async {
        let samples: [(String, String, String, String)] = [
            ("抖音视频", "0.02 复制打开抖音，看看【Helen lin🌷的作品】妈妈的爱是圆的，没有起点，也没有终点。# 我的阳光... https://v.douyin.com/yOeF20Vs-1g/ 10/06 u@f.ba :5pm pQX:/", "https://v.douyin.com/yOeF20Vs-1g/", "抖音"),
            ("抖音图文4张", "6.64 吃好睡好🫶# 生活碎片分享 # 梁颢峥 # 卓颢嵘 # 吃遍大街小巷的美食  https://v.douyin.com/iBe8eDCIkmQ/ 复制此链接，打开抖音搜索，直接观看视频！ Cho:/ Y@M.jc 12/30 :0pm", "https://v.douyin.com/iBe8eDCIkmQ/", "抖音"),
            ("抖音动态图片1张", "7.15 复制打开抖音，看看【@米粒的图文作品】饿了一个鸡蛋对付一下吧!专家不是说睡前两小时不要吃... https://v.douyin.com/8K_0l9RnGNI/ :9pm a@n.DU 11/24 eOk:/", "https://v.douyin.com/8K_0l9RnGNI/", "抖音"),
            ("抖音动态图片3张", "1.25 库存.# 小朋友的泡泡玛特 # 收到礼物的小孩 # 篮球男孩 # 抖音二创激励计划 # LELE篮球日记  https://v.douyin.com/tC1P_Oxe3M0/ 复制此链接，打开抖音搜索，直接观看视频！ :8pm 02/16 MjP:/ R@X.md", "https://v.douyin.com/tC1P_Oxe3M0/", "抖音"),
            ("小红书视频", "努力做一个时间管理大师 今天复习任务重 硬是把原定的... https://xhslink.cn/o/mOpd7ARHkx 跳转【小红书】看看笔记详情~", "https://xhslink.cn/o/mOpd7ARHkx", "小红书"),
            ("小红书动态图片1张", "紧张的小脚丫😂 https://xhslink.cn/o/5bDuWEEdxv6 去【小红书】逛逛，这篇笔记超有料！", "https://xhslink.cn/o/5bDuWEEdxv6", "小红书"),
            ("小红书图文1张", "小哥哥的晚自习开始了 https://xhslink.cn/o/44ARl4jX1El 先复制这段，再进【小红书】就能浏览笔记。", "https://xhslink.cn/o/44ARl4jX1El", "小红书"),
            ("小红书图文7张", "今天的课堂主角是游泳小将🏊 不同的运动项目，相同的... https://xhslink.cn/o/7FuJL3HGnGk 【小红书】上有超棒的笔记，快来瞧瞧！", "https://xhslink.cn/o/7FuJL3HGnGk", "小红书"),
            ("小红书动态图片11张", "初中生打完羽毛球，书包一背就往家走 昊哥背着书包往... https://xhslink.cn/o/AmjNRhLYhr 先复制这段内容，再进入【小红书】即可阅读笔记。", "https://xhslink.cn/o/AmjNRhLYhr", "小红书"),
            ("快手视频", "https://v.kuaishou.com/K2ELTWfL 上学咯 该作品在快手被播放过2.1万次，点击链接，打开【快手】直接观看！", "https://v.kuaishou.com/K2ELTWfL", "快手"),
            ("快手图文4张", #"https://v.kuaishou.com/JU3JaHG3 小小身影站高处，眼里全是光 "波比又困了 "骗你生儿子 "兄弟装 该作品在快手被播放过1.1万次，点击链接，打开【快手】直接观看！"#, "https://v.kuaishou.com/JU3JaHG3", "快手"),
            ("快手动态图片1张", #"https://v.kuaishou.com/nmQGe74X 记录的意义是让幸福可以翻阅 好好珍惜和孩子相伴的每一天来日并不方长 童年何其短暂，当下的温柔与陪伴，才是人间最好！"两个儿子 "拍照记录 "记录真实生活 "记录幸福时刻 该作品在快手被播放过1.9万次，点击链接，打开【快手】直接观看！"#, "https://v.kuaishou.com/nmQGe74X", "快手")
        ]
        for (name, text, expectedURL, expectedPlatform) in samples {
            XCTAssertEqual(LinkExtractor.firstURL(in: text)?.absoluteString, expectedURL, "\(name) 链接提取")
            let platform = await LinkIngestService.detectPlatform(in: text)
            XCTAssertEqual(platform, expectedPlatform, "\(name) 平台识别")
        }
    }

    func testDouyinNotePageImagesFromJSONLD() {
        let html = #"""
        <html><head><script type="application/ld+json">{"@context":"https://schema.org","@type":"article","headline":"图文","url":"https://www.douyin.com/note/7710910581876000435","image":["https://p3-pc-sign.douyinpic.com/tos-cn-i-0813c001/abc~tplv-dy-aweme-images:q75.webp?sc=image"]}</script></head></html>
        """#
        let metadata = HTMLMetadataExtractor.extract(
            html: html,
            finalURL: URL(string: "https://www.douyin.com/note/7710910581876000435")!
        )
        XCTAssertEqual(metadata.imageURLs.count, 1)
        XCTAssertTrue(metadata.imageURLs.first?.absoluteString.contains("douyinpic.com") == true)
        XCTAssertTrue(metadata.videoURLs.isEmpty)
    }

    func testDouyinDetailScopedToMatchingAwemeID() {
        let html = #"""
        <script>window._ROUTER_DATA = {"aweme_details":[
          {"aweme_id":"1111111111111111111","video":{"play_addr":{"url_list":["https://v3-web.douyinvod.com/other.mp4"]}}},
          {"aweme_id":"7710910581876000435","images":[{"url_list":["https://p3.douyinpic.com/obj/aweme_images/target.jpg"]}]}
        ]}</script>
        """#
        let detail = DouyinParser().extractDetail(from: html, matching: "7710910581876000435")
        XCTAssertEqual(detail.sourceID, "7710910581876000435")
        XCTAssertTrue(detail.videos.isEmpty)
        XCTAssertTrue(detail.images.contains { $0.absoluteString.contains("target.jpg") })
    }

    func testWebPImageNeedsConversionForPhotos() {
        XCTAssertTrue(ImageFileProcessor.convertibleToJPEG(ext: "webp"))
        XCTAssertFalse(ImageFileProcessor.convertibleToJPEG(ext: "jpg"))
        XCTAssertFalse(ImageFileProcessor.convertibleToJPEG(ext: "mp4"))
    }

    func testDouyinTitleIgnoresMusicName() {
        let html = #"""
        <script>window._ROUTER_DATA = {"aweme_detail":{"aweme_id":"7710910581876000435","desc":"作品标题","nickname":"作者A","music":{"title":"背景音乐名","desc":"音乐介绍","owner":{"nickname":"音乐人B"}}}}</script>
        """#
        let metadata = HTMLMetadataExtractor.extract(
            html: html,
            finalURL: URL(string: "https://www.douyin.com/video/7710910581876000435")!
        )
        XCTAssertNil(metadata.title)
        XCTAssertEqual(metadata.author, "作者A")
        let detail = DouyinParser().extractDetail(from: html)
        XCTAssertEqual(detail.description, "作品标题")
        XCTAssertEqual(detail.author, "作者A")
        XCTAssertNil(detail.title)
    }

    func testPublicJSONTitleFallbackStillWorks() {
        let html = #"""<script>{"title":"正常标题"}</script>"""#
        let metadata = HTMLMetadataExtractor.extract(
            html: html,
            finalURL: URL(string: "https://example.com/video/1")!
        )
        XCTAssertEqual(metadata.title, "正常标题")
    }

    func testLiveActivityProgress() {
        let url = URL(string: "https://example.com/video.mp4")!
        let destination = URL(fileURLWithPath: "/tmp/video.mp4")
        var first = DownloadQueueTask(url: url, destination: destination, label: "视频 1")
        var second = DownloadQueueTask(
            url: url,
            destination: destination.appendingPathExtension("2"),
            label: "视频 2"
        )
        first.status = .done
        first.progress = 1
        second.status = .running
        second.progress = 0.5
        XCTAssertEqual(LiveActivityProgress.value(for: [first, second]), 0.75)
        XCTAssertEqual(LiveActivityProgress.value(for: []), 0)
    }
}
