import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import QuietWall

final class RemoteWallpaperTests: XCTestCase {
    private var directory: URL!
    private var server: WallpaperHTTPServer?

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        server?.stop()
        server = nil
        try FileManager.default.removeItem(at: directory)
    }

    func testURLValidation() throws {
        XCTAssertEqual(try RemoteWallpaper.parseURL("  https://example.com/media?id=1\n").host, "example.com")
        XCTAssertEqual(try RemoteWallpaper.parseURL("http://127.0.0.1:8080/image").port, 8080)
        for address in ["", "example.com/a.jpg", "file:///tmp/image.png", "ftp://example.com/a", "https://"] {
            XCTAssertThrowsError(try RemoteWallpaper.parseURL(address))
        }
    }

    func testImageContentOverridesSuffixAndMIME() async throws {
        let server = try startServer(body: imageData(), contentType: "video/mp4")
        for path in ["/media", "/wrong.mp4", "/redirect"] {
            let remoteURL = server.url(path)
            let wallpaper = try await RemoteWallpaper.load(remoteURL, directory: directory)
            XCTAssertFalse(wallpaper.isVideo)
            XCTAssertEqual(wallpaper.poster.width, 32)
            XCTAssertEqual(wallpaper.sourceURL, remoteURL)
            XCTAssertEqual(wallpaper.displayName, remoteURL.lastPathComponent)
            XCTAssertTrue(FileManager.default.fileExists(atPath: wallpaper.url.path))
        }
    }

    func testVideoContentOverridesSuffixAndMIME() async throws {
        let movie = try await videoData()
        let server = try startServer(body: movie, contentType: "image/jpeg")
        let wallpaper = try await RemoteWallpaper.load(server.url("/wrong.jpg"), directory: directory)
        XCTAssertTrue(wallpaper.isVideo)
        XCTAssertTrue(try XCTUnwrap(wallpaper.video).url.isFileURL)
        XCTAssertEqual(wallpaper.poster.width, 32)
    }

    func testQuickTimeVideoWithoutSuffix() async throws {
        let movie = try await videoData(fileType: .mov)
        let server = try startServer(body: movie)
        let wallpaper = try await RemoteWallpaper.load(server.url("/media"), directory: directory)
        XCTAssertTrue(wallpaper.isVideo)
        XCTAssertEqual(wallpaper.url.pathExtension, "mov")
    }

    func testHTTPErrorDoesNotLeaveCachedFile() async throws {
        let server = try startServer(body: imageData())
        do {
            _ = try await RemoteWallpaper.load(server.url("/missing"), directory: directory)
            XCTFail("404 response must fail even when its body is an image")
        } catch RemoteWallpaperError.httpStatus(let code) {
            XCTAssertEqual(code, 404)
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    func testWebPageIsRejectedAndCleanedUp() async throws {
        let server = try startServer(body: Data("<html>not media</html>".utf8), contentType: "image/png")
        do {
            _ = try await RemoteWallpaper.load(server.url("/wallpaper.png"), directory: directory)
            XCTFail("HTML must not be installed as wallpaper")
        } catch RemoteWallpaperError.unsupportedContent {}
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    func testPlaylistIsRejectedBeforeLoadingSegments() async throws {
        let playlist = "#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:10,\nhttps://example.invalid/segment.ts\n#EXT-X-ENDLIST"
        let server = try startServer(body: Data(playlist.utf8))
        do {
            _ = try await RemoteWallpaper.load(server.url("/media"), directory: directory)
            XCTFail("Playlists must not trigger streaming playback")
        } catch RemoteWallpaperError.unsupportedContent {}
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    func testCachedWallpaperRestoresWithoutNetwork() async throws {
        let server = try startServer(body: imageData())
        let remoteURL = server.url("/media")
        let original = try await RemoteWallpaper.load(remoteURL, directory: directory)
        server.stop()
        self.server = nil
        let restored = try await RemoteWallpaper.load(remoteURL, cachedURL: original.url, directory: directory)
        XCTAssertEqual(restored.url, original.url)
        XCTAssertEqual(restored.sourceURL, remoteURL)
        XCTAssertEqual(restored.poster.width, original.poster.width)
    }

    func testMissingCacheDownloadsAgain() async throws {
        let server = try startServer(body: imageData())
        let wallpaper = try await RemoteWallpaper.load(server.url("/media"),
            cachedURL: directory.appendingPathComponent("missing.media"), directory: directory)
        XCTAssertFalse(wallpaper.isVideo)
        XCTAssertTrue(FileManager.default.fileExists(atPath: wallpaper.url.path))
    }

    func testInFlightDownloadCanBeCancelled() async throws {
        let server = try startServer(body: imageData())
        let url = server.url("/slow")
        let directory = self.directory!
        let task = Task { try await RemoteWallpaper.load(url, directory: directory) }
        await fulfillment(of: [server.requestReceived], timeout: 5)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled download must not finish successfully")
        } catch {
            XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled)
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    func testCacheCleanupPreservesLocalOriginals() throws {
        let original = directory.appendingPathComponent("original.media")
        try imageData().write(to: original)
        RemoteWallpaper.removeCachedFile(original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        let owned = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        try imageData().write(to: owned)
        RemoteWallpaper.removeCachedFile(owned, directory: directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
    }

    private func startServer(body: Data, contentType: String = "application/octet-stream") throws -> WallpaperHTTPServer {
        let server = try WallpaperHTTPServer(body: body, contentType: contentType)
        self.server = server
        return server
    }

    private func imageData() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 16, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 16))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func videoData(fileType: AVFileType = .mp4) async throws -> Data {
        let url = directory.appendingPathComponent(fileType == .mov ? "fixture.mov" : "fixture.mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: fileType)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 32, AVVideoHeightKey: 32
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 32, kCVPixelBufferHeightKey as String: 32
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 32, 32, kCVPixelFormatType_32ARGB, nil, &buffer), kCVReturnSuccess)
        let pixelBuffer = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        memset(CVPixelBufferGetBaseAddress(pixelBuffer), 0, CVPixelBufferGetDataSize(pixelBuffer))
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        XCTAssertTrue(adaptor.append(pixelBuffer, withPresentationTime: .zero))
        writer.endSession(atSourceTime: CMTime(value: 1, timescale: 1))
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        return try Data(contentsOf: url)
    }
}
