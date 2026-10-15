import Foundation
import UniformTypeIdentifiers

struct WallpaperFolder {
    static func files(in directory: URL) async throws -> [URL] {
        try await Task.detached(priority: .utility) {
            let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
            let files = try FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants])
            return files.filter { url in
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true, values.isSymbolicLink != true,
                      let type = UTType(filenameExtension: url.pathExtension) else { return false }
                return type.conforms(to: .image) || type.conforms(to: .movie)
            }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }.value
    }

    static func ordered(_ files: [URL], after current: URL?) -> [URL] {
        guard let current, let index = files.firstIndex(where: { $0.standardizedFileURL == current.standardizedFileURL }) else {
            return files
        }
        return Array(files.dropFirst(index + 1)) + Array(files.prefix(index + 1))
    }
}
