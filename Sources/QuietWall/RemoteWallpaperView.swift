import SwiftUI

struct RemoteWallpaperView: View {
    @ObservedObject var model: AppModel
    @Binding var address: String
    @State private var errorMessage: String?
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("从网络添加", systemImage: "link").font(.callout.weight(.medium))
            VStack(alignment: .leading, spacing: 12) {
                TextField("https://… 图片或视频直链", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .focused($addressFocused)
                    .onSubmit(importWallpaper)
                    .onChange(of: address) { _ in errorMessage = nil }
                    .accessibilityLabel("壁纸网络地址")
                Button("下载并使用", action: importWallpaper)
                    .buttonStyle(.borderedProminent)
                    .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isLoading)
            }
            Text("输入图片或视频直链，自动识别类型；不支持网页或直播地址。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear { addressFocused = true }
    }

    private func importWallpaper() {
        guard !model.isLoading else { return }
        do {
            try model.loadRemoteWallpaper(address)
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}
