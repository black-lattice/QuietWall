import AppKit
import Combine
import QuietWallCore

struct ScheduledWallpaper: Codable, Equatable {
    let bookmark: Data
    let name: String
    let isFolder: Bool
    init(url: URL, isFolder: Bool) throws {
        bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        name = url.lastPathComponent
        self.isFolder = isFolder
    }
    func resolve() throws -> URL {
        var stale = false
        return try URL(resolvingBookmarkData: bookmark, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
    }
}

@MainActor
final class WallpaperAutomation: ObservableObject {
    struct Configuration: Codable {
        var enabled = false
        var followsAppearance = false
        var times = DayNightSchedule()
        var day: ScheduledWallpaper?
        var night: ScheduledWallpaper?
        var isReady: Bool { day != nil && night != nil && (followsAppearance || times.isValid) }
    }
    @Published private(set) var configuration = Configuration()
    @Published private(set) var message: String?
    var canApply: () -> Bool = { true }
    var apply: ((ScheduledWallpaper) -> Void)?
    private let defaults: UserDefaults
    private let now: () -> Date
    private let dark: @MainActor () -> Bool
    private var lastTarget: ScheduledWallpaper?
    private var timer: Timer?
    private var appearance: NSKeyValueObservation?
    private var observers: [NSObjectProtocol] = []

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
         dark: @escaping @MainActor () -> Bool = { NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }) {
        self.defaults = defaults
        self.now = now
        self.dark = dark
        if let data = defaults.data(forKey: "wallpaperAutomation") {
            do { configuration = try JSONDecoder().decode(Configuration.self, from: data) }
            catch { message = "无法读取定时配置，请重新设置。" }
        }
    }

    func start() {
        appearance = NSApp?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.resume() }
        }
        for name in [NSNotification.Name.NSSystemTimeZoneDidChange, .NSCalendarDayChanged,
                     NSNotification.Name("NSSystemClockDidChangeNotification")] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.resume() }
            })
        }
        resume()
    }

    func update(_ value: Configuration) {
        configuration = value
        if !configuration.isReady { configuration.enabled = false }
        lastTarget = nil
        message = nil
        if let data = try? JSONEncoder().encode(configuration) { defaults.set(data, forKey: "wallpaperAutomation") }
        resume()
    }

    func disableForManualSelection() {
        guard configuration.enabled else { return }
        var value = configuration
        value.enabled = false
        update(value)
    }

    func resume() {
        timer?.invalidate()
        timer = nil
        guard configuration.enabled, configuration.isReady else { return }
        guard canApply() else { return }
        let day = configuration.followsAppearance ? !dark() : configuration.times.isDay(at: now())
        if let target = day ? configuration.day : configuration.night, target != lastTarget, let apply {
            lastTarget = target
            apply(target)
        }
        if !configuration.followsAppearance, let next = configuration.times.nextBoundary(after: now()) {
            let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.resume() }
            }
            timer.tolerance = 1
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    func shutdown() {
        timer?.invalidate()
        timer = nil
        appearance = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }
}
