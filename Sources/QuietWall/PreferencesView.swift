import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                Text("偏好设置").font(.title2.weight(.semibold))
                Text("自动管理播放，在需要时节省电量。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).padding(.top, 32)
            Form {
                Section {
                    PlaybackStatusView(model: model)
                    if model.wallpaper?.isVideo == true {
                        Button(model.manuallyPaused ? "恢复自动播放" : "手动暂停", action: model.togglePause)
                    }
                } header: {
                    Label("当前状态", systemImage: "play.circle")
                } footer: {
                    Text("恢复自动播放仍遵循下方省电策略及系统暂停条件。")
                }
                Section {
                    Toggle(isOn: $model.pauseOnBattery) {
                        settingLabel("电池供电时暂停", detail: "接通电源且其他暂停条件解除后恢复播放。")
                    }
                    Toggle(isOn: $model.pauseOnLowPower) {
                        settingLabel("低电量模式时暂停", detail: "插电时也生效；关闭此选项允许低电量模式下播放，不更改系统设置。")
                    }
                } header: {
                    Label("省电策略", systemImage: "battery.75percent")
                } footer: {
                    Text("仅影响视频，静态图片不受影响。关闭低电量暂停会增加能耗；温度过高、锁屏、休眠或启用减少动态效果时仍会暂停。")
                }
                Section {
                    Toggle(isOn: $model.pauseWhenCovered) {
                        settingLabel("桌面被遮挡时暂停", detail: "桌面重新可见且其他暂停条件解除后恢复播放。")
                    }
                    Picker("遮挡阈值", selection: $model.coverageThreshold) {
                        Text("90% · 更省电").tag(0.90)
                        Text("95% · 推荐").tag(0.95)
                        Text("100% · 完全遮挡").tag(1.0)
                    }
                    .disabled(!model.pauseWhenCovered)
                } header: {
                    Label("桌面可见性", systemImage: "macwindow.on.rectangle")
                }
                Section {
                    WallpaperAutomationView(automation: model.automation)
                } header: {
                    Label("定时切换", systemImage: "sun.max")
                }
                Section {
                    Toggle("登录时启动 QuietWall", isOn: Binding(get: { model.loginEnabled }, set: model.setLoginEnabled))
                    if model.loginNeedsApproval {
                        Button("前往系统设置允许开机启动") { SMAppService.openSystemSettingsLoginItems() }
                    }
                } header: {
                    Label("启动", systemImage: "power")
                }
            }
            .formStyle(.grouped).toggleStyle(.switch)
        }
        .frame(maxWidth: 720).frame(maxWidth: .infinity)
    }

    private func settingLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
