import SwiftUI

struct PlaybackStatusView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(model.status, systemImage: model.wallpaper?.isVideo == false ? "photo" : (model.isPlaying ? "play.circle" : "pause.circle"))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.pausedForLowPower {
                Button("允许低电量模式下播放") { model.pauseOnLowPower = false }
                    .help("关闭 QuietWall 的低电量暂停选项；仍遵循其他暂停条件，不修改系统低电量模式")
            }
            if model.isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).accessibilityLabel("正在读取壁纸")
                    Text("正在读取壁纸…").font(.caption)
                    Spacer()
                    Button("取消", action: model.cancelLoading).controlSize(.small)
                }
            }
        }
    }
}
