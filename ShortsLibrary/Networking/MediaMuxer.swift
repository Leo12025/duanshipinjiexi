import Foundation
import AVFoundation
import CoreMedia

private final class UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

enum MediaMuxer {
    static func mux(video: URL, audio: URL, to output: URL) async throws {
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: video)
        let audioAsset = AVURLAsset(url: audio)

        guard let sourceVideoTrack = try? await videoAsset.loadTracks(withMediaType: .video).first,
              let sourceAudioTrack = try? await audioAsset.loadTracks(withMediaType: .audio).first else {
            throw AppError.parsingFailed("无法读取音视频轨道")
        }

        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ), let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw AppError.parsingFailed("无法创建合成轨道")
        }

        let videoDuration = try await videoAsset.load(.duration)
        let audioDuration = try await audioAsset.load(.duration)
        let duration = CMTimeMinimum(videoDuration, audioDuration)

        try videoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: sourceVideoTrack,
            at: .zero
        )
        try audioTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: sourceAudioTrack,
            at: .zero
        )

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw AppError.parsingFailed("无法创建导出会话")
        }
        exporter.outputURL = output
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true

        let boxed = UncheckedSendableBox(exporter)
        try await withCheckedThrowingContinuation { continuation in
            boxed.value.exportAsynchronously {
                switch boxed.value.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(throwing: boxed.value.error ?? AppError.parsingFailed("音视频合成失败"))
                case .cancelled:
                    continuation.resume(throwing: AppError.parsingFailed("音视频合成已取消"))
                default:
                    break
                }
            }
        }
    }
}
