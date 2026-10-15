import Foundation

public struct RotationSchedule: Codable, Equatable {
    public enum Period: String, Codable, CaseIterable {
        case fiveMinutes, tenMinutes, thirtyMinutes, hour, day, week, month, custom
        public var title: String {
            switch self {
            case .fiveMinutes: return "5 分钟"
            case .tenMinutes: return "10 分钟"
            case .thirtyMinutes: return "30 分钟"
            case .hour: return "1 小时"
            case .day: return "每天"
            case .week: return "每周"
            case .month: return "每月"
            case .custom: return "自定义"
            }
        }
    }
    public enum Unit: String, Codable, CaseIterable {
        case minute, hour, day
        public var title: String {
            switch self {
            case .minute: return "分钟"
            case .hour: return "小时"
            case .day: return "天"
            }
        }
    }
    public var period: Period
    public var amount: Int
    public var unit: Unit

    public init(period: Period = .fiveMinutes, amount: Int = 5, unit: Unit = .minute) {
        self.period = period
        self.amount = amount
        self.unit = unit
    }

    public var isValid: Bool { period != .custom || (1...10000).contains(amount) }

    public func nextDate(after date: Date, calendar: Calendar = .current) -> Date? {
        guard isValid else { return nil }
        switch period {
        case .fiveMinutes: return date.addingTimeInterval(300)
        case .tenMinutes: return date.addingTimeInterval(600)
        case .thirtyMinutes: return date.addingTimeInterval(1800)
        case .hour: return date.addingTimeInterval(3600)
        case .day: return calendar.date(byAdding: .day, value: 1, to: date)
        case .week: return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .month: return calendar.date(byAdding: .month, value: 1, to: date)
        case .custom:
            switch unit {
            case .minute: return date.addingTimeInterval(Double(amount) * 60)
            case .hour: return date.addingTimeInterval(Double(amount) * 3600)
            case .day: return calendar.date(byAdding: .day, value: amount, to: date)
            }
        }
    }
}
