import Foundation
import UIKit

struct DuplicatePair: Identifiable {
    let id = UUID()
    let first: FollowedAccount
    let second: FollowedAccount
    let score: Int
    let reason: String
}

enum FollowSimilarity {
    static func normalizedName(_ name: String) -> String {
        let lowered = name.lowercased()
        var result = ""
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current.append(min(current[j - 1] + 1, previous[j] + 1, previous[j - 1] + cost))
            }
            previous = current
        }
        return previous[b.count]
    }

    static func similarity(a: FollowedAccount, b: FollowedAccount) -> DuplicatePair? {
        if a.platform == b.platform {
            if a.platformUserId == b.platformUserId { return pair(a, b, 100, "同平台相同 ID") }
            if let sec = a.secUserId, sec == b.secUserId { return pair(a, b, 100, "同平台相同 secID") }
        }

        let nameA = normalizedName(a.displayName)
        let nameB = normalizedName(b.displayName)
        guard !nameA.isEmpty, !nameB.isEmpty else { return nil }
        let maxLen = max(nameA.count, nameB.count)
        let distance = levenshtein(nameA, nameB)
        let nameScore = max(0, 100 - distance * 100 / maxLen)

        var score = nameScore * 70 / 100
        var reasons: [String] = []
        if nameScore >= 85 { reasons.append("昵称高度相似") }

        if let hashA = a.avatarPHash, let hashB = b.avatarPHash {
            let hamming = zip(hashA, hashB).filter { $0 != $1 }.count
            let avatarScore = max(0, 100 - hamming * 100 / hashA.count)
            score += avatarScore * 20 / 100
            if avatarScore >= 85 { reasons.append("头像高度相似") }
        }

        if let remarkA = a.remark, let remarkB = b.remark, !remarkA.isEmpty, remarkA == remarkB {
            score += 10
            reasons.append("备注相同")
        }

        guard score >= 70, !reasons.isEmpty else { return nil }
        return pair(a, b, score, reasons.joined(separator: " · "))
    }

    static func detect(among accounts: [FollowedAccount]) -> [DuplicatePair] {
        var results: [DuplicatePair] = []
        for i in 0..<accounts.count {
            for j in (i + 1)..<accounts.count {
                if let pair = similarity(a: accounts[i], b: accounts[j]) {
                    results.append(pair)
                }
            }
        }
        return results.sorted { $0.score > $1.score }
    }

    static func avatarHash(from url: URL) async -> String? {
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data),
              let cg = image.cgImage else { return nil }
        let size = CGSize(width: 8, height: 8)
        UIGraphicsBeginImageContext(size)
        defer { UIGraphicsEndImageContext() }
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        context.draw(cg, in: CGRect(origin: .zero, size: size))
        guard let resized = UIGraphicsGetImageFromCurrentImageContext()?.cgImage,
              let raw = resized.dataProvider?.data,
              let pointer = CFDataGetBytePtr(raw) else { return nil }

        var grays: [UInt8] = []
        for index in 0..<(8 * 8) {
            let offset = index * 4
            grays.append((pointer[offset] * 30 + pointer[offset + 1] * 59 + pointer[offset + 2] * 11) / 100)
        }
        let average = grays.reduce(0) { $0 + Int($1) } / grays.count
        return String(grays.map { $0 > UInt8(average) ? "1" : "0" })
    }

    private static func pair(
        _ a: FollowedAccount,
        _ b: FollowedAccount,
        _ score: Int,
        _ reason: String
    ) -> DuplicatePair {
        DuplicatePair(first: a, second: b, score: score, reason: reason)
    }
}
