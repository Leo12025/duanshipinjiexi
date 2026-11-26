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
                Label("LIVE", systemImage: "livephoto")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard videoURL != nil else { return }
            withAnimation(.easeInOut(duration: 0.15)) { showingVideo.toggle() }
        }
    }
}

struct ImageViewerView: View {
    let files: [MediaFile]
    var livePhotoVideos: [Int: MediaFile] = [:]
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            ForEach(files) { file in
                LivePhotoView(
                    imageURL: file.fileURL,
                    videoURL: livePhotoVideos[file.orderIndex]?.fileURL
                )
                .tag(file.orderIndex)
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
