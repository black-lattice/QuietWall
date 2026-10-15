import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var displays: DisplayManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("偏好设置").font(.title2.weight(.semibold))
                Text("管理显示器、播放与自动切换")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    displaySettings
                    playbackSettings
                    startupSettings
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 16) {
                    statusSettings
                    settingsCard("定时切换", symbol: "sun.max") {
                        WallpaperAutomationView(automation: model.automation)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .toggleStyle(.switch)
        .frame(maxWidth: WallpaperTheme.contentWidth)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var displaySettings: some View {
        settingsCard("多屏幕设置", symbol: "display.2") {
            switchRow("为显示器分别设置", isOn: Binding(get: { displays.independent }, set: { enabled in
                displays.setIndependent(enabled)
                displays.selected.settingsPage = .preferences
            }))
            if displays.independent {
                Picker("当前显示器", selection: Binding(get: { displays.selectedKey }, set: { key in
                    displays.selectedKey = key
                    displays.selected.settingsPage = .preferences
                })) {
                    ForEach(displays.screens) { screen in Text(screen.name).tag(screen.id) }
                }
                note("壁纸、轮换和省电选项仅影响所选显示器。")
            } else {
                note("统一设置；可在壁纸库中应用到所有显示器。")
            }
        }
    }

    private var playbackSettings: some View {
        settingsCard("省电与桌面可见性", symbol: "battery.75percent") {
            switchRow("电池供电时暂停", isOn: $model.pauseOnBattery)
                .help("接通电源且其他暂停条件解除后恢复播放。")
            switchRow("低电量模式时暂停", isOn: $model.pauseOnLowPower)
                .help("插电时也生效；关闭此选项允许低电量模式下播放，不更改系统设置。")
            Divider()
            switchRow("桌面被遮挡时暂停", isOn: $model.pauseWhenCovered)
                .help("桌面重新可见且其他暂停条件解除后恢复播放。")
            HStack {
                Text("遮挡阈值")
                Spacer()
                Picker("遮挡阈值", selection: $model.coverageThreshold) {
                    Text("90% · 更省电").tag(0.90)
                    Text("95% · 推荐").tag(0.95)
                    Text("100% · 完全遮挡").tag(1.0)
                }
                .labelsHidden().fixedSize().disabled(!model.pauseWhenCovered)
            }
            note("仅影响视频。高温、锁屏、休眠或减少动态效果时仍会暂停。")
                .help("静态图片不受影响。关闭低电量暂停会增加能耗。")
        }
    }

    private var startupSettings: some View {
        settingsCard("启动", symbol: "power") {
            switchRow("登录时启动 QuietWall", isOn: Binding(get: { model.loginEnabled }, set: model.setLoginEnabled))
            if model.loginNeedsApproval {
                Button("前往系统设置允许开机启动") { SMAppService.openSystemSettingsLoginItems() }
            }
        }
    }

    private var statusSettings: some View {
        settingsCard("当前状态", symbol: "play.circle") {
            PlaybackStatusView(model: model)
            if model.wallpaper?.isVideo == true {
                Button(model.manuallyPaused ? "恢复自动播放" : "手动暂停", action: model.togglePause)
                note("恢复自动播放后仍遵循省电策略。")
            }
        }
    }

    private func settingsCard<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).wallpaperSurface()
    }

    private func switchRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            Toggle(title, isOn: isOn).labelsHidden()
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
