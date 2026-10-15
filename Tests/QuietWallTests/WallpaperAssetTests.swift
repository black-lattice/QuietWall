import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import QuietWall

final class WallpaperAssetTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testCommonImageFormatsLoadWithoutVideo() throws {
        for type in [UTType.png, .jpeg, .heic, .tiff] {
            let url = try writeImage(type: type)
            let wallpaper = try WallpaperAsset.loadImage(url)
            XCTAssertEqual(wallpaper.url, url)
            XCTAssertFalse(wallpaper.isVideo)
            XCTAssertNil(wallpaper.video)
            XCTAssertEqual(wallpaper.poster.width, 64)
            XCTAssertEqual(wallpaper.poster.height, 32)
            XCTAssertEqual(wallpaper.details, "64 × 32 · 静态图片")
            XCTAssertNil(wallpaper.warning)
        }
    }

    func testImageOrientationIsApplied() throws {
        let url = try writeImage(type: .jpeg, orientation: 6)
        let wallpaper = try WallpaperAsset.loadImage(url)
        XCTAssertEqual(wallpaper.poster.width, 32)
        XCTAssertEqual(wallpaper.poster.height, 64)
        XCTAssertEqual(wallpaper.details, "32 × 64 · 静态图片")
    }

    func testAnimatedImageUsesFirstFrameOnly() throws {
        let url = try writeImage(type: .gif, frameCount: 2)
        let wallpaper = try WallpaperAsset.loadImage(url)
        XCTAssertFalse(wallpaper.isVideo)
        XCTAssertNotNil(wallpaper.warning)
        let pixel = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                                          bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        pixel.draw(wallpaper.poster, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let bytes = try XCTUnwrap(pixel.data).assumingMemoryBound(to: UInt8.self)
        XCTAssertGreaterThan(bytes[0], 240) // First frame is red; second is blue.
        XCTAssertLessThan(bytes[2], 15)
    }

    func testLargeImageDecodeIsBounded() throws {
        let url = try writeImage(type: .png, width: 9000, height: 32)
        let wallpaper = try WallpaperAsset.loadImage(url)
        XCTAssertEqual(wallpaper.poster.width, 8192)
        XCTAssertEqual(wallpaper.details, "9000 × 32 · 静态图片")
    }

    func testInvalidAndMissingImagesAreRejected() throws {
        let url = directory.appendingPathComponent("broken.png")
        XCTAssertThrowsError(try WallpaperAsset.loadImage(url))
        try Data("not an image".utf8).write(to: url)
        XCTAssertThrowsError(try WallpaperAsset.loadImage(url))
        try Data().write(to: url)
        XCTAssertThrowsError(try WallpaperAsset.loadImage(url))
    }

    func testTruncatedImageIsRejected() throws {
        let url = try writeImage(type: .png)
        let data = try Data(contentsOf: url)
        try data.prefix(data.count / 2).write(to: url)
        XCTAssertThrowsError(try WallpaperAsset.loadImage(url))
    }

    private func writeImage(type: UTType, width: Int = 64, height: Int = 32,
                            orientation: Int = 1, frameCount: Int = 1) throws -> URL {
        let url = directory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(type.preferredFilenameExtension ?? "image")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, type.identifier as CFString, frameCount, nil))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
                                            bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        for frame in 0..<frameCount {
            context.setFillColor(CGColor(red: frame == 0 ? 1 : 0, green: 0,
                                         blue: frame == 0 ? 0 : 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let image = try XCTUnwrap(context.makeImage())
            CGImageDestinationAddImage(destination, image,
                                       [kCGImagePropertyOrientation: orientation] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
}
