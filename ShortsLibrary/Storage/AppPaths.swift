import Foundation

enum AppPaths {
    static let root: URL = {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("ShortsLibrary", isDirectory: true)
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }()

    static func itemDirectory(source: String, sourceId: String) -> URL {
        let safeSource = source.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? source
        let safeID = sourceId.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? sourceId
        let url = root
            .appendingPathComponent("items", isDirectory: true)
            .appendingPathComponent("\(safeSource)_\(safeID)", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    static func relativePath(source: String, sourceId: String, filename: String) -> String {
        let safeSource = source.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? source
        let safeID = sourceId.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? sourceId
        return "items/\(safeSource)_\(safeID)/\(filename)"
    }
}
