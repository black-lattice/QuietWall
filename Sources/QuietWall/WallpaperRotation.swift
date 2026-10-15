import AppKit
import Combine
import QuietWallCore

@MainActor
final class WallpaperRotation: ObservableObject {
    @Published private(set) var folderURL: URL?
    @Published private(set) var schedule = RotationSchedule()
    @Published private(set) var isEnabled = false
    @Published private(set) var isRotating = false
    @Published private(set) var nextChange: Date?
    @Published private(set) var message: String?
    @Published private(set) var randomOrder = false
    @Published private(set) var usesFavorites = false
    var favoriteEntries: () -> [WallpaperHistoryEntry] = { [] }
    var manualSelection: (() -> Void)?
    var canRotate: () -> Bool = { true }
    var apply: ((WallpaperAsset) throws -> Void)?

    private struct Saved: Codable {
        var bookmark: Data?
        var schedule: RotationSchedule
        var enabled: Bool
        var nextChange: Date?
        var lastFile: URL?
        var randomOrder: Bool?
        var usesFavorites: Bool?
        var sequence: RotationSequence?
    }
    private let defaults: UserDefaults
    private let now: () -> Date
    private let scan: (URL) async throws -> [URL]
    private let load: (URL) async throws -> WallpaperAsset
    private var bookmark: Data?
    private var lastFile: URL?
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var sequence = RotationSequence()
    private var requestedFile: URL?
    private var backwards = false
    private var manualStep = false
    var hasSource: Bool { folderURL != nil || usesFavorites }

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
         scan: @escaping (URL) async throws -> [URL] = WallpaperFolder.files,
         load: @escaping (URL) async throws -> WallpaperAsset = WallpaperAsset.load) {
        self.defaults = defaults
        self.now = now
        self.scan = scan
        self.load = load
        guard let data = defaults.data(forKey: "wallpaperRotation") else { return }
        do {
            let saved = try JSONDecoder().decode(Saved.self, from: data)
            guard saved.schedule.isValid else { throw CocoaError(.coderReadCorrupt) }
            var stale = false
            if let data = saved.bookmark {
                folderURL = try URL(resolvingBookmarkData: data, options: .withoutUI,
                                    relativeTo: nil, bookmarkDataIsStale: &stale)
            }
            bookmark = saved.bookmark
            schedule = saved.schedule
            isEnabled = saved.enabled
            nextChange = saved.nextChange
            lastFile = saved.lastFile
            randomOrder = saved.randomOrder ?? false
            usesFavorites = saved.usesFavorites ?? false
            sequence = saved.sequence ?? RotationSequence()
        } catch { message = "无法恢复轮换文件夹，请重新选择。" }
    }

    func chooseFolder(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        guard url.isFileURL, values.isDirectory == true else { throw CocoaError(.fileReadUnsupportedScheme) }
        let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        cancelWork()
        usesFavorites = false
        sequence = RotationSequence()
        folderURL = url
        bookmark = data
        lastFile = nil
        message = nil
        isEnabled = true
        nextChange = now()
        persist()
        resume()
    }

    func setEnabled(_ enabled: Bool) {
        guard !enabled || hasSource else { return }
        cancelWork()
        isEnabled = enabled
        if enabled { nextChange = now() }
        persist()
        resume()
    }

    func setSchedule(_ value: RotationSchedule) {
        guard value.isValid else { return }
        cancelWork()
        schedule = value
        if isEnabled { nextChange = value.nextDate(after: now()) }
        persist()
        resume()
    }

    func setRandomOrder(_ value: Bool) {
        randomOrder = value
        sequence.remaining.removeAll()
        persist()
    }

    func chooseFavorites() {
        cancelWork()
        usesFavorites = true
        sequence = RotationSequence()
        lastFile = nil
        isEnabled = true
        nextChange = now()
        persist()
        resume()
    }

    func next() { step() }
    func previous() { step(backwards: true) }
    func select(_ url: URL) { step(file: url) }

    private func step(file: URL? = nil, backwards: Bool = false) {
        guard hasSource else { return }
        manualSelection?()
        cancelWork()
        requestedFile = file.map { $0.isFileURL ? $0.resolvingSymlinksInPath() : $0 }
        self.backwards = backwards
        manualStep = true
        nextChange = now()
        persist()
        resume()
    }

    /// A one-shot timer never wakes the machine. System events resume one overdue change.
    func resume() {
        guard (isEnabled || manualStep), hasSource else { return }
        guard canRotate() else { cancelWork(); return }
        guard !isRotating else { return }
        timer?.invalidate()
        let deadline = nextChange ?? now()
        if deadline <= now() { rotate(); return }
        let timer = Timer(fire: deadline, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.resume() }
        }
        timer.tolerance = min(30, max(1, deadline.timeIntervalSince(now()) * 0.02))
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func shutdown() { cancelWork() }

    private func cancelWork() {
        generation = UUID()
        task?.cancel()
        task = nil
        timer?.invalidate()
        timer = nil
        isRotating = false
        manualStep = false
        requestedFile = nil
        backwards = false
    }

    private func rotate() {
        guard let apply else { return }
        let requestedFile = self.requestedFile
        let backwards = self.backwards
        let manualStep = self.manualStep
        let id = UUID()
        generation = id
        isRotating = true
        message = nil
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let favorites = usesFavorites ? favoriteEntries() : []
                var files: [URL]
                if usesFavorites {
                    files = favorites.map { $0.sourceURL ?? ((try? $0.resolvedFileURL()) ?? $0.fileURL) }
                } else if let folderURL { files = try await scan(folderURL) }
                else { files = [] }
                files = files.map { $0.isFileURL ? $0.resolvingSymlinksInPath() : $0 }
                if let current = lastFile, current.isFileURL { lastFile = current.resolvingSymlinksInPath() }
                try Task.checkCancellation()
                var succeeded = false
                var skipped = 0
                var candidates = sequence.candidates(files, current: lastFile, random: randomOrder)
                if let selected = requestedFile ?? (backwards ? sequence.previous(in: files, current: lastFile) : nil) {
                    candidates = files.contains(selected) ? [selected] : []
                }
                let attempts = randomOrder && requestedFile == nil && !backwards ? 2 : 1
                for attempt in 0..<attempts {
                    if attempt > 0 { candidates = sequence.candidates(files, current: lastFile, random: true) }
                    for file in candidates {
                        try Task.checkCancellation()
                        do {
                            let asset: WallpaperAsset
                            if let entry = favorites.first(where: { $0.sourceURL == file }), !file.isFileURL {
                                asset = try await RemoteWallpaper.load(file, cachedURL: try? entry.resolvedFileURL())
                            } else { asset = try await load(file) }
                            try Task.checkCancellation()
                            guard generation == id else { return }
                            guard (isEnabled || manualStep), canRotate() else { cancelWork(); return }
                            try apply(asset)
                            sequence.used(file, previous: lastFile, backwards: backwards)
                            lastFile = file
                            succeeded = true
                            break
                        } catch is CancellationError { throw CancellationError() }
                        catch {
                            try Task.checkCancellation()
                            guard generation == id else { return }
                            sequence.remaining.removeAll { $0 == file }
                            skipped += 1
                        }
                    }
                    if succeeded { break }
                }
                guard generation == id else { return }
                message = succeeded ? (skipped > 0 ? "已跳过 \(skipped) 个无法读取的文件。" : nil)
                    : "当前轮换来源没有可用图片或视频，请检查文件或重新选择来源。"
            } catch is CancellationError { return }
            catch {
                guard generation == id else { return }
                message = "无法读取壁纸文件夹，请确认文件夹仍可访问。"
            }
            guard generation == id else { return }
            isRotating = false
            self.manualStep = false
            self.requestedFile = nil
            self.backwards = false
            task = nil
            nextChange = schedule.nextDate(after: now())
            persist()
            resume()
        }
    }

    private func persist() {
        let saved = Saved(bookmark: bookmark, schedule: schedule, enabled: isEnabled,
                          nextChange: nextChange, lastFile: lastFile, randomOrder: randomOrder,
                          usesFavorites: usesFavorites, sequence: sequence)
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: "wallpaperRotation") }
    }
}
