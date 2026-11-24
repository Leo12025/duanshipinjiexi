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

    init(
        relativePath: String,
        role: FileRole,
        mimeType: String,
        width: Int? = nil,
        height: Int? = nil,
        orderIndex: Int = 0
    ) {
        self.relativePath = relativePath
        self.role = role.rawValue
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.orderIndex = orderIndex
    }

    var fileURL: URL {
        AppPaths.root.appendingPathComponent(relativePath)
    }

    var existsOnDisk: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }
}
