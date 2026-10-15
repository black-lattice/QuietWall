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
                preview
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("壁纸信息").font(.caption).foregroundStyle(.secondary)
                        Text(model.wallpaper?.displayName ?? "还没有设置壁纸")
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1).truncationMode(.middle)
                            .help(model.wallpaper?.displayName ?? "从上方添加图片或视频")
                        Text(model.wallpaper?.details ?? "添加喜欢的图片或视频，开始布置桌面。")
                            .font(.caption).foregroundStyle(.secondary)
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

    private var preview: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let wallpaper = model.wallpaper {
                    previewImage(wallpaper.poster)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled").font(.system(size: 30))
                        Text("你的下一幅风景").font(.callout)
                    }
                    .foregroundStyle(.white.opacity(0.65))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped().clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(height: 280)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.wallpaper.map {
            "壁纸预览：\($0.displayName)，\($0.details)，\(model.displayMode.title)"
        } ?? "尚未选择壁纸")
    }

    @ViewBuilder
    private func previewImage(_ image: CGImage) -> some View {
        switch model.displayMode {
        case .fill: Image(decorative: image, scale: 1).resizable().scaledToFill()
        case .fit: Image(decorative: image, scale: 1).resizable().scaledToFit()
        case .stretch: Image(decorative: image, scale: 1).resizable()
        }
    }
}
