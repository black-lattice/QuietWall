import SwiftUI
import QuietWallCore

struct WallpaperRotationView: View {
    @ObservedObject var rotation: WallpaperRotation
    @State private var customAmount = "5"
    @State private var customUnit: RotationSchedule.Unit = .minute
    @State private var errorMessage: String?
    @State private var periodControlWidth: CGFloat = 96
    @FocusState private var customAmountFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let folder = rotation.folderURL {
                HStack(spacing: 16) {
                    Image(systemName: "folder.badge.gearshape")
                        .foregroundStyle(WallpaperTheme.accent).font(.title2).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("文件夹轮换 · \(folder.lastPathComponent)")
                            .font(.callout.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                        Text(folder.path).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    }
                    .help(folder.path)
                    Spacer(minLength: 0)
                }
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    settingRow("自动轮换") {
                        Toggle("自动轮换", isOn: Binding(get: { rotation.isEnabled }, set: rotation.setEnabled))
                            .toggleStyle(.switch).labelsHidden()
                    }
                    settingRow("轮换周期") {
                        Picker("轮换周期", selection: Binding(get: { rotation.schedule.period }, set: { period in
                            var value = rotation.schedule
                            value.period = period
                            rotation.setSchedule(value)
                            errorMessage = nil
                        })) {
                            ForEach(RotationSchedule.Period.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: RotationControlWidthKey.self, value: geometry.size.width)
                        })
                        .onPreferenceChange(RotationControlWidthKey.self) { width in
                            if width > 0 { periodControlWidth = width }
                        }
                    }
                    if rotation.schedule.period == .custom {
                        settingRow("间隔时长") {
                            HStack(spacing: 8) {
                                TextField("时长", text: $customAmount)
                                    .focused($customAmountFocused)
                                    .textFieldStyle(.roundedBorder).accessibilityLabel("自定义轮换时长")
                                    .onSubmit(applyCustom)
                                    .frame(width: periodControlWidth)
                                Picker("单位", selection: $customUnit) {
                                    ForEach(RotationSchedule.Unit.allCases, id: \.self) { Text($0.title).tag($0) }
                                }
                                .labelsHidden().frame(width: 80)
                                Button("应用", action: applyCustom).fixedSize()
                            }
                        }
                        Text("1–10000，应用后重新计时")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.leading, 84)
                    }
                }
                Divider()
                HStack(spacing: 12) {
                    if rotation.isEnabled, let date = rotation.nextChange {
                        HStack(spacing: 4) {
                            Text("下次：")
                            Text(date, format: .dateTime.month().day().hour().minute())
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("已停止，保留当前壁纸").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if rotation.isRotating {
                        ProgressView().controlSize(.small).accessibilityLabel("正在切换壁纸")
                    }
                    Button("下一张", action: rotation.next)
                        .disabled(!rotation.isEnabled || rotation.isRotating)
                }
            }
            Text("按文件名顺序循环，不含子文件夹。手动选择单张壁纸会停止轮换；锁屏或休眠时延后。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let message = errorMessage ?? rotation.message {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            customAmount = String(rotation.schedule.amount)
            customUnit = rotation.schedule.unit
        }
    }

    private func settingRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.callout).frame(width: 72, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 28)
    }

    private func applyCustom() {
        guard let amount = Int(customAmount), (1...10000).contains(amount) else {
            errorMessage = "请输入 1–10000 的整数时长。"
            customAmountFocused = true
            return
        }
        rotation.setSchedule(RotationSchedule(period: .custom, amount: amount, unit: customUnit))
        errorMessage = nil
        customAmountFocused = false
    }
}

private struct RotationControlWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
