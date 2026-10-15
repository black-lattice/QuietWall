import Foundation

enum LocalWallpaper {
    static func url(from address: String) throws -> URL {
        let path = (address.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        let url: URL
        if path.hasPrefix("/") {
            url = URL(fileURLWithPath: path)
        } else if let parsed = URL(string: path), parsed.isFileURL {
            url = parsed
        } else {
            throw LocalWallpaperError.invalidPath
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue, FileManager.default.isReadableFile(atPath: url.path) else {
            throw LocalWallpaperError.unreadable
        }
        return url
    }
}

private enum LocalWallpaperError: LocalizedError {
    case invalidPath, unreadable

    var errorDescription: String? {
        switch self {
        case .invalidPath: return "请选择本地图片或视频文件，也可以将文件拖入导入区域。"
        case .unreadable: return "文件不存在或无法读取，请选择一个有效的图片或视频文件，不要选择文件夹。"
        }
    }
}
