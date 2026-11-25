import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UserNotifications

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \LibraryItem.createdAt, order: .reverse)
    private var allItems: [LibraryItem]

    @Query(sort: \FollowedAccount.syncedAt, order: .reverse)
    private var accounts: [FollowedAccount]

    @ObservedObject private var login = LoginSessionManager.shared
    @ObservedObject private var queue = DownloadQueue.shared

    @AppStorage("shorts.wifiOnly") private var wifiOnly = false
    @AppStorage("shorts.maxConcurrent") private var maxConcurrent = 1
    @AppStorage("shorts.notifyOnComplete") private var notifyOnComplete = true

    @State private var showingQueue = false
    @State private var showingFollows = false
    @State private var showingRestore = false
    @State private var loginPlatform: PlatformLogin?
    @State private var backupURL: URL?
    @State private var alertMessage: String?
    @State private var notificationGranted = false

    private var activeItems: [LibraryItem] {
        allItems.filter { !$0.isTrashed }
    }

    private var videoCount: Int {
        activeItems.filter { $0.kindEnum == .video }.count
    }

    private var imageCount: Int {
        activeItems.filter { [.image, .imageText, .dynamic].contains($0.kindEnum) }.count
    }

    private var favoriteCount: Int {
        activeItems.filter { $0.isFavorite }.count
    }

    private var storageText: String {
        let bytes = activeItems.reduce(Int64(0)) { $0 + ($1.byteSize ?? 0) }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var loggedInCount: Int {
        PlatformLogin.allCases.filter { login.states[$0] == true }.count
    }

    var body: some View {
        NavigationStack {
            List {
                profileHeader
                overviewSection
                loginSection
                toolsSection
                dataSection
                aboutSection
            }
            .navigationTitle("我的")
            .sheet(isPresented: $showingQueue) {
                DownloadQueueView()
            }
            .sheet(isPresented: $showingFollows) {
                FollowListView()
            }
            .sheet(item: $loginPlatform) { platform in
                PlatformLoginView(platform: platform)
            }
            .sheet(isPresented: Binding(
                get: { backupURL != nil },
                set: { if !$0 { backupURL = nil } }
            )) {
                if let backupURL {
                    ActivityView(items: [backupURL])
                }
            }
            .fileImporter(isPresented: $showingRestore, allowedContentTypes: [.json]) { result in
                handleRestore(result)
            }
            .alert("提示", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
            .task {
                await login.refresh()
                await refreshNotificationStatus()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openPlatformLogin)) { output in
                if let platform = output.object as? PlatformLogin {
                    loginPlatform = platform
                }
            }
        }
    }

    private var profileHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.accentColor, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text("短视频资料库")
                    .font(.headline)
                Text("本地收藏，不上传云端")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private var overviewGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            StatTile(value: "\(activeItems.count)", title: "总条目", icon: "square.stack.3d.up")
            StatTile(value: "\(videoCount)", title: "视频", icon: "video", tint: .blue)
            StatTile(value: "\(imageCount)", title: "图片 / 图文", icon: "photo", tint: .pink)
            StatTile(value: "\(favoriteCount)", title: "收藏", icon: "heart.fill", tint: .red)
        }
        .padding(.vertical, 4)
    }

    private var overviewSection: some View {
        Section("概览") {
            overviewGrid
            LabeledContent("占用空间", value: storageText)
            LabeledContent("关注账号", value: "\(accounts.count)")
        }
    }

    private var loginSection: some View {
        Section {
            ForEach(PlatformLogin.allCases) { platform in
                loginRow(platform)
            }
        } header: {
            HStack {
                Text("平台登录")
                Spacer()
                Text("\(loggedInCount)/\(PlatformLogin.allCases.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("只复用 WebKit Cookie，不保存账号密码，也不模拟登录。")
        }
    }

    @ViewBuilder
    private func loginRow(_ platform: PlatformLogin) -> some View {
        let isLoggedIn = login.states[platform] == true

        HStack(spacing: 12) {
            Image(systemName: platform.icon)
                .frame(width: 24)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(platform.displayName)
                Text(isLoggedIn ? "已登录" : "未登录")
                    .font(.caption)
                    .foregroundStyle(isLoggedIn ? .green : .secondary)
            }
            Spacer()
            if isLoggedIn {
                Button("退出") {
                    Task { await login.logout(platform) }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            } else {
                Button("登录") { loginPlatform = platform }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isLoggedIn { loginPlatform = platform }
        }
    }

    private var toolsSection: some View {
        Section("小工具") {
            Button { showingQueue = true } label: {
                SettingsRow(
                    icon: "arrow.down.circle",
                    title: "下载队列",
                    subtitle: queue.tasks.isEmpty ? "暂无任务" : "\(queue.tasks.count) 个任务"
                )
            }
            .foregroundStyle(.primary)

            Button { showingFollows = true } label: {
                SettingsRow(
                    icon: "person.2",
                    title: "关注列表",
                    subtitle: "同步、搜索与管理关注账号"
                )
            }
            .foregroundStyle(.primary)

            Toggle("仅 Wi-Fi 下载", isOn: wifiOnlyBinding)
            Picker("并发数", selection: maxConcurrentBinding) {
                ForEach(1...4, id: \.self) { value in
                    Text("\(value)").tag(value)
                }
            }
            Toggle("下载完成通知", isOn: notifyOnCompleteBinding)

            Button {
                Task { await requestNotifications() }
            } label: {
                SettingsRow(
                    icon: "bell.badge",
                    title: "通知权限",
                    subtitle: notificationGranted ? "已开启" : "未开启，点击请求授权",
                    tint: notificationGranted ? .green : .orange
                )
            }
            .foregroundStyle(.primary)
        }
    }

    private var dataSection: some View {
        Section("数据管理") {
            Button { exportBackup() } label: {
                SettingsRow(icon: "square.and.arrow.up.on.square", title: "导出 library.json")
            }
            .foregroundStyle(.primary)

            Button { showingRestore = true } label: {
                SettingsRow(icon: "square.and.arrow.down.on.square", title: "恢复 library.json")
            }
            .foregroundStyle(.primary)

            Button(role: .destructive) {
                LibraryRepository.shared.purgeExpiredTrash(in: modelContext)
                alertMessage = "已清理超过 30 天的回收站内容"
            } label: {
                SettingsRow(
                    icon: "trash",
                    title: "清理过期回收站",
                    subtitle: "删除超过 30 天的项目",
                    tint: .red
                )
            }
        }
    }

    private var aboutSection: some View {
        Section {
            Text("短视频资料库 · 本地收藏")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(AppPaths.root.path)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
    }

    private var wifiOnlyBinding: Binding<Bool> {
        Binding(
            get: { wifiOnly },
            set: { value in
                wifiOnly = value
                queue.settingsChanged()
            }
        )
    }

    private var maxConcurrentBinding: Binding<Int> {
        Binding(
            get: { maxConcurrent },
            set: { value in
                maxConcurrent = value
                queue.settingsChanged()
            }
        )
    }

    private var notifyOnCompleteBinding: Binding<Bool> {
        Binding(
            get: { notifyOnComplete },
            set: { value in
                notifyOnComplete = value
                queue.settingsChanged()
            }
        )
    }

    private func exportBackup() {
        do {
            backupURL = try LibraryBackup.export(in: modelContext)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func handleRestore(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let count = try LibraryBackup.restore(from: url, in: modelContext)
                alertMessage = "已恢复 \(count) 条记录"
            } catch {
                alertMessage = error.localizedDescription
            }
        case .failure(let error):
            alertMessage = error.localizedDescription
        }
    }

    private func requestNotifications() async {
        await NotificationService.shared.requestAuthorization()
        await refreshNotificationStatus()
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationGranted = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }
}
