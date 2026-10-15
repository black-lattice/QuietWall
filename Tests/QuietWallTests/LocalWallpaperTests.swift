import Foundation
import XCTest
@testable import QuietWall

final class LocalWallpaperTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testPastedPathAndDroppedURLPreserveSpacesAndUnicode() throws {
        let url = directory.appendingPathComponent("风景 01 #1.png")
        try Data([0]).write(to: url)
        XCTAssertEqual(try LocalWallpaper.url(from: "  \(url.path)\n").path, url.path)
        XCTAssertEqual(try LocalWallpaper.url(from: url.absoluteString).path, url.path)
    }

    func testMissingFilesAndDirectoriesAreRejected() throws {
        XCTAssertThrowsError(try LocalWallpaper.url(from: directory.path))
        XCTAssertThrowsError(try LocalWallpaper.url(from: directory.appendingPathComponent("missing.png").path))
    }

    func testWebAddressesAndRelativePathsAreRejected() throws {
        for value in ["", "image.png", "https://example.com/image.png", "ftp://example.com/video.mov"] {
            XCTAssertThrowsError(try LocalWallpaper.url(from: value))
        }
    }
}
