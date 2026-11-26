import ActivityKit
import Foundation

struct ShortsActivityAttributes: ActivityAttributes, Hashable {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            case parsing
            case downloading
            case succeeded
            case failed
        }

        var phase: Phase
        var title: String
        var detail: String
        var progress: Double
        var completed: Int
        var total: Int
    }

    var sessionID: String
}
