import Foundation
import Network
import Combine

@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isConnected = false
    @Published private(set) var isWiFi = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.leo12025.shortslibrary.network")

    private init() {
        let path = monitor.currentPath
        isConnected = path.status == .satisfied
        isWiFi = path.usesInterfaceType(.wifi)

        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.isWiFi = path.usesInterfaceType(.wifi)
            }
        }
        monitor.start(queue: queue)
    }
}
