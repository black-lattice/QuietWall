import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import QuietWall

final class WallpaperHistoryTests: XCTestCase {
    private var directory: URL!
    private var storeDirectory: URL { directory.appendingPathComponent("store") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    @MainActor
    func testHistoryAndThumbnailSurviveRestart() async throws {
        let wallpaper = try makeAsset("landscape")
        let history = WallpaperHistory(directory: storeDirectory)
        try history.record(wallpaper, bookmark: bookmark(wallpaper))
        let restored = WallpaperHistory(directory: storeDirectory)
        let entry = try XCTUnwrap(restored.entries.first)
        XCTAssertEqual(entry.id, history.entries.first?.id)
        XCTAssertEqual(entry.name, wallpaper.displayName)
        XCTAssertEqual(try entry.resolvedFileURL().standardizedFileURL, wallpaper.url.standardizedFileURL)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(try XCTUnwrap(entry.thumbnail) as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertLessThanOrEqual(image.width, 320)
        XCTAssertLessThanOrEqual(image.height, 180)
    }

    @MainActor
    func testReuseMovesEntryToFrontWithoutDuplicatingIt() async throws {
        let history = WallpaperHistory(directory: storeDirectory)
        let first = try makeAsset("first")
        let second = try makeAsset("second")
        try history.record(first, bookmark: bookmark(first))
        let originalID = history.entries.first?.id
        try history.record(second, bookmark: bookmark(second))
        let date = Date(timeIntervalSince1970: 12345)
        let discarded = try history.record(first, bookmark: bookmark(first), now: date)
        XCTAssertEqual(history.entries.count, 2)
        XCTAssertEqual(history.entries.first?.id, originalID)
        XCTAssertEqual(history.entries.first?.lastUsed, date)
        XCTAssertTrue(discarded.isEmpty)
        XCTAssertTrue(history.containsFile(second.url))
    }

    @MainActor
    func testRemoteCacheRetainedUntilSourceIsReplaced() async throws {
        let history = WallpaperHistory(directory: storeDirectory)
        let source = URL(string: "https://example.com/wallpaper")!
        let first = try makeAsset("download-one").withSourceURL(source)
        let another = try makeAsset("another").withSourceURL(URL(string: "https://example.com/other")!)
        try history.record(first, bookmark: bookmark(first))
        let originalID = history.entries.first?.id
        try history.record(another, bookmark: bookmark(another))
        XCTAssertTrue(history.containsFile(first.url))
        let replacement = try makeAsset("download-two").withSourceURL(source)
        let discarded = try history.record(replacement, bookmark: bookmark(replacement))
        XCTAssertEqual(history.entries.count, 2)
        XCTAssertEqual(history.entries.first?.id, originalID)
        XCTAssertEqual(discarded.map(\.fileURL), [first.url])
        XCTAssertFalse(history.containsFile(first.url))
        XCTAssertTrue(history.containsFile(replacement.url))
        XCTAssertTrue(history.containsFile(another.url))
    }

    @MainActor
    func testOldestEntryIsEvictedAfterLimit() async throws {
        let history = WallpaperHistory(directory: storeDirectory)
        let base = try makeAsset("base")
        var firstURL: URL?
        var discarded: [WallpaperHistoryEntry] = []
        for index in 0...WallpaperHistory.limit {
            let asset = base.withSourceURL(URL(string: "https://example.com/\(index)")!)
            discarded = try history.record(asset, bookmark: bookmark(asset))
            if index == 0 { firstURL = asset.sourceURL }
        }
        XCTAssertEqual(history.entries.count, WallpaperHistory.limit)
        XCTAssertEqual(discarded.first?.sourceURL, firstURL)
        XCTAssertEqual(history.entries.first?.sourceURL?.lastPathComponent, String(WallpaperHistory.limit))
        XCTAssertTrue(history.containsFile(base.url)) // Shared file is still referenced by retained entries.
    }

    @MainActor
    func testRemovePersistsAndPreservesLocalOriginal() async throws {
        let history = WallpaperHistory(directory: storeDirectory)
        let asset = try makeAsset("local")
        try history.record(asset, bookmark: bookmark(asset))
        try history.remove(XCTUnwrap(history.entries.first))
        XCTAssertTrue(WallpaperHistory(directory: storeDirectory).entries.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: asset.url.path))
    }

    @MainActor
    func testMissingOriginalDoesNotRemoveHistoryOrPreview() async throws {
        let history = WallpaperHistory(directory: storeDirectory)
        let asset = try makeAsset("missing")
        try history.record(asset, bookmark: bookmark(asset))
        try FileManager.default.removeItem(at: asset.url)
        let restored = WallpaperHistory(directory: storeDirectory)
        XCTAssertEqual(restored.entries.count, 1)
        XCTAssertNotNil(restored.entries.first?.thumbnail)
    }

    @MainActor
    func testFailedSaveLeavesPublishedHistoryIntact() async throws {
        let history = WallpaperHistory(directory: storeDirectory)
        let first = try makeAsset("first")
        try history.record(first, bookmark: bookmark(first))
        let id = history.entries.first?.id
        let file = storeDirectory.appendingPathComponent("wallpaper-history.json")
        try FileManager.default.moveItem(at: file, to: storeDirectory.appendingPathComponent("saved.json"))
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        let second = try makeAsset("second")
        XCTAssertThrowsError(try history.record(second, bookmark: bookmark(second)))
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(history.entries.first?.id, id)
    }

    @MainActor
    func testUnreadableHistoryIsNotOverwritten() async throws {
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        let file = storeDirectory.appendingPathComponent("wallpaper-history.json")
        let broken = Data("invalid history".utf8)
        try broken.write(to: file)
        let history = WallpaperHistory(directory: storeDirectory)
        XCTAssertNotNil(history.loadError)
        let asset = try makeAsset("new")
        XCTAssertThrowsError(try history.record(asset, bookmark: bookmark(asset)))
        XCTAssertEqual(try Data(contentsOf: file), broken)
    }

    @MainActor
    func testUsingWallpaperWithBrokenHistoryReturnsWarningAndPreservesFile() async throws {
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        let file = storeDirectory.appendingPathComponent("wallpaper-history.json")
        let broken = Data("invalid history".utf8)
        try broken.write(to: file)
        let history = WallpaperHistory(directory: storeDirectory)
        let asset = try makeAsset("usable")
        let result = history.recordForUse(asset, bookmark: try bookmark(asset))
        XCTAssertNotNil(result.warning)
        XCTAssertTrue(result.discarded.isEmpty)
        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertEqual(try Data(contentsOf: file), broken)
        XCTAssertTrue(FileManager.default.fileExists(atPath: asset.url.path))
    }

    @MainActor
    func testUsingWallpaperAfterWriteFailureKeepsHistoryAndCanRetry() async throws {
        let history = WallpaperHistory(directory: storeDirectory)
        let first = try makeAsset("first")
        try history.record(first, bookmark: bookmark(first))
        let id = history.entries.first?.id
        let file = storeDirectory.appendingPathComponent("wallpaper-history.json")
        try FileManager.default.moveItem(at: file, to: storeDirectory.appendingPathComponent("saved.json"))
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        let second = try makeAsset("second")
        let failed = history.recordForUse(second, bookmark: try bookmark(second))
        XCTAssertNotNil(failed.warning)
        XCTAssertTrue(failed.discarded.isEmpty)
        XCTAssertEqual(history.entries.map(\.id), [id!])
        try FileManager.default.removeItem(at: file)
        let retry = history.recordForUse(second, bookmark: try bookmark(second))
        XCTAssertNil(retry.warning)
        XCTAssertEqual(history.entries.map(\.name), [second.displayName, first.displayName])
        XCTAssertEqual(WallpaperHistory(directory: storeDirectory).entries.count, 2)
    }

    @MainActor
    func testSuccessfulUseStillReturnsReplacedCacheForCleanup() async throws {
        let history = WallpaperHistory(directory: storeDirectory)
        let source = URL(string: "https://example.com/image")!
        let first = try makeAsset("old-cache").withSourceURL(source)
        let second = try makeAsset("new-cache").withSourceURL(source)
        let initial = history.recordForUse(first, bookmark: try bookmark(first))
        XCTAssertNil(initial.warning)
        let updated = history.recordForUse(second, bookmark: try bookmark(second))
        XCTAssertNil(updated.warning)
        XCTAssertEqual(updated.discarded.map(\.fileURL), [first.url])
        XCTAssertTrue(history.containsFile(second.url))
        XCTAssertFalse(history.containsFile(first.url))
    }

    private func bookmark(_ asset: WallpaperAsset) throws -> Data {
        try asset.url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private func makeAsset(_ name: String) throws -> WallpaperAsset {
        let url = directory.appendingPathComponent(name).appendingPathExtension("png")
        let context = try XCTUnwrap(CGContext(data: nil, width: 800, height: 400, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(NSColor.systemGreen.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 800, height: 400))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return try WallpaperAsset.loadImage(url)
    }
}
