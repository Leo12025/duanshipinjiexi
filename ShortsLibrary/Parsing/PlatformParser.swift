import Foundation

protocol PlatformParser {
    var source: MediaSource { get }
    var supportedHosts: [String] { get }
    func canHandle(url: URL) -> Bool
    func parse(url: URL) async throws -> ParsedMedia
}

extension PlatformParser {
    func canHandle(url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        return supportedHosts.contains { base in
            host == base || host.hasSuffix(".\(base)")
        }
    }
}
