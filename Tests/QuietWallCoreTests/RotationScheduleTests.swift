import XCTest
@testable import QuietWallCore

final class RotationScheduleTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return value
    }

    @objc func testMinuteAndHourPresets() {
        let start = Date(timeIntervalSince1970: 100)
        for (period, seconds) in [(RotationSchedule.Period.fiveMinutes, 300.0), (.tenMinutes, 600), (.thirtyMinutes, 1800), (.hour, 3600)] {
            XCTAssertEqual(RotationSchedule(period: period).nextDate(after: start), start.addingTimeInterval(seconds))
        }
    }

    @objc func testMonthClampsToLeapYearEndInsteadOfThirtyDays() throws {
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 1, day: 31, hour: 12)))
        let next = try XCTUnwrap(RotationSchedule(period: .month).nextDate(after: start, calendar: calendar))
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day, .hour], from: next),
                       DateComponents(year: 2024, month: 2, day: 29, hour: 12))
    }

    @objc func testDailyScheduleKeepsLocalTimeAcrossDaylightSaving() throws {
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 12)))
        let next = try XCTUnwrap(RotationSchedule(period: .day).nextDate(after: start, calendar: calendar))
        XCTAssertEqual(next.timeIntervalSince(start), 23 * 3600)
        XCTAssertEqual(calendar.component(.hour, from: next), 12)
    }

    @objc func testWeeklyAndCustomDaysUseCalendar() throws {
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 12)))
        let week = RotationSchedule(period: .week).nextDate(after: start, calendar: calendar)
        XCTAssertEqual(week, calendar.date(byAdding: .day, value: 7, to: start))
        XCTAssertEqual(RotationSchedule(period: .custom, amount: 7, unit: .day).nextDate(after: start, calendar: calendar), week)
    }

    @objc func testCustomBoundsAndUnits() {
        let start = Date()
        XCTAssertNil(RotationSchedule(period: .custom, amount: 0).nextDate(after: start))
        XCTAssertNil(RotationSchedule(period: .custom, amount: -1).nextDate(after: start))
        XCTAssertNil(RotationSchedule(period: .custom, amount: 10001).nextDate(after: start))
        XCTAssertEqual(RotationSchedule(period: .custom, amount: 2, unit: .hour).nextDate(after: start), start.addingTimeInterval(7200))
        XCTAssertEqual(RotationSchedule(period: .custom, amount: 1).nextDate(after: start), start.addingTimeInterval(60))
    }
}
