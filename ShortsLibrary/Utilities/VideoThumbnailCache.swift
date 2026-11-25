import Foundation
import AVFoundation
import UIKit

enum VideoThumbnailCache {
    private static let memory = NSCache<NSString, UIImage>()
    private static let directory: URL = {
        let url = AppPaths.root.appendingPathComponent("video-thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func image(for videoURL: URL) async -> UIImage? {
        let key = "\(videoURL.path)" as NSString
        if let cached = memory.object(forKey: key) { return cached }

        let attrs = try? FileManager.default.attributesOfItem(atPath: videoURL.path)
        let size = (attrs?[.size] as? NSNumber)?.stringValue ?? "0"
        let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970.description ?? "0"
        let target = directory.appendingPathComponent(
            "\(stableHash("\(videoURL.path)|\(size)|\(mtime)")).jpg"
        )
        if let disk = UIImage(contentsOfFile: target.path) {
            memory.setObject(disk, forKey: key)
            return disk
        }

        let asset = AVAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 600)

        let duration = try? await asset.load(.duration)
        let seconds = min(0.5, max(0, (duration?.seconds ?? 1) * 0.1))
        let times = [CMTime(seconds: seconds, preferredTimescale: 600), .zero]

        for time in times {
            guard let cgImage = try? await generator.image(at: time).image else { continue }
            let image = UIImage(cgImage: cgImage)
            if let data = image.jpegData(compressionQuality: 0.8) {
                try? data.write(to: target, options: .atomic)
            }
            memory.setObject(image, forKey: key)
            return image
        }
        return nil
    }

    static func invalidate(for videoURL: URL) {
        memory.removeObject(forKey: videoURL.path as NSString)
        let attrs = try? FileManager.default.attributesOfItem(atPath: videoURL.path)
        let size = (attrs?[.size] as? NSNumber)?.stringValue ?? "0"
        let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970.description ?? "0"
        let target = directory.appendingPathComponent(
            "\(stableHash("\(videoURL.path)|\(size)|\(mtime)")).jpg"
        )
        try? FileManager.default.removeItem(at: target)
    }

    private static func stableHash(_ string: String) -> String {
        var hash: UInt64 = 5381
        for byte in string.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(format: "%016llx", hash)
    }
}
