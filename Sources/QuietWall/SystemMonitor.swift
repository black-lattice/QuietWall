import AppKit
import IOKit.ps

@MainActor
final class SystemMonitor {
    var onChange: (() -> Void)?
    private var displaySleeping = false
    private var systemSleeping = false
    var sleeping: Bool { displaySleeping || systemSleeping }
    private(set) var locked = false
    private(set) var sessionInactive = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var powerSource: CFRunLoopSource?

    var onBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else {
            return true // Unknown power state conservatively pauses playback.
        }
        return source as String != kIOPSACPowerValue
    }

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.displaySleeping = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.displaySleeping = false }
        observe(workspace, NSWorkspace.willSleepNotification) { $0.systemSleeping = true }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.systemSleeping = false }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionInactive = true }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionInactive = false }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { _ in }
        observe(workspace, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) { _ in }
        observe(.default, .NSProcessInfoPowerStateDidChange) { _ in }
        observe(.default, ProcessInfo.thermalStateDidChangeNotification) { _ in }
        // Distributed lock notifications supplement workspace session/sleep events.
        observe(.distributed(), .init("com.apple.screenIsLocked")) { $0.locked = true }
        observe(.distributed(), .init("com.apple.screenIsUnlocked")) { $0.locked = false }
        let context = Unmanaged.passUnretained(self).toOpaque()
        powerSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<SystemMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in monitor.onChange?() }
        }, context)?.takeRetainedValue()
        if let powerSource { CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes) }
    }

    func stop() {
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        if let powerSource { CFRunLoopSourceInvalidate(powerSource) }
        powerSource = nil
        onChange = nil
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         change: @escaping @MainActor (SystemMonitor) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                change(self)
                self.onChange?()
            }
        }
        observers.append((center, token))
    }
}

private extension NotificationCenter {
    static func distributed() -> NotificationCenter { DistributedNotificationCenter.default() }
}
