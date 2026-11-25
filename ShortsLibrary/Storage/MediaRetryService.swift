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
                onFinish: { location in
                    finalizeImage(
                        at: location,
                        role: .cover,
                        orderIndex: 0,
                        item: item,
                        context: context
                    )
                    try? context.save()
                },
                onError: markFailure
            )
        }

        if item.kindEnum == .video,
           item.needsAudioMux,
           let existingVideo = item.videoFile,
           existingVideo.existsOnDisk {
            Task {
                await Self.muxExistingVideo(
                    item: item,
                    video: existingVideo.fileURL,
                    context: context,
                    markFailure: markFailure
                )
            }
        }

        if item.kindEnum == .video,
           item.videoFile?.existsOnDisk != true {
            let candidates = Self.videoCandidates(for: item)
            if !candidates.isEmpty {
                let relative = AppPaths.relativePath(source: item.source, sourceId: item.sourceId, filename: "video.mp4")
                let destination = AppPaths.root.appendingPathComponent(relative)
                Self.enqueueVideo(
                    candidates: candidates,
                    item: item,
                    context: context,
                    relative: relative,
                    destination: destination,
                    title: item.title,
                    markFailure: markFailure
                )
            }
        }

        if item.kindEnum == .audio,
           let audio = item.sourceAudioURLString,
           let url = URL(string: audio),
           item.audioFile?.existsOnDisk != true {
            let ext = url.pathExtension.lowercased()
            let filename = "audio.\(ext.isEmpty ? "m4a" : ext)"
            let relative = AppPaths.relativePath(source: item.source, sourceId: item.sourceId, filename: filename)
            let destination = AppPaths.root.appendingPathComponent(relative)
            DownloadQueue.shared.enqueue(
                url: url,
                destination: destination,
                label: "音频 · \(item.title)",
                onFinish: { location in
                    if item.audioFile == nil {
                        let info = await MediaDownloader.probeVideo(at: location)
                        LibraryRepository.shared.addFile(
                            to: item,
                            relativePath: relative,
                            role: .audio,
                            mimeType: audioMimeType(for: ext),
                            in: context
                        )
                        item.duration = info.duration
                        item.byteSize = info.byteSize
                    }
                    try? context.save()
                },
                onError: markFailure
            )
        }

        if [.image, .imageText, .dynamic].contains(item.kindEnum) {
            for (index, string) in item.sourceImageURLStrings.enumerated() {
                guard let url = URL(string: string) else { continue }
                let ext = url.pathExtension.lowercased()
                let filename = String(format: "images/%02d.%@", index + 1, ext.isEmpty ? "jpg" : ext)
                let relative = AppPaths.relativePath(source: item.source, sourceId: item.sourceId, filename: filename)
                let destination = AppPaths.root.appendingPathComponent(relative)
                let imageRoles = [FileRole.image.rawValue, FileRole.imageOriginal.rawValue, FileRole.imageSegment.rawValue]
                if item.files.contains(where: {
                    imageRoles.contains($0.role) && $0.orderIndex / 100 == index && $0.existsOnDisk
                }) { continue }

                DownloadQueue.shared.enqueue(
                    url: url,
                    destination: destination,
                    label: "图片 \(index + 1) · \(item.title)",
                    onFinish: { location in
                        finalizeImage(
                            at: location,
                            role: .image,
                            orderIndex: index,
                            item: item,
                            context: context
                        )
                        try? context.save()
                    },
                    onError: markFailure
                )
            }
        }

        try? context.save()
    }

    private static func videoCandidates(for item: LibraryItem) -> [URL] {
        let strings = ([item.sourceVideoURLString].compactMap { $0 } + item.sourceVideoFallbackURLStrings)
        return URL.dedupeMedia(strings.compactMap(URL.init(string:)))
    }

    private static func enqueueVideo(
        candidates: [URL],
        index: Int = 0,
        item: LibraryItem,
        context: ModelContext,
        relative: String,
        destination: URL,
        title: String,
        markFailure: @escaping @MainActor (String) -> Void
    ) {
        guard candidates.indices.contains(index) else {
            markFailure("视频：所有候选源下载失败")
            return
        }

        let url = candidates[index]
        DownloadQueue.shared.enqueue(
            url: url,
            destination: destination,
            label: index == 0 ? "视频 · \(title)" : "视频源 \(index + 1) · \(title)",
            onFinish: { location in
                do {
                    try await Self.muxIfNeeded(item: item, video: location, destination: destination)
                } catch {
                    markFailure("音轨合成：\(error.localizedDescription)")
                }
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
                try? context.save()
            },
            onError: { message in
                if index + 1 < candidates.count {
                    Self.enqueueVideo(
                        candidates: candidates,
                        index: index + 1,
                        item: item,
                        context: context,
                        relative: relative,
                        destination: destination,
                        title: title,
                        markFailure: markFailure
                    )
                } else {
                    markFailure("视频：\(message)")
                }
            }
        )
    }

    static func retry(item: LibraryItem, in context: ModelContext) async {
        var failures: [String] = []

        await retryCover(item: item, in: context, failures: &failures)

        switch item.kindEnum {
        case .video:
            await retryVideo(item: item, in: context, failures: &failures)
        case .audio:
            await retryAudio(item: item, in: context, failures: &failures)
        case .image, .imageText, .dynamic:
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
            finalizeImage(
                at: destination,
                role: .cover,
                orderIndex: 0,
                item: item,
                context: context
            )
        } catch {
            failures.append("封面：\(error.localizedDescription)")
        }
    }

    private static func retryVideo(
        item: LibraryItem,
        in context: ModelContext,
        failures: inout [String]
    ) async {
        let candidates = videoCandidates(for: item)
        guard !candidates.isEmpty, item.videoFile?.existsOnDisk != true else { return }

        let relative = AppPaths.relativePath(
            source: item.source,
            sourceId: item.sourceId,
            filename: "video.mp4"
        )
        let destination = AppPaths.root.appendingPathComponent(relative)

        for (index, url) in candidates.enumerated() {
            do {
                try await MediaDownloader.download(url: url, to: destination)
                try await muxIfNeeded(item: item, video: destination, destination: destination)
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
                return
            } catch {
                failures.append("视频源 \(index + 1)：\(error.localizedDescription)")
            }
        }
    }

    private static func retryAudio(
        item: LibraryItem,
        in context: ModelContext,
        failures: inout [String]
    ) async {
        guard let string = item.sourceAudioURLString,
              let url = URL(string: string),
              item.audioFile?.existsOnDisk != true else { return }

        let ext = url.pathExtension.lowercased()
        let relative = AppPaths.relativePath(
            source: item.source,
            sourceId: item.sourceId,
            filename: "audio.\(ext.isEmpty ? "m4a" : ext)"
        )
        let destination = AppPaths.root.appendingPathComponent(relative)

        do {
            try await MediaDownloader.download(url: url, to: destination)
            if item.audioFile == nil {
                let info = await MediaDownloader.probeVideo(at: destination)
                LibraryRepository.shared.addFile(
                    to: item,
                    relativePath: relative,
                    role: .audio,
                    mimeType: audioMimeType(for: ext),
                    in: context
                )
                item.duration = info.duration
                item.byteSize = info.byteSize
            }
        } catch {
            failures.append("音频：\(error.localizedDescription)")
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

            let imageRoles = [FileRole.image.rawValue, FileRole.imageOriginal.rawValue, FileRole.imageSegment.rawValue]
            if item.files.contains(where: {
                imageRoles.contains($0.role) && $0.orderIndex / 100 == index && $0.existsOnDisk
            }) { continue }

            do {
                try await MediaDownloader.download(url: url, to: destination)
                finalizeImage(
                    at: destination,
                    role: .image,
                    orderIndex: index,
                    item: item,
                    context: context
                )
            } catch {
                failures.append("图片 \(index + 1)：\(error.localizedDescription)")
            }
        }
    }

    private static func muxExistingVideo(
        item: LibraryItem,
        video: URL,
        context: ModelContext,
        markFailure: @MainActor (String) -> Void
    ) async {
        do {
            try await muxIfNeeded(item: item, video: video, destination: video)
            try? context.save()
        } catch {
            markFailure("音轨合成：\(error.localizedDescription)")
        }
    }

    private static func muxIfNeeded(item: LibraryItem, video: URL, destination: URL) async throws {
        guard item.needsAudioMux,
              let audioString = item.sourceAudioURLString,
              let audioURL = URL(string: audioString) else { return }

        if await MediaDownloader.hasAudioTrack(at: video) {
            item.needsAudioMux = false
            return
        }

        let directory = destination.deletingLastPathComponent()
        let temporaryAudio = directory.appendingPathComponent("audio-source.m4a")
        let muxed = directory.appendingPathComponent("video-muxed.mp4")
        defer {
            try? FileManager.default.removeItem(at: temporaryAudio)
            try? FileManager.default.removeItem(at: muxed)
        }

        try await MediaDownloader.download(url: audioURL, to: temporaryAudio)
        try await MediaMuxer.mux(video: video, audio: temporaryAudio, to: muxed)

        if video.path != destination.path {
            try? FileManager.default.removeItem(at: video)
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: muxed, to: destination)
        item.needsAudioMux = false
    }

    private static func audioMimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "aac": return "audio/aac"
        case "flac": return "audio/flac"
        default: return "audio/mp4"
        }
    }

    private static func finalizeImage(
        at location: URL,
        role: FileRole,
        orderIndex: Int,
        item: LibraryItem,
        context: ModelContext
    ) {
        let info = ImageFileProcessor.inspect(at: location)
        let finalURL = ImageFileProcessor.renameToDetectedFormat(at: location, ext: info.ext)
        let relative = relativePath(for: finalURL)

        guard !item.files.contains(where: { $0.relativePath == relative }) else { return }

        if role == .cover {
            LibraryRepository.shared.addFile(
                to: item,
                relativePath: relative,
                role: .cover,
                mimeType: info.mimeType,
                width: info.width,
                height: info.height,
                orderIndex: orderIndex,
                isAnimated: info.isAnimated,
                in: context
            )
            return
        }

        if !info.isAnimated,
           ImageFileProcessor.isLongImage(width: info.width, height: info.height) {
            let segments = ImageFileProcessor.splitLongImage(at: finalURL, relativeBase: relative)
            if !segments.isEmpty {
                LibraryRepository.shared.addFile(
                    to: item,
                    relativePath: relative,
                    role: .imageOriginal,
                    mimeType: info.mimeType,
                    width: info.width,
                    height: info.height,
                    orderIndex: orderIndex,
                    in: context
                )
                for (segmentIndex, segment) in segments.enumerated() {
                    LibraryRepository.shared.addFile(
                        to: item,
                        relativePath: segment.relativePath,
                        role: .imageSegment,
                        mimeType: "image/jpeg",
                        width: segment.width,
                        height: segment.height,
                        orderIndex: orderIndex * 100 + segmentIndex,
                        isLongImageSplit: true,
                        segmentIndex: segmentIndex + 1,
                        segmentCount: segments.count,
                        in: context
                    )
                }
                return
            }
        }

        LibraryRepository.shared.addFile(
            to: item,
            relativePath: relative,
            role: .image,
            mimeType: info.mimeType,
            width: info.width,
            height: info.height,
            orderIndex: orderIndex,
            isAnimated: info.isAnimated,
            in: context
        )
    }

    private static func relativePath(for url: URL) -> String {
        let root = AppPaths.root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(root) else { return url.lastPathComponent }
        return String(path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
