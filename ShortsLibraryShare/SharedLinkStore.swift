import Foundation

enum SharedLinkStore {
    private static let pendingTextKey = "shorts.pendingShareText"
    private static let pendingTimeKey = "shorts.pendingShareTime"

    private static var suiteName: String {
        let identifier = Bundle.main.bundleIdentifier ?? "com.leo12025.shortslibrary"
        let parent = identifier.hasSuffix(".share")
            ? String(identifier.dropLast(".share".count))
            : identifier
        return "group.\(parent).shared"
    }

    static func enqueue(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.set(trimmed, forKey: pendingTextKey)
        defaults.set(Date().timeIntervalSince1970, forKey: pendingTimeKey)
    }

    static func consume() -> String? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let text = defaults.string(forKey: pendingTextKey),
              !text.isEmpty else { return nil }
        defaults.removeObject(forKey: pendingTextKey)
        defaults.removeObject(forKey: pendingTimeKey)
        return text
    }
}
