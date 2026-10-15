import SwiftUI
import UniformTypeIdentifiers

enum WallpaperSource: String, CaseIterable, Identifiable {
    case local, remote, folder
    var id: String { rawValue }
    var title: String {
        switch self {
        case .local: return "本地文件"
        case .remote: return "网络地址"
        case .folder: return "文件夹轮换"
        }
    }
}

struct WallpaperImportView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var rotation: WallpaperRotation
    @ObservedObject private var library = WallpaperLibrary.shared
    @State private var isChoosingFile = false
    @State private var isChoosingFolder = false
    @State private var remoteAddress = ""
    @State private var errorMessage: String?
    @State private var isDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("选择壁纸来源").font(.headline)
            Picker("壁纸方式", selection: Binding(get: { model.wallpaperSource }, set: { source in
                errorMessage = nil
                model.wallpaperSource = source
            })) {
                ForEach(WallpaperSource.allCases) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.segmented).labelsHidden().controlSize(.large)
            Divider()
            switch model.wallpaperSource {
            case .local:
                localContent
            case .remote:
                RemoteWallpaperView(model: model, address: $remoteAddress)
            case .folder:
                folderContent
            }
            if let message = errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20).wallpaperSurface()
        .background(isDropTarget ? WallpaperTheme.accent.opacity(0.06) : .clear,
                    in: RoundedRectangle(cornerRadius: WallpaperTheme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: WallpaperTheme.cornerRadius)
            .strokeBorder(isDropTarget ? WallpaperTheme.accent : Color.clear,
                          style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTarget, perform: receiveDrop)
    }

    private var localContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 32)).foregroundStyle(WallpaperTheme.accent)
                .accessibilityHidden(true)
            Text(isDropTarget ? "松开即可使用壁纸" : "将图片或视频拖到这里")
                .font(.callout.weight(.medium))
            localFileButton.buttonStyle(.borderedProminent).controlSize(.large)
            Text("自动识别图片和视频，本地文件保留在原位置。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity).padding(.vertical, 24)
    }

    private var folderContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(action: chooseFolder) {
                Label(rotation.folderURL == nil ? "选择文件夹…" : "更换文件夹…",
                      systemImage: "folder.badge.gearshape")
            }
            .buttonStyle(.borderedProminent).controlSize(.large).disabled(isChoosingFolder)
            .help("选择文件夹后，按设定周期自动轮换其中的图片和视频")
            Button("轮换收藏壁纸") {
                model.automation.disableForManualSelection()
                rotation.chooseFavorites()
            }
                .disabled(library.favorites.entries.isEmpty)
            if !rotation.hasSource {
                Text("选择一个存放图片或视频的文件夹，自动轮换其中的壁纸。")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            WallpaperRotationView(rotation: rotation)
        }
    }

    private var localFileButton: some View {
        Button(action: chooseLocalFile) {
            Label("图片或视频…", systemImage: "photo.on.rectangle")
        }
        .disabled(model.isLoading || isChoosingFile)
        .accessibilityLabel("选择本地图片或视频")
    }

    private func chooseFolder() {
        guard !isChoosingFolder else { return }
        let panel = NSOpenPanel()
        panel.title = "选择壁纸文件夹"
        panel.prompt = "开始轮换"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        isChoosingFolder = true
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            isChoosingFolder = false
            guard response == .OK, let url = panel.url else { return }
            do {
                model.automation.disableForManualSelection()
                try rotation.chooseFolder(url)
                errorMessage = nil
            } catch { errorMessage = "无法使用这个文件夹，请检查访问权限。" }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
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
