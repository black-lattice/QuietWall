import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case wallpapers, sources, preferences
    var id: String { rawValue }
    var title: String {
        switch self {
        case .wallpapers: return "壁纸库"
        case .sources: return "壁纸来源"
        case .preferences: return "偏好设置"
        }
    }
    var symbol: String {
        switch self {
        case .wallpapers: return "square.grid.2x2"
        case .sources: return "photo.badge.plus"
        case .preferences: return "slider.horizontal.3"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var displays: DisplayManager

    var body: some View {
        VStack(spacing: 0) {
            Picker("页面", selection: $model.settingsPage) {
                ForEach(SettingsPage.allCases) { page in
                    Label(page.title, systemImage: page.symbol).tag(page)
                }
            }
            .pickerStyle(.segmented).labelsHidden().controlSize(.large)
            .frame(width: 390)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 16)).foregroundStyle(WallpaperTheme.accent)
                    .frame(width: 32, height: 32)
                    .background(WallpaperTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .background(WallpaperTheme.surface)
            Divider()
            if let error = model.errorMessage {
                HStack(alignment: .top, spacing: 12) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("忽略") { model.errorMessage = nil }
                }
                .padding(12).background(Color.orange.opacity(0.08))
            }
            switch model.settingsPage {
            case .wallpapers, .sources:
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if model.settingsPage == .sources {
                            HStack(alignment: .top, spacing: 24) {
                                WallpaperSourcePreviewView(model: model)
                                    .frame(maxWidth: .infinity)
                                WallpaperImportView(model: model, rotation: model.rotation)
                                    .frame(width: 400)
                            }
                            if model.wallpaperSource == .folder {
                                FolderSourceGrid(model: model, rotation: model.rotation)
                            }
                        } else {
                            CurrentWallpaperView(model: model)
                            WallpaperCollectionView(model: model)
                        }
                    }
                    .frame(maxWidth: WallpaperTheme.contentWidth)
                    .padding(24).frame(maxWidth: .infinity)
                }
            case .preferences:
                PreferencesView(model: model, displays: displays)
            }
        }
        .tint(WallpaperTheme.accent)
        .frame(minWidth: 900, minHeight: 680)
        .background(WallpaperTheme.background)
    }
}
