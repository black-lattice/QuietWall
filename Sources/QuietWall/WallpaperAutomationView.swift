import SwiftUI
import UniformTypeIdentifiers

struct WallpaperAutomationView: View {
    @ObservedObject var automation: WallpaperAutomation
    @State private var error: String?
    @State private var choosing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("自动切换白天与夜间壁纸", isOn: binding(\.enabled))
                .disabled(!automation.configuration.isReady)
            Picker("切换依据", selection: binding(\.followsAppearance)) {
                Text("指定时间").tag(false)
                Text("系统深浅色").tag(true)
            }
            if !automation.configuration.followsAppearance {
                HStack {
                    DatePicker("白天开始", selection: timeBinding(day: true), displayedComponents: .hourAndMinute)
                    DatePicker("夜间开始", selection: timeBinding(day: false), displayedComponents: .hourAndMinute)
                }
                if !automation.configuration.times.isValid {
                    Text("白天和夜间开始时间不能相同。").font(.caption).foregroundStyle(.red)
                }
            }
            targetRow(day: true)
            targetRow(day: false)
            if let message = error ?? automation.message { Text(message).font(.caption).foregroundStyle(.red) }
            Text("先选择两组来源，再开启自动切换。手动选择壁纸或点击上一张／下一张会关闭此功能；锁屏和休眠时延后。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func binding<Value>(_ key: WritableKeyPath<WallpaperAutomation.Configuration, Value>) -> Binding<Value> {
        Binding(get: { automation.configuration[keyPath: key] }, set: { value in
            var config = automation.configuration
            config[keyPath: key] = value
            automation.update(config)
        })
    }

    private func timeBinding(day: Bool) -> Binding<Date> {
        Binding(get: {
            let value = day ? automation.configuration.times.dayMinute : automation.configuration.times.nightMinute
            return Calendar.current.date(bySettingHour: value / 60, minute: value % 60, second: 0, of: Date()) ?? Date()
        }, set: { date in
            var config = automation.configuration
            let value = Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
            if day { config.times.dayMinute = value } else { config.times.nightMinute = value }
            automation.update(config)
        })
    }

    private func targetRow(day: Bool) -> some View {
        let target = day ? automation.configuration.day : automation.configuration.night
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(day ? "白天 / 浅色" : "夜间 / 深色").font(.callout.weight(.medium))
                Text(target.map { "\($0.isFolder ? "文件夹" : "壁纸") · \($0.name)" } ?? "尚未选择")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button("图片或视频") { choose(day: day, folder: false) }.disabled(choosing)
            Button("文件夹") { choose(day: day, folder: true) }.disabled(choosing)
        }
    }

    private func choose(day: Bool, folder: Bool) {
        guard !choosing else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = folder
        panel.canChooseFiles = !folder
        panel.allowsMultipleSelection = false
        if !folder { panel.allowedContentTypes = [.image, .movie] }
        choosing = true
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            choosing = false
            guard response == .OK, let url = panel.url else { return }
            do {
                let target = try ScheduledWallpaper(url: url, isFolder: folder)
                var config = automation.configuration
                if day { config.day = target } else { config.night = target }
                automation.update(config)
                error = nil
            } catch { self.error = "无法保存来源：\(error.localizedDescription)" }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
}
