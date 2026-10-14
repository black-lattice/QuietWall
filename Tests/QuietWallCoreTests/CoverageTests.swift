import XCTest
@testable import QuietWallCore

final class CoverageTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    @objc func testEmptyDesktopIsVisible() {
        XCTAssertFalse(DesktopCoverage.isCovered(screen, by: []))
    }

    @objc func testFullScreenWindowCoversDesktop() {
        XCTAssertTrue(DesktopCoverage.isCovered(screen, by: [screen]))
    }

    @objc func testTiledWindowsCoverTogether() {
        let left = CGRect(x: 0, y: 0, width: 960, height: 1080)
        let right = CGRect(x: 960, y: 0, width: 960, height: 1080)
        XCTAssertTrue(DesktopCoverage.isCovered(screen, by: [left, right]))
    }

    @objc func testOverlappingWindowsDoNotDoubleCountArea() {
        let window = CGRect(x: 0, y: 0, width: 1500, height: 1080)
        XCTAssertFalse(DesktopCoverage.isCovered(screen, by: [window, window]))
    }

    @objc func testOnePixelGapRemainsVisible() {
        let left = CGRect(x: 0, y: 0, width: 959, height: 1080)
        let right = CGRect(x: 960, y: 0, width: 960, height: 1080)
        XCTAssertFalse(DesktopCoverage.isCovered(screen, by: [left, right]))
    }

    @objc func testExternalScreenWithNegativeCoordinates() {
        let external = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)
        XCTAssertFalse(DesktopCoverage.isCovered(external, by: [screen]))
        XCTAssertTrue(DesktopCoverage.isCovered(external, by: [external]))
    }

    @objc func testOversizedAndOffscreenWindows() {
        XCTAssertTrue(DesktopCoverage.isCovered(screen, by: [screen.insetBy(dx: -100, dy: -100)]))
        XCTAssertFalse(DesktopCoverage.isCovered(screen, by: [screen.offsetBy(dx: 3000, dy: 0)]))
        XCTAssertFalse(DesktopCoverage.isCovered(.zero, by: [screen]))
    }
}
