import Foundation

enum LinkExtractor {
    static func firstURL(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = URL(string: trimmed), ["http", "https"].contains(direct.scheme?.lowercased() ?? "") {
            return direct
        }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return detector.matches(in: trimmed, options: [], range: range)
            .compactMap { $0.url }
            .first { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
    }

    static func sourceId(from url: URL) -> String? {
        let components = url.pathComponents.filter { $0 != "/" }
        if let last = components.last, last.count >= 8 {
            return last
        }
        return nil
    }
}
