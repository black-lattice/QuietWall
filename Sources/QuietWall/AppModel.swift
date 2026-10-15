import AppKit
import Combine
import QuietWallCore
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var wallpaper: WallpaperAsset?
    @Published private(set) var isLoading = false
    @Published private(set) var isPlaying = false
    @Published private(set) var status = "请先选择图片或视频"
    @Published private(set) var pausedForLowPower = false
    @Published var errorMessage: String?
    @Published var settingsPage: SettingsPage = .wallpapers
    @Published var wallpaperSource: WallpaperSource = .local
    let history = WallpaperHistory()
    @Published var pauseOnBattery: Bool { didSet { saveOptions(); refresh() } }
    @Published var pauseOnLowPower: Bool { didSet { saveOptions(); refresh() } }
    @Published var pauseWhenCovered: Bool { didSet { saveOptions(); refresh() } }
    @Published var coverageThreshold: Double { didSet { saveOptions(); refresh() } }
    @Published var displayMode: WallpaperDisplayMode {
        didSet { saveOptions(); engine.setDisplayMode(displayMode) }
    }
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
        displayMode = WallpaperDisplayMode(rawValue: defaults.string(forKey: "displayMode") ?? "") ?? .fill
        allScreens = defaults.bool(forKey: "allScreens")
        manuallyPaused = defaults.bool(forKey: "manuallyPaused")
        engine.setDisplayMode(displayMode)
        engine.onError = { [weak self] message in
            self?.playbackFailed = true
            self?.errorMessage = message
            self?.refresh()
        }
        engine.onScreensChanged = { [weak self] in self?.refresh() }
        monitor.onChange = { [weak self] in self?.refresh() }
        monitor.start()
        refreshLoginStatus()
        restoreWallpaper()
    }

    func loadLocalWallpaper(_ address: String) throws {
        loadWallpaper(try LocalWallpaper.url(from: address))
    }

    func loadRemoteWallpaper(_ address: String) throws {
        let url = try RemoteWallpaper.parseURL(address)
        loadWallpaper(url)
    }

    func cancelLoading() {
        loadTask?.cancel()
        loadID = UUID()
        isLoading = false
    }

    func useHistory(_ entry: WallpaperHistoryEntry) {
        do {
            if let sourceURL = entry.sourceURL {
                loadWallpaper(sourceURL, cachedURL: try? entry.resolvedFileURL())
            } else {
                loadWallpaper(try entry.resolvedFileURL())
            }
        } catch { errorMessage = "历史壁纸无法访问，请重新选择原文件。" }
    }

    func removeHistory(_ entry: WallpaperHistoryEntry) {
        do {
            try history.remove(entry)
            removeUnusedCache(entry.fileURL)
        } catch { errorMessage = "无法删除历史记录：\(error.localizedDescription)" }
    }

    private func removeUnusedCache(_ url: URL) {
        guard wallpaper?.url != url, !history.containsFile(url) else { return }
        RemoteWallpaper.removeCachedFile(url)
    }

    func togglePause() {
        guard wallpaper?.isVideo == true else { return }
        manuallyPaused.toggle()
        defaults.set(manuallyPaused, forKey: "manuallyPaused")
        refresh()
    }

    func removeWallpaper() {
        loadTask?.cancel()
        loadID = UUID()
        isLoading = false
        engine.clear()
        let previousURL = wallpaper?.url
        wallpaper = nil
        if let previousURL { removeUnusedCache(previousURL) }
        playbackFailed = false
        errorMessage = nil
        defaults.removeObject(forKey: "wallpaperRemoteURL")
        defaults.removeObject(forKey: "wallpaperBookmark")
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

    private func loadWallpaper(_ url: URL, cachedURL: URL? = nil) {
        loadTask?.cancel()
        let id = UUID()
        loadID = id
        isLoading = true
        errorMessage = nil
        loadTask = Task { [weak self] in
            do {
                let loaded = try await url.isFileURL
                    ? WallpaperAsset.load(url) : RemoteWallpaper.load(url, cachedURL: cachedURL)
                var installed = false
                defer {
                    if !installed && loaded.sourceURL != nil && loaded.url != cachedURL {
                        self?.removeUnusedCache(loaded.url)
                    }
                }
                try Task.checkCancellation()
                // Keep the previous wallpaper if validation or bookmark creation fails.
                let bookmark = try loaded.url.bookmarkData(options: .minimalBookmark,
                                                    includingResourceValuesForKeys: nil, relativeTo: nil)
                guard let self, self.loadID == id else { return }
                let historyUpdate = self.history.recordForUse(loaded, bookmark: bookmark)
                self.playbackFailed = false
                let previousURL = self.wallpaper?.url
                self.engine.install(loaded, allScreens: self.allScreens)
                self.wallpaper = loaded
                installed = true
                if let previousURL { self.removeUnusedCache(previousURL) }
                if let cachedURL { self.removeUnusedCache(cachedURL) }
                historyUpdate.discarded.forEach { self.removeUnusedCache($0.fileURL) }
                self.defaults.set(loaded.sourceURL?.absoluteString, forKey: "wallpaperRemoteURL")
                self.defaults.set(bookmark, forKey: "wallpaperBookmark")
                self.defaults.removeObject(forKey: "videoBookmark")
                self.isLoading = false
                self.errorMessage = historyUpdate.warning
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

    private func restoreWallpaper() {
        if let address = defaults.string(forKey: "wallpaperRemoteURL"),
           let remoteURL = try? RemoteWallpaper.parseURL(address) {
            var stale = false
            let cachedURL = defaults.data(forKey: "wallpaperBookmark").flatMap {
                try? URL(resolvingBookmarkData: $0, options: .withoutUI,
                         relativeTo: nil, bookmarkDataIsStale: &stale)
            }
            loadWallpaper(remoteURL, cachedURL: cachedURL)
            return
        }
        guard let data = defaults.data(forKey: "wallpaperBookmark")
            ?? defaults.data(forKey: "videoBookmark") else { return }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: .withoutUI,
                              relativeTo: nil, bookmarkDataIsStale: &stale)
            loadWallpaper(url)
        } catch {
            errorMessage = "上次的壁纸已移动或无法访问，请重新选择。"
        }
    }

    private func refresh() {
        var policy = PlaybackPolicy()
        policy.hasVideo = wallpaper?.isVideo == true
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
        let message: String
        if let wallpaper, !wallpaper.isVideo {
            message = "正在显示 · 静态壁纸"
        } else if wallpaper == nil {
            message = "请先选择图片或视频"
        } else {
            message = playbackFailed ? "播放失败，请重新选择视频" : (policy.pauseReason?.rawValue ?? "正在播放 · 静音循环")
        }
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
        defaults.set(displayMode.rawValue, forKey: "displayMode")
        defaults.set(allScreens, forKey: "allScreens")
    }
}
