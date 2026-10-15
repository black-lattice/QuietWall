import SwiftUI

struct WallpaperCollectionView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var library = WallpaperLibrary.shared
    @State private var favoritesOnly = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("壁纸集合", selection: $favoritesOnly) {
                Text("最近使用").tag(false)
                Text("我的收藏").tag(true)
            }.pickerStyle(.segmented).frame(width: 240)
            if favoritesOnly {
                HStack {
                    Button("轮换收藏壁纸") {
                        model.automation.disableForManualSelection()
                        model.rotation.chooseFavorites()
                    }.disabled(library.favorites.entries.isEmpty)
                    Button("轮换设置") {
                        model.wallpaperSource = .folder
                        model.settingsPage = .sources
                    }
                }
                WallpaperHistoryView(model: model, history: model.library.favorites, favoritesOnly: true)
            } else { WallpaperHistoryView(model: model, history: model.history) }
        }
    }
}

struct FolderSourceGrid: View {
    @ObservedObject var model: AppModel
    @ObservedObject var rotation: WallpaperRotation
    var body: some View {
        if rotation.usesFavorites {
            WallpaperHistoryView(model: model, history: model.library.favorites, favoritesOnly: true)
        } else if rotation.folderURL != nil {
            WallpaperFolderGrid(model: model, rotation: rotation)
        }
    }
}

struct RotationMenu: View {
    @ObservedObject var rotation: WallpaperRotation
    var body: some View {
        if rotation.hasSource {
            Divider()
            Text(rotation.isEnabled ? "自动轮换中" : "自动轮换已暂停")
            Button("上一张", action: rotation.previous).disabled(rotation.isRotating)
            Button("下一张", action: rotation.next).disabled(rotation.isRotating)
            Button(rotation.isEnabled ? "暂停轮换" : "恢复轮换") { rotation.setEnabled(!rotation.isEnabled) }
        }
    }
}
