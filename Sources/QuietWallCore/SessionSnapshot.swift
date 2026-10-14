import Foundation

/// A missing session/display query must not silently allow background playback.
public struct SessionSnapshot {
    public let sessionInactive: Bool
    public let locked: Bool
    public let displaySleeping: Bool

    public init(onConsole: Bool?, loginDone: Bool?, lockFlag: Bool?, displaysAsleep: [Bool]?) {
        sessionInactive = onConsole != true || loginDone != true
        // macOS adds the lock flag when locked; it is normally absent when unlocked.
        // This optional key is not a public contract, unlike console/login identity.
        locked = lockFlag ?? false
        displaySleeping = displaysAsleep.map { $0.isEmpty || $0.allSatisfy { $0 } } ?? true
    }
}
