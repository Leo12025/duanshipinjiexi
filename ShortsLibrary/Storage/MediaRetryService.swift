import Foundation
import SwiftData
import UIKit

@MainActor
enum MediaRetryService {
    static func enqueueRetry(item: LibraryItem, in context: ModelContext) {
        item.downloadFailed = false
        item.lastDownloadError = nil

        let markFailure: @MainActor (String) -> Void = { message in
            item.downloadFailed = true
            item.lastDownloadError = [item.lastDownloadError, message]
                .compactMap { $0 }
                .joined(separator: "\n")
            try? context.save()
        }

        if let cover = item.sourceCoverURLString,
           let url = URL(string: cover),
           !item.files.contains(where: { $0.role == FileRole.cover.rawValue && $0.existsOnDisk }) {
            let relative = AppPaths.relativePath(source: item.source, sourceId: item.sourceId, filename: "cover.jpg")
            let destination = AppPaths.root.appendingPathComponent(relative)
            DownloadQueue.shared.enqueue(
                url: url,
                destination: destination,
                label: "封面 · \(item.title)",
                onFinish: { _ in
                    if !item.files.contains(where: { $0.relativePath == relative }) {
                        LibraryRepository.shared.addFile(
                            to: item,
                            relativePath: relative,
                            role: .cover,
                            mimeType: "image/jpeg",
                            in: context
                        )
                    }
                    try? context.save()
                },
                onError: markFailure
            )
        }

        if item.kindEnum == .video,
           let video = item.sourceVideoURLString,
           let url = URL(string: video),
           item.videoFile?.existsOnDisk != true {
            let relative = AppPaths.relativePath(source: item.source, sourceId: item.sourceId, filename: "video.mp4")
            let destination = AppPaths.root.appendingPathComponent(relative)
            DownloadQueue.shared.enqueue(
                url: url,
                destination: destination,
                label: "视频 · \(item.title)",
                onFinish: { location in
                    let info = await MediaDownloader.probeVideo(at: location)
                    if item.videoFile == nil {
                        LibraryRepository.shared.addFile(
                            to: item,
                            relativePath: relative,
                            role: .video,
                            mimeType: "video/mp4",
                            width: info.width,
                            height: info.height,
                            in: context
                        )
                    }
                    item.duration = info.duration
                    if let width = info.width {
                        item.resolution = "\(width)x\(info.height ?? 0)"
                    }
                    item.byteSize = info.byteSize
                    try? context.save()
                },
                onError: markFailure
            )
        }

        if item.kindEnum == .imageText {
            for (index, string) in item.sourceImageURLStrings.enumerated() {
                guard let url = URL(string: string) else { continue }
                let ext = url.pathExtension.lowercased()
                let filename = String(format: "images/%02d.%@", index + 1, ext.isEmpty ? "jpg" : ext)
                let relative = AppPaths.relativePath(source: item.source, sourceId: item.sourceId, filename: filename)
                let destination = AppPaths.root.appendingPathComponent(relative)
                if item.files.contains(where: { $0.relativePath == relative && $0.existsOnDisk }) { continue }

                DownloadQueue.shared.enqueue(
                    url: url,
                    destination: destination,
                    label: "图片 \(index + 1) · \(item.title)",
                    onFinish: { location in
                        if !item.files.contains(where: { $0.relativePath == relative }) {
                            let size = imageSize(at: location)
                            LibraryRepository.shared.addFile(
                                to: item,
                                relativePath: relative,
                                role: .image,
                                mimeType: mimeType(for: ext),
                                width: size.width,
                                height: size.height,
                                orderIndex: index,
                                in: context
                            )
                        }
                        try? context.save()
                    },
                    onError: markFailure
                )
            }
        }

        try? context.save()
    }

    static func retry(item: LibraryItem, in context: ModelContext) async {
        var failures: [String] = []

        await retryCover(item: item, in: context, failures: &failures)

        if item.kindEnum == .video {
            await retryVideo(item: item, in: context, failures: &failures)
        } else {
            await retryImages(item: item, in: context, failures: &failures)
        }

        if failures.isEmpty {
            item.downloadFailed = false
            item.lastDownloadError = nil
        } else {
            item.downloadFailed = true
            item.lastDownloadError = failures.joined(separator: "\n")
        }
        item.updatedAt = Date()
        try? context.save()
    }

    private static func retryCover(
        item: LibraryItem,
        in context: ModelContext,
        failures: inout [String]
    ) async {
        guard let string = item.sourceCoverURLString,
              let url = URL(string: string),
              !item.files.contains(where: { $0.role == FileRole.cover.rawValue && $0.existsOnDisk }) else { return }

        let relative = AppPaths.relativePath(
            source: item.source,
            sourceId: item.sourceId,
            filename: "cover.jpg"
        )
        let destination = AppPaths.root.appendingPathComponent(relative)

        do {
            try await MediaDownloader.download(url: url, to: destination)
            if !item.files.contains(where: { $0.relativePath == relative }) {
                LibraryRepository.shared.addFile(
                    to: item,
                    relativePath: relative,
                    role: .cover,
                    mimeType: "image/jpeg",
                    in: context
                )
            }
        } catch {
            failures.append("封面：\(error.localizedDescription)")
        }
    }

    private static func retryVideo(
        item: LibraryItem,
        in context: ModelContext,
        failures: inout [String]
    ) async {
        guard let string = item.sourceVideoURLString,
              let url = URL(string: string),
              item.videoFile?.existsOnDisk != true else { return }

        let relative = AppPaths.relativePath(
            source: item.source,
            sourceId: item.sourceId,
            filename: "video.mp4"
        )
        let destination = AppPaths.root.appendingPathComponent(relative)

        do {
            try await MediaDownloader.download(url: url, to: destination)
            let info = await MediaDownloader.probeVideo(at: destination)
            if item.videoFile == nil {
                LibraryRepository.shared.addFile(
                    to: item,
                    relativePath: relative,
                    role: .video,
                    mimeType: "video/mp4",
                    width: info.width,
                    height: info.height,
                    in: context
                )
            }
            item.duration = info.duration
            if let width = info.width {
                item.resolution = "\(width)x\(info.height ?? 0)"
            }
            item.byteSize = info.byteSize
        } catch {
            failures.append("视频：\(error.localizedDescription)")
        }
    }

    private static func retryImages(
        item: LibraryItem,
        in context: ModelContext,
        failures: inout [String]
    ) async {
        for (index, string) in item.sourceImageURLStrings.enumerated() {
            guard let url = URL(string: string) else { continue }
            let ext = url.pathExtension.lowercased()
            let filename = String(format: "images/%02d.%@", index + 1, ext.isEmpty ? "jpg" : ext)
            let relative = AppPaths.relativePath(
                source: item.source,
                sourceId: item.sourceId,
                filename: filename
            )
            let destination = AppPaths.root.appendingPathComponent(relative)

            if let existing = item.files.first(where: { $0.relativePath == relative }),
               existing.existsOnDisk { continue }

            do {
                try await MediaDownloader.download(url: url, to: destination)
                if !item.files.contains(where: { $0.relativePath == relative }) {
                    let size = imageSize(at: destination)
                    LibraryRepository.shared.addFile(
                        to: item,
                        relativePath: relative,
                        role: .image,
                        mimeType: mimeType(for: ext),
                        width: size.width,
                        height: size.height,
                        orderIndex: index,
                        in: context
                    )
                }
            } catch {
                failures.append("图片 \(index + 1)：\(error.localizedDescription)")
            }
        }
    }

    private static func imageSize(at url: URL) -> (width: Int?, height: Int?) {
        guard let image = UIImage(contentsOfFile: url.path) else { return (nil, nil) }
        return (Int(image.size.width), Int(image.size.height))
    }

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        default: return "image/jpeg"
        }
    }
}
