import SwiftUI

struct WallpaperSourcePreviewView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("壁纸预览", systemImage: "desktopcomputer").font(.headline)
                Spacer()
                Button("调整显示方式") { model.settingsPage = .wallpapers }
                    .controlSize(.small).disabled(model.wallpaper == nil)
            }
            WallpaperPreviewView(model: model, maximumSize: CGSize(width: 480, height: 270))
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.wallpaper?.displayName ?? "还没有设置壁纸")
                        .font(.callout.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                        .help(model.wallpaper?.displayName ?? "从右侧选择图片、视频或文件夹")
                    Text(model.wallpaper?.details ?? "选择后会应用到桌面，并在这里显示预览。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if model.wallpaper?.isVideo == true {
                    Text("视频封面预览").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                PlaybackStatusView(model: model)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20).wallpaperSurface()
    }
}

struct WallpaperPreviewView: View {
    @ObservedObject var model: AppModel
    var maximumSize: CGSize?
    private var displayAspectRatio: CGFloat {
        guard let size = model.targetScreen?.frame.size, size.width > 0, size.height > 0 else { return 16.0 / 9.0 }
        return size.width / size.height
    }

    var body: some View {
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
        .aspectRatio(displayAspectRatio, contentMode: .fit)
        .frame(maxWidth: maximumSize.map { min($0.width, $0.height * displayAspectRatio) })
        .help("按当前目标显示器比例预览")
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
