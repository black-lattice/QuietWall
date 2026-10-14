import AppKit
import Combine
import QuietWallCore
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var video: VideoAsset?
    @Published private(set) var isLoading = false
    @Published private(set) var isPlaying = false
    @Published private(set) var status = PauseReason.noVideo.rawValue
    @Published private(set) var pausedForLowPower = false
    @Published var errorMessage: String?
    @Published var pauseOnBattery: Bool { didSet { saveOptions(); refresh() } }
    @Published var pauseOnLowPower: Bool { didSet { saveOptions(); refresh() } }
    @Published var pauseWhenCovered: Bool { didSet { saveOptions(); refresh() } }
    @Published var coverageThreshold: Double { didSet { saveOptions(); refresh() } }
    @Published var allScreens: Bool {
        didSet { saveOptions(); engine.setAllScreens(allScreens); refresh() }
    }
    @Published private(set) var manuallyPaused: Bool
    @Published private(set) var loginEnabled = false
    @Published private(set) var loginNeedsApproval = false

    private let defaults = UserDefaults.standard
    private let engine = WallpaperEngine()
    private let monitor = SystemMonitor()
    private var timer: Timer?
    private var loadTask: Task<Void, Never>?
    private var loadID = UUID()
    private var playbackFailed = false

    init() {
        pauseOnBattery = defaults.object(forKey: "pauseOnBattery") as? Bool ?? true
        pauseOnLowPower = defaults.object(forKey: "pauseOnLowPower") as? Bool ?? true
        pauseWhenCovered = defaults.object(forKey: "pauseWhenCovered") as? Bool ?? true
        coverageThreshold = DesktopCoverage.savedThreshold(defaults.double(forKey: "coverageThreshold"))
        allScreens = defaults.bool(forKey: "allScreens")
        manuallyPaused = defaults.bool(forKey: "manuallyPaused")
        engine.onError = { [weak self] message in
            self?.playbackFailed = true
            self?.errorMessage = message
            self?.refresh()
        }
        engine.onScreensChanged = { [weak self] in self?.refresh() }
        monitor.onChange = { [weak self] in self?.refresh() }
        monitor.start()
        refreshLoginStatus()
        restoreVideo()
    }

    func chooseVideo() {
        let panel = NSOpenPanel()
        panel.title = "选择本地壁纸视频"
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie, .movie]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.loadVideo(url) }
        }
    }

    func togglePause() {
        manuallyPaused.toggle()
        defaults.set(manuallyPaused, forKey: "manuallyPaused")
        refresh()
    }

    func removeVideo() {
        loadTask?.cancel()
        loadID = UUID()
        isLoading = false
        engine.clear()
        video = nil
        playbackFailed = false
        errorMessage = nil
        defaults.removeObject(forKey: "videoBookmark")
        refresh()
    }

    func setLoginEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            errorMessage = "无法修改开机启动：\(error.localizedDescription)。请先将 QuietWall.app 放入应用程序文件夹。"
        }
        refreshLoginStatus()
    }

    func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        loginEnabled = status == .enabled || status == .requiresApproval
        loginNeedsApproval = status == .requiresApproval
    }

    func shutdown() {
        loadTask?.cancel()
        timer?.invalidate()
        monitor.stop()
        engine.shutdown()
    }

    private func loadVideo(_ url: URL) {
        loadTask?.cancel()
        let id = UUID()
        loadID = id
        isLoading = true
        errorMessage = nil
        loadTask = Task { [weak self] in
            do {
                let loaded = try await VideoAsset.load(url)
                try Task.checkCancellation()
                // Keep the previous wallpaper if validation or bookmark creation fails.
                let bookmark = try url.bookmarkData(options: .minimalBookmark,
                                                    includingResourceValuesForKeys: nil, relativeTo: nil)
                guard let self, self.loadID == id else { return }
                self.playbackFailed = false
                self.engine.install(loaded, allScreens: self.allScreens)
                self.video = loaded
                self.defaults.set(bookmark, forKey: "videoBookmark")
                self.isLoading = false
                self.refresh()
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.loadID == id else { return }
                self.isLoading = false
                self.errorMessage = error.localizedDescription
                self.refresh()
            }
        }
    }

    private func restoreVideo() {
        guard let data = defaults.data(forKey: "videoBookmark") else { return }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: .withoutUI,
                              relativeTo: nil, bookmarkDataIsStale: &stale)
            loadVideo(url)
        } catch {
            errorMessage = "上次的视频已移动或无法访问，请重新选择。"
        }
    }

    private func refresh() {
        var policy = PlaybackPolicy()
        policy.hasVideo = video != nil
        policy.manuallyPaused = manuallyPaused
        policy.sleeping = monitor.sleeping
        policy.locked = monitor.locked || monitor.sessionInactive
        policy.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        policy.pauseOnLowPower = pauseOnLowPower
        policy.onBattery = monitor.onBattery
        policy.pauseOnBattery = pauseOnBattery
        let thermal = ProcessInfo.processInfo.thermalState
        policy.thermallyLimited = thermal == .serious || thermal == .critical
        policy.reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        policy.pauseWhenCovered = pauseWhenCovered
        let canCheckCoverage = policy.pauseReason == nil && !playbackFailed
        if canCheckCoverage && pauseWhenCovered {
            policy.covered = engine.desktopIsCovered(threshold: coverageThreshold)
        }
        let playing = policy.pauseReason == nil && !playbackFailed
        engine.setPlaying(playing)
        let pausedForLowPower = !playbackFailed && policy.pauseReason == .lowPower
        if self.pausedForLowPower != pausedForLowPower { self.pausedForLowPower = pausedForLowPower }
        if isPlaying != playing { isPlaying = playing }
        let message = playbackFailed ? "播放失败，请重新选择视频" : (policy.pauseReason?.rawValue ?? "正在播放 · 静音循环")
        if status != message { status = message }
        updateTimer(enabled: canCheckCoverage && pauseWhenCovered)
    }

    private func updateTimer(enabled: Bool) {
        if enabled && timer == nil {
            let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            timer.tolerance = 1
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if !enabled {
            timer?.invalidate()
            timer = nil
        }
    }

    private func saveOptions() {
        defaults.set(pauseOnBattery, forKey: "pauseOnBattery")
        defaults.set(pauseOnLowPower, forKey: "pauseOnLowPower")
        defaults.set(pauseWhenCovered, forKey: "pauseWhenCovered")
        defaults.set(coverageThreshold, forKey: "coverageThreshold")
        defaults.set(allScreens, forKey: "allScreens")
    }
}
