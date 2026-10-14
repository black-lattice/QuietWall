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
                    Text("静境壁纸").font(.title2.bold())
                    Text("让桌面动起来，也让电池休息。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            preview
            HStack {
                Label(model.status, systemImage: model.isPlaying ? "play.circle" : "pause.circle")
                    .font(.callout)
                Spacer()
                if model.isLoading { ProgressView().controlSize(.small).accessibilityLabel("正在读取视频") }
            }
            HStack {
                Button(model.video == nil ? "选择本地视频…" : "更换视频…") { model.chooseVideo() }
                    .buttonStyle(.borderedProminent).disabled(model.isLoading)
                Button(model.manuallyPaused ? "恢复自动播放" : "手动暂停") { model.togglePause() }
                    .disabled(model.video == nil)
                Spacer()
                if model.video != nil {
                    Button("移除壁纸") { model.removeVideo() }
                        .help("停止动态壁纸，显示原来的系统壁纸；不会删除视频文件")
                }
            }
            Form {
                Section("省电设置") {
                    Toggle("电池供电时暂停", isOn: $model.pauseOnBattery)
                    Toggle("桌面完全被遮挡时暂停", isOn: $model.pauseWhenCovered)
                    Toggle("所有显示器都播放", isOn: $model.allScreens)
                    Text("默认只使用主显示器。低电量模式、温度过高、锁屏、休眠或系统开启“减少动态效果”时自动暂停。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("通用") {
                    Toggle("登录时启动", isOn: Binding(get: { model.loginEnabled }, set: model.setLoginEnabled))
                    if model.loginNeedsApproval {
                        Button("前往系统设置允许开机启动") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
            }
            .formStyle(.grouped)
            if let warning = model.video?.warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text("推荐本地 1080p、24–30 帧 MP4 / MOV。视频始终静音，不自动压缩或转码。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 580, height: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("暂时无法完成操作", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("知道了") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .underPageBackgroundColor))
            if let video = model.video {
                Image(decorative: video.poster, scale: 1)
                    .resizable().scaledToFill()
                    .frame(width: 532, height: 190).clipped()
                VStack {
                    Spacer()
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(video.url.lastPathComponent).font(.headline).lineLimit(1)
                            Text(video.details).font(.caption)
                        }
                        Spacer()
                    }
                    .padding(12).foregroundStyle(.white).background(.black.opacity(0.65))
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "mountain.2").font(.system(size: 36)).accessibilityHidden(true)
                    Text("从一段喜欢的风景开始").font(.headline)
                    Text("选择视频后，它会出现在桌面图标下方。")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.video.map { "壁纸预览：\($0.url.lastPathComponent)，\($0.details)" } ?? "尚未选择壁纸")
    }
}
