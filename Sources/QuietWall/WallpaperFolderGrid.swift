import SwiftUI
import AVFoundation
import ImageIO

struct WallpaperFolderGrid: View {
    @ObservedObject var model: AppModel
    @ObservedObject var rotation: WallpaperRotation
    @State private var files: [URL] = []
    @State private var error: String?
    @State private var revision = 0
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("文件夹壁纸", systemImage: "square.grid.2x2").font(.headline)
                Text("\(files.count) 张").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if loading { ProgressView().controlSize(.small) }
                Button("刷新") { revision += 1 }.disabled(loading)
            }
            if let error { Text(error).font(.callout).foregroundStyle(.secondary) }
            if files.isEmpty && !loading && error == nil {
                Text("文件夹中没有可用的图片或视频。").foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 16)], spacing: 16) {
                ForEach(files, id: \.self) { url in
                    FolderThumbnail(url: url, current: model.wallpaper?.url.standardizedFileURL == url.standardizedFileURL,
                                    revision: revision) { rotation.select(url) }
                        .disabled(model.isLoading || rotation.isRotating)
                }
            }
            Text("点击缩略图立即切换；自动轮换开关保持原状，并从这张继续计时。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task(id: "\(rotation.folderURL?.absoluteString ?? "")-\(revision)") {
            loading = true
            error = nil
            files = []
            do {
                if let folder = rotation.folderURL {
                    let scanned = try await WallpaperFolder.files(in: folder)
                    try Task.checkCancellation()
                    files = scanned
                }
            } catch is CancellationError { return }
            catch { self.error = "无法读取文件夹，请检查访问权限或重新选择。" }
            loading = false
        }
    }
}

private struct FolderThumbnail: View {
    let url: URL
    let current: Bool
    let revision: Int
    let select: () -> Void
    @State private var poster: CGImage?
    @State private var failed = false

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 8) {
                Color.black.overlay {
                    if let poster { Image(decorative: poster, scale: 1).resizable().scaledToFit() }
                    else { Image(systemName: failed ? "exclamationmark.triangle" : "photo").foregroundStyle(.white) }
                }
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    if current {
                        Text("当前").font(.caption).foregroundStyle(.white).padding(6)
                            .background(.black.opacity(0.7), in: Capsule()).padding(6)
                    }
                }
                Text(url.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle)
            }
            .padding(8).wallpaperSurface()
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(current ? WallpaperTheme.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(WallpaperThumbnailButtonStyle())
        .accessibilityLabel("\(current ? "当前壁纸" : "使用壁纸")：\(url.lastPathComponent)")
        .help(url.lastPathComponent)
        .task(id: revision) {
            poster = nil
            failed = false
            let image = await FolderPosterLoader.shared.image(url)
            guard !Task.isCancelled else { return }
            poster = image
            failed = image == nil
        }
    }
}

/// Serial background decoding and a bounded cache avoid thumbnail decode bursts while scrolling.
private actor FolderPosterLoader {
    static let shared = FolderPosterLoader()
    private var cache: [String: CGImage] = [:]
    private var order: [String] = []

    func image(_ url: URL) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let key = "\(url.absoluteString)-\(modified?.timeIntervalSince1970 ?? 0)"
        if let image = cache[key] { return image }
        let image: CGImage?
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 400
            ] as CFDictionary)
        } else {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 400, height: 250)
            image = try? generator.copyCGImage(at: .zero, actualTime: nil)
        }
        if let image, !Task.isCancelled {
            cache[key] = image
            order.append(key)
            if order.count > 80 { cache.removeValue(forKey: order.removeFirst()) }
        }
        return image
    }
}
