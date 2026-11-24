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

    var profileURL: URL {
        switch self {
        case .douyin: return URL(string: "https://www.douyin.com/user/self")!
        case .kuaishou: return URL(string: "https://www.kuaishou.com/profile")!
        case .xiaohongshu: return URL(string: "https://www.xiaohongshu.com/user/profile")!
        case .bilibili: return URL(string: "https://account.bilibili.com/account/home")!
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
            guard await isLoggedIn(platform) else {
                states[platform] = false
                continue
            }
            states[platform] = await verify(platform)
        }
    }

    func verify(_ platform: PlatformLogin) async -> Bool {
        guard await isLoggedIn(platform) else { return false }
        var request = URLRequest(url: platform.profileURL)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        if let cookie = await Self.cookieHeader(for: platform.profileURL) {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else { return false }
            let final = http.url?.absoluteString.lowercased() ?? ""
            if final.contains("login") || final.contains("passport") { return false }
            let body = String(data: data.prefix(64 * 1024), encoding: .utf8)?.lowercased() ?? ""
            if body.contains("请先登录") || body.contains("登录后查看") { return false }
            return true
        } catch {
            return false
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

    static func cookieValue(name: String, domain: String) async -> String? {
        let cookies = await allCookies()
        return cookies.first { cookie in
            cookie.name.lowercased() == name.lowercased()
                && cookie.domain.lowercased().hasSuffix(domain.lowercased())
        }?.value
    }

    static func cookieHeader(for url: URL) async -> String? {
        let host = url.host()?.lowercased() ?? ""
        guard !host.isEmpty else { return nil }
        let cookies = await allCookies()
        let now = Date()
        let matched = cookies.filter { cookie in
            if let expires = cookie.expiresDate, expires < now { return false }
            let domain = cookie.domain
                .lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard !domain.isEmpty else { return false }
            return host == domain || host.hasSuffix(".\(domain)")
        }
        guard !matched.isEmpty else { return nil }
        return matched.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    func isLoggedIn(_ platform: PlatformLogin) async -> Bool {
        let cookies = await Self.allCookies()
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
        let cookies = await Self.allCookies()
        for cookie in cookies where cookie.domain.lowercased().hasSuffix(platform.cookieDomain) {
            await deleteCookie(cookie)
        }
        await refresh()
    }

    private static func allCookies() async -> [HTTPCookie] {
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

extension Notification.Name {
    static let openPlatformLogin = Notification.Name("shorts.openPlatformLogin")
}
