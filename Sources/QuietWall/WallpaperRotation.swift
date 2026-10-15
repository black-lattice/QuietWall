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
    var canRotate: () -> Bool = { true }
    var apply: ((WallpaperAsset) throws -> Void)?

    private struct Saved: Codable {
        var bookmark: Data
        var schedule: RotationSchedule
        var enabled: Bool
        var nextChange: Date?
        var lastFile: URL?
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
            folderURL = try URL(resolvingBookmarkData: saved.bookmark, options: .withoutUI,
                                relativeTo: nil, bookmarkDataIsStale: &stale)
            bookmark = saved.bookmark
            schedule = saved.schedule
            isEnabled = saved.enabled
            nextChange = saved.nextChange
            lastFile = saved.lastFile
        } catch { message = "无法恢复轮换文件夹，请重新选择。" }
    }

    func chooseFolder(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        guard url.isFileURL, values.isDirectory == true else { throw CocoaError(.fileReadUnsupportedScheme) }
        let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        cancelWork()
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
        guard !enabled || folderURL != nil else { return }
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

    func next() {
        guard isEnabled else { return }
        cancelWork()
        nextChange = now()
        persist()
        resume()
    }

    /// A one-shot timer never wakes the machine. System events resume one overdue change.
    func resume() {
        guard isEnabled, folderURL != nil else { return }
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
    }

    private func rotate() {
        guard let folderURL, let apply else { return }
        let id = UUID()
        generation = id
        isRotating = true
        message = nil
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let files = try await scan(folderURL)
                try Task.checkCancellation()
                var succeeded = false
                var skipped = 0
                for file in WallpaperFolder.ordered(files, after: lastFile) {
                    try Task.checkCancellation()
                    do {
                        let asset = try await load(file)
                        try Task.checkCancellation()
                        guard generation == id else { return }
                        guard isEnabled, canRotate() else { cancelWork(); return }
                        try apply(asset)
                        lastFile = file
                        succeeded = true
                        break
                    } catch is CancellationError { throw CancellationError() }
                    catch { skipped += 1 }
                }
                guard generation == id else { return }
                message = succeeded ? (skipped > 0 ? "已跳过 \(skipped) 个无法读取的文件。" : nil)
                    : "文件夹中没有可用图片或视频。请检查文件，或更换文件夹后重试。"
            } catch is CancellationError { return }
            catch {
                guard generation == id else { return }
                message = "无法读取壁纸文件夹，请确认文件夹仍可访问。"
            }
            guard generation == id else { return }
            isRotating = false
            task = nil
            nextChange = schedule.nextDate(after: now())
            persist()
            resume()
        }
    }

    private func persist() {
        guard let bookmark else { return }
        let saved = Saved(bookmark: bookmark, schedule: schedule, enabled: isEnabled,
                          nextChange: nextChange, lastFile: lastFile)
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: "wallpaperRotation") }
    }
}
