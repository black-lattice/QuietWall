import XCTest
import CoreGraphics
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
        XCTAssertFalse(DesktopCoverage.isCovered(screen, by: [left, right], threshold: 1))
        XCTAssertTrue(DesktopCoverage.isCovered(screen, by: [left, right]))
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

    @objc func testNinetyFivePercentBoundary() {
        let screen = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertTrue(DesktopCoverage.isCovered(screen, by: [CGRect(x: 0, y: 0, width: 95, height: 100)]))
        XCTAssertFalse(DesktopCoverage.isCovered(screen, by: [CGRect(x: 0, y: 0, width: 94.9, height: 100)]))
    }

    @objc func testThresholdChangesDecisionForSameLayout() {
        let screen = CGRect(x: 0, y: 0, width: 100, height: 100)
        let windows = [CGRect(x: 0, y: 0, width: 92, height: 100)]
        XCTAssertTrue(DesktopCoverage.isCovered(screen, by: windows, threshold: 0.9))
        XCTAssertFalse(DesktopCoverage.isCovered(screen, by: windows, threshold: 0.95))
        XCTAssertFalse(DesktopCoverage.isCovered(screen, by: windows, threshold: 1))
    }

    @objc func testOverlapCannotReachPercentageThresholdTwice() {
        let screen = CGRect(x: 0, y: 0, width: 100, height: 100)
        let windows = [CGRect(x: 0, y: 0, width: 60, height: 100),
                       CGRect(x: 30, y: 0, width: 60, height: 100)]
        XCTAssertFalse(DesktopCoverage.isCovered(screen, by: windows))
        XCTAssertTrue(DesktopCoverage.isCovered(screen, by: windows, threshold: 0.9))
    }

    @objc func testOffscreenAreaDoesNotCountTowardThreshold() {
        let screen = CGRect(x: 0, y: 0, width: 100, height: 100)
        let windows = [CGRect(x: -100, y: 0, width: 190, height: 100)]
        XCTAssertFalse(DesktopCoverage.isCovered(screen, by: windows))
    }

    @objc func testInvalidThresholdDoesNotPause() {
        for threshold in [Double.nan, .infinity, 0, -1, 1.01] {
            XCTAssertFalse(DesktopCoverage.isCovered(screen, by: [screen], threshold: threshold))
        }
    }

    @objc func testFloatingWindowsCountButWallpaperAndTransparentWindowsDoNot() {
        XCTAssertTrue(DesktopCoverage.canCoverDesktop(layer: 3, alpha: 1, isWallpaper: false))
        XCTAssertTrue(DesktopCoverage.canCoverDesktop(layer: 1000, alpha: 1, isWallpaper: false))
        XCTAssertFalse(DesktopCoverage.canCoverDesktop(layer: -1, alpha: 1, isWallpaper: false))
        XCTAssertFalse(DesktopCoverage.canCoverDesktop(layer: 0, alpha: 0.5, isWallpaper: false))
        XCTAssertFalse(DesktopCoverage.canCoverDesktop(layer: 0, alpha: .nan, isWallpaper: false))
        XCTAssertFalse(DesktopCoverage.canCoverDesktop(layer: 0, alpha: 1, isWallpaper: true))
    }

    @objc func testMissingAndInvalidSavedThresholdUseRecommendedValue() {
        for value in [Double.nan, 0, -1, 0.6, 2] {
            XCTAssertEqual(DesktopCoverage.savedThreshold(value), 0.95)
        }
        for value in [0.9, 0.95, 1] {
            XCTAssertEqual(DesktopCoverage.savedThreshold(value), value)
        }
    }

    @objc func testFullScreenDockWindowDoesNotCoverDesktop() {
        let windows: [(rect: CGRect, layer: Int, isDesktopShell: Bool)] = [
            (screen, 20, true),
            (CGRect(x: 0, y: 0, width: 600, height: 600), 3, false)
        ]
        let rects = windows.filter {
            DesktopCoverage.canCoverDesktop(layer: $0.layer, alpha: 1, isWallpaper: false,
                                            isDesktopShell: $0.isDesktopShell)
        }.map(\.rect)
        XCTAssertFalse(DesktopCoverage.isCovered(screen, by: rects))
        // Ordinary applications at the same layer must still count.
        XCTAssertTrue(DesktopCoverage.canCoverDesktop(layer: 20, alpha: 1, isWallpaper: false))
    }
}
