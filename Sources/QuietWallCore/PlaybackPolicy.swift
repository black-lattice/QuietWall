import Foundation

public enum PauseReason: String {
    case noVideo = "请先选择视频"
    case manual = "已手动暂停"
    case sleeping = "显示器已休眠"
    case locked = "会话已锁定或切换"
    case lowPower = "低电量模式"
    case battery = "电池供电，省电暂停"
    case thermal = "设备温度较高"
    case reducedMotion = "系统已开启减少动态效果"
    case covered = "桌面遮挡已达阈值，省电暂停"
}

public struct PlaybackPolicy {
    public var hasVideo = false
    public var manuallyPaused = false
    public var sleeping = false
    public var locked = false
    public var lowPower = false
    public var onBattery = false
    public var pauseOnBattery = true
    public var thermallyLimited = false
    public var reducedMotion = false
    public var covered = false
    public var pauseWhenCovered = true

    public init() {}

    public var pauseReason: PauseReason? {
        if !hasVideo { return .noVideo }
        if manuallyPaused { return .manual }
        if sleeping { return .sleeping }
        if locked { return .locked }
        if lowPower { return .lowPower }
        if onBattery && pauseOnBattery { return .battery }
        if thermallyLimited { return .thermal }
        if reducedMotion { return .reducedMotion }
        if covered && pauseWhenCovered { return .covered }
        return nil
    }
}
