import SwiftUI
import UniformTypeIdentifiers

enum WallpaperSource: String, CaseIterable, Identifiable {
    case local, remote
    var id: String { rawValue }
    var title: String { self == .local ? "本地文件" : "网络地址" }
}

struct WallpaperImportView: View {
    @ObservedObject var model: AppModel
    @State private var isChoosingFile = false
    @State private var remoteAddress = ""
    @State private var errorMessage: String?
    @State private var isDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("添加壁纸").font(.headline)
                    Text(isDropTarget ? "松开即可使用这张壁纸" : "选择图片或视频，也可以直接拖入这里")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 16)
                HStack(spacing: 12) {
                    Button {
                        model.wallpaperSource = model.wallpaperSource == .remote ? .local : .remote
                    } label: {
                        Label(model.wallpaperSource == .remote ? "收起网络地址" : "网络地址",
                              systemImage: model.wallpaperSource == .remote ? "chevron.up" : "link")
                    }
                    .buttonStyle(.bordered)
                    if model.wallpaperSource == .local {
                        localFileButton.buttonStyle(.borderedProminent)
                    } else {
                        localFileButton.buttonStyle(.bordered)
                    }
                }
                .controlSize(.large).fixedSize()
            }
            if model.wallpaperSource == .remote {
                RemoteWallpaperView(model: model, address: $remoteAddress)
                    .padding(16).wallpaperSurface()
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 4).padding(.vertical, 8)
        .background(isDropTarget ? WallpaperTheme.accent.opacity(0.06) : .clear,
                    in: RoundedRectangle(cornerRadius: WallpaperTheme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: WallpaperTheme.cornerRadius)
            .strokeBorder(isDropTarget ? WallpaperTheme.accent : Color.clear,
                          style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTarget, perform: receiveDrop)
    }

    private var localFileButton: some View {
        Button(action: chooseLocalFile) {
            Label("选择图片或视频…", systemImage: "folder")
        }
        .disabled(model.isLoading || isChoosingFile)
    }

    private func chooseLocalFile() {
        guard !model.isLoading, !isChoosingFile else { return }
        let panel = NSOpenPanel()
        panel.title = "选择壁纸"
        panel.prompt = "使用壁纸"
        panel.allowedContentTypes = [.image, .movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        isChoosingFile = true
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            isChoosingFile = false
            guard response == .OK, let url = panel.url else { return }
            importLocal(url)
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    private func importLocal(_ url: URL) {
        guard !model.isLoading else { return }
        do {
            try model.loadLocalWallpaper(url.path)
            model.wallpaperSource = .local
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func receiveDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !model.isLoading, !providers.isEmpty else { return false }
        model.wallpaperSource = .local
        guard providers.count == 1 else {
            errorMessage = "请一次拖入一个图片或视频文件。"
            return false
        }
        providers[0].loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
            Task { @MainActor in
                guard let url, url.isFileURL else {
                    errorMessage = "无法读取拖入的文件，请点击“选择图片或视频”重新选择。"
                    return
                }
                importLocal(url)
            }
        }
        return true
    }
}
