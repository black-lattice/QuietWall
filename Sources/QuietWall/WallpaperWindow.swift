import AppKit
import AVFoundation

final class WallpaperWindow: NSWindow {
    private var playerLayer: AVPlayerLayer?

    init(screen: NSScreen, player: AVPlayer?, poster: CGImage?, displayMode: WallpaperDisplayMode) {
        super.init(contentRect: screen.frame, styleMask: .borderless,
                   backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        backgroundColor = .black
        hasShadow = false
        let view = WallpaperView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer?.contents = poster
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.layer?.masksToBounds = true
        if let player {
            let playerLayer = AVPlayerLayer()
            playerLayer.player = player
            playerLayer.frame = view.bounds
            playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            view.layer?.addSublayer(playerLayer)
            self.playerLayer = playerLayer
        }
        contentView = view
        setFrame(screen.frame, display: true)
        setDisplayMode(displayMode)
        orderBack(nil)
    }

    func setDisplayMode(_ mode: WallpaperDisplayMode) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentView?.layer?.contentsGravity = mode.imageGravity
        playerLayer?.videoGravity = mode.videoGravity
        CATransaction.commit()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class WallpaperView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
