import Foundation
import AVFoundation
import UIKit

enum VideoFrameExtractor {
    static func frames(from url: URL, count: Int, maxSize: Int) async -> [Data] {
        guard count > 0 else { return [] }
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration).seconds, duration > 0 else { return [] }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSize, height: maxSize)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.4, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.4, preferredTimescale: 600)

        var results: [Data] = []
        for index in 0..<count {
            let fraction = count == 1 ? 0.5 : Double(index) / Double(count - 1)
            let seconds = max(0.1, duration * min(max(fraction, 0), 0.98))
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            guard let cgImage = try? await generator.image(at: time).image else { continue }
            let image = UIImage(cgImage: cgImage)
            if let data = image.jpegData(compressionQuality: 0.72) {
                results.append(data)
            }
        }
        return results
    }
}
