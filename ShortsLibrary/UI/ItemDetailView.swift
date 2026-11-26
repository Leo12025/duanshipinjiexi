import SwiftUI
import SwiftData
import Photos

struct ItemDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var item: LibraryItem

    @State private var showingActivity = false
    @State private var showingTextLinkShare = false
    @State private var showingDelete = false
    @State private var toast: String?
    @State private var isSaving = false
    @State private var showingFullScreenImages = false
    @State private var fullScreenIndex = 0
    @State private var showingFullScreenVideo = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                mediaSection

                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title)
                        .font(.title3.weight(.semibold))

                    HStack(spacing: 8) {
                        Label(item.sourceEnum.displayName, systemImage: item.sourceEnum.icon)
                        Text(Self.typeLabel(for: item))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                        if let author = item.author {
                            Text("作者：\(author)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let caption = item.caption, !caption.isEmpty {
                        Text(caption)
                            .font(.body)
                            .textSelection(.enabled)
                    }

                    if let resolution = item.resolution {
                        Text("画质：\(resolution)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if item.needsAudioMux {
                        Label("音轨尚未合成，可重新下载修复", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if let pageURL = item.pageURL {
                        Link("打开原始链接", destination: pageURL)
                            .font(.footnote)
                    }
                }

                Divider()

                VStack(spacing: 10) {
                    Button {
                        showingTextLinkShare = true
                    } label: {
                        Label("分享文字 + 链接", systemImage: "square.and.arrow.up.on.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        showingActivity = true
                    } label: {
                        Label("分享媒体文件 / 导出到备忘录", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        isSaving = true
                        Task {
                            await saveToPhotos()
                            isSaving = false
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("保存到相册", systemImage: "photo")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSaving)

                    if item.needsRetry {
                        Button {
                            retryMedia()
                        } label: {
                            Label(item.needsAudioMux ? "修复无声" : "重试下载", systemImage: "arrow.triangle.2.circlepath")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        if let error = item.lastDownloadError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    if item.kindEnum == .video, let pageURL = item.pageURL {
                        Button {
                            Task { await reparse(pageURL: pageURL) }
                        } label: {
                            Label("重新解析并修复", systemImage: "arrow.triangle.2.circlepath.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(role: .destructive) {
                        showingDelete = true
                    } label: {
                        Label("删除", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    item.isFavorite.toggle()
                    try? modelContext.save()
                } label: {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                }
            }
        }
        .sheet(isPresented: $showingActivity) {
            ActivityView(items: shareItems)
        }
        .sheet(isPresented: $showingTextLinkShare) {
            ActivityView(items: SharePayload.textAndLinkItems(for: item))
        }
        .alert("确认删除", isPresented: $showingDelete) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { deleteItem() }
        } message: {
            Text("条目会移到“最近删除”，30 天后自动清理。")
        }
        .alert("提示", isPresented: Binding(
            get: { toast != nil },
            set: { if !$0 { toast = nil } }
        )) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(toast ?? "")
        }
        .fullScreenCover(isPresented: $showingFullScreenImages) {
            let files = item.imageFiles.filter { $0.existsOnDisk }
            let videos = item.livePhotoVideoFiles
                .filter { $0.existsOnDisk }
                .reduce(into: [:]) { $0[$1.orderIndex] = $1 }
            FullScreenMediaViewer(
                files: files,
                livePhotoVideos: videos,
                initialIndex: fullScreenIndex,
                isPresented: $showingFullScreenImages
            )
        }
        .fullScreenCover(isPresented: $showingFullScreenVideo) {
            NavigationStack {
                Group {
                    if let video = item.videoFile, video.existsOnDisk {
                        VideoPlayerView(url: video.fileURL)
                    }
                }
                .ignoresSafeArea()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("关闭") { showingFullScreenVideo = false }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var mediaSection: some View {
        if item.kindEnum == .video, let video = item.videoFile, video.existsOnDisk {
            Button {
                showingFullScreenVideo = true
            } label: {
                VideoPlayerView(url: video.fileURL)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.black.opacity(0.5), in: Circle())
                            .padding(8)
                    }
            }
            .buttonStyle(.plain)
        } else if item.kindEnum == .audio, let audio = item.audioFile, audio.existsOnDisk {
            AudioPlayerView(url: audio.fileURL)
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else if [.image, .imageText, .dynamic].contains(item.kindEnum),
                  !item.imageFiles.filter({ $0.existsOnDisk }).isEmpty {
            let files = item.imageFiles.filter { $0.existsOnDisk }
            let videos = item.livePhotoVideoFiles
                .filter { $0.existsOnDisk }
                .reduce(into: [:]) { $0[$1.orderIndex] = $1 }
            ImageViewerView(
                files: files,
                livePhotoVideos: videos,
                onTap: { index in
                    fullScreenIndex = index
                    showingFullScreenImages = true
                }
            )
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else if let cover = item.coverFile, cover.existsOnDisk {
            LocalImageView(url: cover.fileURL, animated: cover.isAnimated)
                .frame(maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            Rectangle()
                .fill(.quaternary)
                .frame(height: 220)
                .overlay {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private static func typeLabel(for item: LibraryItem) -> String {
        switch item.kindEnum {
        case .imageText, .dynamic:
            return "\(item.kindEnum.displayName) · \(item.sourceImageURLStrings.count)张"
        default:
            return item.kindEnum.displayName
        }
    }

    private var shareItems: [Any] {
        var lines: [String] = [item.title]
        if let author = item.author { lines.append("作者：\(author)") }
        if let caption = item.caption, !caption.isEmpty { lines.append("") ; lines.append(caption) }
        if let pageURL = item.pageURL { lines.append("") ; lines.append("来源：\(pageURL.absoluteString)") }

        var items: [Any] = [lines.joined(separator: "\n")]
        for file in item.files where file.existsOnDisk {
            items.append(file.fileURL)
        }
        return items
    }

    private func saveToPhotos() async {
        if item.kindEnum == .audio {
            toast = "音频不支持保存到相册"
            return
        }

        do {
            if item.kindEnum == .video,
               let video = item.videoFile,
               video.existsOnDisk {
                try await PhotoSaver.saveVideo(video.fileURL)
            } else {
                var pairs: [(image: URL, video: URL)] = []
                var plainImages: [URL] = []
                for file in item.imageFiles.filter({ $0.existsOnDisk }) {
                    if let video = item.livePhotoVideoFile(orderIndex: file.orderIndex),
                       video.existsOnDisk {
                        pairs.append((file.fileURL, video.fileURL))
                    } else {
                        plainImages.append(file.fileURL)
                    }
                }
                if pairs.isEmpty && plainImages.isEmpty {
                    toast = "没有可保存的图片或视频"
                    return
                }
                try await PhotoSaver.saveImages(plainImages)
                try await PhotoSaver.saveLivePhotos(pairs)
            }
            toast = "已保存到相册"
        } catch {
            toast = error.localizedDescription
        }
    }

    private func deleteItem() {
        LibraryRepository.shared.trash(item: item, in: modelContext)
        dismiss()
    }

    private func reparse(pageURL: URL) async {
        do {
            let loggedIn = await LoginSessionManager.shared.isLoggedIn(for: pageURL)
            ParseCache.clear(for: pageURL, loggedIn: loggedIn)
            try await LinkIngestService.ingest(url: pageURL, modelContext: modelContext)
            toast = "已重新解析，正在修复音轨"
        } catch {
            toast = error.localizedDescription
        }
    }

    private func retryMedia() {
        let isAudioRepair = item.needsAudioMux
        MediaRetryService.enqueueRetry(item: item, in: modelContext)
        toast = isAudioRepair ? "已开始修复音轨" : "已加入下载队列"
    }
}

extension MediaSource {
    var icon: String {
        switch self {
        case .douyin: return "music.note"
        case .kuaishou: return "bolt"
        case .xiaohongshu: return "book"
        case .bilibili: return "tv"
        case .wechatChannels: return "play.tv"
        }
    }
}
