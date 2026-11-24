import Foundation
import SwiftUI
import Combine

enum QueueTaskStatus: String {
    case pending
    case running
    case done
    case failed
}

struct DownloadQueueTask: Identifiable {
    let id = UUID()
    let url: URL
    let destination: URL
    let label: String
    let onFinish: (@MainActor (URL) async -> Void)?
    let onError: (@MainActor (String) -> Void)?
    var progress: Double = 0
    var status: QueueTaskStatus = .pending
    var error: String?
}

@MainActor
final class DownloadQueue: ObservableObject, @unchecked Sendable {
    static let shared = DownloadQueue()

    @Published private(set) var tasks: [DownloadQueueTask] = []
    @Published private(set) var isRunning = false
    @Published private(set) var waitingForNetwork = false

    private var cancellables: Set<AnyCancellable> = []

    private init() {
        UserDefaults.standard.register(defaults: [
            "shorts.wifiOnly": false,
            "shorts.maxConcurrent": 1,
            "shorts.notifyOnComplete": true
        ])

        NetworkMonitor.shared.$isWiFi
            .dropFirst()
            .sink { [weak self] _ in Task { @MainActor in self?.settingsChanged() } }
            .store(in: &cancellables)
        NetworkMonitor.shared.$isConnected
            .dropFirst()
            .sink { [weak self] _ in Task { @MainActor in self?.settingsChanged() } }
            .store(in: &cancellables)
    }

    var maxConcurrent: Int {
        max(1, min(4, UserDefaults.standard.integer(forKey: "shorts.maxConcurrent")))
    }

    @discardableResult
    func enqueue(
        url: URL,
        destination: URL,
        label: String,
        onFinish: (@MainActor (URL) async -> Void)? = nil,
        onError: (@MainActor (String) -> Void)? = nil
    ) -> UUID {
        let task = DownloadQueueTask(
            url: url,
            destination: destination,
            label: label,
            onFinish: onFinish,
            onError: onError
        )
        tasks.append(task)
        settingsChanged()
        return task.id
    }

    func settingsChanged() {
        Task { await run() }
    }

    func clearCompleted() {
        tasks.removeAll { $0.status == .done || $0.status == .failed }
    }

    private var canStart: Bool {
        let network = NetworkMonitor.shared
        guard network.isConnected else { return false }
        if UserDefaults.standard.bool(forKey: "shorts.wifiOnly"), !network.isWiFi {
            return false
        }
        return true
    }

    private func run() async {
        guard !isRunning else { return }
        guard canStart else {
            waitingForNetwork = true
            return
        }
        waitingForNetwork = false

        let pending = tasks.filter { $0.status == .pending }.map(\.id)
        guard !pending.isEmpty else { return }

        isRunning = true
        defer { isRunning = false }

        let limit = maxConcurrent
        await withTaskGroup(of: Void.self) { group in
            var iterator = pending.makeIterator()
            var active = 0

            func fill() {
                while active < limit, let id = iterator.next() {
                    active += 1
                    group.addTask { await self.process(id: id) }
                }
            }

            fill()
            for await _ in group {
                active -= 1
                if canStart {
                    fill()
                } else {
                    waitingForNetwork = true
                }
            }
        }

        waitingForNetwork = tasks.contains { $0.status == .pending }
    }

    private func process(id: UUID) async {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        updateStatus(id: id, status: .running)

        do {
            try await MediaDownloader.download(url: task.url, to: task.destination) { [weak self] value in
                Task { @MainActor in self?.updateProgress(id: id, value: value) }
            }
            updateStatus(id: id, status: .done)
            await task.onFinish?(task.destination)
            if UserDefaults.standard.bool(forKey: "shorts.notifyOnComplete") {
                NotificationService.shared.notifyDownloadFinished(label: task.label)
            }
        } catch {
            guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
            tasks[index].status = .failed
            tasks[index].error = error.localizedDescription
            task.onError?(error.localizedDescription)
        }
    }

    private func updateStatus(id: UUID, status: QueueTaskStatus) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].status = status
        if status == .done { tasks[index].progress = 1 }
    }

    private func updateProgress(id: UUID, value: Double) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].progress = value
    }
}
