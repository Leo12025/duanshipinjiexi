import Foundation
import SwiftData

enum FollowListService {
    static func collect(
        platform: MediaSource,
        in context: ModelContext
    ) async throws -> String {
        guard await LoginSessionManager.shared.isLoggedIn(platformLogin(for: platform)) else {
            throw AppError.loginRequired(platform.displayName)
        }

        let drafts: [FollowedAccountDraft]
        let source: FollowSource
        if platform == .bilibili {
            guard let mid = await LoginSessionManager.cookieValue(name: "DedeUserID", domain: "bilibili.com"),
                  !mid.isEmpty else {
                throw AppError.loginRequired("B站")
            }
            drafts = try await collectBilibili(mid: mid)
            source = .api
        } else {
            drafts = try await FollowPageCollector.shared.collect(platform: platform)
            source = .webview
        }

        guard !drafts.isEmpty else {
            throw AppError.parsingFailed("未从页面中读取到关注账号，请确认已登录并打开关注列表")
        }
        let count = await FollowListRepository.upsert(drafts: drafts, platform: platform, source: source, in: context)
        return "已同步 \(drafts.count) 个关注，新增 \(count) 个"
    }

    private static func platformLogin(for source: MediaSource) -> PlatformLogin {
        switch source {
        case .douyin: return .douyin
        case .kuaishou: return .kuaishou
        case .xiaohongshu: return .xiaohongshu
        case .bilibili: return .bilibili
        }
    }

    private static func collectBilibili(mid: String) async throws -> [FollowedAccountDraft] {
        var all: [FollowedAccountDraft] = []
        for page in 1...20 {
            let url = URL(string: "https://api.bilibili.com/x/relation/followings?vmid=\(mid)&pn=\(page)&ps=30&order=desc")!
            let data = try await authenticatedData(from: url)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = json["list"] as? [String: Any],
                  let items = list["following"] as? [[String: Any]] else {
                break
            }
            for item in items {
                guard let userId = item["mid"] else { continue }
                let id = "\(userId)"
                let name = item["uname"] as? String ?? "B站用户 \(id)"
                let avatar = item["face"] as? String
                let group = (item["tag"] as? [String: Any])?["name"] as? String
                all.append(FollowedAccountDraft(
                    platformUserId: id,
                    secUserId: nil,
                    displayName: name,
                    remark: nil,
                    groupName: group,
                    avatarURLString: avatar
                ))
            }
            if items.count < 30 { break }
        }
        return all
    }

    private static func authenticatedData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
        if let cookie = await LoginSessionManager.cookieHeader(for: url) {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AppError.badStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }
}
