import SwiftUI

@main
struct QuietWallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            WallpaperMenu(model: delegate.model, showSettings: delegate.showSettings)
        } label: {
            WallpaperMenuIcon(model: delegate.model)
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
        if UserDefaults.standard.data(forKey: "wallpaperBookmark") == nil &&
            UserDefaults.standard.data(forKey: "videoBookmark") == nil &&
            UserDefaults.standard.string(forKey: "wallpaperRemoteURL") == nil { showSettings() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) { model.shutdown() }

    func showSettings() {
        model.refreshLoginStatus()
        if settingsWindow == nil {
            let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "QuietWall"
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 900, height: 680)
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

private final class SettingsWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown,
           let editor = firstResponder as? NSTextView, editor.isEditable,
           !editor.visibleRect.contains(editor.convert(event.locationInWindow, from: nil)) {
            // End editing before dispatch so another input can still receive this click.
            makeFirstResponder(nil)
        }
        super.sendEvent(event)
    }
}

private struct WallpaperMenuIcon: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Image(nsImage: icon)
            .renderingMode(.original)
            .accessibilityLabel("QuietWall：\(model.errorMessage ?? model.status)")
            .help(model.errorMessage ?? model.status)
    }

    private var icon: NSImage {
        let color: NSColor = (model.isPlaying || model.wallpaper?.isVideo == false) ? .systemBlue : .systemGray
        let image = NSImage(systemSymbolName: "leaf", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(paletteColors: [color])) ?? NSImage(size: NSSize(width: 18, height: 18))
        // Preserve the status color instead of letting the menu bar tint a template image.
        image.isTemplate = false
        return image
    }
}

private struct WallpaperMenu: View {
    @ObservedObject var model: AppModel
    let showSettings: () -> Void

    var body: some View {
        Text(model.status)
        if model.pausedForLowPower {
            Button("允许低电量模式下播放") { model.pauseOnLowPower = false }
        }
        if let wallpaper = model.wallpaper { Text(wallpaper.displayName) }
        if let error = model.errorMessage {
            Menu("操作失败 · 查看详情") {
                Text(error)
                Button("打开设置处理…", action: showSettings)
                Button("忽略此提示") { model.errorMessage = nil }
            }
        }
        Divider()
        Picker("显示方式", selection: $model.displayMode) {
            ForEach(WallpaperDisplayMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        Button(model.manuallyPaused ? "恢复自动播放" : "手动暂停") { model.togglePause() }
            .disabled(model.wallpaper?.isVideo != true)
        Button("选择本地壁纸…") {
            model.settingsPage = .sources
            model.wallpaperSource = .local
            showSettings()
        }
        Button("添加网络壁纸…") {
            model.settingsPage = .sources
            model.wallpaperSource = .remote
            showSettings()
        }
        if model.isLoading { Button("取消加载", action: model.cancelLoading) }
        Button("壁纸历史…") {
            model.settingsPage = .wallpapers
            showSettings()
        }
        Button("设置…") {
            model.settingsPage = .preferences
            showSettings()
        }.keyboardShortcut(",")
        Divider()
        Button("退出 QuietWall") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
