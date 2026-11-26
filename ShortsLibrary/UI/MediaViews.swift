import SwiftUI
import UIKit
import AVKit
import AVFoundation

private enum PlayerAudioSession {
    static func prepare(mode: AVAudioSession.Mode = .moviePlayback) {
        Task.detached(priority: .utility) {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: mode, options: [.duckOthers])
            if #available(iOS 27.0, *) {
                session.activate(options: []) { _, _ in }
            } else {
                try? session.setActive(true, options: .notifyOthersOnDeactivation)
            }
        }
    }
}

struct LocalImageView: View {
    let url: URL
    var thumbnail = false
    var animated = false

    var body: some View {
        Group {
            if let image = resolvedImage {
                if animated && !thumbnail {
                    AnimatedImageView(image: image)
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
        }
    }

    private var resolvedImage: UIImage? {
        if thumbnail { return ThumbnailCache.image(for: url) }
        if animated { return ImageFileProcessor.animatedImage(at: url) }
        return UIImage(contentsOfFile: url.path)
    }
}

struct AnimatedImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.startAnimating()
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        uiView.image = image
        uiView.startAnimating()
    }
}

struct FullScreenMediaViewer: View {
    let files: [MediaFile]
    let livePhotoVideos: [Int: MediaFile]
    let initialIndex: Int
    @Binding var isPresented: Bool
    @State private var selection: Int
    @State private var showingVideo = false
    @State private var toast: String?
    @Environment(\.dismiss) private var dismiss

    init(
        files: [MediaFile],
        livePhotoVideos: [Int: MediaFile],
        initialIndex: Int,
        isPresented: Binding<Bool>
    ) {
        self.files = files
        self.livePhotoVideos = livePhotoVideos
        self.initialIndex = initialIndex
        self._isPresented = isPresented
        self._selection = State(initialValue: initialIndex)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                    ZoomableMediaView(
                        imageURL: file.fileURL,
                        videoURL: livePhotoVideos[file.orderIndex]?.fileURL,
                        showingVideo: $showingVideo
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: files.count > 1 ? .automatic : .never))
            .background(Color.black)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { close() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            Task { await saveCurrent() }
                        } label: {
                            Label("保存到相册", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast)
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.7), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(.bottom, 24)
                        .transition(.opacity)
                }
            }
        }
        .onChange(of: selection) { _, _ in showingVideo = false }
    }

    private func close() {
        isPresented = false
        dismiss()
    }

    private func saveCurrent() async {
        guard files.indices.contains(selection) else { return }
        let file = files[selection]
        do {
            if let video = livePhotoVideos[file.orderIndex], video.existsOnDisk {
                try await PhotoSaver.saveLivePhotos([(file.fileURL, video.fileURL)])
            } else {
                try await PhotoSaver.saveImages([file.fileURL])
            }
            await MainActor.run { toast = "已保存到相册" }
        } catch {
            await MainActor.run { toast = error.localizedDescription }
        }
    }
}

struct ZoomableMediaView: View {
    let imageURL: URL
    let videoURL: URL?
    @Binding var showingVideo: Bool

    @State private var scale: CGFloat = 1
    @State private var accumulatedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var accumulatedOffset: CGSize = .zero

    var body: some View {
        ZStack {
            if showingVideo, let videoURL {
                LoopingVideoPlayerView(url: videoURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let image = UIImage(contentsOfFile: imageURL.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = min(max(accumulatedScale * value, 1), 6)
                            }
                            .onEnded { _ in
                                accumulatedScale = scale
                                if scale <= 1 { resetOffset() }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                guard scale > 1 else { return }
                                offset = CGSize(
                                    width: accumulatedOffset.width + value.translation.width,
                                    height: accumulatedOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in accumulatedOffset = offset }
                    )
                    .onTapGesture(count: 2) {
                        if scale > 1 { resetZoom() } else { scale = 2.5; accumulatedScale = scale }
                    }
            } else {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }

            if videoURL != nil {
                Button {
                    showingVideo.toggle()
                } label: {
                    Label(showingVideo ? "图片" : "LIVE", systemImage: showingVideo ? "photo" : "livephoto")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.6), in: Capsule())
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(16)
            }
        }
        .clipped()
    }

    private func resetZoom() {
        scale = 1
        accumulatedScale = 1
        resetOffset()
    }

    private func resetOffset() {
        offset = .zero
        accumulatedOffset = .zero
    }
}

struct LoopingVideoPlayerView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> UIView {
        PlayerAudioSession.prepare(mode: .moviePlayback)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.volume = 0
        let item = AVPlayerItem(url: url)
        let looper = AVPlayerLooper(player: player, templateItem: item)
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        let view = UIView()
        view.backgroundColor = .clear
        view.layer.addSublayer(layer)
        context.coordinator.player = player
        context.coordinator.layer = layer
        context.coordinator.looper = looper
        player.play()
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.layer?.frame = uiView.bounds
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.player?.pause()
        coordinator.player = nil
        coordinator.looper = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var player: AVQueuePlayer?
        var layer: AVPlayerLayer?
        var looper: AVPlayerLooper?
    }
}

struct LivePhotoView: View {
    let imageURL: URL
    let videoURL: URL?
    @State private var showingVideo = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if showingVideo, let videoURL {
                LoopingVideoPlayerView(url: videoURL)
            } else {
                LocalImageView(url: imageURL)
            }
            if videoURL != nil {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showingVideo.toggle() }
                } label: {
                    Label(showingVideo ? "图片" : "LIVE", systemImage: showingVideo ? "photo" : "livephoto")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.55), in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(8)
            }
        }
    }
}

struct ImageViewerView: View {
    let files: [MediaFile]
    var livePhotoVideos: [Int: MediaFile] = [:]
    var onTap: ((Int) -> Void)? = nil
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                LivePhotoView(
                    imageURL: file.fileURL,
                    videoURL: livePhotoVideos[file.orderIndex]?.fileURL
                )
                .tag(index)
                .contentShape(Rectangle())
                .onTapGesture { onTap?(index) }
            }
        }
        .tabViewStyle(.page)
    }
}

struct VideoPlayerView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        PlayerAudioSession.prepare(mode: .moviePlayback)
        let controller = AVPlayerViewController()
        let player = AVPlayer(url: url)
        player.isMuted = false
        player.volume = 1
        controller.player = player
        player.play()
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}

struct AudioPlayerView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        PlayerAudioSession.prepare(mode: .default)
        let controller = AVPlayerViewController()
        let player = AVPlayer(url: url)
        player.isMuted = false
        player.volume = 1
        controller.player = player
        player.play()
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}
