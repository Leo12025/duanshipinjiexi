import ActivityKit
import Foundation

enum LiveActivityProgress {
    static func value(for tasks: [DownloadQueueTask]) -> Double {
        let done = tasks.filter { $0.status == .done }.count
        let running = tasks.filter { $0.status == .running }
        let runningProgress = running.isEmpty
            ? 0
            : running.reduce(0) { $0 + $1.progress } / Double(running.count)
        guard !tasks.isEmpty else { return 0 }
        return min(1, (Double(done) + runningProgress) / Double(tasks.count))
    }
}

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private typealias State = ShortsActivityAttributes.ContentState

    private var activity: Activity<ShortsActivityAttributes>?
    private var activeParses = 0
    private var hasActiveDownloads = false
    private var lastTitle = "短视频资料库"

    private init() {}

    func startParsing(host: String?) async {
        activeParses += 1
        hasActiveDownloads = true
        let state = State(
            phase: .parsing,
            title: "正在解析",
            detail: host ?? "短视频资料库",
            progress: 0,
            completed: 0,
            total: 0
        )
        await ensureActivity(state: state)
    }

    func finishParsing(success: Bool, title: String?, message: String?) async {
        activeParses = max(0, activeParses - 1)
        if !success {
            await end(
                phase: .failed,
                title: "解析失败",
                detail: message ?? "请稍后重试",
                progress: 0,
                completed: 0,
                total: 0
            )
            return
        }
        if let title { lastTitle = title }
        guard !hasActiveDownloads else { return }
        await end(
            phase: .succeeded,
            title: "解析完成",
            detail: lastTitle,
            progress: 1,
            completed: 1,
            total: 1
        )
    }

    func updateDownloads(_ tasks: [DownloadQueueTask]) async {
        let active = tasks.filter { $0.status == .pending || $0.status == .running }
        hasActiveDownloads = !active.isEmpty

        let done = tasks.filter { $0.status == .done }.count
        let failed = tasks.filter { $0.status == .failed }.count
        let total = tasks.count
        let progress = LiveActivityProgress.value(for: tasks)

        guard !active.isEmpty || activeParses > 0 else {
            if failed > 0 {
                await end(
                    phase: .failed,
                    title: "下载失败",
                    detail: "\(failed) 个任务未完成",
                    progress: progress,
                    completed: done,
                    total: total
                )
            } else if !tasks.isEmpty {
                await end(
                    phase: .succeeded,
                    title: "下载完成",
                    detail: lastTitle,
                    progress: 1,
                    completed: total,
                    total: total
                )
            }
            return
        }

        let detail: String
        if let current = active.first(where: { $0.status == .running }) ?? active.first {
            detail = "\(current.label) · \(done)/\(total)"
        } else {
            detail = "\(done)/\(total)"
        }
        let state = State(
            phase: .downloading,
            title: "正在下载",
            detail: detail,
            progress: progress,
            completed: done,
            total: total
        )
        await ensureActivity(state: state)
    }

    private func ensureActivity(state: State) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = ActivityContent(state: state, staleDate: nil)
        if let activity {
            await activity.update(content)
            return
        }
        let attributes = ShortsActivityAttributes(sessionID: UUID().uuidString)
        activity = try? Activity.request(
            attributes: attributes,
            content: content,
            pushType: nil
        )
    }

    private func end(
        phase: State.Phase,
        title: String,
        detail: String,
        progress: Double,
        completed: Int,
        total: Int
    ) async {
        guard let activity else { return }
        let state = State(
            phase: phase,
            title: title,
            detail: detail,
            progress: progress,
            completed: completed,
            total: total
        )
        let content = ActivityContent(state: state, staleDate: nil)
        await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(3)))
        self.activity = nil
    }
}
