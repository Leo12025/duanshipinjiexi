import Foundation

enum AppError: LocalizedError {
    case invalidLink
    case unsupportedPlatform(String)
    case parsingFailed(String)
    case badStatus(Int)
    case noMedia
    case fileSystem(String)
    case loginRequired(String)
    case rateLimited
    case platformChanged(String)
    case verificationRequired(String)
    case aiNotConfigured
    case aiUploadDisabled
    case aiNoMedia
    case aiInvalidResponse
    case aiHTTP(Int, String)

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
        case .loginRequired(let platform):
            return "\(platform)需要登录后才能查看该资源，请在「我的」→「平台登录」中登录后重试"
        case .rateLimited:
            return "平台请求过于频繁，请稍后再试"
        case .platformChanged(let platform):
            return "\(platform)页面结构可能已变化，暂未能提取媒体，请稍后重试"
        case .verificationRequired(let platform):
            return "\(platform)需要完成页面验证，请在 App 内打开并完成验证后重试"
        case .aiNotConfigured:
            return "AI 服务未配置完成，请在「我的」→「AI 解析设置」中填写服务商、模型和 API Key"
        case .aiUploadDisabled:
            return "尚未允许上传画面与文案，请先在「AI 解析设置」中开启"
        case .aiNoMedia:
            return "没有可用于 AI 分析的视频关键帧或图片"
        case .aiInvalidResponse:
            return "AI 服务返回了无法解析的结果"
        case .aiHTTP(let code, let detail):
            return "AI 服务请求失败（HTTP \(code)）：\(detail)"
        }
    }
}
