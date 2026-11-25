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
}
