import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case wallpapers, preferences
    var id: String { rawValue }
    var title: String { self == .wallpapers ? "壁纸库" : "偏好设置" }
    var symbol: String { self == .wallpapers ? "square.grid.2x2" : "slider.horizontal.3" }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("页面", selection: $model.settingsPage) {
                ForEach(SettingsPage.allCases) { page in
                    Label(page.title, systemImage: page.symbol).tag(page)
                }
            }
            .pickerStyle(.segmented).labelsHidden().controlSize(.large)
            .frame(width: 280)
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
            if model.settingsPage == .wallpapers {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        WallpaperImportView(model: model)
                        CurrentWallpaperView(model: model)
                        WallpaperHistoryView(model: model, history: model.history)
                    }
                    .frame(maxWidth: WallpaperTheme.contentWidth)
                    .padding(24).frame(maxWidth: .infinity)
                }
            } else {
                PreferencesView(model: model)
            }
        }
        .tint(WallpaperTheme.accent)
        .frame(minWidth: 900, minHeight: 680)
        .background(WallpaperTheme.background)
    }
}
