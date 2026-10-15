import AppKit
import XCTest
@testable import QuietWall

final class WallpaperLibraryTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    private func entry(_ index: Int) -> WallpaperHistoryEntry {
        WallpaperHistoryEntry(id: UUID(), fileURL: directory.appendingPathComponent("\(index).png"),
            bookmark: Data(), sourceURL: nil, name: "\(index)", details: "fixture", isVideo: false, lastUsed: Date(), thumbnail: nil)
    }
    @MainActor func testFavoritesRemainBeyondHistoryLimitAndSurviveRestart() throws {
        let library = WallpaperLibrary(directory: directory)
        for index in 0..<55 { try library.toggle(entry(index)) }
        XCTAssertEqual(library.favorites.entries.count, 55)
        XCTAssertEqual(WallpaperLibrary(directory: directory).favorites.entries.count, 55)
        let first = library.favorites.entries[0]
        try library.toggle(first)
        XCTAssertFalse(library.contains(first))
        XCTAssertEqual(library.favorites.entries.count, 54)
    }
    @MainActor func testRemovingHistoryDoesNotRemoveFavorite() throws {
        let history = WallpaperHistory(directory: directory)
        let library = WallpaperLibrary(directory: directory)
        let value = entry(1)
        try history.add(value)
        try library.toggle(value)
        try history.remove(value)
        XCTAssertTrue(library.favorites.containsFile(value.fileURL))
        XCTAssertTrue(history.entries.isEmpty)
    }
    func testDisplayModesPersistPerWallpaperAndPerDisplay() {
        let a = "QuietWall.ModeTests.\(UUID())", b = "QuietWall.ModeTests.\(UUID())"
        let first = UserDefaults(suiteName: a)!, second = UserDefaults(suiteName: b)!
        defer { first.removePersistentDomain(forName: a); second.removePersistentDomain(forName: b) }
        let url = URL(string: "https://example.test/wallpaper")!
        let other = URL(fileURLWithPath: "/other.png")
        WallpaperDisplayPreferences(defaults: first).set(.fit, for: url)
        WallpaperDisplayPreferences(defaults: first).set(.stretch, for: other)
        WallpaperDisplayPreferences(defaults: second).set(.fill, for: url)
        XCTAssertEqual(WallpaperDisplayPreferences(defaults: first).mode(for: url), .fit)
        XCTAssertEqual(WallpaperDisplayPreferences(defaults: first).mode(for: other), .stretch)
        XCTAssertEqual(WallpaperDisplayPreferences(defaults: second).mode(for: url), .fill)
    }
}
