import Foundation

public struct DayNightSchedule: Codable, Equatable {
    public var dayMinute: Int
    public var nightMinute: Int
    public init(dayMinute: Int = 480, nightMinute: Int = 1200) {
        self.dayMinute = dayMinute
        self.nightMinute = nightMinute
    }
    public var isValid: Bool {
        (0..<1440).contains(dayMinute) && (0..<1440).contains(nightMinute) && dayMinute != nightMinute
    }
    public func isDay(at date: Date, calendar: Calendar = .current) -> Bool {
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        if dayMinute < nightMinute { return minute >= dayMinute && minute < nightMinute }
        return minute >= dayMinute || minute < nightMinute
    }
    public func nextBoundary(after date: Date, calendar: Calendar = .current) -> Date? {
        guard isValid else { return nil }
        return [dayMinute, nightMinute].compactMap { value in
            calendar.nextDate(after: date, matching: DateComponents(hour: value / 60, minute: value % 60),
                              matchingPolicy: .nextTime, repeatedTimePolicy: .first)
        }.min()
    }
}
