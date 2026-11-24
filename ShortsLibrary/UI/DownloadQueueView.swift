import SwiftUI

struct DownloadQueueView: View {
    @ObservedObject private var queue = DownloadQueue.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("设置") {
                    Toggle("仅 Wi-Fi 下载", isOn: boolBinding("shorts.wifiOnly"))
                    Picker("并发数", selection: intBinding("shorts.maxConcurrent")) {
                        ForEach(1...4, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    Toggle("下载完成通知", isOn: boolBinding("shorts.notifyOnComplete"))
                    if queue.waitingForNetwork {
                        Text("等待网络满足当前设置后继续下载")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section("任务") {
                    if queue.tasks.isEmpty {
                        Text("暂无下载任务")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(queue.tasks) { task in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(task.label)
                                        .font(.subheadline.weight(.medium))
                                    Spacer()
                                    Text(statusText(task.status))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if task.status == .running {
                                    ProgressView(value: task.progress)
                                }
                                if let error = task.error {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("下载队列")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("清除已完成") { queue.clearCompleted() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func boolBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { UserDefaults.standard.bool(forKey: key) },
            set: { value in
                UserDefaults.standard.set(value, forKey: key)
                queue.settingsChanged()
            }
        )
    }

    private func intBinding(_ key: String) -> Binding<Int> {
        Binding(
            get: { UserDefaults.standard.integer(forKey: key) },
            set: { value in
                UserDefaults.standard.set(value, forKey: key)
                queue.settingsChanged()
            }
        )
    }

    private func statusText(_ status: QueueTaskStatus) -> String {
        switch status {
        case .pending: return "等待中"
        case .running: return "下载中"
        case .done: return "完成"
        case .failed: return "失败"
        }
    }
}
