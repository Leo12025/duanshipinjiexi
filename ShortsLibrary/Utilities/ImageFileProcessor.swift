import Foundation
import UIKit
import ImageIO
import UniformTypeIdentifiers

enum ImageFileProcessor {
    struct ImageInfo {
        let ext: String
        let mimeType: String
        let isAnimated: Bool
        let width: Int?
        let height: Int?
    }

    static func inspect(at url: URL) -> ImageInfo {
        guard let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return ImageInfo(ext: "jpg", mimeType: "image/jpeg", isAnimated: false, width: nil, height: nil)
        }

        let type = (CGImageSourceGetType(source) as String?)?.lowercased() ?? ""
        let (ext, mime) = format(from: type, fallback: url.pathExtension)
        let frameCount = CGImageSourceGetCount(source)
        let size = firstFrameSize(source)
        return ImageInfo(
            ext: ext,
            mimeType: mime,
            isAnimated: frameCount > 1,
            width: size?.width,
            height: size?.height
        )
    }

    static func renameToDetectedFormat(at original: URL, ext: String) -> URL {
        let ext = ext.lowercased()
        let current = original.pathExtension.lowercased()
        guard !ext.isEmpty, ext != current else { return original }
        let renamed = original.deletingPathExtension().appendingPathExtension(ext)
        if FileManager.default.fileExists(atPath: renamed.path) {
            try? FileManager.default.removeItem(at: renamed)
        }
        do {
            try FileManager.default.moveItem(at: original, to: renamed)
            return renamed
        } catch {
            return original
        }
    }

    static func isLongImage(width: Int?, height: Int?) -> Bool {
        guard let width, let height, width > 0 else { return false }
        return height >= 2000 && Double(height) / Double(width) >= 2.0
    }

    static func splitLongImage(
        at url: URL,
        relativeBase: String,
        segmentHeight: Int = 1600
    ) -> [(relativePath: String, width: Int, height: Int)] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }

        let width = image.width
        let height = image.height
        guard width > 0, height > segmentHeight else { return [] }

        let directory = url.deletingLastPathComponent()
        let baseName = (url.deletingPathExtension().lastPathComponent as NSString).deletingPathExtension
        var results: [(String, Int, Int)] = []
        var y = 0
        var index = 1

        while y < height {
            let chunk = min(segmentHeight, height - y)
            let rect = CGRect(x: 0, y: y, width: width, height: chunk)
            guard let cropped = image.cropping(to: rect) else { break }
            let rendered = UIGraphicsImageRenderer(size: CGSize(width: width, height: chunk)).image { context in
                context.cgContext.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: chunk))
            }
            guard let data = rendered.jpegData(compressionQuality: 0.92) else { break }
            let filename = String(format: "%@_seg%02d.jpg", baseName, index)
            let destination = directory.appendingPathComponent(filename)
            do {
                try data.write(to: destination, options: .atomic)
                let relative = (relativeBase as NSString).deletingLastPathComponent
                    .appending("/\(filename)")
                results.append((relative, width, chunk))
            } catch {
                break
            }
            y += chunk
            index += 1
        }
        return results
    }

    static func convertibleToJPEG(ext: String) -> Bool {
        ["webp", "apng", "tiff", "tif", "bmp"].contains(ext.lowercased())
    }

    static func convertToJPEG(at url: URL) -> URL? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ShortsLibraryPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        guard let data = JPEGData(from: image),
              (try? data.write(to: destination, options: .atomic)) != nil else { return nil }
        return destination
    }

    private static func JPEGData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality as CFString: 0.92
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    static func animatedImage(at url: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(contentsOfFile: url.path)
        }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return UIImage(contentsOfFile: url.path) }

        var images: [UIImage] = []
        var duration: TimeInterval = 0
        for index in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            images.append(UIImage(cgImage: cgImage))
            duration += frameDuration(source: source, index: index)
        }
        guard !images.isEmpty else { return UIImage(contentsOfFile: url.path) }
        return UIImage.animatedImage(with: images, duration: max(duration, 0.1))
    }

    private static func frameDuration(source: CGImageSource, index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
            return 0.1
        }
        if let webp = properties[kCGImagePropertyWebPDictionary] as? [CFString: Any],
           let value = webp[kCGImagePropertyWebPDelayTime] as? NSNumber {
            return max(value.doubleValue, 0.01)
        }
        if let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any],
           let value = gif[kCGImagePropertyGIFDelayTime] as? NSNumber {
            return max(value.doubleValue, 0.01)
        }
        if let png = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any],
           let value = png[kCGImagePropertyAPNGDelayTime] as? NSNumber {
            return max(value.doubleValue, 0.01)
        }
        return 0.1
    }

    private static func firstFrameSize(_ source: CGImageSource) -> (width: Int, height: Int)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return nil }
        return (width.intValue, height.intValue)
    }

    private static func format(from type: String, fallback: String) -> (String, String) {
        if type.contains("gif") { return ("gif", "image/gif") }
        if type.contains("webp") { return ("webp", "image/webp") }
        if type.contains("png") { return ("png", "image/png") }
        if type.contains("heic") { return ("heic", "image/heic") }
        if type.contains("jpeg") || type.contains("jpg") { return ("jpg", "image/jpeg") }

        switch fallback.lowercased() {
        case "gif": return ("gif", "image/gif")
        case "webp": return ("webp", "image/webp")
        case "png", "apng": return ("png", "image/png")
        case "heic": return ("heic", "image/heic")
        default: return ("jpg", "image/jpeg")
        }
    }
}
