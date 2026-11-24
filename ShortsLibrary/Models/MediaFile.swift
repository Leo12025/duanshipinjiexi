import Foundation
import SwiftData

@Model
final class MediaFile {
    var relativePath: String
    var role: String
    var mimeType: String
    var width: Int?
    var height: Int?
    var orderIndex: Int
    var isAnimated: Bool = false
    var isLongImageSplit: Bool = false
    var segmentIndex: Int? = nil
    var segmentCount: Int? = nil

    init(
        relativePath: String,
        role: FileRole,
        mimeType: String,
        width: Int? = nil,
        height: Int? = nil,
        orderIndex: Int = 0,
        isAnimated: Bool = false,
        isLongImageSplit: Bool = false,
        segmentIndex: Int? = nil,
        segmentCount: Int? = nil
    ) {
        self.relativePath = relativePath
        self.role = role.rawValue
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.orderIndex = orderIndex
        self.isAnimated = isAnimated
        self.isLongImageSplit = isLongImageSplit
        self.segmentIndex = segmentIndex
        self.segmentCount = segmentCount
    }

    var fileURL: URL {
        AppPaths.root.appendingPathComponent(relativePath)
    }

    var existsOnDisk: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }
}

extension MediaFile: Identifiable {
    var id: String { relativePath }
}
