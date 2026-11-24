import Foundation
import Combine
import WebKit

enum PlatformLogin: String, CaseIterable, Identifiable {
    case douyin
    case kuaishou
    case xiaohongshu
    case bilibili

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .douyin: return "抖音"
        case .kuaishou: return "快手"
        case .xiaohongshu: return "小红书"
        case .bilibili: return "B站"
        }
    }

    var loginURL: URL {
        switch self {
        case .douyin: return URL(string: "https://www.douyin.com/")!
        case .kuaishou: return URL(string: "https://www.kuaishou.com/")!
        case .xiaohongshu: return URL(string: "https://www.xiaohongshu.com/")!
        case .bilibili: return URL(string: "https://passport.bilibili.com/login")!
        }
    }

    var cookieDomain: String {
        switch self {
        case .douyin: return "douyin.com"
        case .kuaishou: return "kuaishou.com"
        case .xiaohongshu: return "xiaohongshu.com"
        case .bilibili: return "bilibili.com"
        }
    }

    var extraHosts: [String] {
        switch self {
        case .douyin: return ["iesdouyin.com"]
        case .kuaishou: return ["chenzhongtech.com", "gifshow.com"]
        case .xiaohongshu: return ["xhslink.com"]
        case .bilibili: return ["b23.tv"]
        }
    }

    var sessionCookieKeywords: [String] {
        switch self {
        case .douyin: return ["sessionid", "sid_tt", "odin_tt"]
        case .kuaishou: return ["userid", "token", "session"]
        case .xiaohongshu: return ["web_session", "session"]
        case .bilibili: return ["sessdata", "bili_jct", "dedeuserid"]
        }
    }

    var icon: String {
        switch self {
        case .douyin: return "music.note"
        case .kuaishou: return "bolt"
        case .xiaohongshu: return "book"
        case .bilibili: return "tv"
        }
    }
}

@MainActor
final class LoginSessionManager: ObservableObject {
    static let shared = LoginSessionManager()

    @Published private(set) var states: [PlatformLogin: Bool] = [:]

    private init() {}

    func refresh() async {
        for platform in PlatformLogin.allCases {
            states[platform] = await isLoggedIn(platform)
        }
    }

    func isLoggedIn(for url: URL) async -> Bool {
        let host = url.host()?.lowercased() ?? ""
        guard let platform = PlatformLogin.allCases.first(where: { item in
            host == item.cookieDomain
                || host.hasSuffix(".\(item.cookieDomain)")
                || item.extraHosts.contains(host)
        }) else { return false }
        return await isLoggedIn(platform)
    }

    func isLoggedIn(_ platform: PlatformLogin) async -> Bool {
        let cookies = await allCookies()
        let now = Date()
        return cookies.contains { cookie in
            let domain = cookie.domain.lowercased()
            let name = cookie.name.lowercased()
            guard domain.hasSuffix(platform.cookieDomain) else { return false }
            if let expires = cookie.expiresDate, expires < now { return false }
            return platform.sessionCookieKeywords.contains { keyword in
                name.contains(keyword.lowercased())
            }
        }
    }

    func logout(_ platform: PlatformLogin) async {
        let cookies = await allCookies()
        for cookie in cookies where cookie.domain.lowercased().hasSuffix(platform.cookieDomain) {
            await deleteCookie(cookie)
        }
        await refresh()
    }

    private func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private func deleteCookie(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            WKWebsiteDataStore.default().httpCookieStore.delete(cookie) {
                continuation.resume()
            }
        }
    }
}
