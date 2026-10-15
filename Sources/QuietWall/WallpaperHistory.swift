import AppKit
import Combine
import ImageIO
import UniformTypeIdentifiers

struct WallpaperHistoryEntry: Codable, Identifiable {
    let id: UUID
    let fileURL: URL
    let bookmark: Data
    let sourceURL: URL?
    let name: String
    let details: String
    let isVideo: Bool
    let lastUsed: Date
    let thumbnail: Data?

    func resolvedFileURL() throws -> URL {
        var stale = false
        return try URL(resolvingBookmarkData: bookmark, options: .withoutUI,
                       relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    func matches(_ wallpaper: WallpaperAsset) -> Bool {
        if sourceURL != nil || wallpaper.sourceURL != nil { return sourceURL == wallpaper.sourceURL }
        return ((try? resolvedFileURL()) ?? fileURL).standardizedFileURL == wallpaper.url.standardizedFileURL
    }
}

@MainActor
final class WallpaperHistory: ObservableObject {
    static let limit = 50
    static let shared = WallpaperHistory()
    @Published private(set) var entries: [WallpaperHistoryEntry] = []
    private(set) var loadError: String?
    private let fileURL: URL
    private let maximumCount: Int

    init(directory: URL = RemoteWallpaper.cacheDirectory.deletingLastPathComponent(),
         filename: String = "wallpaper-history.json", maximumCount: Int = 50) {
        self.maximumCount = maximumCount
        fileURL = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do { entries = try JSONDecoder().decode([WallpaperHistoryEntry].self, from: Data(contentsOf: fileURL)) }
        catch { loadError = "无法读取壁纸历史：\(error.localizedDescription)" }
    }

    /// Persist before publishing changes, so a failed write leaves existing history intact.
    @discardableResult
    func record(_ wallpaper: WallpaperAsset, bookmark: Data, now: Date = Date()) throws -> [WallpaperHistoryEntry] {
        let previous = entries.first { $0.matches(wallpaper) }
        let entry = WallpaperHistoryEntry(
            id: previous?.id ?? UUID(), fileURL: wallpaper.url, bookmark: bookmark,
            sourceURL: wallpaper.sourceURL, name: wallpaper.displayName, details: wallpaper.details,
            isVideo: wallpaper.isVideo, lastUsed: now, thumbnail: Self.thumbnail(wallpaper.poster)
        )
        let updated = Array(([entry] + entries.filter { !$0.matches(wallpaper) }).prefix(maximumCount))
        let discarded = entries.filter { old in
            !updated.contains { $0.id == old.id && $0.fileURL == old.fileURL }
        }
        try save(updated)
        return discarded
    }

    /// History is supplementary: a storage failure must not prevent applying a valid wallpaper.
    func recordForUse(_ wallpaper: WallpaperAsset, bookmark: Data) -> (discarded: [WallpaperHistoryEntry], warning: String?) {
        do { return (try record(wallpaper, bookmark: bookmark), nil) }
        catch { return ([], "壁纸已应用，但无法保存历史：\(error.localizedDescription)") }
    }

    func remove(_ entry: WallpaperHistoryEntry) throws {
        try save(entries.filter { $0.id != entry.id })
    }

    func add(_ entry: WallpaperHistoryEntry) throws {
        let updated = [entry] + entries.filter {
            if entry.sourceURL != nil { return $0.sourceURL != entry.sourceURL }
            return $0.fileURL.standardizedFileURL != entry.fileURL.standardizedFileURL
        }
        try save(Array(updated.prefix(maximumCount)))
    }

    func containsFile(_ url: URL) -> Bool {
        entries.contains { $0.fileURL.standardizedFileURL == url.standardizedFileURL }
    }

    private func save(_ entries: [WallpaperHistoryEntry]) throws {
        // Do not overwrite an unreadable history file with an empty replacement.
        if let loadError { throw HistoryError.unreadable(loadError) }
        let data = try JSONEncoder().encode(entries)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        self.entries = entries
    }

    private static func thumbnail(_ image: CGImage) -> Data? {
        let scale = min(320.0 / Double(image.width), 180.0 / Double(image.height), 1)
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let thumbnail = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

private enum HistoryError: LocalizedError {
    case unreadable(String)
    var errorDescription: String? {
        if case .unreadable(let message) = self { return message }
        return nil
    }
}
