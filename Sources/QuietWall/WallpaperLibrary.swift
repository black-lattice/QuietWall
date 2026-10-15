import AppKit
import Combine

@MainActor
final class WallpaperLibrary: ObservableObject {
    static let shared = WallpaperLibrary()
    let favorites: WallpaperHistory
    private var subscription: AnyCancellable?

    init(directory: URL = RemoteWallpaper.cacheDirectory.deletingLastPathComponent()) {
        favorites = WallpaperHistory(directory: directory, filename: "wallpaper-favorites.json", maximumCount: .max)
        subscription = favorites.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    func contains(_ entry: WallpaperHistoryEntry) -> Bool {
        favorites.entries.contains { same($0, entry) }
    }

    func toggle(_ entry: WallpaperHistoryEntry) throws {
        if let existing = favorites.entries.first(where: { same($0, entry) }) { try favorites.remove(existing) }
        else { try favorites.add(entry) }
    }

    private func same(_ lhs: WallpaperHistoryEntry, _ rhs: WallpaperHistoryEntry) -> Bool {
        if lhs.sourceURL != nil || rhs.sourceURL != nil { return lhs.sourceURL == rhs.sourceURL }
        return lhs.fileURL.standardizedFileURL == rhs.fileURL.standardizedFileURL
    }
}

final class WallpaperDisplayPreferences {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func mode(for url: URL) -> WallpaperDisplayMode? {
        (defaults.dictionary(forKey: "wallpaperDisplayModes")?[key(url)] as? String)
            .flatMap(WallpaperDisplayMode.init(rawValue:))
    }

    func set(_ mode: WallpaperDisplayMode, for url: URL) {
        var values = defaults.dictionary(forKey: "wallpaperDisplayModes") ?? [:]
        values[key(url)] = mode.rawValue
        defaults.set(values, forKey: "wallpaperDisplayModes")
    }

    private func key(_ url: URL) -> String {
        url.isFileURL ? url.standardizedFileURL.absoluteString : url.absoluteString
    }
}
