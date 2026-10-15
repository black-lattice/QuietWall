import SwiftUI

struct WallpaperHistoryView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var history: WallpaperHistory
    var favoritesOnly = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label(favoritesOnly ? "我的收藏" : "最近使用", systemImage: favoritesOnly ? "star" : "clock.arrow.circlepath").font(.headline)
                Text(favoritesOnly ? "\(history.entries.count) 张" : "\(history.entries.count) / \(WallpaperHistory.limit)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Text("点击缩略图切换壁纸").font(.caption).foregroundStyle(.secondary)
            }
            .help(favoritesOnly ? "收藏独立保存，没有 50 条限制；本地原文件请保留。" : "保留最近 \(WallpaperHistory.limit) 张壁纸。本地壁纸需要保留原文件。")
            if let error = history.loadError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            if history.entries.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath").font(.title2).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("喜欢的壁纸，都留在这里").font(.callout)
                        Text(favoritesOnly ? "点击历史卡片上的星标收藏壁纸，不受历史条数限制。" : "使用过的图片和视频会自动保存到历史。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(24).frame(maxWidth: .infinity)
                .background(Color.primary.opacity(0.035))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 196, maximum: 280), spacing: 16)],
                          alignment: .leading, spacing: 18) {
                    ForEach(history.entries) { entry in
                        WallpaperHistoryCard(model: model, entry: entry, favoritesOnly: favoritesOnly)
                    }
                }
            }
        }
    }
}

private struct WallpaperHistoryCard: View {
    @ObservedObject var model: AppModel
    let entry: WallpaperHistoryEntry
    var favoritesOnly: Bool
    @ObservedObject private var library = WallpaperLibrary.shared
    @State private var isHovered = false

    private var isCurrent: Bool { model.wallpaper.map { entry.matches($0) } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { model.useHistory(entry) } label: {
                VStack(alignment: .leading, spacing: 10) {
                    GeometryReader { geometry in
                        ZStack {
                            Color.black
                            if let data = entry.thumbnail, let image = NSImage(data: data) {
                                Image(nsImage: image).resizable().scaledToFit()
                            } else {
                                Image(systemName: entry.isVideo ? "film" : "photo")
                                    .font(.title).foregroundStyle(.white)
                            }
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .topTrailing) {
                            if isCurrent {
                                Label("当前", systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.medium)).foregroundStyle(.white)
                                    .padding(.horizontal, 8).padding(.vertical, 5)
                                    .background(.black.opacity(0.7), in: Capsule()).padding(7)
                            }
                        }
                    }
                    .aspectRatio(16.0 / 10.0, contentMode: .fit)
                    Text(entry.name).font(.system(size: 12, weight: .medium))
                        .lineLimit(1).truncationMode(.middle)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(WallpaperThumbnailButtonStyle()).disabled(model.isLoading)
            .accessibilityLabel("\(isCurrent ? "当前壁纸" : "使用壁纸")：\(entry.name)")
            .help("\(entry.name)\n\(entry.details)")
            HStack(spacing: 4) {
                Text("\(entry.sourceURL == nil ? "本地" : "网络") · \(entry.isVideo ? "视频" : "图片")")
                    .font(.caption).foregroundStyle(.secondary)
                    .help("最近使用：\(entry.lastUsed.formatted(date: .abbreviated, time: .shortened))")
                Spacer(minLength: 0)
                Button { model.toggleFavorite(entry) } label: {
                    Image(systemName: library.contains(entry) ? "star.fill" : "star")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(library.contains(entry) ? "取消收藏" : "收藏壁纸")
                Button {
                    if favoritesOnly { model.toggleFavorite(entry) } else { model.removeHistory(entry) }
                } label: {
                    Image(systemName: "trash").font(.system(size: 11)).frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .disabled(model.isLoading)
                .accessibilityLabel("\(favoritesOnly ? "取消收藏" : "从历史移除")：\(entry.name)")
                .help(favoritesOnly ? "取消收藏，不删除原文件或历史" : "从历史移除，不删除本地原文件；未使用的网络缓存会清理")
            }
            .padding(.top, 4)
            Text(entry.lastUsed, format: .dateTime.month().day().hour().minute())
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .wallpaperSurface()
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(isCurrent ? WallpaperTheme.accent : Color.primary.opacity(isHovered ? 0.25 : 0),
                          lineWidth: isCurrent ? 2 : 1))
        .onHover { isHovered = $0 }
    }
}
