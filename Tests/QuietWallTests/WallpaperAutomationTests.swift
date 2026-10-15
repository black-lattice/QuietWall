import AppKit
import XCTest
@testable import QuietWall

final class WallpaperAutomationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var directory: URL!
    override func setUpWithError() throws {
        suite = "QuietWall.AutomationTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try FileManager.default.removeItem(at: directory)
    }
    private func source(_ name: String) throws -> ScheduledWallpaper {
        let url = directory.appendingPathComponent(name)
        try Data().write(to: url)
        return try ScheduledWallpaper(url: url, isFolder: false)
    }
    @MainActor func testAppearanceSwitchAndManualOverride() throws {
        var dark = false
        let automation = WallpaperAutomation(defaults: defaults, dark: { dark })
        defer { automation.shutdown() }
        var selected: [String] = []
        automation.apply = { selected.append($0.name) }
        var config = automation.configuration
        config.day = try source("day.png")
        config.night = try source("night.png")
        config.followsAppearance = true
        config.enabled = true
        automation.update(config)
        automation.resume()
        XCTAssertEqual(selected, ["day.png"])
        dark = true
        automation.resume()
        XCTAssertEqual(selected, ["day.png", "night.png"])
        automation.disableForManualSelection()
        dark = false
        automation.resume()
        XCTAssertEqual(selected.count, 2)
        XCTAssertFalse(WallpaperAutomation(defaults: defaults).configuration.enabled)
    }
    @MainActor func testSleepingDefersAndRestoresCurrentTimeOnly() throws {
        var eligible = false
        var time = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
        let automation = WallpaperAutomation(defaults: defaults, now: { time }, dark: { false })
        defer { automation.shutdown() }
        var applied: [String] = []
        automation.canApply = { eligible }
        automation.apply = { applied.append($0.name) }
        var config = automation.configuration
        config.day = try source("day.png")
        config.night = try source("night.png")
        config.enabled = true
        automation.update(config)
        XCTAssertTrue(applied.isEmpty)
        time = Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: time)!
        eligible = true
        automation.resume()
        automation.resume()
        XCTAssertEqual(applied, ["night.png"])
        let restored = WallpaperAutomation(defaults: defaults, now: { time }, dark: { false })
        defer { restored.shutdown() }
        restored.apply = { applied.append($0.name) }
        restored.resume()
        XCTAssertEqual(applied, ["night.png", "night.png"])
    }
    @MainActor func testIncompleteOrInvalidConfigurationCannotEnable() throws {
        let automation = WallpaperAutomation(defaults: defaults)
        var config = automation.configuration
        config.enabled = true
        automation.update(config)
        XCTAssertFalse(automation.configuration.enabled)
        config.day = try source("day.png")
        config.night = try source("night.png")
        config.times.nightMinute = config.times.dayMinute
        automation.update(config)
        XCTAssertFalse(automation.configuration.enabled)
    }
}
