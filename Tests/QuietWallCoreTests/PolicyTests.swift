import XCTest
@testable import QuietWallCore

final class PolicyTests: XCTestCase {
    @objc func testNoVideoNeverPlays() {
        XCTAssertEqual(PlaybackPolicy().pauseReason, .noVideo)
    }

    @objc func testVisibleDesktopOnACPlays() {
        var policy = PlaybackPolicy()
        policy.hasVideo = true
        XCTAssertNil(policy.pauseReason)
    }

    @objc func testBatteryOptOutDoesNotBypassLowPower() {
        var policy = PlaybackPolicy()
        policy.hasVideo = true
        policy.onBattery = true
        XCTAssertEqual(policy.pauseReason, .battery)
        policy.pauseOnBattery = false
        XCTAssertNil(policy.pauseReason)
        policy.lowPower = true
        XCTAssertEqual(policy.pauseReason, .lowPower)
    }

    @objc func testUncoveringDoesNotUndoManualPause() {
        var policy = PlaybackPolicy()
        policy.hasVideo = true
        policy.manuallyPaused = true
        policy.covered = true
        XCTAssertEqual(policy.pauseReason, .manual)
        policy.covered = false
        XCTAssertEqual(policy.pauseReason, .manual)
    }

    @objc func testLowPowerOnACCanBeAllowedExplicitly() {
        var policy = PlaybackPolicy()
        policy.hasVideo = true
        policy.lowPower = true
        XCTAssertEqual(policy.pauseReason, .lowPower)
        policy.pauseOnLowPower = false
        XCTAssertNil(policy.pauseReason)
        policy.pauseOnLowPower = true
        XCTAssertEqual(policy.pauseReason, .lowPower)
    }

    @objc func testLowPowerOptOutStillHonorsOtherPauseReasons() {
        let cases: [(WritableKeyPath<PlaybackPolicy, Bool>, PauseReason)] = [
            (\.onBattery, .battery), (\.thermallyLimited, .thermal),
            (\.locked, .locked), (\.sleeping, .sleeping),
            (\.manuallyPaused, .manual), (\.reducedMotion, .reducedMotion),
            (\.covered, .covered)
        ]
        for (keyPath, reason) in cases {
            var policy = PlaybackPolicy()
            policy.hasVideo = true
            policy.lowPower = true
            policy.pauseOnLowPower = false
            policy[keyPath: keyPath] = true
            XCTAssertEqual(policy.pauseReason, reason)
        }
    }

    @objc func testWakeDoesNotBypassLockOrBatteryPolicy() {
        var policy = PlaybackPolicy()
        policy.hasVideo = true
        policy.sleeping = true
        policy.locked = true
        policy.onBattery = true
        XCTAssertEqual(policy.pauseReason, .sleeping)
        policy.sleeping = false
        XCTAssertEqual(policy.pauseReason, .locked)
        policy.locked = false
        XCTAssertEqual(policy.pauseReason, .battery)
    }

    @objc func testThermalAndAccessibilityAlwaysPause() {
        var policy = PlaybackPolicy()
        policy.hasVideo = true
        policy.pauseOnBattery = false
        policy.pauseWhenCovered = false
        policy.thermallyLimited = true
        XCTAssertEqual(policy.pauseReason, .thermal)
        policy.thermallyLimited = false
        policy.reducedMotion = true
        XCTAssertEqual(policy.pauseReason, .reducedMotion)
    }

    @objc func testCoverageCanBeDisabled() {
        var policy = PlaybackPolicy()
        policy.hasVideo = true
        policy.covered = true
        XCTAssertEqual(policy.pauseReason, .covered)
        policy.pauseWhenCovered = false
        XCTAssertNil(policy.pauseReason)
    }
}
