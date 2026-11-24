import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct FollowListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \FollowedAccount.syncedAt, order: .reverse)
    private var accounts: [FollowedAccount]

    @State private var searchText = ""
    @State private var platformFilter: MediaSource?
    @State private var showingDuplicates = false
    @State private var showingImport = false
    @State private var message: String?
    @State private var isSyncing = false

    private var filtered: [FollowedAccount] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return accounts.filter { account in
            if let platformFilter, account.platformEnum != platformFilter { return false }
            guard !query.isEmpty else { return true }
            return [account.platformUserId, account.secUserId ?? "", account.displayName, account.remark ?? "", account.groupName ?? ""]
                .joined(separator: " ")
                .lowercased()
                .contains(query)
        }
    }

    private var duplicates: [DuplicatePair] {
        FollowSimilarity.detect(among: accounts)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("同步") {
                    ForEach([MediaSource.bilibili, .douyin, .kuaishou]) { platform in
                        Button {
                            Task { await sync(platform) }
                        } label: {
                            HStack {
                                Label("同步\(platform.displayName)关注", systemImage: platform == .bilibili ? "tv" : platform == .douyin ? "music.note" : "bolt")
                                Spacer()
                                if isSyncing { ProgressView() }
                            }
                        }
                        .disabled(isSyncing)
                    }
                    Text("小红书网页端无正式关注列表，请使用手动导入。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Picker("平台", selection: $platformFilter) {
                        Text("全部").tag(nil as MediaSource?)
                        ForEach(MediaSource.allCases) { platform in
                            Text(platform.displayName).tag(platform as MediaSource?)
                        }
                    }
                    Button {
                        showingDuplicates = true
                    } label: {
                        Label("重复 / 相似查询（\(duplicates.count)）", systemImage: "person.2.badge.gearshape")
                    }
                    Button {
                        showingImport = true
                    } label: {
                        Label("手动导入 / 添加", systemImage: "plus.square.on.square")
                    }
                }

                Section("关注账号（\(filtered.count)）") {
                    ForEach(filtered) { account in
                        NavigationLink(value: account) {
                            FollowAccountRow(account: account)
                        }
                    }
                }
            }
            .navigationTitle("关注列表")
            .searchable(text: $searchText, prompt: "搜索 ID、名称、备注、分组")
            .navigationDestination(for: FollowedAccount.self) { account in
                FollowAccountEditView(account: account)
            }
            .sheet(isPresented: $showingDuplicates) {
                DuplicateListView(pairs: duplicates)
            }
            .sheet(isPresented: $showingImport) {
                FollowImportView()
            }
            .alert("提示", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func sync(_ platform: MediaSource) async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            message = try await FollowListService.collect(platform: platform, in: modelContext)
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct FollowAccountRow: View {
    let account: FollowedAccount

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(account.displayName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(account.platformEnum.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("ID：\(account.platformUserId)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let remark = account.remark, !remark.isEmpty {
                Text("备注：\(remark)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let group = account.groupName, !group.isEmpty {
                Text("分组：\(group)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct FollowAccountEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var account: FollowedAccount

    var body: some View {
        Form {
            Section("账号") {
                LabeledContent("平台", value: account.platformEnum.displayName)
                LabeledContent("ID", value: account.platformUserId)
                if let sec = account.secUserId {
                    LabeledContent("secID", value: sec)
                }
                TextField("名称", text: $account.displayName)
            }
            Section("本地信息") {
                TextField("备注", text: Binding(
                    get: { account.remark ?? "" },
                    set: { account.remark = $0.isEmpty ? nil : $0 }
                ))
                TextField("分组", text: Binding(
                    get: { account.groupName ?? "" },
                    set: { account.groupName = $0.isEmpty ? nil : $0 }
                ))
            }
            Section {
                Text("来源：\(account.sourceEnum.displayName)")
                Text("同步时间：\(account.syncedAt.formatted(date: .abbreviated, time: .shortened))")
            } header: {
                Text("元信息")
            }
        }
        .navigationTitle(account.displayName)
        .onDisappear { try? modelContext.save() }
    }
}

private struct DuplicateListView: View {
    @Environment(\.dismiss) private var dismiss
    let pairs: [DuplicatePair]

    var body: some View {
        NavigationStack {
            List {
                if pairs.isEmpty {
                    Text("未发现重复或相似账号")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(pairs) { pair in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(pair.first.displayName)
                                Text("↔")
                                    .foregroundStyle(.secondary)
                                Text(pair.second.displayName)
                                Spacer()
                                Text("\(pair.score)%")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            Text("\(pair.first.platformEnum.displayName) · \(pair.first.platformUserId) / \(pair.second.platformEnum.displayName) · \(pair.second.platformUserId)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(pair.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("重复 / 相似")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private struct FollowImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var platform: MediaSource = .xiaohongshu
    @State private var text = ""
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("平台", selection: $platform) {
                        ForEach(MediaSource.allCases) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    TextEditor(text: $text)
                        .frame(minHeight: 120)
                    Text("每行一个账号，格式：ID,名称,备注（备注可省略）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("手动导入")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") { Task { await importAccounts() } }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .alert("提示", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("好的", role: .cancel) {
                    if message?.hasPrefix("已导入") == true { dismiss() }
                }
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func importAccounts() async {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let drafts: [FollowedAccountDraft] = lines.compactMap { line in
            let parts = line.split(separator: ",", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let id = parts.first, !id.isEmpty, let name = parts.dropFirst().first, !name.isEmpty else { return nil }
            let remark = parts.count > 2 ? parts[2] : nil
            return FollowedAccountDraft(
                platformUserId: id,
                secUserId: nil,
                displayName: name,
                remark: remark,
                groupName: nil,
                avatarURLString: nil
            )
        }
        guard !drafts.isEmpty else {
            message = "没有可导入的账号"
            return
        }
        let count = await FollowListRepository.upsert(drafts: drafts, platform: platform, source: .manual, in: modelContext)
        message = "已导入 \(count) 个账号"
    }
}
