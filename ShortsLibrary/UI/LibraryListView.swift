import SwiftUI
import SwiftData

private struct MonthGroup: Identifiable {
    let title: String
    var items: [LibraryItem]
    let sortDate: Date
    var id: String { title }
}

private enum LibrarySort: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case largest
    case title

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newest: return "最新"
        case .oldest: return "最早"
        case .largest: return "大小"
        case .title: return "标题"
        }
    }
}

struct LibraryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass

    @Query(sort: \LibraryItem.createdAt, order: .reverse)
    private var allItems: [LibraryItem]

    @State private var filter: LibraryFilter = .all
    @State private var sort: LibrarySort = .newest
    @State private var searchText = ""
    @State private var isAdding = false
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var shareItems: [Any]?
    @State private var alertMessage: String?

    private var filteredItems: [LibraryItem] {
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
        case .wechatChannels:
            result = activeItems.filter { $0.sourceEnum == .wechatChannels }
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
        if !query.isEmpty {
            result = result.filter { item in
                [item.title, item.author ?? "", item.caption ?? ""]
                    .joined(separator: " ")
                    .localizedCaseInsensitiveContains(query)
            }
        }

        return result
    }

    private func sortItems(_ items: [LibraryItem]) -> [LibraryItem] {
        switch sort {
        case .newest:
            return items.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return items.sorted { $0.createdAt < $1.createdAt }
        case .largest:
            return items.sorted { ($0.byteSize ?? 0) > ($1.byteSize ?? 0) }
        case .title:
            return items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    private var groupedItems: [MonthGroup] {
        Dictionary(grouping: filteredItems) { Self.monthTitle(for: $0.createdAt) }
            .compactMap { title, items -> MonthGroup? in
                guard let latest = items.map(\.createdAt).max() else { return nil }
                return MonthGroup(title: title, items: sortItems(items), sortDate: latest)
            }
            .sorted { $0.sortDate > $1.sortDate }
    }

    private var selectedItems: [LibraryItem] {
        filteredItems.filter { selectedIDs.contains($0.id) }
    }

    private func columnCount(for width: CGFloat) -> Int {
        guard sizeClass == .regular else { return 2 }
        if width < 700 { return 3 }
        if width < 1000 { return 4 }
        return 5
    }

    private func cardWidth(in containerWidth: CGFloat, columns: Int) -> CGFloat {
        let spacing: CGFloat = 12
        let horizontalPadding: CGFloat = 24
        let available = max(0, containerWidth - horizontalPadding - spacing * CGFloat(columns - 1))
        return floor(available / CGFloat(columns))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar

                Group {
                    if filteredItems.isEmpty {
                        EmptyStateView(
                            systemImage: filter == .trash ? "trash" : "photo.stack",
                            title: filter == .trash ? "回收站是空的" : "没有匹配的内容",
                            message: filter == .trash
                                ? "删除的内容会在这里保留 30 天。"
                                : "试试切换筛选条件，或添加一条新链接。",
                            buttonTitle: filter == .trash ? nil : "添加链接",
                            action: filter == .trash ? nil : { isAdding = true }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        GeometryReader { geometry in
                            ScrollView {
                                let columns = columnCount(for: geometry.size.width)
                                let width = cardWidth(in: geometry.size.width, columns: columns)

                                LazyVStack(alignment: .leading, spacing: 20) {
                                    ForEach(groupedItems) { group in
                                        VStack(alignment: .leading, spacing: 10) {
                                            Text(group.title)
                                                .font(.headline)
                                                .frame(maxWidth: .infinity, alignment: .leading)

                                            LazyVGrid(
                                                columns: Array(
                                                    repeating: GridItem(.fixed(width), spacing: 12),
                                                    count: columns
                                                ),
                                                spacing: 12
                                            ) {
                                                ForEach(group.items) { item in
                                                    card(for: item, size: width)
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("资源库")
            .searchable(text: $searchText, prompt: "搜索标题、作者、文案")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("排序", selection: $sort) {
                            ForEach(LibrarySort.allCases) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.down.circle.dotted")
                            .accessibilityLabel("排序")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isAdding = true
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel("添加链接")
                    }
                }
                if filter != .trash {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(isSelecting ? "完成" : "选择") {
                            isSelecting.toggle()
                            selectedIDs.removeAll()
                        }
                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    if isSelecting && filter != .trash {
                        Button("收藏") {
                            for item in selectedItems {
                                item.isFavorite = true
                            }
                            save()
                            selectedIDs.removeAll()
                        }
                        Spacer()
                        Button("删除", role: .destructive) {
                            for item in selectedItems {
                                LibraryRepository.shared.trash(item: item, in: modelContext)
                            }
                            selectedIDs.removeAll()
                            isSelecting = false
                        }
                    }
                }
            }
            .navigationDestination(for: LibraryItem.self) { item in
                ItemDetailView(item: item)
            }
            .sheet(isPresented: $isAdding) {
                AddLinkView(initialURL: nil)
            }
            .sheet(isPresented: Binding(
                get: { shareItems != nil },
                set: { if !$0 { shareItems = nil } }
            )) {
                if let shareItems {
                    ActivityView(items: shareItems)
                }
            }
            .alert("提示", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
            .onChange(of: filter) { _, _ in
                selectedIDs.removeAll()
                isSelecting = false
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryFilter.allCases) { item in
                    Button {
                        filter = item
                    } label: {
                        Label(item.displayName, systemImage: item.icon)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                filter == item ? Color.accentColor : Color.secondary.opacity(0.12),
                                in: Capsule()
                            )
                            .foregroundStyle(filter == item ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    @ViewBuilder
    private func card(for item: LibraryItem, size: CGFloat) -> some View {
        if filter == .trash {
            TrashCard(item: item)
        } else if isSelecting {
            Button {
                if selectedIDs.contains(item.id) {
                    selectedIDs.remove(item.id)
                } else {
                    selectedIDs.insert(item.id)
                }
            } label: {
                ItemCard(
                    item: item,
                    isSelected: selectedIDs.contains(item.id),
                    showsDetails: false,
                    fixedSize: size
                )
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: item) {
                ItemCard(item: item, showsDetails: false, fixedSize: size)
                    .contextMenu {
                        Button(item.isFavorite ? "取消收藏" : "收藏") {
                            item.isFavorite.toggle()
                            save()
                        }
                        Button("分享文字 + 链接") {
                            shareItems = SharePayload.textAndLinkItems(for: item)
                        }
                        Button("分享媒体文件") {
                            shareItems = Self.sharePayload(for: item)
                        }
                        if item.needsRetry {
                            Button("重新下载") {
                                MediaRetryService.enqueueRetry(item: item, in: modelContext)
                                alertMessage = "已重新加入下载队列"
                            }
                        }
                        Button("删除到最近删除", role: .destructive) {
                            LibraryRepository.shared.trash(item: item, in: modelContext)
                        }
                    }
            }
            .buttonStyle(.plain)
        }
    }

    private func save() {
        try? modelContext.save()
    }

    private static func monthTitle(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        let year = components.year ?? Calendar.current.component(.year, from: date)
        let month = components.month ?? Calendar.current.component(.month, from: date)
        return "\(year)年\(month)月"
    }

    private static func sharePayload(for item: LibraryItem) -> [Any] {
        var result: [Any] = []
        if let pageURL = item.pageURL {
            result.append(pageURL)
        }
        result.append(contentsOf: item.files.filter { $0.existsOnDisk }.map(\.fileURL))
        return result
    }
}
