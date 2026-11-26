import Foundation
import Photos

enum PhotoSaver {
    static func saveVideo(_ url: URL) async throws {
        guard await requestPermission() else {
            throw AppError.fileSystem("没有相册写入权限")
        }
        try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .video, fileURL: url, options: nil)
            } completionHandler: { success, error in
                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: error ?? AppError.fileSystem("视频保存失败"))
                }
            }
        }
    }

    static func saveImages(_ urls: [URL]) async throws {
        guard await requestPermission() else {
            throw AppError.fileSystem("没有相册写入权限")
        }
        try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                for url in urls {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, fileURL: url, options: nil)
                }
            } completionHandler: { success, error in
                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: error ?? AppError.fileSystem("图片保存失败"))
                }
            }
        }
    }

    static func saveLivePhotos(_ pairs: [(image: URL, video: URL)]) async throws {
        guard !pairs.isEmpty else { return }
        guard await requestPermission() else {
            throw AppError.fileSystem("没有相册写入权限")
        }
        try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                for pair in pairs {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, fileURL: pair.image, options: PHAssetResourceCreationOptions())
                    request.addResource(with: .video, fileURL: pair.video, options: PHAssetResourceCreationOptions())
                }
            } completionHandler: { success, error in
                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: error ?? AppError.fileSystem("动态图片保存失败"))
                }
            }
        }
    }

    private static func requestPermission() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                    continuation.resume(returning: newStatus == .authorized || newStatus == .limited)
                }
            }
        default:
            return false
        }
    }
}
