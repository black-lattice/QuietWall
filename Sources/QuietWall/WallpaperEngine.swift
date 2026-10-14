import AppKit
import AVFoundation
import QuietWallCore

@MainActor
final class WallpaperEngine {
    var onError: ((String) -> Void)?
    var onScreensChanged: (() -> Void)?
    private(set) var windows: [WallpaperWindow] = []
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var failureObservation: NSKeyValueObservation?
    private var screenObserver: NSObjectProtocol?
    private var video: VideoAsset?
    private var allScreens = false
    private var generation = UUID()

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.rebuildWindows()
                self?.onScreensChanged?()
            }
        }
    }

    func install(_ video: VideoAsset, allScreens: Bool) {
        clear()
        self.video = video
        self.allScreens = allScreens
        let player = AVQueuePlayer()
        player.isMuted = true
        player.allowsExternalPlayback = false
        player.preventsDisplaySleepDuringVideoPlayback = false
        let item = AVPlayerItem(asset: video.asset)
        let looper = AVPlayerLooper(player: player, templateItem: item)
        self.player = player
        self.looper = looper
        let generation = self.generation
        failureObservation = looper.observe(\.status, options: [.initial, .new]) { [weak self] looper, _ in
            guard looper.status == .failed else { return }
            let message = looper.error?.localizedDescription ?? "视频播放失败，请重新选择视频。"
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                self.onError?(message)
            }
        }
        rebuildWindows()
    }

    func setAllScreens(_ enabled: Bool) {
        allScreens = enabled
        rebuildWindows()
    }

    func setPlaying(_ playing: Bool) {
        if playing {
            if player?.rate == 0 { player?.play() }
        } else {
            player?.pause()
        }
    }

    /// Queries rectangle metadata only; never captures pixels or asks for screen recording.
    func desktopIsCovered(threshold: Double) -> Bool {
        guard !windows.isEmpty,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                   kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first else { return false }
        let wallpaperIDs = Set(windows.map(\.windowNumber))
        let rects: [CGRect] = list.compactMap { item in
            guard let layer = item[kCGWindowLayer as String] as? Int,
                  let alpha = item[kCGWindowAlpha as String] as? Double,
                  let windowID = item[kCGWindowNumber as String] as? Int,
                  DesktopCoverage.canCoverDesktop(layer: layer, alpha: alpha,
                                                   isWallpaper: wallpaperIDs.contains(windowID)),
                  let bounds = item[kCGWindowBounds as String] as? [String: Any] else { return nil }
            return CGRect(dictionaryRepresentation: bounds as CFDictionary)
        }
        return targetScreens.allSatisfy { screen in
            // Exclude the menu bar and Dock so a maximized window can count as covering the desktop.
            let visible = screen.visibleFrame
            let quartz = CGRect(x: visible.minX, y: primary.frame.maxY - visible.maxY,
                                width: visible.width, height: visible.height)
            return DesktopCoverage.isCovered(quartz, by: rects, threshold: threshold)
        }
    }

    func clear() {
        generation = UUID()
        failureObservation = nil
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player?.removeAllItems()
        player = nil
        video = nil
        windows.forEach { $0.close() }
        windows.removeAll()
    }

    func shutdown() {
        clear()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
    }

    private var targetScreens: [NSScreen] {
        allScreens ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
    }

    private func rebuildWindows() {
        windows.forEach { $0.close() }
        windows.removeAll()
        guard let player, let video else { return }
        windows = targetScreens.map { WallpaperWindow(screen: $0, player: player, poster: video.poster) }
    }
}
