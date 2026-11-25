import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext

    @Binding var externalInput: URL?
    @Binding var selectedTab: Int

    @Query(sort: \LibraryItem.createdAt, order: .reverse)
    private var allItems: [LibraryItem]

    @ObservedObject private var queue = DownloadQueue.shared

    @State private var inputText = ""
    @State private var isParsing = false
    @State private var parseMessage: String?
    @State private var parseFailed = false
    @State private var existingItem: LibraryItem?
    @State private var loginRequiredPlatform: PlatformLogin?
    @State private var showingQueue = false
    @State private var showingFollows = false
    @State private var loginPlatform: PlatformLogin?

    private var activeItems: [LibraryItem] {
        allItems.filter { !$0.isTrashed }
    }

    private var recentItems: [LibraryItem] {
        Array(activeItems.prefix(8))
    }

    private var detectedPlatform: String? {
        LinkIngestService.detectPlatform(in: inputText)
    }

    private var canParse: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isParsing
    }

    private var pendingCount: Int {
        queue.tasks.filter { $0.status == .pending || $0.status == .running }.count
    }

    private var runningTask: DownloadQueueTask? {
        queue.tasks.first { $0.status == .running }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    parseCard

                    if pendingCount > 0 {
                        downloadSummary
                    }

                    quickActions
                    recentSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: LibraryItem.self) { item in
                ItemDetailView(item: item)
            }
            .sheet(isPresented: $showingQueue) {
                DownloadQueueView()
            }
            .sheet(isPresented: $showingFollows) {
                FollowListView()
            }
            .sheet(item: $loginPlatform) { platform in
                PlatformLoginView(platform: platform)
            }
            .onChange(of: externalInput) { _, newValue in
                guard let url = newValue else { return }
                inputText = url.absoluteString
                externalInput = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .openPlatformLogin)) { output in
                if let platform = output.object as? PlatformLogin {
                    loginPlatform = platform
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("短视频资料库")
                .font(.largeTitle.bold())
            Text("本地收藏 · 已保存 \(activeItems.count) 条")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var parseCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("解析新内容", systemImage: "link.badge.plus")
                    .font(.headline)
                Spacer()
                if let detectedPlatform {
                    Label(detectedPlatform, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .lineLimit(1)
                }
            }

            TextEditor(text: $inputText)
                .frame(minHeight: 84)
                .padding(8)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    if inputText.isEmpty {
                        Text("粘贴抖音 / 快手 / 小红书 / B站分享文案或链接")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .allowsHitTesting(false)
                    }
                }
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            HStack {
                if let parseMessage {
                    Text(parseMessage)
                        .font(.caption)
                        .foregroundStyle(parseFailed ? .red : .green)
                        .lineLimit(2)
                }
                Spacer()
                Button {
                    Task { await ingest() }
                } label: {
                    if isParsing {
                        ProgressView()
                            .frame(width: 18, height: 18)
                    } else {
                        Label("解析并入队", systemImage: "arrow.right.circle.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canParse)
            }

            if let existingItem {
                HStack(spacing: 8) {
                    Text("这条已收藏，可重新下载最新资源")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("重新下载") {
                        LinkIngestService.redownload(item: existingItem, in: modelContext)
                        self.existingItem = nil
                        parseMessage = "已重新加入下载队列"
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
            }

            if let platform = loginRequiredPlatform {
                Button("去登录 \(platform.displayName)") {
                    NotificationCenter.default.post(name: .openPlatformLogin, object: platform)
                    loginRequiredPlatform = nil
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var downloadSummary: some View {
        Button {
            showingQueue = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("正在下载 \(pendingCount) 项", systemImage: "arrow.down.circle")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if let task = runningTask {
                    ProgressView(value: task.progress)
                    Text(task.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var quickActions: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            QuickActionCard(
                title: "下载队列",
                subtitle: pendingCount > 0 ? "\(pendingCount) 项进行中" : "暂无任务",
                systemImage: "arrow.down.circle",
                tint: .blue
            ) { showingQueue = true }

            QuickActionCard(
                title: "关注列表",
                subtitle: "同步与管理关注",
                systemImage: "person.2",
                tint: .purple
            ) { showingFollows = true }

            QuickActionCard(
                title: "平台登录",
                subtitle: "复用 WebKit Cookie",
                systemImage: "person.badge.key",
                tint: .orange
            ) {
                selectedTab = 2
            }

            QuickActionCard(
                title: "数据备份",
                subtitle: "导出 / 恢复",
                systemImage: "externaldrive",
                tint: .teal
            ) {
                selectedTab = 2
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近入库")
                    .font(.title3.bold())
                Spacer()
                Button("查看全部") { selectedTab = 1 }
                    .font(.subheadline)
            }

            if recentItems.isEmpty {
                EmptyStateView(
                    systemImage: "sparkles.rectangle.stack",
                    title: "还没有收藏",
                    message: "在上方粘贴一条分享链接，解析后内容会自动进入资源库。"
                )
                .frame(maxWidth: .infinity, minHeight: 220)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(recentItems) { item in
                            NavigationLink(value: item) {
                                RecentItemCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func ingest() async {
        isParsing = true
        parseMessage = nil
        parseFailed = false
        existingItem = nil
        loginRequiredPlatform = nil
        defer { isParsing = false }

        do {
            let outcome = try await LinkIngestService.ingest(text: inputText, modelContext: modelContext)
            parseMessage = outcome.message
            existingItem = outcome.isNew ? nil : outcome.item
            inputText = ""
        } catch {
            parseFailed = true
            parseMessage = error.localizedDescription
            if case AppError.loginRequired(let name) = error,
               let platform = PlatformLogin.allCases.first(where: { $0.displayName == name }) {
                loginRequiredPlatform = platform
            }
        }
    }
}

private struct QuickActionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}
