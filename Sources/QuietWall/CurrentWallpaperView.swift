import SwiftUI

struct CurrentWallpaperView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("当前壁纸", systemImage: "desktopcomputer").font(.headline)
                Spacer()
                Text(model.wallpaper?.isVideo == true ? "视频壁纸" : "静态壁纸")
                    .font(.caption).foregroundStyle(.secondary)
                    .opacity(model.wallpaper == nil ? 0 : 1)
            }
            HStack(alignment: .top, spacing: 24) {
                WallpaperPreviewView(model: model)
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("壁纸信息").font(.caption).foregroundStyle(.secondary)
                        Text(model.wallpaper?.displayName ?? "还没有设置壁纸")
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1).truncationMode(.middle)
                            .help(model.wallpaper?.displayName ?? "在“壁纸来源”中添加图片或视频")
                        Text(model.wallpaper?.details ?? "添加喜欢的图片或视频，开始布置桌面。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if model.wallpaper == nil {
                        Button("添加壁纸") { model.settingsPage = .sources }
                            .buttonStyle(.borderedProminent)
                    }
                    PlaybackStatusView(model: model)
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("显示方式").font(.callout.weight(.medium))
                        Picker("显示方式", selection: $model.displayMode) {
                            ForEach(WallpaperDisplayMode.allCases) { mode in Text(mode.title).tag(mode) }
                        }
                        .pickerStyle(.segmented).labelsHidden()
                        Text(model.displayMode.explanation)
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Toggle("应用到所有显示器", isOn: $model.allScreens).font(.callout)
                    }
                    HStack(spacing: 8) {
                        if model.wallpaper?.isVideo == true {
                            Button(model.manuallyPaused ? "恢复自动播放" : "手动暂停", action: model.togglePause)
                        }
                        Button("移除壁纸", action: model.removeWallpaper)
                            .disabled(model.wallpaper == nil)
                            .help("恢复系统壁纸，保留历史及本地原文件")
                    }
                    .controlSize(.small)
                    if let warning = model.wallpaper?.warning {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(width: 260, alignment: .leading)
            }
        }
        .padding(20).wallpaperSurface()
    }

}
