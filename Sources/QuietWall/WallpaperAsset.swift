import AppKit
import ImageIO
import UniformTypeIdentifiers

struct WallpaperAsset {
    let url: URL
    let video: VideoAsset?
    let poster: CGImage
    let details: String
    let warning: String?

    var isVideo: Bool { video != nil }

    // This nonisolated async loader decodes images away from the main actor.
    static func load(_ url: URL) async throws -> WallpaperAsset {
        try Task.checkCancellation()
        let type = try url.resourceValues(forKeys: [.contentTypeKey]).contentType
        if type?.conforms(to: .image) == true || CGImageSourceCreateWithURL(url as CFURL, nil) != nil {
            return try loadImage(url)
        }
        let video = try await VideoAsset.load(url)
        return WallpaperAsset(url: url, video: video, poster: video.poster,
                              details: video.details, warning: video.warning)
    }

    static func loadImage(_ url: URL) throws -> WallpaperAsset {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw WallpaperImageError.unreadable }
        // Apply EXIF orientation and cap very large images to bound decoded memory.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(max(width, height), 8192),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else {
            throw WallpaperImageError.unreadable
        }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let rotated = (5...8).contains(orientation)
        let dimensions = rotated ? "\(height) × \(width)" : "\(width) × \(height)"
        let multipleFrames = CGImageSourceGetCount(source) > 1
        return WallpaperAsset(
            url: url, video: nil, poster: image,
            details: "\(dimensions) · 静态图片",
            warning: multipleFrames ? "多帧图片仅显示第一帧，不播放动画。" : nil
        )
    }
}

enum WallpaperImageError: LocalizedError {
    case unreadable

    var errorDescription: String? {
        "无法读取这张图片，请选择有效的 JPEG、PNG、HEIC 或其他系统支持的图片。"
    }
}
