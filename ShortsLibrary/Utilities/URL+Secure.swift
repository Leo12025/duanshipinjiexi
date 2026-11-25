import Foundation

extension URL {
    var secureMediaURL: URL {
        guard scheme?.lowercased() == "http",
              var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }
        components.scheme = "https"
        return components.url ?? self
    }

    var protocolCandidates: [URL] {
        let secure = secureMediaURL
        return secure == self ? [self] : [secure, self]
    }

    var mediaDedupeKey: String {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return absoluteString
        }
        components.scheme = nil
        components.host = components.host?.lowercased()
        components.fragment = nil
        components.queryItems = components.queryItems?
            .filter { !$0.name.lowercased().hasPrefix("utm_") }
            .sorted { $0.name < $1.name }
        return components.url?.absoluteString ?? absoluteString
    }

    static func dedupeMedia(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        return urls.filter { seen.insert($0.mediaDedupeKey).inserted }
    }

    var normalizedCacheKey: String {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return absoluteString
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        components.queryItems = components.queryItems?
            .filter { item in
                let name = item.name.lowercased()
                return !name.hasPrefix("utm_") && !["spm", "from", "share_id", "timestamp"].contains(name)
            }
            .sorted { $0.name < $1.name }
        return components.url?.absoluteString ?? absoluteString
    }
}
