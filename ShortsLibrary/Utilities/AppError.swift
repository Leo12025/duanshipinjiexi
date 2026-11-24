import Foundation

enum AppError: LocalizedError {
    case invalidLink
    case unsupportedPlatform(String)
    case parsingFailed(String)
    case badStatus(Int)
    case noMedia
    case fileSystem(String)

    var errorDescription: String? {
        switch self {
        case .invalidLink:
            return "没有在文本中找到有效的链接"
        case .unsupportedPlatform(let host):
            return "暂不支持该平台：\(host)"
        case .parsingFailed(let detail):
            return "解析失败：\(detail)"
        case .badStatus(let code):
            return "网络请求失败（HTTP \(code)）"
        case .noMedia:
            return "页面中没有找到可保存的图片或视频"
        case .fileSystem(let detail):
            return "文件操作失败：\(detail)"
        }
    }
}
