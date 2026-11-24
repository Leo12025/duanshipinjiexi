import Foundation

struct DownloadJob: Identifiable {
    let id = UUID()
    let url: URL
    let destination: URL
    var progress: Double = 0
    var status: Status = .pending

    enum Status: String {
        case pending
        case running
        case failed
        case done
    }
}
