import SwiftUI

struct DisplayWorkspaceView: View {
    @ObservedObject var displays: DisplayManager
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Label("显示器", systemImage: "display.2").font(.callout.weight(.medium))
                Toggle("分别设置", isOn: Binding(get: { displays.independent }, set: displays.setIndependent))
                    .toggleStyle(.switch)
                if displays.independent {
                    Picker("当前显示器", selection: $displays.selectedKey) {
                        ForEach(displays.screens) { screen in Text(screen.name).tag(screen.id) }
                    }.labelsHidden().frame(maxWidth: 300)
                }
                Spacer()
                Text(displays.independent ? "壁纸、轮换与省电选项仅影响所选屏幕" : "可在壁纸库中选择应用到所有显示器")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            Divider()
            SettingsView(model: displays.selected).id(displays.independent ? displays.selectedKey : "shared")
        }
    }
}

struct DisplayMenu: View {
    @ObservedObject var displays: DisplayManager
    let showSettings: () -> Void
    var body: some View {
        if displays.independent {
            Picker("控制显示器", selection: $displays.selectedKey) {
                ForEach(displays.screens) { screen in Text(screen.name).tag(screen.id) }
            }
            Divider()
        }
        WallpaperMenu(model: displays.selected, showSettings: showSettings)
    }
}

struct DisplayMenuIcon: View {
    @ObservedObject var displays: DisplayManager
    var body: some View { WallpaperMenuIcon(model: displays.selected) }
}
