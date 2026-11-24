import SwiftUI
import SwiftData
import Photos

struct ItemDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var item: LibraryItem

    @State private var showingActivity = false
    @State private var showingDelete = false
    @State private var toast: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                mediaSection

                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title)
                        .font(.title3.weight(.semibold))

                    HStack {
                        Label(item.sourceEnum.displayName, systemImage: item.sourceEnum.icon)
                        Text(item.kindEnum.displayName)
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
                        showingActivity = true
                    } label: {
                        Label("分享 / 导出到备忘录", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        Task { await saveToPhotos() }
                    } label: {
                        Label("保存到相册", systemImage: "photo")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    if item.needsRetry {
                        Button {
                            retryMedia()
                        } label: {
                            Label("重试下载", systemImage: "arrow.triangle.2.circlepath")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        if let error = item.lastDownloadError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
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
    }

    @ViewBuilder
    private var mediaSection: some View {
        if item.kindEnum == .video, let video = item.videoFile, video.existsOnDisk {
            VideoPlayerView(url: video.fileURL)
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else if item.kindEnum == .audio, let audio = item.audioFile, audio.existsOnDisk {
            AudioPlayerView(url: audio.fileURL)
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else if [.image, .imageText, .dynamic].contains(item.kindEnum), !item.imageFiles.isEmpty {
            ImageViewerView(urls: item.imageFiles.filter { $0.existsOnDisk }.map(\.fileURL))
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else if let cover = item.coverFile, cover.existsOnDisk {
            LocalImageView(url: cover.fileURL)
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
                let images = item.imageFiles.filter { $0.existsOnDisk }.map(\.fileURL)
                if images.isEmpty {
                    toast = "没有可保存的图片或视频"
                    return
                }
                try await PhotoSaver.saveImages(images)
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

    private func retryMedia() {
        MediaRetryService.enqueueRetry(item: item, in: modelContext)
        toast = "已加入下载队列"
    }
}

extension MediaSource {
    var icon: String {
        switch self {
        case .douyin: return "music.note"
        case .kuaishou: return "bolt"
        case .xiaohongshu: return "book"
        case .bilibili: return "tv"
        }
    }
}
