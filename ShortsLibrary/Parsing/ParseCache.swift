import Foundation

private struct CachedResult {
    let parsed: ParsedMedia?
    let timestamp: Date

    var age: TimeInterval { Date().timeIntervalSince(timestamp) }
}

enum ParseCache {
    private static let successTTL: TimeInterval = 600
    private static let failureTTL: TimeInterval = 60
    private static var storage: [String: CachedResult] = [:]
    private static let lock = NSLock()

    static func parsed(for url: URL, loggedIn: Bool) -> ParsedMedia? {
        let key = cacheKey(url: url, loggedIn: loggedIn)
        lock.lock()
        defer { lock.unlock() }
        guard let entry = storage[key] else { return nil }
        guard entry.age < successTTL, let parsed = entry.parsed else { return nil }
        return parsed
    }

    static func hasRecentFailure(for url: URL, loggedIn: Bool) -> Bool {
        let key = cacheKey(url: url, loggedIn: loggedIn)
        lock.lock()
        defer { lock.unlock() }
        guard let entry = storage[key] else { return false }
        guard entry.age < failureTTL, entry.parsed == nil else {
            storage[key] = nil
            return false
        }
        return true
    }

    static func store(_ parsed: ParsedMedia, for url: URL, loggedIn: Bool) {
        let key = cacheKey(url: url, loggedIn: loggedIn)
        lock.lock()
        storage[key] = CachedResult(parsed: parsed, timestamp: Date())
        lock.unlock()
    }

    static func markFailure(for url: URL, loggedIn: Bool) {
        let key = cacheKey(url: url, loggedIn: loggedIn)
        lock.lock()
        storage[key] = CachedResult(parsed: nil, timestamp: Date())
        lock.unlock()
    }

    static func clear() {
        lock.lock()
        storage.removeAll()
        lock.unlock()
    }

    static func clear(for url: URL, loggedIn: Bool) {
        let key = cacheKey(url: url, loggedIn: loggedIn)
        lock.lock()
        storage[key] = nil
        lock.unlock()
    }

    private static func cacheKey(url: URL, loggedIn: Bool) -> String {
        "\(url.normalizedCacheKey)|\(loggedIn ? "auth" : "public")"
    }
}
