import AppKit

extension AppModel {
    func loadWallpaper(_ url: URL, cachedURL: URL? = nil) {
        loadTask?.cancel()
        let id = UUID()
        loadID = id
        isLoading = true
        errorMessage = nil
        loadTask = Task { [weak self] in
            do {
                let loaded = try await url.isFileURL
                    ? WallpaperAsset.load(url) : RemoteWallpaper.load(url, cachedURL: cachedURL)
                var installed = false
                defer {
                    if !installed && loaded.sourceURL != nil && loaded.url != cachedURL {
                        self?.removeUnusedCache(loaded.url)
                    }
                }
                try Task.checkCancellation()
                guard let self, self.loadID == id else { return }
                try self.applyWallpaper(loaded, cachedURL: cachedURL)
                installed = true
                self.isLoading = false
                self.rotation.resume()
                self.automation.resume()
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.loadID == id else { return }
                self.isLoading = false
                self.errorMessage = error.localizedDescription
                self.refresh()
                self.rotation.resume()
                self.automation.resume()
            }
        }
    }

    func applyWallpaper(_ loaded: WallpaperAsset, cachedURL: URL? = nil) throws {
        let bookmark = try loaded.url.bookmarkData(options: .minimalBookmark,
            includingResourceValuesForKeys: nil, relativeTo: nil)
        let historyUpdate = history.recordForUse(loaded, bookmark: bookmark)
        playbackFailed = false
        let previousURL = wallpaper?.url
        restoringDisplayMode = true
        displayMode = displayPreferences.mode(for: loaded.sourceURL ?? loaded.url) ?? displayMode
        restoringDisplayMode = false
        displayPreferences.set(displayMode, for: loaded.sourceURL ?? loaded.url)
        if library.favorites.entries.contains(where: { $0.matches(loaded) }) {
            _ = library.favorites.recordForUse(loaded, bookmark: bookmark)
        }
        engine.install(loaded, allScreens: allScreens)
        wallpaper = loaded
        if let previousURL { removeUnusedCache(previousURL) }
        if let cachedURL { removeUnusedCache(cachedURL) }
        historyUpdate.discarded.forEach { removeUnusedCache($0.fileURL) }
        defaults.set(loaded.sourceURL?.absoluteString, forKey: "wallpaperRemoteURL")
        defaults.set(bookmark, forKey: "wallpaperBookmark")
        defaults.removeObject(forKey: "videoBookmark")
        errorMessage = historyUpdate.warning
        refresh()
    }

    func restoreWallpaper() {
        if let address = defaults.string(forKey: "wallpaperRemoteURL"),
           let remoteURL = try? RemoteWallpaper.parseURL(address) {
            var stale = false
            let cachedURL = defaults.data(forKey: "wallpaperBookmark").flatMap {
                try? URL(resolvingBookmarkData: $0, options: .withoutUI,
                         relativeTo: nil, bookmarkDataIsStale: &stale)
            }
            loadWallpaper(remoteURL, cachedURL: cachedURL)
            return
        }
        guard let data = defaults.data(forKey: "wallpaperBookmark")
            ?? defaults.data(forKey: "videoBookmark") else { return }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: .withoutUI,
                              relativeTo: nil, bookmarkDataIsStale: &stale)
            loadWallpaper(url)
        } catch {
            errorMessage = "上次的壁纸已移动或无法访问，请重新选择。"
        }
    }

}
