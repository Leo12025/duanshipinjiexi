import ActivityKit
import SwiftUI
import WidgetKit

struct ShortsLibraryLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShortsActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: icon(for: context.state.phase))
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(context.state.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    ProgressView(value: context.state.progress)
                }
                Spacer(minLength: 4)
                if context.state.phase == .downloading {
                    Text("\(context.state.completed)/\(context.state.total)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .activityBackgroundTint(Color(.secondarySystemBackground))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.title, systemImage: icon(for: context.state.phase))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(statusText(for: context.state))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        ProgressView(value: context.state.progress)
                        Link("打开资料库", destination: URL(string: "shortsaver://")!)
                            .font(.caption)
                    }
                }
            } compactLeading: {
                Image(systemName: icon(for: context.state.phase))
            } compactTrailing: {
                Text(statusText(for: context.state))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: icon(for: context.state.phase))
            }
        }
    }

    private func icon(for phase: ShortsActivityAttributes.ContentState.Phase) -> String {
        switch phase {
        case .parsing: return "link"
        case .downloading: return "arrow.down.to.line"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private func statusText(for state: ShortsActivityAttributes.ContentState) -> String {
        switch state.phase {
        case .parsing: return "解析中"
        case .downloading: return "\(Int((state.progress * 100).rounded()))%"
        case .succeeded: return "完成"
        case .failed: return "失败"
        }
    }
}

@main
struct ShortsLibraryLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        ShortsLibraryLiveActivityWidget()
    }
}
