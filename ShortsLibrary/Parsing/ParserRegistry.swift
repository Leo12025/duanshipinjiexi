import Foundation

enum ParserRegistry {
    static let all: [any PlatformParser] = [
        DouyinParser(),
        KuaishouParser(),
        XiaohongshuParser(),
        BilibiliParser()
    ]

    static func parser(for url: URL) -> (any PlatformParser)? {
        all.first { $0.canHandle(url: url) }
    }
}
