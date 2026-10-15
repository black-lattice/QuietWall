import AppKit
import ImageIO
import UniformTypeIdentifiers
import QuietWallCore
import XCTest
@testable import QuietWall

final class WallpaperRotationTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suite = "QuietWallRotationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try FileManager.default.removeItem(at: directory)
    }

    func testFolderScanFiltersAndSortsNaturally() async throws {
        for name in ["10.mp4", "2.jpg", "1.png", "notes.txt", ".hidden.png"] {
            try Data().write(to: directory.appendingPathComponent(name))
        }
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("nested.png"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("alias.png"),
                                                   withDestinationURL: directory.appendingPathComponent("1.png"))
        let files = try await WallpaperFolder.files(in: directory)
        XCTAssertEqual(files.map(\.lastPathComponent), ["1.png", "2.jpg", "10.mp4"])
        XCTAssertEqual(WallpaperFolder.ordered(files, after: files[1]).map(\.lastPathComponent), ["10.mp4", "1.png", "2.jpg"])
    }

    @MainActor
    func testRotatesInOrderWrapsAndRetainsSettings() async throws {
        _ = try makeImage("1")
        _ = try makeImage("2")
        let rotation = WallpaperRotation(defaults: defaults)
        defer { rotation.shutdown() }
        var used: [String] = []
        rotation.apply = { used.append($0.url.lastPathComponent) }
        try rotation.chooseFolder(directory)
        await settle(rotation)
        rotation.next()
        await settle(rotation)
        rotation.next()
        await settle(rotation)
        XCTAssertEqual(used, ["1.png", "2.png", "1.png"])
        rotation.setSchedule(RotationSchedule(period: .custom, amount: 2, unit: .hour))
        let restored = WallpaperRotation(defaults: defaults)
        defer { restored.shutdown() }
        XCTAssertTrue(restored.isEnabled)
        XCTAssertEqual(restored.folderURL?.standardizedFileURL, directory.standardizedFileURL)
        XCTAssertEqual(restored.schedule, rotation.schedule)
        XCTAssertEqual(restored.nextChange, rotation.nextChange)
        restored.apply = { used.append($0.url.lastPathComponent) }
        restored.next()
        await settle(restored)
        XCTAssertEqual(used.last, "2.png")
    }

    @MainActor
    func testCorruptMediaIsSkipped() async throws {
        try Data("bad image".utf8).write(to: directory.appendingPathComponent("1.png"))
        _ = try makeImage("2")
        let rotation = WallpaperRotation(defaults: defaults)
        defer { rotation.shutdown() }
        var used: URL?
        rotation.apply = { used = $0.url }
        try rotation.chooseFolder(directory)
        await settle(rotation)
        XCTAssertEqual(used?.lastPathComponent, "2.png")
        XCTAssertNotNil(rotation.message)
    }

    @MainActor
    func testEmptyFolderRetainsWallpaperAndRescansNextTime() async throws {
        let rotation = WallpaperRotation(defaults: defaults)
        defer { rotation.shutdown() }
        var applied = 0
        rotation.apply = { _ in applied += 1 }
        try rotation.chooseFolder(directory)
        await settle(rotation)
        XCTAssertEqual(applied, 0)
        XCTAssertNotNil(rotation.message)
        XCTAssertGreaterThan(try XCTUnwrap(rotation.nextChange), Date())
        _ = try makeImage("added")
        rotation.next()
        await settle(rotation)
        XCTAssertEqual(applied, 1)
        XCTAssertNil(rotation.message)
    }

    @MainActor
    func testOverdueRestartOnlyAdvancesOnce() async throws {
        _ = try makeImage("1")
        _ = try makeImage("2")
        var time = Date()
        let initial = WallpaperRotation(defaults: defaults, now: { time })
        initial.apply = { _ in }
        try initial.chooseFolder(directory)
        await settle(initial)
        initial.shutdown()
        time = time.addingTimeInterval(3600)
        let restored = WallpaperRotation(defaults: defaults, now: { time })
        defer { restored.shutdown() }
        var used: [String] = []
        restored.apply = { used.append($0.url.lastPathComponent) }
        restored.resume()
        restored.resume()
        await settle(restored)
        XCTAssertEqual(used, ["2.png"])
        XCTAssertEqual(restored.nextChange, time.addingTimeInterval(300))
        restored.resume()
        XCTAssertFalse(restored.isRotating)
    }

    @MainActor
    func testLockedOrSleepingDefersUntilEligible() async throws {
        _ = try makeImage("1")
        let rotation = WallpaperRotation(defaults: defaults)
        defer { rotation.shutdown() }
        var eligible = false
        var applied = 0
        rotation.canRotate = { eligible }
        rotation.apply = { _ in applied += 1 }
        try rotation.chooseFolder(directory)
        XCTAssertFalse(rotation.isRotating)
        XCTAssertEqual(applied, 0)
        eligible = true
        rotation.resume()
        await settle(rotation)
        XCTAssertEqual(applied, 1)
    }

    @MainActor
    func testDisablingCancelsInFlightWithoutApplying() async throws {
        let url = try makeImage("1")
        let asset = try WallpaperAsset.loadImage(url)
        var continuation: CheckedContinuation<WallpaperAsset, Never>?
        let rotation = WallpaperRotation(defaults: defaults, load: { _ in
            await withCheckedContinuation { continuation = $0 }
        })
        defer { rotation.shutdown() }
        var applied = 0
        rotation.apply = { _ in applied += 1 }
        try rotation.chooseFolder(directory)
        for _ in 0..<200 {
            if continuation != nil { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let pending = try XCTUnwrap(continuation)
        rotation.setEnabled(false)
        pending.resume(returning: asset)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(applied, 0)
        XCTAssertFalse(rotation.isRotating)
        XCTAssertFalse(WallpaperRotation(defaults: defaults).isEnabled)
    }

    @MainActor
    func testChangingIntervalResetsDeadlineAndRejectsInvalidCustomValue() async throws {
        _ = try makeImage("1")
        let time = Date()
        let rotation = WallpaperRotation(defaults: defaults, now: { time })
        defer { rotation.shutdown() }
        var applied = 0
        rotation.apply = { _ in applied += 1 }
        try rotation.chooseFolder(directory)
        await settle(rotation)
        rotation.setSchedule(RotationSchedule(period: .thirtyMinutes))
        XCTAssertEqual(rotation.nextChange, time.addingTimeInterval(1800))
        rotation.setSchedule(RotationSchedule(period: .custom, amount: 0))
        XCTAssertEqual(rotation.schedule.period, .thirtyMinutes)
        XCTAssertEqual(applied, 1)
    }

    @MainActor
    func testMissingFolderCanRecoverWithoutLosingConfiguration() async throws {
        let folder = directory.appendingPathComponent("wallpapers")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let rotation = WallpaperRotation(defaults: defaults)
        defer { rotation.shutdown() }
        var applied = 0
        rotation.apply = { _ in applied += 1 }
        try rotation.chooseFolder(folder)
        await settle(rotation)
        try FileManager.default.removeItem(at: folder)
        rotation.next()
        await settle(rotation)
        XCTAssertNotNil(rotation.message)
        XCTAssertTrue(rotation.isEnabled)
        XCTAssertEqual(rotation.folderURL, folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let image = try makeImage("recovered")
        try FileManager.default.copyItem(at: image, to: folder.appendingPathComponent("recovered.png"))
        rotation.next()
        await settle(rotation)
        XCTAssertEqual(applied, 1)
        XCTAssertNil(rotation.message)
    }

    @MainActor
    func testGridSelectionAndNavigationWhilePaused() async throws {
        let first = try makeImage("1")
        let second = try makeImage("2")
        let rotation = WallpaperRotation(defaults: defaults)
        defer { rotation.shutdown() }
        var used: [URL] = []
        rotation.apply = { used.append($0.url) }
        try rotation.chooseFolder(directory)
        await settle(rotation)
        rotation.setEnabled(false)
        rotation.select(second)
        await settle(rotation)
        XCTAssertEqual(used.last?.resolvingSymlinksInPath(), second.resolvingSymlinksInPath())
        XCTAssertFalse(rotation.isEnabled)
        rotation.previous()
        await settle(rotation)
        XCTAssertEqual(used.last?.resolvingSymlinksInPath(), first.resolvingSymlinksInPath())
        rotation.next()
        await settle(rotation)
        XCTAssertEqual(used.last?.resolvingSymlinksInPath(), second.resolvingSymlinksInPath())
    }

    @MainActor
    func testRandomBadFileDoesNotStallFollowingCycles() async throws {
        _ = try makeImage("1")
        _ = try makeImage("2")
        try Data("broken".utf8).write(to: directory.appendingPathComponent("bad.png"))
        let rotation = WallpaperRotation(defaults: defaults)
        defer { rotation.shutdown() }
        var applied = 0
        rotation.apply = { _ in applied += 1 }
        rotation.setRandomOrder(true)
        try rotation.chooseFolder(directory)
        await settle(rotation)
        for _ in 0..<8 { rotation.next(); await settle(rotation) }
        XCTAssertEqual(applied, 9)
    }

    @MainActor
    func testFavoriteRotationAndDisplayProfilesAreIndependent() async throws {
        let url = try makeImage("1")
        let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        let entry = WallpaperHistoryEntry(id: UUID(), fileURL: url, bookmark: bookmark, sourceURL: nil,
            name: "favorite", details: "test", isVideo: false, lastUsed: Date(), thumbnail: nil)
        let otherSuite = "QuietWallRotationTests.\(UUID())"
        let otherDefaults = UserDefaults(suiteName: otherSuite)!
        defer { otherDefaults.removePersistentDomain(forName: otherSuite) }
        let a = WallpaperRotation(defaults: defaults), b = WallpaperRotation(defaults: otherDefaults)
        defer { a.shutdown(); b.shutdown() }
        var used = 0
        a.favoriteEntries = { [entry] }
        a.apply = { _ in used += 1 }
        a.chooseFavorites()
        await settle(a)
        XCTAssertEqual(used, 1)
        XCTAssertFalse(b.isEnabled)
        XCTAssertTrue(WallpaperRotation(defaults: defaults).usesFavorites)
        XCTAssertFalse(WallpaperRotation(defaults: otherDefaults).usesFavorites)
    }

    @MainActor
    private func settle(_ rotation: WallpaperRotation) async {
        for _ in 0..<400 {
            if !rotation.isRotating { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("轮换未在预期时间内完成")
    }

    private func makeImage(_ name: String) throws -> URL {
        let url = directory.appendingPathComponent(name).appendingPathExtension("png")
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
}
