import AppKit
import Combine

struct DisplayDescriptor: Identifiable {
    let id: String
    let name: String
}

enum DisplayIdentity {
    static func isAsleep(_ screen: NSScreen) -> Bool {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return true }
        return CGDisplayIsAsleep(number.uint32Value) != 0
    }

    static func key(_ screen: NSScreen) -> String {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        guard let id = number?.uint32Value,
              let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else {
            return "display-\(number?.uint32Value ?? 0)"
        }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

@MainActor
final class DisplayManager: ObservableObject {
    let primary = AppModel()
    @Published private(set) var screens: [DisplayDescriptor] = []
    @Published var selectedKey = "shared"
    @Published private(set) var independent: Bool
    private var models: [String: AppModel] = [:]
    private var observer: NSObjectProtocol?
    private let defaults = UserDefaults.standard
    private var primaryKey: String?

    var selected: AppModel { independent ? (models[selectedKey] ?? primary) : primary }
    var selectedName: String { independent ? (screens.first { $0.id == selectedKey }?.name ?? "主显示器") : "统一设置" }

    init() {
        independent = UserDefaults.standard.bool(forKey: "independentDisplays")
        primaryKey = UserDefaults.standard.string(forKey: "primaryDisplayProfile")
        updateScreens()
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                           object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateScreens() }
        }
    }

    func setIndependent(_ enabled: Bool) {
        guard independent != enabled else { return }
        independent = enabled
        defaults.set(enabled, forKey: "independentDisplays")
        if !enabled {
            for model in models.values where model !== primary { model.shutdown() }
            models.removeAll()
            selectedKey = "shared"
            primary.setTargetDisplay(nil)
        }
        updateScreens()
    }

    private func updateScreens() {
        screens = NSScreen.screens.enumerated().map {
            DisplayDescriptor(id: DisplayIdentity.key($0.element), name: "\($0.offset + 1). \($0.element.localizedName)")
        }
        configureCacheProtection(for: primary)
        guard independent else { primary.setTargetDisplay(nil); return }
        if primaryKey == nil {
            primaryKey = screens.first?.id
            defaults.set(primaryKey, forKey: "primaryDisplayProfile")
        }
        guard let primaryKey else { return }
        primary.setTargetDisplay(primaryKey)
        models[primaryKey] = primary
        for screen in screens where models[screen.id] == nil {
            let profile = UserDefaults(suiteName: "com.blacklattice.QuietWall.display.\(screen.id)")!
            if profile.object(forKey: "pauseOnBattery") == nil {
                for key in ["pauseOnBattery", "pauseOnLowPower", "pauseWhenCovered", "coverageThreshold"] {
                    if let value = defaults.object(forKey: key) { profile.set(value, forKey: key) }
                }
            }
            models[screen.id] = AppModel(defaults: profile, displayKey: screen.id)
        }
        var known = Set(defaults.stringArray(forKey: "displayProfileKeys") ?? [])
        known.formUnion(models.keys.filter { $0 != primaryKey })
        defaults.set(Array(known), forKey: "displayProfileKeys")
        for model in models.values {
            configureCacheProtection(for: model)
            model.refresh()
            model.rotation.resume()
            model.automation.resume()
        }
        if !screens.contains(where: { $0.id == selectedKey }) { selectedKey = screens.first?.id ?? primaryKey }
    }

    private func configureCacheProtection(for model: AppModel) {
        model.cacheIsInUse = { [weak self, weak model] url in
            guard let self, let model else { return false }
            if self.models.values.contains(where: { $0 !== model && $0.wallpaper?.url == url }) { return true }
            var profiles: [UserDefaults] = model !== self.primary ? [self.defaults] : []
            let ownKey = self.models.first(where: { $0.value === model })?.key
            for key in self.defaults.stringArray(forKey: "displayProfileKeys") ?? [] where key != ownKey {
                if let profile = UserDefaults(suiteName: "com.blacklattice.QuietWall.display.\(key)") { profiles.append(profile) }
            }
            return profiles.contains { profile in
                guard let data = profile.data(forKey: "wallpaperBookmark") else { return false }
                var stale = false
                return (try? URL(resolvingBookmarkData: data, options: .withoutUI,
                                 relativeTo: nil, bookmarkDataIsStale: &stale)) == url
            }
        }
    }

    func shutdown() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        models.values.filter { $0 !== primary }.forEach { $0.shutdown() }
        primary.shutdown()
    }
}
