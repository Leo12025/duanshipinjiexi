import Foundation
import SwiftData

@Model
final class LibraryItem {
    var id: UUID = UUID()
    var source: String
    var sourceId: String
    var kind: String
    var title: String
    var author: String?
    var caption: String?
    var pageURLString: String
    var createdAt: Date
    var updatedAt: Date
    var isFavorite: Bool
    var isTrashed: Bool
    var trashedAt: Date?
    var duration: Double?
    var resolution: String?
    var byteSize: Int64?
    var sourceVideoURLString: String?
    var sourceVideoFallbackURLStrings: [String] = []
    var sourceAudioURLString: String?
    var sourceCoverURLString: String?
    var sourceImageURLStrings: [String]
    var downloadFailed: Bool
    var lastDownloadError: String?
    var needsAudioMux: Bool

    @Relationship(deleteRule: .cascade)
    var files: [MediaFile] = []

    init(
        source: MediaSource,
        sourceId: String,
        kind: MediaKind,
        title: String,
        author: String?,
        caption: String?,
        pageURL: URL
    ) {
        self.source = source.rawValue
        self.sourceId = sourceId
        self.kind = kind.rawValue
        self.title = title
        self.author = author
        self.caption = caption
        self.pageURLString = pageURL.absoluteString
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isFavorite = false
        self.isTrashed = false
        self.trashedAt = nil
        self.sourceVideoURLString = nil
        self.sourceVideoFallbackURLStrings = []
        self.sourceAudioURLString = nil
        self.sourceCoverURLString = nil
        self.sourceImageURLStrings = []
        self.downloadFailed = false
        self.lastDownloadError = nil
        self.needsAudioMux = false
    }

    var sourceEnum: MediaSource {
        MediaSource(rawValue: source) ?? .douyin
    }

    var kindEnum: MediaKind {
        MediaKind(rawValue: kind) ?? .video
    }

    var pageURL: URL? {
        URL(string: pageURLString)
    }

    var coverFile: MediaFile? {
        files.first { $0.role == FileRole.cover.rawValue }
            ?? files.first { $0.role == FileRole.image.rawValue }
    }

    var videoFile: MediaFile? {
        files.first { $0.role == FileRole.video.rawValue }
    }

    var audioFile: MediaFile? {
        files.first { $0.role == FileRole.audio.rawValue }
    }

    var imageFiles: [MediaFile] {
        files
            .filter { [FileRole.image.rawValue, FileRole.imageSegment.rawValue].contains($0.role) }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    var imageOriginalFiles: [MediaFile] {
        files.filter { $0.role == FileRole.imageOriginal.rawValue }
    }

    var animatedImageFiles: [MediaFile] {
        imageFiles.filter { $0.isAnimated }
    }

    var needsRetry: Bool {
        if downloadFailed { return true }
        if kindEnum == .video, sourceVideoURLString != nil, videoFile?.existsOnDisk != true { return true }
        if kindEnum == .video, needsAudioMux { return true }
        if kindEnum == .audio, sourceAudioURLString != nil, audioFile?.existsOnDisk != true { return true }
        if [.image, .imageText, .dynamic].contains(kindEnum),
           !sourceImageURLStrings.isEmpty,
           !imageFiles.contains(where: { $0.existsOnDisk }) { return true }
        return false
    }
}

extension LibraryItem: Hashable {
    static func == (lhs: LibraryItem, rhs: LibraryItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
