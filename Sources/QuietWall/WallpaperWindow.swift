import AppKit
import AVFoundation

final class WallpaperWindow: NSWindow {
    init(screen: NSScreen, player: AVPlayer?, poster: CGImage?) {
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
        view.layer?.contentsGravity = .resizeAspectFill
        view.layer?.masksToBounds = true
        if let player {
            let playerLayer = AVPlayerLayer()
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.frame = view.bounds
            playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            view.layer?.addSublayer(playerLayer)
        }
        contentView = view
        setFrame(screen.frame, display: true)
        orderBack(nil)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class WallpaperView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
