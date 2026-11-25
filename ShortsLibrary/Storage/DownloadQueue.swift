import Foundation
import SwiftUI
import Combine

enum QueueTaskStatus: String {
    case pending
    case running
    case paused
    case done
    case failed
}

struct DownloadQueueTask: Identifiable {
    let id = UUID()
    let downloadID = UUID()
    let url: URL
    let destination: URL
    let label: String
    let onFinish: (@MainActor (URL) async -> Void)?
    let onError: (@MainActor (String) -> Void)?
    var progress: Double = 0
    var status: QueueTaskStatus = .pending
    var generation: Int = 0
    var error: String?
}

@MainActor
final class DownloadQueue: ObservableObject, @unchecked Sendable {
    static let shared = DownloadQueue()

    @Published private(set) var tasks: [DownloadQueueTask] = []
    @Published private(set) var isRunning = false
    @Published private(set) var waitingForNetwork = false

    private var cancellables: Set<AnyCancellable> = []
    private var cancelledIDs: Set<UUID> = []

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
        let key = Self.taskKey(url: url, destination: destination)
        if let existing = tasks.first(where: {
            Self.taskKey(url: $0.url, destination: $0.destination) == key
                && ($0.status == .pending || $0.status == .running)
        }) {
            return existing.id
        }

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

    func cancel(id: UUID) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        if task.status == .running {
            cancelledIDs.insert(id)
            MediaDownloader.cancel(taskID: task.downloadID)
        }
        if let index = tasks.firstIndex(where: { $0.id == id }) {
            tasks[index].generation += 1
            tasks[index].status = .failed
            tasks[index].error = "已取消"
        }
        task.onError?("已取消")
    }

    func pause(id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        guard tasks[index].status == .pending || tasks[index].status == .running else { return }
        if tasks[index].status == .running {
            cancelledIDs.insert(id)
            MediaDownloader.cancel(taskID: tasks[index].downloadID)
        }
        tasks[index].generation += 1
        tasks[index].status = .paused
    }

    func resume(id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }),
              tasks[index].status == .paused else { return }
        tasks[index].generation += 1
        tasks[index].status = .pending
        tasks[index].error = nil
        settingsChanged()
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
        guard let task = tasks.first(where: {
            $0.id == id && $0.status == .pending && !cancelledIDs.contains(id)
        }) else { return }
        let generation = task.generation
        updateStatus(id: id, status: .running)

        do {
            try await MediaDownloader.download(
                url: task.url,
                to: task.destination,
                taskID: task.downloadID
            ) { [weak self] value in
                Task { @MainActor in self?.updateProgress(id: id, value: value) }
            }
            guard let current = tasks.first(where: { $0.id == id }),
                  current.generation == generation,
                  current.status == .running,
                  !cancelledIDs.contains(id) else {
                try? FileManager.default.removeItem(at: task.destination)
                try? FileManager.default.removeItem(at: task.destination.appendingPathExtension("part"))
                return
            }
            updateStatus(id: id, status: .done)
            await task.onFinish?(task.destination)
            if UserDefaults.standard.bool(forKey: "shorts.notifyOnComplete") {
                NotificationService.shared.notifyDownloadFinished(label: task.label)
            }
        } catch {
            if cancelledIDs.remove(id) != nil { return }
            guard let index = tasks.firstIndex(where: { $0.id == id }),
                  tasks[index].generation == generation else { return }
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

    private static func taskKey(url: URL, destination: URL) -> String {
        "\(url.normalizedCacheKey)|\(destination.absoluteString)"
    }

    private func updateProgress(id: UUID, value: Double) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].progress = value
    }
}
