import Foundation
import XCTest
@testable import QuietWallCore

final class DayNightScheduleTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }
    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: hour, minute: minute))!
    }
    func testDefaultDayAndNightBoundaries() {
        let schedule = DayNightSchedule()
        XCTAssertFalse(schedule.isDay(at: date(7, 59), calendar: calendar))
        XCTAssertTrue(schedule.isDay(at: date(8), calendar: calendar))
        XCTAssertFalse(schedule.isDay(at: date(20), calendar: calendar))
        XCTAssertEqual(schedule.nextBoundary(after: date(8), calendar: calendar), date(20))
        XCTAssertEqual(schedule.nextBoundary(after: date(21), calendar: calendar), calendar.date(byAdding: .day, value: 1, to: date(8)))
    }
    func testOvernightDayRangeAndInvalidTimes() {
        let schedule = DayNightSchedule(dayMinute: 1200, nightMinute: 480)
        XCTAssertTrue(schedule.isDay(at: date(23), calendar: calendar))
        XCTAssertTrue(schedule.isDay(at: date(7), calendar: calendar))
        XCTAssertFalse(schedule.isDay(at: date(12), calendar: calendar))
        XCTAssertFalse(DayNightSchedule(dayMinute: 10, nightMinute: 10).isValid)
        XCTAssertNil(DayNightSchedule(dayMinute: -1).nextBoundary(after: date(12), calendar: calendar))
    }
    func testDSTUsesCalendarBoundary() {
        var calendar = self.calendar
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let before = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1))!
        let next = DayNightSchedule(dayMinute: 150, nightMinute: 1200).nextBoundary(after: before, calendar: calendar)!
        XCTAssertGreaterThan(next, before)
        XCTAssertEqual(calendar.component(.day, from: next), 8)
        XCTAssertEqual(calendar.component(.hour, from: next), 3)
    }
}
