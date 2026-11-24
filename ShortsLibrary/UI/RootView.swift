import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case douyin
    case kuaishou
    case xiaohongshu
    case bilibili
    case video
    case image
    case imageText
    case dynamic
    case audio
    case favorites
    case trash

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "全部"
        case .douyin: return "抖音"
        case .kuaishou: return "快手"
        case .xiaohongshu: return "小红书"
        case .bilibili: return "B站"
        case .video: return "视频"
        case .image: return "图片"
        case .imageText: return "图文"
        case .dynamic: return "动态"
        case .audio: return "音频"
        case .favorites: return "收藏"
        case .trash: return "最近删除"
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.stack.3d.up"
        case .douyin: return "music.note"
        case .kuaishou: return "bolt"
        case .xiaohongshu: return "book"
        case .bilibili: return "tv"
        case .video: return "video"
        case .image: return "photo"
        case .imageText: return "photo.stack"
        case .dynamic: return "bubble.left.and.bubble.right"
        case .audio: return "waveform"
        case .favorites: return "star"
        case .trash: return "trash"
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("shorts.lastClipboardChangeCount") private var lastClipboardChangeCount = 0
    @AppStorage("shorts.lastPromptedLink") private var lastPromptedLink = ""

    @State private var filter: LibraryFilter = .all
    @State private var isAdding = false
    @State private var initialURL: URL?
    @State private var alertMessage: String?
    @State private var backupURL: URL?
    @State private var showingRestore = false
    @State private var showingQueue = false
    @State private var detectedLink: URL?
    @State private var detectedPlatform = ""

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(LibraryFilter.allCases) { item in
                    Button {
                        filter = item
                    } label: {
                        Label(item.displayName, systemImage: item.icon)
                            .foregroundStyle(filter == item ? .primary : .secondary)
                    }
                }

                Section("数据") {
                    Button {
                        showingQueue = true
                    } label: {
                        Label("下载队列", systemImage: "arrow.down.circle")
                    }
                    Button {
                        do {
                            backupURL = try LibraryBackup.export(in: modelContext)
                        } catch {
                            alertMessage = error.localizedDescription
                        }
                    } label: {
                        Label("导出 library.json", systemImage: "square.and.arrow.up.on.square")
                    }
                    Button {
                        showingRestore = true
                    } label: {
                        Label("恢复 library.json", systemImage: "square.and.arrow.down.on.square")
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("短视频库")
        } detail: {
            LibraryListView(filter: filter, isAdding: $isAdding)
        }
        .sheet(isPresented: $isAdding, onDismiss: { initialURL = nil }) {
            AddLinkView(initialURL: initialURL)
        }
        .sheet(isPresented: Binding(
            get: { backupURL != nil },
            set: { if !$0 { backupURL = nil } }
        )) {
            if let backupURL {
                ActivityView(items: [backupURL])
            }
        }
        .sheet(isPresented: $showingQueue) {
            DownloadQueueView()
        }
        .fileImporter(isPresented: $showingRestore, allowedContentTypes: [.json]) { result in
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
        .alert("提示", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .task {
            LibraryRepository.shared.purgeExpiredTrash(in: modelContext)
            await NotificationService.shared.requestAuthorization()
            checkClipboard()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { checkClipboard() }
        }
        .alert("检测到\(detectedPlatform)链接", isPresented: Binding(
            get: { detectedLink != nil },
            set: { if !$0 { detectedLink = nil } }
        )) {
            Button("忽略", role: .cancel) {}
            Button("解析") {
                guard let link = detectedLink else { return }
                detectedLink = nil
                parseDetectedLink(link)
            }
        } message: {
            Text(detectedLink?.absoluteString ?? "")
        }
        .onOpenURL { url in
            if let target = Self.extractURL(from: url) {
                initialURL = target
                isAdding = true
            } else {
                alertMessage = "无法识别打开的链接"
            }
        }
    }

    private func parseDetectedLink(_ link: URL) {
        Task {
            do {
                alertMessage = try await LinkIngestService.ingest(url: link, modelContext: modelContext)
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    private func checkClipboard() {
        let pasteboard = UIPasteboard.general
        guard pasteboard.changeCount != lastClipboardChangeCount else { return }
        lastClipboardChangeCount = pasteboard.changeCount

        guard let text = pasteboard.string,
              let url = LinkExtractor.firstURL(in: text),
              let parser = ParserRegistry.parser(for: url),
              url.absoluteString != lastPromptedLink else { return }

        detectedLink = url
        detectedPlatform = parser.source.displayName
        lastPromptedLink = url.absoluteString
    }

    private static func extractURL(from url: URL) -> URL? {
        if url.scheme?.lowercased() == "shortsaver" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            guard let value = components?.queryItems?.first(where: { $0.name == "url" })?.value,
                  let target = URL(string: value),
                  ["http", "https"].contains(target.scheme?.lowercased() ?? "") else {
                return nil
            }
            return target
        }
        if ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            return url
        }
        return nil
    }
}
