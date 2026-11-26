import Foundation

enum LinkExtractor {
    static func firstURL(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let detected = firstDetectedURL(in: trimmed) {
            return detected
        }

        guard !trimmed.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }

        let candidates = [trimmed, "https://" + trimmed]
        for candidate in candidates {
            guard let url = URL(string: candidate),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  let host = url.host(), host.contains(".") else { continue }
            return url
        }
        return nil
    }

    private static func firstDetectedURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, options: [], range: range)
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
