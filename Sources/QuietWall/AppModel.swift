import AppKit
import Combine
import QuietWallCore
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published var wallpaper: WallpaperAsset?
    @Published var isLoading = false
    @Published var isPlaying = false
    @Published var status = "请先选择图片或视频"
    @Published var pausedForLowPower = false
    @Published var errorMessage: String?
    @Published var settingsPage: SettingsPage = .wallpapers
    @Published var wallpaperSource: WallpaperSource = .local
    let history = WallpaperHistory.shared
    let library = WallpaperLibrary.shared
    let displayPreferences: WallpaperDisplayPreferences
    var restoringDisplayMode = false
    let rotation: WallpaperRotation
    let automation: WallpaperAutomation
    @Published var independentDisplay = false
    @Published var displayKey: String?
    var cacheIsInUse: ((URL) -> Bool)?
    var targetScreen: NSScreen? { engine.targetScreens.first }
    @Published var pauseOnBattery: Bool { didSet { saveOptions(); refresh() } }
    @Published var pauseOnLowPower: Bool { didSet { saveOptions(); refresh() } }
    @Published var pauseWhenCovered: Bool { didSet { saveOptions(); refresh() } }
    @Published var coverageThreshold: Double { didSet { saveOptions(); refresh() } }
    @Published var displayMode: WallpaperDisplayMode {
        didSet {
            saveOptions()
            engine.setDisplayMode(displayMode)
            if !restoringDisplayMode, let wallpaper {
                displayPreferences.set(displayMode, for: wallpaper.sourceURL ?? wallpaper.url)
            }
        }
    }
    @Published var allScreens: Bool {
        didSet { saveOptions(); engine.setAllScreens(allScreens); refresh() }
    }
    @Published var manuallyPaused: Bool
    @Published var loginEnabled = false
    @Published var loginNeedsApproval = false

    let defaults: UserDefaults
    let engine: WallpaperEngine
    private let monitor = SystemMonitor()
    private var timer: Timer?
    var loadTask: Task<Void, Never>?
    var loadID = UUID()
    var playbackFailed = false

    init(defaults: UserDefaults = .standard, displayKey: String? = nil) {
        self.defaults = defaults
        self.displayKey = displayKey
        independentDisplay = displayKey != nil
        engine = WallpaperEngine(displayKey: displayKey)
        rotation = WallpaperRotation(defaults: defaults)
        automation = WallpaperAutomation(defaults: defaults)
        displayPreferences = WallpaperDisplayPreferences(defaults: defaults)
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
        engine.onScreensChanged = { [weak self] in
            self?.objectWillChange.send()
            self?.refresh()
            self?.rotation.resume()
            self?.automation.resume()
        }
        monitor.onChange = { [weak self] in
            self?.refresh()
            self?.rotation.resume()
            self?.automation.resume()
        }
        rotation.canRotate = { [weak self] in
            guard let self else { return false }
            return !self.isLoading && self.targetScreen != nil && !self.engine.targetScreens.allSatisfy(DisplayIdentity.isAsleep) && !self.monitor.sleeping && !self.monitor.locked && !self.monitor.sessionInactive
        }
        rotation.favoriteEntries = { [weak self] in self?.library.favorites.entries ?? [] }
        rotation.apply = { [weak self] asset in try self?.applyWallpaper(asset) }
        rotation.manualSelection = { [weak self] in self?.automation.disableForManualSelection() }
        automation.canApply = { [weak self] in self?.rotation.canRotate() ?? false }
        automation.apply = { [weak self] target in
            guard let self else { return }
            do {
                let url = try target.resolve()
                if target.isFolder { try self.rotation.chooseFolder(url) }
                else { self.rotation.setEnabled(false); self.loadWallpaper(url) }
            } catch { self.errorMessage = "无法应用定时壁纸：\(error.localizedDescription)" }
        }
        monitor.start()
        refreshLoginStatus()
        restoreWallpaper()
        rotation.resume()
        automation.start()
    }

    func loadLocalWallpaper(_ address: String) throws {
        automation.disableForManualSelection()
        let url = try LocalWallpaper.url(from: address)
        rotation.setEnabled(false)
        loadWallpaper(url)
    }

    func loadRemoteWallpaper(_ address: String) throws {
        automation.disableForManualSelection()
        let url = try RemoteWallpaper.parseURL(address)
        rotation.setEnabled(false)
        loadWallpaper(url)
    }

    func cancelLoading() {
        automation.disableForManualSelection()
        rotation.setEnabled(false)
        loadTask?.cancel()
        loadID = UUID()
        isLoading = false
    }

    func useHistory(_ entry: WallpaperHistoryEntry) {
        automation.disableForManualSelection()
        rotation.setEnabled(false)
        do {
            if let sourceURL = entry.sourceURL {
                loadWallpaper(sourceURL, cachedURL: try? entry.resolvedFileURL())
            } else {
                loadWallpaper(try entry.resolvedFileURL())
            }
        } catch { errorMessage = "历史壁纸无法访问，请重新选择原文件。" }
    }

    func toggleFavorite(_ entry: WallpaperHistoryEntry) {
        do {
            try library.toggle(entry)
            if !library.contains(entry) { removeUnusedCache(entry.fileURL) }
        }
        catch { errorMessage = "无法修改收藏：\(error.localizedDescription)" }
    }

    func removeHistory(_ entry: WallpaperHistoryEntry) {
        do {
            try history.remove(entry)
            removeUnusedCache(entry.fileURL)
        } catch { errorMessage = "无法删除历史记录：\(error.localizedDescription)" }
    }

    func removeUnusedCache(_ url: URL) {
        guard wallpaper?.url != url, !history.containsFile(url), !library.favorites.containsFile(url), cacheIsInUse?(url) != true else { return }
        RemoteWallpaper.removeCachedFile(url)
    }

    func togglePause() {
        guard wallpaper?.isVideo == true else { return }
        manuallyPaused.toggle()
        defaults.set(manuallyPaused, forKey: "manuallyPaused")
        refresh()
    }

    func removeWallpaper() {
        automation.disableForManualSelection()
        rotation.setEnabled(false)
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
        automation.shutdown()
        rotation.shutdown()
        loadTask?.cancel()
        timer?.invalidate()
        monitor.stop()
        engine.shutdown()
    }

    func setTargetDisplay(_ key: String?) {
        displayKey = key
        independentDisplay = key != nil
        engine.setTargetDisplay(key)
        refresh()
        rotation.resume()
        automation.resume()
    }

    func refresh() {
        var policy = PlaybackPolicy()
        policy.hasVideo = wallpaper?.isVideo == true && targetScreen != nil
        policy.manuallyPaused = manuallyPaused
        policy.sleeping = monitor.sleeping || engine.targetScreens.allSatisfy(DisplayIdentity.isAsleep)
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
