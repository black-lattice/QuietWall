import XCTest
@testable import QuietWallCore

final class SessionSnapshotTests: XCTestCase {
    @objc func testLockedAtLaunchPausesBeforeAnyNotification() {
        let snapshot = SessionSnapshot(onConsole: true, loginDone: true,
                                       lockFlag: true, displaysAsleep: [false])
        var policy = PlaybackPolicy()
        policy.hasVideo = true
        policy.locked = snapshot.locked || snapshot.sessionInactive
        policy.sleeping = snapshot.displaySleeping
        XCTAssertEqual(policy.pauseReason, .locked)
    }

    @objc func testSleepingAtLaunchPausesBeforeAnyNotification() {
        let snapshot = SessionSnapshot(onConsole: true, loginDone: true,
                                       lockFlag: nil, displaysAsleep: [true, true])
        var policy = PlaybackPolicy()
        policy.hasVideo = true
        policy.sleeping = snapshot.displaySleeping
        XCTAssertEqual(policy.pauseReason, .sleeping)
    }

    @objc func testMissingSessionIsConservative() {
        let snapshot = SessionSnapshot(onConsole: nil, loginDone: nil,
                                       lockFlag: nil, displaysAsleep: [false])
        XCTAssertTrue(snapshot.sessionInactive)
    }

    @objc func testInactiveOrIncompleteLoginPauses() {
        XCTAssertTrue(SessionSnapshot(onConsole: false, loginDone: true,
                                      lockFlag: nil, displaysAsleep: [false]).sessionInactive)
        XCTAssertTrue(SessionSnapshot(onConsole: true, loginDone: false,
                                      lockFlag: nil, displaysAsleep: [false]).sessionInactive)
    }

    @objc func testMissingDisplaysAreConservative() {
        for displays: [Bool]? in [nil, []] {
            XCTAssertTrue(SessionSnapshot(onConsole: true, loginDone: true,
                                          lockFlag: nil, displaysAsleep: displays).displaySleeping)
        }
    }

    @objc func testUnlockedSessionWithOneAwakeDisplayCanPlay() {
        let snapshot = SessionSnapshot(onConsole: true, loginDone: true,
                                       lockFlag: nil, displaysAsleep: [true, false])
        XCTAssertFalse(snapshot.sessionInactive)
        XCTAssertFalse(snapshot.locked)
        XCTAssertFalse(snapshot.displaySleeping)
    }
}
