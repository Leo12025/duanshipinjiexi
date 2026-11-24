import Foundation
import AVFoundation

enum MediaDownloader {
    @discardableResult
    static func download(
        url: URL,
        to destination: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        try await DownloadManager.shared.download(from: url, to: destination, progress: progress)
        return destination
    }

    static func probeVideo(at url: URL) async -> (duration: Double?, width: Int?, height: Int?, byteSize: Int64?) {
        let asset = AVURLAsset(url: url)
        let duration = try? await asset.load(.duration).seconds

        var width: Int?
        var height: Int?
        if let tracks = try? await asset.load(.tracks),
           let track = tracks.first(where: { $0.mediaType == .video }),
           let size = try? await track.load(.naturalSize) {
            width = Int(size.width)
            height = Int(size.height)
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let byteSize = (attributes?[.size] as? NSNumber)?.int64Value

        return (duration, width, height, byteSize)
    }
}
