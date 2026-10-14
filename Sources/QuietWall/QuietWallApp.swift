import SwiftUI

@main
struct QuietWallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("QuietWall", systemImage: "leaf") {
            WallpaperMenu(model: delegate.model, showSettings: delegate.showSettings)
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if UserDefaults.standard.data(forKey: "videoBookmark") == nil { showSettings() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) { model.shutdown() }

    func showSettings() {
        model.refreshLoginStatus()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 700),
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "QuietWall · 静境壁纸"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

private struct WallpaperMenu: View {
    @ObservedObject var model: AppModel
    let showSettings: () -> Void

    var body: some View {
        Text(model.status)
        if let video = model.video { Text(video.url.lastPathComponent) }
        Divider()
        Button(model.manuallyPaused ? "恢复自动播放" : "手动暂停") { model.togglePause() }
            .disabled(model.video == nil)
        Button("选择视频…") { model.chooseVideo() }.disabled(model.isLoading)
        Button("设置…", action: showSettings).keyboardShortcut(",")
        Divider()
        Button("退出 QuietWall") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
