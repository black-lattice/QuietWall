import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "leaf.circle.fill")
                    .font(.system(size: 40)).foregroundStyle(.green)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("QuietWall").font(.title2.bold())
                    Text("让桌面动起来，也让电池休息。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            preview
            HStack {
                Label(model.status, systemImage: model.wallpaper?.isVideo == false ? "photo" : (model.isPlaying ? "play.circle" : "pause.circle"))
                    .font(.callout)
                Spacer()
                if model.isLoading { ProgressView().controlSize(.small).accessibilityLabel("正在读取壁纸") }
            }
            HStack {
                Button(model.wallpaper == nil ? "选择图片或视频…" : "更换壁纸…") { model.chooseWallpaper() }
                    .buttonStyle(.borderedProminent).disabled(model.isLoading)
                Button(model.manuallyPaused ? "恢复自动播放" : "手动暂停") { model.togglePause() }
                    .disabled(model.wallpaper?.isVideo != true)
                Spacer()
                if model.wallpaper != nil {
                    Button("移除壁纸") { model.removeWallpaper() }
                        .help("移除当前壁纸，显示原来的系统壁纸；不会删除原文件")
                }
            }
            Form {
                Section("视频省电设置") {
                    Toggle("电池供电时暂停", isOn: $model.pauseOnBattery)
                    Toggle("低电量模式时暂停（插电时也生效）", isOn: $model.pauseOnLowPower)
                    Toggle("桌面大部分被遮挡时暂停", isOn: $model.pauseWhenCovered)
                    Picker("遮挡达到多少时暂停", selection: $model.coverageThreshold) {
                        Text("90% · 更省电").tag(0.90)
                        Text("95% · 推荐").tag(0.95)
                        Text("100% · 完全遮挡").tag(1.0)
                    }
                    .disabled(!model.pauseWhenCovered)
                    Text("这些选项仅影响视频。静态图片无需播放。温度过高、锁屏、休眠或系统开启“减少动态效果”时自动暂停。关闭低电量模式暂停会增加能耗。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("通用") {
                    Toggle("在所有显示器上显示壁纸", isOn: $model.allScreens)
                    Toggle("登录时启动", isOn: Binding(get: { model.loginEnabled }, set: model.setLoginEnabled))
                    if model.loginNeedsApproval {
                        Button("前往系统设置允许开机启动") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if let error = model.errorMessage {
                    Section("需要处理") {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.callout).textSelection(.enabled)
                        Button("忽略此提示") { model.errorMessage = nil }
                    }
                }
            }
            .formStyle(.grouped)
            if let warning = model.wallpaper?.warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text("支持 JPEG、PNG、HEIC 等图片；视频推荐 1080p、24–30 帧 MP4 / MOV，始终静音。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 580, height: 700)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .underPageBackgroundColor))
            if let wallpaper = model.wallpaper {
                Image(decorative: wallpaper.poster, scale: 1)
                    .resizable().scaledToFill()
                    .frame(width: 532, height: 190).clipped()
                VStack {
                    Spacer()
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(wallpaper.url.lastPathComponent).font(.headline).lineLimit(1)
                            Text(wallpaper.details).font(.caption)
                        }
                        Spacer()
                    }
                    .padding(12).foregroundStyle(.white).background(.black.opacity(0.65))
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "mountain.2").font(.system(size: 36)).accessibilityHidden(true)
                    Text("从喜欢的风景开始").font(.headline)
                    Text("选择图片或视频，显示在桌面图标下方。")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.wallpaper.map { "壁纸预览：\($0.url.lastPathComponent)，\($0.details)" } ?? "尚未选择壁纸")
    }
}
