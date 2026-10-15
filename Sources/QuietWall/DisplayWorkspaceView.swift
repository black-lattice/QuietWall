import SwiftUI

struct DisplayWorkspaceView: View {
    @ObservedObject var displays: DisplayManager
    var body: some View {
        SettingsView(model: displays.selected, displays: displays)
            .id(displays.independent ? displays.selectedKey : "shared")
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
