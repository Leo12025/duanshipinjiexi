import SwiftUI
import SwiftData

struct LibraryListView: View {
    let filter: LibraryFilter
    @Binding var isAdding: Bool

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \LibraryItem.createdAt, order: .reverse)
    private var allItems: [LibraryItem]

    @State private var searchText = ""
    @State private var inputText = ""
    @State private var isParsing = false
    @State private var parseMessage: String?
    @State private var parseFailed = false
    @State private var existingItem: LibraryItem?
    @State private var loginRequiredPlatform: PlatformLogin?

    init(filter: LibraryFilter, isAdding: Binding<Bool>) {
        self.filter = filter
        self._isAdding = isAdding
    }

    private var detectedPlatform: String? {
        LinkIngestService.detectPlatform(in: inputText)
    }

    private var canParse: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isParsing
    }

    private var items: [LibraryItem] {
        let activeItems = allItems.filter { !$0.isTrashed }
        var result: [LibraryItem]

        switch filter {
        case .all:
            result = activeItems
        case .douyin:
            result = activeItems.filter { $0.sourceEnum == .douyin }
        case .kuaishou:
            result = activeItems.filter { $0.sourceEnum == .kuaishou }
        case .xiaohongshu:
            result = activeItems.filter { $0.sourceEnum == .xiaohongshu }
        case .bilibili:
            result = activeItems.filter { $0.sourceEnum == .bilibili }
        case .video:
            result = activeItems.filter { $0.kindEnum == .video }
        case .image:
            result = activeItems.filter { $0.kindEnum == .image }
        case .imageText:
            result = activeItems.filter { $0.kindEnum == .imageText }
        case .dynamic:
            result = activeItems.filter { $0.kindEnum == .dynamic }
        case .audio:
            result = activeItems.filter { $0.kindEnum == .audio }
        case .favorites:
            result = activeItems.filter { $0.isFavorite }
        case .trash:
            result = allItems.filter { $0.isTrashed }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return result }

        return result.filter { item in
            [item.title, item.author ?? "", item.caption ?? ""]
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if filter == .all {
                    ingestBox
                }

                Group {
                    if items.isEmpty {
                        ContentUnavailableView {
                            Label("暂无内容", systemImage: "tray")
                        } description: {
                            Text("在上方粘贴链接，或点击右上角 + 添加")
                        } actions: {
                            Button("添加链接") { isAdding = true }
                        }
                    } else {
                        ScrollView {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 150), spacing: 14)],
                                spacing: 14
                            ) {
                                ForEach(items) { item in
                                    if filter == .trash {
                                        TrashCard(item: item)
                                    } else {
                                        NavigationLink(value: item) {
                                            ItemCard(item: item)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle(filter.displayName)
            .searchable(text: $searchText, prompt: "搜索标题、作者、文案")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isAdding = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(for: LibraryItem.self) { item in
                ItemDetailView(item: item)
            }
        }
    }

    private var ingestBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("解析链接", systemImage: "link.badge.plus")
                    .font(.headline)
                Spacer()
                if let detectedPlatform {
                    Label(detectedPlatform, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            HStack(alignment: .top, spacing: 8) {
                TextField("粘贴抖音 / 快手 / 小红书 / B站分享文案或链接", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button {
                    Task { await ingest() }
                } label: {
                    if isParsing {
                        ProgressView()
                    } else {
                        Text("解析")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canParse)
            }

            if let parseMessage {
                Text(parseMessage)
                    .font(.caption)
                    .foregroundStyle(parseFailed ? .red : .green)
            }

            if let existingItem {
                HStack(spacing: 8) {
                    Text("如需获取最新资源可重新下载")
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
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
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

private struct ItemCard: View {
    let item: LibraryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if let cover = item.coverFile, cover.existsOnDisk {
                    LocalImageView(url: cover.fileURL, thumbnail: true)
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: item.kindEnum == .video ? "play.rectangle" : "photo.stack")
                                .font(.title)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(item.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack {
                Text(item.sourceEnum.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if item.needsRetry {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Image(systemName: item.kindEnum == .video ? "video" : "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TrashCard: View {
    @Environment(\.modelContext) private var modelContext
    let item: LibraryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            if let date = item.trashedAt {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("恢复") {
                    LibraryRepository.shared.restore(item: item, in: modelContext)
                }
                .buttonStyle(.bordered)
                Button("彻底删除", role: .destructive) {
                    try? LibraryRepository.shared.deletePermanently(item: item, in: modelContext)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }
}
