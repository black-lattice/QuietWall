import Foundation
import ImageIO
import UniformTypeIdentifiers

enum RemoteWallpaper {
    static var cacheDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QuietWall/Downloads", isDirectory: true)
    }

    static func parseURL(_ text: String) throws -> URL {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = url.host, !host.isEmpty else { throw RemoteWallpaperError.invalidURL }
        return url
    }

    static func load(_ url: URL, cachedURL: URL? = nil,
                     directory: URL = cacheDirectory) async throws -> WallpaperAsset {
        _ = try parseURL(url.absoluteString)
        if let cachedURL, let cached = try? await WallpaperAsset.load(cachedURL) {
            try Task.checkCancellation()
            return cached.withSourceURL(url)
        }
        try Task.checkCancellation()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 600
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let temporaryURL: URL
        let response: URLResponse
        do { (temporaryURL, response) = try await session.download(from: url) }
        catch {
            try Task.checkCancellation()
            throw error
        }
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        guard let response = response as? HTTPURLResponse else { throw RemoteWallpaperError.invalidResponse }
        guard (200...299).contains(response.statusCode) else {
            throw RemoteWallpaperError.httpStatus(response.statusCode)
        }
        guard let finalURL = response.url else { throw RemoteWallpaperError.invalidResponse }
        _ = try parseURL(finalURL.absoluteString)
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // AVFoundation needs a recognized suffix on macOS 13; derive it from the bytes, not HTTP hints.
        let localURL = directory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(try fileExtension(temporaryURL))
        try FileManager.default.moveItem(at: temporaryURL, to: localURL)
        do {
            let loaded = try await WallpaperAsset.load(localURL)
            try Task.checkCancellation()
            return loaded.withSourceURL(url)
        } catch {
            try? FileManager.default.removeItem(at: localURL)
            if error is CancellationError { throw error }
            throw RemoteWallpaperError.unsupportedContent
        }
    }

    private static func fileExtension(_ url: URL) throws -> String {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let identifier = CGImageSourceGetType(source), let type = UTType(identifier as String),
           type.conforms(to: .image), let suffix = type.preferredFilenameExtension { return suffix }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let prefix = try handle.read(upToCount: 512) ?? Data()
        if String(data: prefix, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            .hasPrefix("#EXTM3U") == true { throw RemoteWallpaperError.unsupportedContent }
        let box = String(bytes: prefix.dropFirst(4).prefix(4), encoding: .ascii)
        if box == "ftyp" {
            return String(bytes: prefix.dropFirst(8).prefix(4), encoding: .ascii) == "qt  " ? "mov" : "mp4"
        }
        if ["moov", "mdat", "wide", "free", "skip"].contains(box ?? "") { return "mov" }
        if prefix.starts(with: Data("RIFF".utf8)), prefix.dropFirst(8).starts(with: Data("AVI ".utf8)) { return "avi" }
        // The decoder remains the final validator, including when the container is unfamiliar.
        return "mp4"
    }

    static func removeCachedFile(_ url: URL, directory: URL = cacheDirectory) {
        // Only delete files owned by our download store, never imported local originals.
        guard url.isFileURL,
              url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
              UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

enum RemoteWallpaperError: LocalizedError {
    case invalidURL, invalidResponse, unsupportedContent
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "请输入完整的 HTTP 或 HTTPS 图片／视频直链。"
        case .invalidResponse: return "服务器没有返回有效的下载响应。"
        case .httpStatus(let code): return "下载失败（HTTP \(code)），请检查地址和访问权限。"
        case .unsupportedContent: return "这个地址没有返回可用的图片或视频。请使用媒体文件直链，网页和直播播放列表暂不支持。"
        }
    }
}
