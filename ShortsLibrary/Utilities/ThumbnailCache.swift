import Foundation
import UIKit
import ImageIO

enum ThumbnailCache {
    private static let memory = NSCache<NSString, UIImage>()
    private static let directory: URL = {
        let url = AppPaths.root.appendingPathComponent("thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func image(for original: URL, maxPixel: Int = 400) -> UIImage? {
        let key = "\(original.path)|\(maxPixel)" as NSString
        if let cached = memory.object(forKey: key) { return cached }

        let attrs = try? FileManager.default.attributesOfItem(atPath: original.path)
        let size = (attrs?[.size] as? NSNumber)?.stringValue ?? "0"
        let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970.description ?? "0"
        let target = directory.appendingPathComponent(
            "\(stableHash("\(original.path)|\(maxPixel)|\(size)|\(mtime)")).jpg"
        )
        if let disk = UIImage(contentsOfFile: target.path) {
            memory.setObject(disk, forKey: key)
            return disk
        }

        guard let source = CGImageSourceCreateWithURL(original as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                  source,
                  0,
                  [
                    kCGImageSourceThumbnailMaxPixelSize as String: maxPixel,
                    kCGImageSourceCreateThumbnailFromImageAlways as String: true,
                    kCGImageSourceShouldCacheImmediately as String: true
                  ] as CFDictionary
              ) else {
            let full = UIImage(contentsOfFile: original.path)
            if let full { memory.setObject(full, forKey: key) }
            return full
        }

        let image = UIImage(cgImage: thumbnail)
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: target, options: .atomic)
        }
        memory.setObject(image, forKey: key)
        return image
    }

    static func invalidate(for original: URL) {
        let key = "\(original.path)|400" as NSString
        memory.removeObject(forKey: key)
        let attrs = try? FileManager.default.attributesOfItem(atPath: original.path)
        let size = (attrs?[.size] as? NSNumber)?.stringValue ?? "0"
        let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970.description ?? "0"
        let target = directory.appendingPathComponent(
            "\(stableHash("\(original.path)|400|\(size)|\(mtime)")).jpg"
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
