import SwiftUI
import UIKit
import AVKit
import AVFoundation

private enum PlayerAudioSession {
    static func prepare(mode: AVAudioSession.Mode = .moviePlayback) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: mode, options: [.duckOthers])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
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

struct ImageViewerView: View {
    let files: [MediaFile]
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            ForEach(files) { file in
                LocalImageView(url: file.fileURL, animated: file.isAnimated)
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
